---
name: synology-dsm-upgrade
description:
  Use when applying a DSM update to the Synology fs2, or when the user asks to
  upgrade, patch or reboot fs2. Quiesces iSCSI workloads, k1 and batch jobs,
  drives the DSM update from the command line, and restores everything.
---

<!-- Steps are numbered across phases so they can be referenced by number. -->
<!-- markdownlint-disable MD029 -->

# Synology DSM Upgrade (fs2)

Every DSM update reboots fs2, including "Update N" patches. The reboot takes
10–20 minutes. Kubernetes iSCSI volumes go read-only if fs2 is gone for more
than 120 seconds, and the pods keep running on the read-only mount. NFS clients
mounted `hard` block and resume. This procedure removes every iSCSI user before
the reboot and shuts down k1, whose disk is a qcow2 on fs2's `proxmox-ssd` NFS
export.

## Operating rules

- Run one step at a time and check its output against the stated expectation. On
  anything unexpected, stop and report it to the user with the output. Do not
  improvise a workaround, retry with different options, or skip a check.
- Get an explicit go-ahead from the user at the two gates marked **GATE**.
  Invoking this skill authorizes the `ssh` commands written here, nothing else.
- Run `kubectl` and repo scripts from the repo root in the dev shell.
- SSH to fs2 as `root@fs2`. Synology tools are not on root's PATH over SSH; use
  the full paths below.
- Keep run state in `.tmp/dsm-upgrade/` at the repo top (ignored by git).

## Phase 1: Preflight (no disruption)

1. Current version, uptime and update offer:

   ```bash
   ssh root@fs2 'grep -E "^(productversion|buildnumber|smallfixnumber)=" /etc.defaults/VERSION; uptime; /usr/syno/sbin/synoupgrade --check'
   ```

   `Result:` JSON with `"available":true` names the target `version`. Note
   `reboot` (expect `"now"`). If nothing is available, stop.

2. Update settings must be notify-only, so DSM never installs and reboots by
   itself:

   ```bash
   ssh root@fs2 '/usr/syno/bin/synowebapi --exec api=SYNO.Core.Upgrade.Setting method=get version=4 2>/dev/null'
   ```

   Expect `"autoupdate_type" : "notify"`.

3. Release notes for the target version. Summarize for the user anything about
   required manual package updates, removed features, iSCSI, NFS or SAN Manager,
   and whether it is a major/minor release (no downgrade):

   ```bash
   mkdir -p .tmp/dsm-upgrade
   model=$(ssh root@fs2 cat /proc/sys/kernel/syno_hw_version)
   curl -sG 'https://www.synology.com/api/releaseNote/findChangeLog' \
     --data-urlencode identify=DSM --data-urlencode "model=$model" \
     --data-urlencode lang=en-global -o .tmp/dsm-upgrade/release-notes.json
   ```

4. Storage health:

   ```bash
   ssh root@fs2 'cat /proc/mdstat; ls /sys/block | grep -cE "^sd[a-z]+$"'
   ```

   Data arrays (`md2` and up) show no `_`. `md0` and `md1` span every bay, so
   they show a `_` per empty bay; their active member count must equal the
   number of installed disks (the last line). Any `recovery`, `resync` or
   `check` means stop.

5. SAN Manager running, and no upgrade in progress:

   ```bash
   ssh root@fs2 '/usr/syno/bin/synopkg status ScsiTarget; /usr/syno/bin/synowebapi --exec api=SYNO.Core.Upgrade method=status version=1 2>/dev/null'
   ```

   Expect `"status":"running"` for ScsiTarget and `"status" : "none"` for the
   upgrade.

6. Download the update and wait for it. This only downloads:

   ```bash
   ssh root@fs2 '/usr/syno/bin/synowebapi --exec api=SYNO.Core.Upgrade.Server.Download method=start version=2 target="\"update\"" need_auto_smallupdate=true 2>/dev/null'
   ssh root@fs2 '/usr/syno/bin/synowebapi --exec api=SYNO.Core.Upgrade.Server.Download method=progress version=2 need_download_target=true 2>/dev/null'
   ```

   Poll `progress` every 30 seconds until its status reports the download is
   finished. Stop on `failed` or `stopped`.

7. Pre-upgrade checks, as the DSM UI runs them:

   ```bash
   ssh root@fs2 '/usr/syno/bin/synowebapi --exec api=SYNO.Core.Upgrade method=status version=1 feasibility_check=true 2>/dev/null'
   ssh root@fs2 '/usr/syno/bin/synowebapi --exec api=SYNO.Core.Upgrade.PreCheck method=start version=1 lang="\"enu\"" type="\"server\"" 2>/dev/null'
   ```

   Expect `"allow_upgrade" : true` and a precheck with no blocking items.

