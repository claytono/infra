#!/usr/bin/env bash
# Shared library for renovate-eval scripts
# Source this file; do not execute directly.
#
# IMPORTANT: Top-level code in this library must not write to stdout, as
# some callers pipe stdout to claude -p via heredoc. Functions may use
# stdout for return values when documented.

# --- Logging ---
# All log functions write to stderr only.

log_info() {
    echo "INFO: $*" >&2
}

log_warn() {
    echo "WARNING: $*" >&2
}

log_error() {
    echo "ERROR: $*" >&2
}

# --- Tool/auth validation ---

require_tools() {
    local missing=()
    for tool in "$@"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        return 1
    fi
}

require_gh_auth() {
    if [[ -n "${GH_TOKEN:-}" ]] || [[ -n "${GITHUB_TOKEN:-}" ]]; then
        if gh repo view &>/dev/null; then
            return 0
        fi
        log_error "GH_TOKEN/GITHUB_TOKEN is set but invalid or lacks required scopes"
        return 1
    fi
    if ! gh auth status &>/dev/null; then
        log_error "Not authenticated with GitHub. Run 'gh auth login' or set GH_TOKEN/GITHUB_TOKEN"
        return 1
    fi
}

# --- Shared constants ---

VALID_LABELS=(renovate:safe renovate:caution renovate:breaking renovate:risk)
VALID_CONFIDENCE_LEVELS=(high medium low)

validate_label() {
    local label="$1"
    local valid
    for valid in "${VALID_LABELS[@]}"; do
        [[ "$label" == "$valid" ]] && return 0
    done
    return 1
}

validate_confidence() {
    local confidence="$1"
    local valid
    for valid in "${VALID_CONFIDENCE_LEVELS[@]}"; do
        [[ "$confidence" == "$valid" ]] && return 0
    done
    return 1
}

# --- Diff utilities ---

# run_diff PR_NUMBER OUTPUT_FILE
# Writes the PR diff to OUTPUT_FILE. Tries gh pr diff first (no local side
# effects), falls back to local git diff --no-ext-diff if the API fails
# (e.g. HTTP 406 on large PRs).
run_diff() {
    local pr_number="$1" output_file="$2"

    if gh pr diff "$pr_number" > "$output_file" 2>/dev/null; then
        return 0
    fi

    log_warn "gh pr diff failed, falling back to local git diff"
    local base_ref head_ref
    base_ref=$(gh pr view "$pr_number" --json baseRefName -q .baseRefName)
    head_ref=$(gh pr view "$pr_number" --json headRefName -q .headRefName)

    if ! git remote update; then
        log_error "Failed to update remote refs"
        return 1
    fi
    if ! git diff --no-ext-diff "origin/${base_ref}...origin/${head_ref}" > "$output_file"; then
        log_error "git diff failed for origin/${base_ref}...origin/${head_ref}"
        return 1
    fi
}

# compute_fingerprint FILE
# Computes a SHA-256 fingerprint of the added/removed lines in a diff file.
# Prints the hash to stdout. Returns 1 if the file doesn't exist.
compute_fingerprint() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "Cannot compute fingerprint: $file does not exist"
        return 1
    fi

    { grep '^[+-]' "$file" || true; } | \
        { grep -v '^[+-][+-][+-]' || true; } | \
        shasum -a 256 | cut -d' ' -f1
}

# --- Sentinel utilities ---
# Format must remain compatible with workflow gate job regex:
#   grep -o '<!-- renovate-eval-skill:{[^}]*}'

build_sentinel_comment() {
    # Args: label confidence rounds ci_status eval_count fingerprint [version]
    local label="$1" confidence="$2" rounds="$3" ci_status="$4"
    local eval_count="$5" fingerprint="$6" version="${7:-3}"
    echo "<!-- renovate-eval-skill:{\"version\":$version,\"label\":\"$label\",\"confidence\":\"$confidence\",\"rounds\":$rounds,\"ci_status\":\"$ci_status\",\"eval_count\":$eval_count,\"fingerprint\":\"$fingerprint\"} -->"
}

parse_sentinel_json() {
    # Reads sentinel comment from stdin or first arg, extracts JSON object
    local input="${1:-$(cat)}"
    echo "$input" | \
        grep -o '<!-- renovate-eval-skill:{[^}]*}' | \
        sed 's/<!-- renovate-eval-skill://'
}
