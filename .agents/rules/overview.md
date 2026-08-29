# Development Environment

This repository requires a Nix development shell with all required tools (Helm,
kubectl, pre-commit hooks, linting tools).

Service credentials (API keys, passwords, tokens) are automatically loaded into
the environment via direnv. See [tooling/secrets.md](tooling/secrets.md).
