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

