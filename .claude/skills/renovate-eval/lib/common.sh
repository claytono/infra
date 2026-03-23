#!/usr/bin/env bash
# Shared library for renovate-eval scripts
# Source this file; do not execute directly.
#
# IMPORTANT: All output goes to stderr. This library must NEVER write to
# stdout, as some callers pipe stdout to claude -p via heredoc.

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
        if gh api /user &>/dev/null; then
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
