---
paths: ["opentofu/**/*"]
---

# OpenTofu Usage

## Working Directory

Run `tofu apply` in the `opentofu/` directory to apply infrastructure changes
(DNS, healthchecks, etc.)

## Initialization

**Never use `tofu init -upgrade`** - it updates providers beyond the lock file.

Use plain `tofu init` instead.

## Minimize Plan/Apply Runs

`tofu plan` and `tofu apply` trigger 1Password authentication prompts for the
user. Avoid running them repeatedly — save output to a file and reference it
instead of re-running.

```bash
tofu plan -no-color > /tmp/tofu-plan-output.txt 2>&1
```
