# Local values shared across multiple resources
#
# infrastructure_hosts defines all infrastructure machines with static IPs.
# This data structure is consumed by both:
# - unifi_user resources (DHCP reservations with internal DNS)
# - aws_route53_record resources (public DNS A records)
#
# This ensures UniFi DHCP and Route53 DNS stay automatically in sync.
# To add a new host, simply add an entry here and run `opentofu apply`.
#
# Optional fields:
# - public_dns (default: true) - set to false to skip public Route53 record
# - enable_ipv6 (default: true) - set to false to skip AAAA record creation
#
# Proxmox VE hosts IP plan: 172.19.74.4x (p1=.41, p2=.42, p3=.43, etc.)

locals {
  # IPv6 prefix for Default VLAN (172.19.74.0/24)
  infrastructure_ipv6_prefix = "2600:4040:2ece:7500"

  infrastructure_hosts = {
    # Proxmox VE hosts
    p1 = {
      mac      = "90:e2:ba:d8:2a:8c"
      ip       = "172.19.74.41"
      hostname = "p1.oneill.net"
      note     = "Proxmox VE host"
    }
    p2 = {
      mac      = "b4:96:91:4b:34:58"
      ip       = "172.19.74.42"
      hostname = "p2.oneill.net"
      note     = "Proxmox VE host"
    }
    p3 = {
      mac      = "b4:96:91:39:e0:94"
      ip       = "172.19.74.43"
      hostname = "p3.oneill.net"
      note     = "Proxmox VE host"
    }
    p4 = {
      mac      = "b4:96:91:a0:83:54"
      ip       = "172.19.74.44"
      hostname = "p4.oneill.net"
      note     = "Proxmox VE host"
    }
    # AMT/vPro management interfaces
    p2-amt = {
      mac         = "34:17:eb:aa:83:12"
      ip          = "172.19.74.201"
      hostname    = "p2-amt.oneill.net"
      note        = "p2 AMT interface"
      enable_ipv6 = false
    }
    p3-amt = {
      mac         = "98:90:96:b8:cc:3d"
      ip          = "172.19.74.82"
      hostname    = "p3-amt.oneill.net"
      note        = "p3 AMT interface"
      enable_ipv6 = false
    }
    p4-amt = {
      mac         = "64:00:6a:4d:46:30"
      ip          = "172.19.74.83"
      hostname    = "p4-amt.oneill.net"
      note        = "p4 AMT interface"
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
      mac      = "52:54:72:19:74:74"
      ip       = "172.19.74.74"
      hostname = "k3.oneill.net"
      note     = "Kubernetes worker node (VM)"
    }
    k4 = {
      mac      = "52:54:72:19:74:75"
      ip       = "172.19.74.75"
      hostname = "k4.oneill.net"
      note     = "Kubernetes worker node (VM)"
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
    pantrypi = {
      mac      = "dc:a6:32:9d:b7:0f"
      ip       = "172.19.74.120"
      hostname = "pantrypi.oneill.net"
      note     = "Raspberry Pi in pantry - zwavejs, zigbee2mqtt, rtl433"
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
