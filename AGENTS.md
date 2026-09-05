# Homelab Infrastructure Repository

## Overview

This is a homelab infrastructure monorepo managed with automation,
repeatability, and infrastructure as code principles.

**Detailed documentation is organized in [.agents/rules/](.agents/rules/)**
including:

- **[overview.md](.agents/rules/overview.md)** - Development environment (Nix)
- **[workflow.md](.agents/rules/workflow.md)** - Development workflow principles
- **[backups.md](.agents/rules/backups.md)** - Restic backup architecture for
  hosts and Kubernetes storage
- **[kubernetes/](.agents/rules/kubernetes/)** - Kubernetes deployment patterns
  (GitOps, Helm rendering, External Secrets)
- **[ansible/](.agents/rules/ansible/)** - Ansible usage guidelines
- **[opentofu/](.agents/rules/opentofu/)** - OpenTofu/Terraform usage
- **[tooling/](.agents/rules/tooling/)** - Pre-commit hooks, CI/CD, and
  Authentik integration
- **[integrations/](.agents/rules/integrations/)** - Home Assistant and other
  integrations
- **[integrations/synology.md](.agents/rules/integrations/synology.md)** -
  Synology troubleshooting resources

## Architecture Principles

- **GitOps for Kubernetes**: We test locally first with `kubectl apply -k`
  before creating PRs for ArgoCD deployment
- **Kubernetes service access**: Use configured ingress by default. Use
  `kubectl port-forward` only when direct service access is explicitly required
- **Infrastructure as code**: All changes tracked in version control
- **Automation first**: Prefer scripts and tooling over manual steps
