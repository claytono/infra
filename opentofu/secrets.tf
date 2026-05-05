# Reference to the existing 1Password vault used by infra
data "onepassword_vault" "infra" {
  uuid = "duipvbtxrc4wl22tw3jsihfo2m"
}

# Vultr API credentials from 1Password
ephemeral "onepassword_item" "vultr_api" {
  vault = data.onepassword_vault.infra.uuid
  title = "Vultr API"
}

# Hetzner Cloud API credentials from 1Password
ephemeral "onepassword_item" "hetzner_cloud_api" {
  vault = data.onepassword_vault.infra.uuid
  title = "hetzner-cloud-api"
}

data "onepassword_item" "resticprofile_rclone" {
  vault = data.onepassword_vault.infra.uuid
  title = "resticprofile-rclone"
}

# Manual companion item for Hetzner WebDAV rclone pass values. The built-in
# `password` fields on the tofu-managed `hetzner-restic-main` /
# `hetzner-restic-xtal` login items stay as the raw WebDAV login passwords.
# This secure note carries only the pre-obscured `RCLONE_CONFIG_HETZNER_WEBDAV_*`
# values that Kubernetes needs for rclone's `webdav pass` setting.
#
# We keep this as a separate item because `rclone obscure` uses a random IV.
# If OpenTofu tried to regenerate the obscured values during plan/apply, the
# result would drift every time even when the underlying raw password had not
# changed.
data "onepassword_item" "hetzner_restic_rclone" {
  vault = data.onepassword_vault.infra.uuid
  title = "hetzner-restic-rclone"
}

data "onepassword_item" "hetzner_velero_rclone" {
  vault = data.onepassword_vault.infra.uuid
  title = "hetzner-velero-rclone"
}

# Tailscale OpenTofu OAuth credentials from 1Password (for managing policy/ACLs/OAuth clients)
data "onepassword_item" "tailscale_opentofu" {
  vault = data.onepassword_vault.infra.uuid
  title = "tailscale-opentofu"
}

