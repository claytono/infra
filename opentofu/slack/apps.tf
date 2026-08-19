locals {
  hermes_slack_command_url = "https://hermes-agent.local/slack/commands"
  hermes_slack_commands = [
    {
      command     = "/hermes"
      description = "Talk to Hermes or run a subcommand"
      usage_hint  = "[subcommand] [args]"
    },
    {
      command     = "/btw"
      description = "Alias for /background — Run a prompt in the background"
      usage_hint  = "<prompt>"
    },
    {
      command     = "/bg"
      description = "Alias for /background — Run a prompt in the background"
      usage_hint  = "<prompt>"
    },
    {
      command     = "/start"
      description = "Acknowledge platform start pings without a reply"
    },
    {
      command     = "/new"
      description = "Start a new session (fresh session ID + history)"
      usage_hint  = "[name]"
    },
    {
      command     = "/retry"
      description = "Retry the last message (resend to agent)"
    },
    {
      command     = "/undo"
      description = "Back up N user turns and re-prompt (default 1)"
      usage_hint  = "[N]"
    },
    {
      command     = "/title"
      description = "Set a title for the current session"
      usage_hint  = "[name]"
    },
    {
      command     = "/branch"
      description = "Branch the current session (explore a different path)"
      usage_hint  = "[name]"
    },
    {
      command     = "/compress"
      description = "Compress conversation context (add 'here [N]' to keep recent N turns; --preview shows what would happen)"
      usage_hint  = "[here [N] | focus topic | --preview|--dry-run]"
    },
    {
      command     = "/rollback"
      description = "List or restore filesystem checkpoints"
      usage_hint  = "[number]"
    },
    {
      command     = "/stop"
      description = "Kill all running background processes"
    },
    {
      command     = "/approve"
      description = "Approve a pending dangerous command"
      usage_hint  = "[session|always]"
    },
    {
      command     = "/deny"
      description = "Deny a pending dangerous command (optionally with a reason)"
      usage_hint  = "[all] [reason]"
    },
    {
      command     = "/background"
      description = "Run a prompt in the background"
      usage_hint  = "<prompt>"
    },
    {
      command     = "/agents"
      description = "Show active agents and running tasks"
    },
    {
      command     = "/queue"
      description = "Queue a prompt for the next turn (doesn't interrupt)"
      usage_hint  = "<prompt>"
    },
    {
      command     = "/steer"
      description = "Inject a message after the next tool call without interrupting"
      usage_hint  = "<prompt>"
    },
    {
      command     = "/goal"
      description = "Set a standing goal Hermes works on across turns until achieved"
      usage_hint  = "[text | draft <text> | show | gate add <cmd> | pause | resume | clear | status | wait <pid> | unwait"
    },
    {
      command     = "/subgoal"
      description = "Add or manage extra criteria on the active goal"
      usage_hint  = "[text | remove N | clear]"
    },
    {
      command     = "/context"
      description = "Show detailed context window view with usage gauge, category breakdown, compression stats, and throughput"
      usage_hint  = "[all]"
    },
    {
      command     = "/whoami"
      description = "Show your slash command access (admin / user)"
    },
    {
      command     = "/profile"
      description = "Show active profile name and home directory"
    },
    {
      command     = "/sethome"
      description = "Set this chat as the home channel"
    },
    {
      command     = "/resume"
      description = "Resume a previously-named session"
      usage_hint  = "[name]"
    },
    {
      command     = "/sessions"
      description = "Browse and resume previous sessions"
    },
    {
      command     = "/model"
      description = "Switch model (session-scoped; --global to persist)"
      usage_hint  = "[model] [--provider name] [--global|--session] [--refresh]"
    },
    {
      command     = "/codex-runtime"
      description = "Toggle codex app-server runtime for OpenAI/Codex models"
      usage_hint  = "[auto|codex_app_server]"
    },
    {
      command     = "/personality"
      description = "Set a predefined personality"
      usage_hint  = "[name]"
    },
    {
      command     = "/footer"
      description = "Toggle gateway runtime-metadata footer on final replies"
      usage_hint  = "[on|off|status]"
    },
    {
      command     = "/yolo"
      description = "Toggle YOLO mode (skip all dangerous command approvals)"
    },
    {
      command     = "/approvals"
      description = "Show or set the persistent dangerous-command approval mode"
      usage_hint  = "[manual|smart|off]"
    },
    {
      command     = "/reasoning"
      description = "Manage reasoning effort and display"
      usage_hint  = "[level|show|hide|full|clamp] [--global]"
    },
    {
      command     = "/fast"
      description = "Toggle fast mode — OpenAI Priority Processing / Anthropic Fast Mode (Normal/Fast)"
      usage_hint  = "[normal|fast|status] [--global]"
    },
    {
      command     = "/voice"
      description = "Toggle voice mode"
      usage_hint  = "[on|off|tts|status]"
    },
    {
      command     = "/memory"
      description = "Review pending memory writes / toggle the approval gate"
      usage_hint  = "[pending|approve|reject|approval] [id|on|off]"
    },
    {
      command     = "/bundles"
      description = "List skill bundles (aliases /<name> for multiple skills)"
    },
    {
      command     = "/learn"
      description = "Learn a reusable skill from anything you describe (dirs, URLs, this chat, notes)"
      usage_hint  = "<what to learn from>"
    },
    {
      command     = "/suggestions"
      description = "Review suggested automations (accept/dismiss)"
      usage_hint  = "[accept|dismiss N | catalog]"
    },
    {
      command     = "/blueprint"
      description = "Set up an automation from a blueprint template"
      usage_hint  = "[name] [slot=value ...]"
    },
    {
      command     = "/curator"
      description = "Background skill maintenance (status, run, pin, archive, list-archived)"
      usage_hint  = "[subcommand]"
    },
    {
      command     = "/kanban"
      description = "Multi-profile collaboration board (tasks, links, comments)"
      usage_hint  = "[subcommand]"
    },
    {
      command     = "/reload-mcp"
      description = "Reload MCP servers from config"
    },
    {
      command     = "/reload-skills"
      description = "Re-scan ~/.hermes/skills/ for newly installed or removed skills"
    },
    {
      command     = "/commands"
      description = "Browse all commands and skills (paginated)"
      usage_hint  = "[page]"
    },
    {
      command     = "/help"
      description = "Show available commands"
    },
    {
      command     = "/restart"
      description = "Gracefully restart the gateway after draining active runs"
    },
    {
      command     = "/usage"
      description = "Show token usage and rate limits; `reset` redeems a banked Codex limit reset"
      usage_hint  = "[reset [--force]]"
    },
    {
      command     = "/insights"
      description = "Show usage insights and analytics"
      usage_hint  = "[days]"
    },
    {
      command     = "/platform"
      description = "Pause, resume, or list a failing gateway platform"
      usage_hint  = "<pause|resume|list> [name]"
    },
  ]
}

