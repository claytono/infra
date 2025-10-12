#!/usr/bin/env python3
"""
Analyze Helm Chart.yaml changes using OpenAI's API.

This script analyzes Chart.yaml and rendered Helm template changes to determine
if they are routine (metadata/version updates) or significant (functional changes).

Can be run in GitHub Actions or standalone for testing.
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error
from typing import Optional


def exponential_backoff_retry(
    func, max_attempts: int = 5, base_wait: int = 10, max_wait: int = 300
):
    """
    Retry a function with exponential backoff.

    Args:
        func: Function to retry
        max_attempts: Maximum number of retry attempts
        base_wait: Base wait time in seconds
        max_wait: Maximum wait time in seconds

    Returns:
        Result from successful function call

    Raises:
        Last exception if all retries fail
    """
    for attempt in range(max_attempts):
        try:
            return func()
        except Exception as e:
            if attempt == max_attempts - 1:
                raise

            wait_time = min(base_wait * (2**attempt), max_wait)
            print(
                f"Attempt {attempt + 1} failed: {e}",
                file=sys.stderr,
            )
            print(f"Retrying in {wait_time} seconds...", file=sys.stderr)
            time.sleep(wait_time)


def get_chart_diffs(pr_number: Optional[int] = None) -> str:
    """
    Get diffs for Chart.yaml files and corresponding helm/ directories.

    Args:
        pr_number: PR number to get diffs for (optional, for standalone mode)

    Returns:
        Formatted diff content with Chart.yaml and helm/ changes
    """
    # Get full diff using gh pr diff
    cmd = ["gh", "pr", "diff"]
    if pr_number:
        cmd.append(str(pr_number))

    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        check=True,
    )

    full_diff = result.stdout

    # Parse the diff to extract Chart.yaml and helm/ changes
    diff_content = "# Chart.yaml Changes\n\n"

    lines = full_diff.splitlines()
    i = 0
    chart_files = []
    helm_sections = []

    while i < len(lines):
        line = lines[i]

        # Look for diff headers for Chart.yaml files
        if line.startswith("diff --git") and "Chart.yaml" in line:
            # Extract filename
            parts = line.split()
            filename = parts[2].replace("a/", "")
            chart_files.append(filename)

            # Collect this diff section
            diff_section = []
            i += 1
            while i < len(lines) and not lines[i].startswith("diff --git"):
                diff_section.append(lines[i])
                i += 1

            diff_content += f"## {filename}\n\n"
            diff_content += "```diff\n"
            diff_content += "\n".join(diff_section)
            diff_content += "\n```\n\n"
            continue

        # Look for diff headers for helm/ directories
        elif line.startswith("diff --git") and "/helm/" in line:
            # Collect helm diff sections
            helm_section = [line]
            i += 1
            while i < len(lines) and not lines[i].startswith("diff --git"):
                helm_section.append(lines[i])
                i += 1
            helm_sections.append(helm_section)
            continue

        i += 1

    # Add helm template changes summary
    if helm_sections:
        diff_content += "\n# Rendered Helm Template Changes\n\n"
        diff_content += (
            f"### Summary: {len(helm_sections)} template file(s) changed\n\n"
        )

        # Show first 100 lines of helm changes as sample
        diff_content += "### Sample of template diffs (first 100 lines):\n"
        diff_content += "```diff\n"

        all_helm_lines = []
        for section in helm_sections:
            all_helm_lines.extend(section)

        sample_lines = all_helm_lines[:100]
        diff_content += "\n".join(sample_lines)
        diff_content += "\n```\n\n"

    return diff_content


def get_openai_api_key() -> str:
    """
    Get OpenAI API key from environment variable or 1Password.

    Returns:
        OpenAI API key

    Raises:
        ValueError: If API key cannot be found
    """
    # Try environment variable first
    api_key = os.environ.get("OPENAI_API_KEY")
    if api_key:
        return api_key

    # Try 1Password CLI if available
    try:
        result = subprocess.run(
            ["op", "read", "op://infra/openai-github-actions/password"],
            capture_output=True,
            text=True,
            check=True,
        )
        api_key = result.stdout.strip()
        if api_key:
            return api_key
    except (subprocess.CalledProcessError, FileNotFoundError):
        # op command not available or failed
        pass

    raise ValueError(
        "OPENAI_API_KEY not found. Set OPENAI_API_KEY environment variable or "
        "ensure 'op' CLI is installed and configured with access to "
        "op://infra/openai-github-actions/password"
    )


def call_openai_api(prompt: str, api_key: str, model: str = "gpt-5") -> str:
    """
    Call OpenAI API with the given prompt.

    Args:
        prompt: The prompt to send to the AI
        api_key: OpenAI API key
        model: The model to use (default: gpt-5)

    Returns:
        AI response content

    Raises:
        urllib.error.HTTPError: If API call fails
        KeyError: If response format is unexpected
    """
    url = "https://api.openai.com/v1/chat/completions"

    data = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
    }

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode("utf-8"),
        headers=headers,
        method="POST",
    )

    try:
        with urllib.request.urlopen(req) as response:
            response_data = json.loads(response.read().decode("utf-8"))
            return response_data["choices"][0]["message"]["content"]
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8")
        raise Exception(f"OpenAI API error (HTTP {e.code}): {error_body}")


def analyze_changes(diff_content: str, api_key: str, model: str = "gpt-5") -> str:
    """
    Analyze chart changes using OpenAI API.

    Args:
        diff_content: The diff content to analyze
        api_key: OpenAI API key
        model: The model to use (default: gpt-5)

    Returns:
        AI analysis response
    """
    prompt = f"""You are analyzing Helm Chart changes from a Renovate dependency update pull request.

