"""JSON schema validation for eval-data.json."""

from __future__ import annotations

import re
from typing import Any

from .common import VALID_LABELS, VALID_PACKAGE_TYPES


def validate_eval_data(data: dict[str, Any]) -> list[str]:
    """Validate eval-data dict. Returns list of errors (empty = valid)."""
    errors: list[str] = []

    if not isinstance(data, dict):
        return ["Root must be a JSON object"]

    # packages
    packages = data.get("packages")
    if not isinstance(packages, list) or len(packages) == 0:
        errors.append("'packages' must be a non-empty array")
    else:
        for i, pkg in enumerate(packages):
            if not isinstance(pkg, dict):
                errors.append(f"packages[{i}]: must be an object")
                continue
            for field in ("name", "old_version", "new_version"):
                val = pkg.get(field)
                if not isinstance(val, str) or not val:
                    errors.append(f"packages[{i}].{field}: required non-empty string")
            pkg_type = pkg.get("type")
            if not isinstance(pkg_type, str) or pkg_type not in VALID_PACKAGE_TYPES:
                errors.append(
                    f"packages[{i}].type: must be one of {VALID_PACKAGE_TYPES}, "
                    f"got {pkg_type!r}"
                )

    # label
    label = data.get("label")
    if not isinstance(label, str) or label not in VALID_LABELS:
        errors.append(f"'label' must be one of {VALID_LABELS}, got {label!r}")

    # Required string fields
    for field in ("update_scope", "hazards", "verdict"):
        val = data.get(field)
        if not isinstance(val, str) or not val.strip():
            errors.append(f"'{field}' is required and must be a non-empty string")

    # Optional string fields (string or null)
    for field in (
        "performance_stability",
        "features_ux",
        "security",
        "key_fixes",
        "newer_versions",
    ):
        val = data.get(field)
        if val is not None and not isinstance(val, str):
            errors.append(
                f"'{field}' must be a string or null, got {type(val).__name__}"
            )

    # sources
    sources = data.get("sources")
    if not isinstance(sources, list) or len(sources) == 0:
        errors.append("'sources' must be a non-empty array")
    else:
        for i, src in enumerate(sources):
            if not isinstance(src, dict):
                errors.append(f"sources[{i}]: must be an object")
                continue
            if not isinstance(src.get("label"), str) or not src["label"]:
                errors.append(f"sources[{i}].label: required non-empty string")
            url = src.get("url")
            if not isinstance(url, str) or not url.startswith("http"):
                errors.append(f"sources[{i}].url: must be a string starting with http")

    # Check for bare #NNN references in markdown content fields
    content_fields = [
        "update_scope",
        "performance_stability",
        "features_ux",
        "security",
        "key_fixes",
        "newer_versions",
        "hazards",
        "verdict",
    ]
    for field in content_fields:
        val = data.get(field)
        if isinstance(val, str):
            bare_refs = re.findall(r"(?:^|[^(\[/])#(\d{2,})", val)
            if bare_refs:
                errors.append(
                    f"'{field}' contains bare #NNN reference(s): "
                    f"{', '.join('#' + r for r in bare_refs)} "
                    "— use [#NNN](url) format"
                )

    return errors
