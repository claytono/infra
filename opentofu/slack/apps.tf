resource "slack-app_manifest" "frank" {
  manifest = jsonencode({
    display_information = {
      name             = "Frank"
      description      = "Frank"
      background_color = "#5f83b0"
    }
    features = {
      assistant_view = {
        assistant_description = "Frank"
      }
      app_home = {
        home_tab_enabled               = false
        messages_tab_enabled           = true
        messages_tab_read_only_enabled = false
      }
      bot_user = {
        display_name  = "Frank"
        always_online = false
      }
    }
    oauth_config = {
      scopes = {
        bot = [
          "app_mentions:read",
          "assistant:write",
          "channels:history",
          "channels:read",
          "chat:write",
          "files:read",
          "files:write",
          "groups:history",
          "groups:read",
          "im:history",
          "im:read",
          "im:write",
          "mpim:history",
          "mpim:read",
          "pins:read",
          "pins:write",
          "reactions:read",
          "reactions:write",
          "users:read",
        ]
      }
    }
    settings = {
      event_subscriptions = {
        bot_events = [
          "app_mention",
          "member_joined_channel",
          "member_left_channel",
          "message.channels",
          "message.groups",
          "message.im",
          "message.mpim",
          "pin_added",
          "pin_removed",
          "reaction_added",
          "reaction_removed",
        ]
      }
      interactivity = {
        is_enabled = true
      }
      org_deploy_enabled     = false
      socket_mode_enabled    = true
      token_rotation_enabled = false
    }
  })
}

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
          "dnd:read",
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
