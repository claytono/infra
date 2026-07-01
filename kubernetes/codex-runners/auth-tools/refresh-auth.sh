#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl nodejs npm
npm install -g @openai/codex@latest

python3 /etc/codex-auth-tools/copy-auth-json.py
if ! timeout 300 codex exec \
  --skip-git-repo-check \
  --sandbox read-only \
  --color never \
  "Reply exactly with: ok" >/tmp/codex-auth-refresh.out 2>&1; then
  tail -200 /tmp/codex-auth-refresh.out >&2
  exit 1
fi
python3 /etc/codex-auth-tools/publish-auth-json.py

curl -fsS -m 10 --retry 5 -o /dev/null \
  "https://hc.k.oneill.net/ping/${HEALTHCHECK_PING_KEY}/codex-auth-refresh"
