#!/usr/bin/env bash
# Initialize renovate-eval skill session
# Detects environment capabilities and lists open Renovate PRs
# Outputs a single JSON object for the skill to consume

set -euo pipefail

# Check if gh CLI is installed
if ! command -v gh &>/dev/null; then
    echo "ERROR: GitHub CLI (gh) is not installed" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is not installed" >&2
    exit 1
fi

# Check if authenticated with GitHub
if ! gh auth status &>/dev/null; then
    echo "ERROR: Not authenticated with GitHub. Run 'gh auth login'" >&2
    exit 1
fi

# Detect environment
REPO_ROOT=$(git rev-parse --show-toplevel)
PLANNOTATOR=$(command -v plannotator >/dev/null 2>&1 && echo true || echo false)
REPO_CONFIG="${REPO_ROOT}/.claude/renovate-eval.md"
HAS_REPO_CONFIG=$([ -f "$REPO_CONFIG" ] && echo true || echo false)

# Fetch all open Renovate PRs with CI status and labels
PRS_JSON=$(gh pr list \
    --author "app/renovate" \
    --state open \
    --json number,title,createdAt,autoMergeRequest,statusCheckRollup,labels \
    --limit 100 \
    ) || {
    echo "ERROR: Failed to fetch PRs" >&2
    exit 1
}

# Filter and transform PRs
PRS=$(echo "$PRS_JSON" | jq '
    [.[] | select(
        .autoMergeRequest == null or
        ([.statusCheckRollup[]? | select(.status == "COMPLETED" and .conclusion == "FAILURE")] | length > 0)
    )] |
    sort_by(.createdAt) | reverse |
    [.[] | {
        number,
        title,
        automerge: (.autoMergeRequest != null),
        ci_failing: (([.statusCheckRollup[]? | select(.status == "COMPLETED" and .conclusion == "FAILURE")] | length) > 0),
        eval_label: (
            [.labels[].name] |
            map(select(startswith("renovate:") and . != "renovate:evaluated")) |
            if length > 0 then .[0] else null end
        ),
        evaluated: ([.labels[].name] | any(. == "renovate:evaluated"))
    }]
')

# Output combined JSON
jq -n \
    --arg repo_root "$REPO_ROOT" \
    --argjson plannotator_available "$PLANNOTATOR" \
    --argjson has_repo_config "$HAS_REPO_CONFIG" \
    --arg repo_config "$REPO_CONFIG" \
    --argjson prs "$PRS" \
    '{
        repo_root: $repo_root,
        plannotator_available: $plannotator_available,
        repo_config: (if $has_repo_config then $repo_config else null end),
        prs: $prs
    }'
