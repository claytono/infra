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

# AWS Certificate Manager (ACM) SSL certificate validation records
# These DNS records prove domain ownership for automatic SSL certificate provisioning
resource "aws_route53_record" "acm_validation" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "_aab5ac87821783e4e8f7de6297024cbf.oneill.net"
  type    = "CNAME"
  ttl     = 300
  records = ["_1a2c7c1f07a03bf47cb635883858422f.lblqlwmygg.acm-validations.aws."]
}

resource "aws_route53_record" "www_acm_validation" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "_60263719a5bd132a7a8af2a903116405.www.oneill.net"
  type    = "CNAME"
  ttl     = 300
  records = ["_d7fef7f4941ad7aa5ae1136c4cd91060.lblqlwmygg.acm-validations.aws."]
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
  records = ["claytono.github.io."]
}

resource "aws_route53_record" "k_subdomain_ns" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "k.oneill.net"
  type    = "NS"
  ttl     = 3600
  records = aws_route53_zone.k_oneill_net.name_servers
}

resource "aws_route53_record" "oneill_luser" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "luser.oneill.net"
  type    = "A"
  ttl     = 300
  records = ["173.73.171.201"]
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

resource "aws_route53_record" "infrastructure_hosts" {
  for_each = var.infrastructure_hosts

  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = each.value.hostname
  type    = "A"
  ttl     = 300
  records = [each.value.ip]
}

# Service CNAME for NUT web interface
resource "aws_route53_record" "nut" {
  zone_id = aws_route53_zone.oneill_net.zone_id
  name    = "nut.oneill.net"
  type    = "CNAME"
  ttl     = 300
  records = ["infrapi.oneill.net"]
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
