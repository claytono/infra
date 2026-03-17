#!/usr/bin/env bash
# Fetch all PR data for Renovate PR evaluation
# Usage: fetch-pr-data.sh [--pr NUMBER]

set -euo pipefail

# Parse arguments
PR_NUMBER=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --pr)
            PR_NUMBER="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--pr NUMBER]"
            echo ""
            echo "Fetch all PR data for Renovate evaluation."
            echo ""
            echo "Options:"
            echo "  --pr NUMBER    PR number (default: auto-detect from current branch)"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--pr NUMBER]" >&2
            exit 1
            ;;
    esac
done

# Check if gh CLI is installed
if ! command -v gh &>/dev/null; then
    echo "ERROR: GitHub CLI (gh) is not installed" >&2
    exit 1
fi

# Check if authenticated with GitHub
if ! gh auth status &>/dev/null; then
    echo "ERROR: Not authenticated with GitHub. Run 'gh auth login'" >&2
    exit 1
fi

# Auto-detect PR if not provided
if [[ -z "$PR_NUMBER" ]]; then
    PR_NUMBER=$(gh pr view --json number -q .number 2>/dev/null || true)
    if [[ -z "$PR_NUMBER" ]]; then
        echo "ERROR: Could not detect PR number. Use --pr NUMBER or run from a PR branch" >&2
        exit 1
    fi
fi

# Get repository info
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
if [[ -z "$REPO" ]]; then
    echo "ERROR: Not in a git repository with GitHub remote" >&2
    exit 1
fi

echo "# Renovate PR Data for #$PR_NUMBER"
echo ""

# Fetch PR metadata
echo "## Metadata"
if ! PR_DATA=$(gh pr view "$PR_NUMBER" --json number,title,author,state,url,baseRefName,headRefName,additions,deletions,changedFiles 2>&1); then
    echo "ERROR: Failed to fetch PR metadata"
    echo "${PR_DATA//$'\n'/$'\n'  }"
else
    echo "- Number: $(echo "$PR_DATA" | jq -r '.number')"
    echo "- Title: $(echo "$PR_DATA" | jq -r '.title')"
    echo "- Author: $(echo "$PR_DATA" | jq -r '.author.login')"
    echo "- State: $(echo "$PR_DATA" | jq -r '.state')"
    echo "- URL: $(echo "$PR_DATA" | jq -r '.url')"
    echo "- Branch: $(echo "$PR_DATA" | jq -r '.headRefName') ← $(echo "$PR_DATA" | jq -r '.baseRefName')"
    echo "- Changes: +$(echo "$PR_DATA" | jq -r '.additions') -$(echo "$PR_DATA" | jq -r '.deletions') across $(echo "$PR_DATA" | jq -r '.changedFiles') files"
fi
echo ""

# Fetch PR body
echo "## PR Body"
if ! PR_BODY=$(gh pr view "$PR_NUMBER" --json body -q .body 2>&1); then
    echo "ERROR: Failed to fetch PR body"
    echo "${PR_BODY//$'\n'/$'\n'  }"
else
    # Remove HTML comments (renovate debug info)
    echo "$PR_BODY" | sed 's/<!--[^>]*-->//g' | grep -v '^$'
fi
echo ""

# Fetch files changed
echo "## Files Changed"
if ! FILES_DATA=$(gh pr view "$PR_NUMBER" --json files 2>&1); then
    echo "ERROR: Failed to fetch files data"
    echo "${FILES_DATA//$'\n'/$'\n'  }"
else
    FILE_COUNT=$(echo "$FILES_DATA" | jq '.files | length')
    echo "Total: $FILE_COUNT files"
    echo ""
    echo "$FILES_DATA" | jq -r '.files[] | "- \(.path) (+\(.additions)/-\(.deletions))"'
fi
echo ""

# Fetch diff
echo "## Diff"
echo '```diff'
gh pr diff "$PR_NUMBER" 2>&1
echo '```'
echo ""


# Fetch linked and referencing issues via timeline API
echo "## Related Issues"

# Get issues that this PR closes (from PR metadata)
LINKED_ISSUES=$(gh pr view "$PR_NUMBER" --json closingIssuesReferences -q '.closingIssuesReferences[].number' 2>/dev/null || true)

if [[ -n "$LINKED_ISSUES" ]]; then
    echo "### Issues Closed by This PR"
    for ISSUE_NUM in $LINKED_ISSUES; do
        ISSUE_DATA=$(gh issue view "$ISSUE_NUM" --json number,title,body,state 2>/dev/null || true)
        if [[ -n "$ISSUE_DATA" ]]; then
            echo ""
            echo "**Issue #$ISSUE_NUM:** $(echo "$ISSUE_DATA" | jq -r '.title')"
            echo "- State: $(echo "$ISSUE_DATA" | jq -r '.state')"
            echo "- Body:"
            echo "$ISSUE_DATA" | jq -r '.body // "No body"' | sed 's/^/  /'
        fi
    done
    echo ""
fi

# Get cross-references from timeline (issues/PRs that mention this PR)
CROSS_REFS=$(gh api "repos/$REPO/issues/$PR_NUMBER/timeline" --paginate -q '
    [.[] | select(.event == "cross-referenced") | .source.issue |
     {number, title, state, type: (if .pull_request then "PR" else "Issue" end)}]
    | unique_by(.number)' 2>/dev/null || echo "[]")

CROSS_REF_COUNT=$(echo "$CROSS_REFS" | jq 'length' 2>/dev/null || echo "0")

if [[ "$CROSS_REF_COUNT" -gt 0 ]]; then
    echo "### Cross-References (issues/PRs mentioning this PR)"
    echo "$CROSS_REFS" | jq -r '.[] | "- \(.type) #\(.number): \(.title) [\(.state)]"'
    echo ""

    # Fetch full body for each cross-referencing issue (not PRs, those are usually noise)
    for ISSUE_NUM in $(echo "$CROSS_REFS" | jq -r '.[] | select(.type == "Issue") | .number'); do
        ISSUE_BODY=$(gh issue view "$ISSUE_NUM" --json body -q '.body // "No body"' 2>/dev/null || true)
        if [[ -n "$ISSUE_BODY" ]] && [[ "$ISSUE_BODY" != "No body" ]]; then
            echo "**Issue #$ISSUE_NUM body:**"
            echo "${ISSUE_BODY//$'\n'/$'\n'  }"
            echo ""
        fi
    done
fi

if [[ -z "$LINKED_ISSUES" ]] && [[ "$CROSS_REF_COUNT" -eq 0 ]]; then
    echo "No linked or referencing issues found."
    echo ""
fi

echo "---"
echo "Data collection complete for PR #$PR_NUMBER"
