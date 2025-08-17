# Kubernetes Upgrade Playbook

This playbook provides step-by-step instructions for upgrading Kubernetes
clusters managed by Ansible and kubeadm.

## Prerequisites

- [ ] VM snapshot of k1
- [ ] Verify all applications are healthy before starting

## Phase 0: Environment Preparation

### 0.1 Update Development Environment

1. **Update nix flake for latest tooling**

   ```bash
   # Update flake inputs to latest versions
   nix flake update

   # Rebuild development environment with latest tools
   exit  # exit current nix develop
   nix develop  # re-enter with updated packages
   ```

2. **Verify required tools are available**

   ```bash
   # Verify all required tools
   kubectl version --client
   kubeconform --version
   pluto version
   ansible --version
   ```

3. **Check certificate expiration (pre-upgrade)**

   ```bash
   # Check current certificate expiration dates
   sudo kubeadm certs check-expiration
   ```

## Phase 1: Infrastructure Preparation

### 1.1 Version Assessment

1. **Check current cluster version and APIs**

   ```bash
   # Check current Kubernetes version to determine target
   kubectl version
   ```

2. **Determine target version**
   - Check [Kubernetes release notes](https://kubernetes.io/releases/) for
     breaking changes
   - Plan upgrade path (Kubernetes supports n-1 version skew)

### 1.2 Compatibility Verification

1. **Check for deprecated APIs and invalid manifests**

   ```bash
   # Check for deprecated APIs in running cluster
   pluto detect-all-in-cluster --target-versions k8s=v1.XX.0

   # Validate manifests against target version
   kubeconform -kubernetes-version 1.XX.0 kubernetes/
   ```

2. **Check Chart.yaml files and image versions for these services:**

- **CNI**: flannel
- **Load Balancer**: metallb
- **Ingress**: ingress-nginx
- **GitOps**: argocd
- **Autoscaling**: vpa, descheduler
- **DNS/Secrets**: external-dns, external-secrets, 1password-connect
- **Monitoring**: kube-state-metrics, metrics-server
- **Storage**: nfs-client-provisioner
- **Operations**: reloader
- **Container Runtime**: containerd (via githubixx.containerd role)

## Phase 2: kubeadm Upgrade (Control Plane)

### 2.1 Update Repository Configuration

1. **Update kubernetes.yaml variables for repo and kubeadm:**

   ```yaml
   # In group_vars/kubernetes.yaml
   kubernetes_short_version: "1.XX" # Update repo config
   kubeadm_version: "1.XX.XX-1.1"
   cri_tools_version: "1.XX.0-1.1" # MUST match k8s minor version
   # Keep other versions at current for now
   ```

2. **Deploy kubeadm to all nodes:**

   ```bash
   ansible-playbook -l kubernetes -t kubernetes site.yaml
   ```

### 2.2 Evaluate Cluster Configuration

1. **Check kubeadm ConfigMap:**

   ```bash
   kubectl get configmap kubeadm-config -n kube-system -o yaml
   kubectl get configmap kubelet-config -n kube-system -o yaml
   ```

2. **Compare with kubeadm expectations:**

   ```bash
   sudo kubeadm config print init-defaults
   sudo kubeadm config print join-defaults
   ```

3. **Look for:**
   - Version mismatches
   - Deprecated API versions
   - Missing configuration parameters
   - CNI configuration alignment

### 2.3 Run kubeadm Upgrade

1. **Plan the upgrade:**

   ```bash
   sudo kubeadm upgrade plan
   ```

2. **Apply the upgrade:**

   ```bash
   sudo kubeadm upgrade apply v1.XX.XX
   ```

## Phase 3: Control Plane Package Updates

### 3.1 Drain Control Plane

```bash
kubectl drain k1 --ignore-daemonsets --force --delete-emptydir-data
```

### 3.2 Update All Package Versions

1. **Update kubernetes.yaml with all versions:**

   ```yaml
   kubernetes_version: "1.XX.XX"
   kubeadm_version: "1.XX.XX-1.1"
   kubelet_version: "1.XX.XX-1.1"
   kubectl_version: "1.XX.XX-1.1"
   cri_tools_version: "1.XX.0-1.1"
   kubernetes_cni_version: "1.X.X-1.1" # Keep compatible version
   ```

### 3.3 Deploy Updated Packages

```bash
ansible-playbook -l k1 -t kubernetes site.yaml
```

### 3.4 Uncordon Control Plane

```bash
kubectl uncordon k1
```

## Phase 4: Worker Node Upgrades

For each worker node, repeat these steps:

### 4.1 Drain Worker Node

```bash
kubectl drain <worker-hostname> --ignore-daemonsets --force --delete-emptydir-data
```

### 4.2 Deploy Packages to Worker

```bash
ansible-playbook -l <worker-hostname> -t kubernetes site.yaml
```

### 4.3 Uncordon Worker Node

```bash
kubectl uncordon <worker-hostname>
```

### 4.4 Verify Node Ready

```bash
kubectl get nodes -o wide
# Ensure node shows Ready status and correct version before continuing
```

## Phase 5: Final Validation

### 5.1 Cluster Health Check

```bash
# Check all nodes are ready and on correct version
kubectl get nodes -o wide

# Check for any non-running pods
kubectl get pods --all-namespaces --field-selector=status.phase!=Running

# Verify all pods are running (count should match)
kubectl get pods --all-namespaces | wc -l && \
  kubectl get pods --all-namespaces | grep Running | wc -l

# Verify cluster info
kubectl cluster-info
```

### 5.2 Ingress Connectivity Check

```bash
# Verify all ingress resources have addresses
kubectl get ingress --all-namespaces
```

### 5.3 DNS Resolution Test

```bash
# Test DNS resolution from within cluster
kubectl run test-dns --image=nicolaka/netshoot --rm -it --restart=Never \
  -- dig kubernetes.default.svc.cluster.local
```

### 5.4 Storage Validation

```bash
# Check all persistent volumes and claims are bound
kubectl get pv,pvc --all-namespaces
```

### 5.5 Certificate Validation

```bash
# Verify certificates were automatically renewed during upgrade
sudo kubeadm certs check-expiration
```

**Note:** Kubeadm automatically renews all certificates (1-year default
lifetime) during cluster upgrades.

### 5.6 Additional Application Testing (Optional)

- [ ] Test specific application endpoints via ingress
- [ ] Verify certificate auto-renewal functionality
- [ ] Test external integrations (webhooks, APIs, etc.)
- [ ] Validate backup/restore operations
- [ ] Check custom resource controllers

### 5.7 Component Updates (Optional)

1. **Update Helm charts** to latest compatible versions
2. **Update documentation** with new versions
3. **Update monitoring/alerting** if needed

## Important Notes

### Dependency Requirements

- **kubeadm dependency**: kubeadm 1.XX requires cri-tools >= 1.XX.0
- Always update `cri_tools_version` when updating `kubeadm_version`

### Troubleshooting

#### Hostname Resolution Issues

If `kubectl` commands fail with certificate errors:

- Verify `hostname -f` returns proper FQDN
- Check `/etc/hosts` configuration
- Ensure hostname role is applied

#### Package Dependency Conflicts

If apt shows dependency conflicts:

- Update dependent packages simultaneously
- Check apt preferences files in `/etc/apt/preferences.d/`

### Rollback Plan

If issues occur:

1. **Control plane rollback:**

   ```bash
   sudo kubeadm upgrade apply v1.OLD.VERSION
   ```

2. **Downgrade packages:**

   ```bash
   apt-get install kubeadm=1.OLD.VERSION-1.1 kubelet=1.OLD.VERSION-1.1
   ```

3. **Restore etcd from backup** if needed
4. **Restart services** and validate functionality

## Version-Specific Notes

### 1.29 → 1.30

- No breaking changes for standard workloads
- FlowSchema/PriorityLevelConfiguration API removal (rarely used)
- All kustomize v1beta1 usage remains compatible

### General Upgrade Guidelines

- Always test in staging environment first
- Upgrade one minor version at a time
- Monitor cluster metrics during upgrade
- Keep etcd backups recent
- Document any custom modifications needed
