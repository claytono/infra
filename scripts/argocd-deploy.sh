#!/bin/bash
set -euo pipefail

# argocd-deploy.sh - Deploy ArgoCD applications with proper error handling
#
# This script deploys ArgoCD applications to a specified target revision and tracks
# success/failure status for each application individually.
#
# HOW IT WORKS:
# 1. For each application: patch source to target revision, sync, and wait for healthy state
# 2. Tracks which applications succeed vs fail during deployment
# 3. Optionally comments deployment results on GitHub PRs
# 4. Sets GitHub Actions outputs and exits with error code if any deployments fail
#
# GITHUB ACTIONS INTEGRATION:
# The script sets these outputs in $GITHUB_OUTPUT:
# - success_apps: Space-separated list of successfully deployed applications
# - failed_apps: Space-separated list of failed applications
# - success_count: Number of successful deployments
# - failed_count: Number of failed deployments
#
# EXAMPLES:
# ./argocd-deploy.sh --apps "app1 app2" --target-revision "main"
# ./argocd-deploy.sh --apps "webapp" --target-revision "feature-branch" --comment-pr 123
#
# Usage: ./argocd-deploy.sh --apps "app1 app2" --target-revision "branch-name" [--comment-pr PR_NUMBER]

# Default values
APPS=""
TARGET_REVISION=""
PR_NUMBER=""
SYNC_TIMEOUT="300"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --apps)
      APPS="$2"
      shift 2
      ;;
    --target-revision)
      TARGET_REVISION="$2"
      shift 2
      ;;
    --comment-pr)
      PR_NUMBER="$2"
      shift 2
      ;;
    --sync-timeout)
      SYNC_TIMEOUT="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 --apps 'app1 app2' --target-revision 'branch' [--comment-pr PR_NUMBER]"
      echo "Deploy ArgoCD applications to specified target revision"
      echo ""
      echo "Options:"
      echo "  --apps APPS              Space-separated list of application names"
      echo "  --target-revision REV    Target revision (branch/tag/commit)"
      echo "  --comment-pr PR_NUMBER   Comment results on PR"
      echo "  --sync-timeout SECONDS   Sync timeout in seconds (default: 300)"
      echo "  --help                   Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate required arguments
if [[ -z "$APPS" ]]; then
  echo "Error: --apps is required"
  exit 1
fi

if [[ -z "$TARGET_REVISION" ]]; then
  echo "Error: --target-revision is required"
  exit 1
fi

# Arrays to track results
SUCCESS_APPS=()
FAILED_APPS=()

# Function to comment on PR
comment_pr() {
  local message="$1"
  if [[ -n "$PR_NUMBER" && -n "${GH_TOKEN:-}" ]]; then
    gh pr comment "$PR_NUMBER" --body "$message"
  else
    echo "PR Comment: $message"
  fi
}

# Function to deploy a single app
deploy_app() {
  local app="$1"
  echo "Deploying $app to $TARGET_REVISION..."

  # Patch source
  if ! argocd app patch-source "$app" --target-revision "$TARGET_REVISION" 2>&1; then
    echo "❌ Failed to patch source for $app"
    return 1
  fi

  # Sync with timeout
  if ! timeout "$SYNC_TIMEOUT" argocd app sync "$app" --timeout "$SYNC_TIMEOUT" 2>&1; then
    echo "❌ Failed to sync $app (timeout: ${SYNC_TIMEOUT}s)"
    return 1
  fi

  # Wait for sync to complete
  if ! argocd app wait "$app" --timeout "$SYNC_TIMEOUT" 2>&1; then
    echo "❌ $app failed to reach healthy state"
    return 1
  fi

  echo "✅ Successfully deployed $app"
  return 0
}

# Main deployment loop
echo "Starting deployment of apps: $APPS"
echo "Target revision: $TARGET_REVISION"

for app in $APPS; do
  if deploy_app "$app"; then
    SUCCESS_APPS+=("$app")
  else
    FAILED_APPS+=("$app")
  fi
done

# Generate results
TOTAL_APPS=$(echo "$APPS" | wc -w)
SUCCESS_COUNT=${#SUCCESS_APPS[@]}
FAILED_COUNT=${#FAILED_APPS[@]}

echo ""
echo "Deployment Summary:"
echo "  Total: $TOTAL_APPS"
echo "  Success: $SUCCESS_COUNT"
echo "  Failed: $FAILED_COUNT"

# Output for GitHub Actions
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "success_apps=${SUCCESS_APPS[*]}"
    echo "failed_apps=${FAILED_APPS[*]}"
    echo "success_count=$SUCCESS_COUNT"
    echo "failed_count=$FAILED_COUNT"
  } >> "$GITHUB_OUTPUT"
fi

# Comment on PR if requested
if [[ -n "$PR_NUMBER" ]]; then
  if [[ $FAILED_COUNT -eq 0 ]]; then
    comment_pr "🚀 Successfully deployed **${SUCCESS_APPS[*]}** to \`$TARGET_REVISION\`"
  else
    COMMENT="⚠️ Deployment to \`$TARGET_REVISION\` completed with failures:"
    if [[ $SUCCESS_COUNT -gt 0 ]]; then
      COMMENT="$COMMENT"$'\n\n'"✅ **Succeeded:** ${SUCCESS_APPS[*]}"
    fi
    if [[ $FAILED_COUNT -gt 0 ]]; then
      COMMENT="$COMMENT"$'\n'"❌ **Failed:** ${FAILED_APPS[*]}"
    fi
    comment_pr "$COMMENT"
  fi
fi

# Exit with appropriate code
if [[ $FAILED_COUNT -gt 0 ]]; then
  exit 1
fi

exit 0
