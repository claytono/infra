resource "aws_route53_zone" "fnord_net" {
  name              = "fnord.net"
  delegation_set_id = aws_route53_delegation_set.main.id
}

resource "aws_route53_record" "fnord_mx" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "fnord.net"
  type    = "MX"
  ttl     = 86400
  records = [
    "10 mx-1.pobox.com.",
    "10 mx-2.pobox.com.",
    "10 mx-3.pobox.com."
  ]
}

# Fastmail DKIM CNAMEs
resource "aws_route53_record" "dkim_fn1_fnord" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "fm1._domainkey.fnord.net"
  type    = "CNAME"
  ttl     = 3600
  records = ["fm1.fnord.net.dkim.fmhosted.com"]
}

resource "aws_route53_record" "dkim_fn2_fnord" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "fm2._domainkey.fnord.net"
  type    = "CNAME"
  ttl     = 3600
  records = ["fm2.fnord.net.dkim.fmhosted.com"]
}

resource "aws_route53_record" "dkim_fn3_fnord" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "fm3._domainkey.fnord.net"
  type    = "CNAME"
  ttl     = 3600
  records = ["fm3.fnord.net.dkim.fmhosted.com"]
}

# SPF TXT for Fastmail (messagingengine.com)
resource "aws_route53_record" "spf_fnord" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "fnord.net"
  type    = "TXT"
  ttl     = 3600
  records = [
    "v=spf1 include:_spf.google.com include:spf.messagingengine.com ~all"
  ]
}

resource "aws_route53_record" "lucy" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "lucy.fnord.net"
  type    = "CNAME"
  ttl     = 604800
  records = ["lucy.allakhazam.com."]
}

resource "aws_route53_record" "ns1_a" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "ns1.fnord.net"
  type    = "A"
  ttl     = 86400
  records = [local.nameserver_ips.ns1.ipv4]
}

resource "aws_route53_record" "ns1_aaaa" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "ns1.fnord.net"
  type    = "AAAA"
  ttl     = 86400
  records = [local.nameserver_ips.ns1.ipv6]
}

resource "aws_route53_record" "ns2_a" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "ns2.fnord.net"
  type    = "A"
  ttl     = 86400
  records = [local.nameserver_ips.ns2.ipv4]
}

resource "aws_route53_record" "ns2_aaaa" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "ns2.fnord.net"
  type    = "AAAA"
  ttl     = 86400
  records = [local.nameserver_ips.ns2.ipv6]
}

resource "aws_route53_record" "ns3_a" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "ns3.fnord.net"
  type    = "A"
  ttl     = 86400
  records = [local.nameserver_ips.ns3.ipv4]
}

resource "aws_route53_record" "ns3_aaaa" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "ns3.fnord.net"
  type    = "AAAA"
  ttl     = 86400
  records = [local.nameserver_ips.ns3.ipv6]
}

resource "aws_route53_record" "ns4_a" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "ns4.fnord.net"
  type    = "A"
  ttl     = 86400
  records = [local.nameserver_ips.ns4.ipv4]
}

resource "aws_route53_record" "ns4_aaaa" {
  zone_id = aws_route53_zone.fnord_net.zone_id
  name    = "ns4.fnord.net"
  type    = "AAAA"
  ttl     = 86400
  records = [local.nameserver_ips.ns4.ipv6]
}

# Cloudflare zone for fnord.net
resource "cloudflare_zone" "fnord_net" {
  account = {
    id = var.cloudflare_account_id
  }
  name = "fnord.net"
}

# MX records (one resource per server)
resource "cloudflare_dns_record" "fnord_mx1" {
  zone_id  = cloudflare_zone.fnord_net.id
  name     = "fnord.net"
  type     = "MX"
  content  = "mx-1.pobox.com"
  priority = 10
  ttl      = 86400
}

resource "cloudflare_dns_record" "fnord_mx2" {
  zone_id  = cloudflare_zone.fnord_net.id
  name     = "fnord.net"
  type     = "MX"
  content  = "mx-2.pobox.com"
  priority = 10
  ttl      = 86400
}

resource "cloudflare_dns_record" "fnord_mx3" {
  zone_id  = cloudflare_zone.fnord_net.id
  name     = "fnord.net"
  type     = "MX"
  content  = "mx-3.pobox.com"
  priority = 10
  ttl      = 86400
}

# SPF TXT record
resource "cloudflare_dns_record" "fnord_spf" {
  zone_id = cloudflare_zone.fnord_net.id
  name    = "fnord.net"
  type    = "TXT"
  content = "\"v=spf1 include:_spf.google.com include:spf.messagingengine.com ~all\""
  ttl     = 3600
}

# DKIM CNAMEs (Fastmail)
resource "cloudflare_dns_record" "dkim_fn1_fnord" {
  zone_id = cloudflare_zone.fnord_net.id
  name    = "fm1._domainkey.fnord.net"
  type    = "CNAME"
  content = "fm1.fnord.net.dkim.fmhosted.com"
  ttl     = 3600
}

resource "cloudflare_dns_record" "dkim_fn2_fnord" {
  zone_id = cloudflare_zone.fnord_net.id
  name    = "fm2._domainkey.fnord.net"
  type    = "CNAME"
  content = "fm2.fnord.net.dkim.fmhosted.com"
  ttl     = 3600
}

resource "cloudflare_dns_record" "dkim_fn3_fnord" {
  zone_id = cloudflare_zone.fnord_net.id
  name    = "fm3._domainkey.fnord.net"
  type    = "CNAME"
  content = "fm3.fnord.net.dkim.fmhosted.com"
  ttl     = 3600
}

# lucy CNAME
resource "cloudflare_dns_record" "lucy" {
  zone_id = cloudflare_zone.fnord_net.id
  name    = "lucy.fnord.net"
  type    = "CNAME"
  content = "lucy.allakhazam.com"
  ttl     = 86400
}
