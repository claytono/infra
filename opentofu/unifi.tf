# UniFi DHCP Reservations for Kubernetes and infrastructure hosts
#
# These resources manage static DHCP reservations on the UDMP for hosts that
# need consistent IP addresses. The actual IP configuration on the hosts is
# managed via Ansible (see ansible/host_vars/*.yaml).

# k1 - Kubernetes control-plane (VM)
resource "unifi_user" "k1" {
  mac              = "52:54:00:7a:16:72"
  name             = "k1"
  note             = "Kubernetes control-plane node (VM)"
  fixed_ip         = "172.19.74.134"
  local_dns_record = "k1.oneill.net"
}

# k2 - Kubernetes node
resource "unifi_user" "k2" {
  mac              = "06:bc:96:51:3a:a0"
  name             = "k2"
  note             = "Kubernetes worker node"
  fixed_ip         = "172.19.74.112"
  local_dns_record = "k2.oneill.net"
}

# k4 - Kubernetes node
resource "unifi_user" "k4" {
  mac              = "06:bc:96:51:3a:b1"
  name             = "k4"
  note             = "Kubernetes worker node"
  fixed_ip         = "172.19.74.75"
  local_dns_record = "k4.oneill.net"
}

# k5 - Kubernetes node
resource "unifi_user" "k5" {
  mac              = "06:bc:96:51:3a:b0"
  name             = "k5"
  note             = "Kubernetes worker node"
  fixed_ip         = "172.19.74.76"
  local_dns_record = "k5.oneill.net"
}

# fs2 - Synology NAS
resource "unifi_user" "fs2" {
  mac              = "00:11:32:94:97:11"
  name             = "fs2"
  note             = "Synology NAS"
  fixed_ip         = "172.19.74.139"
  local_dns_record = "fs2.oneill.net"
}
