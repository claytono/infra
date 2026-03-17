#!/usr/bin/env bash
# Validate evaluator output for mechanical correctness
# Usage: validate-report.sh ARTIFACT_DIR
# Exit 0 = valid, Exit 1 = errors found (printed to stdout)
set -euo pipefail

ARTIFACT_DIR="${1:?Usage: validate-report.sh ARTIFACT_DIR}"
ERRORS=()

# --- Validate eval-meta.json ---
META="$ARTIFACT_DIR/eval-meta.json"
if [[ ! -s "$META" ]]; then
    ERRORS+=("META: eval-meta.json is missing or empty")
else
    # Valid label
    LABEL=$(jq -r '.label // empty' "$META" 2>/dev/null || true)
    case "$LABEL" in
        renovate:safe|renovate:caution|renovate:breaking|renovate:risk) ;;
        "") ERRORS+=("META: missing 'label' field") ;;
        *) ERRORS+=("META: invalid label '$LABEL' — must be one of: renovate:safe, renovate:caution, renovate:breaking, renovate:risk") ;;
    esac

    # Valid confidence
    CONFIDENCE=$(jq -r '.confidence // empty' "$META" 2>/dev/null || true)
    case "$CONFIDENCE" in
        high|medium|low) ;;
        "") ERRORS+=("META: missing 'confidence' field") ;;
        *) ERRORS+=("META: invalid confidence '$CONFIDENCE' — must be one of: high, medium, low") ;;
    esac

    # Required fields exist
    for field in packages sources_used ci_status; do
        if ! jq -e ".$field" "$META" > /dev/null 2>&1; then
            ERRORS+=("META: missing required field '$field'")
        fi
    done

    # ci_status valid
    CI=$(jq -r '.ci_status // empty' "$META" 2>/dev/null || true)
    case "$CI" in
        passing|failing|pending|unknown|"") ;;
        *) ERRORS+=("META: invalid ci_status '$CI' — must be one of: passing, failing, pending, unknown") ;;
    esac
fi

# --- Validate eval-report.md ---
REPORT="$ARTIFACT_DIR/eval-report.md"
if [[ ! -s "$REPORT" ]]; then
    ERRORS+=("REPORT: eval-report.md is missing or empty")
else
    CONTENT=$(cat "$REPORT")

    # Check for Hazards & Risks section (always required)
    if ! echo "$CONTENT" | grep -q "^## Hazards & Risks"; then
        ERRORS+=("REPORT: missing required '## Hazards & Risks' section")
    fi

    # Check for Sources section
    if ! echo "$CONTENT" | grep -q "^## Sources"; then
        ERRORS+=("REPORT: missing required '## Sources' section")
    fi

    # Check for Verdict section
    if ! echo "$CONTENT" | grep -q "^## .*Verdict:"; then
        ERRORS+=("REPORT: missing Verdict section (expected '## [emoji] Verdict: [Label]')")
    fi

    # Check verdict uses valid label name
    VERDICT_LINE=$(echo "$CONTENT" | grep "^## .*Verdict:" || true)
    if [[ -n "$VERDICT_LINE" ]]; then
        if ! echo "$VERDICT_LINE" | grep -qiE '\b(Safe|Caution|Breaking|Risk)\b'; then
            ERRORS+=("REPORT: verdict label must be one of: Safe, Caution, Breaking, Risk — found: $VERDICT_LINE")
        fi
    fi

    # Check for bare #NNN references (not inside markdown links)
    # Match #NNN that is NOT preceded by [ ( or / (which would indicate a markdown link or URL)
    BARE_REFS=$(echo "$CONTENT" | grep -oE '(^|[^(\[/])#[0-9]{3,}' | grep -oE '#[0-9]+' || true)
    if [[ -n "$BARE_REFS" ]]; then
        REF_COUNT=$(echo "$BARE_REFS" | wc -l | tr -d ' ')
        ERRORS+=("REPORT: found $REF_COUNT bare #NNN reference(s) without full markdown links — use [#NNN](url) format")
    fi

    # Check for Deep Dive section
    if ! echo "$CONTENT" | grep -q "^## The Deep Dive"; then
        ERRORS+=("REPORT: missing '## The Deep Dive' section")
    fi

    # Check Update Scope subsection
    if ! echo "$CONTENT" | grep -q "^### Update Scope"; then
        ERRORS+=("REPORT: missing '### Update Scope' subsection")
    fi
fi

# --- Validate eval-evidence.md ---
EVIDENCE="$ARTIFACT_DIR/eval-evidence.md"
if [[ ! -s "$EVIDENCE" ]]; then
    ERRORS+=("EVIDENCE: eval-evidence.md is missing or empty")
fi

# --- Log this invocation ---
LOG="$ARTIFACT_DIR/validate.log"
TIMESTAMP=$(date +%H:%M:%S)

# --- Output results ---
if [[ ${#ERRORS[@]} -eq 0 ]]; then
    echo "VALID: All checks passed"
    echo "[$TIMESTAMP] VALID" >> "$LOG"
    exit 0
else
    echo "ERRORS FOUND: ${#ERRORS[@]}"
    echo "[$TIMESTAMP] ERRORS: ${#ERRORS[@]}" >> "$LOG"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
        echo "  - $err" >> "$LOG"
    done
    exit 1
fi
