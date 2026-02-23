resource "aws_route53_zone" "oneill_net" {
  name              = "oneill.net"
  delegation_set_id = aws_route53_delegation_set.main.id
}

# CloudFront distribution records for website hosting
# Both apex domain and www subdomain point to the same CloudFront distribution
resource "aws_route53_record" "oneill_a" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "oneill.net"
  type    = "A"
  alias {
    name                   = "d330vtujw3sx24.cloudfront.net."
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "www.oneill.net"
  type    = "A"
  alias {
    name                   = "d330vtujw3sx24.cloudfront.net."
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}

# Email configuration
resource "aws_route53_record" "oneill_mx" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "oneill.net"
  type    = "MX"
  ttl     = 86400
  records = [
    "10 mx-1.pobox.com.",
    "10 mx-2.pobox.com.",
    "10 mx-3.pobox.com."
  ]
}

resource "aws_route53_record" "oneill_spf" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "oneill.net"
  type    = "TXT"
  ttl     = 3600
  records = ["v=spf1 include:_spf.google.com include:spf.messagingengine.com ~all"]
}


resource "aws_route53_record" "dkim" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "mesmtp._domainkey.oneill.net"
  type    = "TXT"
  ttl     = 3600
  records = ["v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCSWE5uk2EOlSVQ2Z68vMr04EQ5NoC0ki3wIDY3zIXFaEGbPisEJEYsNQ6fbj+d+9sc6kZ079M77S/FNpgZuWDepqZyT5SmzwGMw0RbUPr3F1JvQ9wFVx15P2ssPrFiY1Lv9vskqvanDka5+TDC7oiUd9oFZanF/KVLxMNsRRtStQIDAQAB"]
}

# Fastmail DKIM CNAME records for oneill.net
resource "aws_route53_record" "dkim_fm1" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "fm1._domainkey.oneill.net"
  type    = "CNAME"
  ttl     = 3600
  records = ["fm1.oneill.net.dkim.fmhosted.com"]
}

resource "aws_route53_record" "dkim_fm2" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "fm2._domainkey.oneill.net"
  type    = "CNAME"
  ttl     = 3600
  records = ["fm2.oneill.net.dkim.fmhosted.com"]
}

resource "aws_route53_record" "dkim_fm3" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "fm3._domainkey.oneill.net"
  type    = "CNAME"
  ttl     = 3600
  records = ["fm3.oneill.net.dkim.fmhosted.com"]
}


# Other services and subdomains
resource "aws_route53_record" "atproto" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "_atproto.oneill.net"
  type    = "TXT"
  ttl     = 300
  records = ["did=did:plc:cvvzqrdxxordkaboxirrerb3"]
}

resource "aws_route53_record" "clayton" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "clayton.oneill.net"
  type    = "CNAME"
  ttl     = 3600
  records = ["oneill-website.pages.dev."]
}

resource "aws_route53_record" "k_subdomain_ns" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "k.oneill.net"
  type    = "NS"
  ttl     = 3600
  records = aws_route53_zone.k_oneill_net.name_servers
}

resource "aws_route53_record" "router" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "router.oneill.net"
  type    = "A"
  ttl     = 3600
  records = ["172.19.74.1"]
}

# Infrastructure hosts - automatically synced with UniFi DHCP reservations
# Host definitions are in ../../locals.tf (infrastructure_hosts) and shared
# with unifi_user resources to ensure DNS and DHCP stay automatically in sync.
# Only creates Route53 records for hosts with public_dns=true (defaults to true)

resource "aws_route53_record" "infrastructure_hosts" {
  for_each = { for k, v in var.infrastructure_hosts : k => v if v.public_dns }

  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = each.value.hostname
  type    = "A"
  ttl     = 300
  records = [each.value.ip]
}

resource "aws_route53_record" "infrastructure_hosts_aaaa" {
  for_each = {
    for k, v in var.infrastructure_hosts : k => v
    if v.public_dns && v.enable_ipv6
  }

  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = each.value.hostname
  type    = "AAAA"
  ttl     = 300
  records = [format("%s::74:%s", var.infrastructure_ipv6_prefix, split(".", each.value.ip)[3])]
}

# Service CNAMEs for infra1 services
resource "aws_route53_record" "nut" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "nut.oneill.net"
  type    = "CNAME"
  ttl     = 300
  records = ["infra1.oneill.net"]
}

resource "aws_route53_record" "os_install" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "os-install.oneill.net"
  type    = "CNAME"
  ttl     = 300
  records = ["infra1.oneill.net"]
}

resource "aws_route53_record" "pve" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "pve.oneill.net"
  type    = "CNAME"
  ttl     = 300
  records = ["infra1.oneill.net"]
}

# Service CNAMEs for pantrypi services
resource "aws_route53_record" "zwavejs" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "zwavejs.oneill.net"
  type    = "CNAME"
  ttl     = 300
  records = ["pantrypi.oneill.net"]
}

