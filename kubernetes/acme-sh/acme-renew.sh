#!/bin/sh
set -e

echo "Starting acme.sh renewal check..."

# Run cron to handle renewal and deployment for all certificates
echo "Running cron for renewal and deployment..."
/usr/local/bin/acme.sh --cron

echo "Renewal check completed successfully"
