#!/bin/sh
set -e

. /scripts/acme-common.sh

echo "Starting acme.sh certificate management for UDM Pro"

# Register account with ZeroSSL (will succeed if not already registered)
echo "Ensuring account is registered with ZeroSSL..."
"$ACME_SH" --register-account \
  --eab-kid "$ACME_EAB_KID" \
  --eab-hmac-key "$ACME_EAB_HMAC_KEY" \
  -m clayton@oneill.net || true

# Check if certificate exists, issue if not
echo "Checking certificate status..."
if ! "$ACME_SH" --info -d udmp.oneill.net | grep "^Le_" > /dev/null; then
  echo "Certificate does not exist, issuing new certificate..."
  if ! "$ACME_SH" --issue --dns dns_cf -d udmp.oneill.net -d router.oneill.net -k 2048; then
    echo "Certificate issuance failed"
    exit 1
  fi
else
  echo "Certificate found"
fi

# Check if deploy hook is set, deploy if not
echo "Checking deploy hook status..."
if ! "$ACME_SH" --info -d udmp.oneill.net | grep "^Le_DeployHook=" > /dev/null; then
  echo "Deploy hook not set, configuring SSH deployment..."

  prepare_udmp_ssh_key

  # Set up SSH deploy environment variables
  export DEPLOY_SSH_USER="root"
  export DEPLOY_SSH_SERVER="udmp.oneill.net"

  # Use UnifiOS standard paths (as per official unifi deploy hook)
  export DEPLOY_SSH_FULLCHAIN="/data/unifi-core/config/unifi-core.crt"
  export DEPLOY_SSH_KEYFILE="/data/unifi-core/config/unifi-core.key"

  # Single-line: acme.sh cannot persist multi-line values in domain.conf
  export DEPLOY_SSH_REMOTE_CMD="cd /data/unifi-core/config/; [ -f unifi-core.crt ] && [ ! -f unifi-core_original.crt ] && cp unifi-core.crt unifi-core_original.crt; [ -f unifi-core.key ] && [ ! -f unifi-core_original.key ] && cp unifi-core.key unifi-core_original.key; chmod 600 unifi-core.key; chown root:root unifi-core.*; systemctl restart unifi-core"
  export DEPLOY_SSH_MULTI_CALL="yes"

  # Deploy certificate via SSH
  if ! "$ACME_SH" --deploy -d udmp.oneill.net --deploy-hook ssh; then
    echo "Certificate deployment failed"
    exit 1
  fi
  echo "Certificate deployed successfully"
else
  echo "Deploy hook already configured"
fi

echo "Certificate setup completed successfully"
