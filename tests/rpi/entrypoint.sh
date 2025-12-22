#!/bin/bash
# Entrypoint for RPi QEMU test container
# Expects a customized image from rpi-image-customize, handles QEMU-specific prep and boot

set -euo pipefail

IMAGE="${IMAGE:-/images/rpi.img}"

if [[ ! -f "$IMAGE" ]]; then
    echo "Error: Image not found: $IMAGE" >&2
    exit 1
fi

echo "=== Preparing RPi image for QEMU ==="

# Create working copy
cp "$IMAGE" /work/disk.img
qemu-img resize /work/disk.img 4G 2>/dev/null

# Set up loop device with kpartx for partition access
LOOP_DEV=$(losetup --find --show /work/disk.img)
kpartx -av "$LOOP_DEV"

# Wait for mapper devices to appear
LOOP_NAME=$(basename "$LOOP_DEV")
BOOT_PART="/dev/mapper/${LOOP_NAME}p1"
for i in {1..10}; do
    [[ -b "$BOOT_PART" ]] && break
    sleep 0.5
done

ROOT_PART="/dev/mapper/${LOOP_NAME}p2"

cleanup() {
    kpartx -d "$LOOP_DEV" 2>/dev/null || true
    losetup -d "$LOOP_DEV" 2>/dev/null || true
}
trap cleanup EXIT

# Mount boot partition and extract kernel/DTB
mkdir -p /work/boot
mount -t vfat "$BOOT_PART" /work/boot
cp /work/boot/kernel8.img /work/kernel8.img
cp /work/boot/bcm2710-rpi-3-b-plus.dtb /work/bcm2710-rpi-3-b-plus.dtb
umount /work/boot

# Disable systemd watchdog (causes boot loops in QEMU)
echo "Disabling systemd watchdog..."
debugfs -R "dump /etc/systemd/system.conf /work/system.conf" "$ROOT_PART" 2>/dev/null
sed -i 's/^#*WatchdogDevice=.*/WatchdogDevice=\/dev\/watchdog666/' /work/system.conf
grep -q "^WatchdogDevice=" /work/system.conf || echo "WatchdogDevice=/dev/watchdog666" >> /work/system.conf
debugfs -w -R "rm /etc/systemd/system.conf" "$ROOT_PART" 2>/dev/null
debugfs -w -R "write /work/system.conf /etc/systemd/system.conf" "$ROOT_PART" 2>/dev/null

# Detach loop device before QEMU
kpartx -d "$LOOP_DEV"
losetup -d "$LOOP_DEV"
trap - EXIT

echo "=== Starting QEMU ==="

# Monitor for cloud-init completion in background
# Create signal file when cloud-init.target is reached
monitor_boot() {
    while read -r line; do
        echo "$line"
        if [[ "$line" == *"cloud-init.target"* ]]; then
            touch /work/cloud-init-done
        fi
    done
}

# Run QEMU with SSH on port 22 (mapped by docker-compose)
# raspi3b machine uses USB networking via SMSC LAN9514
# dwc_otg params are required for USB networking to work
qemu-system-aarch64 \
    -machine raspi3b \
    -cpu cortex-a72 \
    -m 1G \
    -kernel /work/kernel8.img \
    -dtb /work/bcm2710-rpi-3-b-plus.dtb \
    -drive format=raw,file=/work/disk.img,if=sd \
    -append "rw console=ttyAMA1,115200 root=/dev/mmcblk0p2 rootdelay=1 dwc_otg.lpm_enable=0 dwc_otg.fiq_fsm_enable=0" \
    -device usb-net,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::22-:22 \
    -nographic \
    -no-reboot 2>&1 | monitor_boot
