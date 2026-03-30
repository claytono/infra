"""Render eval-data JSON to markdown report."""

from __future__ import annotations

from typing import Any

from .common import LABEL_EMOJI, LABEL_SHORT


def _build_title(packages: list[dict[str, str]]) -> str:
    """Build the H1 title line from packages, deduped."""
    seen: list[tuple[str, str, str, str]] = []
    for pkg in packages:
        key = (pkg["name"], pkg["type"], pkg["old_version"], pkg["new_version"])
        if key not in seen:
            seen.append(key)
    parts = [
        f"{name} ({ptype}) {old_ver} -> {new_ver}"
        for name, ptype, old_ver, new_ver in seen
    ]
    return ", ".join(parts)


def render_report(
    eval_data: dict[str, Any],
    ci_status: str | None = None,
) -> str:
    """Render eval-data dict to markdown. ci_status included only if provided."""
    lines: list[str] = []
    label = eval_data["label"]
    emoji = LABEL_EMOJI.get(label, "")
    short = LABEL_SHORT.get(label, label)

    # Title
    title = _build_title(eval_data["packages"])
    lines.append(f"# {title}")
    lines.append("")

    # Status line
    status = f"**Risk:** {emoji} {short}"
    if ci_status:
        status += f" | **CI:** {ci_status}"
    lines.append(status)
    lines.append("")

    # The Deep Dive
    lines.append("## The Deep Dive")
    lines.append("")

    # Update Scope (always required)
    lines.append("### Update Scope")
    lines.append("")
    lines.append(eval_data["update_scope"])
    lines.append("")

    # Optional sections
    optional_sections = [
        ("performance_stability", "Performance & Stability"),
        ("features_ux", "Features & UX"),
        ("security", "Security"),
        ("key_fixes", "Key Fixes"),
        ("newer_versions", "Newer Versions"),
    ]
    for field, heading in optional_sections:
        val = eval_data.get(field)
        if val and isinstance(val, str) and val.strip():
            lines.append(f"### {heading}")
            lines.append("")
            lines.append(val)
            lines.append("")

    # Hazards & Risks (always required)
    lines.append("## Hazards & Risks")
    lines.append("")
    lines.append(eval_data["hazards"])
    lines.append("")

    # Sources
    lines.append("## Sources")
    lines.append("")
    for src in eval_data["sources"]:
        lines.append(f"- [{src['label']}]({src['url']})")
    lines.append("")

    # Verdict
    lines.append("---")
    lines.append("")
    lines.append(f"## {emoji} Verdict: {short}")
    lines.append("")
    lines.append(eval_data["verdict"])

    return "\n".join(lines)
