# Renovate Eval Context

## Repo Layout

- Kubernetes apps: `kubernetes/<app>/` with Helm values at `values.yaml` and
  `Chart.yaml`. Rendered Helm templates at `kubernetes/<app>/helm/`.
- Ansible roles: `ansible/roles/<role>/defaults/main.yaml` (some legacy roles
  use `main.yml`)
- Ansible inventory: `ansible/inventory/`
- OpenTofu: `opentofu/*.tf`
- Pre-commit hooks: `.pre-commit-config.yaml`

## Deployment

- Kubernetes deploys via ArgoCD on PR merge -- no manual deploy needed
- Ansible deploys via Semaphore on merge to main
- For pre-merge testing: `kubectl apply -k kubernetes/<app>/` for Kubernetes,
  `ansible-playbook` for Ansible (run from `ansible/` directory)

## Available Tools

- `skopeo` -- container image inspection (list tags, inspect manifests)
- `kubectl` and `helm` -- Kubernetes inspection (local mode only)

## Config Discovery

- Helm values: `kubernetes/[app]/values.yaml`, `Chart.yaml`
- K8s raw manifests: `kubernetes/[app]/*.yaml`
- Rendered Helm templates: `kubernetes/[app]/helm/` (read-only reference)
- Ansible defaults: `ansible/roles/[role]/defaults/main.yaml` (or `main.yml`)
- Ansible inventory: `ansible/inventory/`
- Look for: enabled features, sidecar containers (Redis is common), integrations
  (ingress, Prometheus monitoring, Authentik SSO/OIDC), persistence (Longhorn),
  env vars, resource limits, External Secrets pulling from 1Password

## Notes

- 14-day minimumReleaseAge on Renovate
- Sidecar containers are common (Redis, proxies, exporters)
- Authentik provides SSO for most services
- External Secrets Operator pulls secrets from 1Password
- Persistent storage via NFS and Synology iSCSI storage classes

## Actions Menu

The following actions MUST be included in the actions menu presented to the user
after evaluation. These are in addition to the default actions provided by the
skill (Merge, Review later, Close).

- **Deploy for testing** — Show for kubernetes, ansible, and terraform/opentofu
  updates. Read `.claude/rules/` for deployment instructions specific to each
  update type. For Kubernetes: `kubectl apply -k kubernetes/<app>/`. For
  Ansible: run `ansible-playbook` from the `ansible/` directory. For OpenTofu:
  run `tofu plan` then `tofu apply` from the `opentofu/` directory.
