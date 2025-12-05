#!/bin/sh
# Maintenance wrapper script for NFS restic repos
# Runs forget + check with a single healthcheck ping
# Usage: maintenance-wrapper.sh <profile>

profile="$1"
if [ -z "$profile" ]; then
  echo "Usage: $0 <profile>" >&2
  exit 1
fi

uuid=$(cat /tmp/uuid)
hc_url="https://hc-ping.com/${HEALTHCHECK_PING_KEY}/kube-restic-${profile}-maintenance"

# Track state for cleanup
rc=1
failed_command=""
log_file="/tmp/maintenance-$$.log"

# Tee all output to log file for error capture
exec > >(tee -a "$log_file") 2>&1

# Always ping healthcheck on exit with captured error info
cleanup() {
  echo "Pinging healthcheck finish: ${hc_url}/${rc}"
  if [ $rc -eq 0 ]; then
    wget "${hc_url}/${rc}?rid=${uuid}" -O /dev/null -q --post-data "Profile: ${profile}
Commands: forget, check
Status: success" || true
  else
    error_output=$(tail -100 "$log_file")
    wget "${hc_url}/${rc}?rid=${uuid}" -O /dev/null -q --post-data "Profile: ${profile}
Failed command: ${failed_command}
Exit code: ${rc}
Output:
${error_output}" || true
  fi
  rm -f "$log_file"
}
trap cleanup EXIT

# Ping start
echo "Pinging healthcheck start: ${hc_url}/start"
wget "${hc_url}/start?rid=${uuid}" -O /dev/null -q --post-data "Profile: ${profile}
Commands: forget, check" || true

# Run forget
echo "Running forget for profile: ${profile}"
failed_command="resticprofile forget"
if ! resticprofile -c /resticprofile-config/profiles.yaml -n "$profile" --lock-wait 6h forget; then
  rc=$?
  echo "forget failed with exit code $rc"
  exit $rc
fi

# Run check
echo "Running check for profile: ${profile}"
failed_command="resticprofile check"
if ! resticprofile -c /resticprofile-config/profiles.yaml -n "$profile" --lock-wait 6h check; then
  rc=$?
  echo "check failed with exit code $rc"
  exit $rc
fi

# Success
rc=0
echo "Maintenance completed successfully"