resource "aws_route53_record" "zigbee2mqtt" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "zigbee2mqtt.oneill.net"
  type    = "CNAME"
  ttl     = 300
  records = ["pantrypi.oneill.net"]
}

resource "aws_route53_record" "matter" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "matter.oneill.net"
  type    = "CNAME"
  ttl     = 300
  records = ["pantrypi.oneill.net"]
}

resource "aws_route53_record" "thread" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "thread.oneill.net"
  type    = "CNAME"
  ttl     = 300
  records = ["pantrypi.oneill.net"]
}

# TXT record for Proxmox auto-installer URL discovery
# The installer looks up proxmox-auto-installer.{search domain}
resource "aws_route53_record" "proxmox_auto_installer" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "proxmox-auto-installer.oneill.net"
  type    = "TXT"
  ttl     = 300
  records = ["https://os-install.oneill.net/answer"]
}

# Nameserver records for delegation set
resource "aws_route53_record" "oneill_ns1_a" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "ns1.oneill.net"
  type    = "A"
  ttl     = 86400
  records = [local.nameserver_ips.ns1.ipv4]
}

resource "aws_route53_record" "oneill_ns1_aaaa" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "ns1.oneill.net"
  type    = "AAAA"
  ttl     = 86400
  records = [local.nameserver_ips.ns1.ipv6]
}

resource "aws_route53_record" "oneill_ns2_a" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "ns2.oneill.net"
  type    = "A"
  ttl     = 86400
  records = [local.nameserver_ips.ns2.ipv4]
}

resource "aws_route53_record" "oneill_ns2_aaaa" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "ns2.oneill.net"
  type    = "AAAA"
  ttl     = 86400
  records = [local.nameserver_ips.ns2.ipv6]
}

resource "aws_route53_record" "oneill_ns3_a" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "ns3.oneill.net"
  type    = "A"
  ttl     = 86400
  records = [local.nameserver_ips.ns3.ipv4]
}

resource "aws_route53_record" "oneill_ns3_aaaa" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "ns3.oneill.net"
  type    = "AAAA"
  ttl     = 86400
  records = [local.nameserver_ips.ns3.ipv6]
}

resource "aws_route53_record" "oneill_ns4_a" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "ns4.oneill.net"
  type    = "A"
  ttl     = 86400
  records = [local.nameserver_ips.ns4.ipv4]
}

resource "aws_route53_record" "oneill_ns4_aaaa" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "ns4.oneill.net"
  type    = "AAAA"
  ttl     = 86400
  records = [local.nameserver_ips.ns4.ipv6]
}

# Cloudflare zone for oneill.net
resource "cloudflare_zone" "oneill_net" {
  account = {
    id = var.cloudflare_account_id
  }
  name = "oneill.net"
}

# Redirect-only domains: proxied placeholder so Cloudflare redirect rules
# apply at the edge. 192.0.2.1 is RFC 5737 (documentation/example use) —
# Cloudflare intercepts before reaching it.
resource "cloudflare_dns_record" "oneill_a" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "oneill.net"
  type    = "A"
  content = "192.0.2.1"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "www" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "www.oneill.net"
  type    = "A"
  content = "192.0.2.1"
  proxied = true
  ttl     = 1
}

# MX records (one resource per server)
resource "cloudflare_dns_record" "oneill_mx1" {
  zone_id  = cloudflare_zone.oneill_net.id
  name     = "oneill.net"
  type     = "MX"
  content  = "mx-1.pobox.com"
  priority = 10
  ttl      = 86400
}

resource "cloudflare_dns_record" "oneill_mx2" {
  zone_id  = cloudflare_zone.oneill_net.id
  name     = "oneill.net"
  type     = "MX"
  content  = "mx-2.pobox.com"
  priority = 10
  ttl      = 86400
}

resource "cloudflare_dns_record" "oneill_mx3" {
  zone_id  = cloudflare_zone.oneill_net.id
  name     = "oneill.net"
  type     = "MX"
  content  = "mx-3.pobox.com"
  priority = 10
  ttl      = 86400
}

# SPF TXT record
resource "cloudflare_dns_record" "oneill_spf" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "oneill.net"
  type    = "TXT"
  content = "\"v=spf1 include:_spf.google.com include:spf.messagingengine.com ~all\""
  ttl     = 3600
}

# DKIM TXT record (MessageSystems)
resource "cloudflare_dns_record" "dkim" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "mesmtp._domainkey.oneill.net"
  type    = "TXT"
  content = "\"v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCSWE5uk2EOlSVQ2Z68vMr04EQ5NoC0ki3wIDY3zIXFaEGbPisEJEYsNQ6fbj+d+9sc6kZ079M77S/FNpgZuWDepqZyT5SmzwGMw0RbUPr3F1JvQ9wFVx15P2ssPrFiY1Lv9vskqvanDka5+TDC7oiUd9oFZanF/KVLxMNsRRtStQIDAQAB\""
  ttl     = 3600
}

# DKIM CNAMEs (Fastmail)
resource "cloudflare_dns_record" "dkim_fm1" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "fm1._domainkey.oneill.net"
  type    = "CNAME"
  content = "fm1.oneill.net.dkim.fmhosted.com"
  ttl     = 3600
}

