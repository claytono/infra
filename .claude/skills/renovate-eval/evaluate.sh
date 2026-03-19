#!/usr/bin/env bash
# Renovate PR evaluation engine
# Orchestrates evaluator-auditor feedback loop
set -euo pipefail

# Defaults
MODE="dry-run"
CONTEXT="local"
EVALUATOR_MODEL="opus"
AUDITOR_MODEL="sonnet"
CI_TIMEOUT=300
PR_NUMBER=""
INSTRUCTIONS=""
KEEP_ARTIFACTS=false

usage() {
    cat <<EOF
Usage: evaluate.sh --pr NUMBER [--dry-run|--post] [--context local|ci]
         [--evaluator-model MODEL] [--auditor-model MODEL]
         [--ci-timeout SECONDS] [--instructions "TEXT"]
         [--keep-artifacts]

Defaults: --dry-run, --context local, --evaluator-model opus,
          --auditor-model sonnet, --ci-timeout 300
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --pr)
            PR_NUMBER="$2"
            shift 2
            ;;
        --dry-run)
            MODE="dry-run"
            shift
            ;;
        --post)
            MODE="post"
            shift
            ;;
        --context)
            CONTEXT="$2"
            shift 2
            ;;
        --evaluator-model)
            EVALUATOR_MODEL="$2"
            shift 2
            ;;
        --auditor-model)
            AUDITOR_MODEL="$2"
            shift 2
            ;;
        --ci-timeout)
            CI_TIMEOUT="$2"
            shift 2
            ;;
        --instructions)
            INSTRUCTIONS="$2"
            shift 2
            ;;
        --keep-artifacts)
            KEEP_ARTIFACTS=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$PR_NUMBER" ]]; then
    echo "ERROR: --pr NUMBER is required" >&2
    usage >&2
    exit 1
fi

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
ARTIFACT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/renovate-eval-${PR_NUMBER}.XXXXXX")

cleanup_artifacts() {
    if [[ "$KEEP_ARTIFACTS" == "false" && -d "$ARTIFACT_DIR" ]]; then
        rm -rf "$ARTIFACT_DIR"
    fi
}
trap cleanup_artifacts EXIT

# Verify gh is authenticated before proceeding
if ! gh auth status &>/dev/null; then
    echo "ERROR: Not authenticated with GitHub. Run 'gh auth login'" >&2
    exit 1
fi

TOTAL_START=$SECONDS
echo "=== Renovate PR Evaluation ==="
echo "PR: #$PR_NUMBER"
echo "Mode: $MODE"
echo "Context: $CONTEXT"
echo "Evaluator: $EVALUATOR_MODEL"
echo "Auditor: $AUDITOR_MODEL"
echo ""

# Data collection
echo "--- Fetching PR data ---"
"$SCRIPT_DIR/scripts/fetch-pr-data.sh" --pr "$PR_NUMBER" \
    > "$ARTIFACT_DIR/pr-data.md" || true

echo "--- Checking CI status ---"
if [[ "$MODE" == "post" ]]; then
    "$SCRIPT_DIR/scripts/check-ci-status.sh" --pr "$PR_NUMBER" --wait \
        --timeout "$CI_TIMEOUT" > "$ARTIFACT_DIR/ci-status.md" || true
else
    "$SCRIPT_DIR/scripts/check-ci-status.sh" --pr "$PR_NUMBER" \
        > "$ARTIFACT_DIR/ci-status.md" || true
fi

# Evaluator-auditor loop
MAX_ROUNDS=3
ROUND=1
STATUS="FEEDBACK"
EVAL_SESSION_ID=""
AUDIT_SESSION_ID=""

echo ""
echo "--- Starting evaluation loop ---"

