"""Quick PR status: live CI + existing evaluation."""

from __future__ import annotations

import subprocess

from .common import extract_eval_data, get_ci_status, log, parse_sentinel
from .render import render_report


def get_existing_eval_comment(pr_number: int | str) -> str | None:
    """Fetch the latest renovate-eval sentinel comment body from PR."""
    result = subprocess.run(
        [
            "gh",
            "pr",
            "view",
            str(pr_number),
            "--json",
            "comments",
            "--jq",
            '.comments | map(select(.body | contains("<!-- renovate-eval-skill:"))) '
            "| sort_by(.createdAt) | last | .body",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    body = result.stdout.strip()
    return body if body and body != "null" else None


def pr_status(pr_number: int | str) -> str:
    """Get PR status: live CI + existing eval, re-rendered with live CI."""
    ci_status = get_ci_status(pr_number)

    comment_body = get_existing_eval_comment(pr_number)
    if not comment_body:
        return f"CI_STATUS: {ci_status}"

    # Check if it's a v4 comment
    sentinel = parse_sentinel(comment_body)
    if not sentinel:
        # Not v4 — treat as no evaluation
        return f"CI_STATUS: {ci_status}"

    # Extract embedded JSON and re-render with live CI
    eval_data = extract_eval_data(comment_body)
    if not eval_data:
        return f"CI_STATUS: {ci_status}"

    # Validate before rendering
    from .validate import validate_eval_data

    errors = validate_eval_data(eval_data)
    if errors:
        log.error("Embedded eval-data failed validation: %s", "; ".join(errors))
        return f"CI_STATUS: {ci_status}"

    # Re-render with live CI status
    try:
        report = render_report(eval_data, ci_status=ci_status)
    except (KeyError, TypeError) as e:
        log.error("Failed to render embedded eval-data: %s", e)
        return f"CI_STATUS: {ci_status}"
    return report
