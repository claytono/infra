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

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