while [[ "$ROUND" -le "$MAX_ROUNDS" && "$STATUS" != "PASS" ]]; do
    echo ""
    echo "=== Round $ROUND ==="

    EVAL_START=$SECONDS
    echo ""
    echo "--- Evaluator (round $ROUND) ---"
    EVAL_ARGS=(
        --round "$ROUND" --artifact-dir "$ARTIFACT_DIR" --model "$EVALUATOR_MODEL"
        --context "$CONTEXT" --script-dir "$SCRIPT_DIR" --repo-root "$REPO_ROOT"
    )
    [[ -n "$INSTRUCTIONS" ]] && EVAL_ARGS+=(--instructions "$INSTRUCTIONS")
    [[ -n "$EVAL_SESSION_ID" ]] && EVAL_ARGS+=(--session-id "$EVAL_SESSION_ID")

    "$SCRIPT_DIR/scripts/run-evaluator.sh" "${EVAL_ARGS[@]}" \
        2>&1 | tee "$ARTIFACT_DIR/evaluator-r${ROUND}.log"
    echo "Evaluator completed in $(( SECONDS - EVAL_START ))s"

    # Capture session ID from round 1 for resume in subsequent rounds
    if [[ "$ROUND" -eq 1 && -f "$ARTIFACT_DIR/evaluator-output.json" ]]; then
        EVAL_SESSION_ID=$(jq -r '.session_id // empty' "$ARTIFACT_DIR/evaluator-output.json" 2>/dev/null || true)
        [[ -n "$EVAL_SESSION_ID" ]] && echo "Evaluator session: $EVAL_SESSION_ID"
    fi

    # Validate evaluator output
    if [[ ! -s "$ARTIFACT_DIR/eval-report.md" ]]; then
        echo "ERROR: no report produced (round $ROUND)" >&2
        exit 1
    fi
    if [[ ! -s "$ARTIFACT_DIR/eval-meta.json" ]]; then
        echo "ERROR: no metadata produced (round $ROUND)" >&2
        exit 1
    fi
    if ! jq -e '.label | IN("renovate:safe","renovate:caution","renovate:breaking","renovate:risk")' \
        "$ARTIFACT_DIR/eval-meta.json" > /dev/null 2>&1; then
        echo "ERROR: invalid label in metadata" >&2
        cat "$ARTIFACT_DIR/eval-meta.json" >&2
        exit 1
    fi
    if ! jq -e '.confidence | IN("high","medium","low")' \
        "$ARTIFACT_DIR/eval-meta.json" > /dev/null 2>&1; then
        echo "ERROR: invalid confidence in metadata" >&2
        cat "$ARTIFACT_DIR/eval-meta.json" >&2
        exit 1
    fi

    # Run mechanical validator (log-only — auditor handles enforcement)
    if ! "$SCRIPT_DIR/scripts/validate-report.sh" "$ARTIFACT_DIR"; then
        echo "WARNING: evaluator output has validation issues (round $ROUND)" >&2
        cat "$ARTIFACT_DIR/validate.log" >&2 || true
    fi

    # Preserve per-round artifacts for debugging
    cp "$ARTIFACT_DIR/eval-report.md" "$ARTIFACT_DIR/eval-report-r${ROUND}.md"
    cp "$ARTIFACT_DIR/eval-meta.json" "$ARTIFACT_DIR/eval-meta-r${ROUND}.json"
    cp "$ARTIFACT_DIR/eval-evidence.md" "$ARTIFACT_DIR/eval-evidence-r${ROUND}.md" 2>/dev/null || true

    AUDIT_START=$SECONDS
    echo ""
    echo "--- Auditor (round $ROUND) ---"
    AUDIT_ARGS=(
        --round "$ROUND" --artifact-dir "$ARTIFACT_DIR" --model "$AUDITOR_MODEL"
        --script-dir "$SCRIPT_DIR"
    )
    [[ -n "$AUDIT_SESSION_ID" ]] && AUDIT_ARGS+=(--session-id "$AUDIT_SESSION_ID")

    "$SCRIPT_DIR/scripts/run-auditor.sh" "${AUDIT_ARGS[@]}"
    echo "Auditor completed in $(( SECONDS - AUDIT_START ))s"

    # Validate auditor output
    if [[ ! -s "$ARTIFACT_DIR/audit-result.json" ]]; then
        echo "ERROR: no audit result (round $ROUND)" >&2
        exit 1
    fi
    if ! jq -e '.status | IN("PASS","FEEDBACK")' \
        "$ARTIFACT_DIR/audit-result.json" > /dev/null 2>&1; then
        echo "ERROR: invalid audit status" >&2
        cat "$ARTIFACT_DIR/audit-result.json" >&2
        exit 1
    fi

    # Capture auditor session ID from round 1
    if [[ "$ROUND" -eq 1 && -f "$ARTIFACT_DIR/auditor-output.json" ]]; then
        AUDIT_SESSION_ID=$(jq -r '.session_id // empty' "$ARTIFACT_DIR/auditor-output.json" 2>/dev/null || true)
        [[ -n "$AUDIT_SESSION_ID" ]] && echo "Auditor session: $AUDIT_SESSION_ID"
    fi

    # Preserve per-round audit artifacts
    cp "$ARTIFACT_DIR/audit-result.json" "$ARTIFACT_DIR/audit-result-r${ROUND}.json"
    cp "$ARTIFACT_DIR/auditor-raw.log" "$ARTIFACT_DIR/auditor-r${ROUND}.log" 2>/dev/null || true

    STATUS=$(jq -r '.status' "$ARTIFACT_DIR/audit-result.json")
    echo "Audit status: $STATUS"

    if [[ "$STATUS" == "FEEDBACK" ]]; then
        ISSUE_COUNT=$(jq '.issues | length' "$ARTIFACT_DIR/audit-result.json")
        echo "Issues found: $ISSUE_COUNT"
        jq -r '.issues[] | "  - [\(.severity)] \(.section): \(.description)"' \
            "$ARTIFACT_DIR/audit-result.json"
    fi

    ROUND=$((ROUND + 1))
