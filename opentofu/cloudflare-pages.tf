# Look up the "Pages Write" permission group ID
data "cloudflare_account_api_token_permission_groups_list" "pages_write" {
  account_id = local.cloudflare_account_id
  name       = "Pages Write"
}

# Cloudflare Pages project for the Hugo blog (Direct Upload mode)
resource "cloudflare_pages_project" "website" {
  account_id        = local.cloudflare_account_id
  name              = "oneill-website"
  production_branch = "main"
}

# Custom domain for the Pages project
resource "cloudflare_pages_domain" "clayton" {
  account_id   = local.cloudflare_account_id
  project_name = cloudflare_pages_project.website.name
  name         = "clayton.oneill.net"
}

# Scoped Cloudflare API token for Pages deployment from GitHub Actions
resource "cloudflare_account_token" "pages_deploy" {
  account_id = local.cloudflare_account_id
  name       = "cloudflare-pages-deploy"

  policies = [{
    effect = "allow"
    permission_groups = [{
      id = data.cloudflare_account_api_token_permission_groups_list.pages_write.result[0].id
    }]
    resources = jsonencode({ "com.cloudflare.api.account.${local.cloudflare_account_id}" = "*" })
  }]
}
