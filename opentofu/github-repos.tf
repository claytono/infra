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