8. Export the DSM configuration and copy it off fs2:

   ```bash
   f=fs2-$(date +%Y%m%d-%H%M).dss
   ssh root@fs2 "/usr/syno/bin/synoconfbkp export --filepath=/tmp/$f && sha256sum /tmp/$f"
   ssh root@fs2 "cat /tmp/$f" > .tmp/dsm-upgrade/$f
   shasum -a 256 .tmp/dsm-upgrade/$f
   ```

   Expect the two checksums to match. Then remove the copy on fs2, using the
   `.dss` name from above:

   ```bash
   ssh root@fs2 "rm /tmp/<file>"
   ```

9. Fresh control-plane backup (writes to fs2 while it is still up):

   ```bash
   kubectl -n kube-system create job --from=cronjob/cluster-backup pre-dsm-backup-$(date +%Y%m%d)
   kubectl -n kube-system wait --for=condition=complete job/pre-dsm-backup-$(date +%Y%m%d) --timeout=15m
   ```

10. Inventory, to show the user what is about to stop:

    ```bash
    scripts/iscsi-storage status
    ssh p1 sudo qm list
    ssh luser 'findmnt -t nfs,nfs4 -n -o TARGET,OPTIONS | cut -c1-120; sudo fuser -vm $(findmnt -t nfs,nfs4 -n -o TARGET) 2>&1'
    kubectl get cronjobs -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,SCHEDULE:.spec.schedule,TZ:.spec.timeZone
    kubectl -n velero get schedules -o custom-columns=NAME:.metadata.name,SCHEDULE:.spec.schedule,PAUSED:.spec.paused
    ```

    For each VM `qm list` shows as `running`, check
    `ssh p1 sudo qm config <vmid>` for a disk on `proxmox-ssd:`. Expect k1
    (VMID 134) as the only running VM on `proxmox-ssd`. On luser, report any
    process using a `soft` mount: it gets I/O errors during the outage. If
    `daily-iscsi-backups` is already paused, stop and ask the user.

**GATE 1**: present the target version, release-note highlights, the precheck
result, the inventory and the next scheduled run of each CronJob and Velero
schedule. Ask the user to confirm starting the disruption.

## Phase 2: Quiesce

11. Pause Velero and suspend every CronJob that is not already suspended, saving
    the list:

    ```bash
    kubectl -n velero patch schedule daily-iscsi-backups --type merge -p '{"spec":{"paused":true}}'
    kubectl get cronjobs -A -o json | jq -r '.items[] | select(.spec.suspend != true) | "\(.metadata.namespace) \(.metadata.name)"' > .tmp/dsm-upgrade/cronjobs.txt
    while read -r ns n; do kubectl -n "$ns" patch cronjob "$n" -p '{"spec":{"suspend":true}}'; done < .tmp/dsm-upgrade/cronjobs.txt
    kubectl get pods -A -l batch.kubernetes.io/job-name --field-selector status.phase!=Succeeded,status.phase!=Failed
    ```

    The last command must print no pods. If a job is running, wait for it and
    report what it was.

12. Scale down iSCSI workloads (GATE 1 is the confirmation):

    ```bash
    scripts/iscsi-storage down --yes
    ```

    It ends with `All iSCSI workloads scaled down`.

13. Gate on zero iSCSI sessions. Each check must come back empty:

    ```bash
    kubectl get volumeattachments -o json | jq -r '.items[] | select(.spec.attacher=="org.democratic-csi.synology-iscsi") | "\(.spec.nodeName) \(.spec.source.persistentVolumeName)"'
    for n in k1 k2 k3 k4 k5; do echo "== $n"; ssh $n 'sudo iscsiadm -m session 2>&1'; done
    ```

    Each node prints `iscsiadm: No active sessions.` If a session remains,
    follow "Stale iSCSI session" below for it, then rerun this step. Do not
    continue past this step with any session open.

14. Shut down k1. From here on, the API server is unavailable:

    ```bash
    ssh p1 'sudo qm shutdown 134 --timeout 300 && sudo qm status 134'
    ```

    Expect `status: stopped`.

**GATE 2**: tell the user everything is quiesced and that the next step installs
DSM, which cannot be downgraded. Ask for the go-ahead.

## Phase 3: Upgrade

15. Start the install with the parameters the DSM Admin Center sends:

    ```bash
    ssh root@fs2 '/usr/syno/bin/synowebapi --exec api=SYNO.Core.Upgrade method=start version=1 force=true type="\"server\"" 2>/dev/null'
    ```

    Expect `"success" : true`. If it fails, stop and report: do not try
    `synoupgrade --start-force` or other variants without the user. The rollback
    for a failed start is Phase 4 with DSM unchanged.

