# Proxmox VM resources managed by OpenTofu
#
# VM defaults for new VMs:
# - cpu.type = x86-64-v3 (live migration compatible across Haswell+)
# - scsi_hardware = virtio-scsi-single (enables iothread per disk)
# - disk.iothread = true (dedicated I/O thread)
# - disk.discard = "on" (TRIM support)
# - network_device.queues = cores (multiqueue for parallel packet processing)
# - agent.enabled = true, agent.trim = true (guest agent with fstrim)

resource "proxmox_virtual_environment_vm" "k1" {
  name      = "k1"
  node_name = "p9"
  vm_id     = 134

  started = true
  on_boot = true

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v3"
    units   = 100 # cgroup v2 default
  }

  memory {
    dedicated = 4096
  }

  agent {
    enabled = true
    trim    = true
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    interface    = "scsi0"
    datastore_id = "proxmox-ssd"
    size         = 40
    file_format  = "qcow2"
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = "52:54:00:7a:16:72"
    model       = "virtio"
    queues      = 2
  }

  operating_system {
    type = "l26"
  }
}
