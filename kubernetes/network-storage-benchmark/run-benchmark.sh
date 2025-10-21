#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="network-storage-benchmark"

readonly TIMEOUT_POD_READY=180  # iSCSI volumes can take 1-2 minutes to attach
readonly TIMEOUT_PVC_BOUND=120
readonly TIMEOUT_JOB_COMPLETE=600
readonly TIMEOUT_DEPLOYMENT=120
readonly TIMEOUT_NAMESPACE_DELETE=60

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage: $0 [storage|network|cleanup] [OPTIONS]

Run Kubernetes storage or network benchmarks and cleanup afterwards.

Commands:
  storage         Run storage (fio) benchmarks for iSCSI and NFS
  network         Run network (iperf3) benchmarks between two nodes
  cleanup         Clean test volumes, trim iSCSI volumes, and delete namespace

Storage Options:
  --node NODE          Pin benchmark to specific node (e.g., k2, k4, k5)
                       If not specified, automatically selects a worker node (excludes k1)
  --storage-type TYPE  Storage type(s) to test (default: all)
                       Options: iscsi, nfs, nfs-slow, all
                       Or comma-separated list: iscsi,nfs-slow

Network Options:
  --source NODE   Source node for network test (optional)
                  If not specified, automatically selects a worker node (excludes k1)
  --dest NODE     Destination node for network test (optional)
                  If not specified, automatically selects a different worker node
  --matrix        Test all node pairs including k1 (runs multiple tests)

General Options:
  --keep-namespace    Keep namespace after completion (default, for troubleshooting)
  --results-dir DIR   Local directory to save results (default: ./results)
  --fast              Run only 1 iteration instead of 3 (for storage tests)
  --dev               Dev mode: 1G files, 1 iteration, no warmup, 10s runtime
  --help              Show this help message

Note: Namespace is kept by default. Use './run-benchmark.sh cleanup' to clean up between runs.

Examples:
  # Clean up from previous runs (required before starting new tests)
  $0 cleanup

  # Run storage benchmark (auto-selects worker node)
  $0 storage

  # Run storage benchmark on specific node
  $0 storage --node k2

  # Run only iSCSI benchmark
  $0 storage --storage-type iscsi

  # Run only NFS benchmark in fast mode
  $0 storage --storage-type nfs --fast
  $0 storage --storage-type iscsi --dev

  # Run slow storage benchmarks
  $0 storage --storage-type nfs-slow

  # Run all storage types
  $0 storage --storage-type all

  # Run network benchmark (auto-selects two different worker nodes)
  $0 network

  # Run network benchmark from k2 to k4
  $0 network --source k2 --dest k4

  # Run network benchmark with only source specified (auto-selects dest)
  $0 network --source k2

  # Run network benchmark matrix (all node pairs)
  $0 network --matrix

  # Clean up test volumes and delete namespace
  $0 cleanup

  # Keep namespace for manual inspection
  $0 storage --node k2 --keep-namespace

EOF
  exit 1
}

log() {
  echo -e "${BLUE}==>${NC} $*"
}

log_success() {
  echo -e "${GREEN}✓${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}!${NC} $*"
}

