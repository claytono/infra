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

resource "hcloud_storage_box" "backups" {
  location         = "fsn1" # Falkenstein, Germany
  storage_box_type = "bx41" # 10 TB class
  name             = "homelab-backups"
  password         = random_password.storage_box_parent.result
  access_settings = {
    webdav_enabled       = true
    ssh_enabled          = false
    samba_enabled        = false
    reachable_externally = true
    zfs_enabled          = false
  }

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}

resource "onepassword_item" "hetzner_storage_box_parent" {
  vault    = data.onepassword_vault.infra.uuid
  title    = "hetzner-storage-box-parent"
  category = "login"
  url      = "https://${hcloud_storage_box.backups.server}"
  username = hcloud_storage_box.backups.username
  password = random_password.storage_box_parent.result

  section {
    label = "credentials"

    field {
      label = "url"
      type  = "STRING"
      value = "https://${hcloud_storage_box.backups.server}"
    }
  }
}

resource "hcloud_storage_box_subaccount" "main" {
  storage_box_id = hcloud_storage_box.backups.id
  home_directory = "restic-main"
  password       = random_password.storage_box_main.result
  description    = "restic main"

  access_settings = {
    webdav_enabled       = true
    ssh_enabled          = true
    samba_enabled        = false
    reachable_externally = true
    readonly             = false
  }
}

resource "hcloud_storage_box_subaccount" "xtal" {
  storage_box_id = hcloud_storage_box.backups.id
  home_directory = "restic-xtal"
  password       = random_password.storage_box_xtal.result
  description    = "restic xtal"

  access_settings = {
    webdav_enabled       = true
    ssh_enabled          = true
    samba_enabled        = false
    reachable_externally = true
    readonly             = false
  }
}

resource "hcloud_storage_box_subaccount" "velero" {
  storage_box_id = hcloud_storage_box.backups.id
  home_directory = "velero"
  password       = random_password.storage_box_velero.result
  description    = "velero kopia repo"

  access_settings = {
    webdav_enabled       = true
    ssh_enabled          = true
    samba_enabled        = false
    reachable_externally = true
    readonly             = false
  }
}

resource "onepassword_item" "hetzner_restic_main" {
  vault    = data.onepassword_vault.infra.uuid
  title    = "hetzner-restic-main"
  category = "login"
  url      = "https://${hcloud_storage_box_subaccount.main.server}"
  username = hcloud_storage_box_subaccount.main.username
  password = random_password.storage_box_main.result

  section {
    label = "credentials"

    field {
      label = "url"
      type  = "STRING"
      value = "https://${hcloud_storage_box_subaccount.main.server}"
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
  vault    = data.onepassword_vault.infra.uuid
  title    = "hetzner-restic-xtal"
  category = "login"
  url      = "https://${hcloud_storage_box_subaccount.xtal.server}"
  username = hcloud_storage_box_subaccount.xtal.username
  password = random_password.storage_box_xtal.result

  section {
    label = "credentials"

    field {
      label = "url"
      type  = "STRING"
      value = "https://${hcloud_storage_box_subaccount.xtal.server}"
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
  vault    = data.onepassword_vault.infra.uuid
  title    = "hetzner-velero"
  category = "login"
  url      = "https://${hcloud_storage_box_subaccount.velero.server}"
  username = hcloud_storage_box_subaccount.velero.username
  password = random_password.storage_box_velero.result

  section {
    label = "credentials"

    field {
      label = "url"
      type  = "STRING"
      value = "https://${hcloud_storage_box_subaccount.velero.server}"
    }

    field {
      label = "RCLONE_ENCRYPTION_PASSWORD"
      type  = "CONCEALED"
      value = local.velero_b2_credentials_fields["RCLONE_ENCRYPTION_PASSWORD"]
    }

    field {
      label = "RCLONE_S3_ACCESS_KEY"
      type  = "STRING"
      value = local.velero_b2_credentials_fields["RCLONE_S3_ACCESS_KEY"]
    }

    field {
      label = "RCLONE_S3_SECRET_KEY"
      type  = "CONCEALED"
      value = local.velero_b2_credentials_fields["RCLONE_S3_SECRET_KEY"]
    }

    field {
      label = "KOPIA_PASSWORD"
      type  = "CONCEALED"
      value = local.velero_b2_credentials_fields["KOPIA_PASSWORD"]
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
