"""Fetch all PR data for Renovate PR evaluation."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

from .common import run_diff


def fetch_metadata(pr_number: int | str) -> str:
    """Fetch PR metadata, return markdown."""
    lines = ["## Metadata"]
    result = subprocess.run(
        [
            "gh",
            "pr",
            "view",
            str(pr_number),
            "--json",
            "number,title,author,state,url,baseRefName,headRefName,"
            "additions,deletions,changedFiles",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        lines.append("ERROR: Failed to fetch PR metadata")
        lines.append(f"  {result.stderr.strip()}")
    else:
        data = json.loads(result.stdout)
        lines.append(f"- Number: {data['number']}")
        lines.append(f"- Title: {data['title']}")
        lines.append(f"- Author: {data['author']['login']}")
        lines.append(f"- State: {data['state']}")
        lines.append(f"- URL: {data['url']}")
        lines.append(f"- Branch: {data['headRefName']} \u2190 {data['baseRefName']}")
        lines.append(
            f"- Changes: +{data['additions']} -{data['deletions']} "
            f"across {data['changedFiles']} files"
        )
    lines.append("")
    return "\n".join(lines)


def fetch_body(pr_number: int | str) -> str:
    """Fetch PR body, strip HTML comments."""
    lines = ["## PR Body"]
    result = subprocess.run(
        ["gh", "pr", "view", str(pr_number), "--json", "body", "-q", ".body"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        lines.append("ERROR: Failed to fetch PR body")
        lines.append(f"  {result.stderr.strip()}")
    else:
        body = re.sub(r"<!--.*?-->", "", result.stdout, flags=re.DOTALL)
        for line in body.splitlines():
            if line.strip():
                lines.append(line)
    lines.append("")
    return "\n".join(lines)


def fetch_files(pr_number: int | str, diff_path: str) -> str:
    """Fetch file list with diff line offsets."""
    # Build offset map from the diff
    diff_offsets: dict[str, int] = {}
    if os.path.isfile(diff_path):
        with open(diff_path, "rb") as f:
            for line_num, line in enumerate(f, 1):
                if line.startswith(b"diff --git "):
                    # Extract b/ path
                    try:
                        text_line = line.decode("utf-8", errors="replace")
                    except Exception:
                        continue
                    match = re.search(r" b/(.+)$", text_line)
                    if match:
                        diff_offsets[match.group(1)] = line_num

    lines = ["## Files Changed"]
    result = subprocess.run(
        ["gh", "pr", "view", str(pr_number), "--json", "files"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        lines.append("ERROR: Failed to fetch files data")
        lines.append(f"  {result.stderr.strip()}")
    else:
        data = json.loads(result.stdout)
        files = data.get("files", [])
        lines.append(f"Total: {len(files)} files")
        lines.append("")
        for f in files:
            fpath = f["path"]
            adds = f["additions"]
            dels = f["deletions"]
            offset = diff_offsets.get(fpath)
            if offset:
                lines.append(f"- {fpath} (+{adds}/-{dels}) [L{offset}]")
            else:
                lines.append(f"- {fpath} (+{adds}/-{dels})")
    lines.append("")
    return "\n".join(lines)


def fetch_related_issues(pr_number: int | str, repo: str) -> str:
    """Fetch linked issues and cross-references."""
    lines = ["## Related Issues"]

    # Closing issues
    result = subprocess.run(
        [
            "gh",
            "pr",
            "view",
            str(pr_number),
            "--json",
            "closingIssuesReferences",
            "-q",
            ".closingIssuesReferences[].number",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    linked_issues = result.stdout.strip().split("\n") if result.stdout.strip() else []

    if linked_issues and linked_issues[0]:
        lines.append("### Issues Closed by This PR")
        for issue_num in linked_issues:
            issue_result = subprocess.run(
                [
                    "gh",
                    "issue",
                    "view",
                    issue_num,
                    "--json",
                    "number,title,body,state",
                ],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if issue_result.returncode == 0:
                idata = json.loads(issue_result.stdout)
                lines.append("")
                lines.append(f"**Issue #{issue_num}:** {idata['title']}")
                lines.append(f"- State: {idata['state']}")
                lines.append("- Body:")
                body = idata.get("body") or "No body"
                for bline in body.splitlines():
                    lines.append(f"  {bline}")
        lines.append("")

    # Cross-references
    try:
        xref_result = subprocess.run(
            [
                "gh",
                "api",
                f"repos/{repo}/issues/{pr_number}/timeline",
                "--paginate",
                "--slurp",
                "-q",
                '[.[][] | select(.event == "cross-referenced") | .source.issue | '
                '{number, title, state, type: (if .pull_request then "PR" else "Issue" end)}]'
                " | unique_by(.number)",
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        cross_refs = (
            json.loads(xref_result.stdout) if xref_result.stdout.strip() else []
        )
    except (json.JSONDecodeError, subprocess.TimeoutExpired):
        cross_refs = []

    if cross_refs:
        lines.append("### Cross-References (issues/PRs mentioning this PR)")
        for xref in cross_refs:
            lines.append(
                f"- {xref['type']} #{xref['number']}: {xref['title']} [{xref['state']}]"
            )
        lines.append("")
        # Fetch full body for cross-referencing issues (not PRs)
        for xref in cross_refs:
            if xref["type"] == "Issue":
                ibody_result = subprocess.run(
                    [
                        "gh",
                        "issue",
                        "view",
                        str(xref["number"]),
                        "--json",
                        "body",
                        "-q",
                        '.body // "No body"',
                    ],
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                body = ibody_result.stdout.strip()
                if body and body != "No body":
                    lines.append(f"**Issue #{xref['number']} body:**")
                    for bline in body.splitlines():
                        lines.append(f"  {bline}")
                    lines.append("")

    has_linked = linked_issues and linked_issues[0]
    if not has_linked and not cross_refs:
        lines.append("No linked or referencing issues found.")
        lines.append("")

    return "\n".join(lines)


def detect_repo() -> str:
    """Detect the GitHub repo (owner/name)."""
    result = subprocess.run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise SystemExit("ERROR: Not in a git repository with GitHub remote")
    return result.stdout.strip()


def fetch_pr_data(pr_number: int | str, output_dir: str) -> None:
    """Fetch all PR data to output_dir. Writes pr-data.md and pr-diff.patch."""
    repo = detect_repo()
    diff_path = os.path.join(output_dir, "pr-diff.patch")

    # Write diff first (fetch_files needs it for line offsets)
    run_diff(pr_number, diff_path)

    pr_data_path = os.path.join(output_dir, "pr-data.md")
    with open(pr_data_path, "w") as f:
        f.write(fetch_metadata(pr_number))
        f.write(fetch_body(pr_number))
        f.write(fetch_files(pr_number, diff_path))
        f.write(fetch_related_issues(pr_number, repo))

    print(f"Wrote {pr_data_path}", file=sys.stderr)
