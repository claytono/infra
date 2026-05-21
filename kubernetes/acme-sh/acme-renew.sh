#!/bin/sh
set -e

. /scripts/acme-common.sh

echo "Starting acme.sh renewal check..."

prepare_udmp_ssh_key

# Run cron to handle renewal and deployment for all certificates
echo "Running cron for renewal and deployment..."
"$ACME_SH" --cron

echo "Renewal check completed successfully"
