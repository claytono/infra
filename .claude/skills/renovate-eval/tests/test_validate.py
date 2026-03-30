"""Tests for lib/validate.py."""

from __future__ import annotations

import copy


from lib.validate import validate_eval_data


class TestValidateEvalData:
    def test_valid_data(self, valid_eval_data):
        assert validate_eval_data(valid_eval_data) == []

    def test_not_a_dict(self):
        assert validate_eval_data("string") == ["Root must be a JSON object"]
        assert validate_eval_data([]) == ["Root must be a JSON object"]

    def test_missing_packages(self, valid_eval_data):
        del valid_eval_data["packages"]
        errors = validate_eval_data(valid_eval_data)
        assert any("'packages'" in e for e in errors)

    def test_empty_packages(self, valid_eval_data):
        valid_eval_data["packages"] = []
        errors = validate_eval_data(valid_eval_data)
        assert any("'packages' must be a non-empty array" in e for e in errors)

    def test_invalid_package_type(self, valid_eval_data):
        valid_eval_data["packages"][0]["type"] = "invalid"
        errors = validate_eval_data(valid_eval_data)
        assert any("packages[0].type" in e for e in errors)

    def test_missing_package_fields(self, valid_eval_data):
        valid_eval_data["packages"][0] = {"name": "foo"}
        errors = validate_eval_data(valid_eval_data)
        assert any("old_version" in e for e in errors)
        assert any("new_version" in e for e in errors)
        assert any("type" in e for e in errors)

    def test_invalid_label(self, valid_eval_data):
        valid_eval_data["label"] = "invalid"
        errors = validate_eval_data(valid_eval_data)
        assert any("'label'" in e for e in errors)

    def test_missing_required_strings(self, valid_eval_data):
        for field in ("update_scope", "hazards", "verdict"):
            data = copy.deepcopy(valid_eval_data)
            data[field] = ""
            errors = validate_eval_data(data)
            assert any(f"'{field}'" in e for e in errors)

    def test_optional_fields_null(self, valid_eval_data):
        """Null optional fields should be valid."""
        for field in (
            "performance_stability",
            "features_ux",
            "security",
            "key_fixes",
            "newer_versions",
        ):
            valid_eval_data[field] = None
        assert validate_eval_data(valid_eval_data) == []

    def test_optional_fields_string(self, valid_eval_data):
        """String optional fields should be valid."""
        valid_eval_data["performance_stability"] = "Some text"
        assert validate_eval_data(valid_eval_data) == []

    def test_optional_fields_wrong_type(self, valid_eval_data):
        valid_eval_data["performance_stability"] = 123
        errors = validate_eval_data(valid_eval_data)
        assert any("performance_stability" in e for e in errors)

    def test_missing_sources(self, valid_eval_data):
        del valid_eval_data["sources"]
        errors = validate_eval_data(valid_eval_data)
        assert any("'sources'" in e for e in errors)

    def test_empty_sources(self, valid_eval_data):
        valid_eval_data["sources"] = []
        errors = validate_eval_data(valid_eval_data)
        assert any("'sources' must be a non-empty array" in e for e in errors)

    def test_source_missing_label(self, valid_eval_data):
        valid_eval_data["sources"][0] = {"url": "https://example.com"}
        errors = validate_eval_data(valid_eval_data)
        assert any("sources[0].label" in e for e in errors)

    def test_source_invalid_url(self, valid_eval_data):
        valid_eval_data["sources"][0]["url"] = "not-a-url"
        errors = validate_eval_data(valid_eval_data)
        assert any("sources[0].url" in e for e in errors)

    def test_bare_reference_detected(self, valid_eval_data):
        valid_eval_data["update_scope"] = "Fixes bug #1234 in the parser."
        errors = validate_eval_data(valid_eval_data)
        assert any("bare #NNN" in e for e in errors)

    def test_linked_reference_ok(self, valid_eval_data):
        valid_eval_data["update_scope"] = (
            "Fixes [#1234](https://github.com/ex/repo/issues/1234)."
        )
        assert validate_eval_data(valid_eval_data) == []

    def test_multi_package_valid(self, multi_package_eval_data):
        assert validate_eval_data(multi_package_eval_data) == []

    def test_all_package_types(self, valid_eval_data):
        for ptype in (
            "docker",
            "helm",
            "ansible",
            "terraform",
            "pre-commit",
            "github-action",
            "dependency",
        ):
            data = copy.deepcopy(valid_eval_data)
            data["packages"][0]["type"] = ptype
            assert validate_eval_data(data) == [], f"Failed for type {ptype}"

    def test_package_not_dict(self, valid_eval_data):
        valid_eval_data["packages"] = ["not a dict"]
        errors = validate_eval_data(valid_eval_data)
        assert any("must be an object" in e for e in errors)

    def test_source_not_dict(self, valid_eval_data):
        valid_eval_data["sources"] = ["not a dict"]
        errors = validate_eval_data(valid_eval_data)
        assert any("must be an object" in e for e in errors)

    def test_all_labels(self, valid_eval_data):
        for label in (
            "renovate:safe",
            "renovate:caution",
            "renovate:breaking",
            "renovate:risk",
        ):
            data = copy.deepcopy(valid_eval_data)
            data["label"] = label
            assert validate_eval_data(data) == [], f"Failed for label {label}"
