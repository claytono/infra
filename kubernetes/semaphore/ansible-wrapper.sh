#!/bin/bash
# Semaphore-specific ansible wrapper
# Sets Semaphore UI integration environment variables

export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_LOAD_CALLBACK_PLUGINS=1
export ANSIBLE_STDOUT_CALLBACK=yaml

# If we find ansible/ansible.cfg in the current directory, cd into ansible/
# This ensures Ansible picks up the repository's ansible.cfg
if [ -f "ansible/ansible.cfg" ]; then
  echo "Found ansible/ansible.cfg, changing directory to ansible/"
  cd ansible || exit 1

  # Symlink the vault password file to where ansible.cfg expects it
  # The ansible.cfg expects: vault_password_file=ansible-vault-password
  if [ -f /secrets/ansible-vault/ansible-vault-password ] && [ ! -f ansible-vault-password ]; then
    ln -s /secrets/ansible-vault/ansible-vault-password ansible-vault-password
    echo "Symlinked vault password file"
  fi
fi

# Detect which ansible command we're wrapping from $0
TOOL_NAME=$(basename "$0")

echo "Running $TOOL_NAME via ansible-wrapper.sh"
echo "Args: $*"
# Exec the nix-provided ansible binary from /ansible-bins
exec "/ansible-bins/$TOOL_NAME" "$@"
