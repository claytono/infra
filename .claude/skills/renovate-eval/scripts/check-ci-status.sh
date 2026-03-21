#!/usr/bin/env bash
# Check CI status for a PR
# Usage: check-ci-status.sh [--pr NUMBER] [--wait] [--timeout SECONDS]

set -euo pipefail

_CCI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$_CCI_DIR/../lib/common.sh"

PR_NUMBER=""
WAIT=false
TIMEOUT=300
SHOW_HELP=false

parse_args() {
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
                SHOW_HELP=true
                return 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                echo "Usage: $0 [--pr NUMBER] [--wait] [--timeout SECONDS]" >&2
                return 1
                ;;
        esac
    done
}

check_prerequisites() {
    require_tools gh
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

wait_for_ci() {
    WAIT_EXIT=0
    if command -v timeout &>/dev/null; then
        timeout "$TIMEOUT" gh pr checks "$PR_NUMBER" --watch --interval 15 || WAIT_EXIT=$?
    elif command -v gtimeout &>/dev/null; then
        gtimeout "$TIMEOUT" gh pr checks "$PR_NUMBER" --watch --interval 15 || WAIT_EXIT=$?
    else
        echo "WARNING: timeout command not available, running without timeout" >&2
        gh pr checks "$PR_NUMBER" --watch --interval 15 || WAIT_EXIT=$?
    fi

    if [[ "$WAIT_EXIT" -eq 124 ]]; then
        echo ""
        echo "WARNING: CI check timed out after ${TIMEOUT}s"
        exit 2
    elif [[ "$WAIT_EXIT" -ne 0 ]]; then
        echo ""
        echo "WARNING: Some CI checks failed"
    fi
}

check_ci_once() {
    gh pr checks "$PR_NUMBER"
}

fetch_failed_logs() {
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
}

main() {
    parse_args "$@" || exit $?
    [[ "$SHOW_HELP" == "true" ]] && exit 0

    check_prerequisites || exit 1
    detect_pr || exit 1

    echo "# CI Status for PR #$PR_NUMBER"
    echo ""

    if [[ "$WAIT" == "true" ]]; then
        wait_for_ci
    else
        check_ci_once
    fi

    fetch_failed_logs
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
