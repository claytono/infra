# Kubernetes Upgrade Playbook

Step-by-step instructions for upgrading Kubernetes clusters managed by Ansible
and kubeadm.

## Version Policy

Stay one minor version behind the latest stable release (e.g., latest is 1.35 →
target 1.34).

## Prerequisites

1. **Investigate the release.** Before starting, review the target version's
   changelog, urgent upgrade notes, and deprecation list. Check for removed
   APIs, removed feature gates, and breaking changes that affect our workloads.
   Run pluto against the cluster and kubeconform against our manifests during
   this phase — not mid-upgrade.

   ```bash
   pluto detect-all-in-cluster --target-versions k8s=v1.XX.0

   CRD_SCHEMA_URL='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
   kubeconform -schema-location default \
     -schema-location "$CRD_SCHEMA_URL" \
     -kubernetes-version 1.XX.0 kubernetes/
   ```

   kubeconform flags kustomize patches, non-K8s YAML (values.yaml,
   kustomization.yaml), and `.tmp/` directories as failures — these are expected
   noise.

2. **Verify component compatibility** with the target version. Check upstream
   docs for flannel, metallb, traefik, argocd, vpa, descheduler, external-dns,
   external-secrets, cert-manager, kube-state-metrics, metrics-server,
   democratic-csi, nfs-subdir-external-provisioner, reloader, and containerd.

3. **Snapshot k1** on Proxmox:

   ```bash
   # From any Proxmox node (p1-p4):
   pvesh get /cluster/resources --type vm --output-format json | \
     python3 -c "import sys,json; [print(f'VMID={v[\"vmid\"]} node={v[\"node\"]}') for v in json.load(sys.stdin) if v['name']=='k1']"

   VMID=<vmid>
   NODE=<node>

   pvesh create /nodes/$NODE/qemu/$VMID/snapshot --snapname pre-upgrade \
     --description "Before K8s upgrade to v1.XX"

   # Verify it exists
   pvesh get /nodes/$NODE/qemu/$VMID/snapshot --output-format json | python3 -m json.tool
   ```

4. **Verify cluster health:**

   ```bash
   kubectl get applications -A                                  # All Synced & Healthy
   kubectl get pods -A --field-selector=status.phase!=Running   # Only completed jobs
   ssh k1 sudo kubeadm certs check-expiration                  # Save for post-upgrade comparison
   ```

## Phase 1: Deploy kubeadm

Update `ansible/group_vars/kubernetes.yaml` — only kubeadm, cri-tools, and repo
versions. Leave kubelet/kubectl/kubernetes-cni unchanged:

```yaml
kubernetes_short_version: "1.XX"
kubeadm_version: "1.XX.XX-1.1"
cri_tools_version: "1.XX.0-1.1"
kubernetes_repo_versions:
  - "1.XX"
  - "1.YY" # previous version for rollback
```

If the kubeadm config API version has changed (e.g., v1beta3 → v1beta4), update
`ansible/roles/kubeadm/templates/kubeadm.conf.j2` to match. This template is not
used during `kubeadm upgrade apply` (kubeadm reads the live ConfigMap), but it
should stay current for any future `kubeadm reset && init`.

Deploy to all nodes and verify:

```bash
cd ansible && ansible-playbook -l kubernetes -t kubernetes site.yaml
ssh k1 kubeadm version   # Should show target version
```

## Phase 2: Upgrade Control Plane

Review what kubeadm will do, pre-pull images, then apply:

```bash
ssh k1 sudo kubeadm upgrade plan 2>&1 | tee /tmp/k1-upgrade-plan.log

ssh k1 'sudo time kubeadm config images pull --kubernetes-version v1.XX.XX' \
  2>&1 | tee /tmp/k1-image-pull.log

ssh k1 'sudo time kubeadm upgrade apply v1.XX.XX' \
  2>&1 | tee /tmp/k1-upgrade.log
```

The upgrade can take up to 20 minutes, especially with major etcd version jumps
(e.g., 3.5 → 3.6). Tee the output so it's available for review if the terminal
disconnects.

