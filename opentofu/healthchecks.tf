# Heartbeat canary meta-monitoring for self-hosted healthchecks
#
# Flow: CronJob pings canary hourly -> canary times out after 50min -> goes DOWN
#       -> sends email to cloud -> cloud receives ping -> stays green
#
# The CronJob is in kubernetes/healthchecks/cronjob-canary-ping.yaml
# This tests: healthchecks app, DB, sendalerts, SMTP relay, Gmail delivery

# Look up email channel on cloud instance
data "healthchecksio_channel" "cloud_email" {
  provider = healthchecksio.cloud
  kind     = "email"
}

# Cloud check - receives email pings from self-hosted heartbeat canary
resource "healthchecksio_check" "self_hosted_monitor" {
  provider = healthchecksio.cloud

  name     = "hc.k.oneill.net"
  desc     = "Self-hosted healthchecks - receives email ping from heartbeat canary"
  timeout  = 3600 # 1 hour - expects email ping every hour
  grace    = 1800 # 30 minutes grace for email delivery delays
  channels = [data.healthchecksio_channel.cloud_email.id]
}

# Look up email channel on canary project (configured to email cloud check)
data "healthchecksio_channel" "canary_email" {
  provider = healthchecksio.canary
  kind     = "email"
}

# Self-hosted heartbeat canary - pinged hourly by CronJob, times out after 50min
# Each DOWN transition triggers email to cloud check
resource "healthchecksio_check" "heartbeat_canary" {
  provider = healthchecksio.canary

  name     = "Heartbeat Canary"
  desc     = "Pinged hourly by CronJob, times out after 50min, DOWN alert emails cloud"
  timeout  = 3000 # 50 minutes - goes DOWN 10min before next hourly ping
  grace    = 300  # 5 minutes
  channels = [data.healthchecksio_channel.canary_email.id]
}

# =============================================================================
# Self-hosted checks (main project)
# =============================================================================

# Look up email channel on self-hosted main project
data "healthchecksio_channel" "selfhosted_email" {
  provider = healthchecksio.selfhosted
  kind     = "email"
}

