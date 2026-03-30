"""Tests for lib/evaluator.py."""

from __future__ import annotations

import json
import os
import subprocess

import pytest

from lib.evaluator import build_revision_prompt, build_round_one_prompt, run_evaluator


class TestBuildRoundOnePrompt:
    def test_includes_evaluator_md(self, tmp_dir):
        prompts_dir = os.path.join(tmp_dir, "prompts")
        os.makedirs(prompts_dir)
        with open(os.path.join(prompts_dir, "evaluator.md"), "w") as f:
            f.write("# Evaluator Instructions")

        prompt = build_round_one_prompt(
            script_dir=tmp_dir,
            artifact_dir="/tmp/artifacts",
            repo_root="/tmp/repo",
            context="local",
        )
        assert "# Evaluator Instructions" in prompt
        assert "**local**" in prompt

    def test_includes_repo_context(self, tmp_dir):
        prompts_dir = os.path.join(tmp_dir, "prompts")
        os.makedirs(prompts_dir)
        with open(os.path.join(prompts_dir, "evaluator.md"), "w") as f:
            f.write("evaluator")

        repo_root = os.path.join(tmp_dir, "repo")
        claude_dir = os.path.join(repo_root, ".claude")
        os.makedirs(claude_dir)
        with open(os.path.join(claude_dir, "renovate-eval.md"), "w") as f:
            f.write("repo context")

        prompt = build_round_one_prompt(
            script_dir=tmp_dir,
            artifact_dir="/tmp/art",
            repo_root=repo_root,
            context="ci",
        )
        assert "Repo context" in prompt

    def test_includes_instructions(self, tmp_dir):
        prompts_dir = os.path.join(tmp_dir, "prompts")
        os.makedirs(prompts_dir)
        with open(os.path.join(prompts_dir, "evaluator.md"), "w") as f:
            f.write("evaluator")

        prompt = build_round_one_prompt(
            script_dir=tmp_dir,
            artifact_dir="/tmp/art",
            repo_root="/tmp/repo",
            context="local",
            instructions="Focus on security",
        )
        assert "Focus on security" in prompt


class TestBuildRevisionPrompt:
    def test_uses_audit_result(self, tmp_dir):
        # No validation-feedback.json, should use audit-result.json
        audit_file = os.path.join(tmp_dir, "audit-result.json")
        with open(audit_file, "w") as f:
            f.write("{}")

        prompt = build_revision_prompt(
            script_dir="/tmp/scripts",
            artifact_dir=tmp_dir,
        )
        assert "auditor" in prompt
        assert "audit-result.json" in prompt

    def test_prefers_validation_feedback(self, tmp_dir):
        with open(os.path.join(tmp_dir, "validation-feedback.json"), "w") as f:
            f.write("{}")
        with open(os.path.join(tmp_dir, "audit-result.json"), "w") as f:
            f.write("{}")

        prompt = build_revision_prompt(
            script_dir="/tmp/scripts",
            artifact_dir=tmp_dir,
        )
        assert "validation" in prompt
        assert "validation-feedback.json" in prompt


class TestRunEvaluator:
    def test_success(self, monkeypatch, tmp_dir):
        output = {
            "session_id": "abc123",
            "result": "done",
            "total_cost_usd": 0.5,
            "usage": {"input_tokens": 100, "output_tokens": 50},
        }

        monkeypatch.setattr(
            "lib.evaluator.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0],
                0,
                stdout=json.dumps(output),
                stderr="",
            ),
        )
        prompts_dir = os.path.join(tmp_dir, "prompts")
        os.makedirs(prompts_dir)
        with open(os.path.join(prompts_dir, "evaluator.md"), "w") as f:
            f.write("evaluator")

        result = run_evaluator(
            round_num=1,
            artifact_dir=tmp_dir,
            model="opus",
            context="local",
            script_dir=tmp_dir,
            repo_root="/tmp/repo",
        )
        assert result["session_id"] == "abc123"
        assert os.path.isfile(os.path.join(tmp_dir, "evaluator-cost-r1.json"))

    def test_nonzero_exit_raises(self, monkeypatch, tmp_dir):
        monkeypatch.setattr(
            "lib.evaluator.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 1, stdout="", stderr="error"
            ),
        )
        prompts_dir = os.path.join(tmp_dir, "prompts")
        os.makedirs(prompts_dir)
        with open(os.path.join(prompts_dir, "evaluator.md"), "w") as f:
            f.write("evaluator")

        with pytest.raises(RuntimeError, match="claude exited"):
            run_evaluator(
                round_num=1,
                artifact_dir=tmp_dir,
                model="opus",
                context="local",
                script_dir=tmp_dir,
                repo_root="/tmp/repo",
            )

    def test_bad_json_raises(self, monkeypatch, tmp_dir):
        monkeypatch.setattr(
            "lib.evaluator.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout="not json", stderr=""
            ),
        )
        prompts_dir = os.path.join(tmp_dir, "prompts")
        os.makedirs(prompts_dir)
        with open(os.path.join(prompts_dir, "evaluator.md"), "w") as f:
            f.write("evaluator")

        with pytest.raises(RuntimeError, match="Failed to parse"):
            run_evaluator(
                round_num=1,
                artifact_dir=tmp_dir,
                model="opus",
                context="local",
                script_dir=tmp_dir,
                repo_root="/tmp/repo",
            )

    def test_revision_requires_session(self, tmp_dir):
        with pytest.raises(RuntimeError, match="cannot resume"):
            run_evaluator(
                round_num=2,
                artifact_dir=tmp_dir,
                model="opus",
                context="local",
                script_dir=tmp_dir,
                repo_root="/tmp/repo",
                session_id="",
            )

    def test_is_revision_uses_resume(self, monkeypatch, tmp_dir):
        output = {
            "session_id": "abc",
            "result": "ok",
            "total_cost_usd": 0.1,
            "usage": {},
        }
        cmds_called = []

        def mock_run(cmd, **kw):
            cmds_called.append(cmd)
            return subprocess.CompletedProcess(
                cmd, 0, stdout=json.dumps(output), stderr=""
            )

        monkeypatch.setattr("lib.evaluator.subprocess.run", mock_run)
        # Create validation-feedback for the revision prompt
        with open(os.path.join(tmp_dir, "validation-feedback.json"), "w") as f:
            f.write("{}")

        run_evaluator(
            round_num=1,
            artifact_dir=tmp_dir,
            model="opus",
            context="local",
            script_dir=tmp_dir,
            repo_root="/tmp/repo",
            session_id="session123",
            is_revision=True,
        )
        assert any("--resume" in cmd for cmd in cmds_called)

    def test_cost_suffix(self, monkeypatch, tmp_dir):
        output = {
            "session_id": "abc",
            "result": "ok",
            "total_cost_usd": 0.1,
            "usage": {},
        }
        monkeypatch.setattr(
            "lib.evaluator.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout=json.dumps(output), stderr=""
            ),
        )
        prompts_dir = os.path.join(tmp_dir, "prompts")
        os.makedirs(prompts_dir)
        with open(os.path.join(prompts_dir, "evaluator.md"), "w") as f:
            f.write("evaluator")

        run_evaluator(
            round_num=1,
            artifact_dir=tmp_dir,
            model="opus",
            context="local",
            script_dir=tmp_dir,
            repo_root="/tmp/repo",
            cost_suffix="-a2",
        )
        assert os.path.isfile(os.path.join(tmp_dir, "evaluator-cost-r1-a2.json"))
