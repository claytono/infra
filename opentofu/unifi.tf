# UniFi DHCP Reservations for Kubernetes and infrastructure hosts
#
# These resources manage static DHCP reservations on the UDMP for hosts that
# need consistent IP addresses. The actual IP configuration on the hosts is
# managed via Ansible (see ansible/host_vars/*.yaml).
#
# Host definitions are in locals.tf (infrastructure_hosts) and shared with
# Route53 DNS records to ensure UniFi DHCP and DNS stay automatically in sync.

resource "unifi_user" "infrastructure_hosts" {
  for_each = local.infrastructure_hosts

  mac              = each.value.mac
  name             = each.key
  note             = each.value.note
  fixed_ip         = each.value.ip
  local_dns_record = each.value.hostname
}
