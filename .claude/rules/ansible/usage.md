---
paths: ["ansible/**/*"]
---

# Ansible Usage

## Working Directory

**Always run ansible commands from the `ansible/` directory at the root of this repository**

This ensures `ansible.cfg` is used for proper `roles_path` and other settings.

## File Extensions

**Use `.yaml` extension for YAML files**, not `.yml`
