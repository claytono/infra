#!/usr/bin/env bash
# Check CI status for a PR
# Usage: check-ci-status.sh [--pr NUMBER] [--wait] [--timeout SECONDS]

set -euo pipefail

# Parse arguments
PR_NUMBER=""
WAIT=false
TIMEOUT=300
while [[ $# -gt 0 ]]; do
    case $1 in
        --pr)
            PR_NUMBER="$2"
            shift 2
            ;;
        --wait)
            WAIT=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--pr NUMBER] [--wait] [--timeout SECONDS]"
            echo ""
            echo "Check CI status for a PR."
            echo ""
            echo "Options:"
            echo "  --pr NUMBER       PR number (default: auto-detect from current branch)"
            echo "  --wait            Poll CI status until all checks complete"
            echo "  --timeout SECONDS Max wait time in seconds (default: 300)"
            echo "  -h, --help        Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--pr NUMBER] [--wait] [--timeout SECONDS]" >&2
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

echo "# CI Status for PR #$PR_NUMBER"
echo ""

if [[ "$WAIT" == "true" ]]; then
    # Wait for CI to complete with timeout
    WAIT_EXIT=0
    if command -v timeout &>/dev/null; then
        timeout "$TIMEOUT" gh pr checks "$PR_NUMBER" --watch --interval 15 || WAIT_EXIT=$?
    elif command -v gtimeout &>/dev/null; then
        gtimeout "$TIMEOUT" gh pr checks "$PR_NUMBER" --watch --interval 15 || WAIT_EXIT=$?
    else
        echo "WARNING: timeout command not available, running without timeout" >&2
        gh pr checks "$PR_NUMBER" --watch --interval 15 || WAIT_EXIT=$?
    fi

    # Map timeout exit code (124) to exit 2
    if [[ "$WAIT_EXIT" -eq 124 ]]; then
        echo ""
        echo "WARNING: CI check timed out after ${TIMEOUT}s"
        exit 2
    elif [[ "$WAIT_EXIT" -ne 0 ]]; then
        echo ""
        echo "WARNING: Some CI checks failed"
    fi
else
    # One-shot check
    gh pr checks "$PR_NUMBER"
fi

# Check if any failures exist (for fetching logs) using JSON for robust parsing
if gh pr checks "$PR_NUMBER" --json name,conclusion,detailsUrl 2>/dev/null | \
    jq -e '.[] | select(.conclusion == "FAILURE")' >/dev/null 2>&1; then
    echo ""
    echo "## Failed Check Logs"

    gh pr checks "$PR_NUMBER" --json name,conclusion,detailsUrl | \
        jq -r '.[] | select(.conclusion == "FAILURE") | [.name, .detailsUrl] | @tsv' | \
        while IFS=$'\t' read -r CHECK_NAME LINK; do
            RUN_ID=$(echo "$LINK" | sed -n 's#.*/runs/\([0-9]*\).*#\1#p')

            if [[ -n "$RUN_ID" ]]; then
                echo ""
                echo "### $CHECK_NAME"
                echo "Run: $LINK"
                echo '```'
                gh run view "$RUN_ID" --log 2>&1 | tail -100 || echo "Could not retrieve logs"
                echo '```'
            fi
        done
fi
