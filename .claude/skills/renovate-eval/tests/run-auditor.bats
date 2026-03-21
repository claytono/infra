#!/usr/bin/env bats

# Tests for run-auditor.sh prompt assembly
# These tests verify that the auditor prompt is constructed correctly
# without actually calling claude -p.

SCRIPT_DIR="$BATS_TEST_DIRNAME/.."

setup() {
    source "$SCRIPT_DIR/scripts/run-auditor.sh"
    SCRIPT_DIR="$BATS_TEST_DIRNAME/.."
    # These variables are used by the sourced run-auditor.sh functions
    # shellcheck disable=SC2034
    MODEL="test-model"
    # shellcheck disable=SC2034
    ROUND=1
    ARTIFACT_DIR="$(mktemp -d)"
    echo "# Test Report" > "$ARTIFACT_DIR/eval-report.md"
    echo "# Test Evidence" > "$ARTIFACT_DIR/eval-evidence.md"
    load_report_data
}

teardown() {
    rm -rf "$ARTIFACT_DIR"
}

# --- auditor.md structure ---

@test "auditor.md has --- separator between preamble and instructions" {
    run grep -c '^---$' "$SCRIPT_DIR/prompts/auditor.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "auditor.md preamble contains role statement" {
    preamble=$(sed '/^---$/q' "$SCRIPT_DIR/prompts/auditor.md")
    echo "$preamble" | grep -q "auditing a Renovate PR evaluation report"
}

@test "auditor.md instructions contain Rubric Compliance section" {
    instructions=$(sed '1,/^---$/d' "$SCRIPT_DIR/prompts/auditor.md")
    echo "$instructions" | grep -q "Rubric Compliance"
}

@test "auditor.md instructions contain Structural Quality section" {
    instructions=$(sed '1,/^---$/d' "$SCRIPT_DIR/prompts/auditor.md")
    echo "$instructions" | grep -q "Structural Quality"
}

@test "auditor.md instructions contain Evidence Judgment section" {
    instructions=$(sed '1,/^---$/d' "$SCRIPT_DIR/prompts/auditor.md")
    echo "$instructions" | grep -q "Evidence Judgment"
}

@test "auditor.md instructions contain Output Schema" {
    instructions=$(sed '1,/^---$/d' "$SCRIPT_DIR/prompts/auditor.md")
    echo "$instructions" | grep -q "Output Schema"
}

@test "auditor.md instructions contain weasel words check" {
    instructions=$(sed '1,/^---$/d' "$SCRIPT_DIR/prompts/auditor.md")
    echo "$instructions" | grep -q "Weasel words"
}

@test "auditor.md does not duplicate evaluator risk calibration rules" {
    # The old auditor.md had its own "renovate:safe requires NO breaking
    # changes, NO security issues" rules. The new one should not.
    run grep -c "NO breaking changes" "$SCRIPT_DIR/prompts/auditor.md"
    [ "$output" -eq 0 ] || [ "$status" -ne 0 ]
}

@test "auditor.md includes pre-existing CVE example" {
    grep -q "pre-existing CVEs" "$SCRIPT_DIR/prompts/auditor.md"
}

# --- prompt assembly in run-auditor.sh ---

@test "sed preamble extraction ends at first ---" {
    preamble=$(sed '/^---$/q' "$SCRIPT_DIR/prompts/auditor.md")
    # Should contain the role but not the audit checklist
    echo "$preamble" | grep -q "auditing"
    # SC2314: ! is the last command here, so it will fail the test correctly
    # shellcheck disable=SC2314
    ! echo "$preamble" | grep -q "Rubric Compliance"
}

@test "sed instruction extraction starts after first ---" {
    instructions=$(sed '1,/^---$/d' "$SCRIPT_DIR/prompts/auditor.md")
    # Should contain audit checklist but not the role preamble header
    echo "$instructions" | grep -q "Rubric Compliance"
    # SC2314: ! is the last command here, so it will fail the test correctly
    # shellcheck disable=SC2314
    ! echo "$instructions" | grep -q "^# Renovate Evaluation Report Auditor"
}

# --- reference documents exist ---

@test "evaluator.md exists for embedding" {
    [ -f "$SCRIPT_DIR/prompts/evaluator.md" ]
}

@test "report-format.md exists for embedding" {
    [ -f "$SCRIPT_DIR/prompts/report-format.md" ]
}