wait_for_job() {
  local job_name=$1
  local namespace=$2
  local timeout=${3:-${TIMEOUT_JOB_COMPLETE}}

  log "Waiting for job ${job_name} to complete (timeout: ${timeout}s)..."

  local elapsed=0
  local interval=5

  while [ "$elapsed" -lt "$timeout" ]; do
    if kubectl get job "${job_name}" -n "${namespace}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null | grep -q "True"; then
      log_success "Job completed successfully"
      return 0
    fi

    if kubectl get job "${job_name}" -n "${namespace}" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null | grep -q "True"; then
      log_error "Job failed"

      echo ""
      log "Pod logs:"
      kubectl logs -n "${namespace}" "job/${job_name}" --tail=50 2>/dev/null || true

      return 1
    fi

    local pod_status=$(kubectl get pods -n "${namespace}" -l "job-name=${job_name}" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    if [ "$pod_status" = "Failed" ] || [ "$pod_status" = "Error" ]; then
      log_error "Job pod is in ${pod_status} state"

      echo ""
      log "Pod logs:"
      kubectl logs -n "${namespace}" -l "job-name=${job_name}" --tail=50 2>/dev/null || true

      return 1
    fi

    sleep $interval
    elapsed=$((elapsed + interval))
  done

  log_error "Job timed out after ${timeout}s"
  return 1
}

stream_job_logs() {
  local job_name=$1
  local namespace=$2
  local label_selector=$3

  echo ""
  log "Streaming ${job_name} logs..."

  # First wait for pod to be created (kubectl wait fails immediately if no resources match)
  local waited=0
  local pod_name=""
  while [ -z "$pod_name" ] && [ "$waited" -lt "${TIMEOUT_POD_READY}" ]; do
    pod_name=$(kubectl get pods -n "${namespace}" -l "${label_selector}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -z "$pod_name" ]; then
      sleep 2
      waited=$((waited + 2))
    fi
  done

  if [ -z "$pod_name" ]; then
    log_error "Pod was not created within ${TIMEOUT_POD_READY}s"
    return 1
  fi

  log "Pod ${pod_name} created, waiting for it to be ready..."

  if ! kubectl wait --for=condition=Ready pod/"${pod_name}" -n "${namespace}" --timeout="${TIMEOUT_POD_READY}s" 2>/dev/null; then
    log_error "Pod did not become ready within ${TIMEOUT_POD_READY}s"
    return 1
  fi

  while true; do
    if ! kubectl get pod "${pod_name}" -n "${namespace}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
      log "Pod completed, log streaming finished"
      break
    fi

    kubectl logs -n "${namespace}" "$pod_name" -f --all-containers 2>&1 || true

    sleep 1
  done

  return 0
}

get_alpine_image() {
  # Extract alpine image version from kustomization.yaml
  local image_name
  image_name=$(yq eval \
    '.images[] | select(.name == "alpine") | .name + ":" + .newTag' \
    "${SCRIPT_DIR}/kustomization.yaml")

  if [ -z "$image_name" ]; then
    log_error "Alpine image not found in kustomization.yaml"
    log_error "Expected 'images' section with 'name: alpine' entry"
    exit 1
  fi

  echo "$image_name"
}

render_storage_job_template() {
  local storage_type=$1
  local node_name=$2
  local fast_mode=$3
  local dev_mode=$4
  local alpine_image=$(get_alpine_image)
  local template_file="${SCRIPT_DIR}/job-storage-benchmark.yaml.j2"

  python3 - <<EOF
import sys
from jinja2 import Template

template_file = "${template_file}"
with open(template_file, 'r') as f:
    template = Template(f.read())

rendered = template.render(
    storage_type="${storage_type}",
    node_name="${node_name}",
    fast_mode="${fast_mode}",
    dev_mode="${dev_mode}",
    alpine_image="${alpine_image}"
)

print(rendered)
EOF
}

render_network_job_template() {
  local source_node=$1
  local dest_node=$2
  local alpine_image=$(get_alpine_image)
  local template_file="${SCRIPT_DIR}/job-network-benchmark.yaml.j2"

  python3 - <<EOF
import sys
from jinja2 import Template

template_file = "${template_file}"
with open(template_file, 'r') as f:
    template = Template(f.read())

rendered = template.render(
    source_node="${source_node}",
    dest_node="${dest_node}",
    alpine_image="${alpine_image}"
)

print(rendered)
EOF
}

wait_for_deployment() {
  local deployment_name=$1
  local namespace=$2
  local timeout=${3:-${TIMEOUT_DEPLOYMENT}}

  log "Waiting for deployment ${deployment_name} to be ready..."

  if kubectl wait --for=condition=available --timeout="${timeout}s" "deployment/${deployment_name}" -n "${namespace}" 2>/dev/null; then
    log_success "Deployment ready"
    return 0
  else
    log_error "Deployment failed to become ready"
    return 1
  fi
}

copy_results() {
  local namespace=$1
  local results_dir=$2
  local storage_type=$3

  log "Copying results from cluster..."

  local pod="results-copy-$(date +%s)"
  local alpine_image=$(get_alpine_image)
  local template_file="${SCRIPT_DIR}/pod-results-copy.yaml.j2"

  if python3 - <<EOF | kubectl apply -n "${namespace}" -f - >/dev/null 2>&1
from jinja2 import Template
with open("${template_file}", 'r') as f:
    template = Template(f.read())
print(template.render(pod_name="${pod}", alpine_image="${alpine_image}"))
EOF
  then
    log "Created results-copy pod: ${pod}"
  else
    log_error "Failed to create results-copy pod"
    return 1
  fi

  # Wait for pod to be ready
  if ! kubectl wait --for=condition=Ready pod/"${pod}" -n "${namespace}" --timeout=30s >/dev/null 2>&1; then
    log_error "Results-copy pod failed to become ready"
    kubectl delete pod "${pod}" -n "${namespace}" --wait=false >/dev/null 2>&1 || true
    return 1
  fi

  # Find the most recent subdirectory for this storage type
  local latest_subdir
  latest_subdir=$(kubectl exec -n "${namespace}" "${pod}" -- sh -c "ls -td /results/${storage_type}-* 2>/dev/null | head -1" 2>/dev/null | tr -d '\r')

  if [ -z "${latest_subdir}" ]; then
    log_error "No results subdirectory found for ${storage_type}"
    kubectl delete pod "${pod}" -n "${namespace}" --wait=false >/dev/null 2>&1 || true
    return 1
  fi

  log "Found results in: ${latest_subdir}"

  # Create local results directory
  mkdir -p "${results_dir}"

  # Copy only the specific subdirectory for this run
  log "Copying ${storage_type} results to ${results_dir}..."
  # Extract just the directory name from the path
  local subdir_name
  subdir_name=$(basename "${latest_subdir}")

  # Copy the directory (without trailing slash to preserve directory structure)
  if ! kubectl cp "${namespace}/${pod}:${latest_subdir}" "${results_dir}/${subdir_name}" 2>&1; then
    log_error "Failed to copy results from pod"
    log_error "Check pod logs: kubectl logs -n ${namespace} ${pod}"
    kubectl delete pod "${pod}" -n "${namespace}" --wait=false >/dev/null 2>&1 || true
    return 1
  fi

  # Check if we got files and list them
  local file_count
  file_count=$(find "${results_dir}/${subdir_name}" -type f \( -name "*.md" -o -name "*.csv" -o -name "*.json" \) 2>/dev/null | wc -l)

  if [ "$file_count" -gt 0 ]; then
    echo ""
    log_success "Results saved to directory: ${results_dir}/${subdir_name}"
    echo ""
    log "Result files:"
    find "${results_dir}/${subdir_name}" -type f \( -name "*.md" -o -name "*.csv" -o -name "*.json" \) | sed 's/^/  /' | head -20
  else
    log_warn "No result files found after copy"
  fi

  # Cleanup results-copy pod
  kubectl delete pod "${pod}" -n "${namespace}" --wait=false >/dev/null 2>&1 || true
}

cleanup_namespace() {
  local namespace=$1

  log "Cleaning up namespace ${namespace}..."
  kubectl delete namespace "${namespace}" --wait=false 2>/dev/null || true
  log_success "Namespace deletion initiated"
}

wait_for_namespace_deletion() {
  local namespace=$1
  local waited=0

  while kubectl get namespace "${namespace}" 2>/dev/null; do
    sleep 2
    waited=$((waited + 2))
    if [ "$waited" -ge "${TIMEOUT_NAMESPACE_DELETE}" ]; then
      log_error "Namespace deletion timeout after ${TIMEOUT_NAMESPACE_DELETE}s"
      return 1
    fi
  done
  log_success "Namespace cleaned up"
  return 0
}

ensure_clean_namespace() {
  local namespace=$1

  if kubectl get namespace "${namespace}" &>/dev/null; then
    log "Cleaning up existing namespace..."
    cleanup_namespace "${namespace}"
    wait_for_namespace_deletion "${namespace}"
  fi
}

run_storage_benchmark() {
  local node=$1
  local keep_namespace=$2
  local results_dir=$3
  local fast_mode=$4
  local storage_type_filter=$5
  local dev_mode=$6

  log "Starting storage benchmark"

  # Delete existing namespace if it exists (to start fresh)
  ensure_clean_namespace "${NAMESPACE}"

  # If no node specified, pick a random worker node (not k1 control plane)
  if [ -z "$node" ]; then
    log "No node specified, selecting a worker node..."
    node=$(kubectl get nodes --no-headers | grep -v "^k1 " | grep "Ready" | awk '{print $1}' | shuf | head -1)
    if [ -z "$node" ]; then
      log_error "Could not find any available worker nodes"
      return 1
    fi
    log "Auto-selected node: ${node}"
  else
    log "Target node: ${node}"
  fi

  # Deploy infrastructure
  log "Deploying infrastructure..."
  kubectl apply -k "${SCRIPT_DIR}/" >/dev/null

  # Determine which storage types to test
  local storage_types=()
  case "${storage_type_filter}" in
    iscsi)
      storage_types=("iscsi")
      ;;
    nfs)
      storage_types=("nfs")
      ;;
    nfs-slow)
      storage_types=("nfs-slow")
      ;;
    all|"")
      storage_types=("iscsi" "nfs" "nfs-slow")
      ;;
    *)
      # Try parsing as comma-separated list
      if [[ "${storage_type_filter}" == *,* ]]; then
        IFS=',' read -ra storage_types <<< "${storage_type_filter}"
        # Validate each type
        for type in "${storage_types[@]}"; do
          if [[ ! "${type}" =~ ^(iscsi|nfs|nfs-slow)$ ]]; then
            log_error "Invalid storage type in list: ${type}"
            log_error "Valid types: iscsi, nfs, nfs-slow"
            return 1
          fi
        done
      else
        log_error "Invalid storage type: ${storage_type_filter}"
        log_error "Valid options: 'iscsi', 'nfs', 'nfs-slow', 'all', or comma-separated list"
        return 1
      fi
      ;;
  esac

  # Wait for PVCs to be bound
  log "Waiting for PVCs to be bound..."
  for storage_type in "${storage_types[@]}"; do
    kubectl wait --for=jsonpath='{.status.phase}'=Bound "pvc/network-storage-benchmark-${storage_type}" -n "${NAMESPACE}" --timeout="${TIMEOUT_PVC_BOUND}s" >/dev/null
  done
  kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/network-storage-benchmark-results -n "${NAMESPACE}" --timeout="${TIMEOUT_PVC_BOUND}s" >/dev/null
  log_success "PVCs ready"

  # Run benchmarks for each storage type
  for storage_type in "${storage_types[@]}"; do
    [ "$storage_type" != "iscsi" ] && echo ""

    log "Starting ${storage_type} benchmark..."
    render_storage_job_template "${storage_type}" "${node}" "${fast_mode}" "${dev_mode}" | kubectl apply -n "${NAMESPACE}" -f - >/dev/null
    log_success "${storage_type} job created"

    # Stream logs until pod exits naturally
    stream_job_logs "storage-benchmark-${storage_type}" "${NAMESPACE}" "storage-type=${storage_type}"

    # Wait for job to be marked complete
    echo ""
    if ! wait_for_job "storage-benchmark-${storage_type}" "${NAMESPACE}"; then
      log_error "${storage_type} benchmark failed"

      # Show pod status
      echo ""
      log "Pod status:"
      kubectl get pods -n "${NAMESPACE}"

      echo ""
      log "Recent events:"
      kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' | tail -20

      [ "$keep_namespace" = "false" ] && cleanup_namespace "${NAMESPACE}"
      return 1
    fi

    # Copy results using dedicated pod
    echo ""
    copy_results "${NAMESPACE}" "${results_dir}" "${storage_type}"

    log_success "${storage_type} benchmark completed"
  done

  # All benchmarks completed successfully
  echo ""
  log_success "Storage benchmarks completed!"

  # Cleanup
  if [ "$keep_namespace" = "false" ]; then
    echo ""
    cleanup_namespace "${NAMESPACE}"
  else
    log_warn "Namespace kept for manual inspection"
    echo ""
    log "To view results: kubectl exec -n ${NAMESPACE} -it deployment/iperf-server -- ls /results/"
    log "To cleanup later: kubectl delete namespace ${NAMESPACE}"
  fi

  return 0
}

