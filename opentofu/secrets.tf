# Reference to the existing Kubernetes vault
data "onepassword_vault" "kubernetes" {
  uuid = "duipvbtxrc4wl22tw3jsihfo2m"
}

# Vultr API credentials from 1Password
data "onepassword_item" "vultr_api" {
  vault = data.onepassword_vault.kubernetes.uuid
  title = "Vultr API"
}

# Backblaze B2 credentials from 1Password (master key with writeBuckets permission)
data "onepassword_item" "terraform_b2" {
  vault = data.onepassword_vault.kubernetes.uuid
  title = "terraform-b2"
}

# Tailscale OpenTofu OAuth credentials from 1Password (for managing policy/ACLs/OAuth clients)
data "onepassword_item" "tailscale_opentofu" {
  vault = data.onepassword_vault.kubernetes.uuid
  title = "tailscale-opentofu"
}

# GitHub credentials from 1Password (for managing repository secrets)
data "onepassword_item" "github_opentofu" {
  vault = data.onepassword_vault.kubernetes.uuid
  title = "github-opentofu"
}

# ArgoCD GitHub Actions token from 1Password
data "onepassword_item" "argocd_github_actions_token" {
  vault = data.onepassword_vault.kubernetes.uuid
  title = "argocd-github-actions-token"
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
