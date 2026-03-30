"""Tests for lib/auditor.py."""

from __future__ import annotations

import json
import os
import subprocess

import pytest

from lib.auditor import (
    _strip_output_section,
    build_round_one_prompt,
    build_revision_prompt,
    run_auditor,
)


class TestStripOutputSection:
    def test_strips_output(self):
        md = "## Research\nGood stuff\n## Output\nWrite files\n## Next\nMore"
        result = _strip_output_section(md)
        assert "## Research" in result
        assert "Good stuff" in result
        assert "## Output" not in result
        assert "Write files" not in result
        assert "## Next" in result

    def test_ignores_heading_in_code_fence(self):
        md = "## Research\n```\n## Claim: something\n```\n## Output\nWrite files"
        result = _strip_output_section(md)
        assert "## Research" in result
        assert "## Claim: something" in result
        assert "## Output" not in result
        assert "Write files" not in result

    def test_strips_to_eof(self):
        md = "## Research\nStuff\n## Output\nWrite files\nMore output"
        result = _strip_output_section(md)
        assert "Write files" not in result
        assert "More output" not in result

    def test_no_output_section(self):
        md = "## Research\nStuff\n## Conclusion\nDone"
        result = _strip_output_section(md)
        assert result == md


class TestBuildRoundOnePrompt:
    def test_assembles_prompt(self, tmp_dir):
        prompts_dir = os.path.join(tmp_dir, "prompts")
        os.makedirs(prompts_dir)
        with open(os.path.join(prompts_dir, "auditor.md"), "w") as f:
            f.write("Preamble\n---\nAudit instructions")
        with open(os.path.join(prompts_dir, "evaluator.md"), "w") as f:
            f.write("## Research\nRules\n## Output\nJSON stuff")
        with open(os.path.join(prompts_dir, "report-format.md"), "w") as f:
            f.write("Format spec")

        prompt = build_round_one_prompt(
            script_dir=tmp_dir,
            artifact_dir="/tmp/art",
            report="# Report content",
            evidence="## Evidence",
        )
        assert "Preamble" in prompt
        assert "## Research" in prompt
        assert "## Output" not in prompt
        assert "Format spec" in prompt
        assert "# Report content" in prompt
        assert "## Evidence" in prompt
        assert "Audit instructions" in prompt


class TestBuildRevisionPrompt:
    def test_includes_round_and_report(self):
        prompt = build_revision_prompt(
            round_num=2,
            report="# Revised report",
            evidence="## Updated evidence",
        )
        assert "2" in prompt
        assert "# Revised report" in prompt
        assert "## Updated evidence" in prompt


class TestRunAuditor:
    def test_success(self, monkeypatch, tmp_dir):
        audit_json = '{"status":"PASS","issues":[]}'
        output = {
            "result": f"---JSON_START---\n{audit_json}\n---JSON_END---",
            "session_id": "aud123",
            "total_cost_usd": 0.3,
            "usage": {},
        }
        monkeypatch.setattr(
            "lib.auditor.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0],
                0,
                stdout=json.dumps(output),
                stderr="",
            ),
        )
        prompts_dir = os.path.join(tmp_dir, "prompts")
        os.makedirs(prompts_dir)
        for f in ("auditor.md", "evaluator.md", "report-format.md"):
            with open(os.path.join(prompts_dir, f), "w") as fh:
                fh.write(f"# {f}\n---\nInstructions")
        with open(os.path.join(tmp_dir, "eval-report.md"), "w") as f:
            f.write("# Report")

        result = run_auditor(
            round_num=1,
            artifact_dir=tmp_dir,
            model="sonnet",
            script_dir=tmp_dir,
        )
        assert result["status"] == "PASS"
        assert os.path.isfile(os.path.join(tmp_dir, "audit-result.json"))

    def test_nonzero_exit_raises(self, monkeypatch, tmp_dir):
        monkeypatch.setattr(
            "lib.auditor.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 1, stdout="", stderr="error"
            ),
        )
        with open(os.path.join(tmp_dir, "eval-report.md"), "w") as f:
            f.write("# Report")
        prompts_dir = os.path.join(tmp_dir, "prompts")
        os.makedirs(prompts_dir)
        for f in ("auditor.md", "evaluator.md", "report-format.md"):
            with open(os.path.join(prompts_dir, f), "w") as fh:
                fh.write("content\n---\ninstructions")

        with pytest.raises(RuntimeError, match="claude exited"):
            run_auditor(
                round_num=1,
                artifact_dir=tmp_dir,
                model="sonnet",
                script_dir=tmp_dir,
            )

    def test_no_json_sentinels(self, monkeypatch, tmp_dir):
        output = {"result": "No JSON here", "total_cost_usd": 0.1, "usage": {}}
        monkeypatch.setattr(
            "lib.auditor.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0],
                0,
                stdout=json.dumps(output),
                stderr="",
            ),
        )
        with open(os.path.join(tmp_dir, "eval-report.md"), "w") as f:
            f.write("# Report")
        prompts_dir = os.path.join(tmp_dir, "prompts")
        os.makedirs(prompts_dir)
        for f in ("auditor.md", "evaluator.md", "report-format.md"):
            with open(os.path.join(prompts_dir, f), "w") as fh:
                fh.write("content\n---\ninstructions")

        result = run_auditor(
            round_num=1,
            artifact_dir=tmp_dir,
            model="sonnet",
            script_dir=tmp_dir,
        )
        assert result == {}

    def test_evidence_fallback(self, monkeypatch, tmp_dir):
        """When eval-evidence.md doesn't exist, should use fallback text."""
        audit_json = '{"status":"PASS","issues":[]}'
        output = {
            "result": f"---JSON_START---\n{audit_json}\n---JSON_END---",
            "total_cost_usd": 0.1,
            "usage": {},
        }
        called_with = {}

        def mock_run(cmd, **kw):
            called_with["input"] = kw.get("input", "")
            return subprocess.CompletedProcess(
                cmd, 0, stdout=json.dumps(output), stderr=""
            )

        monkeypatch.setattr("lib.auditor.subprocess.run", mock_run)
        with open(os.path.join(tmp_dir, "eval-report.md"), "w") as f:
            f.write("# Report")
        prompts_dir = os.path.join(tmp_dir, "prompts")
        os.makedirs(prompts_dir)
        for f in ("auditor.md", "evaluator.md", "report-format.md"):
            with open(os.path.join(prompts_dir, f), "w") as fh:
                fh.write("content\n---\ninstructions")

        run_auditor(
            round_num=1, artifact_dir=tmp_dir, model="sonnet", script_dir=tmp_dir
        )
        assert "No evidence file provided" in called_with["input"]

    def test_revision_requires_session(self, tmp_dir):
        with open(os.path.join(tmp_dir, "eval-report.md"), "w") as f:
            f.write("# Report")
        with pytest.raises(RuntimeError, match="cannot resume"):
            run_auditor(
                round_num=2,
                artifact_dir=tmp_dir,
                model="sonnet",
                script_dir="/tmp",
                session_id="",
            )
