# GitHub repository secrets management

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

resource "github_actions_secret" "infra_semaphore_api_token" {
  repository      = "infra"
  secret_name     = "SEMAPHORE_API_TOKEN"
  plaintext_value = local.semaphore_api_token
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
