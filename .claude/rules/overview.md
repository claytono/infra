# Development Environment

This repository requires a Nix development shell with all required tools (Helm, kubectl, pre-commit hooks, linting tools).

If a command fails due to missing tools, run it via `nix develop -c <command>` to execute in the Nix environment.