run_network_benchmark() {
  local source_node=$1
  local dest_node=$2
  local keep_namespace=$3
  local results_dir=$4

  log "Starting network benchmark"

  # Delete existing namespace if it exists (to start fresh)
  ensure_clean_namespace "${NAMESPACE}"

  # Get available worker nodes (excluding k1 and disabled nodes)
  local available_nodes
  available_nodes=$(kubectl get nodes --no-headers | grep -v "^k1 " | grep "Ready" | grep -v "SchedulingDisabled" | awk '{print $1}' | shuf)

  if [ -z "$available_nodes" ]; then
    log_error "Could not find any available worker nodes"
    return 1
  fi

  # Auto-select source node if not specified
  if [ -z "$source_node" ]; then
    source_node=$(echo "$available_nodes" | head -1)
    log "Auto-selected source node: ${source_node}"
  else
    log "Source node: ${source_node}"
  fi

  # Auto-select destination node if not specified (different from source)
  if [ -z "$dest_node" ]; then
    dest_node=$(echo "$available_nodes" | grep -v "^${source_node}$" | head -1)
    if [ -z "$dest_node" ]; then
      log_error "Could not find a second worker node for destination (need at least 2 nodes)"
      return 1
    fi
    log "Auto-selected destination node: ${dest_node}"
  else
    log "Destination node: ${dest_node}"
  fi

  # Deploy infrastructure
  log "Deploying infrastructure..."
  kubectl apply -k "${SCRIPT_DIR}/" >/dev/null
  kubectl apply -n "${NAMESPACE}" -f "${SCRIPT_DIR}/network-benchmark-server.yaml" >/dev/null

  # Wait for PVCs
  log "Waiting for results PVC..."
  kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/network-storage-benchmark-results -n "${NAMESPACE}" --timeout="${TIMEOUT_PVC_BOUND}s" >/dev/null
  log_success "PVC ready"

  # Update server deployment with destination node and wait for it to roll out
  log "Deploying iperf3 server on ${dest_node}..."
  kubectl patch deployment iperf-server -n "${NAMESPACE}" --type=json -p="[
    {\"op\": \"add\", \"path\": \"/spec/template/spec/nodeSelector\", \"value\": {\"kubernetes.io/hostname\": \"${dest_node}\"}}
  ]" >/dev/null

  if ! wait_for_deployment "iperf-server" "${NAMESPACE}" 120; then
    log_error "Server deployment failed"
    [ "$keep_namespace" = "false" ] && cleanup_namespace "${NAMESPACE}"
    return 1
  fi

  # Delete any existing job first (jobs are immutable)
  kubectl delete job network-benchmark -n "${NAMESPACE}" --ignore-not-found=true >/dev/null 2>&1

  # Create client job with source node and dest node
  log "Creating client job on ${source_node}..."
  render_network_job_template "${source_node}" "${dest_node}" | kubectl apply -n "${NAMESPACE}" -f - >/dev/null
  log_success "Job created"

  # Stream logs until job completes
  echo ""
  if ! stream_job_logs "network-benchmark" "${NAMESPACE}" "app=network-benchmark"; then
    log_warn "Log streaming ended (pod may have completed)"
  fi

  # Wait for completion
  echo ""
  if wait_for_job "network-benchmark" "${NAMESPACE}"; then
    log_success "Network benchmark completed!"

    # Copy results
    echo ""
    copy_results "${NAMESPACE}" "${results_dir}" "network"

    # Cleanup
    if [ "$keep_namespace" = "false" ]; then
      echo ""
      cleanup_namespace "${NAMESPACE}"
    else
      log_warn "Namespace kept for manual inspection"
      echo ""
      log "To view results: kubectl exec -n ${NAMESPACE} -it deployment/iperf-server -- ls /results/"
      log "To cleanup later: kubectl delete namespace ${NAMESPACE}"
    fi

    return 0
  else
    log_error "Network benchmark failed"

    # Show pod status
    echo ""
    log "Pod status:"
    kubectl get pods -n "${NAMESPACE}"

    if [ "$keep_namespace" = "false" ]; then
      echo ""
      cleanup_namespace "${NAMESPACE}"
    fi

    return 1
  fi
}

