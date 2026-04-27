# Local values shared across multiple resources
#
# infrastructure_hosts defines all infrastructure machines with static IPs.
# This data structure is consumed by both:
# - unifi_user resources (DHCP reservations with internal DNS)
# - cloudflare_dns_record resources (public DNS A records)
#
# This ensures UniFi DHCP and Cloudflare DNS stay automatically in sync.
# To add a new host, simply add an entry here and run `opentofu apply`.
#
# Optional fields:
# - public_dns (default: true) - set to false to skip public DNS record
# - enable_ipv6 (default: true) - set to false to skip AAAA record creation
#
# Proxmox VE hosts IP plan: 172.19.74.4x (p1=.41)

locals {
  # IPv6 prefix for Default VLAN (172.19.74.0/24)
  infrastructure_ipv6_prefix = "2600:4040:2eec:a000"

  infrastructure_hosts = {
    # Proxmox VE hosts
    p1 = {
      mac      = "90:e2:ba:d8:2a:8c"
      ip       = "172.19.74.41"
      hostname = "p1.oneill.net"
      note     = "Proxmox VE host"
    }
    # AMT/vPro management interfaces
    k5-amt = {
      mac         = "34:17:eb:aa:83:12"
      ip          = "172.19.74.201"
      hostname    = "k5-amt.oneill.net"
      note        = "k5 AMT interface"
      enable_ipv6 = false
    }
    k3-amt = {
      mac         = "98:90:96:b8:cc:3d"
      ip          = "172.19.74.82"
      hostname    = "k3-amt.oneill.net"
      note        = "k3 AMT interface"
      enable_ipv6 = false
    }
    k4-amt = {
      mac         = "64:00:6a:4d:46:30"
      ip          = "172.19.74.83"
      hostname    = "k4-amt.oneill.net"
      note        = "k4 AMT interface"
      enable_ipv6 = false
    }
    # Kubernetes nodes
    k1 = {
      mac      = "52:54:00:7a:16:72"
      ip       = "172.19.74.134"
      hostname = "k1.oneill.net"
      note     = "Kubernetes control-plane node (VM)"
    }
    k2 = {
      mac      = "52:54:72:19:74:72"
      ip       = "172.19.74.112"
      hostname = "k2.oneill.net"
      note     = "Kubernetes worker node (VM)"
    }
    k3 = {
      mac      = "b4:96:91:39:e0:94"
      ip       = "172.19.74.74"
      hostname = "k3.oneill.net"
      note     = "Kubernetes worker node (bare metal)"
    }
    k4 = {
      mac      = "b4:96:91:a0:83:54"
      ip       = "172.19.74.75"
      hostname = "k4.oneill.net"
      note     = "Kubernetes worker node (bare metal)"
    }
    k5 = {
      mac      = "b4:96:91:4b:34:58"
      ip       = "172.19.74.76"
      hostname = "k5.oneill.net"
      note     = "Kubernetes worker node (bare metal)"
    }
    luser = {
      mac        = "52:54:72:19:74:61"
      ip         = "172.19.74.161"
      hostname   = "luser.oneill.net"
      note       = "General purpose VM"
      public_dns = false
    }
    # Other infrastructure
    fs2 = {
      mac         = "b4:96:91:4e:1b:ac"
      ip          = "172.19.74.139"
      hostname    = "fs2.oneill.net"
      note        = "Synology NAS"
      enable_ipv6 = false
    }
    infra1 = {
      mac      = "c0:3f:d5:6a:49:30"
      ip       = "172.19.74.31"
      hostname = "infra1.oneill.net"
      note     = "Infrastructure services"
    }
    garagepi = {
      mac      = "d8:3a:dd:1c:15:30"
      ip       = "172.19.74.216"
      hostname = "garagepi.oneill.net"
      note     = "Raspberry Pi in garage - rtl433"
    }
    garagepi-eth = {
      mac      = "d8:3a:dd:1c:15:2f"
      ip       = "172.19.74.221"
      hostname = "garagepi-eth.oneill.net"
      note     = "Raspberry Pi in garage - wired interface"
    }
    pantrypi = {
      mac      = "dc:a6:32:9d:b7:0f"
      ip       = "172.19.74.120"
      hostname = "pantrypi.oneill.net"
      note     = "Raspberry Pi in pantry - zwavejs, zigbee2mqtt, rtl433"
    }
    landroid = {
      mac         = "7c:fa:80:61:08:2e"
      ip          = "172.20.6.67"
      hostname    = "landroid.oneill.net"
      note        = "Worx Landroid WR310.1 mower"
      public_dns  = false
      enable_ipv6 = false
    }
    # Test VMs
    testvm = {
      mac      = "BC:24:11:59:85:90"
      ip       = "172.19.74.60"
      hostname = "testvm.oneill.net"
      note     = "Test VM"
    }
    # Desktop PCs
    szamar = {
      mac         = "9c:6b:00:9b:16:ef"
      ip          = "172.19.74.50"
      hostname    = "szamar.oneill.net"
      note        = "Gaming PC"
      enable_ipv6 = false
    }
  }
}
