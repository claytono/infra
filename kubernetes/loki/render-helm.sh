#!/bin/bash

set -eu -o pipefail

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASEDIR"

# Source the chart-version.sh helper
source "$BASEDIR/../scripts/chart-version.sh"

rm -rf helm tmp
mkdir tmp helm

# Use helm_template helper function
helm_template loki loki \
	--values values.yaml \
	--output-dir tmp

mv tmp/*/* helm
rmdir tmp/*
rmdir tmp

# Delete the PSP since it's a deprecated resource and we don't need the warnings.
rm -f helm/templates/podsecuritypolicy.yaml

yq '.data."loki.yaml" | @base64d' \
	helm/templates/secret.yaml \
	>helm/loki.dist.yaml
