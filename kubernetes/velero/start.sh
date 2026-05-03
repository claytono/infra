#!/bin/sh
set -e

HETZNER_PASS="$(cat /secrets/hetzner_pass)"
ENCRYPTION_PASSWORD="$(cat /secrets/encryption_password)"

OBSCURED_HETZNER_PASS="$(rclone obscure "$HETZNER_PASS")"
OBSCURED_ENCRYPTION_PASSWORD="$(rclone obscure "$ENCRYPTION_PASSWORD")"

cat > /tmp/rclone.conf <<EOF
[hetzner]
type = webdav
url = $(cat /secrets/hetzner_url)
vendor = other
user = $(cat /secrets/hetzner_user)
pass = ${OBSCURED_HETZNER_PASS}

[hetzner_velero]
type = crypt
remote = hetzner:
filename_encryption = standard
directory_name_encryption = true
password = ${OBSCURED_ENCRYPTION_PASSWORD}
EOF

export RCLONE_CONFIG=/tmp/rclone.conf

echo "Creating encrypted 'data' directory via Hetzner WebDAV..."
rclone mkdir hetzner_velero:/data
echo "✓ Created encrypted data directory"

echo "Waiting for directory to be visible..."
sleep 3

for i in 1 2 3; do
    if rclone lsd hetzner_velero: 2>/dev/null | grep -q "data"; then
        echo "✓ Verified 'data' bucket directory exists and is visible via hetzner_velero"
        break
    fi
    echo "⚠ Waiting for 'data' directory to be visible via hetzner_velero (attempt $i/3)..."
    sleep 2
done

if ! rclone lsd hetzner_velero: 2>/dev/null | grep -q "data"; then
    echo "✗ ERROR: 'data' directory not visible via hetzner_velero after retries"
    echo "Directory listing (encrypted names):"
    rclone lsd hetzner_velero: 2>&1 || echo "Failed to list directories"
    exit 1
fi

# Note: --no-cleanup flag is added via deployment args to prevent automatic cleanup of empty dirs
exec rclone "$@"
