# Kubernetes Upgrade Playbook

How Kubernetes upgrades run on this cluster, which is managed by Ansible and
kubeadm. Patch updates are automated end to end; minor upgrades use the same
automation but are started by hand.

## Version Policy

Stay one minor version behind the latest stable release (e.g., latest is 1.35 →
target 1.34).

## How Upgrades Run

Renovate proposes version changes to `ansible/group_vars/kubernetes.yaml`:

- **Patch updates** (1.34.6 → 1.34.7) arrive as one PR moving
  `kubernetes_version` and the kubeadm, kubelet and kubectl pins together.
- **Minor upgrades** (1.34 → 1.35) arrive as two PRs: first
  `kubernetes_short_version`, which switches the APT repositories, then the
  pins. Renovate never proposes skipping a minor.

When a version change is deployed, the plays in `ansible/kubernetes.yaml`
(imported by `site.yaml`) upgrade the cluster in order:

1. **Routine Kubernetes play** (all nodes at once). Preflight checks refuse a
   downgrade, a skipped minor, pins that disagree with `kubernetes_version`, a
   version absent from the repositories, and a minor upgrade without
   `-e kubeadm_allow_minor_upgrade=true`. A node whose version is changing gets
   no packages installed here.
2. **Control plane** (k1). Installs the new kubeadm, runs `kubeadm upgrade plan`
   and `kubeadm upgrade apply --dry-run` (both must pass), cordons k1, runs
   `kubeadm upgrade apply`, installs kubectl, kubernetes-cni and kubelet,
   restarts kubelet, waits for the API server, for k1 Ready at the new version
   and for its pods, then uncordons. If k1 does not come back, the run stops.
3. **Workers**, one at a time: k3, k4, k5, then k2 last (its
   `kubeadm_upgrade_tier` is `last`). Each refuses to start unless the API
   server is already at the target version, then runs the same sequence with
   `kubeadm upgrade node` in place of `apply`, following upstream's order. Any
   failure stops the run before the next node.
4. **Verification**: every node in the run Ready at the target version.

When versions already match, each upgrade play ends after a few read-only
checks, so ordinary deploys are unaffected.

Details worth knowing:

- **The cluster must be healthy first.** Before touching each node, the upgrade
  refuses to start if any node is cordoned other than by the upgrade itself, and
  waits up to a minute for every unfinished pod in the cluster, unscheduled ones
  included, to be Ready, naming any that are not. Checking the whole cluster
  before each node means a workload left down by an earlier step stops the run
  before the next node. To upgrade despite unready pods, add
  `-e kubeadm_upgrade_allow_unready_pods=true`; those workloads are then left
  out of the waits. There is no override for a cordoned node: uncordon it, or
  finish what it is cordoned for, first.

- **A retry while a node is still cordoned by the upgrade.** Some workloads can
  only run on one node: the ezshare-sync job needs k5's USB device, and plex,
  immich machine learning, ollama and whisperx need k2's GPU. While a failed run
  leaves their node cordoned they have no node to go to, so the cluster-wide
  checks leave out pods with no node for as long as any node carries the
  upgrade's cordon annotation. Once the run uncordons the last such node, its
  own post-uncordon wait counts them again, so they still have to come back
  Ready before the run passes.

- **Cordon or drain.** A patch only cordons: restarting kubelet leaves running
  containers alone. A minor upgrade drains, as upstream requires.
- **Rehearsal output** is kept on k1 in
  `/var/log/kubeadm-upgrade/<version>-<timestamp>-{plan,dry-run}.log`. It is not
  printed in the Ansible output (the dry-run alone is thousands of lines); read
  these files when a run fails.
- **Two node annotations.** `oneill.net/kubeadm-upgrade-in-progress` is set on
  every node when its upgrade starts and removed only once the run's final
  verification passes. `oneill.net/kubeadm-upgrade-cordoned` is set only when
  the upgrade did the cordoning, so a node a person cordoned beforehand is never
  uncordoned by the upgrade.
