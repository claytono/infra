# AGENTS.md

## Overview

This is a homelab infrastructure monorepo.  Solutions should be appropriate for
that sort of environment.   We do not manually hack things together, but instead
we focus on automation, repeatability, and infrastructure as code.

## Development Workflow

Development happens locally with direct application to the homelab infrastructure.
When making changes:

1. **Kubernetes changes**: Apply directly with `kubectl apply -k <directory>` to
   test during development. ArgoCD manages deployments from main branch, but we
   apply locally first to verify changes work before committing.
2. **OpenTofu changes**: Run `tofu apply` in the `opentofu/` directory to apply
   infrastructure changes (DNS, healthchecks, etc.)
3. **Ansible changes**: Run `ansible-playbook site.yaml` from `ansible/` directory
   (or use `--limit` to target specific hosts)
4. **Test changes**: Verify the changes work before committing. For cronjobs, you
   can trigger a manual run with `kubectl create job --from=cronjob/<name> <test-name>`

Always apply changes and verify they work - do not stop after writing code to ask
for permission to deploy.

## Repository Structure


- **`ansible/`** - System configuration and provisioning
- **`kubernetes/`** - Kubernetes application manifests using GitOps
- **`opentofu/`** - Cloud infrastructure (DNS, etc.)
- **`scripts/`** - Automation and tooling

## Development Environment

This repository requires a Nix development shell with all required tools (Helm,
kubectl, pre-commit hooks, linting tools). If pre-commit hooks fail due to
missing tools (yamlfix, yamllint, kubeconform), this indicates we're not in the
nix develop environment - ask the user to restart Claude Code in the nix develop
environment.

## Kubernetes Application Deployment Pattern

**Critical**: This repository uses a GitOps approach with pre-rendered Helm
templates, NOT direct Helm installations.

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

### Helm Chart Workflow

1. **Define Dependencies**: Update `Chart.yaml` with chart name, version, and
   repository
2. **Configure Values**: Set application configuration in `values.yaml`
3. **Render Templates**: Run `./render` script to generate static YAML in
   `helm/` directory
4. **Reference in Kustomize**: List rendered templates in `kustomization.yaml`
   resources
5. **Deploy**: ArgoCD deploys the kustomized manifests (note
   `argoManaged: 'true'` annotations is set via kustomize)

### Rendering Helm Charts

Each application directory contains a `render` script that:

- Sources the `/kubernetes/scripts/chart-version` helper functions
- Uses `helm_template` function to render charts with correct repository/version
- Outputs static YAML files to `helm/` directory
- May perform post-processing (removing deprecated resources, etc.)

Example render script pattern:

```bash
#!/bin/bash
source "$BASEDIR/../scripts/chart-version"
rm -rf helm tmp && mkdir tmp helm
helm_template release-name chart-name --values values.yaml \
  --namespace namespace --output-dir tmp
mv tmp/*/* helm && rmdir tmp/*
```

**Never run `helm install` or `helm upgrade` directly** - all deployments use
pre-rendered manifests.

## External Secrets Integration

Applications use External Secrets Operator with:

- `ClusterSecretStore` named `production` for secret retrieval
- External secrets defined in `externalsecret.yaml` files
- Secrets referenced by name in application manifests

## Common Commands

### Linting and Validation

```bash
./scripts/lint                    # Run pre-commit hooks on changed files
./scripts/lint --all-files        # Run all hooks on all files
./scripts/lint shellcheck         # Run specific hook
```

### Kubernetes Deployment

```bash
kubectl apply -k <directory>      # Deploy using kustomize (standard approach)
```

### Helm Template Rendering

```bash
cd kubernetes/app-name && ./render    # Render Helm templates for specific app
```

## Pre-commit Hooks

The repository uses extensive pre-commit validation including:

- YAML formatting (yamlfix) and validation (yamllint)
- Kubernetes manifest validation (kubeconform)
- Shell script validation (shellcheck, shfmt)
- Ansible linting
- Terraform/OpenTofu validation

Rendered Helm templates in `kubernetes/*/helm/` directories are excluded from
most hooks.

## CI/CD Integration

GitHub Actions automatically:

- Renders Helm charts when `Chart.yaml` or `values.yaml` files change
- Commits rendered manifests back to pull requests
- Validates manifests haven't diverged on main branch
- Uses Nix development environment for consistent tooling

## Authentik

When setting up Authentik for new services, you must run ak-tool to provision
them via terraform. Run ak-tool --help for details.
