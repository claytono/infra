# Manage the existing B2 bucket with master key (has writeBuckets permission)
resource "b2_bucket" "restic_backups" {
  bucket_name = "cmo-restic"
  bucket_type = "allPrivate"

  # Lifecycle rule: delete old versions 1 day after hidden (minimum allowed)
  lifecycle_rules {
    file_name_prefix             = "" # Apply to all files in bucket
    days_from_hiding_to_deleting = 1
  }
}

# Velero Kubernetes volume backups
resource "b2_bucket" "velero_backups" {
  bucket_name = "cmo-velero"
  bucket_type = "allPrivate"

  # Lifecycle rule: delete old versions 1 day after hidden (minimum allowed)
  lifecycle_rules {
    file_name_prefix             = "" # Apply to all files in bucket
    days_from_hiding_to_deleting = 1
  }
}

# Application key for Velero with access to velero-backups bucket
resource "b2_application_key" "velero" {
  key_name   = "velero-backups"
  bucket_ids = [b2_bucket.velero_backups.bucket_id]

  capabilities = [
    "listBuckets",
    "listFiles",
    "readFiles",
    "shareFiles",
    "writeFiles",
    "deleteFiles",
    "writeBuckets" # Needed for rclone S3 API directory creation
  ]
}

# Generate encryption password for rclone
resource "random_password" "rclone_encryption" {
  length  = 32
  special = true
}

# Generate S3 credentials for rclone virtual S3 server
resource "random_password" "rclone_s3_secret" {
  length  = 32
  special = true
}

# Generate Kopia repository password
resource "random_password" "kopia_password" {
  length  = 32
  special = true
}

# Store Velero B2 credentials in 1Password
resource "onepassword_item" "velero_b2" {
  vault      = data.onepassword_vault.infra.uuid
  title      = "velero-b2-credentials"
  category   = "login"
  note_value = "Velero backup credentials for B2 storage with Kopia encryption. Managed by OpenTofu - do not edit manually."

  section {
    label = "credentials"

    field {
      label = "RCLONE_CONFIG_B2_ACCOUNT"
      type  = "STRING"
      value = b2_application_key.velero.application_key_id
    }

    field {
      label = "RCLONE_CONFIG_B2_KEY"
      type  = "CONCEALED"
      value = b2_application_key.velero.application_key
    }

    field {
      label = "RCLONE_ENCRYPTION_PASSWORD"
      type  = "CONCEALED"
      value = random_password.rclone_encryption.result
    }

    field {
      label = "RCLONE_S3_ACCESS_KEY"
      type  = "STRING"
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