- **After a drain** (minor upgrades only), the upgrade also waits for the
  evicted pods to be Ready on the other nodes. Pods with no node yet are left
  out at that point, since some only fit once the drained node is uncordoned;
  after the uncordon, every workload in the cluster must be Ready before the
  next node is drained. Workloads that were not Ready before the drain are left
  out of both checks. Pods are compared by their owner (ReplicaSet, StatefulSet
  and so on), because a drain recreates them under new names. Each of these
  waits, and the wait for a node's own pods after its kubelet restart, allows 15
  minutes (`kubeadm_node_pods_timeout`): an evicted pod may first wait for its
  old copy to stop (up to the drain's 120s grace period), then for a
  `ReadWriteOncePod` volume to move, a recursive ownership change on the volume
  and image pulls on a node that has never run it. During the 1.35 upgrade felix
  took about 8 minutes this way.
- **`kubectl` runs on k1** with `/etc/kubernetes/admin.conf`, so limited runs
  such as `-l k3` still work.

## Patch Updates

Review the Renovate PR (the renovate-eval comment covers the release notes),
then merge it. The merge deploy through Semaphore performs the upgrade. Merging
the PR is the approval for the maintenance window.

No Proxmox snapshot is taken: kubeadm keeps its own manifest and etcd backups
during `apply`, which covers what a patch realistically breaks.

Watch the Semaphore job, then run the checks in
[Final Validation](#final-validation).

## Minor Upgrades

### Prerequisites

1. **Investigate the release.** Before starting, review the target version's
   changelog, urgent upgrade notes, and deprecation list. Check for removed
   APIs, removed feature gates, and breaking changes that affect our workloads.
   Run pluto against the cluster and kubeconform against our manifests during
   this phase — not mid-upgrade.

   ```bash
   pluto detect-all-in-cluster --target-versions k8s=v1.XX.0

   CRD_SCHEMA_URL='https://raw.githubusercontent.com/datreeio/CRDs-catalog/f1e7f6bc0537bf0622ffe6e47dbaa85914fabbec/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
   kubeconform -schema-location default \
     -schema-location "$CRD_SCHEMA_URL" \
     -kubernetes-version 1.XX.0 kubernetes/
   ```

   kubeconform flags kustomize patches, non-K8s YAML (values.yaml,
   kustomization.yaml), and `.tmp/` directories as failures — these are expected
   noise.

2. **Verify component compatibility** with the target version. Check upstream
   docs for flannel, multus (and its network attachment definitions), metallb,
   traefik, argocd, vpa, descheduler, external-dns, external-secrets,
   cert-manager, kube-state-metrics, metrics-server, democratic-csi,
   csi-driver-nfs (`kubernetes/0-nfs-csi-driver`), volume-snapshot-controller,
   velero, cloudnative-pg, node-feature-discovery, nvidia-device-plugin, spegel,
   tailscale-operator, reloader, and containerd.

3. **Check the kubeadm config API version.** If it has changed (e.g., v1beta3 →
   v1beta4), update `ansible/roles/kubeadm/templates/kubeadm.conf.j2` to match.
   See [kubeadm Configuration Template](#kubeadm-configuration-template).

4. **Snapshot k1** on Proxmox (see [Proxmox Snapshots](#proxmox-snapshots)). The
   workers cannot be snapshotted.

5. **Verify cluster health:**

   ```bash
   kubectl get applications -A                                  # All Synced & Healthy
   kubectl get pods -A --field-selector=status.phase!=Running   # Only completed jobs
   ssh k1 sudo kubeadm certs check-expiration                  # Save for post-upgrade comparison
   ```

### Steps

1. **Merge the `kubernetes_short_version` PR.** Its deploy only switches the APT
   repositories to the new minor plus the one below; the installed packages stay
   where they are.

2. **Run the upgrade by hand from the pin PR's branch, before merging it.** A
   minor upgrade refuses to run without the flag, so the merge deploy cannot
   start it, and running it locally keeps the drains away from the Semaphore
   runner, which a drain could evict mid-run. Doing the control plane on its own
   first leaves a point to check it before any worker is drained:

   ```bash
   cd ansible
   ansible-playbook -l k1 kubernetes.yaml \
     -e kubeadm_allow_minor_upgrade=true
   # check the control plane, then:
   ansible-playbook -l k2,k3,k4,k5 kubernetes.yaml \
     -e kubeadm_allow_minor_upgrade=true
   ```

   The upgrade can take up to 20 minutes on k1, especially with major etcd
   version jumps (e.g., 3.5 → 3.6). Drains can take several minutes because of
   PodDisruptionBudgets and iSCSI volume detachment, and on a small cluster some
   evicted pods stay Pending until the node is uncordoned.

3. **Merge the pin PR.** The cluster already matches it, so the merge deploy is
   a no-op.

4. Run [Final Validation](#final-validation), then delete the k1 snapshot.

## Re-running After a Failure

Re-running the same command, or retrying the Semaphore job, is the normal way to
recover. Each upgrade step is safe to repeat: a node whose upgrade was
interrupted or failed still carries the in-progress annotation, so the next run
stops at that node again instead of treating it as done and moving on. A node
whose upgrade failed is left cordoned, so nothing new is scheduled onto it; a
successful retry uncordons it. Nodes that had already succeeded in the failed
run are upgraded again on the retry, which is safe but restarts their kubelet.
While k1 is not done, every run repeats `kubeadm upgrade apply` at the target
version, which finishes an apply that was interrupted partway.

Include every unfinished node in a limited run (`-l`). While a node is still
cordoned by the upgrade, the readiness checks leave out pods with no node, since
some can only run there; they are checked again once a run uncordons that node.
A run that leaves the cordoned node out never does, so it can pass while that
node and the workloads tied to it are still down.

To see which nodes an upgrade has not finished:

```bash
kubectl get nodes -o custom-columns='NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,UNSCHEDULABLE:.spec.unschedulable,IN-PROGRESS:.metadata.annotations.oneill\.net/kubeadm-upgrade-in-progress'
```

If a re-run keeps failing at the same point, fix the cause, or finish that node
by hand using [Manual Fallback](#manual-fallback), then run the deploy again so
the remaining nodes follow.

## Final Validation

```bash
kubectl get nodes -o wide                                      # All at target version
kubectl cluster-info
kubectl get pods -A --field-selector=status.phase!=Running     # Only completed jobs
kubectl get applications -A                                    # All Synced & Healthy
ssh k1 sudo kubeadm certs check-expiration                    # Should be ~1 year out
kubectl get ingress -A                                         # All have addresses
kubectl get pv,pvc -A                                          # All Bound
kubectl get pods -A -o wide | grep nvidia                      # GPU workloads running
kubectl run test-dns --image=nicolaka/netshoot --rm -it --restart=Never \
  -- dig kubernetes.default.svc.cluster.local
```

## Rollback Plan

If the control plane upgrade fails or is unhealthy:

1. Restore k1 from its Proxmox snapshot (see
   [Proxmox Snapshots](#proxmox-snapshots)).

2. Workers reconnect automatically once the API server is back. Workers are only
   upgraded after k1 succeeds, so after a k1 rollback they are normally still on
   the old version. If any were upgraded, a kubelet one minor newer than the API
   server is outside the supported skew: roll it back by setting the previous
   versions in `group_vars` and finishing it by hand.

3. Set `ansible/group_vars/kubernetes.yaml` back to the version k1 is on.
   Otherwise the next deploy, including unrelated ones and the nightly
   idempotency run, retries the upgrade that just failed.

**Rollback triggers:** `kubeadm upgrade apply` exits non-zero, API server not
responding within 5 minutes, control plane pods in CrashLoopBackOff.

## Reference

### Proxmox Snapshots

Run on `p1` as root. Find k1's VM and node (k1 is currently VMID 134 on `p1`):

```bash
ssh root@p1
export NAME=k1
pvesh get /cluster/resources --type vm --output-format json | \
  python3 -c "import sys,json,os; [print(f'VMID={v[\"vmid\"]} node={v[\"node\"]}') for v in json.load(sys.stdin) if v['name']==os.environ['NAME']]"
VMID=<vmid>
NODE=<node>
```

Take the snapshot and confirm it exists:

```bash
pvesh create /nodes/$NODE/qemu/$VMID/snapshot --snapname pre-upgrade \
  --description "Before K8s upgrade to v1.XX"
pvesh get /nodes/$NODE/qemu/$VMID/snapshot --output-format json | python3 -m json.tool
```

Roll back:

```bash
pvesh create /nodes/$NODE/qemu/$VMID/snapshot/pre-upgrade/rollback
```

Delete it only once the upgrade has been validated, never as part of recovery:

```bash
pvesh delete /nodes/$NODE/qemu/$VMID/snapshot/pre-upgrade
```

### Manual Fallback

The commands the automation runs, for finishing a node by hand. `kubectl`
commands run from anywhere with cluster-admin access. Set `group_vars` to the
target first, so the packages the commands below install match.

Control plane (k1):

```bash
ssh k1 sudo apt-get install -y kubeadm=1.XX.XX-1.1 cri-tools=1.XX.0-1.1
ssh k1 sudo kubeadm upgrade plan v1.XX.XX
kubectl cordon k1                     # drain instead for a minor upgrade
ssh k1 sudo kubeadm upgrade apply v1.XX.XX --yes
ssh k1 sudo apt-get install -y kubelet=1.XX.XX-1.1 kubectl=1.XX.XX-1.1 kubernetes-cni=1.X.X-1.1
ssh k1 sudo systemctl restart kubelet
kubectl uncordon k1
```

Worker:

```bash
ssh <worker> sudo apt-get install -y kubeadm=1.XX.XX-1.1 cri-tools=1.XX.0-1.1
ssh <worker> sudo kubeadm upgrade node
kubectl cordon <worker>               # drain instead for a minor upgrade:
                                      #   scripts/rolling-node-reboot.sh --skip-reboot --skip-uncordon <worker>
ssh <worker> sudo apt-get install -y kubelet=1.XX.XX-1.1 kubectl=1.XX.XX-1.1 kubernetes-cni=1.X.X-1.1
ssh <worker> sudo systemctl restart kubelet
kubectl uncordon <worker>
```

Afterwards, remove the upgrade annotations so the automation treats the node as
done (removing one that is not there is a no-op):

```bash
kubectl annotate node <node> oneill.net/kubeadm-upgrade-in-progress- oneill.net/kubeadm-upgrade-cordoned-
```

### kubeadm Configuration Template

The template at `ansible/roles/kubeadm/templates/kubeadm.conf.j2` uses the
kubeadm v1beta4 API. It is not used during `kubeadm upgrade apply` (kubeadm
reads the live ConfigMap and migrates it automatically), but it must stay
current for any future `kubeadm reset && init`, and it has to be updated by hand
when the API version changes (e.g., v1beta4 changed `extraArgs` from a map to a
list of `{name, value}` objects).

Before any `kubeadm reset && init`, reconcile the template against the live
config and kubeadm defaults:

```bash
cat ansible/roles/kubeadm/templates/kubeadm.conf.j2
kubectl get configmap kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}'
ssh k1 sudo kubeadm config print init-defaults
```

### Dependency Requirements

kubeadm requires cri-tools from the same minor version. Renovate moves
`cri_tools_version` when a matching release exists; the role installs kubeadm
and cri-tools together.

### Troubleshooting

**Certificate errors with kubectl:** Check `hostname -f` returns the FQDN and
`/etc/hosts` is correct.

**Package dependency conflicts:** Check apt preferences files in
`/etc/apt/preferences.d/` — the Ansible role creates version pins there.

**Preflight says a version is not available:** the apt cache on that node may
predate the release. Preflight refreshes it when a version is changing; if it
still fails, check the repositories in `/etc/apt/sources.list.d/kubernetes-v*`.
