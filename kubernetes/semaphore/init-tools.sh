#!/bin/bash
set -e

apk add direnv

echo "Installing nix package manager..."

curl -fsSL https://install.determinate.systems/nix \
  | sh -s -- install linux --no-confirm --init none

# Source nix
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# Add nix profile to PATH
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Set up direnv hook for bash
eval "$(direnv hook bash)"

git clone --depth=1 https://github.com/claytono/infra /infra
cd /infra

direnv allow .

# Load the direnv environment
eval "$(direnv export bash)"

echo "Ansible version:"
ansible --version

echo "OpenTofu version:"
tofu --version

echo "Replacing image binaries with nix-provided versions..."

# Replace OpenTofu - symlink to /usr/local/bin
if [ -f /usr/local/bin/tofu ]; then
  rm -f /usr/local/bin/tofu
  ln -s "$(which tofu)" /usr/local/bin/tofu
  echo "Replaced tofu at /usr/local/bin/tofu"
fi

# Create /ansible-bins directory and symlink ansible binaries from Python environment
# Find the nix Python environment (not system python or venv)
PYTHON_ENV_DIR=$(find /nix/store -maxdepth 1 -name "*python3-*-env" -type d 2>/dev/null | head -1)
if [ -z "$PYTHON_ENV_DIR" ] || [ ! -d "$PYTHON_ENV_DIR" ]; then
  echo "ERROR: Could not find nix Python environment in /nix/store" >&2
  exit 1
fi
PYTHON_ENV_BIN="$PYTHON_ENV_DIR/bin"

mkdir -p /ansible-bins
for tool in ansible ansible-playbook ansible-galaxy ansible-vault; do
  if [ -x "$PYTHON_ENV_BIN/$tool" ]; then
    ln -sf "$PYTHON_ENV_BIN/$tool" "/ansible-bins/$tool"
    echo "Symlinked $tool from Python environment: $PYTHON_ENV_BIN/$tool"
  else
    echo "WARNING: $tool not found in Python environment at $PYTHON_ENV_BIN"
  fi
done

# Point ansible venv binaries to wrapper script
# Dynamically find the latest Ansible version directory
ANSIBLE_VERSION=$(find /opt/semaphore/apps/ansible -maxdepth 1 -type d -name '[0-9]*' 2>/dev/null | sort -V | tail -1)
if [ -z "$ANSIBLE_VERSION" ]; then
  echo "ERROR: Could not find Ansible version directory in /opt/semaphore/apps/ansible"
  exit 1
fi

ANSIBLE_VENV="$ANSIBLE_VERSION/venv/bin"
echo "Found Ansible venv at: $ANSIBLE_VENV"

if [ -d "$ANSIBLE_VENV" ]; then
  for tool in ansible ansible-playbook ansible-galaxy ansible-vault; do
    if [ -f "$ANSIBLE_VENV/$tool" ]; then
      rm -f "$ANSIBLE_VENV/$tool"
      ln -s /scripts/ansible-wrapper.sh "$ANSIBLE_VENV/$tool"
      echo "Replaced $tool in ansible venv with wrapper"
    fi
  done
else
  echo "ERROR: Ansible venv directory not found at $ANSIBLE_VENV"
  exit 1
fi

echo "Starting Semaphore server..."

# Prepend ansible venv to PATH so wrapper scripts are found first
export PATH="$ANSIBLE_VENV:$PATH"

# Exec into the original server wrapper
exec /usr/local/bin/server-wrapper
