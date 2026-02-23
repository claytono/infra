terraform {
  required_version = ">= 1.0"

  required_providers {
    slack-app = {
      source  = "change-engine/slack-app"
      version = "~> 0.1"
    }
  }

  backend "s3" {
    bucket  = "coneill-opentofu-state"
    key     = "homelab/slack.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

# Token provided via SLACK_APP_TOKEN env var (set by direnv)
provider "slack-app" {}
