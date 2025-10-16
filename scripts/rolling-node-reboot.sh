#!/bin/bash
set -euo pipefail

# Rolling reboot script for Kubernetes nodes
# Drains each node, reboots it, waits for it to come back, then moves to the next
#
# Usage: rolling-node-reboot.sh [node1 node2 ...]
# If no nodes specified, reboots all nodes

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Determine which nodes to process
if [ $# -eq 0 ]; then
    # No arguments - get all nodes
    NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
    log_info "No nodes specified, will reboot all nodes"
else
    # Use provided node list
    NODES="$*"
    log_info "Will reboot specified nodes: $*"
fi

if [ -z "$NODES" ]; then
    log_error "No nodes found!"
    exit 1
fi

echo

# Process each node
for node in $NODES; do
    log_info "========================================="
    log_info "Processing node: $node"
    log_info "========================================="

    # Drain the node
    log_info "Draining node $node..."
    if ! kubectl drain "$node" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --force \
        --grace-period=120 \
        --timeout=5m; then
        log_error "Failed to drain node $node"
        log_warn "Press ENTER to reboot anyway, or Ctrl+C to abort..."
        read -r
        log_info "Proceeding with reboot despite drain failure"
    else
        log_info "Node $node drained successfully"
    fi

    # Reboot the node
    log_info "Rebooting node $node..."
    if ! ssh "$node" "sudo systemctl reboot"; then
        log_warn "SSH command returned error (expected - node is rebooting)"
    fi

    # Wait for node to go NotReady
    log_info "Waiting for node $node to go NotReady..."
    timeout=120
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        status=$(kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [ "$status" != "True" ]; then
            log_info "Node $node is now NotReady"
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    if [ $elapsed -ge $timeout ]; then
        log_error "Timeout waiting for node $node to go NotReady"
        exit 1
    fi

    # Wait for node to come back and be Ready
    # For control plane nodes, the API might be unavailable, so we need to retry
    log_info "Waiting for node $node to come back online and be Ready..."
    timeout=600
    elapsed=0
    api_available=false

    while [ $elapsed -lt $timeout ]; do
        # Try to connect to API and check node status
        if status=$(kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null); then
            api_available=true
            if [ "$status" = "True" ]; then
                log_info "Node $node is Ready!"
                break
            fi
        else
            # API not available yet
            if [ "$api_available" = false ]; then
                # First time we can't reach API - this is expected for control plane
                log_info "API server not reachable yet (expected for control plane nodes)..."
                api_available="waiting"
            fi
        fi

        sleep 5
        elapsed=$((elapsed + 5))

        if [ $((elapsed % 30)) -eq 0 ]; then
            log_info "Still waiting... ($elapsed seconds elapsed)"
        fi
    done

    if [ $elapsed -ge $timeout ]; then
        log_error "Timeout waiting for node $node to become Ready"
        exit 1
    fi

    # Uncordon the node
    log_info "Uncordoning node $node..."
    if ! kubectl uncordon "$node"; then
        log_error "Failed to uncordon node $node"
        exit 1
    fi

    log_info "Node $node is back online and uncordoned"

    # Wait a bit before moving to next node to let pods stabilize
    log_info "Waiting 30 seconds for pods to stabilize before next node..."
    sleep 30
    echo
done

log_info "========================================="
log_info "All nodes rebooted successfully!"
log_info "========================================="
