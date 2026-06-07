# Public, Basic Auth-protected feed endpoint for MinusPod.
#
# Overcast fetches RSS server-side, so the feed hostname must be reachable from
# the public Internet. The Worker protects the public feed with HTTP Basic Auth
# and only forwards read-only podcast feed/asset paths to the Cloudflare Tunnel.

locals {
  minuspod_feed_public_hostname    = "minuspod-feed.oneill.net"
  minuspod_feed_basic_auth_user    = "minuspod"
  minuspod_feed_worker_script_name = "minuspod-feed-basic-auth"
}

resource "random_password" "minuspod_feed_basic_auth" {
  length  = 32
  special = false
}

resource "onepassword_item" "minuspod_feed_basic_auth" {
  vault      = data.onepassword_vault.infra.uuid
  title      = "minuspod-feed-basic-auth"
  url        = "https://${local.minuspod_feed_public_hostname}/tech-brew-ride-home"
  username   = local.minuspod_feed_basic_auth_user
  password   = random_password.minuspod_feed_basic_auth.result
  note_value = <<-EOF
    Managed by OpenTofu.

    Feed-only HTTP Basic Auth credentials for Overcast and other podcast
    clients. These credentials protect the public MinusPod feed URL exposed
    through Cloudflare Tunnel and the minuspod-feed-basic-auth Worker.
  EOF
}

resource "cloudflare_workers_script" "minuspod_feed_basic_auth" {
  account_id         = local.cloudflare_account_id
  script_name        = local.minuspod_feed_worker_script_name
  compatibility_date = "2026-06-07"
  content_file       = "${path.module}/workers/minuspod-feed-basic-auth.js"
  content_sha256     = filesha256("${path.module}/workers/minuspod-feed-basic-auth.js")
  main_module        = "minuspod-feed-basic-auth.js"

  bindings = [
    {
      name = "BASIC_USER"
      type = "plain_text"
      text = local.minuspod_feed_basic_auth_user
    },
    {
      name = "BASIC_PASS"
      type = "secret_text"
      text = random_password.minuspod_feed_basic_auth.result
    },
  ]
}

resource "cloudflare_workers_route" "minuspod_feed_basic_auth" {
  zone_id = module.dns.cloudflare_oneill_net_zone_id
  pattern = "${local.minuspod_feed_public_hostname}/*"
  script  = cloudflare_workers_script.minuspod_feed_basic_auth.script_name
}

resource "cloudflare_dns_record" "tunnel_minuspod_feed" {
  zone_id = module.dns.cloudflare_oneill_net_zone_id
  name    = local.minuspod_feed_public_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}
