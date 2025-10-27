#!/bin/sh
set -e

# Get plain-text password from secret
PLAIN_PASSWORD="$(cat /secrets/encryption_password)"

# Obscure it using rclone
OBSCURED_PASSWORD="$(rclone obscure "$PLAIN_PASSWORD")"

# Create rclone.conf with obscured password
cat > /tmp/rclone.conf <<EOF
[b2]
type = b2
account = $(cat /secrets/b2_account)
key = $(cat /secrets/b2_key)

[crypt_b2]
type = crypt
remote = b2:cmo-velero
directory_name_encryption = true
password = ${OBSCURED_PASSWORD}

[out_s3]
type = s3
provider = Other
access_key_id = $(cat /secrets/b2_account)
secret_access_key = $(cat /secrets/b2_key)
endpoint = https://s3.us-west-000.backblazeb2.com
region = us-west-000

[crypt_out_s3]
type = crypt
remote = out_s3:cmo-velero
directory_name_encryption = true
password = ${OBSCURED_PASSWORD}
EOF

# Export rclone config location
export RCLONE_CONFIG=/tmp/rclone.conf

# Create the "data" directory in the B2 bucket using B2 native API with encryption
# The S3 API tries to create buckets which requires account-level permissions
# The B2 native API properly handles directory/file creation within the bucket
# We use crypt_b2 (not crypt_out_s3) to ensure directory names are encrypted
# This allows Velero to access bucket "data" with prefix "velero"
echo "Creating encrypted 'data' directory via B2 native API..."
echo "Velero encrypted backup marker file" > /tmp/.velero-marker
rclone copy /tmp/.velero-marker crypt_b2:/data/.velero-marker
rm -f /tmp/.velero-marker
echo "✓ Created encrypted data directory with marker file"

# Wait for B2 eventual consistency to propagate the directory
echo "Waiting for directory to be visible..."
sleep 3

# Verify via crypt_b2 (encrypted view) - this is the remote we'll serve from
# We can't verify via out_s3 because directory name encryption is enabled
for i in 1 2 3; do
    if rclone lsd crypt_b2: 2>/dev/null | grep -q "data"; then
        echo "✓ Verified 'data' bucket directory exists and is visible via crypt_b2"
        break
    fi
    echo "⚠ Waiting for 'data' directory to be visible via crypt_b2 (attempt $i/3)..."
    sleep 2
done

# Final verification - fail if directory still not visible via crypt remote
if ! rclone lsd crypt_b2: 2>/dev/null | grep -q "data"; then
    echo "✗ ERROR: 'data' directory not visible via crypt_b2 after retries"
    echo "Directory listing (encrypted names):"
    rclone lsd crypt_b2: 2>&1 || echo "Failed to list directories"
    exit 1
fi

# Exec rclone serve with remaining arguments
# Note: --no-cleanup flag is added via deployment args to prevent automatic cleanup of empty dirs
exec rclone "$@"
