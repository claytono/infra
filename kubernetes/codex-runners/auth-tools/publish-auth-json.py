#!/usr/bin/env python3
import json
import os
import stat
import sys
import time
from pathlib import Path


def fail(message: str) -> None:
    print(f"codex auth publish failed: {message}", file=sys.stderr)
    sys.exit(1)


codex_home = Path(os.environ.get("CODEX_HOME", "/codex-home"))
source = Path(os.environ.get("SOURCE_AUTH", str(codex_home / "auth.json")))
auth_dir = Path(os.environ.get("AUTH_DIR", "/auth"))
target = auth_dir / "auth.json"
auth_uid = int(os.environ.get("AUTH_UID", "1001"))
auth_gid = int(os.environ.get("AUTH_GID", "1001"))
tmp = auth_dir / f".auth.json.{os.getpid()}.{time.time_ns()}.tmp"

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
    auth_dir.mkdir(parents=True, exist_ok=True)
    tmp.write_bytes(raw)
    os.chown(tmp, auth_uid, auth_gid)
    tmp.chmod(stat.S_IRUSR | stat.S_IWUSR)
    os.replace(tmp, target)
except OSError as exc:
    try:
        tmp.unlink(missing_ok=True)
    except OSError:
        pass
    fail(f"could not publish {target}: {exc}")

print(f"published Codex auth to {target}")
