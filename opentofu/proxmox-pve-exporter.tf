# Proxmox API user and token for prometheus-pve-exporter
# Read-only access (PVEAuditor) for cluster, node, and VM metrics

resource "proxmox_virtual_environment_user" "pve_exporter" {
  user_id = "pve-exporter@pve"
  comment = "Prometheus PVE exporter - managed by OpenTofu"
  enabled = true
}

resource "proxmox_virtual_environment_acl" "pve_exporter" {
  path      = "/"
  role_id   = "PVEAuditor"
  user_id   = proxmox_virtual_environment_user.pve_exporter.user_id
  propagate = true
}

resource "proxmox_virtual_environment_user_token" "pve_exporter" {
  user_id               = proxmox_virtual_environment_user.pve_exporter.user_id
  token_name            = "exporter"
  comment               = "Prometheus PVE exporter - managed by OpenTofu"
  privileges_separation = false
}

resource "onepassword_item" "pve_exporter" {
  vault    = data.onepassword_vault.infra.uuid
  title    = "prometheus-pve-exporter"
  category = "login"

  section {
    label = "Token"

    field {
      label = "credential"
      type  = "CONCEALED"
      value = split("=", proxmox_virtual_environment_user_token.pve_exporter.value)[1]
    }
  }

  note_value = "Proxmox API token for prometheus-pve-exporter. Managed by OpenTofu."
}
