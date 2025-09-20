# Homelab Infrastructure

This is my personal infrastructure monorepo for managing my homelab environment.

## Structure

- **`ansible/`** - System configuration and provisioning
- **`esphome/`** - ESPHome device configurations and build tools
- **`kubernetes/`** - Kubernetes application manifests
- **`opentofu/`** - Cloud infrastructure (DNS, etc.)
- **`scripts/`** - Automation and tooling

## Development Environment

```bash
# Enter development environment
nix develop

# Install pre-commit hooks
pre-commit install

# Run linting
./scripts/lint
```

This repository is designed specifically for my environment and use cases.
