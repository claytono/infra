#!/bin/bash
set -euo pipefail

echo "Starting iperf3 server..."
echo "Node: ${NODE_NAME:-unknown}"
echo ""

iperf3 -s -p 5201
