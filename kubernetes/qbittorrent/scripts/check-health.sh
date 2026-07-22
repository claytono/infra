#!/bin/sh

set -eu

: "${QBITTORRENT_API_KEY:?QBITTORRENT_API_KEY is required}"

curl \
  --fail \
  --silent \
  --show-error \
  --max-time 2 \
  --header "Authorization: Bearer ${QBITTORRENT_API_KEY}" \
  --output /dev/null \
  http://127.0.0.1:8080/api/v2/transfer/info
