# Local values shared across multiple resources
#
# infrastructure_hosts defines all infrastructure machines with static IPs.
# This data structure is consumed by both:
# - unifi_user resources (DHCP reservations)
# - aws_route53_record resources (DNS A records)
#
# This ensures UniFi DHCP and Route53 DNS stay automatically in sync.
# To add a new host, simply add an entry here and run `opentofu apply`.

locals {
  infrastructure_hosts = {
    k1 = {
      mac      = "52:54:00:7a:16:72"
      ip       = "172.19.74.134"
      hostname = "k1.oneill.net"
      note     = "Kubernetes control-plane node (VM)"
    }
    k2 = {
      mac      = "b4:96:91:4b:34:58"
      ip       = "172.19.74.112"
      hostname = "k2.oneill.net"
      note     = "Kubernetes worker node"
    }
    k4 = {
      mac      = "b4:96:91:a0:83:54"
      ip       = "172.19.74.75"
      hostname = "k4.oneill.net"
      note     = "Kubernetes worker node"
    }
    k5 = {
      mac      = "b4:96:91:39:e0:94"
      ip       = "172.19.74.76"
      hostname = "k5.oneill.net"
      note     = "Kubernetes worker node"
    }
    fs2 = {
      mac      = "b4:96:91:4e:1b:ac"
      ip       = "172.19.74.139"
      hostname = "fs2.oneill.net"
      note     = "Synology NAS"
    }
    p9 = {
      mac      = "b4:96:91:39:e0:70"
      ip       = "172.19.74.155"
      hostname = "p9.oneill.net"
      note     = "Proxmox VE host"
    }
  }
}
