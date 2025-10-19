#!/bin/bash
set -euo pipefail

# Rolling reboot script for Kubernetes nodes
# Drains each node, reboots it, waits for it to come back, then moves to the next
#
# By default, the script will:
# 1. Get list of pods on the node before draining
# 2. Drain the node
# 3. Wait for drained pods to become ready on other nodes (5 min timeout)
# 4. Reboot the node
# 5. Wait for node to come back up
# 6. Uncordon the node
# 7. Wait for all pods on the node to be ready (5 min timeout)
#
# Usage: rolling-node-reboot.sh [OPTIONS] [node1 node2 ...]
# If no nodes specified, reboots all nodes
#
# Options:
#   --skip-pod-checks    Skip waiting for pods to be ready (faster but less safe)
#                        Reverts to old behavior of just waiting 30s between nodes

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

show_help() {
    cat << EOF
Rolling reboot script for Kubernetes nodes

Usage: $(basename "$0") [OPTIONS] [node1 node2 ...]

By default, reboots all nodes if none are specified.

Options:
  -h, --help                      Show this help message and exit
  --skip-pod-checks               Skip waiting for pods to be ready (faster but less safe)
  --skip-reboot                   Drain and uncordon nodes without rebooting (useful for testing)

  Timeout Options (in seconds):
  --timeout <seconds>             Set all timeouts at once (overridden by specific flags)
  --timeout-drain <seconds>       Timeout for kubectl drain (default: ${DEFAULT_TIMEOUT_DRAIN}s)
  --timeout-pods-ready <seconds>  Timeout for pods ready after drain (default: ${DEFAULT_TIMEOUT_PODS_READY}s)
  --timeout-node-notready <seconds>  Timeout for node to go NotReady (default: ${DEFAULT_TIMEOUT_NODE_NOTREADY}s)
  --timeout-node-ready <seconds>  Timeout for node to become Ready (default: ${DEFAULT_TIMEOUT_NODE_READY}s)
  --timeout-node-pods <seconds>   Timeout for node pods after uncordon (default: ${DEFAULT_TIMEOUT_NODE_PODS}s)
  --progress-interval <seconds>   Progress reporting interval (default: ${DEFAULT_PROGRESS_INTERVAL}s)

Default behavior:
  1. Drain the node (${DEFAULT_TIMEOUT_DRAIN}s timeout)
  2. Wait for cluster pods to be ready (${DEFAULT_TIMEOUT_PODS_READY}s timeout)
  3. Reboot the node
  4. Wait for node to go NotReady (${DEFAULT_TIMEOUT_NODE_NOTREADY}s timeout)
  5. Wait for node to come back Ready (${DEFAULT_TIMEOUT_NODE_READY}s timeout)
  6. Uncordon the node
  7. Wait for pods on node to be ready (${DEFAULT_TIMEOUT_NODE_PODS}s timeout)

Examples:
  $(basename "$0")                              # Reboot all nodes with defaults
  $(basename "$0") node1 node2                  # Reboot specific nodes
  $(basename "$0") --skip-pod-checks node1      # Skip pod readiness checks
  $(basename "$0") --timeout 600 node1          # Set all timeouts to 600s
  $(basename "$0") --timeout 600 --timeout-node-ready 900 node1  # Override one timeout
  $(basename "$0") --progress-interval 10 node1 # Report progress every 10s
EOF
    exit 0
}

# Default timeout values (in seconds)
DEFAULT_TIMEOUT_DRAIN=300
DEFAULT_TIMEOUT_PODS_READY=300
DEFAULT_TIMEOUT_NODE_NOTREADY=300
DEFAULT_TIMEOUT_NODE_READY=600
DEFAULT_TIMEOUT_NODE_PODS=300
DEFAULT_PROGRESS_INTERVAL=10

