"""Tests for lib/common.py."""

from __future__ import annotations

import json
import os
import subprocess

import pytest

from lib.common import (
    build_sentinel,
    compute_fingerprint,
    embed_eval_data,
    extract_eval_data,
    get_ci_status,
    parse_sentinel,
)


class TestSentinel:
    def test_build_sentinel(self):
        result = build_sentinel("renovate:safe", 2, "passing", 1, "abc123")
        assert "<!-- renovate-eval-skill:" in result
        assert '"version":4' in result
        assert '"label":"renovate:safe"' in result
        assert '"rounds":2' in result
        assert '"ci_status":"passing"' in result
        assert '"eval_count":1' in result
        assert '"fingerprint":"abc123"' in result
        assert result.endswith(" -->")

    def test_parse_sentinel_v4(self):
        sentinel = build_sentinel("renovate:caution", 1, "failing", 3, "def456")
        result = parse_sentinel(sentinel)
        assert result is not None
        assert result["version"] == 4
        assert result["label"] == "renovate:caution"
        assert result["rounds"] == 1
        assert result["ci_status"] == "failing"
        assert result["eval_count"] == 3
        assert result["fingerprint"] == "def456"

    def test_parse_sentinel_wrong_version(self):
        body = '<!-- renovate-eval-skill:{"version":3,"label":"renovate:safe"} -->'
        assert parse_sentinel(body) is None

    def test_parse_sentinel_no_match(self):
        assert parse_sentinel("no sentinel here") is None

    def test_parse_sentinel_invalid_json(self):
        assert parse_sentinel("<!-- renovate-eval-skill:{invalid} -->") is None

    def test_roundtrip(self):
        sentinel = build_sentinel("renovate:risk", 3, "unknown", 5, "xyz")
        parsed = parse_sentinel(sentinel)
        assert parsed["label"] == "renovate:risk"
        assert parsed["rounds"] == 3


class TestEmbedExtract:
    def test_embed_eval_data(self):
        data = {"label": "renovate:safe", "verdict": "ok"}
        result = embed_eval_data(data)
        assert result.startswith("<!-- renovate-eval-data\n")
        assert result.endswith("\n-->")

    def test_extract_eval_data(self):
        data = {"label": "renovate:safe", "verdict": "ok"}
        embedded = embed_eval_data(data)
        extracted = extract_eval_data(embedded)
        assert extracted == data

    def test_extract_no_match(self):
        assert extract_eval_data("no data here") is None

    def test_extract_bad_base64(self):
        body = "<!-- renovate-eval-data\n!!invalid!!\n-->"
        assert extract_eval_data(body) is None

    def test_roundtrip_complex(self, valid_eval_data):
        embedded = embed_eval_data(valid_eval_data)
        extracted = extract_eval_data(embedded)
        assert extracted == valid_eval_data


class TestFingerprint:
    def test_compute_fingerprint(self, tmp_dir):
        diff_path = os.path.join(tmp_dir, "test.patch")
        with open(diff_path, "w") as f:
            f.write("--- a/file.txt\n")
            f.write("+++ b/file.txt\n")
            f.write("+added line\n")
            f.write("-removed line\n")
            f.write(" context line\n")

        result = compute_fingerprint(diff_path)
        assert len(result) == 64  # SHA-256 hex
        assert result == compute_fingerprint(diff_path)  # deterministic

    def test_fingerprint_ignores_headers(self, tmp_dir):
        """--- and +++ lines should be excluded."""
        diff1 = os.path.join(tmp_dir, "diff1.patch")
        diff2 = os.path.join(tmp_dir, "diff2.patch")

        # Same content lines, different headers
        with open(diff1, "w") as f:
            f.write("--- a/old.txt\n+++ b/new.txt\n+line1\n")
        with open(diff2, "w") as f:
            f.write("--- a/other.txt\n+++ b/other.txt\n+line1\n")

        assert compute_fingerprint(diff1) == compute_fingerprint(diff2)

    def test_fingerprint_missing_file(self, tmp_dir):
        with pytest.raises(FileNotFoundError):
            compute_fingerprint(os.path.join(tmp_dir, "nonexistent"))

    def test_fingerprint_empty_diff(self, tmp_dir):
        diff_path = os.path.join(tmp_dir, "empty.patch")
        with open(diff_path, "w") as f:
            f.write(" context only\n")

        result = compute_fingerprint(diff_path)
        assert len(result) == 64


class TestRequireGhAuth:
    def test_token_env_success(self, monkeypatch):
        monkeypatch.setenv("GH_TOKEN", "test-token")
        monkeypatch.setattr(
            "lib.common.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(a[0], 0),
        )
        from lib.common import require_gh_auth

        require_gh_auth()  # should not raise

    def test_token_env_invalid(self, monkeypatch):
        monkeypatch.setenv("GH_TOKEN", "bad-token")
        monkeypatch.setattr(
            "lib.common.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(a[0], 1),
        )
        from lib.common import require_gh_auth

        with pytest.raises(SystemExit):
            require_gh_auth()

    def test_no_token_auth_status(self, monkeypatch):
        monkeypatch.delenv("GH_TOKEN", raising=False)
        monkeypatch.delenv("GITHUB_TOKEN", raising=False)
        monkeypatch.setattr(
            "lib.common.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(a[0], 0),
        )
        from lib.common import require_gh_auth

        require_gh_auth()  # should not raise

    def test_no_token_not_authed(self, monkeypatch):
        monkeypatch.delenv("GH_TOKEN", raising=False)
        monkeypatch.delenv("GITHUB_TOKEN", raising=False)
        monkeypatch.setattr(
            "lib.common.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(a[0], 1),
        )
        from lib.common import require_gh_auth

        with pytest.raises(SystemExit):
            require_gh_auth()


