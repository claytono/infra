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
