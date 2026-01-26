# List all projects to find the default project
data "openai_projects" "all" {}

# Find the default project (usually named "Default project")
locals {
  default_project = try(
    [
      for project in data.openai_projects.all.projects :
      project if project.name == "Default project"
    ][0],
    null
  )
}

# Validate that we found the default project
resource "terraform_data" "validate_default_project" {
  lifecycle {
    precondition {
      condition     = local.default_project != null
      error_message = "Could not find 'Default project' in OpenAI projects. Available projects: ${join(", ", [for p in data.openai_projects.all.projects : p.name])}"
    }
  }
}

# Service account for GitHub Actions in the default project
# This automatically creates an API key that can be used by the renovate-chart-analysis workflow
resource "openai_project_service_account" "github_actions" {
  project_id = local.default_project.id
  name       = "github-actions-chart-analysis"
}

# Store the API key in 1Password
resource "onepassword_item" "openai_github_actions" {
  vault    = data.onepassword_vault.infra.uuid
  title    = "openai-github-actions"
  category = "password"

  password = openai_project_service_account.github_actions.api_key_value
}

# Store the API key in GitHub Actions secrets
resource "github_actions_secret" "openai_api_key" {
  repository      = "infra"
  secret_name     = "OPENAI_API_KEY"
  plaintext_value = openai_project_service_account.github_actions.api_key_value
}

# Service account for karakeep application
resource "openai_project_service_account" "karakeep" {
  project_id = local.default_project.id
  name       = "karakeep"
}

# Store the karakeep OpenAI API key in its own 1Password item
resource "onepassword_item" "karakeep_openai" {
  vault    = data.onepassword_vault.infra.uuid
  title    = "karakeep-openai-api-key"
  category = "password"

  password = openai_project_service_account.karakeep.api_key_value
}

# Service account for speakr application
resource "openai_project_service_account" "speakr" {
  project_id = local.default_project.id
  name       = "speakr"
}

# Store the speakr OpenAI API key in 1Password
resource "onepassword_item" "speakr_openai" {
  vault    = data.onepassword_vault.infra.uuid
  title    = "speakr-openai-api-key"
  category = "password"

  password = openai_project_service_account.speakr.api_key_value
}
