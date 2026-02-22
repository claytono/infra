resource "slack-app_manifest" "home" {
  manifest = jsonencode({
    display_information = {
      name        = "Home"
      description = "Home notifications"
    }
    features = {
      bot_user = {
        display_name  = "Home"
        always_online = false
      }
    }
    oauth_config = {
      scopes = {
        bot = [
          "chat:write",
          "incoming-webhook",
        ]
      }
    }
    settings = {
      org_deploy_enabled     = false
      socket_mode_enabled    = false
      token_rotation_enabled = false
    }
  })
}