done

# Handle failed audit after max rounds
if [[ "$STATUS" != "PASS" ]]; then
    echo ""
    echo "WARNING: Report did not pass audit after $MAX_ROUNDS rounds"

    {
        echo '> ⚠️ **This report did not pass automated quality review.** Treat with skepticism.'
        echo ""
        cat "$ARTIFACT_DIR/eval-report.md"
    } > "$ARTIFACT_DIR/eval-report.md.tmp"
    mv "$ARTIFACT_DIR/eval-report.md.tmp" "$ARTIFACT_DIR/eval-report.md"

    jq '.label = "renovate:risk"' "$ARTIFACT_DIR/eval-meta.json" \
        > "$ARTIFACT_DIR/eval-meta.json.tmp"
    mv "$ARTIFACT_DIR/eval-meta.json.tmp" "$ARTIFACT_DIR/eval-meta.json"
fi

# Cost summary (before cleanup which may delete the files)
TOTAL_COST=0
for cost_file in "$ARTIFACT_DIR"/evaluator-cost-r*.json "$ARTIFACT_DIR"/auditor-cost-r*.json; do
    [[ -f "$cost_file" ]] || continue
    FILE_COST=$(jq -r '.cost_usd // 0' "$cost_file" 2>/dev/null || echo 0)
    TOTAL_COST=$(echo "$TOTAL_COST + $FILE_COST" | bc 2>/dev/null || echo "$TOTAL_COST")
done

# Output mode
if [[ "$MODE" == "dry-run" ]]; then
    echo ""
    echo "=== Report ==="
    cat "$ARTIFACT_DIR/eval-report.md"
    echo ""
    echo "=== Metadata ==="
    jq . "$ARTIFACT_DIR/eval-meta.json"
