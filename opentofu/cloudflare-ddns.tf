# Look up the "DNS Write" permission group ID
data "cloudflare_account_api_token_permission_groups_list" "dns_write" {
  account_id = local.cloudflare_account_id
  name       = "DNS Write"
}

# Scoped Cloudflare API token for DDNS updates to fnord.net and oneill.net
resource "cloudflare_account_token" "ddns" {
  account_id = local.cloudflare_account_id
  name       = "cloudflare-ddns"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = data.cloudflare_account_api_token_permission_groups_list.dns_write.result[0].id
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.zone.${module.dns.cloudflare_fnord_net_zone_id}"  = "*"
      "com.cloudflare.api.account.zone.${module.dns.cloudflare_oneill_net_zone_id}" = "*"
    })
  }]
}

# Store token in 1Password for Kubernetes ExternalSecret
resource "onepassword_item" "cloudflare_ddns" {
  vault    = data.onepassword_vault.infra.uuid
  title    = "cloudflare-ddns"
  category = "secure_note"

  note_value = "Cloudflare API token for DDNS updates to fnord.net and oneill.net. Managed by OpenTofu - do not edit manually."

  section {
    label = "credentials"

    field {
      label = "CLOUDFLARE_API_TOKEN"
      type  = "CONCEALED"
      value = cloudflare_account_token.ddns.value
    }
  }
}
