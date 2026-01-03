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

# OpenAI admin API key from 1Password (for managing API keys)
data "onepassword_item" "openai_admin_api" {
  vault = data.onepassword_vault.infra.uuid
  title = "terraform-openai-admin-key"
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

  # OpenAI admin API key for managing API keys
  openai_api_key = data.onepassword_item.openai_admin_api.password
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

# Unifi credentials from 1Password (used to configure provider for DHCP reservations)
data "onepassword_item" "unifi_terraform" {
  vault = data.onepassword_vault.infra.uuid
  title = "unifi-opentofu-api-key"
}

locals {
  unifi_api_key = data.onepassword_item.unifi_terraform.password
  unifi_api_url = "https://udmp.oneill.net"
}

# Proxmox credentials from 1Password (used to configure provider for VM management)
data "onepassword_item" "proxmox_opentofu" {
  vault = data.onepassword_vault.infra.uuid
  title = "proxmox-opentofu"
}

locals {
  proxmox_api_token = "${data.onepassword_item.proxmox_opentofu.username}=${data.onepassword_item.proxmox_opentofu.credential}"
}

# Healthchecks API keys from 1Password (cloud and self-hosted instances)
data "onepassword_item" "healthchecks_cloud" {
  vault = data.onepassword_vault.infra.uuid
  title = "healthchecks-io"
}

data "onepassword_item" "healthchecks_selfhosted" {
  vault = data.onepassword_vault.infra.uuid
  title = "healthchecks"
}

locals {
  healthchecks_cloud_fields = {
    for f in flatten([
      for sec in data.onepassword_item.healthchecks_cloud.section : sec.field
    ]) : f.label => f.value
  }
  healthchecks_selfhosted_fields = {
    for f in flatten([
      for sec in data.onepassword_item.healthchecks_selfhosted.section : sec.field
    ]) : f.label => f.value
  }

  healthchecks_cloud_api_key      = local.healthchecks_cloud_fields["API_KEY"]
  healthchecks_selfhosted_api_key = local.healthchecks_selfhosted_fields["api-key"]
  healthchecks_canary_api_key     = local.healthchecks_selfhosted_fields["canary-api-key"]
}

# Semaphore credentials from 1Password
data "onepassword_item" "semaphore_api" {
  vault = data.onepassword_vault.infra.uuid
  title = "semaphore-api-token"
}

data "onepassword_item" "semaphore_ansible_ssh" {
  vault = data.onepassword_vault.infra.uuid
  title = "Semaphore Ansible"
}

locals {
  semaphore_api_token       = data.onepassword_item.semaphore_api.password
  semaphore_ansible_ssh_key = data.onepassword_item.semaphore_ansible_ssh.private_key
}
