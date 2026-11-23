---
name: kubernetes-worker-rebuild
description:
  Use when a bare-metal Kubernetes worker needs its boot drive replaced or a
  fresh OS install. Drains and removes the node, PXE-installs Debian from
  infra1, and rejoins it to the cluster with Ansible.
---

<!-- Steps are numbered across phases so they can be referenced by number. -->
<!-- markdownlint-disable MD029 -->

# Kubernetes Worker Rebuild

A worker's boot disk holds nothing that needs to be kept: pod volumes live on
fs2, and Ansible rebuilds everything else. A rebuild removes the node from the
cluster, installs Debian over PXE from infra1, and lets `site.yaml` rejoin it
with kubeadm.

The commands use three placeholders, filled in by step 3: `<node>` (the short
host name, such as `k4`), `<node-ip>` and `<amt-ip>`.

## Operating rules

- Run one step at a time and check its output against the stated expectation. On
  anything unexpected, stop and report it to the user with the output.
- Get an explicit go-ahead from the user at each step marked **GATE**. Invoking
  this skill authorizes the `ssh` commands written here, nothing else.
- Run `ansible-playbook` from the repo's `ansible/` directory. Pipe each run
  through `tee` to a log in `.tmp/` and check it for `fatal`, `[ERROR]` and the
  `PLAY RECAP` line.
- Give user-facing times in Eastern.

## Phase 1: Preflight (no disruption)

1. Check that the Tailscale auth key has not expired. Its expiry date is in the
   comment above `tailscale_authkey` in `ansible/group_vars/all/tailscale.yaml`.
   If that date has passed, or will pass before the rebuild finishes, stop: the
   user creates a new auth key in the Tailscale admin console (Settings → Keys:
   reusable, 90-day expiry, not ephemeral, no tags). Encrypt it, replace the
   vault block, and update the date in the comment:

   ```bash
   (cd ansible && printf '%s' '<new key>' | ansible-vault encrypt_string --stdin-name tailscale_authkey)
   ```

   An expired key fails late, at `tailscale up`, with
   `backend error: invalid key: API key does not exist`.

2. Check that the Ansible vault password file exists (it is not checked in):

   ```bash
   ls ansible/ansible-vault-password
   ```

   If it is missing, stop and ask the user to put it in place.

3. Look up the node's two addresses. The installed system first comes up on the
   AMT address, and Ansible moves it to the node address:

   ```bash
   dig +short <node>.oneill.net
   dig +short <node>-amt.oneill.net
   ```

   The first is `<node-ip>`, the second `<amt-ip>`.

4. Check that the PXE server on infra1 is serving the boot menu and preseed:

   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" http://infra1.oneill.net:8081/boot.ipxe
   grep -E '^item .*-preseed' ansible/roles/os-install/files/boot.ipxe
   ```

   Expect `200`. Each preseed entry loads `preseed.<release>.cfg`; check that
   each one is served:

   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" https://os-install.oneill.net/preseed.<release>.cfg
   ```

5. Check that the drain can finish. A drain waits forever on a pod it may not
   evict, so make sure no PodDisruptionBudget at zero allowed disruptions covers
   a pod on the node, and no pod is pinned to it:

   ```bash
   kubectl get pdb -A | awk 'NR==1 || $5==0'
   kubectl get pods -A --field-selector spec.nodeName=<node> -o wide
   ```

   Single-instance CloudNativePG clusters have no PDB; their primary moves and
   the app is down for a minute or two. Compare the memory requests of the
   node's non-DaemonSet pods with the free allocatable memory on the other
   workers (`kubectl describe node`).

## Phase 2: Remove the node

6. **GATE**: drain the node.

   ```bash
   kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=10m
   ```

   Then wait until every moved pod is ready elsewhere:

   ```bash
   kubectl get pods -A --no-headers | awk '$4=="Completed"{next} {split($3,a,"/"); if (a[1]!=a[2] || $4!="Running") print}'
   ```

   A Velero `kopia-maintain` job that ran while `velero-encrypt` was moving can
   fail with `no available server`; the next scheduled run succeeds.

7. **GATE**: power off the node, then delete it. Power off first; a running
   kubelet re-registers a deleted node straight away.

   ```bash
   ssh root@<node> poweroff
   until ! ping -c1 -W1 <node>.oneill.net >/dev/null; do sleep 2; done; echo "no longer answering ping"
   kubectl wait --for=condition=Ready=Unknown node/<node> --timeout=90s
   kubectl delete node <node>
   ```

   A node has booted again right after `poweroff` before (cause unknown). A few
   minutes later, check `kubectl get node <node>`. If it has registered again,
   cordon it at once (`kubectl cordon <node>`) and tell the user.

8. Ask the user to replace the drive, and to remove the old machine from the
   Tailscale admin console so the new install registers as `<node>` rather than
   `<node>-1`. Wait for both before step 14.

## Phase 3: Install