# Got Your Back - full weekly Gmail backup
resource "healthchecksio_check" "gyb_full" {
  provider = healthchecksio.selfhosted

  name     = "got-your-back-full"
  desc     = "Weekly full Gmail backup via Got Your Back"
  tags     = ["backup", "kubernetes", "gyb"]
  timeout  = 604800 # 7 days
  grace    = 86400  # 1 day
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# Got Your Back - incremental backup every 4 hours
resource "healthchecksio_check" "gyb_incremental" {
  provider = healthchecksio.selfhosted

  name     = "got-your-back-incremental"
  desc     = "Incremental Gmail backup via Got Your Back"
  tags     = ["backup", "kubernetes", "gyb"]
  timeout  = 28800 # 8 hours (allows one missed run)
  grace    = 14400 # 4 hours
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# rsnapshot daily backup
resource "healthchecksio_check" "rsnapshot_daily" {
  provider = healthchecksio.selfhosted

  name     = "rsnapshot-daily"
  desc     = "Daily rsnapshot backup"
  tags     = ["backup", "kubernetes", "rsnapshot"]
  timeout  = 86400 # 1 day
  grace    = 86400 # 1 day
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# rsnapshot weekly backup
resource "healthchecksio_check" "rsnapshot_weekly" {
  provider = healthchecksio.selfhosted

  name     = "rsnapshot-weekly"
  desc     = "Weekly rsnapshot backup"
  tags     = ["backup", "kubernetes", "rsnapshot"]
  timeout  = 604800 # 7 days
  grace    = 86400  # 1 day
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# rsnapshot monthly backup
resource "healthchecksio_check" "rsnapshot_monthly" {
  provider = healthchecksio.selfhosted

  name     = "rsnapshot-monthly"
  desc     = "Monthly rsnapshot backup"
  tags     = ["backup", "kubernetes", "rsnapshot"]
  timeout  = 2678400 # 31 days
  grace    = 86400   # 1 day
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# Velero daily backup validation
resource "healthchecksio_check" "velero_daily" {
  provider = healthchecksio.selfhosted

  name     = "velero-daily-backup"
  desc     = "Daily Velero backup validation"
  tags     = ["backup", "kubernetes", "velero"]
  timeout  = 86400 # 1 day
  grace    = 86400 # 1 day
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# =============================================================================
# kube-restic checks (B2 and main-copy)
# =============================================================================

# kube-restic B2 backup - expects ping every 24 hours
resource "healthchecksio_check" "kube_restic_b2_backup" {
  provider = healthchecksio.selfhosted

  name     = "kube-restic-b2-backup"
  desc     = "Daily B2 restic backup from Kubernetes"
  tags     = ["backup", "kubernetes", "restic"]
  timeout  = 86400 # 1 day
  grace    = 86400 # 1 day
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# kube-restic B2 forget - expects ping every 24 hours
resource "healthchecksio_check" "kube_restic_b2_forget" {
  provider = healthchecksio.selfhosted

  name     = "kube-restic-b2-forget"
  desc     = "Daily B2 restic forget/prune from Kubernetes"
  tags     = ["backup", "kubernetes", "restic"]
  timeout  = 86400 # 1 day
  grace    = 86400 # 1 day
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# kube-restic main-copy - copies main backup to B2
resource "healthchecksio_check" "kube_restic_main_copy" {
  provider = healthchecksio.selfhosted

  name     = "kube-restic-main-copy-copy"
  desc     = "Daily copy of main restic backup to B2"
  tags     = ["backup", "kubernetes", "restic"]
  timeout  = 86400  # 1 day
  grace    = 108000 # 30 hours - allow one failure + next day to complete
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# kube-restic xtal-copy - copies xtal backup to B2
resource "healthchecksio_check" "kube_restic_xtal_copy" {
  provider = healthchecksio.selfhosted

  name     = "kube-restic-xtal-copy-copy"
  desc     = "Daily copy of xtal restic backup to B2"
  tags     = ["backup", "kubernetes", "restic"]
  timeout  = 86400  # 1 day
  grace    = 108000 # 30 hours - allow one failure + next day to complete
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# kube-restic B2 check - weekly integrity check
resource "healthchecksio_check" "kube_restic_b2_check" {
  provider = healthchecksio.selfhosted

  name     = "kube-restic-b2-check"
  desc     = "Weekly B2 restic integrity check from Kubernetes"
  tags     = ["backup", "kubernetes", "restic"]
  timeout  = 604800 # 7 days
  grace    = 86400  # 1 day
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# kube-restic xtal-b2-forget - daily forget/prune on xtal B2 repo
resource "healthchecksio_check" "kube_restic_xtal_b2_forget" {
  provider = healthchecksio.selfhosted

  name     = "kube-restic-xtal-b2-forget"
  desc     = "Daily forget/prune on xtal B2 repo"
  tags     = ["backup", "kubernetes", "restic"]
  timeout  = 86400  # 1 day
  grace    = 108000 # 30 hours - allow one failure + next day to complete
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# kube-restic xtal-b2-check - weekly integrity check on xtal B2 repo
resource "healthchecksio_check" "kube_restic_xtal_b2_check" {
  provider = healthchecksio.selfhosted

  name     = "kube-restic-xtal-b2-check"
  desc     = "Weekly integrity check on xtal B2 repo"
  tags     = ["backup", "kubernetes", "restic"]
  timeout  = 604800 # 7 days
  grace    = 86400  # 1 day
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}

# Ansible idempotency test - daily verification that playbooks are idempotent
resource "healthchecksio_check" "ansible_idempotency_test" {
  provider = healthchecksio.selfhosted

  name     = "ansible-idempotency-test"
  desc     = "Daily Ansible idempotency smoke test via Semaphore and ARA"
  tags     = ["ansible", "kubernetes", "semaphore"]
  timeout  = 86400 # 1 day
  grace    = 14400 # 4 hours - allow for slow runs or one retry
  channels = [data.healthchecksio_channel.selfhosted_email.id]
}
