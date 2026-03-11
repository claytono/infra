# Cloudflare Tunnel for exposing internal Kubernetes services externally.
# The tunnel connector (cloudflared) runs in Kubernetes and connects outbound
# to Cloudflare's edge. Traffic to request.oneill.net flows through the tunnel
# to the Seerr service inside the cluster.

resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id = local.cloudflare_account_id
  name       = "homelab"
  config_src = "cloudflare"
}

# Tunnel ingress configuration — routes request.oneill.net to the Seerr
# Kubernetes service. The catch-all rule returns 404 for unmatched hostnames.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = local.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id

  config = {
    ingress = [
      {
        hostname = "request.oneill.net"
        service  = "http://seerr.seerr.svc.cluster.local:5055"
      },
      {
        service = "http_status:404"
      }
    ]
  }
}

# Read the tunnel token for the cloudflared connector
data "cloudflare_zero_trust_tunnel_cloudflared_token" "homelab" {
  account_id = local.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

# Store the tunnel token in 1Password for Kubernetes ExternalSecret
resource "onepassword_item" "cloudflare_tunnel" {
  vault    = data.onepassword_vault.infra.uuid
  title    = "cloudflare-tunnel"
  category = "secure_note"

  note_value = "Cloudflare Tunnel token for the homelab tunnel. Used by cloudflared in Kubernetes. Managed by OpenTofu - do not edit manually."

  section {
    label = "credentials"

    field {
      label = "TUNNEL_TOKEN"
      type  = "CONCEALED"
      value = data.cloudflare_zero_trust_tunnel_cloudflared_token.homelab.token
    }
  }
}

# CNAME pointing request.oneill.net to the tunnel
resource "cloudflare_dns_record" "tunnel_request" {
  zone_id = module.dns.cloudflare_oneill_net_zone_id
  name    = "request.oneill.net"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}