run_network_matrix_benchmark() {
  local keep_namespace=$1
  local results_dir=$2

  # Get all nodes including k1
  local all_nodes
  all_nodes=$(kubectl get nodes --no-headers | grep "Ready" | awk '{print $1}' | sort)

  if [ -z "$all_nodes" ]; then
    log_error "Could not find any ready nodes"
    return 1
  fi

  local node_array
  IFS=$'\n' read -rd '' -a node_array <<< "$all_nodes" || true
  local total_tests=$(( ${#node_array[@]} * (${#node_array[@]} - 1) ))
  local test_num=0
  local failed_tests=0
  local timestamp=$(date +%Y%m%d-%H%M%S)
  local csv_file="${results_dir}/matrix-${timestamp}.csv"

  log "Matrix mode: Testing all node pairs (${total_tests} tests)"
  log "Results will be saved to: ${csv_file}"
  echo ""

  # Create CSV header
  mkdir -p "${results_dir}"
  echo "Source,Destination,Bandwidth_Gbps_Iter1,Bandwidth_Gbps_Iter2,Bandwidth_Gbps_Iter3,Bandwidth_Gbps_Avg,Retransmits_Iter1,Retransmits_Iter2,Retransmits_Iter3,Status" > "${csv_file}"

  # Test all pairs (excluding self-to-self)
  for src in "${node_array[@]}"; do
    for dst in "${node_array[@]}"; do
      if [ "$src" != "$dst" ]; then
        test_num=$((test_num + 1))
        echo ""
        log "========================================="
        log "Test ${test_num}/${total_tests}: ${src} -> ${dst}"
        log "========================================="

        if run_network_benchmark "$src" "$dst" "$keep_namespace" "$results_dir"; then
          log_success "Test ${test_num}/${total_tests} completed successfully"

          # Extract results from the most recent test report
          local report_file=$(find "${results_dir}" -name "network-${src}-to-${dst}-*-report.txt" -type f | sort | tail -1)

          if [ -f "$report_file" ]; then
            # Parse bandwidth and retransmits from report
            local bw1=$(grep "Iteration 1:" -A1 "$report_file" | grep "Bandwidth:" | awk '{print $2}')
            local bw2=$(grep "Iteration 2:" -A1 "$report_file" | grep "Bandwidth:" | awk '{print $2}')
            local bw3=$(grep "Iteration 3:" -A1 "$report_file" | grep "Bandwidth:" | awk '{print $2}')
            local ret1=$(grep "Iteration 1:" -A2 "$report_file" | grep "Retransmits:" | awk '{print $2}')
            local ret2=$(grep "Iteration 2:" -A2 "$report_file" | grep "Retransmits:" | awk '{print $2}')
            local ret3=$(grep "Iteration 3:" -A2 "$report_file" | grep "Retransmits:" | awk '{print $2}')

            # Calculate average bandwidth
            local bw_avg=$(echo "scale=2; ($bw1 + $bw2 + $bw3) / 3" | bc 2>/dev/null || echo "0.00")

            # Add to CSV
            echo "${src},${dst},${bw1},${bw2},${bw3},${bw_avg},${ret1},${ret2},${ret3},SUCCESS" >> "${csv_file}"
          else
            echo "${src},${dst},,,,,,,FAILED" >> "${csv_file}"
          fi
        else
          log_error "Test ${test_num}/${total_tests} failed"
          failed_tests=$((failed_tests + 1))
          echo "${src},${dst},,,,,,,FAILED" >> "${csv_file}"
        fi
      fi
    done
  done

  echo ""
  log "========================================="
  log "Matrix test complete"
  log "Total tests: ${total_tests}"
  log "Successful: $((total_tests - failed_tests))"
  log "Failed: ${failed_tests}"
  log "========================================="
  echo ""
  log "CSV results saved to: ${csv_file}"
  echo ""
  log "Summary table:"
  column -t -s',' "${csv_file}" | head -20

  [ "$failed_tests" -eq 0 ]
}

run_cleanup() {
  log "==> Running comprehensive cleanup"

  # Deploy infrastructure to ensure namespace and PVCs exist
  log "==> Deploying infrastructure..."
  kubectl apply -k "${SCRIPT_DIR}/" >/dev/null 2>&1

  # Wait for PVCs to be bound
  log "==> Waiting for PVCs to be bound..."
  local storage_types=("iscsi" "nfs" "nfs-slow" "results")
  local all_bound=true

  for storage_type in "${storage_types[@]}"; do
    local pvc_name="network-storage-benchmark-${storage_type}"

    if ! kubectl get pvc -n "${NAMESPACE}" "${pvc_name}" &>/dev/null; then
      log_error "PVC ${pvc_name} does not exist"
      all_bound=false
      continue
    fi

    if ! kubectl wait --for=jsonpath='{.status.phase}'=Bound \
         pvc/"${pvc_name}" -n "${NAMESPACE}" \
         --timeout="${TIMEOUT_PVC_BOUND}s" >/dev/null 2>&1; then
      log_error "PVC ${pvc_name} failed to bind"
      all_bound=false
    else
      log_success "PVC ${pvc_name} is bound"
    fi
  done

  if [ "$all_bound" = "false" ]; then
    log_error "Some PVCs failed to bind, continuing with cleanup of bound volumes..."
  fi

  log "==> Cleaning test volumes and trimming iSCSI storage"

  # Remove results from cleanup list (only clean storage PVCs)
  local storage_types=("iscsi" "nfs" "nfs-slow")

  for storage_type in "${storage_types[@]}"; do
    local pvc_name="network-storage-benchmark-${storage_type}"

    # Check if PVC is bound
    local pvc_status=$(kubectl get pvc -n "${NAMESPACE}" "${pvc_name}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "${pvc_status}" != "Bound" ]; then
      log "PVC ${pvc_name} is ${pvc_status}, skipping cleanup"
      continue
    fi

    log "Cleaning ${storage_type} volume..."

    local fstrim_cmd=""
    if [[ "${storage_type}" == iscsi* ]]; then
      fstrim_cmd="echo 'Running fstrim...'; fstrim -v /mnt/storage || true;"
    fi

    # Cleanup pod requires privileged mode for fstrim on iSCSI block devices
    local cleanup_pod="cleanup-${storage_type}-$(date +%s)"
    kubectl run "${cleanup_pod}" \
      -n "${NAMESPACE}" \
      --image=alpine:3.18 \
      --restart=Never \
      --overrides="{
        \"spec\": {
          \"containers\": [{
            \"name\": \"cleanup\",
            \"image\": \"alpine:3.18\",
            \"command\": [\"/bin/sh\", \"-c\"],
            \"args\": [\"echo 'Cleaning volume...'; find /mnt/storage -mindepth 1 -delete 2>&1 || true; df -h /mnt/storage; ${fstrim_cmd}\"],
            \"volumeMounts\": [{
              \"name\": \"storage\",
              \"mountPath\": \"/mnt/storage\"
            }],
            \"securityContext\": {
              \"privileged\": true
            }
          }],
          \"volumes\": [{
            \"name\": \"storage\",
            \"persistentVolumeClaim\": {
              \"claimName\": \"${pvc_name}\"
            }
          }]
        }
      }"

    if kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/"${cleanup_pod}" -n "${NAMESPACE}" --timeout=180s; then
      echo ""
      kubectl logs -n "${NAMESPACE}" "${cleanup_pod}"
      kubectl delete pod -n "${NAMESPACE}" "${cleanup_pod}" --wait=false 2>&1 || true
      log_success "Cleaned ${storage_type} volume"
    else
      log_error "Failed to clean ${storage_type} volume"
      echo ""
      log "Pod status:"
      kubectl get pod "${cleanup_pod}" -n "${NAMESPACE}"
      echo ""
      log "Pod logs (if available):"
      kubectl logs -n "${NAMESPACE}" "${cleanup_pod}" 2>&1 || echo "No logs available"
      echo ""
      log "Pod events:"
      kubectl describe pod "${cleanup_pod}" -n "${NAMESPACE}" | grep -A 20 Events:
      kubectl delete pod -n "${NAMESPACE}" "${cleanup_pod}" --wait=false 2>&1 || true
    fi
  done

  log "==> Deleting namespace"
  cleanup_namespace "${NAMESPACE}"
  wait_for_namespace_deletion "${NAMESPACE}"

  log_success "Cleanup complete"
}

