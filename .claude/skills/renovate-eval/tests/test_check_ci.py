"""Tests for lib/check_ci.py."""

from __future__ import annotations

import json
import os
import subprocess

from lib.check_ci import check_ci, check_ci_once, fetch_failed_logs, wait_for_ci


class TestCheckCiOnce:
    def test_returns_output_and_code(self, monkeypatch):
        monkeypatch.setattr(
            "lib.check_ci.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout="all pass", stderr=""
            ),
        )
        output, code = check_ci_once(1234)
        assert code == 0
        assert "all pass" in output

    def test_failure_code(self, monkeypatch):
        monkeypatch.setattr(
            "lib.check_ci.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 1, stdout="", stderr="fail"
            ),
        )
        _output, code = check_ci_once(1234)
        assert code == 1


class TestWaitForCi:
    def test_success(self, monkeypatch):
        monkeypatch.setattr(
            "shutil.which", lambda cmd: "/usr/bin/timeout" if cmd == "timeout" else None
        )
        monkeypatch.setattr(
            "lib.check_ci.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout="done", stderr=""
            ),
        )
        _output, code = wait_for_ci(1234, timeout=60)
        assert code == 0

    def test_timeout_exit_124(self, monkeypatch):
        monkeypatch.setattr(
            "shutil.which", lambda cmd: "/usr/bin/timeout" if cmd == "timeout" else None
        )
        monkeypatch.setattr(
            "lib.check_ci.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 124, stdout="", stderr=""
            ),
        )
        output, code = wait_for_ci(1234, timeout=60)
        assert code == 2
        assert "timed out" in output

    def test_no_timeout_cmd(self, monkeypatch):
        monkeypatch.setattr("shutil.which", lambda cmd: None)
        monkeypatch.setattr(
            "lib.check_ci.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout="ok", stderr=""
            ),
        )
        _output, code = wait_for_ci(1234)
        assert code == 0

    def test_failure_not_timeout(self, monkeypatch):
        monkeypatch.setattr(
            "shutil.which", lambda cmd: "/usr/bin/timeout" if cmd == "timeout" else None
        )
        monkeypatch.setattr(
            "lib.check_ci.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 1, stdout="failed", stderr=""
            ),
        )
        _output, code = wait_for_ci(1234)
        assert code == 1


class TestFetchFailedLogs:
    def test_no_failures(self, monkeypatch):
        monkeypatch.setattr(
            "lib.check_ci.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout="[]", stderr=""
            ),
        )
        assert fetch_failed_logs(1234) == ""

    def test_gh_error(self, monkeypatch):
        monkeypatch.setattr(
            "lib.check_ci.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(a[0], 1, stdout="", stderr=""),
        )
        assert fetch_failed_logs(1234) == ""

    def test_with_failure(self, monkeypatch):
        checks = json.dumps(
            [
                {
                    "name": "build",
                    "conclusion": "FAILURE",
                    "detailsUrl": "https://github.com/foo/bar/actions/runs/12345/jobs/67890",
                },
            ]
        )

        def mock_run(cmd, **kw):
            if "--json" in cmd:
                return subprocess.CompletedProcess(cmd, 0, stdout=checks, stderr="")
            return subprocess.CompletedProcess(cmd, 0, stdout="log output", stderr="")

        monkeypatch.setattr("lib.check_ci.subprocess.run", mock_run)
        result = fetch_failed_logs(1234)
        assert "### build" in result

    def test_no_run_id_in_url(self, monkeypatch):
        checks = json.dumps(
            [
                {
                    "name": "build",
                    "conclusion": "FAILURE",
                    "detailsUrl": "https://example.com/no-run-id",
                },
            ]
        )
        monkeypatch.setattr(
            "lib.check_ci.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout=checks, stderr=""
            ),
        )
        result = fetch_failed_logs(1234)
        # No ### section since no run ID extractable
        assert "### build" not in result


class TestCheckCi:
    def test_non_wait(self, monkeypatch, tmp_dir):
        monkeypatch.setattr(
            "lib.check_ci.check_ci_once", lambda pr: ("checks output", 0)
        )
        monkeypatch.setattr("lib.check_ci.fetch_failed_logs", lambda pr: "")
        outfile = os.path.join(tmp_dir, "ci.md")
        code = check_ci(1234, output_file=outfile)
        assert code == 0
        assert os.path.isfile(outfile)

    def test_wait_mode(self, monkeypatch, tmp_dir):
        monkeypatch.setattr(
            "lib.check_ci.wait_for_ci", lambda pr, timeout: ("waited", 0)
        )
        monkeypatch.setattr("lib.check_ci.fetch_failed_logs", lambda pr: "")
        outfile = os.path.join(tmp_dir, "ci.md")
        code = check_ci(1234, wait=True, timeout=60, output_file=outfile)
        assert code == 0

    def test_stdout_when_no_file(self, monkeypatch, capsys):
        monkeypatch.setattr(
            "lib.check_ci.check_ci_once", lambda pr: ("stdout output", 0)
        )
        monkeypatch.setattr("lib.check_ci.fetch_failed_logs", lambda pr: "")
        check_ci(1234)
        assert "stdout output" in capsys.readouterr().out
