#!/bin/bash
set -euo pipefail

# detect-argocd-apps.sh - Detect ArgoCD applications affected by file changes
#
# This script analyzes changed files in the kubernetes/ directory and determines
# which ArgoCD applications are affected by those changes using git diff.
#
# HOW IT WORKS:
# 1. Gets list of changed files in kubernetes/ directory via git diff
# 2. Extracts application names from file paths using pattern kubernetes/APP_NAME/*
# 3. Validates that detected apps exist in the argo-apps directory
# 4. Outputs results for use in GitHub Actions workflows
#
# DIRECTORY STRUCTURE ASSUMPTION:
# kubernetes/
# ├── app1/
# │   ├── kustomization.yaml
# │   └── deployment.yaml
# ├── app2/
# │   └── helm/
# └── shared-resources/  # <- Would be detected as "shared-resources" app
#
# GITHUB ACTIONS INTEGRATION:
# The script sets these outputs in $GITHUB_OUTPUT:
# - apps: Space-separated list of application names
# - app_count: Number of applications detected
#
# EXAMPLES:
# ./detect-argocd-apps.sh --base-ref main       # Compare current branch to main
# ./detect-argocd-apps.sh --head-ref feature    # Compare feature branch to main
# ./detect-argocd-apps.sh --base-ref HEAD~1 --head-ref HEAD  # Compare last commit
#
# Usage: ./detect-argocd-apps.sh [--base-ref BASE_REF] [--head-ref HEAD_REF]

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$BASEDIR")"

# Default values
BASE_REF="main"
HEAD_REF="HEAD"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --base-ref)
      BASE_REF="$2"
      shift 2
      ;;
    --head-ref)
      HEAD_REF="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [--base-ref BASE_REF] [--head-ref HEAD_REF]"
      echo "Detects ArgoCD applications affected by file changes"
      echo ""
      echo "Options:"
      echo "  --base-ref REF     Base reference for comparison (default: main)"
      echo "  --head-ref REF     Head reference for comparison (default: HEAD)"
      echo "  --help             Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Function to get changed files from git diff
get_changed_files() {
  git diff --name-only "$BASE_REF"..."$HEAD_REF" | grep '^kubernetes/' || true
}

# Function to extract app names from file paths
extract_app_names() {
  local changed_files="$1"
  local apps=()

  while read -r file; do
    if [[ -n "$file" && "$file" =~ ^kubernetes/([^/]+)/ ]]; then
      local app_name="${BASH_REMATCH[1]}"
      # Add to array if not already present
      if [[ ! " ${apps[*]} " =~ \ ${app_name}\  ]]; then
        apps+=("$app_name")
      fi
    fi
  done <<< "$changed_files"

  # Output apps as space-separated string
  printf '%s\n' "${apps[@]}"
}

# Function to validate apps exist in argo-apps directory
validate_apps() {
  local apps=("$@")
  local valid_apps=()
  local argo_apps_dir="$REPO_ROOT/kubernetes/argo-apps"

  # Check if argo-apps directory exists
  if [[ ! -d "$argo_apps_dir" ]]; then
    echo "Warning: argo-apps directory not found at $argo_apps_dir" >&2
    # Return all apps if we can't validate
    printf '%s\n' "${apps[@]}"
    return
  fi

  for app in "${apps[@]}"; do
    # Look for corresponding yaml file in argo-apps directory
    if [[ -f "$argo_apps_dir/$app.yaml" ]]; then
      valid_apps+=("$app")
    else
      echo "Warning: Application '$app' not found in argo-apps directory" >&2
    fi
  done

  printf '%s\n' "${valid_apps[@]}"
}

# Main logic
main() {
  cd "$REPO_ROOT"

  # Get changed files
  local changed_files
  changed_files=$(get_changed_files)

  if [[ -z "$changed_files" ]]; then
    echo "No kubernetes files changed"
    return 0
  fi

  # Extract app names
  local app_names
  readarray -t app_names < <(extract_app_names "$changed_files")

  if [[ ${#app_names[@]} -eq 0 ]]; then
    echo "No ArgoCD applications detected in changed files"
    return 0
  fi

  # Validate apps exist in argo-apps directory
  local valid_apps
  readarray -t valid_apps < <(validate_apps "${app_names[@]}")

  # Output results
  if [[ ${#valid_apps[@]} -gt 0 ]]; then
    echo "Detected applications: ${valid_apps[*]}"
    # Output for GitHub Actions
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo "apps=${valid_apps[*]}" >> "$GITHUB_OUTPUT"
      echo "app_count=${#valid_apps[@]}" >> "$GITHUB_OUTPUT"
    fi
  else
    echo "No valid ArgoCD applications found"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo "apps=" >> "$GITHUB_OUTPUT"
      echo "app_count=0" >> "$GITHUB_OUTPUT"
    fi
  fi
}

main "$@"
