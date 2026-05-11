"""Tests for lib/agent_runner.py."""

from __future__ import annotations

import json
import os
import subprocess

import pytest

from lib.agent_runner import (
    CODEX_MINIMAL_MODE_DISABLED_FEATURES,
    parse_codex_session_id,
    parse_codex_usage,
    resolve_provider,
    run_agent,
)


def test_resolve_provider_default(monkeypatch):
    monkeypatch.delenv("RENOVATE_EVAL_PROVIDER", raising=False)
    assert resolve_provider() == "claude"


def test_resolve_provider_env(monkeypatch):
    monkeypatch.setenv("RENOVATE_EVAL_PROVIDER", "codex")
    assert resolve_provider() == "codex"


def test_resolve_provider_rejects_invalid():
    with pytest.raises(ValueError, match="Invalid provider"):
        resolve_provider("bad")


def test_parse_codex_session_id():
    raw = "\n".join(
        [
            json.dumps({"type": "thread.started", "thread_id": "thread-123"}),
            json.dumps({"type": "turn.started"}),
        ]
    )
    assert parse_codex_session_id(raw) == "thread-123"


def test_parse_codex_session_id_ignores_bad_lines():
    raw = "not json\n" + json.dumps({"type": "turn.started"})
    assert parse_codex_session_id(raw) == ""


def test_parse_codex_usage_normalizes_cached_tokens():
    raw = "\n".join(
        [
            "not json",
            json.dumps(
                {
                    "type": "turn.completed",
                    "usage": {
                        "input_tokens": 100,
                        "cached_input_tokens": 25,
                        "output_tokens": 10,
                        "reasoning_output_tokens": 4,
                    },
                }
            ),
            json.dumps(
                {
                    "type": "turn.completed",
                    "usage": {
                        "input_tokens": 50,
                        "cached_input_tokens": 5,
                        "output_tokens": 7,
                        "ignored_float": 1.5,
                    },
                }
            ),
        ]
    )

    assert parse_codex_usage(raw) == {
        "input_tokens": 150,
        "cached_input_tokens": 30,
        "output_tokens": 17,
        "reasoning_output_tokens": 4,
        "cache_read_input_tokens": 30,
        "total_tokens": 167,
    }


def test_run_claude_writes_output(monkeypatch, tmp_dir):
    output = {"session_id": "abc", "result": "ok", "usage": {}}
    called = {}

    def mock_run(cmd, **kwargs):
        called["cmd"] = cmd
        called["input"] = kwargs["input"]
        return subprocess.CompletedProcess(cmd, 0, json.dumps(output), "")

    monkeypatch.setattr("lib.agent_runner.subprocess.run", mock_run)
    output_json = os.path.join(tmp_dir, "claude-output.json")

    result = run_agent(
        provider="claude",
        role="evaluator",
        prompt="prompt",
        artifact_dir=tmp_dir,
        repo_root="/repo",
        output_json=output_json,
        model="opus",
    )

    assert called["cmd"][:4] == ["claude", "-p", "--model", "opus"]
    assert called["input"] == "prompt"
    assert result["provider"] == "claude"
    with open(output_json) as f:
        assert json.load(f)["session_id"] == "abc"