resource "slack-app_manifest" "felix" {
  manifest = jsonencode({
    display_information = {
      name             = "Felix"
      description      = "Your Felix agent on Slack"
      background_color = "#1a1a2e"
    }
    features = {
      assistant_view = {
        assistant_description = "Chat with Hermes in threads and DMs."
      }
      app_home = {
        home_tab_enabled               = false
        messages_tab_enabled           = true
        messages_tab_read_only_enabled = false
      }
      bot_user = {
        display_name  = "Felix"
        always_online = true
      }
      slash_commands = [
        for command in local.hermes_slack_commands : merge(command, {
          url           = local.hermes_slack_command_url
          should_escape = false
        })
      ]
    }
    oauth_config = {
      pkce_enabled = false
      scopes = {
        bot = [
          "app_mentions:read",
          "assistant:write",
          "channels:history",
          "channels:read",
          "chat:write",
          "commands",
          "files:read",
          "files:write",
          "groups:history",
          "groups:read",
          "im:history",
          "im:read",
          "im:write",
          "mpim:history",
          "mpim:read",
          "reactions:read",
          "users:read",
        ]
      }
    }
    settings = {
      event_subscriptions = {
        bot_events = [
          "app_mention",
          "assistant_thread_context_changed",
          "assistant_thread_started",
          "message.channels",
          "message.groups",
          "message.im",
          "message.mpim",
          "reaction_added",
          "reaction_removed",
        ]
      }
      interactivity = {
        is_enabled = true
      }
      is_mcp_enabled         = false
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
      pkce_enabled = false
      scopes = {
        bot = [
          "chat:write",
          "dnd:read",
          "incoming-webhook",
        ]
      }
    }
    settings = {
      is_mcp_enabled         = false
      org_deploy_enabled     = false
      socket_mode_enabled    = false
      token_rotation_enabled = false
    }
  })
}
