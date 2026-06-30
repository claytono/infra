"""Static checks for the composite GitHub Action."""

from __future__ import annotations

from pathlib import Path


ACTION_YAML = Path(__file__).resolve().parents[1] / "action.yaml"


def test_action_installs_superpowers_by_default():
    action = ACTION_YAML.read_text()

    assert "install_superpowers:" in action
    assert "default: 'true'" in action
    assert "superpowers_version:" in action
    assert "default: latest" in action
    assert "https://github.com/obra/superpowers/releases/latest" in action
    assert "git -c advice.detachedHead=false clone" in action
    assert '--branch "$superpowers_ref"' in action


def test_action_wires_superpowers_for_claude_and_codex():
    action = ACTION_YAML.read_text()

    assert "claude_plugin_dir=$checkout" in action
    assert (
        "RENOVATE_EVAL_CLAUDE_PLUGIN_DIR: "
        "${{ steps.superpowers.outputs.claude_plugin_dir }}" in action
    )
    assert ".claude-plugin/plugin.json" in action
    assert ".codex-plugin/plugin.json" in action
    assert "renovate-eval-superpowers" in action
    assert 'codex plugin marketplace add "$marketplace" --json' in action
    assert (
        "codex plugin add superpowers --marketplace renovate-eval-superpowers --json"
        in action
    )
