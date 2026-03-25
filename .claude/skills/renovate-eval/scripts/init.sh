#!/usr/bin/env bash
# Initialize renovate-eval skill session
# Detects environment capabilities and lists open Renovate PRs
# Outputs a single JSON object for the skill to consume

set -euo pipefail

_INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$_INIT_DIR/../lib/common.sh"

check_prerequisites() {
    require_tools gh jq
    require_gh_auth
}

detect_environment() {
    REPO_ROOT=$(git rev-parse --show-toplevel)
    PLANNOTATOR=$(command -v plannotator >/dev/null 2>&1 && echo true || echo false)
    REPO_CONFIG="${REPO_ROOT}/.claude/renovate-eval.md"
    HAS_REPO_CONFIG=$([ -f "$REPO_CONFIG" ] && echo true || echo false)
    AUTOMERGE_AVAILABLE=$(gh api 'repos/{owner}/{repo}' --jq '.allow_auto_merge // false')
}

fetch_renovate_prs() {
    PRS_JSON=$(gh pr list \
        --author "app/renovate" \
        --state open \
        --json number,title,createdAt,autoMergeRequest,statusCheckRollup,labels \
        --limit 100 \
        ) || {
        echo "ERROR: Failed to fetch PRs" >&2
        return 1
    }

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
}

output_result() {
    jq -n \
        --arg repo_root "$REPO_ROOT" \
        --argjson plannotator_available "$PLANNOTATOR" \
        --argjson has_repo_config "$HAS_REPO_CONFIG" \
        --arg repo_config "$REPO_CONFIG" \
        --argjson automerge_available "$AUTOMERGE_AVAILABLE" \
        --argjson prs "$PRS" \
        '{
            repo_root: $repo_root,
            plannotator_available: $plannotator_available,
            automerge_available: $automerge_available,
            repo_config: (if $has_repo_config then $repo_config else null end),
            prs: $prs
        }'
}

main() {
    check_prerequisites
    detect_environment
    fetch_renovate_prs
    output_result
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
