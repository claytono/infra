# Homelab Infrastructure Repository

## Overview

This is a homelab infrastructure monorepo managed with automation, repeatability, and infrastructure as code principles.

**Detailed documentation is organized in [.claude/rules/](.claude/rules/)** including:

- **[overview.md](.claude/rules/overview.md)** - Development environment (Nix)
- **[workflow.md](.claude/rules/workflow.md)** - Development workflow principles
- **[kubernetes/](.claude/rules/kubernetes/)** - Kubernetes deployment patterns (GitOps, Helm rendering, External Secrets)
- **[ansible/](.claude/rules/ansible/)** - Ansible usage guidelines
- **[opentofu/](.claude/rules/opentofu/)** - OpenTofu/Terraform usage
- **[tooling/](.claude/rules/tooling/)** - Pre-commit hooks, CI/CD, and Authentik integration
- **[integrations/](.claude/rules/integrations/)** - Home Assistant and other integrations

## Architecture Principles

- **GitOps for Kubernetes**: ArgoCD deploys from main branch, but test locally first
- **Infrastructure as code**: All changes tracked in version control
- **Automation first**: Prefer scripts and tooling over manual steps
