"""Tests for lib/render.py."""

from __future__ import annotations

from lib.render import render_report


class TestRenderReport:
    def test_basic_render(self, valid_eval_data):
        result = render_report(valid_eval_data)
        assert result.startswith("# sonarr (docker) 4.0.16 -> 4.0.17")
        assert "**Risk:** \U0001f7e2 Safe" in result
        assert "## The Deep Dive" in result
        assert "### Update Scope" in result
        assert "## Hazards & Risks" in result
        assert "## Sources" in result
        assert "## \U0001f7e2 Verdict: Safe" in result

    def test_ci_status_included(self, valid_eval_data):
        result = render_report(valid_eval_data, ci_status="passing")
        assert "| **CI:** passing" in result

    def test_ci_status_omitted(self, valid_eval_data):
        result = render_report(valid_eval_data)
        assert "**CI:**" not in result

    def test_optional_sections_omitted_when_null(self, valid_eval_data):
        valid_eval_data["performance_stability"] = None
        valid_eval_data["features_ux"] = None
        valid_eval_data["security"] = None
        valid_eval_data["newer_versions"] = None
        result = render_report(valid_eval_data)
        assert "### Performance & Stability" not in result
        assert "### Features & UX" not in result
        assert "### Security" not in result
        assert "### Newer Versions" not in result

    def test_optional_sections_included_when_present(self, valid_eval_data):
        valid_eval_data["performance_stability"] = "Some perf notes"
        valid_eval_data["features_ux"] = "Some feature notes"
        result = render_report(valid_eval_data)
        assert "### Performance & Stability" in result
        assert "Some perf notes" in result
        assert "### Features & UX" in result
        assert "Some feature notes" in result

    def test_key_fixes_rendered(self, valid_eval_data):
        result = render_report(valid_eval_data)
        assert "### Key Fixes" in result
        assert "#8242" in result

    def test_sources_as_links(self, valid_eval_data):
        result = render_report(valid_eval_data)
        assert (
            "- [Sonarr v4.0.17 release](https://github.com/Sonarr/Sonarr/releases/tag/v4.0.17)"
            in result
        )

    def test_multi_package_title(self, multi_package_eval_data):
        result = render_report(multi_package_eval_data)
        assert (
            "# postgresql (docker) 16.2 -> 16.3, sonarr (helm) 2.10.5 -> 2.10.6"
            in result
        )

    def test_multi_package_deduplication(self, valid_eval_data):
        """Duplicate packages should appear only once in title."""
        valid_eval_data["packages"].append(valid_eval_data["packages"][0].copy())
        result = render_report(valid_eval_data)
        title = result.split("\n")[0]
        assert title.count("sonarr") == 1

    def test_caution_label(self, valid_eval_data):
        valid_eval_data["label"] = "renovate:caution"
        result = render_report(valid_eval_data)
        assert "**Risk:** \U0001f7e1 Caution" in result
        assert "## \U0001f7e1 Verdict: Caution" in result

    def test_breaking_label(self, valid_eval_data):
        valid_eval_data["label"] = "renovate:breaking"
        result = render_report(valid_eval_data)
        assert "**Risk:** \U0001f7e0 Breaking" in result

    def test_risk_label(self, valid_eval_data):
        valid_eval_data["label"] = "renovate:risk"
        result = render_report(valid_eval_data)
        assert "**Risk:** \U0001f534 Risk" in result