16. Wait for fs2 to go down, then come back. Each wait is bounded to 10 minutes;
    check the console after each and repeat the wait if fs2 is still
    progressing:

    ```bash
    timeout 600 bash -c 'until ! nc -z -w2 fs2.oneill.net 5001; do sleep 10; done'; echo "rc=$? $(date -u +%FT%TZ)"
    timeout 600 bash -c 'until nc -z -w2 fs2.oneill.net 3260 && nc -z -w2 fs2.oneill.net 2049 && nc -z -w2 fs2.oneill.net 5001; do sleep 15; done'; echo "rc=$? $(date -u +%FT%TZ)"
    ssh infra1 'sudo tail -n 40 /var/log/conserver/fs2.log'
    ```

    `rc=124` means the wait timed out. If fs2 is not back 30 minutes after going
    down, report it with the console output.

17. Confirm the new version and that DSM has settled:

    ```bash
    ssh root@fs2 'grep -E "^(productversion|buildnumber|smallfixnumber)=" /etc.defaults/VERSION; uptime; /usr/syno/bin/synopkg status ScsiTarget; /usr/syno/bin/synowebapi --exec api=SYNO.Core.Upgrade method=status version=1 2>/dev/null; grep -E "^md|\[" /proc/mdstat'
    ```

    Expect the target version, ScsiTarget `running`, upgrade status `none`, and
    the arrays as in step 4. DSM may still be updating packages after boot: wait
    while upgrade status is not `none` before Phase 4.

## Phase 4: Restore

18. Start k1 and wait for the cluster:

    ```bash
    ssh p1 'sudo qm start 134'
    timeout 600 bash -c 'until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 10; done'
    kubectl wait --for=condition=Ready node --all --timeout=10m
    kubectl get pods -A --no-headers | grep -vE 'Running|Completed'
    ```

    Report pods that stay unhealthy after a few minutes, especially those using
    NFS.

19. Restore iSCSI workloads:

    ```bash
    timeout 900 scripts/iscsi-storage up --yes
    ```

    It ends with `Workload restore completed successfully`. If it times out,
    report which workloads are not ready. A pod stuck in `ContainerCreating`
    with an iSCSI login or attach error: see "Stale iSCSI session".

20. Verify no read-only CSI mounts and that the CSI controller talks to DSM:

    ```bash
    for n in k2 k3 k4 k5; do ssh $n 'for m in $(findmnt -rn -o TARGET | grep "kubernetes.io~csi/pvc-.*/mount$"); do findmnt -n -o OPTIONS "$m" | grep -q "^ro" && echo "$(hostname) RO: $m"; done'; done
    kubectl -n democratic-csi logs deploy/democratic-csi-controller -c csi-driver --since=30m | grep -iE 'error|401|403|login' | tail -20
    ```

    The first command prints nothing. Report any controller errors.

21. Restore the schedules:

    ```bash
    while read -r ns n; do kubectl -n "$ns" patch cronjob "$n" -p '{"spec":{"suspend":false}}'; done < .tmp/dsm-upgrade/cronjobs.txt
    kubectl -n velero patch schedule daily-iscsi-backups --type merge -p '{"spec":{"paused":false}}'
    ```

22. Report: old and new version, the time fs2 was down (from step 16), any
    deviations, and the updates this skill needs.

## Stale iSCSI session

Targets allow one session, so a session left on a node blocks every other node
from logging in. Targets are named
`iqn.2000-01.com.synology:csi.<namespace>-<pvc>`. Example for
`default/radarr-config`:

```bash
T=iqn.2000-01.com.synology:csi.default-radarr-config
for n in k1 k2 k3 k4 k5; do echo "== $n"; ssh $n "sudo iscsiadm -m session | grep -F $T"; done
kubectl get pods -A -o wide | grep radarr
```

On a node that holds the session but does not run the pod, find the disk and
confirm it is not mounted before logging out:

```bash
ssh k3 "sudo iscsiadm -m session -P3 | grep -A40 -F $T | grep -m1 'Attached scsi disk'"
ssh k3 'lsblk -nr -o MOUNTPOINTS /dev/sdX | grep .'
```

If `lsblk` prints anything, stop and report. Otherwise, with the user's
agreement:

```bash
ssh k3 "sudo iscsiadm -m node -T $T -p fs2.oneill.net:3260 --logout && sudo iscsiadm -m node -T $T -p fs2.oneill.net:3260 -o delete"
```

## Known noise

- During the nightly Velero backup, nodes log `session recovery timed out` and
  `EXT4-fs ... Remounting filesystem read-only` for targets named
  `csi.velero-daily-iscsi-backups-*`. These are Velero's temporary snapshot
  clones, not application volumes.
- The fs2 console logs thousands of `iSCSI Login negotiation failed` lines in
  the same hour, also from Velero clone creation.
