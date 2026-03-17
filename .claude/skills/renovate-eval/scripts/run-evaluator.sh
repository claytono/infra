#!/usr/bin/env bash
# Run the evaluator via claude -p
# Round 1: full evaluation with evaluator.md as prompt, data in files
# Round 2+: resume session with revision instructions
set -euo pipefail

# Parse arguments
ROUND=""
ARTIFACT_DIR=""
MODEL=""
CONTEXT=""
SCRIPT_DIR=""
REPO_ROOT=""
INSTRUCTIONS=""
SESSION_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --round) ROUND="$2"; shift 2 ;;
        --artifact-dir) ARTIFACT_DIR="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --context) CONTEXT="$2"; shift 2 ;;
        --script-dir) SCRIPT_DIR="$2"; shift 2 ;;
        --repo-root) REPO_ROOT="$2"; shift 2 ;;
        --instructions) INSTRUCTIONS="$2"; shift 2 ;;
        --session-id) SESSION_ID="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

for var in ROUND ARTIFACT_DIR MODEL CONTEXT SCRIPT_DIR REPO_ROOT; do
    if [[ -z "${!var}" ]]; then
        echo "ERROR: --${var,,//_/-} is required" >&2
        exit 1
    fi
done

REPO_CONTEXT_FILE="$REPO_ROOT/.claude/renovate-eval.md"
INSTRUCTIONS_BLOCK=""
if [[ -n "$INSTRUCTIONS" ]]; then
    INSTRUCTIONS_BLOCK="
## Additional Instructions from User

$INSTRUCTIONS"
fi

OUTPUT_JSON="$ARTIFACT_DIR/evaluator-output.json"

if [[ "$ROUND" -eq 1 ]]; then
    claude -p --model "$MODEL" --permission-mode bypassPermissions \
        --output-format json <<EVAL_PROMPT > "$OUTPUT_JSON"
$(cat "$SCRIPT_DIR/prompts/evaluator.md")

---

## Context Mode

You are running in **$CONTEXT** mode.

## Data Files

Read these files for your research:
- **PR data:** $ARTIFACT_DIR/pr-data.md
- **CI status:** $ARTIFACT_DIR/ci-status.md
- **Report format spec:** $SCRIPT_DIR/prompts/report-format.md
$([[ -f "$REPO_CONTEXT_FILE" ]] && echo "- **Repo context:** $REPO_CONTEXT_FILE")
$INSTRUCTIONS_BLOCK

## Output Files

Write your report to: $ARTIFACT_DIR/eval-report.md
Write your metadata to: $ARTIFACT_DIR/eval-meta.json
Write your evidence to: $ARTIFACT_DIR/eval-evidence.md
EVAL_PROMPT
else
    # Round 2+: resume session (required — fresh call would lack evaluator contract)
    if [[ -z "$SESSION_ID" ]]; then
        echo "ERROR: no evaluator session ID for round $ROUND — cannot resume" >&2
        exit 1
    fi

    claude -p --model "$MODEL" --permission-mode bypassPermissions \
        --output-format json --resume "$SESSION_ID" <<EVAL_PROMPT > "$OUTPUT_JSON"
The auditor reviewed your report and found issues. Read the feedback at
$ARTIFACT_DIR/audit-result.json and revise your report.

Read the revision guidelines at $SCRIPT_DIR/prompts/revision.md for how
to approach this revision.

Run the validation script after making changes:
$SCRIPT_DIR/scripts/validate-report.sh $ARTIFACT_DIR
$INSTRUCTIONS_BLOCK
EVAL_PROMPT
fi

# Extract display text for logging
jq -r '.result // empty' "$OUTPUT_JSON" 2>/dev/null

# Save cost data
jq '{cost_usd: .total_cost_usd, input_tokens: .usage.input_tokens,
     cache_creation_tokens: .usage.cache_creation_input_tokens,
     cache_read_tokens: .usage.cache_read_input_tokens,
     output_tokens: .usage.output_tokens}' "$OUTPUT_JSON" \
    > "$ARTIFACT_DIR/evaluator-cost-r${ROUND}.json" 2>/dev/null || true