Verify the control plane is healthy before touching anything else:

```bash
kubectl cluster-info
kubectl get nodes
kubectl get pods -n kube-system
```

If the control plane is unhealthy, restore from the Proxmox snapshot (see
Rollback Plan) before proceeding.

## Phase 3: Upgrade k1 Packages

Drain k1, update package versions, deploy, and uncordon:

```bash
scripts/rolling-node-reboot.sh --skip-reboot --skip-uncordon k1
```

Check available package versions, then update `kubernetes.yaml`:

```bash
ssh k1 'sudo apt update && apt-cache policy kubernetes-cni kubelet kubectl cri-tools'
```

```yaml
kubernetes_version: "1.XX.XX"
kubelet_version: "1.XX.XX-1.1"
kubectl_version: "1.XX.XX-1.1"
kubernetes_cni_version: "1.X.X-1.1" # latest available in target repo
```

```bash
cd ansible && ansible-playbook -l k1 -t kubernetes site.yaml
kubectl uncordon k1
```

The API server may be briefly unavailable after the kubelet restarts — wait a
few seconds and retry if `kubectl uncordon` gets a connection error.

Verify k1 shows the target version before proceeding to workers:

```bash
kubectl get nodes -o wide
```

## Phase 4: Upgrade Workers

Upgrade one at a time. Generic workers first, specialized nodes (GPU) last.

For each worker:

```bash
scripts/rolling-node-reboot.sh --skip-reboot --skip-uncordon <worker>
ssh <worker> sudo kubeadm upgrade node
cd ansible && ansible-playbook -l <worker> -t kubernetes site.yaml
kubectl uncordon <worker>
kubectl get nodes -o wide   # Verify Ready + target version before next worker
```

Drains can take several minutes due to PodDisruptionBudgets and iSCSI volume
detachment. On a small cluster, some evicted pods may remain Pending until the
node is uncordoned — this is expected when capacity is tight.

## Phase 5: Final Validation

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

Once satisfied, remove the Proxmox snapshot:

```bash
# From the same Proxmox node as Prerequisites
pvesh delete /nodes/$NODE/qemu/$VMID/snapshot/pre-upgrade
```

## Rollback Plan

If the control plane upgrade fails or is unhealthy:

1. Restore k1 from Proxmox snapshot:

   ```bash
   pvesh create /nodes/$NODE/qemu/$VMID/snapshot/pre-upgrade/rollback
   ```

2. Workers reconnect automatically once the API server is back. If workers were
   already upgraded, kubelet n+1 talking to apiserver n is supported (n-1 skew),
   but they should be rolled back by redeploying previous packages via Ansible.

**Rollback triggers:** `kubeadm upgrade apply` exits non-zero, API server not
responding within 5 minutes, control plane pods in CrashLoopBackOff.

## Reference

### kubeadm Configuration Template

The template at `ansible/roles/kubeadm/templates/kubeadm.conf.j2` uses the
kubeadm v1beta4 API. kubeadm migrates the live cluster ConfigMap automatically
during upgrades, but the local template must be updated manually when the API
version changes (e.g., v1beta4 changed `extraArgs` from a map to a list of
`{name, value}` objects).

Before any `kubeadm reset && init`, reconcile the template against the live
config and kubeadm defaults:

```bash
cat ansible/roles/kubeadm/templates/kubeadm.conf.j2
kubectl get configmap kubeadm-config -n kube-system -o jsonpath='{.data.ClusterConfiguration}'
ssh k1 sudo kubeadm config print init-defaults
```

### Dependency Requirements

kubeadm requires cri-tools from the same minor version. Always update
`cri_tools_version` when updating `kubeadm_version`.

### Troubleshooting

**Certificate errors with kubectl:** Check `hostname -f` returns the FQDN and
`/etc/hosts` is correct.

**Package dependency conflicts:** Check apt preferences files in
`/etc/apt/preferences.d/` — the Ansible role creates version pins there.
