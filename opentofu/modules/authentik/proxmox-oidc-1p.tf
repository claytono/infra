###############################################
# Proxmox OIDC 1Password item (manually maintained)
###############################################

resource "random_password" "proxmox_oidc" {
  length  = 32
  special = false
}

locals {
  # Terraform is the source of truth for OIDC client credentials
  proxmox_oidc_client_id = "proxmox"
  proxmox_oidc_secret    = random_password.proxmox_oidc.result
}

resource "onepassword_item" "proxmox_oidc" {
  vault    = var.onepassword_vault_uuid
  title    = "proxmox-oidc"
  category = "login"

  note_value = "OIDC client for proxmox. Managed by OpenTofu — do not edit manually."

  section {
    label = "OIDC"
    field {
      label = "client-id"
      type  = "STRING"
      value = local.proxmox_oidc_client_id
    }
    field {
      label = "client-secret"
      type  = "CONCEALED"
      value = local.proxmox_oidc_secret
    }
  }
}
