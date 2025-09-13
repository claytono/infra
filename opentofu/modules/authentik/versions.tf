terraform {
  required_version = ">= 1.0"
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = ">= 2025.8.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