elif [[ "$MODE" == "post" ]]; then
    echo ""
    echo "--- Posting results ---"

    REPO_NWO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

    # Ensure labels exist (without --force to respect user color changes)
    for pair in "renovate:safe 0e8a16" "renovate:caution fbca04" \
        "renovate:breaking e99d42" "renovate:risk d93f0b" "renovate:evaluated 0075ca"; do
        name="${pair% *}"
        color="${pair#* }"
        gh label create "$name" --color "$color" 2>/dev/null || true
    done

    # Find existing comment and extract eval_count
    EXISTING_COMMENT=$(gh api "repos/$REPO_NWO/issues/$PR_NUMBER/comments" \
        --paginate --jq '
        [.[] | select(.body | contains("<!-- renovate-eval-skill:"))] | last |
        {id, body}' 2>/dev/null || echo "{}")
    COMMENT_ID=$(echo "$EXISTING_COMMENT" | jq -r '.id // empty' 2>/dev/null || echo "")
    EXISTING_BODY=$(echo "$EXISTING_COMMENT" | jq -r '.body // empty' 2>/dev/null || echo "")

    # Extract eval_count from existing sentinel
    PREV_EVAL_COUNT=0
    if [[ -n "$EXISTING_BODY" ]]; then
        PREV_EVAL_COUNT=$(echo "$EXISTING_BODY" | \
            grep -o '<!-- renovate-eval-skill:{[^}]*}' | \
            sed 's/<!-- renovate-eval-skill://' | \
            jq -r '.eval_count // 0' 2>/dev/null || echo 0)
    fi

    if [[ "${EVAL_TRIGGER:-manual}" == "manual" ]]; then
        EVAL_COUNT=1
    else
        EVAL_COUNT=$((PREV_EVAL_COUNT + 1))
    fi

    # Construct comment body with metadata sentinel
    LABEL=$(jq -r '.label' "$ARTIFACT_DIR/eval-meta.json")
    CONFIDENCE=$(jq -r '.confidence' "$ARTIFACT_DIR/eval-meta.json")
    CI=$(jq -r '.ci_status' "$ARTIFACT_DIR/eval-meta.json")
    FINAL_ROUND=$((ROUND - 1))
    {
        echo "<!-- renovate-eval-skill:{\"version\":2,\"label\":\"$LABEL\",\"confidence\":\"$CONFIDENCE\",\"rounds\":$FINAL_ROUND,\"ci_status\":\"$CI\",\"eval_count\":$EVAL_COUNT} -->"
        echo ""
        cat "$ARTIFACT_DIR/eval-report.md"
    } > "$ARTIFACT_DIR/comment-body.md"

    # Create or update comment
    if [[ -n "$COMMENT_ID" && "$COMMENT_ID" != "null" ]]; then
        echo "Updating existing comment $COMMENT_ID"
        gh api --method PATCH "repos/$REPO_NWO/issues/comments/$COMMENT_ID" \
            -F body=@"$ARTIFACT_DIR/comment-body.md"
    else
        echo "Creating new comment"
        gh pr comment "$PR_NUMBER" --body-file "$ARTIFACT_DIR/comment-body.md"
    fi

    # Apply labels (only remove old risk labels that differ from the new one)
    CURRENT_LABELS=$(gh pr view "$PR_NUMBER" --json labels --jq '[.labels[].name] | join(",")' 2>/dev/null || echo "")
    REMOVE_ARGS=()
    for old_label in renovate:safe renovate:caution renovate:breaking renovate:risk; do
        if [[ "$old_label" != "$LABEL" && "$CURRENT_LABELS" == *"$old_label"* ]]; then
            REMOVE_ARGS+=(--remove-label "$old_label")
        fi
    done
    ADD_ARGS=()
    [[ "$CURRENT_LABELS" != *"$LABEL"* ]] && ADD_ARGS+=(--add-label "$LABEL")
    [[ "$CURRENT_LABELS" != *"renovate:evaluated"* ]] && ADD_ARGS+=(--add-label "renovate:evaluated")
    if [[ ${#REMOVE_ARGS[@]} -gt 0 || ${#ADD_ARGS[@]} -gt 0 ]]; then
        gh pr edit "$PR_NUMBER" "${REMOVE_ARGS[@]}" "${ADD_ARGS[@]}"
    fi

    echo "Posted comment and applied labels: $LABEL, renovate:evaluated"
fi

echo ""
echo "=== Evaluation complete in $(( SECONDS - TOTAL_START ))s ==="
echo "Total cost: \$$(printf '%.2f' "$TOTAL_COST" 2>/dev/null || echo "$TOTAL_COST")"
if [[ "$KEEP_ARTIFACTS" == "true" ]]; then
    echo "Artifacts: $ARTIFACT_DIR"
fi
