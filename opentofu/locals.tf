# Local values shared across multiple resources
#
# infrastructure_hosts defines all infrastructure machines with static IPs.
# This data structure is consumed by both:
# - unifi_user resources (DHCP reservations)
# - aws_route53_record resources (DNS A records)
#
# This ensures UniFi DHCP and Route53 DNS stay automatically in sync.
# To add a new host, simply add an entry here and run `opentofu apply`.
#
# Proxmox VE hosts IP plan: 172.19.74.4x (p1=.41, p2=.42, p3=.43, etc.)

locals {
  infrastructure_hosts = {
    # Proxmox VE hosts
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
    p9 = {
      mac      = "b4:96:91:39:e0:70"
      ip       = "172.19.74.155"
      hostname = "p9.oneill.net"
      note     = "Proxmox VE host"
    }
    # AMT/vPro management interfaces
    p2-amt = {
      mac      = "34:17:eb:aa:83:12"
      ip       = "172.19.74.201"
      hostname = "p2-amt.oneill.net"
      note     = "p2 AMT interface"
    }
    p3-amt = {
      mac      = "98:90:96:b8:cc:3d"
      ip       = "172.19.74.82"
      hostname = "p3-amt.oneill.net"
      note     = "p3 AMT interface"
    }
    p4-amt = {
      mac      = "64:00:6a:4d:46:30"
      ip       = "172.19.74.83"
      hostname = "p4-amt.oneill.net"
      note     = "p4 AMT interface"
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
    # Other infrastructure
    fs2 = {
      mac      = "b4:96:91:4e:1b:ac"
      ip       = "172.19.74.139"
      hostname = "fs2.oneill.net"
      note     = "Synology NAS"
    }
    infrapi = {
      mac      = "d8:3a:dd:1c:15:2f"
      ip       = "172.19.74.224"
      hostname = "infrapi.oneill.net"
      note     = "Infrastructure services (NUT)"
    }
  }
}
