# Scoped Cloudflare API token for DNS-01 challenge validation on oneill.net
resource "cloudflare_account_token" "dns_write" {
  account_id = local.cloudflare_account_id
  name       = "cloudflare-dns-write"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = data.cloudflare_account_api_token_permission_groups_list.dns_write.result[0].id
    }]
    resources = jsonencode({
      "com.cloudflare.api.account.zone.${module.dns.cloudflare_oneill_net_zone_id}" = "*"
    })
  }]
}

# Store token and zone ID in 1Password for Kubernetes ExternalSecret
resource "onepassword_item" "cloudflare_dns_write" {
  vault    = data.onepassword_vault.infra.uuid
  title    = "cloudflare-dns-write"
  category = "secure_note"

  note_value = "Cloudflare API token for DNS-01 ACME challenges on oneill.net. Managed by OpenTofu - do not edit manually."

  section {
    label = "credentials"

    field {
      label = "CF_Token"
      type  = "CONCEALED"
      value = cloudflare_account_token.dns_write.value
    }

    field {
      label = "CF_Zone_ID"
      type  = "STRING"
      value = module.dns.cloudflare_oneill_net_zone_id
    }
  }
}
