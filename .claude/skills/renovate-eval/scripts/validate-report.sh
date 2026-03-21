#!/usr/bin/env bash
# Validate evaluator output for mechanical correctness
# Usage: validate-report.sh ARTIFACT_DIR
# Exit 0 = valid, Exit 1 = errors found (printed to stdout)
set -euo pipefail

_VR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$_VR_DIR/../lib/common.sh"

ERRORS=()

validate_meta() {
    local artifact_dir="$1"
    local META="$artifact_dir/eval-meta.json"
    if [[ ! -s "$META" ]]; then
        ERRORS+=("META: eval-meta.json is missing or empty")
        return 0
    fi

    # Valid label
    LABEL=$(jq -r '.label // empty' "$META" 2>/dev/null || true)
    if [[ -z "$LABEL" ]]; then
        ERRORS+=("META: missing 'label' field")
    elif ! validate_label "$LABEL"; then
        ERRORS+=("META: invalid label '$LABEL' — must be one of: ${VALID_LABELS[*]}")
    fi

    # Valid confidence
    CONFIDENCE=$(jq -r '.confidence // empty' "$META" 2>/dev/null || true)
    if [[ -z "$CONFIDENCE" ]]; then
        ERRORS+=("META: missing 'confidence' field")
    elif ! validate_confidence "$CONFIDENCE"; then
        ERRORS+=("META: invalid confidence '$CONFIDENCE' — must be one of: ${VALID_CONFIDENCE_LEVELS[*]}")
    fi

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
}

validate_report_content() {
    local artifact_dir="$1"
    local REPORT="$artifact_dir/eval-report.md"
    if [[ ! -s "$REPORT" ]]; then
        ERRORS+=("REPORT: eval-report.md is missing or empty")
        return 0
    fi

    local CONTENT
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
    local VERDICT_LINE
    VERDICT_LINE=$(echo "$CONTENT" | grep "^## .*Verdict:" || true)
    if [[ -n "$VERDICT_LINE" ]]; then
        if ! echo "$VERDICT_LINE" | grep -qiE '\b(Safe|Caution|Breaking|Risk)\b'; then
            ERRORS+=("REPORT: verdict label must be one of: Safe, Caution, Breaking, Risk — found: $VERDICT_LINE")
        fi
    fi

    # Check for bare #NNN references (not inside markdown links)
    # Match #NNN that is NOT preceded by [ ( or / (which would indicate a markdown link or URL)
    local BARE_REFS
    BARE_REFS=$(echo "$CONTENT" | grep -oE '(^|[^(\[/])#[0-9]{3,}' | grep -oE '#[0-9]+' || true)
    if [[ -n "$BARE_REFS" ]]; then
        local REF_COUNT
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
}

validate_evidence() {
    local artifact_dir="$1"
    local EVIDENCE="$artifact_dir/eval-evidence.md"
    if [[ ! -s "$EVIDENCE" ]]; then
        ERRORS+=("EVIDENCE: eval-evidence.md is missing or empty")
    fi
}

log_and_report() {
    local artifact_dir="$1"
    local LOG="$artifact_dir/validate.log"
    local TIMESTAMP
    TIMESTAMP=$(date +%H:%M:%S)

    if [[ ${#ERRORS[@]} -eq 0 ]]; then
        echo "VALID: All checks passed"
        echo "[$TIMESTAMP] VALID" >> "$LOG"
        return 0
    else
        echo "ERRORS FOUND: ${#ERRORS[@]}"
        echo "[$TIMESTAMP] ERRORS: ${#ERRORS[@]}" >> "$LOG"
        for err in "${ERRORS[@]}"; do
            echo "  - $err"
            echo "  - $err" >> "$LOG"
        done
        return 1
    fi
}

main() {
    local ARTIFACT_DIR="${1:?Usage: validate-report.sh ARTIFACT_DIR}"
    ERRORS=()

    validate_meta "$ARTIFACT_DIR"
    validate_report_content "$ARTIFACT_DIR"
    validate_evidence "$ARTIFACT_DIR"
    log_and_report "$ARTIFACT_DIR" || exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