This repository uses a GitOps approach where Helm charts are pre-rendered into static YAML
manifests stored in helm/ directories. When Chart.yaml is updated (usually a version bump),
the render script regenerates all the templates in helm/, which can result in many file changes.

Your task is to determine if the changes are:
1. **ROUTINE** - Only version/hash updates in Chart.yaml, and the helm/ template changes are
   only metadata updates (labels, annotations, helm chart version references) that don't
   change the actual deployed resources or configuration.
2. **SIGNIFICANT** - Changes that affect what gets deployed, including:
   - Image tag changes (new versions of deployed applications)
   - New dependencies or removed dependencies
   - Changes to repository URLs
   - Structural changes to deployed resources
   - New or removed Kubernetes resources
   - Changes to resource configurations (replicas, limits, etc.)
   - Breaking changes or deprecations
   - Security-relevant changes

Respond EXACTLY in this format (include the emoji but minimal markdown):

🟢 ROUTINE

[1-2 sentences describing what changed]

OR

🔴 SIGNIFICANT

[Brief intro sentence, then list the key changes as bullet points with details]
- Change 1: [describe what changed and why it matters]
- Change 2: [describe what changed and why it matters]
- etc.

IMPORTANT: Do not use bold (**), italics (*), headers (#), or code blocks in your response.
For ROUTINE changes: 1-2 sentence plain text description.
For SIGNIFICANT changes: intro sentence + detailed bullet points explaining what changed and impact.

---

Here are the changes to review:

{diff_content}
"""

    def api_call():
        return call_openai_api(prompt, api_key, model)

    return exponential_backoff_retry(api_call)


def main():
    parser = argparse.ArgumentParser(
        description="Analyze Helm Chart.yaml changes with AI"
    )
    parser.add_argument(
        "--pr",
        type=int,
        help="PR number to analyze (for standalone testing)",
    )
    parser.add_argument(
        "--model",
        default="gpt-5",
        help="AI model to use (default: gpt-5)",
    )
    parser.add_argument(
        "--output-file",
        help="Output file for GitHub Actions (defaults to GITHUB_OUTPUT env var)",
    )

    args = parser.parse_args()

    # Get OpenAI API key
    print("Getting OpenAI API key...", file=sys.stderr)
    api_key = get_openai_api_key()

    # Get diffs
    print("Collecting Chart.yaml and helm/ changes...", file=sys.stderr)
    diff_content = get_chart_diffs(args.pr)

    if (
        not diff_content.strip()
        or diff_content.strip()
        == "# Chart.yaml Changes\n\n\n# Rendered Helm Template Changes"
    ):
        print("No Chart.yaml changes found", file=sys.stderr)
        sys.exit(0)

    # Analyze changes
    print("Analyzing changes with AI...", file=sys.stderr)
    response = analyze_changes(diff_content, api_key, args.model)

    # Output results
    output_file = args.output_file or os.environ.get("GITHUB_OUTPUT")

    if output_file:
        # GitHub Actions output format
        with open(output_file, "a") as f:
            f.write("response<<EOF\n")
            f.write(response)
            f.write("\nEOF\n")
            f.write("diff-content<<EOF\n")
            f.write(diff_content)
            f.write("\nEOF\n")
        print("Analysis complete. Results written to output file.", file=sys.stderr)
    else:
        # Standalone output
        print("\n=== AI Analysis ===\n")
        print(response)

        # Only print diff for ROUTINE changes
        if "ROUTINE" in response:
            print("\n=== Diff Content ===\n")
            print(diff_content)


if __name__ == "__main__":
    main()
