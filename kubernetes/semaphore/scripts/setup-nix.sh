#!/bin/bash
set -xeu -o pipefail

# Clear leftover state from previous runs (emptyDirs persist across container restarts in the same pod)
rm -rf /infra/*

# Copy config files from ConfigMap, decoding --- to /
for f in /config-map/*; do
  dest="/infra/$(basename "$f" | sed 's|---|/|g')"
  echo "Copying $f -> $dest"
  mkdir -p "$(dirname "$dest")"
  cp -L "$f" "$dest"
done

apk add --no-cache curl xz su-exec

rm -rf /nix/*
chmod 755 /nix

curl -fL https://install.determinate.systems/nix \
  | sh -s -- install linux --no-confirm --init none

. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

cd /infra
eval "$(nix print-dev-env .#semaphore)"

# Create ansible-bins directory and populate with symlinks
PYTHON_ENV_DIR=$(find /nix/store -maxdepth 1 -name "*python3-*-env" -type d 2>/dev/null | head -1)
if [ -z "$PYTHON_ENV_DIR" ]; then
  echo "ERROR: Could not find Python environment in /nix/store" >&2
  exit 1
fi
mkdir -p /infra/ansible-bins
for tool in ansible ansible-playbook ansible-galaxy ansible-vault; do
  if [ -x "$PYTHON_ENV_DIR/bin/$tool" ]; then
    ln -sf "$PYTHON_ENV_DIR/bin/$tool" "/infra/ansible-bins/$tool"
  fi
done

echo "Nix setup complete"
