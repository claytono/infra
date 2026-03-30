"""Build and run the evaluator via claude -p."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


def _read_file(path: str) -> str:
    """Read file contents, return empty string if missing."""
    try:
        return Path(path).read_text()
    except FileNotFoundError:
        return ""


def build_round_one_prompt(
    *,
    script_dir: str,
    artifact_dir: str,
    repo_root: str,
    context: str,
    instructions: str = "",
) -> str:
    """Build the evaluator prompt for round 1."""
    evaluator_md = _read_file(os.path.join(script_dir, "prompts", "evaluator.md"))

    repo_context_file = os.path.join(repo_root, ".claude", "renovate-eval.md")
    repo_context_line = ""
    if os.path.isfile(repo_context_file):
        repo_context_line = f"- **Repo context:** {repo_context_file}"

    instructions_block = ""
    if instructions:
        instructions_block = f"""
## Additional Instructions from User

{instructions}"""

    return f"""{evaluator_md}

---

## Context Mode

You are running in **{context}** mode.

## Data Files

Read these files for your research:
- **PR data:** {artifact_dir}/pr-data.md (metadata, file list with change counts — read this first)
- **Full diff:** {artifact_dir}/pr-diff.patch (read selectively based on file list — skip large vendored/generated sections)
- **CI status:** {artifact_dir}/ci-status.md
- **Output schema:** {script_dir}/prompts/eval-data-schema.md
{repo_context_line}
{instructions_block}

## Output Files

Write your evaluation data to: {artifact_dir}/eval-data.json
Write your evidence to: {artifact_dir}/eval-evidence.md
"""


def build_revision_prompt(
    *,
    script_dir: str,
    artifact_dir: str,
    instructions: str = "",
) -> str:
    """Build the revision prompt for round 2+."""
    instructions_block = ""
    if instructions:
        instructions_block = f"""
## Additional Instructions from User

{instructions}"""

    # Check which feedback file exists — validation-feedback.json for validation
    # retries, audit-result.json for auditor feedback
    validation_fb = os.path.join(artifact_dir, "validation-feedback.json")
    audit_fb = os.path.join(artifact_dir, "audit-result.json")
    if os.path.isfile(validation_fb):
        feedback_file = validation_fb
        feedback_source = "validation"
    else:
        feedback_file = audit_fb
        feedback_source = "auditor"

    return f"""The {feedback_source} reviewed your output and found issues. Read the feedback at
{feedback_file} and revise your evaluation data.

Read the revision guidelines at {script_dir}/prompts/revision.md for how
to approach this revision.

Run the validation subcommand after making changes:
python3 {script_dir}/renovate_eval.py validate {artifact_dir}/eval-data.json
{instructions_block}"""


def run_evaluator(
    *,
    round_num: int,
    artifact_dir: str,
    model: str,
    context: str,
    script_dir: str,
    repo_root: str,
    instructions: str = "",
    session_id: str = "",
    is_revision: bool = False,
    cost_suffix: str = "",
) -> dict:
    """Run the evaluator. Returns the parsed claude JSON output.

    is_revision: force revision prompt + --resume even on round 1
    (used for validation retries).
    """
    output_json = os.path.join(artifact_dir, "evaluator-output.json")

    if round_num == 1 and not is_revision:
        prompt = build_round_one_prompt(
            script_dir=script_dir,
            artifact_dir=artifact_dir,
            repo_root=repo_root,
            context=context,
            instructions=instructions,
        )
    else:
        if not session_id:
            raise RuntimeError(
                f"No evaluator session ID for round {round_num} — cannot resume"
            )
        prompt = build_revision_prompt(
            script_dir=script_dir,
            artifact_dir=artifact_dir,
            instructions=instructions,
        )

    cmd = [
        "claude",
        "-p",
        "--model",
        model,
        "--permission-mode",
        "bypassPermissions",
        "--output-format",
        "json",
    ]
    if (round_num > 1 or is_revision) and session_id:
        cmd.extend(["--resume", session_id])

    result = subprocess.run(
        cmd,
        input=prompt,
        capture_output=True,
        text=True,
        timeout=600,
    )

    with open(output_json, "w") as f:
        f.write(result.stdout)

    # #2: check returncode
    if result.returncode != 0:
        raise RuntimeError(
            f"claude exited with code {result.returncode}: "
            f"{result.stderr[:500] if result.stderr else '(no stderr)'}"
        )

    # Extract and log
    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise RuntimeError(
            f"Failed to parse evaluator JSON output: {result.stdout[:200]}"
        )

    if output.get("result"):
        print(output["result"], file=sys.stderr)

    # Save cost info
    suffix = f"r{round_num}{cost_suffix}"
    cost_file = os.path.join(artifact_dir, f"evaluator-cost-{suffix}.json")
    try:
        cost_data = {
            "cost_usd": output.get("total_cost_usd", 0),
            "input_tokens": output.get("usage", {}).get("input_tokens", 0),
            "cache_creation_tokens": output.get("usage", {}).get(
                "cache_creation_input_tokens", 0
            ),
            "cache_read_tokens": output.get("usage", {}).get(
                "cache_read_input_tokens", 0
            ),
            "output_tokens": output.get("usage", {}).get("output_tokens", 0),
        }
        with open(cost_file, "w") as f:
            json.dump(cost_data, f, indent=2)
    except Exception:
        pass

    return output