class TestRequireTools:
    def test_all_present(self, monkeypatch):
        monkeypatch.setattr("shutil.which", lambda t: f"/usr/bin/{t}")
        from lib.common import require_tools

        require_tools("gh", "git")

    def test_missing_tool(self, monkeypatch):
        monkeypatch.setattr("shutil.which", lambda t: None)
        from lib.common import require_tools

        with pytest.raises(SystemExit):
            require_tools("nonexistent")


class TestRunDiff:
    def test_gh_pr_diff_success(self, monkeypatch, tmp_dir):
        monkeypatch.setattr(
            "lib.common.subprocess.run",
            lambda *a, **kw: subprocess.CompletedProcess(
                a[0], 0, stdout=b"diff content"
            ),
        )
        from lib.common import run_diff

        outfile = os.path.join(tmp_dir, "diff.patch")
        run_diff(1234, outfile)
        with open(outfile, "rb") as f:
            assert f.read() == b"diff content"

    def test_gh_pr_diff_fallback(self, monkeypatch, tmp_dir):
        call_count = [0]

        def mock_run(cmd, **kw):
            call_count[0] += 1
            if call_count[0] == 1:
                # gh pr diff fails
                return subprocess.CompletedProcess(cmd, 1, stdout=b"", stderr=b"")
            if "baseRefName" in str(cmd):
                return subprocess.CompletedProcess(cmd, 0, stdout="main\n", stderr="")
            if "headRefName" in str(cmd):
                return subprocess.CompletedProcess(
                    cmd, 0, stdout="renovate/foo\n", stderr=""
                )
            if "remote" in cmd:
                return subprocess.CompletedProcess(cmd, 0, stdout=b"", stderr=b"")
            if "diff" in cmd:
                return subprocess.CompletedProcess(cmd, 0, stdout=b"fallback diff")
            return subprocess.CompletedProcess(cmd, 0, stdout=b"", stderr=b"")

        monkeypatch.setattr("lib.common.subprocess.run", mock_run)
        from lib.common import run_diff

        outfile = os.path.join(tmp_dir, "diff.patch")
        run_diff(1234, outfile)
        with open(outfile, "rb") as f:
            assert f.read() == b"fallback diff"


class TestSetupLogging:
    def test_no_duplicate_handlers(self):
        from lib.common import log, setup_logging

        initial = len(log.handlers)
        setup_logging()
        setup_logging()
        # Should not add more than one handler total
        assert len(log.handlers) <= initial + 1


class TestGetCiStatus:
    def test_returns_string(self, monkeypatch):
        """get_ci_status should always return a string."""
        # Mock subprocess to simulate failure
        import subprocess

        def mock_run(*args, **kwargs):
            result = subprocess.CompletedProcess(args[0], 1, stdout="", stderr="")
            return result

        monkeypatch.setattr("lib.common.subprocess.run", mock_run)
        assert get_ci_status(1234) == "unknown"

    def test_passing(self, monkeypatch):
        import subprocess

        def mock_run(*args, **kwargs):
            return subprocess.CompletedProcess(
                args[0],
                0,
                stdout=json.dumps(
                    [
                        {"name": "build", "bucket": "pass"},
                        {"name": "lint", "bucket": "pass"},
                    ]
                ),
            )

        monkeypatch.setattr("lib.common.subprocess.run", mock_run)
        assert get_ci_status(1234) == "passing"

    def test_failing(self, monkeypatch):
        import subprocess

        def mock_run(*args, **kwargs):
            return subprocess.CompletedProcess(
                args[0],
                0,
                stdout=json.dumps(
                    [
                        {"name": "build", "bucket": "pass"},
                        {"name": "test", "bucket": "fail"},
                    ]
                ),
            )

        monkeypatch.setattr("lib.common.subprocess.run", mock_run)
        assert get_ci_status(1234) == "failing"

    def test_pending(self, monkeypatch):
        import subprocess

        def mock_run(*args, **kwargs):
            return subprocess.CompletedProcess(
                args[0],
                0,
                stdout=json.dumps(
                    [
                        {"name": "build", "bucket": "pass"},
                        {"name": "deploy", "bucket": "pending"},
                    ]
                ),
            )

        monkeypatch.setattr("lib.common.subprocess.run", mock_run)
        assert get_ci_status(1234) == "pending"

    def test_cancel_is_failing(self, monkeypatch):
        import subprocess

        def mock_run(*args, **kwargs):
            return subprocess.CompletedProcess(
                args[0],
                0,
                stdout=json.dumps([{"name": "build", "bucket": "cancel"}]),
            )

        monkeypatch.setattr("lib.common.subprocess.run", mock_run)
        assert get_ci_status(1234) == "failing"

    def test_skipping_is_passing(self, monkeypatch):
        import subprocess

        def mock_run(*args, **kwargs):
            return subprocess.CompletedProcess(
                args[0],
                0,
                stdout=json.dumps(
                    [
                        {"name": "build", "bucket": "pass"},
                        {"name": "optional", "bucket": "skipping"},
                    ]
                ),
            )

        monkeypatch.setattr("lib.common.subprocess.run", mock_run)
        assert get_ci_status(1234) == "passing"

    def test_empty_checks(self, monkeypatch):
        import subprocess

        def mock_run(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 0, stdout="[]")

        monkeypatch.setattr("lib.common.subprocess.run", mock_run)
        assert get_ci_status(1234) == "unknown"
