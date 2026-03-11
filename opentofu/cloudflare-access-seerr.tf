# Cloudflare Access configuration for Seerr (request.oneill.net).
# The account already has a one-time PIN (OTP) identity provider configured.
# Email allowlist is stored in 1Password to keep addresses out of git.

resource "cloudflare_zero_trust_access_policy" "seerr_allow_emails" {
  account_id = local.cloudflare_account_id
  name       = "Allow Seerr users"
  decision   = "allow"

  include = [for email in local.seerr_access_emails : {
    email = { email = trimspace(email) }
  }]
}

resource "cloudflare_zero_trust_access_application" "seerr" {
  account_id       = local.cloudflare_account_id
  name             = "Seerr"
  domain           = "request.oneill.net"
  type             = "self_hosted"
  session_duration = "720h"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.seerr_allow_emails.id
    precedence = 1
  }]
}
