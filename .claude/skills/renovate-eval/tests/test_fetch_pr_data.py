"""Tests for lib/fetch_pr_data.py."""

from __future__ import annotations

import json
import os
import subprocess

import pytest

from lib.fetch_pr_data import (
    detect_repo,
    fetch_body,
    fetch_files,
    fetch_metadata,
    fetch_pr_data,
    fetch_related_issues,
)


class TestDetectRepo:
    def test_success(self, monkeypatch):
        monkeypatch.setattr(
            "lib.fetch_pr_data.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout="owner/repo\n", stderr=""
            ),
        )
        assert detect_repo() == "owner/repo"

    def test_failure(self, monkeypatch):
        monkeypatch.setattr(
            "lib.fetch_pr_data.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(a[0], 1, stdout="", stderr=""),
        )
        with pytest.raises(SystemExit):
            detect_repo()


class TestFetchPrData:
    def test_writes_files(self, monkeypatch, tmp_dir):
        monkeypatch.setattr("lib.fetch_pr_data.detect_repo", lambda: "owner/repo")
        monkeypatch.setattr(
            "lib.fetch_pr_data.run_diff", lambda pr, out: open(out, "w").close()
        )

        data = {
            "number": 1,
            "title": "T",
            "author": {"login": "b"},
            "state": "OPEN",
            "url": "u",
            "baseRefName": "main",
            "headRefName": "h",
            "additions": 0,
            "deletions": 0,
            "changedFiles": 0,
        }

        def mock_run(cmd, **kw):
            cmd_str = " ".join(str(c) for c in cmd)
            if "body" in cmd_str:
                return subprocess.CompletedProcess(
                    cmd, 0, stdout="body text", stderr=""
                )
            if "files" in cmd_str:
                return subprocess.CompletedProcess(
                    cmd, 0, stdout=json.dumps({"files": []}), stderr=""
                )
            if "closingIssuesReferences" in cmd_str:
                return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
            if "timeline" in cmd_str:
                return subprocess.CompletedProcess(cmd, 0, stdout="[]", stderr="")
            return subprocess.CompletedProcess(
                cmd, 0, stdout=json.dumps(data), stderr=""
            )

        monkeypatch.setattr("lib.fetch_pr_data.subprocess.run", mock_run)
        fetch_pr_data(1, tmp_dir)
        assert os.path.isfile(os.path.join(tmp_dir, "pr-data.md"))
        assert os.path.isfile(os.path.join(tmp_dir, "pr-diff.patch"))


class TestFetchMetadata:
    def test_success(self, monkeypatch):
        data = {
            "number": 42,
            "title": "Update foo",
            "author": {"login": "bot"},
            "state": "OPEN",
            "url": "https://github.com/a/b/pull/42",
            "baseRefName": "main",
            "headRefName": "renovate/foo",
            "additions": 10,
            "deletions": 5,
            "changedFiles": 2,
        }
        monkeypatch.setattr(
            "lib.fetch_pr_data.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout=json.dumps(data), stderr=""
            ),
        )
        result = fetch_metadata(42)
        assert "Update foo" in result
        assert "+10" in result

    def test_failure(self, monkeypatch):
        monkeypatch.setattr(
            "lib.fetch_pr_data.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 1, stdout="", stderr="err"
            ),
        )
        result = fetch_metadata(42)
        assert "ERROR" in result


class TestFetchBody:
    def test_error(self, monkeypatch):
        monkeypatch.setattr(
            "lib.fetch_pr_data.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 1, stdout="", stderr="err"
            ),
        )
        result = fetch_body(42)
        assert "ERROR" in result

    def test_strips_html_comments(self, monkeypatch):
        body = "Before <!-- comment --> After"
        monkeypatch.setattr(
            "lib.fetch_pr_data.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout=body, stderr=""
            ),
        )
        result = fetch_body(42)
        assert "Before" in result
        assert "After" in result
        assert "comment" not in result

    def test_multiline_html_comment(self, monkeypatch):
        body = "Before <!-- multi\nline\ncomment --> After"
        monkeypatch.setattr(
            "lib.fetch_pr_data.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout=body, stderr=""
            ),
        )
        result = fetch_body(42)
        assert "multi" not in result


class TestFetchFiles:
    def test_with_diff_offsets(self, monkeypatch, tmp_dir):
        diff_path = os.path.join(tmp_dir, "test.patch")
        with open(diff_path, "wb") as f:
            f.write(b"diff --git a/foo.txt b/foo.txt\n+added\n")

        files_data = {"files": [{"path": "foo.txt", "additions": 1, "deletions": 0}]}
        monkeypatch.setattr(
            "lib.fetch_pr_data.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout=json.dumps(files_data), stderr=""
            ),
        )
        result = fetch_files(42, diff_path)
        assert "foo.txt" in result
        assert "[L1]" in result


class TestFetchRelatedIssues:
    def test_no_issues(self, monkeypatch):
        def mock_run(cmd, **kw):
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        monkeypatch.setattr("lib.fetch_pr_data.subprocess.run", mock_run)
        result = fetch_related_issues(42, "owner/repo")
        assert "No linked" in result

    def test_with_cross_references(self, monkeypatch):
        xrefs = json.dumps(
            [
                {"number": 10, "title": "Related", "state": "OPEN", "type": "Issue"},
            ]
        )

        def mock_run(cmd, **kw):
            cmd_str = " ".join(str(c) for c in cmd)
            if "closingIssuesReferences" in cmd_str:
                return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
            if "timeline" in cmd_str:
                return subprocess.CompletedProcess(cmd, 0, stdout=xrefs, stderr="")
            if "issue" in cmd_str and "view" in cmd_str:
                return subprocess.CompletedProcess(
                    cmd, 0, stdout="Issue body text", stderr=""
                )
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        monkeypatch.setattr("lib.fetch_pr_data.subprocess.run", mock_run)
        result = fetch_related_issues(42, "owner/repo")
        assert "Related" in result

    def test_with_closing_issue(self, monkeypatch):
        call_count = [0]

        def mock_run(cmd, **kw):
            call_count[0] += 1
            cmd_str = " ".join(str(c) for c in cmd)
            if "closingIssuesReferences" in cmd_str:
                return subprocess.CompletedProcess(cmd, 0, stdout="99\n", stderr="")
            if "issue" in cmd_str and "view" in cmd_str:
                data = {
                    "number": 99,
                    "title": "Fix bug",
                    "body": "Details",
                    "state": "OPEN",
                }
                return subprocess.CompletedProcess(
                    cmd, 0, stdout=json.dumps(data), stderr=""
                )
            if "timeline" in cmd_str:
                return subprocess.CompletedProcess(cmd, 0, stdout="[]", stderr="")
            return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

        monkeypatch.setattr("lib.fetch_pr_data.subprocess.run", mock_run)
        result = fetch_related_issues(42, "owner/repo")
        assert "Issue #99" in result
