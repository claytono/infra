#!/usr/bin/env bash
# Fetch all PR data for Renovate PR evaluation
# Usage: fetch-pr-data.sh --output-dir DIR [--pr NUMBER]

set -euo pipefail

_FPD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$_FPD_DIR/../lib/common.sh"

PR_NUMBER=""
REPO=""
OUTPUT_DIR=""
SHOW_HELP=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --pr)
                PR_NUMBER="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 --output-dir DIR [--pr NUMBER]"
                echo ""
                echo "Fetch all PR data for Renovate evaluation."
                echo "Writes pr-data.md and pr-diff.patch to OUTPUT_DIR."
                echo ""
                echo "Options:"
                echo "  --output-dir DIR Directory to write output files (required)"
                echo "  --pr NUMBER      PR number (default: auto-detect from current branch)"
                echo "  -h, --help       Show this help message"
                SHOW_HELP=true
                return 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                echo "Usage: $0 --output-dir DIR [--pr NUMBER]" >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$OUTPUT_DIR" ]]; then
        echo "ERROR: --output-dir is required" >&2
        return 1
    fi
}

check_prerequisites() {
    require_tools gh jq
    require_gh_auth
}

detect_pr() {
    if [[ -z "$PR_NUMBER" ]]; then
        PR_NUMBER=$(gh pr view --json number -q .number 2>/dev/null || true)
        if [[ -z "$PR_NUMBER" ]]; then
            echo "ERROR: Could not detect PR number. Use --pr NUMBER or run from a PR branch" >&2
            return 1
        fi
    fi
}

detect_repo() {
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    if [[ -z "$REPO" ]]; then
        echo "ERROR: Not in a git repository with GitHub remote" >&2
        return 1
    fi
}

fetch_metadata() {
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
}

fetch_body() {
    echo "## PR Body"
    if ! PR_BODY=$(gh pr view "$PR_NUMBER" --json body -q .body 2>&1); then
        echo "ERROR: Failed to fetch PR body"
        echo "${PR_BODY//$'\n'/$'\n'  }"
    else
        # Remove HTML comments (renovate debug info)
        echo "$PR_BODY" | sed 's/<!--[^>]*-->//g' | grep -v '^$'
    fi
    echo ""
}

fetch_files() {
    # Write diff first so we can include line offsets in the file list
    run_diff "$PR_NUMBER" "$OUTPUT_DIR/pr-diff.patch"

    # Build a map of file path -> line number in the patch
    declare -A DIFF_OFFSETS
    while IFS=: read -r line_num content; do
        # Extract the b/ path (new name) from "diff --git a/... b/..."
        local fpath
        fpath="${content##* b/}"
        DIFF_OFFSETS["$fpath"]="$line_num"
    done < <(grep -n '^diff --git ' "$OUTPUT_DIR/pr-diff.patch" 2>/dev/null || true)

    echo "## Files Changed"
    if ! FILES_DATA=$(gh pr view "$PR_NUMBER" --json files 2>&1); then
        echo "ERROR: Failed to fetch files data"
        echo "${FILES_DATA//$'\n'/$'\n'  }"
    else
        FILE_COUNT=$(echo "$FILES_DATA" | jq '.files | length')
        echo "Total: $FILE_COUNT files"
        echo ""
        echo "$FILES_DATA" | jq -r '.files[] | "\(.path)\t\(.additions)\t\(.deletions)"' | \
            while IFS=$'\t' read -r fpath adds dels; do
                local offset="${DIFF_OFFSETS[$fpath]:-}"
                if [[ -n "$offset" ]]; then
                    echo "- $fpath (+$adds/-$dels) [L$offset]"
                else
                    echo "- $fpath (+$adds/-$dels)"
                fi
            done
    fi
    echo ""
}

fetch_related_issues() {
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
}

main() {
    parse_args "$@"
    [[ "$SHOW_HELP" == "true" ]] && exit 0
    check_prerequisites
    detect_pr
    detect_repo

    local pr_data="$OUTPUT_DIR/pr-data.md"

    {
        fetch_metadata
        fetch_body
        fetch_files
        fetch_related_issues
    } > "$pr_data"

    echo "Wrote $pr_data" >&2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
