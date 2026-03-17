#!/usr/bin/env bash
# List open Renovate PRs that need attention
# Outputs JSON array for programmatic consumption
# Shows PRs without automerge OR with failing CI

set -euo pipefail

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

# Fetch all open Renovate PRs with CI status and labels
PRS_JSON=$(gh pr list \
    --author "app/renovate" \
    --state open \
    --json number,title,createdAt,autoMergeRequest,statusCheckRollup,labels \
    --limit 100 \
    2>&1) || {
    echo "ERROR: Failed to fetch PRs: $PRS_JSON" >&2
    exit 1
}

# Filter and transform to clean JSON output
echo "$PRS_JSON" | jq '
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
'
