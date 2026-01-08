#!/bin/bash
set -xeu -o pipefail

# Source setup script from ConfigMap (does file copy, nix install, eval nix env)
source /config-map/scripts__setup-nix.sh

cd /infra

# Overwrite semaphore's default tofu with our nix version (requires root)
ln -sf "$(which tofu)" /usr/local/bin/tofu

ansible --version
tofu --version

# Replace Semaphore's bundled ansible with our wrapper pointing to nix ansible
ANSIBLE_VERSION=$(find /opt/semaphore/apps/ansible -maxdepth 1 -type d -name '[0-9]*' 2>/dev/null | sort -V | tail -1)
if [ -z "$ANSIBLE_VERSION" ]; then
  echo "ERROR: Could not find Ansible version directory in /opt/semaphore/apps/ansible"
  exit 1
fi

ANSIBLE_VENV="$ANSIBLE_VERSION/venv/bin"

if [ -d "$ANSIBLE_VENV" ]; then
  for tool in ansible ansible-playbook ansible-galaxy ansible-vault; do
    if [ -f "$ANSIBLE_VENV/$tool" ]; then
      rm -f "$ANSIBLE_VENV/$tool"
      ln -s /infra/scripts/ansible-wrapper.sh "$ANSIBLE_VENV/$tool"
    fi
  done
else
  echo "ERROR: Ansible venv directory not found at $ANSIBLE_VENV"
  exit 1
fi

export PATH="/infra/bin:$ANSIBLE_VENV:$PATH"

# Fix ownership of persistent workdir (may have root-owned files from previous runs)
chown -R semaphore /tmp/semaphore

# Configure git safe.directory for the semaphore user
su-exec semaphore git config --global --add safe.directory '*'

# Drop privileges to semaphore user for the server
exec su-exec semaphore /usr/local/bin/server-wrapper
