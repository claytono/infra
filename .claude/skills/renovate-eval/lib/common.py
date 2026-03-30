"""Shared constants and utilities for renovate-eval."""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import os
import re
import subprocess
import sys
from typing import Any

log = logging.getLogger("renovate-eval")

# --- Constants ---

SENTINEL_VERSION = 4

VALID_LABELS = [
    "renovate:safe",
    "renovate:caution",
    "renovate:breaking",
    "renovate:risk",
]

VALID_CI_STATUS = ["passing", "failing", "pending", "unknown"]

LABEL_EMOJI = {
    "renovate:safe": "\U0001f7e2",  # green circle
    "renovate:caution": "\U0001f7e1",  # yellow circle
    "renovate:breaking": "\U0001f7e0",  # orange circle
    "renovate:risk": "\U0001f534",  # red circle
}

LABEL_SHORT = {
    "renovate:safe": "Safe",
    "renovate:caution": "Caution",
    "renovate:breaking": "Breaking",
    "renovate:risk": "Risk",
}

LABEL_COLORS = {
    "renovate:safe": "0e8a16",
    "renovate:caution": "fbca04",
    "renovate:breaking": "e99d42",
    "renovate:risk": "d93f0b",
    "renovate:evaluated": "0075ca",
}

VALID_PACKAGE_TYPES = [
    "docker",
    "helm",
    "ansible",
    "terraform",
    "pre-commit",
    "github-action",
    "dependency",
]


# --- Logging ---


def setup_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    if not log.handlers:
        handler = logging.StreamHandler(sys.stderr)
        handler.setFormatter(logging.Formatter("%(levelname)s: %(message)s"))
        log.addHandler(handler)
    log.setLevel(level)


# --- Auth verification ---


def require_gh_auth() -> None:
    """Verify GitHub CLI authentication, matching bash require_gh_auth."""
    gh_token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if gh_token:
        result = subprocess.run(
            ["gh", "repo", "view"],
            capture_output=True,
            timeout=30,
        )
        if result.returncode != 0:
            raise SystemExit(
                "ERROR: GH_TOKEN/GITHUB_TOKEN is set but invalid or lacks required scopes"
            )
        return
    result = subprocess.run(
        ["gh", "auth", "status"],
        capture_output=True,
        timeout=30,
    )
    if result.returncode != 0:
        raise SystemExit(
            "ERROR: Not authenticated with GitHub. "
            "Run 'gh auth login' or set GH_TOKEN/GITHUB_TOKEN"
        )


def require_tools(*tools: str) -> None:
    """Check that all required CLI tools are available."""
    import shutil

    missing = [t for t in tools if shutil.which(t) is None]
    if missing:
        raise SystemExit(f"ERROR: Missing required tools: {' '.join(missing)}")


# --- Sentinel ---


def build_sentinel(
    label: str,
    rounds: int,
    ci_status: str,
    eval_count: int,
    fingerprint: str,
) -> str:
    """Build a v4 sentinel HTML comment."""
    payload = {
        "version": SENTINEL_VERSION,
        "label": label,
        "rounds": rounds,
        "ci_status": ci_status,
        "eval_count": eval_count,
        "fingerprint": fingerprint,
    }
    return f"<!-- renovate-eval-skill:{json.dumps(payload, separators=(',', ':'))} -->"


def parse_sentinel(comment_body: str) -> dict[str, Any] | None:
    """Extract sentinel JSON from a comment body. Returns None if not v4."""
    match = re.search(r"<!-- renovate-eval-skill:\{([^}]*)\}", comment_body)
    if not match:
        return None
    try:
        data = json.loads("{" + match.group(1) + "}")
    except json.JSONDecodeError:
        return None
    if data.get("version") != SENTINEL_VERSION:
        return None
    return data


# --- Embedded eval-data ---


def embed_eval_data(eval_data: dict[str, Any]) -> str:
    """Encode eval-data dict as a base64 HTML comment block."""
    encoded = base64.b64encode(
        json.dumps(eval_data, separators=(",", ":")).encode()
    ).decode()
    return f"<!-- renovate-eval-data\n{encoded}\n-->"


def extract_eval_data(comment_body: str) -> dict[str, Any] | None:
    """Extract eval-data dict from a base64-encoded HTML comment block."""
    match = re.search(
        r"<!-- renovate-eval-data\r?\n([A-Za-z0-9+/=\r\n]+)\r?\n-->", comment_body
    )
    if not match:
        return None
    try:
        decoded = base64.b64decode(match.group(1).replace("\n", "")).decode()
        return json.loads(decoded)
    except (json.JSONDecodeError, Exception):
        return None


# --- CI status ---


def get_ci_status(pr_number: int | str) -> str:
    """Get CI status for a PR. Returns passing/failing/pending/unknown."""
    try:
        result = subprocess.run(
            ["gh", "pr", "checks", str(pr_number), "--json", "name,bucket"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            return "unknown"
        checks = json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError):
        return "unknown"

    if not checks:
        return "unknown"

    has_pending = False
    for check in checks:
        bucket = check.get("bucket", "")
        if bucket in ("fail", "cancel"):
            return "failing"
        if bucket not in ("pass", "skipping"):
            has_pending = True

    return "pending" if has_pending else "passing"


# --- Fingerprint ---


def compute_fingerprint(diff_path: str) -> str:
    """Compute SHA-256 fingerprint of added/removed diff lines."""
    if not os.path.isfile(diff_path):
        raise FileNotFoundError(
            f"Cannot compute fingerprint: {diff_path} does not exist"
        )

    h = hashlib.sha256()
    with open(diff_path, "rb") as f:
        for line in f:
            if line.startswith((b"+", b"-")) and not line.startswith((b"+++", b"---")):
                h.update(line)
    return h.hexdigest()


# --- Diff utility ---


def run_diff(pr_number: int | str, output_file: str) -> None:
    """Write PR diff to output_file. Tries gh pr diff, falls back to git."""
    result = subprocess.run(
        ["gh", "pr", "diff", str(pr_number)],
        capture_output=True,
        timeout=120,
    )
    if result.returncode == 0:
        with open(output_file, "wb") as f:
            f.write(result.stdout)
        return

    log.warning("gh pr diff failed, falling back to local git diff")
    # Get base and head refs
    base_ref = subprocess.run(
        [
            "gh",
            "pr",
            "view",
            str(pr_number),
            "--json",
            "baseRefName",
            "-q",
            ".baseRefName",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout.strip()
    head_ref = subprocess.run(
        [
            "gh",
            "pr",
            "view",
            str(pr_number),
            "--json",
            "headRefName",
            "-q",
            ".headRefName",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout.strip()

    subprocess.run(
        ["git", "remote", "update"], check=True, capture_output=True, timeout=120
    )
    result = subprocess.run(
        ["git", "diff", "--no-ext-diff", f"origin/{base_ref}...origin/{head_ref}"],
        capture_output=True,
        timeout=120,
    )
    if result.returncode != 0:
        raise RuntimeError(f"git diff failed for origin/{base_ref}...origin/{head_ref}")
    with open(output_file, "wb") as f:
        f.write(result.stdout)