9. List the preseed entries in `ansible/roles/os-install/files/boot.ipxe` and
   ask the user which one to install. The user PXE boots the node (the one-time
   boot menu, or AMT through MeshCentral's remote desktop) and picks that entry
   before the iPXE menu's 30-second timeout; the default is the local disk. The
   install runs unattended and reboots.

10. Confirm the installed system is reachable on the AMT address. It comes up on
    the onboard NIC, which shares its MAC with AMT, so DHCP gives it the AMT
    reservation and the console shows `<node>-amt login:`:

    ```bash
    nc -z -w3 <amt-ip> 22 && ssh-keyscan -T 5 <amt-ip> | awk '{print $2}'
    ```

11. Replace the node's old host keys. Remove them under the names the skill
    knows; `ssh-keygen -R` also finds hashed entries:

    ```bash
    ssh-keygen -R <node>
    ssh-keygen -R <node>.oneill.net
    ssh-keygen -R <node-ip>
    ssh-keygen -R <amt-ip>
    ```

    Then list any other names its old keys are stored under, such as the
    Tailscale name and address or the IPv6 address, and run `ssh-keygen -R` for
    each:

    ```bash
    grep "<node>" ~/.ssh/known_hosts | cut -d' ' -f1
    ```

    Add the new keys under the LAN names, read from the AMT address (the keys
    are the same on every address):

    ```bash
    ssh-keyscan <amt-ip> 2>/dev/null | sed 's/^<amt-ip> /<node>,<node>.oneill.net,<node-ip>,<amt-ip> /' >> ~/.ssh/known_hosts
    ```

## Phase 4: Provision

12. **GATE**: run Ansible over the AMT address:

    ```bash
    ansible-playbook site.yaml -l <node> -e ansible_host=<amt-ip> 2>&1 | tee ../.tmp/<node>-rebuild-1.log
    ```

    It brings up the 10G NIC on `<node-ip>` and then fails at
    `Check active Ethernet interface state` with
    `Default IPv6 gateway is incorrect`. That is expected: the installer's
    `dhcpcd` still runs on the onboard NIC and holds a router-advertised IPv6
    default route that outranks the static one. Ansible has already rewritten
    `/etc/network/interfaces` to configure only the 10G NIC.

13. **GATE**: reboot the node to drop the onboard NIC's DHCP configuration:

    ```bash
    ssh ansible@<amt-ip> sudo reboot
    ```

    After it comes back, confirm only the 10G NIC is configured:

    ```bash
    ssh ansible@<node>.oneill.net 'uptime -s; ip -br addr; ip -6 route show default; ip route show default; pgrep -a dhcpcd || echo "no dhcpcd"'
    ```

    Expect a new boot time, the onboard NIC DOWN, only the 10G NIC with
    addresses, both default routes through it, and `no dhcpcd`. AMT keeps
    working on the onboard port without the OS.

14. **GATE**: run Ansible against the node's normal address. The old Tailscale
    entry must be gone (step 8); never skip the Tailscale role.

    ```bash
    ansible-playbook site.yaml -l <node> 2>&1 | tee ../.tmp/<node>-rebuild-2.log
    ```

    Expect `failed=0`. It runs Tailscale, NUT, Restic, containerd and kubelet,
    and `kubeadm join`. When `tailscale status` lists the new `<node>`, ask the
    user to disable its key expiry in the admin console.

## Phase 5: Verify

15. Confirm the node is Ready and schedulable, and its DaemonSet pods are ready:

    ```bash
    kubectl get node <node> -o wide
    kubectl get pods -A --field-selector spec.nodeName=<node> --no-headers | awk '$4=="Completed"{next} {split($3,a,"/"); if (a[1]!=a[2] || $4!="Running") print}'
    ```

    Expect `<node-ip>`, no `SchedulingDisabled`, and no pods listed by the
    second command once they settle.

16. Run a test pod on the node to confirm pod networking:

    ```bash
    kubectl run test-<node> --image=curlimages/curl --restart=Never --overrides='{"spec":{"nodeName":"<node>"}}' -- curl -sf -o /dev/null -w "%{http_code}" https://httpbin.org/get
    kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/test-<node> --timeout=90s
    kubectl logs test-<node>
    kubectl delete pod test-<node>
    ```

    Expect `200`.

17. Confirm smartd watches the new drive:

    ```bash
    ssh root@<node> 'smartctl -i /dev/sda | grep -E "Model|Serial"; smartctl -H /dev/sda | grep result; journalctl -t smartd -b --no-pager | tail -3'
    ```

    Expect the new drive's model, `PASSED`, and `Monitoring 1 ATA/SATA` in the
    log.

18. Run the playbook again and confirm it changes nothing:

    ```bash
    ansible-playbook site.yaml -l <node> 2>&1 | tee ../.tmp/<node>-rebuild-3.log
    ```

    Expect `changed=0 failed=0`.

Workloads do not move back by themselves; the node takes pods as they are
rescheduled. Restic backups continue in the host's existing snapshot series in
the `main` repository, and its Healthchecks check is reused by name.
