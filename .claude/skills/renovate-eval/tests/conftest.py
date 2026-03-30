"""Shared test fixtures for renovate-eval."""

from __future__ import annotations

import json
import os
import tempfile

import pytest


@pytest.fixture
def valid_eval_data() -> dict:
    """Minimal valid eval-data dict."""
    return {
        "packages": [
            {
                "name": "sonarr",
                "old_version": "4.0.16",
                "new_version": "4.0.17",
                "type": "docker",
            }
        ],
        "label": "renovate:safe",
        "update_scope": "Sonarr Docker image 4.0.16 -> 4.0.17. No bundled dependency changes.",
        "performance_stability": None,
        "features_ux": None,
        "security": None,
        "key_fixes": "Fixed a bug in the search indexer ([#8242](https://github.com/Sonarr/Sonarr/issues/8242)).",
        "newer_versions": None,
        "hazards": "None identified. Patch release with no breaking changes.",
        "sources": [
            {
                "label": "Sonarr v4.0.17 release",
                "url": "https://github.com/Sonarr/Sonarr/releases/tag/v4.0.17",
            }
        ],
        "verdict": "Straightforward patch release with a minor bug fix. Safe to merge.",
    }


@pytest.fixture
def multi_package_eval_data() -> dict:
    """Eval data with multiple packages."""
    return {
        "packages": [
            {
                "name": "postgresql",
                "old_version": "16.2",
                "new_version": "16.3",
                "type": "docker",
            },
            {
                "name": "sonarr",
                "old_version": "2.10.5",
                "new_version": "2.10.6",
                "type": "helm",
            },
        ],
        "label": "renovate:caution",
        "update_scope": "PostgreSQL 16.2 -> 16.3 and Sonarr Helm chart 2.10.5 -> 2.10.6.",
        "performance_stability": "PostgreSQL 16.3 includes vacuum performance improvements.",
        "features_ux": None,
        "security": None,
        "key_fixes": None,
        "newer_versions": None,
        "hazards": "PostgreSQL minor version bump may require `pg_upgrade` validation.",
        "sources": [
            {
                "label": "PostgreSQL 16.3 release notes",
                "url": "https://www.postgresql.org/docs/16/release-16-3.html",
            },
            {
                "label": "Sonarr Helm chart 2.10.6",
                "url": "https://github.com/example/charts/releases/tag/sonarr-2.10.6",
            },
        ],
        "verdict": "Minor updates with low risk but worth validating PostgreSQL upgrade path.",
    }


@pytest.fixture
def tmp_dir():
    """Create a temporary directory, cleaned up after test."""
    with tempfile.TemporaryDirectory() as d:
        yield d


@pytest.fixture
def eval_data_file(tmp_dir, valid_eval_data):
    """Write valid eval data to a temp file, return path."""
    path = os.path.join(tmp_dir, "eval-data.json")
    with open(path, "w") as f:
        json.dump(valid_eval_data, f)
    return path
