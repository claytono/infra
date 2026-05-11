"""Run Claude or Codex and normalize their CLI outputs."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any


VALID_PROVIDERS = ("claude", "codex")
CODEX_MINIMAL_MODE_DISABLED_FEATURES = (
    "shell_tool",
    "apps",
    "browser_use",
    "computer_use",
    "image_generation",
    "in_app_browser",
    "multi_agent",
    "plugins",
    "tool_search",
    "unified_exec",
)


def resolve_provider(provider: str | None = None) -> str:
    """Resolve and validate the requested agent provider."""
    resolved = (
        provider or os.environ.get("RENOVATE_EVAL_PROVIDER") or "claude"
    ).strip()
    if resolved not in VALID_PROVIDERS:
        valid = ", ".join(VALID_PROVIDERS)
        raise ValueError(f"Invalid provider '{resolved}'. Expected one of: {valid}")
    return resolved


def run_agent(
    *,
    provider: str,
    role: str,
    prompt: str,
    artifact_dir: str,
    repo_root: str,
    output_json: str,
    model: str = "",
    reasoning_effort: str = "",
    session_id: str = "",
    resume: bool = False,
    disable_tools: bool = False,
    timeout: int | None = 600,
) -> dict[str, Any]:
    """Run an agent provider and return a normalized output dict."""
    resolved = resolve_provider(provider)
    if resolved == "claude":
        return _run_claude(
            role=role,
            prompt=prompt,
            output_json=output_json,
            model=model,
            session_id=session_id,
            resume=resume,
            disable_tools=disable_tools,
            timeout=timeout,
        )
    return _run_codex(
        role=role,
        prompt=prompt,
        artifact_dir=artifact_dir,
        repo_root=repo_root,
        output_json=output_json,
        model=model,
        reasoning_effort=reasoning_effort,
        session_id=session_id,
        resume=resume,
        disable_tools=disable_tools,
        timeout=timeout,
    )


def _run_claude(
    *,
    role: str,
    prompt: str,
    output_json: str,
    model: str,
    session_id: str,
    resume: bool,
    disable_tools: bool,
    timeout: int | None,
) -> dict[str, Any]:
    if not model:
        raise RuntimeError(f"claude {role} requires a model")

    cmd = [
        "claude",
        "-p",
        "--model",
        model,
        "--permission-mode",
        "bypassPermissions",
    ]
    if disable_tools:
        cmd.extend(["--tools", ""])
    cmd.extend(["--output-format", "json"])
    if resume and session_id:
        cmd.extend(["--resume", session_id])

    result = subprocess.run(
        cmd,
        input=prompt,
        capture_output=True,
        text=True,
        timeout=timeout,
    )

    Path(output_json).write_text(result.stdout)
    if result.returncode != 0:
        raise RuntimeError(
            f"claude exited with code {result.returncode}: "
            f"{result.stderr[:500] if result.stderr else '(no stderr)'}"
        )

    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise RuntimeError(f"Failed to parse {role} JSON output: {result.stdout[:200]}")

    output.setdefault("provider", "claude")
    output.setdefault("raw_stdout", result.stdout)
    return output


def _run_codex(
    *,
    role: str,
    prompt: str,
    artifact_dir: str,
    repo_root: str,
    output_json: str,
    model: str,
    reasoning_effort: str,
    session_id: str,
    resume: bool,
    disable_tools: bool,
    timeout: int | None,
) -> dict[str, Any]:
    last_message = os.path.join(artifact_dir, f"{role}-last-message.md")
    raw_jsonl = os.path.join(artifact_dir, f"{role}-output.jsonl")

    cmd = ["codex", "exec"]
    if disable_tools:
        # Codex has no Claude-equivalent no-tools mode. This is best-effort
        # minimal/no-shell mode using the strongest currently supported flags.
        cmd.extend(
            [
                "--sandbox",
                "read-only",
                "--ignore-user-config",
                "--ignore-rules",
                "-c",
                "mcp_servers={}",
            ]
        )
        for feature in CODEX_MINIMAL_MODE_DISABLED_FEATURES:
            cmd.extend(["--disable", feature])
    else:
        cmd.append("--dangerously-bypass-approvals-and-sandbox")

    cmd.extend(
        [
            "--cd",
            repo_root,
            "--json",
            "--output-last-message",
            last_message,
        ]
    )
    if model:
        cmd.extend(["-m", model])
    if reasoning_effort:
        cmd.extend(
            [
                "-c",
                f"model_reasoning_effort={json.dumps(reasoning_effort)}",
            ]
        )
    if resume and not session_id:
        raise RuntimeError(f"codex {role} resume requires a session ID")
    if resume:
        cmd.extend(["resume", session_id, "-"])
    else:
        cmd.append("-")

    result = subprocess.run(
        cmd,
        input=prompt,
        capture_output=True,
        text=True,
        timeout=timeout,
    )

    Path(raw_jsonl).write_text(result.stdout)
    if result.returncode != 0:
        raise RuntimeError(
            f"codex exited with code {result.returncode}: "
            f"{result.stderr[:500] if result.stderr else '(no stderr)'}"
        )

    result_text = Path(last_message).read_text() if os.path.isfile(last_message) else ""
    output = {
        "provider": "codex",
        "result": result_text,
        "session_id": parse_codex_session_id(result.stdout),
        "total_cost_usd": 0,
        "usage": parse_codex_usage(result.stdout),
        "raw_stdout": result.stdout,
        "raw_jsonl_path": raw_jsonl,
    }
    Path(output_json).write_text(json.dumps(output, indent=2))
    return output


def parse_codex_session_id(raw_jsonl: str) -> str:
    """Extract the Codex thread id from JSONL events."""
    for line in raw_jsonl.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") == "thread.started":
            thread_id = event.get("thread_id", "")
            return thread_id if isinstance(thread_id, str) else ""
    return ""


def parse_codex_usage(raw_jsonl: str) -> dict[str, int]:
    """Extract and normalize token usage from Codex JSONL events."""
    usage: dict[str, int] = {}
    for line in raw_jsonl.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") != "turn.completed":
            continue
        event_usage = event.get("usage", {})
        if not isinstance(event_usage, dict):
            continue
        for key, value in event_usage.items():
            if isinstance(value, bool) or not isinstance(value, int):
                continue
            usage[key] = usage.get(key, 0) + value

    if "cached_input_tokens" in usage:
        usage.setdefault("cache_read_input_tokens", usage["cached_input_tokens"])
    if "total_tokens" not in usage and (
        "input_tokens" in usage or "output_tokens" in usage
    ):
        usage["total_tokens"] = usage.get("input_tokens", 0) + usage.get(
            "output_tokens", 0
        )
    return usage
