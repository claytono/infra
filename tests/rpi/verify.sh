#!/bin/bash
# Verify RPi image configuration via SSH
# Tests cloud-init, networking, and post-install.sh results
#
# Usage: ./verify.sh [host] [port]
#   host: SSH host (default: localhost)
#   port: SSH port (default: 2222)
set -euo pipefail

SSH_HOST="${1:-localhost}"
SSH_PORT="${2:-2222}"
SSH_USER="root"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$SSH_PORT")

ssh_cmd() {
    # shellcheck disable=SC2029 # commands are intentionally expanded locally
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$SSH_HOST" "$@"
}

echo "=== Verifying RPi configuration ==="
echo "Host: $SSH_HOST:$SSH_PORT"
echo ""
FAILED=0

# Test 1: SSH connectivity
if ssh_cmd 'exit 0' 2>/dev/null; then
    echo "PASS: SSH connectivity"
else
    echo "FAIL: SSH connectivity"
    exit 1
fi

# Test 2: cloud-init completed successfully
CLOUD_STATUS=$(ssh_cmd 'cloud-init status' 2>/dev/null || echo "unknown")
if echo "$CLOUD_STATUS" | grep -q 'done'; then
    echo "PASS: cloud-init completed"
else
    echo "FAIL: cloud-init status: $CLOUD_STATUS"
    FAILED=1
fi

# Test 3: Hostname set correctly (should match what rpi-image-customize set)
ACTUAL_HOSTNAME=$(ssh_cmd 'hostname' 2>/dev/null)
if [[ -n "$ACTUAL_HOSTNAME" ]]; then
    echo "PASS: Hostname is '$ACTUAL_HOSTNAME'"
else
    echo "FAIL: Hostname not set"
    FAILED=1
fi

# Test 4: Network connectivity (QEMU uses usb0, real Pi uses eth0)
if ssh_cmd 'ip -4 addr show scope global' 2>/dev/null | grep -qE 'inet [0-9]+\.[0-9]+'; then
    echo "PASS: Network interface has IP address"
else
    echo "FAIL: No network interface with IP address"
    FAILED=1
fi

# Test 5: WiFi regulatory domain in boot cmdline.txt
# Note: /proc/cmdline is QEMU's cmdline, not the image's. Check the file directly.
if ssh_cmd 'cat /boot/firmware/cmdline.txt' 2>/dev/null | grep -q 'cfg80211.ieee80211_regdom=US'; then
    echo "PASS: WiFi regulatory domain set in cmdline.txt"
else
    echo "FAIL: WiFi regulatory domain not in cmdline.txt"
    FAILED=1
fi

# Test 6: post-install.sh created ansible user
if ssh_cmd 'id ansible' &>/dev/null; then
    echo "PASS: ansible user exists (post-install.sh ran)"
else
    echo "FAIL: ansible user does not exist"
    FAILED=1
fi

# Test 7: SSH key installed for ansible
if ssh_cmd 'test -s /home/ansible/.ssh/authorized_keys' 2>/dev/null; then
    echo "PASS: SSH key installed for ansible"
else
    echo "FAIL: No SSH keys in ansible authorized_keys"
    FAILED=1
fi

# Test 8: Passwordless sudo for ansible
if ssh_cmd 'su - ansible -c "sudo -n true"' 2>/dev/null; then
    echo "PASS: Passwordless sudo configured"
else
    echo "FAIL: Passwordless sudo not working"
    FAILED=1
fi

if [[ $FAILED -eq 0 ]]; then
    echo ""
    echo "All tests passed!"
    exit 0
else
    echo ""
    echo "=== Diagnostic info ==="
    ssh_cmd 'cloud-init status --long' 2>/dev/null || true
    ssh_cmd 'tail -30 /var/log/cloud-init-output.log' 2>/dev/null || true
    echo ""
    echo "Some tests failed!"
    exit 1
fi
