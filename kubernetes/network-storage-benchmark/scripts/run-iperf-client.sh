#!/bin/bash
set -euo pipefail

SERVER_HOST="${SERVER_HOST:-iperf-server}"
OUTPUT_DIR="${OUTPUT_DIR:-/results}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SOURCE_NODE="${NODE_NAME:-unknown}"
DEST_NODE="${DEST_NODE:-unknown}"

echo "========================================="
echo "Network Benchmark Test"
echo "Source Node: ${SOURCE_NODE}"
echo "Destination Node: ${DEST_NODE}"
echo "Server: ${SERVER_HOST}"
echo "Timestamp: ${TIMESTAMP}"
echo "========================================="

# Wait for server to be ready
echo "Waiting for iperf3 server to be ready..."
i=1
while [ $i -le 30 ]; do
  if iperf3 -c "${SERVER_HOST}" -p 5201 -t 1 2>/dev/null; then
    echo "Server is ready"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 2
  i=$((i + 1))
done

# Final connectivity test
if ! iperf3 -c "${SERVER_HOST}" -p 5201 -t 1 >/dev/null 2>&1; then
  echo "ERROR: Server not reachable"
  exit 1
fi

RUN_OUTPUT="${OUTPUT_DIR}/network-${SOURCE_NODE}-to-${DEST_NODE}-${TIMESTAMP}"
mkdir -p "${RUN_OUTPUT}"

# Run warmup test
echo ""
echo "=== Running Warmup Test ==="
iperf3 -c "${SERVER_HOST}" -p 5201 -t 10 -J > "${RUN_OUTPUT}/warmup.json"
echo "Warmup complete"

# Run measured tests
for iteration in 1 2 3; do
  echo ""
  echo "=== Running Measured Test ${iteration}/3 ==="

  # TCP test
  iperf3 -c "${SERVER_HOST}" -p 5201 -t 30 -J > "${RUN_OUTPUT}/tcp-iter${iteration}.json"

  # Brief pause between tests
  sleep 2
done

echo ""
echo "=== Generating Report ==="

REPORT_FILE="${OUTPUT_DIR}/network-${SOURCE_NODE}-to-${DEST_NODE}-${TIMESTAMP}-report.txt"

{
  echo "========================================================================"
  echo "Network Benchmark Report"
  echo "========================================================================"
  echo ""
  echo "Timestamp:        ${TIMESTAMP}"
  echo "Source Node:      ${SOURCE_NODE}"
  echo "Destination Node: ${DEST_NODE}"
  echo "Test Duration:    30 seconds per iteration"
  echo ""
  echo "Configuration:"
  echo "- Warmup iterations: 1 (discarded)"
  echo "- Measured iterations: 3"
  echo "- Protocol: TCP"
  echo "- Tool: iperf3"
  echo ""
  echo "========================================================================"
  echo "Results"
  echo "========================================================================"
  echo ""
} > "${REPORT_FILE}"

# Parse each iteration result from JSON using Python
for iteration in 1 2 3; do
  json_file="${RUN_OUTPUT}/tcp-iter${iteration}.json"
  python3 /scripts/parse-results.py "${json_file}" "${iteration}" >> "${REPORT_FILE}"
done

{
  echo ""
  echo "Raw JSON files available in: ${RUN_OUTPUT}/"
  echo ""
  echo "To extract detailed metrics, use jq locally:"
  echo "  jq '.end.sum_sent' tcp-iter1.json"
  echo ""
  echo "========================================================================"
} >> "${REPORT_FILE}"

echo "Report generated: ${REPORT_FILE}"
echo ""
cat "${REPORT_FILE}"
