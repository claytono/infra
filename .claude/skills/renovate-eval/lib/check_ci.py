"""Check CI status for a PR, with optional wait mode."""

from __future__ import annotations

import json
import shutil
import subprocess

from .common import log


def _find_timeout_cmd() -> str | None:
    """Find timeout or gtimeout command."""
    for cmd in ("timeout", "gtimeout"):
        if shutil.which(cmd):
            return cmd
    return None


def check_ci_once(pr_number: int | str) -> tuple[str, int]:
    """Run gh pr checks once and return (output, exit_code)."""
    result = subprocess.run(
        ["gh", "pr", "checks", str(pr_number)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result.stdout + result.stderr, result.returncode


def wait_for_ci(pr_number: int | str, timeout: int = 300) -> tuple[str, int]:
    """Wait for CI checks to complete. Returns (output, exit_code).

    exit_code 0 = all passed, 1 = some failed, 2 = timeout.
    """
    timeout_cmd = _find_timeout_cmd()

    if timeout_cmd:
        cmd = [
            timeout_cmd,
            str(timeout),
            "gh",
            "pr",
            "checks",
            str(pr_number),
            "--watch",
            "--interval",
            "15",
        ]
    else:
        log.warning("timeout command not available, running without timeout")
        cmd = [
            "gh",
            "pr",
            "checks",
            str(pr_number),
            "--watch",
            "--interval",
            "15",
        ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stdout + result.stderr

    if result.returncode == 124:
        # timeout exit code
        return output + f"\nWARNING: CI check timed out after {timeout}s", 2
    return output, result.returncode


def fetch_failed_logs(pr_number: int | str) -> str:
    """Fetch logs for failed CI checks."""
    result = subprocess.run(
        [
            "gh",
            "pr",
            "checks",
            str(pr_number),
            "--json",
            "name,conclusion,detailsUrl",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        return ""

    try:
        checks = json.loads(result.stdout)
    except json.JSONDecodeError:
        return ""

    failed = [c for c in checks if c.get("conclusion") == "FAILURE"]
    if not failed:
        return ""

    lines = ["", "## Failed Check Logs"]
    for check in failed:
        name = check.get("name", "unknown")
        link = check.get("detailsUrl", "")

        # Extract run ID from details URL
        import re

        match = re.search(r"/runs/(\d+)", link)
        if match:
            run_id = match.group(1)
            lines.append("")
            lines.append(f"### {name}")
            lines.append(f"Run: {link}")
            lines.append("```")
            log_result = subprocess.run(
                ["gh", "run", "view", run_id, "--log"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            if log_result.returncode == 0:
                # Last 100 lines
                log_lines = log_result.stdout.splitlines()[-100:]
                lines.extend(log_lines)
            else:
                lines.append("Could not retrieve logs")
            lines.append("```")

    return "\n".join(lines)


def check_ci(
    pr_number: int | str,
    wait: bool = False,
    timeout: int = 300,
    output_file: str | None = None,
) -> int:
    """Check CI status and optionally write to file.

    Returns exit code: 0 = success, 1 = failure, 2 = timeout.
    """
    lines = [f"# CI Status for PR #{pr_number}", ""]

    if wait:
        output, exit_code = wait_for_ci(pr_number, timeout)
        lines.append(output)
    else:
        output, exit_code = check_ci_once(pr_number)
        lines.append(output)

    lines.append(fetch_failed_logs(pr_number))

    content = "\n".join(lines)
    if output_file:
        with open(output_file, "w") as f:
            f.write(content)
    else:
        print(content)

    return exit_code
