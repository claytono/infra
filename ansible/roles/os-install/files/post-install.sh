#!/bin/bash
# Post-install script for Debian and Proxmox VE
# Sets up root and ansible SSH keys, passwordless sudo for ansible
# Used by: Proxmox first-boot hook, Debian preseed late_command

set -euo pipefail

SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB3URIT9ojo8mqsEjxmFu1C+Bxa3jdcKkUzM++IfDVmu coneill@xtal.oneill.net"

# Detect if running on Proxmox VE
is_proxmox() {
    [[ -f /etc/pve/.version ]] || command -v pveversion &>/dev/null
}

# On Proxmox, disable enterprise repos (require subscription) and enable no-subscription repo
if is_proxmox; then
    # Remove enterprise repos that require subscription
    rm -f /etc/apt/sources.list.d/pve-enterprise.sources
    rm -f /etc/apt/sources.list.d/ceph.sources

    # Add no-subscription repo
    cat > /etc/apt/sources.list.d/pve-no-subscription.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
fi

# Install packages based on system type
apt-get update
if is_proxmox; then
    apt-get install -y python3 sudo
else
    # Debian VM packages
    apt-get install -y python3 sudo qemu-guest-agent cloud-init
fi

# Set up root SSH key
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo "$SSH_KEY" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Create ansible user if it doesn't exist (preseed creates it, Proxmox doesn't)
if ! id ansible &>/dev/null; then
    useradd -m -u 9000 -s /bin/bash ansible
fi

# Set up SSH directory for ansible
mkdir -p /home/ansible/.ssh
chmod 700 /home/ansible/.ssh
echo "$SSH_KEY" > /home/ansible/.ssh/authorized_keys
chmod 600 /home/ansible/.ssh/authorized_keys
chown -R ansible:ansible /home/ansible/.ssh

# Configure passwordless sudo for ansible
echo 'ansible ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/ansible
chmod 440 /etc/sudoers.d/ansible

# Lock ansible password (SSH key only)
passwd -l ansible
