#!/bin/bash
set -euo pipefail

MOUNT_PATH="${MOUNT_PATH:-/mnt/test}"
STORAGE_TYPE="${STORAGE_TYPE:-unknown}"

echo "========================================="
echo "Cleaning up ${STORAGE_TYPE} volume"
echo "Mount path: ${MOUNT_PATH}"
echo "========================================="

# Show initial disk usage
echo "Initial disk usage:"
df -h "${MOUNT_PATH}"
du -sh "${MOUNT_PATH}" || true

# Delete all files
echo ""
echo "Deleting all files..."
if ! find "${MOUNT_PATH}" -mindepth 1 -delete 2>&1; then
    echo "ERROR: Failed to delete files" >&2
    echo "Mount point: ${MOUNT_PATH}" >&2
    ls -la "${MOUNT_PATH}" || true
    exit 1
fi

echo "Files deleted"
df -h "${MOUNT_PATH}"

echo ""
echo "Pre-test cleanup complete"
