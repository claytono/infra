# GitHub repository secrets management

locals {
  cachix_github_repositories = toset([
    "dotfiles",
    "go-unifi-mcp",
  ])

  # Repositories that run the shared claytono-renovate-eval workflow. Its
  # provider comes from RENOVATE_EVAL_PROVIDER, and callers pass the Claude
  # OAuth token to it explicitly.
  renovate_eval_github_repositories = toset([
    "infra",
    "dotfiles",
    "go-unifi-mcp",
    "github-actions",
  ])

  tailscale_ssh_github_repositories = toset([
    "github-actions",
    "dotfiles",
  ])
}

# Infra repository secrets
resource "github_actions_secret" "infra_argocd_auth_token" {
  repository  = "infra"
  secret_name = "ARGOCD_AUTH_TOKEN"
  value       = data.onepassword_item.argocd_github_actions_token.password
}

resource "github_actions_secret" "infra_cachix_auth_token" {
  repository  = "infra"
  secret_name = "CACHIX_AUTH_TOKEN"
  value       = data.onepassword_item.cachix_auth_token.password
}

resource "github_actions_secret" "cachix_auth_token" {
  for_each = local.cachix_github_repositories

  repository  = each.key
  secret_name = "CACHIX_AUTH_TOKEN"
  value       = data.onepassword_item.cachix_auth_token.password
}

resource "github_actions_secret" "infra_tailscale_oauth_client_id" {
  repository  = "infra"
  secret_name = "TAILSCALE_OAUTH_CLIENT_ID"
  value       = tailscale_oauth_client.github_actions.id
}

resource "github_actions_secret" "infra_tailscale_oauth_client_secret" {
  repository  = "infra"
  secret_name = "TAILSCALE_OAUTH_CLIENT_SECRET"
  value       = tailscale_oauth_client.github_actions.key
}

resource "github_actions_secret" "tailscale_ssh_oauth_client_id" {
  for_each = local.tailscale_ssh_github_repositories

  repository  = each.key
  secret_name = "TAILSCALE_SSH_OAUTH_CLIENT_ID"
  value       = tailscale_oauth_client.github_actions_ssh.id
}

resource "github_actions_secret" "tailscale_ssh_oauth_client_secret" {
  for_each = local.tailscale_ssh_github_repositories

  repository  = each.key
  secret_name = "TAILSCALE_SSH_OAUTH_CLIENT_SECRET"
  value       = tailscale_oauth_client.github_actions_ssh.key
}

resource "github_actions_secret" "infra_semaphore_api_token" {
  repository  = "infra"
  secret_name = "SEMAPHORE_API_TOKEN"
  value       = local.semaphore_api_token
}

resource "github_actions_secret" "claude_code_oauth_token" {
  for_each = local.renovate_eval_github_repositories

  repository  = each.key
  secret_name = "CLAUDE_CODE_OAUTH_TOKEN"
  value       = data.onepassword_item.claude_code_oauth_token.credential
}

moved {
  from = github_actions_secret.infra_claude_code_oauth_token
  to   = github_actions_secret.claude_code_oauth_token["infra"]
}

resource "github_actions_variable" "renovate_eval_provider" {
  for_each = local.renovate_eval_github_repositories

  repository    = each.key
  variable_name = "RENOVATE_EVAL_PROVIDER"
  value         = "claude"
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
  repository  = "website-hugo"
  secret_name = "CLOUDFLARE_API_TOKEN"
  value       = cloudflare_account_token.pages_deploy.value
}

resource "github_actions_secret" "website_hugo_cf_account_id" {
  repository  = "website-hugo"
  secret_name = "CLOUDFLARE_ACCOUNT_ID"
  value       = local.cloudflare_account_id
}
