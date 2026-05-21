#!/bin/sh

ACME_HOME="${ACME_HOME:-/acme.sh}"
ACME_SH="${ACME_SH:-/usr/local/bin/acme.sh}"
export HOME="$ACME_HOME"
UDMP_SSH_KEY_SOURCE="${UDMP_SSH_KEY_SOURCE:-/var/run/secrets/acme-sh-ssh/id_rsa}"
UDMP_SSH_DIR="${TMPDIR:-/tmp}/acme-sh-ssh"
UDMP_SSH_KEY="${UDMP_SSH_DIR}/id_rsa"

prepare_udmp_ssh_key() {
  if [ ! -r "$UDMP_SSH_KEY_SOURCE" ]; then
    echo "UDMP SSH key is not readable at ${UDMP_SSH_KEY_SOURCE}"
    return 1
  fi

  mkdir -p "$UDMP_SSH_DIR"
  cp "$UDMP_SSH_KEY_SOURCE" "$UDMP_SSH_KEY"
  chmod 0700 "$UDMP_SSH_DIR"
  chmod 0400 "$UDMP_SSH_KEY"

  export DEPLOY_SSH_CMD="ssh -T -i ${UDMP_SSH_KEY}"
}
