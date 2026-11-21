# Credential for writing to VictoriaMetrics through vmauth at vm.k.oneill.net.
#
# Reads need no credential; writes, imports and series deletes do.
# kubernetes/victoria-metrics/externalsecret-vmauth.yaml and .secrets.tmpl
# read the password from this item.

locals {
  vmauth_username = "vmauth"
}

resource "random_password" "vmauth" {
  length  = 32
  special = false
}

resource "onepassword_item" "vmauth" {
  vault      = data.onepassword_vault.infra.uuid
  title      = "victoria-metrics-vmauth"
  url        = "https://vm.k.oneill.net"
  username   = local.vmauth_username
  password   = random_password.vmauth.result
  note_value = <<-EOF
    Managed by OpenTofu.

    HTTP Basic Auth for writes, imports and series deletes through vmauth at
    https://vm.k.oneill.net. Reads need no credential.
  EOF
}
