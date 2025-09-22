#!/bin/sh
set -e

echo "Starting acme.sh certificate management for fs2.oneill.net"

# Register account with ZeroSSL (will succeed if not already registered)
echo "Ensuring account is registered with ZeroSSL..."
/usr/local/bin/acme.sh --register-account \
  --eab-kid "$ACME_EAB_KID" \
  --eab-hmac-key "$ACME_EAB_HMAC_KEY" \
  -m clayton@oneill.net || true

# Check if certificate exists, issue if not
echo "Checking certificate status..."
if ! /usr/local/bin/acme.sh --info -d fs2.oneill.net | grep "^Le_" > /dev/null; then
  echo "Certificate does not exist, issuing new certificate..."
  if ! /usr/local/bin/acme.sh --issue --dns dns_aws -d fs2.oneill.net; then
    echo "Certificate issuance failed"
    exit 1
  fi
else
  echo "Certificate found"
fi

# Check if deploy hook is set, deploy if not
echo "Checking deploy hook status..."
if ! /usr/local/bin/acme.sh --info -d fs2.oneill.net | grep "^Le_DeployHook=" > /dev/null; then
  echo "Deploy hook not set, deploying certificate..."
  if ! /usr/local/bin/acme.sh --deploy -d fs2.oneill.net --deploy-hook synology_dsm; then
    echo "Certificate deployment failed"
    exit 1
  fi
  echo "Certificate deployed successfully"
else
  echo "Deploy hook already configured"
fi

echo "Certificate setup completed successfully"
