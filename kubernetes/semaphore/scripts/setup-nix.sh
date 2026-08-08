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

# Preserve the tools from the repository's Nix environment before init-tools.sh
# replaces Semaphore's bundled Ansible executables with wrappers.
NIX_ANSIBLE=$(command -v ansible) || {
  echo "ERROR: ansible not found in the repository Nix environment" >&2
  exit 1
}
NIX_ENV_BIN=$(dirname "$NIX_ANSIBLE")
case "$NIX_ENV_BIN" in
  /nix/store/*-python3-*-env/bin) ;;
  *)
    echo "ERROR: ansible resolved outside the repository Nix environment: $NIX_ANSIBLE" >&2
    exit 1
    ;;
esac

mkdir -p /infra/ansible-bins
for tool in python3 ansible ansible-playbook ansible-galaxy ansible-vault; do
  tool_path="$NIX_ENV_BIN/$tool"
  if [ ! -x "$tool_path" ]; then
    echo "ERROR: $tool not found in the repository Nix environment" >&2
    exit 1
  fi
  ln -sf "$tool_path" "/infra/ansible-bins/$tool"
done

echo "Nix setup complete"
