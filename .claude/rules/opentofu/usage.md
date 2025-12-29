---
paths: ["opentofu/**/*"]
---

# OpenTofu Usage

## Working Directory

Run `tofu apply` in the `opentofu/` directory to apply infrastructure changes (DNS, healthchecks, etc.)

## Initialization

**Never use `tofu init -upgrade`** - it updates providers beyond the lock file.

Use plain `tofu init` instead.
