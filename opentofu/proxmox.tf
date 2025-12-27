# Proxmox VM resources managed by OpenTofu
#
# VM defaults for new VMs:
# - cpu.type = x86-64-v3 (live migration compatible across Haswell+)
# - scsi_hardware = virtio-scsi-single (enables iothread per disk)
# - disk.iothread = true (dedicated I/O thread)
# - disk.discard = "on" (TRIM support)
# - network_device.queues = cores (multiqueue for parallel packet processing)
# - agent.enabled = true, agent.trim = true (guest agent with fstrim)

# RTX 2060 Super hardware mapping for PCI passthrough
resource "proxmox_virtual_environment_hardware_mapping_pci" "rtx2060" {
  name = "rtx2060"
  map = [{
    id           = "10de:1f06"
    node         = "p1"
    path         = "0000:01:00"
    iommu_group  = 2
    subsystem_id = "1458:3fed"
  }]
}

# Intel iGPU hardware mapping for PCI passthrough
# Intel HD Graphics 4600 (Haswell) on p2, p4, p9
resource "proxmox_virtual_environment_hardware_mapping_pci" "intel_igpu" {
  name = "intel-igpu"
  map = [
    {
      id           = "8086:0412"
      node         = "p2"
      path         = "0000:00:02"
      iommu_group  = 0
      subsystem_id = "1028:05a4"
    },
    {
      id           = "8086:0412"
      node         = "p4"
      path         = "0000:00:02"
      iommu_group  = 0
      subsystem_id = "1028:05a4"
    },
    {
      id           = "8086:0412"
      node         = "p9"
      path         = "0000:00:02"
      iommu_group  = 0
      subsystem_id = "1028:05a4"
    },
  ]
}

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
  }

  memory {
    dedicated = 8192
    floating  = 4096
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

  lifecycle {
    ignore_changes = [node_name, started]
  }
}

resource "proxmox_virtual_environment_vm" "k2" {
  name      = "k2"
  node_name = "p2"
  vm_id     = 1072

  started = false
  on_boot = true
  machine = "q35"

  cpu {
    cores   = 4
    sockets = 1
    type    = "x86-64-v3"
  }

  memory {
    dedicated = 24576
    floating  = 12288
  }

  agent {
    enabled = true
    trim    = true
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    interface    = "scsi0"
    datastore_id = "local-zfs"
    size         = 100
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = "52:54:72:19:74:72"
    model       = "virtio"
    queues      = 4
  }

  # RTX 2060 Super GPU passthrough from p1
  hostpci {
    device  = "hostpci0"
    mapping = proxmox_virtual_environment_hardware_mapping_pci.rtx2060.name
    pcie    = true
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [node_name, started]
  }
}

resource "proxmox_virtual_environment_vm" "k3" {
  name      = "k3"
  node_name = "p9"
  vm_id     = 1074

  started = false
  on_boot = true

  cpu {
    cores   = 4
    sockets = 1
    type    = "x86-64-v3"
  }

  memory {
    dedicated = 24576
    floating  = 12288
  }

  agent {
    enabled = true
    trim    = true
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    interface    = "scsi0"
    datastore_id = "local-zfs"
    size         = 100
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = "52:54:72:19:74:74"
    model       = "virtio"
    queues      = 4
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [node_name, started]
  }
}

resource "proxmox_virtual_environment_vm" "k4" {
  name      = "k4"
  node_name = "p4"
  vm_id     = 1075

  started = false
  on_boot = true

  cpu {
    cores   = 4
    sockets = 1
    type    = "x86-64-v3"
  }

  memory {
    dedicated = 24576
    floating  = 12288
  }

  agent {
    enabled = true
    trim    = true
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    interface    = "scsi0"
    datastore_id = "local-zfs"
    size         = 100
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = "52:54:72:19:74:75"
    model       = "virtio"
    queues      = 4
  }

  # Intel iGPU passthrough from p4
  hostpci {
    device  = "hostpci0"
    mapping = proxmox_virtual_environment_hardware_mapping_pci.intel_igpu.name
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [node_name, started]
  }
}

resource "proxmox_virtual_environment_vm" "luser" {
  name      = "luser"
  node_name = "p9"
  vm_id     = 161

  started = true
  on_boot = true

  cpu {
    cores   = 4
    sockets = 1
    type    = "x86-64-v3"
  }

  memory {
    dedicated = 16384
    floating  = 8192
  }

  agent {
    enabled = true
    trim    = true
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    interface    = "scsi0"
    datastore_id = "local-zfs"
    size         = 128
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = "52:54:72:19:74:61"
    model       = "virtio"
    queues      = 4
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [node_name, started]
  }
}
