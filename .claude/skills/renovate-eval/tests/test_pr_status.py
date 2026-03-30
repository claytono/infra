"""Tests for lib/pr_status.py."""

from __future__ import annotations


import subprocess

from lib.common import build_sentinel, embed_eval_data
from lib.pr_status import get_existing_eval_comment, pr_status


class TestGetExistingEvalComment:
    def test_returns_body(self, monkeypatch):
        monkeypatch.setattr(
            "lib.pr_status.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0],
                0,
                stdout="<!-- renovate-eval-skill:{} --> report",
                stderr="",
            ),
        )
        assert get_existing_eval_comment(1234) is not None

    def test_returns_none_on_empty(self, monkeypatch):
        monkeypatch.setattr(
            "lib.pr_status.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(a[0], 0, stdout="", stderr=""),
        )
        assert get_existing_eval_comment(1234) is None

    def test_returns_none_on_null(self, monkeypatch):
        monkeypatch.setattr(
            "lib.pr_status.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout="null", stderr=""
            ),
        )
        assert get_existing_eval_comment(1234) is None


class TestPrStatus:
    def test_no_comment(self, monkeypatch):
        monkeypatch.setattr("lib.pr_status.get_ci_status", lambda pr: "passing")
        monkeypatch.setattr("lib.pr_status.get_existing_eval_comment", lambda pr: None)
        assert pr_status(1234) == "CI_STATUS: passing"

    def test_v3_comment_ignored(self, monkeypatch):
        v3_body = '<!-- renovate-eval-skill:{"version":3,"label":"renovate:safe","confidence":"high"} -->\n# Report'
        monkeypatch.setattr("lib.pr_status.get_ci_status", lambda pr: "pending")
        monkeypatch.setattr(
            "lib.pr_status.get_existing_eval_comment", lambda pr: v3_body
        )
        assert pr_status(1234) == "CI_STATUS: pending"

    def test_v4_comment_rerendered(self, valid_eval_data, monkeypatch):
        sentinel = build_sentinel("renovate:safe", 1, "pending", 1, "abc")
        embedded = embed_eval_data(valid_eval_data)
        comment = f"{sentinel}\n\n# Old Report\n\n{embedded}"

        monkeypatch.setattr("lib.pr_status.get_ci_status", lambda pr: "passing")
        monkeypatch.setattr(
            "lib.pr_status.get_existing_eval_comment", lambda pr: comment
        )

        result = pr_status(1234)
        # Should be a re-rendered report with live CI
        assert result.startswith("# sonarr (docker) 4.0.16 -> 4.0.17")
        assert "| **CI:** passing" in result

    def test_v4_invalid_data_falls_back(self, monkeypatch):
        """When embedded data fails validation, should fall back to CI status."""
        sentinel = build_sentinel("renovate:safe", 1, "pending", 1, "abc")
        # Embed invalid data (missing required fields)
        import base64

        bad_data = base64.b64encode(b'{"label":"renovate:safe"}').decode()
        embedded = f"<!-- renovate-eval-data\n{bad_data}\n-->"
        comment = f"{sentinel}\n\n# Report\n\n{embedded}"

        monkeypatch.setattr("lib.pr_status.get_ci_status", lambda pr: "passing")
        monkeypatch.setattr(
            "lib.pr_status.get_existing_eval_comment", lambda pr: comment
        )

        result = pr_status(1234)
        assert result == "CI_STATUS: passing"

    def test_v4_render_error_falls_back(self, monkeypatch):
        """When render_report raises, should fall back to CI status."""
        sentinel = build_sentinel("renovate:safe", 1, "pending", 1, "abc")
        # Embed data that passes validation but causes render to fail
        eval_data = {
            "packages": [
                {"name": "x", "old_version": "1", "new_version": "2", "type": "docker"}
            ],
            "label": "renovate:safe",
            "update_scope": "test",
            "hazards": "none",
            "verdict": "ok",
            "sources": [{"label": "s", "url": "https://x.com"}],
        }
        embedded = embed_eval_data(eval_data)
        comment = f"{sentinel}\n\n# Report\n\n{embedded}"

        monkeypatch.setattr("lib.pr_status.get_ci_status", lambda pr: "passing")
        monkeypatch.setattr(
            "lib.pr_status.get_existing_eval_comment", lambda pr: comment
        )
        # Monkey-patch render to raise
        monkeypatch.setattr(
            "lib.pr_status.render_report",
            lambda *a, **kw: (_ for _ in ()).throw(KeyError("test")),
        )

        result = pr_status(1234)
        assert result == "CI_STATUS: passing"

    def test_v4_no_embedded_data(self, monkeypatch):
        sentinel = build_sentinel("renovate:safe", 1, "pending", 1, "abc")
        comment = f"{sentinel}\n\n# Report without embedded data"

        monkeypatch.setattr("lib.pr_status.get_ci_status", lambda pr: "failing")
        monkeypatch.setattr(
            "lib.pr_status.get_existing_eval_comment", lambda pr: comment
        )

        assert pr_status(1234) == "CI_STATUS: failing"
