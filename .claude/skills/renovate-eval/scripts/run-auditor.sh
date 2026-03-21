#!/usr/bin/env bash
# Run the auditor via claude -p (no tool access)
# Round 1: full audit with auditor.md as prompt
# Round 2+: resume session with revised report
set -euo pipefail

ROUND=""
ARTIFACT_DIR=""
MODEL=""
SCRIPT_DIR=""
SESSION_ID=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --round) ROUND="$2"; shift 2 ;;
            --artifact-dir) ARTIFACT_DIR="$2"; shift 2 ;;
            --model) MODEL="$2"; shift 2 ;;
            --script-dir) SCRIPT_DIR="$2"; shift 2 ;;
            --session-id) SESSION_ID="$2"; shift 2 ;;
            *) echo "Unknown argument: $1" >&2; return 1 ;;
        esac
    done
}

validate_args() {
    for var in ROUND ARTIFACT_DIR MODEL SCRIPT_DIR; do
        if [[ -z "${!var}" ]]; then
            echo "ERROR: --${var,,//_/-} is required" >&2
            return 1
        fi
    done
}

load_report_data() {
    REPORT=$(cat "$ARTIFACT_DIR/eval-report.md")
    EVIDENCE=$(cat "$ARTIFACT_DIR/eval-evidence.md" 2>/dev/null || echo "No evidence file provided.")
    OUTPUT_JSON="$ARTIFACT_DIR/auditor-output.json"
}

run_round_one() {
    cat <<AUDIT_PROMPT | claude -p --model "$MODEL" --permission-mode bypassPermissions --tools "" \
        --output-format json > "$OUTPUT_JSON"
$(cat "$SCRIPT_DIR/prompts/auditor.md")

---

## Report to Audit

$REPORT

---

## Evaluator Evidence

The evaluator provided the following evidence log documenting commands run,
config files read, and reasoning for risk assessments. Use this to verify
claims made in the report.

$EVIDENCE
AUDIT_PROMPT
}

run_revision() {
    if [[ -z "$SESSION_ID" ]]; then
        echo "ERROR: no auditor session ID for round $ROUND — cannot resume" >&2
        return 1
    fi

    cat <<AUDIT_PROMPT | claude -p --model "$MODEL" --permission-mode bypassPermissions --tools "" \
        --output-format json --resume "$SESSION_ID" > "$OUTPUT_JSON"
The evaluator has revised the report based on your feedback. Review the
revised report and evidence below. Check whether your previous issues
have been adequately addressed. Apply the same audit criteria.

## Current Round

$ROUND

## Revised Report

$REPORT

## Updated Evidence

$EVIDENCE
AUDIT_PROMPT
}

extract_result() {
    jq -r '.result // empty' "$OUTPUT_JSON" 2>/dev/null \
        | tee "$ARTIFACT_DIR/auditor-raw.log" \
        | sed -n '/---JSON_START---/,/---JSON_END---/{//!p;}' \
        > "$ARTIFACT_DIR/audit-result.json"
}

extract_cost() {
    jq '{cost_usd: .total_cost_usd, input_tokens: .usage.input_tokens,
         cache_creation_tokens: .usage.cache_creation_input_tokens,
         cache_read_tokens: .usage.cache_read_input_tokens,
         output_tokens: .usage.output_tokens}' "$OUTPUT_JSON" \
        > "$ARTIFACT_DIR/auditor-cost-r${ROUND}.json" 2>/dev/null || true
}

main() {
    parse_args "$@"
    validate_args
    load_report_data

    if [[ "$ROUND" -eq 1 ]]; then
        run_round_one
    else
        run_revision
    fi

    extract_result
    extract_cost
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
