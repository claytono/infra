#!/bin/bash
set -euo pipefail

# Source Nix profile, error if not found
if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
else
  echo "ERROR: Nix profile script not found at /nix/var/nix/profiles/default/etc/profile.d/nix.sh" >&2
  exit 1
fi

export PATH="/nix/var/nix/profiles/default/bin:$PATH"

exec nix develop --command "$@"