def test_run_claude_disable_tools_and_resume(monkeypatch, tmp_dir):
    output = {"session_id": "abc", "result": "ok", "usage": {}}
    called = {}

    def mock_run(cmd, **kwargs):
        called["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0, json.dumps(output), "")

    monkeypatch.setattr("lib.agent_runner.subprocess.run", mock_run)

    run_agent(
        provider="claude",
        role="auditor",
        prompt="prompt",
        artifact_dir=tmp_dir,
        repo_root="/repo",
        output_json=os.path.join(tmp_dir, "claude-output.json"),
        model="sonnet",
        session_id="session-123",
        resume=True,
        disable_tools=True,
    )

    assert "--tools" in called["cmd"]
    assert called["cmd"][called["cmd"].index("--tools") + 1] == ""
    assert called["cmd"][-2:] == ["--resume", "session-123"]


def test_run_codex_uses_thread_id_and_last_message(monkeypatch, tmp_dir):
    raw = "\n".join(
        [
            json.dumps({"type": "thread.started", "thread_id": "thread-123"}),
            json.dumps(
                {
                    "type": "turn.completed",
                    "usage": {
                        "input_tokens": 100,
                        "cached_input_tokens": 25,
                        "output_tokens": 10,
                    },
                }
            ),
        ]
    )
    called = {}

    def mock_run(cmd, **kwargs):
        called["cmd"] = cmd
        called["input"] = kwargs["input"]
        last_message = cmd[cmd.index("--output-last-message") + 1]
        with open(last_message, "w") as f:
            f.write("final answer")
        return subprocess.CompletedProcess(cmd, 0, raw, "")

    monkeypatch.setattr("lib.agent_runner.subprocess.run", mock_run)
    output_json = os.path.join(tmp_dir, "codex-output.json")

    result = run_agent(
        provider="codex",
        role="evaluator",
        prompt="prompt",
        artifact_dir=tmp_dir,
        repo_root="/repo",
        output_json=output_json,
    )

    assert called["cmd"][:5] == [
        "codex",
        "exec",
        "--dangerously-bypass-approvals-and-sandbox",
        "--cd",
        "/repo",
    ]
    assert called["cmd"][-1] == "-"
    assert called["input"] == "prompt"
    assert result["session_id"] == "thread-123"
    assert result["result"] == "final answer"
    assert os.path.isfile(os.path.join(tmp_dir, "evaluator-output.jsonl"))
    with open(output_json) as f:
        saved = json.load(f)
    assert saved["provider"] == "codex"
    assert saved["usage"]["input_tokens"] == 100
    assert saved["usage"]["cache_read_input_tokens"] == 25


def test_run_codex_minimal_mode_disables_tool_surfaces(monkeypatch, tmp_dir):
    raw = json.dumps({"type": "thread.started", "thread_id": "thread-123"})
    called = {}

    def mock_run(cmd, **kwargs):
        called["cmd"] = cmd
        last_message = cmd[cmd.index("--output-last-message") + 1]
        with open(last_message, "w") as f:
            f.write("final answer")
        return subprocess.CompletedProcess(cmd, 0, raw, "")

    monkeypatch.setattr("lib.agent_runner.subprocess.run", mock_run)
    output_json = os.path.join(tmp_dir, "codex-output.json")

    result = run_agent(
        provider="codex",
        role="auditor",
        prompt="prompt",
        artifact_dir=tmp_dir,
        repo_root="/repo",
        output_json=output_json,
        model="gpt-5.2",
        disable_tools=True,
    )

    assert "--dangerously-bypass-approvals-and-sandbox" not in called["cmd"]
    assert called["cmd"][called["cmd"].index("--sandbox") + 1] == "read-only"
    assert "--ignore-user-config" in called["cmd"]
    assert "--ignore-rules" in called["cmd"]
    assert "-c" in called["cmd"]
    assert called["cmd"][called["cmd"].index("-c") + 1] == "mcp_servers={}"
    assert called["cmd"][called["cmd"].index("-m") + 1] == "gpt-5.2"

    disabled = {
        called["cmd"][i + 1]
        for i, arg in enumerate(called["cmd"])
        if arg == "--disable"
    }
    assert disabled == set(CODEX_MINIMAL_MODE_DISABLED_FEATURES)
    assert result["session_id"] == "thread-123"
    assert os.path.isfile(os.path.join(tmp_dir, "auditor-output.jsonl"))
    with open(output_json) as f:
        assert json.load(f)["provider"] == "codex"


def test_run_codex_passes_reasoning_effort(monkeypatch, tmp_dir):
    raw = json.dumps({"type": "thread.started", "thread_id": "thread-123"})
    called = {}

    def mock_run(cmd, **kwargs):
        called["cmd"] = cmd
        last_message = cmd[cmd.index("--output-last-message") + 1]
        with open(last_message, "w") as f:
            f.write("final answer")
        return subprocess.CompletedProcess(cmd, 0, raw, "")

    monkeypatch.setattr("lib.agent_runner.subprocess.run", mock_run)

    run_agent(
        provider="codex",
        role="evaluator",
        prompt="prompt",
        artifact_dir=tmp_dir,
        repo_root="/repo",
        output_json=os.path.join(tmp_dir, "codex-output.json"),
        reasoning_effort="xhigh",
    )

    config_values = [
        called["cmd"][i + 1] for i, arg in enumerate(called["cmd"]) if arg == "-c"
    ]
    assert 'model_reasoning_effort="xhigh"' in config_values


def test_run_codex_allows_no_timeout(monkeypatch, tmp_dir):
    raw = json.dumps({"type": "thread.started", "thread_id": "thread-123"})
    called = {}

    def mock_run(cmd, **kwargs):
        called["timeout"] = kwargs["timeout"]
        last_message = cmd[cmd.index("--output-last-message") + 1]
        with open(last_message, "w") as f:
            f.write("final answer")
        return subprocess.CompletedProcess(cmd, 0, raw, "")

    monkeypatch.setattr("lib.agent_runner.subprocess.run", mock_run)

    run_agent(
        provider="codex",
        role="evaluator",
        prompt="prompt",
        artifact_dir=tmp_dir,
        repo_root="/repo",
        output_json=os.path.join(tmp_dir, "codex-output.json"),
        timeout=None,
    )

    assert called["timeout"] is None


def test_run_codex_resume(monkeypatch, tmp_dir):
    commands = []

    def capture_run(cmd, **kwargs):
        commands.append(cmd)
        last_message = cmd[cmd.index("--output-last-message") + 1]
        with open(last_message, "w") as f:
            f.write("")
        return subprocess.CompletedProcess(cmd, 0, "", "")

    monkeypatch.setattr("lib.agent_runner.subprocess.run", capture_run)
    run_agent(
        provider="codex",
        role="auditor",
        prompt="prompt",
        artifact_dir=tmp_dir,
        repo_root="/repo",
        output_json=os.path.join(tmp_dir, "codex-output-2.json"),
        session_id="thread-123",
        resume=True,
    )
    assert commands[0][-3:] == ["resume", "thread-123", "-"]


def test_run_codex_resume_requires_session_id(monkeypatch, tmp_dir):
    def fail_if_called(cmd, **kwargs):
        raise AssertionError("codex should not be invoked without a session id")

    monkeypatch.setattr("lib.agent_runner.subprocess.run", fail_if_called)

    with pytest.raises(RuntimeError, match="resume requires a session ID"):
        run_agent(
            provider="codex",
            role="auditor",
            prompt="prompt",
            artifact_dir=tmp_dir,
            repo_root="/repo",
            output_json=os.path.join(tmp_dir, "codex-output.json"),
            resume=True,
        )


def test_run_codex_minimal_resume(monkeypatch, tmp_dir):
    commands = []

    def capture_run(cmd, **kwargs):
        commands.append(cmd)
        last_message = cmd[cmd.index("--output-last-message") + 1]
        with open(last_message, "w") as f:
            f.write("")
        return subprocess.CompletedProcess(cmd, 0, "", "")

    monkeypatch.setattr("lib.agent_runner.subprocess.run", capture_run)
    run_agent(
        provider="codex",
        role="auditor",
        prompt="prompt",
        artifact_dir=tmp_dir,
        repo_root="/repo",
        output_json=os.path.join(tmp_dir, "codex-output-2.json"),
        session_id="thread-123",
        resume=True,
        disable_tools=True,
    )
    assert "--dangerously-bypass-approvals-and-sandbox" not in commands[0]
    assert commands[0][-3:] == ["resume", "thread-123", "-"]


def test_run_codex_nonzero_exit_writes_raw_jsonl(monkeypatch, tmp_dir):
    def fail_run(cmd, **kwargs):
        return subprocess.CompletedProcess(cmd, 1, "raw failure output", "error")

    monkeypatch.setattr("lib.agent_runner.subprocess.run", fail_run)

    with pytest.raises(RuntimeError, match="codex exited"):
        run_agent(
            provider="codex",
            role="evaluator",
            prompt="prompt",
            artifact_dir=tmp_dir,
            repo_root="/repo",
            output_json=os.path.join(tmp_dir, "codex-output.json"),
        )

    with open(os.path.join(tmp_dir, "evaluator-output.jsonl")) as f:
        assert f.read() == "raw failure output"
