#!/usr/bin/env python3
import json
import os
import stat
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"codex auth copy failed: {message}", file=sys.stderr)
    sys.exit(1)


source = Path(os.environ.get("AUTH_SOURCE", "/auth/auth.json"))
codex_home = Path(os.environ.get("CODEX_HOME", "/home/runner/.codex"))
target = codex_home / "auth.json"

try:
    raw = source.read_bytes()
except FileNotFoundError:
    fail(f"{source} is missing")
except OSError as exc:
    fail(f"could not read {source}: {exc}")

if not raw:
    fail(f"{source} is empty")

try:
    parsed = json.loads(raw)
except json.JSONDecodeError as exc:
    fail(f"{source} is not valid JSON: {exc}")

if not isinstance(parsed, dict):
    fail(f"{source} must contain a JSON object")

try:
    codex_home.mkdir(parents=True, exist_ok=True)
    target.write_bytes(raw)
    target.chmod(stat.S_IRUSR | stat.S_IWUSR)
except OSError as exc:
    fail(f"could not write {target}: {exc}")

print(f"copied Codex auth to {target}")
