---
paths: ["ansible/**/*"]
---

# Ansible Usage

## Working Directory

**Always run ansible commands from the `ansible/` directory at the root of this
repository**

This ensures `ansible.cfg` is used for proper `roles_path` and other settings.

## Deploying Changes

Run `site.yaml` with a host limit to deploy changes:

```bash
cd ansible && ansible-playbook site.yaml -l <hostname>
```

Always limit to specific hosts when testing changes.

## File Extensions

**Use `.yaml` extension for YAML files**, not `.yml`