resource "cloudflare_dns_record" "dkim_fm2" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "fm2._domainkey.oneill.net"
  type    = "CNAME"
  content = "fm2.oneill.net.dkim.fmhosted.com"
  ttl     = 3600
}

resource "cloudflare_dns_record" "dkim_fm3" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "fm3._domainkey.oneill.net"
  type    = "CNAME"
  content = "fm3.oneill.net.dkim.fmhosted.com"
  ttl     = 3600
}


# Bluesky AT Protocol verification
resource "cloudflare_dns_record" "atproto" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "_atproto.oneill.net"
  type    = "TXT"
  content = "\"did=did:plc:cvvzqrdxxordkaboxirrerb3\""
  ttl     = 1
}

# Cloudflare Pages custom domain
resource "cloudflare_dns_record" "clayton" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "clayton.oneill.net"
  type    = "CNAME"
  content = "oneill-website.pages.dev"
  proxied = true
  ttl     = 1
}

# Proxmox auto-installer URL discovery
resource "cloudflare_dns_record" "proxmox_auto_installer" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "proxmox-auto-installer.oneill.net"
  type    = "TXT"
  content = "\"https://os-install.oneill.net/answer\""
  ttl     = 1
}

# Router A record
resource "cloudflare_dns_record" "router" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "router.oneill.net"
  type    = "A"
  content = "172.19.74.1"
  ttl     = 3600
}

# k.oneill.net NS delegation (stays on Route53, managed by external-dns)
resource "cloudflare_dns_record" "k_subdomain_ns" {
  for_each = toset(aws_route53_zone.k_oneill_net.name_servers)
  zone_id  = cloudflare_zone.oneill_net.id
  name     = "k.oneill.net"
  type     = "NS"
  content  = each.value
  ttl      = 3600
}

# Infrastructure hosts - A records
resource "cloudflare_dns_record" "cf_infrastructure_hosts" {
  for_each = { for k, v in var.infrastructure_hosts : k => v if v.public_dns }
  zone_id  = cloudflare_zone.oneill_net.id
  name     = each.value.hostname
  type     = "A"
  content  = each.value.ip
  ttl      = 1
}

# Infrastructure hosts - AAAA records (IPv6-enabled hosts only)
resource "cloudflare_dns_record" "cf_infrastructure_hosts_aaaa" {
  for_each = {
    for k, v in var.infrastructure_hosts : k => v
    if v.public_dns && v.enable_ipv6
  }
  zone_id = cloudflare_zone.oneill_net.id
  name    = each.value.hostname
  type    = "AAAA"
  content = format("%s::74:%s", var.infrastructure_ipv6_prefix, split(".", each.value.ip)[3])
  ttl     = 1
}

# Service CNAMEs for infra1 services
resource "cloudflare_dns_record" "nut" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "nut.oneill.net"
  type    = "CNAME"
  content = "infra1.oneill.net"
  ttl     = 1
}

resource "cloudflare_dns_record" "os_install" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "os-install.oneill.net"
  type    = "CNAME"
  content = "infra1.oneill.net"
  ttl     = 1
}

resource "cloudflare_dns_record" "pve" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "pve.oneill.net"
  type    = "CNAME"
  content = "infra1.oneill.net"
  ttl     = 1
}

# Service CNAMEs for pantrypi services
resource "cloudflare_dns_record" "zwavejs" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "zwavejs.oneill.net"
  type    = "CNAME"
  content = "pantrypi.oneill.net"
  ttl     = 1
}

resource "cloudflare_dns_record" "zigbee2mqtt" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "zigbee2mqtt.oneill.net"
  type    = "CNAME"
  content = "pantrypi.oneill.net"
  ttl     = 1
}

resource "cloudflare_dns_record" "matter" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "matter.oneill.net"
  type    = "CNAME"
  content = "pantrypi.oneill.net"
  ttl     = 1
}

resource "cloudflare_dns_record" "thread" {
  zone_id = cloudflare_zone.oneill_net.id
  name    = "thread.oneill.net"
  type    = "CNAME"
  content = "pantrypi.oneill.net"
  ttl     = 1
}

# Redirect oneill.net and www.oneill.net to clayton.oneill.net
resource "cloudflare_ruleset" "oneill_redirects" {
  zone_id     = cloudflare_zone.oneill_net.id
  name        = "oneill.net redirects"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"
  description = "Redirect oneill.net and www.oneill.net to clayton.oneill.net"
  rules = [{
    ref         = "redirect_to_clayton"
    description = "Redirect apex and www to clayton.oneill.net"
    expression  = "(http.host eq \"oneill.net\") or (http.host eq \"www.oneill.net\")"
    action      = "redirect"
    action_parameters = {
      from_value = {
        status_code           = 301
        target_url            = { expression = "concat(\"https://clayton.oneill.net\", http.request.uri.path)" }
        preserve_query_string = true
      }
    }
  }]
}
