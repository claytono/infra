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
      version = "~> 0.12"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.24"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2025.10.0"
    }
    openai = {
      source  = "registry.terraform.io/mkdev-me/openai"
      version = "~> 1.1"
    }
    unifi = {
      source  = "filipowm/unifi"
      version = "~> 1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    dns = {
      source  = "hashicorp/dns"
      version = "~> 3.4"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.89"
    }
    healthchecksio = {
      source  = "kristofferahl/healthchecksio"
      version = "~> 2.0"
    }
    semaphoreui = {
      source  = "CruGlobal/semaphoreui"
      version = "~> 1.4"
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

provider "openai" {
  api_key = local.openai_api_key
}

provider "unifi" {
  api_key = local.unifi_api_key
  api_url = local.unifi_api_url
}

provider "proxmox" {
  endpoint  = "https://pve.oneill.net"
  api_token = local.proxmox_api_token
  insecure  = false

  ssh {
    agent    = true
    username = "root"
  }
}

module "dns" {
  source               = "./modules/dns"
  infrastructure_hosts = local.infrastructure_hosts
}

# Authentik provider configuration via 1Password (see locals in secrets.tf)
provider "authentik" {
  url   = local.authentik_url
  token = local.authentik_token
}

module "authentik" {
  source                 = "./modules/authentik"
  onepassword_vault_uuid = data.onepassword_vault.infra.uuid
}

# Healthchecks providers - cloud (hosted) and self-hosted instances
provider "healthchecksio" {
  alias   = "cloud"
  api_key = local.healthchecks_cloud_api_key
}

provider "healthchecksio" {
  alias   = "selfhosted"
  api_key = local.healthchecks_selfhosted_api_key
  api_url = "https://hc.k.oneill.net/api/v1"
}

provider "healthchecksio" {
  alias   = "canary"
  api_key = local.healthchecks_canary_api_key
  api_url = "https://hc.k.oneill.net/api/v1"
}

# Semaphore provider configuration
provider "semaphoreui" {
  hostname  = "semaphore.k.oneill.net"
  protocol  = "https"
  port      = 443
  api_token = local.semaphore_api_token
}

module "semaphore" {
  source                  = "./modules/semaphore"
  ansible_ssh_private_key = local.semaphore_ansible_ssh_key
}