# Parse command line options
SKIP_POD_CHECKS=false
SKIP_REBOOT=false
NODES_ARGS=()
GLOBAL_TIMEOUT=""
TIMEOUT_DRAIN=""
TIMEOUT_PODS_READY=""
TIMEOUT_NODE_NOTREADY=""
TIMEOUT_NODE_READY=""
TIMEOUT_NODE_PODS=""
PROGRESS_INTERVAL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        --skip-pod-checks)
            SKIP_POD_CHECKS=true
            shift
            ;;
        --skip-reboot)
            SKIP_REBOOT=true
            shift
            ;;
        --timeout)
            GLOBAL_TIMEOUT="$2"
            shift 2
            ;;
        --timeout-drain)
            TIMEOUT_DRAIN="$2"
            shift 2
            ;;
        --timeout-pods-ready)
            TIMEOUT_PODS_READY="$2"
            shift 2
            ;;
        --timeout-node-notready)
            TIMEOUT_NODE_NOTREADY="$2"
            shift 2
            ;;
        --timeout-node-ready)
            TIMEOUT_NODE_READY="$2"
            shift 2
            ;;
        --timeout-node-pods)
            TIMEOUT_NODE_PODS="$2"
            shift 2
            ;;
        --progress-interval)
            PROGRESS_INTERVAL="$2"
            shift 2
            ;;
        -*)
            log_error "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
        *)
            NODES_ARGS+=("$1")
            shift
            ;;
    esac
done

# Apply timeout precedence: individual flags override --timeout, which overrides defaults
TIMEOUT_DRAIN="${TIMEOUT_DRAIN:-${GLOBAL_TIMEOUT:-$DEFAULT_TIMEOUT_DRAIN}}"
TIMEOUT_PODS_READY="${TIMEOUT_PODS_READY:-${GLOBAL_TIMEOUT:-$DEFAULT_TIMEOUT_PODS_READY}}"
TIMEOUT_NODE_NOTREADY="${TIMEOUT_NODE_NOTREADY:-${GLOBAL_TIMEOUT:-$DEFAULT_TIMEOUT_NODE_NOTREADY}}"
TIMEOUT_NODE_READY="${TIMEOUT_NODE_READY:-${GLOBAL_TIMEOUT:-$DEFAULT_TIMEOUT_NODE_READY}}"
TIMEOUT_NODE_PODS="${TIMEOUT_NODE_PODS:-${GLOBAL_TIMEOUT:-$DEFAULT_TIMEOUT_NODE_PODS}}"
PROGRESS_INTERVAL="${PROGRESS_INTERVAL:-$DEFAULT_PROGRESS_INTERVAL}"

