resource "random_password" "storage_box_parent" {
  length           = 32
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  override_special = "^!$%()=?+#-.,:~*@{}_&"
}

resource "random_password" "storage_box_main" {
  length           = 32
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  override_special = "^!$%()=?+#-.,:~*@{}_&"
}

resource "random_password" "storage_box_xtal" {
  length           = 32
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  override_special = "^!$%()=?+#-.,:~*@{}_&"
}

resource "random_password" "storage_box_velero" {
  length           = 32
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  min_upper        = 1
  override_special = "^!$%()=?+#-.,:~*@{}_&"
}

resource "random_password" "rclone_encryption" {
  length  = 32
  special = true
}

resource "random_password" "rclone_s3_secret" {
  length  = 32
  special = true
}

resource "random_password" "kopia_password" {
  length  = 32
  special = true
}

resource "hcloud_storage_box" "backups" {
  location         = "fsn1" # Falkenstein, Germany
  storage_box_type = "bx41" # 10 TB class
  name             = "homelab-backups"
  password         = random_password.storage_box_parent.result
  access_settings = {
    reachable_externally = true
    webdav_enabled       = true
  }

  delete_protection = true

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [ssh_keys]
  }
}

resource "onepassword_item" "hetzner_storage_box_parent" {
  vault      = data.onepassword_vault.infra.uuid
  title      = "hetzner-storage-box-parent"
  url        = local.hetzner_storage_box_urls.parent
  username   = hcloud_storage_box.backups.username
  password   = random_password.storage_box_parent.result
  note_value = <<-EOF
    Managed by OpenTofu.

    This login item holds the raw parent Hetzner Storage Box WebDAV credentials.
    The companion secure note `hetzner-restic-rclone` stores `RCLONE_CONFIG_HETZNER_WEBDAV_ROOT_PASS`, which must be the literal output of `rclone obscure` for this item's raw built-in password.
    If this password rotates, run `./scripts/bootstrap-secrets --apply rclone` to populate any missing companion fields.
  EOF

  section {
    label = "credentials"

    field {
      label = "url"
      value = local.hetzner_storage_box_urls.parent
    }
  }
}

# Keep SSH enabled during migration so SFTP remains available for WebDAV
# troubleshooting and emergency access.
resource "hcloud_storage_box_subaccount" "main" {
  storage_box_id = hcloud_storage_box.backups.id
  home_directory = "restic-main"
  password       = random_password.storage_box_main.result
  description    = "restic main"

  access_settings = {
    ssh_enabled          = true
    reachable_externally = true
    webdav_enabled       = true
  }
}

resource "hcloud_storage_box_subaccount" "xtal" {
  storage_box_id = hcloud_storage_box.backups.id
  home_directory = "restic-xtal"
  password       = random_password.storage_box_xtal.result
  description    = "restic xtal"

  access_settings = {
    ssh_enabled          = true
    reachable_externally = true
    webdav_enabled       = true
  }
}

resource "hcloud_storage_box_subaccount" "velero" {
  storage_box_id = hcloud_storage_box.backups.id
  home_directory = "velero"
  password       = random_password.storage_box_velero.result
  description    = "velero kopia repo"

  access_settings = {
    ssh_enabled          = true
    reachable_externally = true
    webdav_enabled       = true
  }
}

locals {
  hetzner_storage_box_urls = {
    parent = "https://${hcloud_storage_box.backups.server}"
    main   = "https://${hcloud_storage_box_subaccount.main.server}"
    xtal   = "https://${hcloud_storage_box_subaccount.xtal.server}"
    velero = "https://${hcloud_storage_box_subaccount.velero.server}"
  }

  hetzner_restic_note_context = {
    main = {
      destination           = "main"
      url_description       = "is consumed directly by `kubernetes/restic/shared/externalsecret.yaml`"
      obscured_pass_setting = "RCLONE_CONFIG_HETZNER_WEBDAV_RESTIC_MAIN_PASS"
    }
    xtal = {
      destination           = "xtal"
      url_description       = "is the xtal destination URL consumed by the same restic/rclone pattern"
      obscured_pass_setting = "RCLONE_CONFIG_HETZNER_WEBDAV_RESTIC_XTAL_PASS"
    }
  }

  hetzner_restic_note_values = {
    for name, context in local.hetzner_restic_note_context : name => <<-EOF
      Managed by OpenTofu.

      This login item holds the raw Hetzner Storage Box WebDAV credentials for the ${context.destination} restic destination.
      - `username` and the built-in `password` are the raw WebDAV login credentials.
      - `url` ${context.url_description}.
      - `RCLONE_CONFIG_HETZNER_RESTIC_PASSWORD` and `RCLONE_CONFIG_HETZNER_RESTIC_PASSWORD2` are the crypt backend passwords copied from `resticprofile-rclone`.

      The companion secure note `hetzner-restic-rclone` stores `${context.obscured_pass_setting}`, which must be the literal output of `rclone obscure` for this item's raw built-in password.
      If this password rotates, update the companion item's obscured field too.
    EOF
  }
}

