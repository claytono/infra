#!/bin/sh
set -e

DOMAIN="fs2.oneill.net"
ACME_HOME="/acme.sh"
ACME_SH="/usr/local/bin/acme.sh"
LIVE_SYNO_HOSTNAME="${SYNO_Hostname:-}"
LIVE_SYNO_PORT="${SYNO_Port:-}"

get_domain_info() {
  "$ACME_SH" --home "$ACME_HOME" --info -d "$DOMAIN"
}

get_local_cert_dir() {
  domain_conf="$(get_domain_info | sed -n 's/^DOMAIN_CONF=//p')"
  if [ -z "$domain_conf" ]; then
    return 1
  fi

  dirname "$domain_conf"
}

get_cert_fingerprint() {
  cert_path="$1"
  openssl x509 -in "$cert_path" -noout -fingerprint -sha256 | cut -d= -f2
}

get_live_fingerprint() {
  live_chain="$(
    openssl s_client \
      -connect "${LIVE_SYNO_HOSTNAME}:${LIVE_SYNO_PORT}" \
      -servername "${LIVE_SYNO_HOSTNAME}" \
      </dev/null 2>/dev/null || true
  )"

  if [ -z "$live_chain" ]; then
    return 1
  fi

  printf "%s" "$live_chain" |
    openssl x509 -noout -fingerprint -sha256 2>/dev/null |
    cut -d= -f2
}

echo "Starting acme.sh certificate management for ${DOMAIN}"

# Register account with ZeroSSL (will succeed if not already registered)
echo "Ensuring account is registered with ZeroSSL..."
"$ACME_SH" --home "$ACME_HOME" --register-account \
  --eab-kid "$ACME_EAB_KID" \
  --eab-hmac-key "$ACME_EAB_HMAC_KEY" \
  -m clayton@oneill.net || true

# Check if certificate exists, issue if not
echo "Checking certificate status..."
if ! get_domain_info | grep "^Le_" > /dev/null; then
  echo "Certificate does not exist, issuing new certificate..."
  if ! "$ACME_SH" --home "$ACME_HOME" --issue --dns dns_cf -d "$DOMAIN"; then
    echo "Certificate issuance failed"
    exit 1
  fi
else
  echo "Certificate found"
fi

cert_dir="$(get_local_cert_dir)"
local_cert="${cert_dir}/${DOMAIN}.cer"
local_fingerprint="$(get_cert_fingerprint "$local_cert")"
echo "Local certificate fingerprint: ${local_fingerprint}"

deploy_needed=0

# Check if deploy hook is set, deploy if not
echo "Checking deploy hook status..."
if ! get_domain_info | grep "^Le_DeployHook=.*synology_dsm" > /dev/null; then
  echo "Deploy hook is not configured for Synology"
  deploy_needed=1
else
  echo "Deploy hook already configured"
fi

live_fingerprint="$(get_live_fingerprint || true)"
if [ -z "$live_fingerprint" ]; then
  echo "Unable to read live certificate from ${LIVE_SYNO_HOSTNAME}:${LIVE_SYNO_PORT}"
  deploy_needed=1
else
  echo "Live certificate fingerprint: ${live_fingerprint}"
  if [ "$live_fingerprint" != "$local_fingerprint" ]; then
    echo "Live certificate does not match local acme certificate"
    deploy_needed=1
  else
    echo "Live certificate already matches local acme certificate"
  fi
fi

if [ "$deploy_needed" -eq 1 ]; then
  echo "Deploying certificate to Synology..."
  # Synology recovery needs to work even when DSM is already serving an expired cert.
  if ! "$ACME_SH" --home "$ACME_HOME" --deploy --insecure -d "$DOMAIN" --deploy-hook synology_dsm; then
    echo "Certificate deployment failed"
    exit 1
  fi

  live_fingerprint="$(get_live_fingerprint || true)"
  echo "Live certificate fingerprint after deploy: ${live_fingerprint:-<unavailable>}"
  if [ -z "$live_fingerprint" ] || [ "$live_fingerprint" != "$local_fingerprint" ]; then
    echo "Certificate deployment did not reconcile the live Synology certificate"
    exit 1
  fi

  echo "Certificate deployed successfully"
fi

echo "Certificate setup completed successfully"
