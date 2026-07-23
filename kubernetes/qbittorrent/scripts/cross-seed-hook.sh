#!/bin/sh
set -eu

: "${CROSS_SEED_API_KEY:?CROSS_SEED_API_KEY is required}"

info_hash=${1:?info hash is required}
tags=${2:-}

old_ifs=$IFS
IFS=,
for tag in $tags; do
  tag=$(printf '%s' "$tag" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  if [ "$tag" = cross-seed ]; then
    exit 0
  fi
done
IFS=$old_ifs

curl \
  --fail \
  --silent \
  --show-error \
  --max-time 30 \
  --request POST \
  --header "X-Api-Key: ${CROSS_SEED_API_KEY}" \
  --data-urlencode "infoHash=${info_hash}" \
  --output /dev/null \
  http://cross-seed:2468/api/webhook
