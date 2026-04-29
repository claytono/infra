# GitHub repository secrets management

locals {
  tailscale_ssh_github_repositories = toset([
    "github-actions",
    "dotfiles",
  ])
}

# Infra repository secrets
resource "github_actions_secret" "infra_argocd_auth_token" {
  repository      = "infra"
  secret_name     = "ARGOCD_AUTH_TOKEN"
  plaintext_value = data.onepassword_item.argocd_github_actions_token.password
}

resource "github_actions_secret" "infra_cachix_auth_token" {
  repository      = "infra"
  secret_name     = "CACHIX_AUTH_TOKEN"
  plaintext_value = data.onepassword_item.cachix_auth_token.password
}

resource "github_actions_secret" "infra_tailscale_oauth_client_id" {
  repository      = "infra"
  secret_name     = "TAILSCALE_OAUTH_CLIENT_ID"
  plaintext_value = tailscale_oauth_client.github_actions.id
}

resource "github_actions_secret" "infra_tailscale_oauth_client_secret" {
  repository      = "infra"
  secret_name     = "TAILSCALE_OAUTH_CLIENT_SECRET"
  plaintext_value = tailscale_oauth_client.github_actions.key
}

resource "github_actions_secret" "tailscale_ssh_oauth_client_id" {
  for_each = local.tailscale_ssh_github_repositories

  repository      = each.key
  secret_name     = "TAILSCALE_SSH_OAUTH_CLIENT_ID"
  plaintext_value = tailscale_oauth_client.github_actions_ssh.id
}

resource "github_actions_secret" "tailscale_ssh_oauth_client_secret" {
  for_each = local.tailscale_ssh_github_repositories

  repository      = each.key
  secret_name     = "TAILSCALE_SSH_OAUTH_CLIENT_SECRET"
  plaintext_value = tailscale_oauth_client.github_actions_ssh.key
}

resource "github_actions_secret" "infra_semaphore_api_token" {
  repository      = "infra"
  secret_name     = "SEMAPHORE_API_TOKEN"
  plaintext_value = local.semaphore_api_token
}

resource "github_actions_secret" "infra_claude_code_oauth_token" {
  repository      = "infra"
  secret_name     = "CLAUDE_CODE_OAUTH_TOKEN"
  plaintext_value = data.onepassword_item.claude_code_oauth_token.credential
}

resource "github_actions_variable" "infra_semaphore_project" {
  repository    = "infra"
  variable_name = "SEMAPHORE_PROJECT"
  value         = module.semaphore.project_name
}

resource "github_actions_variable" "infra_semaphore_template" {
  repository    = "infra"
  variable_name = "SEMAPHORE_TEMPLATE"
  value         = module.semaphore.template_name
}

# Website-Hugo repository secrets (Cloudflare Pages deployment)
resource "github_actions_secret" "website_hugo_cf_api_token" {
  repository      = "website-hugo"
  secret_name     = "CLOUDFLARE_API_TOKEN"
  plaintext_value = cloudflare_account_token.pages_deploy.value
}

resource "github_actions_secret" "website_hugo_cf_account_id" {
  repository      = "website-hugo"
  secret_name     = "CLOUDFLARE_ACCOUNT_ID"
  plaintext_value = local.cloudflare_account_id
}
