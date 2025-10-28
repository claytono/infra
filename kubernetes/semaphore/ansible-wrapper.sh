#!/bin/bash
# Semaphore-specific ansible wrapper
# Sets Semaphore UI integration environment variables

export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_LOAD_CALLBACK_PLUGINS=1
export ANSIBLE_STDOUT_CALLBACK=yaml

# ARA (Ansible Run Analysis) configuration
export ARA_API_CLIENT=http
export ARA_API_SERVER=https://ara.k.oneill.net
export ARA_API_TIMEOUT=30
# Use threading for PostgreSQL backend to avoid SSL connection reuse issues
export ARA_CALLBACK_THREADS=4
export ARA_API_USERNAME=ara

# Read ARA API password from mounted secret
if [ -f /secrets/ara/password ]; then
  export ARA_API_PASSWORD=$(cat /secrets/ara/password)
fi

# Set CA bundle for Python requests library
export REQUESTS_CA_BUNDLE=/etc/ssl/cert.pem

# Load direnv environment to get nix Python in PATH
if [ -f /infra/.envrc ]; then
  eval "$(cd /infra && direnv export bash 2>/dev/null)"
fi

# Enable ARA callback and action plugins using nix Python environment
NIX_PYTHON=$(find /nix/store -maxdepth 1 -name "*python3-*-env" -type d 2>/dev/null | head -1)/bin/python3
if [ ! -x "$NIX_PYTHON" ]; then
  echo "WARNING: Could not find executable nix Python environment at $NIX_PYTHON" >&2
  echo "ARA integration will be disabled" >&2
  NIX_PYTHON=""
fi

if [ -n "$NIX_PYTHON" ]; then
  ARA_CALLBACK_PATH=$("$NIX_PYTHON" -c "import ara.setup; print(ara.setup.callback_plugins)" 2>&1 || true)
  if [ -n "$ARA_CALLBACK_PATH" ] && [[ "$ARA_CALLBACK_PATH" != *"Error"* ]] && [[ "$ARA_CALLBACK_PATH" != *"Traceback"* ]]; then
    export ANSIBLE_CALLBACK_PLUGINS="$ARA_CALLBACK_PATH"
    export ANSIBLE_CALLBACKS_ENABLED=ara_default
  fi

  # Enable ARA action plugins for ara_playbook usage in playbooks
  ARA_ACTION_PATH=$("$NIX_PYTHON" -c "import ara.setup; print(ara.setup.action_plugins)" 2>&1 || true)
  if [ -n "$ARA_ACTION_PATH" ] && [[ "$ARA_ACTION_PATH" != *"Error"* ]] && [[ "$ARA_ACTION_PATH" != *"Traceback"* ]]; then
    export ANSIBLE_ACTION_PLUGINS="$ARA_ACTION_PATH"
  fi
fi

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