# Determine which nodes to process
if [ ${#NODES_ARGS[@]} -eq 0 ]; then
    # No arguments - get all nodes
    NODES=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
    log_info "No nodes specified, will reboot all nodes"
else
    # Use provided node list
    NODES="${NODES_ARGS[*]}"
    log_info "Will reboot specified nodes: ${NODES_ARGS[*]}"
fi

if [ -z "$NODES" ]; then
    log_error "No nodes found!"
    exit 1
fi

# Function to wait for all pods in the cluster to be ready
# Excludes pods on cordoned nodes (they won't be scheduled there)
wait_for_all_pods_ready() {
    local timeout=$TIMEOUT_PODS_READY
    local start_time
    start_time=$(date +%s)

    log_info "Waiting for all cluster pods to be ready (timeout: ${timeout}s)..."

    while true; do
        # Get all pods that are not on cordoned nodes and not in terminal state
        local pods_status
        pods_status=$(kubectl get pods --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')

        # Get list of cordoned nodes
        local cordoned_nodes
        cordoned_nodes=$(kubectl get nodes -o json | jq -r '.items[] | select(.spec.unschedulable==true) | .metadata.name')

        # Count total pods and ready pods (excluding those on cordoned nodes and terminal states)
        local total_pods=0
        local ready_pods=0
        local not_ready_list=()

        while IFS= read -r pod_info; do
            [ -z "$pod_info" ] && continue

            local namespace=$(echo "$pod_info" | jq -r '.metadata.namespace')
            local name=$(echo "$pod_info" | jq -r '.metadata.name')
            local node=$(echo "$pod_info" | jq -r '.spec.nodeName // empty')
            local phase=$(echo "$pod_info" | jq -r '.status.phase')
            local ready=$(echo "$pod_info" | jq -r '.status.conditions[]? | select(.type=="Ready") | .status')

            # Skip pods in terminal states
            if [ "$phase" = "Succeeded" ] || [ "$phase" = "Failed" ]; then
                continue
            fi

            # Skip pods on cordoned nodes
            if echo "$cordoned_nodes" | grep -q "^${node}$"; then
                continue
            fi

            total_pods=$((total_pods + 1))

            if [ "$ready" = "True" ]; then
                ready_pods=$((ready_pods + 1))
            else
                not_ready_list+=("$namespace/$name")
            fi
        done < <(echo "$pods_status" | jq -c '.items[]')

        if [ "$total_pods" -eq 0 ]; then
            log_warn "No pods found in cluster, waiting..."
            sleep 5
            continue
        fi

        if [ "$ready_pods" -eq "$total_pods" ]; then
            log_info "All cluster pods are ready! ($ready_pods/$total_pods)"
            return 0
        fi

        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ "$elapsed" -ge "$timeout" ]; then
            log_error "Timeout waiting for pods to be ready after ${timeout}s"
            log_error "Ready: $ready_pods/$total_pods"
            if [ ${#not_ready_list[@]} -gt 0 ]; then
                log_error "Not ready pods (showing first 10):"
                printf '%s\n' "${not_ready_list[@]}" | head -10 | while read -r pod; do
                    log_error "  - $pod"
                done
            fi
            return 1
        fi

        # Print status at configured interval
        if [ $((elapsed % PROGRESS_INTERVAL)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            log_info "Waiting for pods... ($ready_pods/$total_pods ready, ${elapsed}s elapsed)"
        fi

        sleep 5
    done
}

# Function to wait for all pods on a node to be ready
wait_for_node_pods_ready() {
    local node=$1
    local timeout=$TIMEOUT_NODE_PODS
    local start_time
    start_time=$(date +%s)

    log_info "Waiting for all pods on node $node to be ready (timeout: ${timeout}s)..."

    while true; do
        # Get all pods on the node
        local pods
        pods=$(kubectl get pods --all-namespaces \
            --field-selector spec.nodeName="$node" \
            -o json 2>/dev/null || echo '{"items":[]}')

        # Count total pods and ready pods (excluding terminal states)
        # Skip pods in terminal states (Succeeded/Failed) as they won't become Ready
        local total_pods
        total_pods=$(echo "$pods" | jq -r '[.items[] | select(.status.phase != "Succeeded" and .status.phase != "Failed")] | length')

        if [ "$total_pods" -eq 0 ]; then
            log_warn "No non-terminal pods found on node $node yet, waiting..."
            sleep 5
            continue
        fi

        local ready_pods
        ready_pods=$(echo "$pods" | jq -r '[.items[] | select(.status.phase != "Succeeded" and .status.phase != "Failed") | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')

        if [ "$ready_pods" -eq "$total_pods" ]; then
            log_info "All pods on node $node are ready! ($ready_pods/$total_pods)"
            return 0
        fi

        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ "$elapsed" -ge "$timeout" ]; then
            log_error "Timeout waiting for pods on node $node to be ready after ${timeout}s"
            log_error "Ready: $ready_pods/$total_pods"
            return 1
        fi

        if [ $((elapsed % PROGRESS_INTERVAL)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            log_info "Still waiting... ($ready_pods/$total_pods ready, ${elapsed}s elapsed)"
        fi

        sleep 5
    done
}

echo

# Process each node
for node in $NODES; do
    log_info "========================================="
    log_info "Processing node: $node"
    log_info "========================================="

    # Drain the node
    log_info "Draining node $node (timeout: ${TIMEOUT_DRAIN}s)..."
    if ! kubectl drain "$node" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --force \
        --grace-period=120 \
        --timeout="${TIMEOUT_DRAIN}s"; then
        log_error "Failed to drain node $node"
        log_warn "Press ENTER to reboot anyway, or Ctrl+C to abort..."
        read -r
        log_info "Proceeding with reboot despite drain failure"
    else
        log_info "Node $node drained successfully"
    fi

    # Wait for all cluster pods to be ready (if not skipping checks)
    if [ "$SKIP_POD_CHECKS" = false ]; then
        if ! wait_for_all_pods_ready; then
            log_error "Some pods did not become ready after draining"
            log_warn "Press ENTER to continue anyway, or Ctrl+C to abort..."
            read -r
            log_info "Proceeding despite pods not being ready"
        fi
    fi

    # Reboot the node (unless skipping)
    if [ "$SKIP_REBOOT" = false ]; then
        log_info "Rebooting node $node..."
        if ! ssh "$node" "sudo systemctl reboot"; then
            log_warn "SSH command returned error (expected - node is rebooting)"
        fi

        # Wait for node to go NotReady
        log_info "Waiting for node $node to go NotReady (timeout: ${TIMEOUT_NODE_NOTREADY}s)..."
        elapsed=0
        while [ $elapsed -lt "$TIMEOUT_NODE_NOTREADY" ]; do
            status=$(kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
            if [ "$status" != "True" ]; then
                log_info "Node $node is now NotReady"
                break
            fi

            if [ $((elapsed % PROGRESS_INTERVAL)) -eq 0 ] && [ $elapsed -gt 0 ]; then
                log_info "Still waiting for node to go NotReady... (${elapsed}s elapsed)"
            fi

            sleep 1
            elapsed=$((elapsed + 1))
        done

        if [ $elapsed -ge "$TIMEOUT_NODE_NOTREADY" ]; then
            log_error "Timeout waiting for node $node to go NotReady"
            exit 1
        fi

        # Wait for node to come back and be Ready
        # For control plane nodes, the API might be unavailable, so we need to retry
        log_info "Waiting for node $node to come back online and be Ready (timeout: ${TIMEOUT_NODE_READY}s)..."
        elapsed=0
        api_available=false

        while [ $elapsed -lt "$TIMEOUT_NODE_READY" ]; do
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

            if [ $((elapsed % PROGRESS_INTERVAL)) -eq 0 ] && [ $elapsed -gt 0 ]; then
                log_info "Still waiting... (${elapsed}s elapsed)"
            fi
        done

        if [ $elapsed -ge "$TIMEOUT_NODE_READY" ]; then
            log_error "Timeout waiting for node $node to become Ready"
            exit 1
        fi
    else
        log_info "Skipping reboot for node $node (--skip-reboot enabled)"
    fi

    # Uncordon the node
    log_info "Uncordoning node $node..."
    if ! kubectl uncordon "$node"; then
        log_error "Failed to uncordon node $node"
        exit 1
    fi

    log_info "Node $node is back online and uncordoned"

    # Wait for all pods on the node to be ready (if not skipping checks)
    if [ "$SKIP_POD_CHECKS" = false ]; then
        if ! wait_for_node_pods_ready "$node"; then
            log_error "Pods on node $node did not become ready"
            log_warn "Press ENTER to continue anyway, or Ctrl+C to abort..."
            read -r
            log_info "Continuing to next node despite pods not being ready"
        fi
    else
        # Wait a bit before moving to next node to let pods stabilize
        log_info "Waiting 30 seconds for pods to stabilize before next node..."
        sleep 30
    fi
    echo
done

log_info "========================================="
log_info "All nodes rebooted successfully!"
log_info "========================================="
