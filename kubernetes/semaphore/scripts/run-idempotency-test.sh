#!/bin/bash
set -xeu -o pipefail

source /config-map/scripts---setup-nix.sh

python /infra/scripts/ansible-idempotency-test "$@"
