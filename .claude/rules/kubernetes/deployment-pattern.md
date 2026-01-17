---
paths: ["kubernetes/**/*"]
---

# Kubernetes Application Deployment Pattern

**Critical**: This repository uses a GitOps approach with pre-rendered Helm templates, NOT direct Helm installations.

## Application Structure

Each Kubernetes application follows this structure:

```text
app-name/
├── Chart.yaml          # Helm chart dependencies with specific versions
├── values.yaml         # Chart configuration values
├── kustomization.yaml  # Lists all resources including pre-rendered templates
├── helm/              # Pre-rendered Helm template YAML files
│   └── templates/
├── render             # Script to generate helm/ directory
└── namespace.yaml     # Application namespace (if needed)
```

## Helm Chart Workflow

1. **Define Dependencies**: Update `Chart.yaml` with chart name, version, and repository
2. **Configure Values**: Set application configuration in `values.yaml`
3. **Render Templates**: Run `./render` script to generate static YAML in `helm/` directory
4. **Reference in Kustomize**: List rendered templates in `kustomization.yaml` resources
5. **Deploy**: ArgoCD deploys the kustomized manifests (note `argoManaged: 'true'` annotation is set via kustomize)

## Deployment and Testing

**Always use kustomize for deployments:**

```bash
kubectl apply -k <directory>      # Deploy using kustomize (standard approach)
```

Do NOT use `kubectl apply -f <file>` directly.

**Testing workflow:**
- Apply changes locally with `kubectl apply -k <directory>` to test during development
- ArgoCD manages deployments from main branch, but apply locally first to verify changes work before committing
- For cronjobs, trigger a manual run with: `kubectl create job --from=cronjob/<name> <test-name>`

## ConfigMap and Secret Reload

Most workloads have [Reloader](https://github.com/stakater/Reloader) configured
via the `reloader.stakater.com/auto: "true"` pod annotation. This automatically
triggers a rolling restart when referenced ConfigMaps or Secrets change.

**Implications:**

- After `kubectl apply`, pods restart automatically—no manual deletion needed
- Changes propagate within ~30 seconds of ConfigMap update
- Not all workloads have this; check pod annotations if restart doesn't occur
- If a workload is missing Reloader and would benefit from it, ask about adding
  the annotation

## Rendering Helm Charts

Render scripts for Kubernetes applications are standardized across this repository. Refer to [helm-rendering.md](./helm-rendering.md) for the canonical render script pattern, helper usage, and best practices that apply to all applications.
