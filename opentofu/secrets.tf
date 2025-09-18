# Reference to the existing 1Password vault used by infra
data "onepassword_vault" "infra" {
  uuid = "duipvbtxrc4wl22tw3jsihfo2m"
}

# Vultr API credentials from 1Password
data "onepassword_item" "vultr_api" {
  vault = data.onepassword_vault.infra.uuid
  title = "Vultr API"
}

# Backblaze B2 credentials from 1Password (master key with writeBuckets permission)
data "onepassword_item" "terraform_b2" {
  vault = data.onepassword_vault.infra.uuid
  title = "terraform-b2"
}

# Tailscale OpenTofu OAuth credentials from 1Password (for managing policy/ACLs/OAuth clients)
data "onepassword_item" "tailscale_opentofu" {
  vault = data.onepassword_vault.infra.uuid
  title = "tailscale-opentofu"
}

# GitHub credentials from 1Password (for managing repository secrets)
data "onepassword_item" "github_opentofu" {
  vault = data.onepassword_vault.infra.uuid
  title = "github-opentofu"
}

# ArgoCD GitHub Actions token from 1Password
data "onepassword_item" "argocd_github_actions_token" {
  vault = data.onepassword_vault.infra.uuid
  title = "argocd-github-actions-token"
}

# Cachix auth token from 1Password
data "onepassword_item" "cachix_auth_token" {
  vault = data.onepassword_vault.infra.uuid
  title = "cachix-auth-token"
}

# Clean field mapping for B2 credentials
locals {
  b2_fields = {
    for f in flatten([
      for sec in data.onepassword_item.terraform_b2.section : sec.field
    ]) : f.label => f.value
  }
}

# Local values for easier reference
locals {
  vultr_api_key = data.onepassword_item.vultr_api.password

  # B2 credentials using clean field mapping
  b2_application_key_id = local.b2_fields["RCLONE_CONFIG_B2_ACCOUNT"]
  b2_application_key    = local.b2_fields["RCLONE_CONFIG_B2_KEY"]

  # Tailscale OpenTofu credentials for policy and OAuth client management
  tailscale_fields = {
    for f in flatten([
      for sec in data.onepassword_item.tailscale_opentofu.section : sec.field
    ]) : f.label => f.value
  }

  tailscale_client_id     = local.tailscale_fields["client_id"]
  tailscale_client_secret = local.tailscale_fields["client_secret"]

  # GitHub token for managing repository secrets
  github_token = data.onepassword_item.github_opentofu.password
}

# Authentik credentials from 1Password (used to configure provider)
data "onepassword_item" "ak_tool" {
  vault = data.onepassword_vault.infra.uuid
  title = "ak-tool"
}

locals {
  ak_tool_fields = {
    for f in flatten([
      for sec in data.onepassword_item.ak_tool.section : sec.field
    ]) : f.label => f.value
  }

  authentik_url   = local.ak_tool_fields["base_url"]
  authentik_token = local.ak_tool_fields["api_token"]
}