resource "onepassword_item" "hetzner_restic_main" {
  vault      = data.onepassword_vault.infra.uuid
  title      = "hetzner-restic-main"
  url        = local.hetzner_storage_box_urls.main
  username   = hcloud_storage_box_subaccount.main.username
  note_value = local.hetzner_restic_note_values.main
  # Keep this raw; rclone's pre-obscured WebDAV password is maintained in the
  # companion item read and validated from `secrets.tf`.
  password = random_password.storage_box_main.result

  section {
    label = "credentials"

    field {
      label = "url"
      value = local.hetzner_storage_box_urls.main
    }

    field {
      label = "RCLONE_CONFIG_HETZNER_RESTIC_PASSWORD"
      type  = "CONCEALED"
      value = local.resticprofile_rclone_fields["RCLONE_CONFIG_CRYPT_PASSWORD"]
    }

    field {
      label = "RCLONE_CONFIG_HETZNER_RESTIC_PASSWORD2"
      type  = "CONCEALED"
      value = local.resticprofile_rclone_fields["RCLONE_CONFIG_CRYPT_PASSWORD2"]
    }
  }
}

resource "onepassword_item" "hetzner_restic_xtal" {
  vault      = data.onepassword_vault.infra.uuid
  title      = "hetzner-restic-xtal"
  url        = local.hetzner_storage_box_urls.xtal
  username   = hcloud_storage_box_subaccount.xtal.username
  note_value = local.hetzner_restic_note_values.xtal
  # Keep this raw; rclone's pre-obscured WebDAV password is maintained in the
  # companion item read and validated from `secrets.tf`.
  password = random_password.storage_box_xtal.result

  section {
    label = "credentials"

    field {
      label = "url"
      value = local.hetzner_storage_box_urls.xtal
    }

    field {
      label = "RCLONE_CONFIG_HETZNER_RESTIC_PASSWORD"
      type  = "CONCEALED"
      value = local.resticprofile_rclone_fields["RCLONE_CONFIG_CRYPT_PASSWORD"]
    }

    field {
      label = "RCLONE_CONFIG_HETZNER_RESTIC_PASSWORD2"
      type  = "CONCEALED"
      value = local.resticprofile_rclone_fields["RCLONE_CONFIG_CRYPT_PASSWORD2"]
    }
  }
}

resource "onepassword_item" "hetzner_velero" {
  vault      = data.onepassword_vault.infra.uuid
  title      = "hetzner-velero"
  url        = local.hetzner_storage_box_urls.velero
  username   = hcloud_storage_box_subaccount.velero.username
  password   = random_password.storage_box_velero.result
  note_value = <<-EOF
    Managed by OpenTofu.

    This login item holds the raw Hetzner Storage Box WebDAV credentials and raw Velero rclone encryption password.
    The companion secure note `hetzner-velero-rclone` stores `RCLONE_CONFIG_HETZNER_WEBDAV_VELERO_PASS` and `RCLONE_CONFIG_HETZNER_VELERO_PASSWORD`, which must be the literal output of `rclone obscure` for the corresponding raw values.
    If the raw WebDAV or encryption password rotates, run `./scripts/bootstrap-secrets --apply rclone` to populate any missing companion fields.
  EOF

  section {
    label = "credentials"

    field {
      label = "url"
      value = local.hetzner_storage_box_urls.velero
    }

    field {
      label = "RCLONE_ENCRYPTION_PASSWORD"
      type  = "CONCEALED"
      value = random_password.rclone_encryption.result
    }

    field {
      label = "RCLONE_S3_ACCESS_KEY"
      value = "velero"
    }

    field {
      label = "RCLONE_S3_SECRET_KEY"
      type  = "CONCEALED"
      value = random_password.rclone_s3_secret.result
    }

    field {
      label = "KOPIA_PASSWORD"
      type  = "CONCEALED"
      value = random_password.kopia_password.result
    }
  }
}

output "hetzner_storage_box_main_server" {
  value = hcloud_storage_box_subaccount.main.server
}

output "hetzner_storage_box_xtal_server" {
  value = hcloud_storage_box_subaccount.xtal.server
}

output "hetzner_storage_box_velero_server" {
  value = hcloud_storage_box_subaccount.velero.server
}
