#!/bin/sh
set -eu

echo "Installing kubectl, wget, coreutils, and jq..."
apk add --no-cache curl wget coreutils jq
curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

echo "Checking Velero backup status..."

# Calculate 48 hours ago in epoch seconds
NOW_EPOCH=$(date +%s)
CUTOFF_EPOCH=$(( NOW_EPOCH - (48 * 3600) ))

# Get all backups sorted by creation time
BACKUPS_JSON=$(kubectl get backups.velero.io -n velero \
  --sort-by=.metadata.creationTimestamp \
  --request-timeout=30s \
  -o json)

# Find the most recent completed backup within the past 48 hours
FOUND_BACKUP=""
BACKUP_COUNT=$(echo "$BACKUPS_JSON" | jq -r '.items | length')

if [ "$BACKUP_COUNT" -eq 0 ]; then
  echo "ERROR: No backups found"
  wget -q -O- "https://hc-ping.com/${HEALTHCHECK_PING_KEY}/fail" \
    --post-data "No backups found"
  exit 1
fi

echo "Checking $BACKUP_COUNT backups for completed backup within past 48 hours..."

# Iterate through backups from newest to oldest
for i in $(seq $((BACKUP_COUNT - 1)) -1 0); do
  BACKUP_NAME=$(echo "$BACKUPS_JSON" | jq -r ".items[$i].metadata.name")
  BACKUP_STATUS=$(echo "$BACKUPS_JSON" | jq -r ".items[$i].status.phase")
  BACKUP_CREATED=$(echo "$BACKUPS_JSON" | jq -r ".items[$i].metadata.creationTimestamp")

  # Convert creation time to epoch
  BACKUP_EPOCH=$(date -u -d "$BACKUP_CREATED" +%s)
  AGE_HOURS=$(( (NOW_EPOCH - BACKUP_EPOCH) / 3600 ))

  echo "  $BACKUP_NAME: status=$BACKUP_STATUS, age=${AGE_HOURS}h"

  # If backup is older than 48 hours, stop checking
  if [ "$BACKUP_EPOCH" -lt "$CUTOFF_EPOCH" ]; then
    echo "  (stopping - older than 48h)"
    break
  fi

  # If backup is completed and within 48 hours, we found it!
  if [ "$BACKUP_STATUS" = "Completed" ]; then
    FOUND_BACKUP="$BACKUP_NAME"
    FOUND_AGE="$AGE_HOURS"
    echo "  ✓ Found completed backup!"
    break
  fi
done

# Check if we found a successful backup
if [ -z "$FOUND_BACKUP" ]; then
  echo "ERROR: No completed backup found in past 48 hours"
  wget -q -O- "https://hc-ping.com/${HEALTHCHECK_PING_KEY}/fail" \
    --post-data "No completed backup found in past 48 hours"
  exit 1
fi

# Success!
echo "SUCCESS: Backup $FOUND_BACKUP completed successfully (${FOUND_AGE}h ago)"
wget -q -O- "https://hc-ping.com/${HEALTHCHECK_PING_KEY}" \
  --post-data "Backup: $FOUND_BACKUP completed successfully (${FOUND_AGE}h ago)"