# GitHub credentials from 1Password (for managing repository secrets)
ephemeral "onepassword_item" "github_opentofu" {
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
ephemeral "onepassword_item" "openai_admin_api" {
  vault = data.onepassword_vault.infra.uuid
  title = "terraform-openai-admin-key"
}

locals {
  resticprofile_rclone_fields = merge([
    for _, sec in data.onepassword_item.resticprofile_rclone.section_map : {
      for k, v in sec.field_map : k => v.value
    }
  ]...)

  hetzner_restic_rclone_fields = merge([
    for _, sec in data.onepassword_item.hetzner_restic_rclone.section_map : {
      for k, v in sec.field_map : k => v.value
    }
  ]...)

  hetzner_velero_rclone_fields = merge([
    for _, sec in data.onepassword_item.hetzner_velero_rclone.section_map : {
      for k, v in sec.field_map : k => v.value
    }
  ]...)
}

# Read the companion item intentionally and fail early if the manual rclone
# fields are missing. This keeps the relationship between the tofu-managed login
# items and the manual companion secure note explicit in OpenTofu.
resource "terraform_data" "validate_hetzner_restic_rclone" {
  lifecycle {
    precondition {
      condition = alltrue([
        can(local.hetzner_restic_rclone_fields["RCLONE_CONFIG_HETZNER_WEBDAV_RESTIC_MAIN_PASS"]),
        can(local.hetzner_restic_rclone_fields["RCLONE_CONFIG_HETZNER_WEBDAV_RESTIC_XTAL_PASS"]),
        can(local.hetzner_restic_rclone_fields["RCLONE_CONFIG_HETZNER_WEBDAV_ROOT_PASS"]),
      ])
      error_message = "1Password item 'hetzner-restic-rclone' must contain RCLONE_CONFIG_HETZNER_WEBDAV_RESTIC_MAIN_PASS, RCLONE_CONFIG_HETZNER_WEBDAV_RESTIC_XTAL_PASS, and RCLONE_CONFIG_HETZNER_WEBDAV_ROOT_PASS as pre-obscured rclone WebDAV passwords. Run './scripts/bootstrap-secrets --apply rclone'."
    }
  }
}

resource "terraform_data" "validate_hetzner_velero_rclone" {
  lifecycle {
    precondition {
      condition = alltrue([
        can(local.hetzner_velero_rclone_fields["RCLONE_CONFIG_HETZNER_WEBDAV_VELERO_PASS"]),
        can(local.hetzner_velero_rclone_fields["RCLONE_CONFIG_HETZNER_VELERO_PASSWORD"]),
      ])
      error_message = "1Password item 'hetzner-velero-rclone' must contain RCLONE_CONFIG_HETZNER_WEBDAV_VELERO_PASS and RCLONE_CONFIG_HETZNER_VELERO_PASSWORD as pre-obscured rclone passwords. Run './scripts/bootstrap-secrets --apply rclone'."
    }
  }
}

# Local values for easier reference
locals {
  vultr_api_key = ephemeral.onepassword_item.vultr_api.password
  hcloud_token  = ephemeral.onepassword_item.hetzner_cloud_api.password

  # Tailscale OpenTofu credentials for policy and OAuth client management
  tailscale_fields = merge([
    for _, sec in data.onepassword_item.tailscale_opentofu.section_map : {
      for k, v in sec.field_map : k => v.value
    }
  ]...)

  tailscale_client_id     = local.tailscale_fields["client_id"]
  tailscale_client_secret = local.tailscale_fields["client_secret"]

  # GitHub token for managing repository secrets
  github_token = ephemeral.onepassword_item.github_opentofu.password

  # OpenAI admin API key for managing API keys
  openai_api_key = ephemeral.onepassword_item.openai_admin_api.password
}

# Authentik credentials from 1Password (used to configure provider)
data "onepassword_item" "ak_tool" {
  vault = data.onepassword_vault.infra.uuid
  title = "ak-tool"
}

locals {
  ak_tool_fields = merge([
    for _, sec in data.onepassword_item.ak_tool.section_map : {
      for k, v in sec.field_map : k => v.value
    }
  ]...)

  authentik_url   = local.ak_tool_fields["base_url"]
  authentik_token = local.ak_tool_fields["api_token"]
}

# Unifi credentials from 1Password (used to configure provider for DHCP reservations)
ephemeral "onepassword_item" "unifi_terraform" {
  vault = data.onepassword_vault.infra.uuid
  title = "unifi-opentofu-api-key"
}

locals {
  unifi_api_key = ephemeral.onepassword_item.unifi_terraform.password
  unifi_api_url = "https://udmp.oneill.net"
}

# Proxmox credentials from 1Password (used to configure provider for VM management)
ephemeral "onepassword_item" "proxmox_opentofu" {
  vault = data.onepassword_vault.infra.uuid
  title = "proxmox-opentofu"
}

locals {
  proxmox_api_token = "${ephemeral.onepassword_item.proxmox_opentofu.username}=${ephemeral.onepassword_item.proxmox_opentofu.credential}"
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
  healthchecks_cloud_fields = merge([
    for _, sec in data.onepassword_item.healthchecks_cloud.section_map : {
      for k, v in sec.field_map : k => v.value
    }
  ]...)
  healthchecks_selfhosted_fields = merge([
    for _, sec in data.onepassword_item.healthchecks_selfhosted.section_map : {
      for k, v in sec.field_map : k => v.value
    }
  ]...)

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

# Claude Code OAuth token from 1Password
data "onepassword_item" "claude_code_oauth_token" {
  vault = data.onepassword_vault.infra.uuid
  title = "claude-code-api-token"
}

# Cloudflare credentials from 1Password (for DNS management)
data "onepassword_item" "cloudflare_opentofu" {
  vault = data.onepassword_vault.infra.uuid
  title = "cloudflare-opentofu"
}

locals {
  cloudflare_fields = merge([
    for _, sec in data.onepassword_item.cloudflare_opentofu.section_map : {
      for k, v in sec.field_map : k => v.value
    }
  ]...)

  cloudflare_api_token  = local.cloudflare_fields["api_token"]
  cloudflare_account_id = local.cloudflare_fields["account_id"]
}

# Cloudflare Access email allowlist from 1Password (keeps addresses out of git)
data "onepassword_item" "cloudflare_access_seerr" {
  vault = data.onepassword_vault.infra.uuid
  title = "cloudflare-access-seerr"
}

locals {
  cloudflare_access_seerr_fields = merge([
    for _, sec in data.onepassword_item.cloudflare_access_seerr.section_map : {
      for k, v in sec.field_map : k => v.value
    }
  ]...)

  seerr_access_emails = split(",", local.cloudflare_access_seerr_fields["allowed_emails"])
}
