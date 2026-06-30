"""Build and run the auditor through the selected agent provider."""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

from .agent_runner import run_agent
from .common import log
from .evaluator import (
    INITIAL_SUPERPOWERS_RESEARCH_BLOCK,
    TARGETED_REVISION_SUPERPOWERS_BLOCK,
)


def _read_file(path: str) -> str:
    """Read file contents, return empty string if missing."""
    try:
        return Path(path).read_text()
    except FileNotFoundError:
        return ""


def _strip_output_section(evaluator_md: str) -> str:
    """Strip the Output section from evaluator.md, keeping research methodology.

    Tracks code fence state so headings inside fenced blocks are ignored.
    """
    lines = evaluator_md.splitlines()
    result = []
    in_output = False
    in_fence = False
    for line in lines:
        # Track code fence state
        if line.startswith("```"):
            in_fence = not in_fence

        if not in_fence and re.match(r"^## Output\b", line):
            in_output = True
            continue
        if in_output and not in_fence and re.match(r"^## ", line):
            in_output = False
        if not in_output:
            result.append(line)
    return "\n".join(result)


def build_round_one_prompt(
    *,
    script_dir: str,
    artifact_dir: str,
    report: str,
    evidence: str,
    yolo: bool = False,
) -> str:
    """Build the auditor prompt for round 1."""
    auditor_md = _read_file(os.path.join(script_dir, "prompts", "auditor.md"))
    evaluator_md = _read_file(os.path.join(script_dir, "prompts", "evaluator.md"))
    report_format_md = _read_file(
        os.path.join(script_dir, "prompts", "report-format.md")
    )

    # Split auditor.md at --- separator: preamble above, instructions below
    parts = auditor_md.split("\n---\n", 1)
    preamble = parts[0] if parts else auditor_md
    audit_instructions = parts[1] if len(parts) > 1 else ""

    # Strip Output section from evaluator.md for the rubric
    evaluator_rubric = _strip_output_section(evaluator_md)
    runtime_requirements = "\n\n".join(
        (
            INITIAL_SUPERPOWERS_RESEARCH_BLOCK.strip(),
            TARGETED_REVISION_SUPERPOWERS_BLOCK.strip(),
        )
    )

    return f"""{preamble}

## Evaluator Rubric

The evaluator was given the following instructions. This is the authoritative
reference for what rules the evaluator should have followed.

Evaluator yolo mode was {"enabled" if yolo else "disabled"} for this run.

{evaluator_rubric}

{runtime_requirements}

---

## Report Format Specification

The evaluator was told to follow this report format.

{report_format_md}

---

## Report to Audit

{report}

---

## Evaluator Evidence

{evidence}

---

## Audit Instructions

{audit_instructions}"""


def build_revision_prompt(
    *,
    round_num: int,
    report: str,
    evidence: str,
) -> str:
    """Build the auditor revision prompt for round 2+."""
    return f"""The evaluator has revised the report based on your feedback. Review the
revised report and evidence below. Check whether your previous issues
have been adequately addressed. Apply the same audit criteria.

## Current Round

{round_num}

## Revised Report

{report}

## Updated Evidence

{evidence}"""


def run_auditor(
    *,
    round_num: int,
    artifact_dir: str,
    model: str,
    script_dir: str,
    repo_root: str = "",
    provider: str = "claude",
    reasoning_effort: str = "",
    session_id: str = "",
    yolo: bool = False,
    timeout: int | None = 300,
) -> dict:
    """Run the auditor. Returns the parsed audit result."""
    report = _read_file(os.path.join(artifact_dir, "eval-report.md"))
    evidence = _read_file(os.path.join(artifact_dir, "eval-evidence.md"))
    if not evidence:
        evidence = "No evidence file provided."

    output_json = os.path.join(artifact_dir, "auditor-output.json")

    if round_num == 1:
        prompt = build_round_one_prompt(
            script_dir=script_dir,
            artifact_dir=artifact_dir,
            report=report,
            evidence=evidence,
            yolo=yolo,
        )
    else:
        if not session_id:
            raise RuntimeError(
                f"No auditor session ID for round {round_num} — cannot resume"
            )
        prompt = build_revision_prompt(
            round_num=round_num,
            report=report,
            evidence=evidence,
        )

    output = run_agent(
        provider=provider,
        role="auditor",
        prompt=prompt,
        artifact_dir=artifact_dir,
        repo_root=repo_root,
        output_json=output_json,
        model=model,
        reasoning_effort=reasoning_effort,
        session_id=session_id,
        resume=round_num > 1,
        disable_tools=True,
        yolo=yolo,
        timeout=timeout,
    )

    # Extract result text and parse JSON from sentinels
    raw_text = output.get("result", "")
    raw_log = os.path.join(artifact_dir, "auditor-raw.log")
    with open(raw_log, "w") as f:
        f.write(raw_text)

    # Extract JSON between ---JSON_START--- / ---JSON_END---
    audit_result = {}
    match = re.search(r"---JSON_START---\s*(.*?)\s*---JSON_END---", raw_text, re.DOTALL)
    if match:
        try:
            audit_result = json.loads(match.group(1))
        except json.JSONDecodeError:
            log.error("Failed to parse audit result JSON")

    audit_result_path = os.path.join(artifact_dir, "audit-result.json")
    with open(audit_result_path, "w") as f:
        json.dump(audit_result, f, indent=2)

    # Save cost info
    cost_file = os.path.join(artifact_dir, f"auditor-cost-r{round_num}.json")
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

    return audit_result
