#!/usr/bin/env bats

setup() {
    FIXTURES="$BATS_TEST_DIRNAME/fixtures"
    SCRIPT="$BATS_TEST_DIRNAME/../scripts/validate-report.sh"
}

copy_fixture() {
    local fixture="$1"
    local tmpdir
    tmpdir=$(mktemp -d)
    cp "$FIXTURES/$fixture/"* "$tmpdir/"
    echo "$tmpdir"
}

@test "valid report passes validation" {
    TMPDIR=$(copy_fixture valid-report)
    run "$SCRIPT" "$TMPDIR"
    rm -rf "$TMPDIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

@test "invalid label fails with error" {
    TMPDIR=$(copy_fixture bad-meta-label)
    run "$SCRIPT" "$TMPDIR"
    rm -rf "$TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid label"* ]]
    [[ "$output" == *"renovate:yolo"* ]]
}

@test "missing sections fails listing each missing section" {
    TMPDIR=$(copy_fixture missing-sections)
    run "$SCRIPT" "$TMPDIR"
    rm -rf "$TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Hazards & Risks"* ]]
    [[ "$output" == *"Sources"* ]]
    [[ "$output" == *"The Deep Dive"* ]]
    [[ "$output" == *"Update Scope"* ]]
}

@test "bare references fails" {
    TMPDIR=$(copy_fixture bare-references)
    run "$SCRIPT" "$TMPDIR"
    rm -rf "$TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bare #NNN reference"* ]]
}

@test "missing eval-meta.json fails" {
    TMPDIR=$(copy_fixture valid-report)
    rm "$TMPDIR/eval-meta.json"
    run "$SCRIPT" "$TMPDIR"
    rm -rf "$TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"eval-meta.json is missing or empty"* ]]
}

@test "missing eval-report.md fails" {
    TMPDIR=$(copy_fixture valid-report)
    rm "$TMPDIR/eval-report.md"
    run "$SCRIPT" "$TMPDIR"
    rm -rf "$TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"eval-report.md is missing or empty"* ]]
}

@test "missing eval-evidence.md fails" {
    TMPDIR=$(copy_fixture valid-report)
    rm "$TMPDIR/eval-evidence.md"
    run "$SCRIPT" "$TMPDIR"
    rm -rf "$TMPDIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"eval-evidence.md is missing or empty"* ]]
}
