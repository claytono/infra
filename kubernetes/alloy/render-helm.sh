#!/bin/bash

set -eu -o pipefail

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASEDIR"

# Source the chart-version.sh helper
source "$BASEDIR/../scripts/chart-version.sh"

rm -rf helm tmp
mkdir tmp helm

# Use helm_template helper function
helm_template alloy alloy \
	--values values.yaml \
	--namespace loki \
	--output-dir tmp

mv tmp/*/* helm
rmdir tmp/*
rmdir tmp

# Delete the PSP since it's a deprecated resource and we don't need the warnings.
rm -f helm/templates/podsecuritypolicy.yaml
