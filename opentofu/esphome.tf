# ESPHome host resources
#
# Data is auto-generated in esphome-hosts.tf from esphome/*.yaml configs.
# These resources use the same patterns as infrastructure_hosts in unifi.tf
# and the dns module.

resource "unifi_user" "esphome_hosts" {
  for_each = local.esphome_hosts

  mac              = each.value.mac
  name             = each.key
  note             = each.value.note
  fixed_ip         = each.value.ip
  local_dns_record = each.value.hostname
}

resource "cloudflare_dns_record" "esphome_hosts" {
  for_each = local.esphome_hosts

  zone_id = module.dns.cloudflare_oneill_net_zone_id
  name    = each.value.hostname
  type    = "A"
  content = each.value.ip
  ttl     = 1
}