main() {
  for cmd in kubectl python3; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Required tool not found: ${cmd}"
      exit 1
    fi
  done

  if ! python3 -c "import jinja2" 2>/dev/null; then
    log_error "Python library 'jinja2' not found."
    log_error ""
    log_error "This repository uses a Nix development environment."
    log_error "Please restart Claude Code in the nix develop shell."
    log_error ""
    log_error "Alternatively, install manually: pip3 install jinja2"
    exit 1
  fi

  if [ $# -eq 0 ]; then
    usage
  fi

  local command=$1
  shift

  # Parse options
  local node=""
  local source_node=""
  local dest_node=""
  local keep_namespace="true"  # Default to keeping namespace for troubleshooting
  local fast_mode="false"
  local dev_mode="false"
  local results_dir="${SCRIPT_DIR}/results"
  local matrix_mode="false"
  local storage_type_filter="all"

  while [ $# -gt 0 ]; do
    case $1 in
      --node)
        node=$2
        shift 2
        ;;
      --source)
        source_node=$2
        shift 2
        ;;
      --dest)
        dest_node=$2
        shift 2
        ;;
      --storage-type)
        storage_type_filter=$2
        shift 2
        ;;
      --matrix)
        matrix_mode="true"
        shift
        ;;
      --keep-namespace)
        keep_namespace="true"
        shift
        ;;
      --fast)
        fast_mode="true"
        shift
        ;;
      --dev)
        dev_mode="true"
        shift
        ;;
      --results-dir)
        results_dir=$2
        shift 2
        ;;
      --help)
        usage
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        ;;
    esac
  done

  case $command in
    storage)
      run_storage_benchmark "$node" "$keep_namespace" "$results_dir" "$fast_mode" "$storage_type_filter" "$dev_mode"
      ;;
    network)
      if [ "$matrix_mode" = "true" ]; then
        run_network_matrix_benchmark "$keep_namespace" "$results_dir"
      else
        run_network_benchmark "$source_node" "$dest_node" "$keep_namespace" "$results_dir"
      fi
      ;;
    cleanup)
      run_cleanup
      ;;
    *)
      log_error "Unknown command: ${command}"
      usage
      ;;
  esac
}

main "$@"
