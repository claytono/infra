resource "vultr_ssh_key" "flux" {
  name    = "flux-ssh-key"
  ssh_key = trimspace(file(var.ssh_pubkey_path))
}

# To get available OS IDs, run:
# curl -X GET "https://api.vultr.com/v2/os" -H "Authorization: Bearer YOUR_API_KEY" | jq '.os[] | select(.name | contains("Debian")) | {id, name, arch, family}'

resource "vultr_instance" "flux" {
  plan        = "vc2-1c-1gb"
  region      = "ewr"
  os_id       = 477 # Debian 11 x64 (bullseye)
  label       = "flux.fnord.net"
  hostname    = "flux"
  ssh_key_ids = [vultr_ssh_key.flux.id]
  enable_ipv6 = true
}

resource "vultr_reverse_ipv4" "flux" {
  instance_id = vultr_instance.flux.id
  ip          = vultr_instance.flux.main_ip
  reverse     = "flux.fnord.net"
}

resource "vultr_reverse_ipv6" "flux" {
  instance_id = vultr_instance.flux.id
  ip          = vultr_instance.flux.v6_main_ip
  reverse     = "flux.fnord.net"
}

data "aws_route53_zone" "fnord_net" {
  name         = "fnord.net."
  private_zone = false
}

resource "aws_route53_record" "flux_a" {
  zone_id = data.aws_route53_zone.fnord_net.zone_id
  name    = "flux.fnord.net"
  type    = "A"
  ttl     = 300
  records = [vultr_instance.flux.main_ip]
}

resource "aws_route53_record" "flux_aaaa" {
  zone_id = data.aws_route53_zone.fnord_net.zone_id
  name    = "flux.fnord.net"
  type    = "AAAA"
  ttl     = 300
  records = [vultr_instance.flux.v6_main_ip]
}

# Cloudflare DNS records for flux
resource "cloudflare_dns_record" "flux_a" {
  zone_id = module.dns.cloudflare_fnord_net_zone_id
  name    = "flux.fnord.net"
  type    = "A"
  content = vultr_instance.flux.main_ip
  ttl     = 300
}

resource "cloudflare_dns_record" "flux_aaaa" {
  zone_id = module.dns.cloudflare_fnord_net_zone_id
  name    = "flux.fnord.net"
  type    = "AAAA"
  # Normalize IPv6 by stripping leading zeros; Cloudflare's API does this
  # and the provider doesn't account for it, causing perpetual drift.
  # https://github.com/cloudflare/terraform-provider-cloudflare/issues/3354
  content = replace(vultr_instance.flux.v6_main_ip, "/\\b0+([0-9a-fA-F]+)/", "$1")
  ttl     = 300
}
