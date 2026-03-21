#!/usr/bin/env bats

setup() {
    source "$BATS_TEST_DIRNAME/../lib/common.sh"
}

# --- VALID_LABELS and VALID_CONFIDENCE_LEVELS arrays ---

@test "VALID_LABELS array is populated with 4 entries" {
    [ "${#VALID_LABELS[@]}" -eq 4 ]
}

@test "VALID_CONFIDENCE_LEVELS array is populated with 3 entries" {
    [ "${#VALID_CONFIDENCE_LEVELS[@]}" -eq 3 ]
}

# --- validate_label ---

@test "validate_label accepts renovate:safe" {
    run validate_label "renovate:safe"
    [ "$status" -eq 0 ]
}

@test "validate_label accepts renovate:caution" {
    run validate_label "renovate:caution"
    [ "$status" -eq 0 ]
}

@test "validate_label accepts renovate:breaking" {
    run validate_label "renovate:breaking"
    [ "$status" -eq 0 ]
}

@test "validate_label accepts renovate:risk" {
    run validate_label "renovate:risk"
    [ "$status" -eq 0 ]
}

@test "validate_label rejects invalid label" {
    run validate_label "renovate:invalid"
    [ "$status" -eq 1 ]
}

@test "validate_label rejects empty string" {
    run validate_label ""
    [ "$status" -eq 1 ]
}

# --- validate_confidence ---

@test "validate_confidence accepts high" {
    run validate_confidence "high"
    [ "$status" -eq 0 ]
}

@test "validate_confidence accepts medium" {
    run validate_confidence "medium"
    [ "$status" -eq 0 ]
}

@test "validate_confidence accepts low" {
    run validate_confidence "low"
    [ "$status" -eq 0 ]
}

@test "validate_confidence rejects invalid value" {
    run validate_confidence "extreme"
    [ "$status" -eq 1 ]
}

@test "validate_confidence rejects empty string" {
    run validate_confidence ""
    [ "$status" -eq 1 ]
}

# --- build_sentinel_comment ---

@test "build_sentinel_comment outputs correct format with all fields" {
    run build_sentinel_comment "renovate:safe" "high" 1 "success" 2 "abc123"
    [ "$status" -eq 0 ]
    [[ "$output" == '<!-- renovate-eval-skill:{"version":3,"label":"renovate:safe","confidence":"high","rounds":1,"ci_status":"success","eval_count":2,"fingerprint":"abc123"} -->' ]]
}

@test "build_sentinel_comment uses default version 3" {
    run build_sentinel_comment "renovate:caution" "medium" 2 "pending" 1 "def456"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"version":3'* ]]
}

@test "build_sentinel_comment accepts custom version" {
    run build_sentinel_comment "renovate:risk" "low" 3 "failure" 5 "ghi789" 4
    [ "$status" -eq 0 ]
    [[ "$output" == *'"version":4'* ]]
}

# --- build_sentinel_comment output matches workflow regex ---

@test "build_sentinel_comment output matches workflow gate regex" {
    run build_sentinel_comment "renovate:breaking" "high" 1 "success" 1 "fingerprint1"
    [ "$status" -eq 0 ]
    # The workflow gate uses this exact grep pattern
    echo "$output" | grep -o '<!-- renovate-eval-skill:{[^}]*}'
}

# --- parse_sentinel_json ---

@test "parse_sentinel_json round-trip: build then parse verifies JSON fields" {
    sentinel=$(build_sentinel_comment "renovate:safe" "high" 2 "success" 3 "fp42")
    json=$(echo "$sentinel" | parse_sentinel_json)
    [[ "$json" == *'"label":"renovate:safe"'* ]]
    [[ "$json" == *'"confidence":"high"'* ]]
    [[ "$json" == *'"rounds":2'* ]]
    [[ "$json" == *'"ci_status":"success"'* ]]
    [[ "$json" == *'"eval_count":3'* ]]
    [[ "$json" == *'"fingerprint":"fp42"'* ]]
    [[ "$json" == *'"version":3'* ]]
}

@test "parse_sentinel_json accepts input as argument" {
    sentinel=$(build_sentinel_comment "renovate:caution" "low" 1 "pending" 1 "argtest")
    json=$(parse_sentinel_json "$sentinel")
    [[ "$json" == *'"label":"renovate:caution"'* ]]
    [[ "$json" == *'"confidence":"low"'* ]]
}

# --- log_info / log_warn / log_error write to stderr ---

@test "log_info writes to stderr not stdout" {
    run bash -c 'source "$1/../lib/common.sh" && log_info "hello info" 2>&1' -- "$BATS_TEST_DIRNAME"
    [[ "$output" == *"INFO: hello info"* ]]
}

@test "log_info produces no stdout" {
    stdout=$(source "$BATS_TEST_DIRNAME/../lib/common.sh" && log_info "test" 2>/dev/null)
    [ -z "$stdout" ]
}

@test "log_warn writes to stderr not stdout" {
    run bash -c 'source "$1/../lib/common.sh" && log_warn "hello warn" 2>&1' -- "$BATS_TEST_DIRNAME"
    [[ "$output" == *"WARNING: hello warn"* ]]
}

@test "log_warn produces no stdout" {
    stdout=$(source "$BATS_TEST_DIRNAME/../lib/common.sh" && log_warn "test" 2>/dev/null)
    [ -z "$stdout" ]
}

@test "log_error writes to stderr not stdout" {
    run bash -c 'source "$1/../lib/common.sh" && log_error "hello error" 2>&1' -- "$BATS_TEST_DIRNAME"
    [[ "$output" == *"ERROR: hello error"* ]]
}

@test "log_error produces no stdout" {
    stdout=$(source "$BATS_TEST_DIRNAME/../lib/common.sh" && log_error "test" 2>/dev/null)
    [ -z "$stdout" ]
}

# --- require_tools ---

@test "require_tools succeeds for bash" {
    run require_tools bash
    [ "$status" -eq 0 ]
}

@test "require_tools succeeds for multiple existing tools" {
    run require_tools bash cat
    [ "$status" -eq 0 ]
}

@test "require_tools fails for nonexistent tool" {
    run require_tools nonexistent_tool_xyz
    [ "$status" -eq 1 ]
}

@test "require_tools error message names the missing tool" {
    run bash -c 'source "$1/../lib/common.sh" && require_tools nonexistent_tool_xyz 2>&1' -- "$BATS_TEST_DIRNAME"
    [[ "$output" == *"nonexistent_tool_xyz"* ]]
}

@test "require_tools fails if any tool is missing" {
    run require_tools bash nonexistent_tool_xyz
    [ "$status" -eq 1 ]
}
