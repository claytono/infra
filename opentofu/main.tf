terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.15"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.1"
    }
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.10"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.21"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2025.8.0"
    }
  }

  backend "s3" {
    bucket  = "coneill-opentofu-state"
    key     = "homelab/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

# 1Password provider configuration
provider "onepassword" {
  account = "6GO3NBF2PRCY3NAW6SN2CG6I2U"
}

provider "aws" {
  region = "us-west-2"

  default_tags {
    tags = {
      ManagedBy = "opentofu"
    }
  }
}

provider "vultr" {
  api_key = local.vultr_api_key
}

provider "b2" {
  application_key_id = local.b2_application_key_id
  application_key    = local.b2_application_key
}

provider "tailscale" {
  oauth_client_id     = local.tailscale_client_id
  oauth_client_secret = local.tailscale_client_secret
}

provider "github" {
  token = local.github_token
}

module "dns" {
  source = "./modules/dns"
}

# Authentik provider configuration via 1Password (see locals in secrets.tf)
provider "authentik" {
  url   = local.authentik_url
  token = local.authentik_token
}

module "authentik" {
  source = "./modules/authentik"
}
