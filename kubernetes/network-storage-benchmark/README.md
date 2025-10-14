# Network and Storage Benchmark Suite

Comprehensive benchmarking suite for testing storage (iSCSI and NFS) and network
performance in Kubernetes, designed for evaluating infrastructure upgrades
(e.g., 1G to 10G network migration).

## Prerequisites

- Nix development environment (provides kubectl, python3, jinja2, pre-commit
  tools)
- Access to Kubernetes cluster with worker nodes
- Storage classes configured: `synology-iscsi`, `nfs`, `nfs-slow`

## Quick Start

Typical workflow:

```bash
# Run storage benchmark (auto-selects random worker node, tests all storage types)
./run-benchmark.sh storage

# Run network benchmark (auto-selects random pair of nodes)
./run-benchmark.sh network

# Run network benchmark testing all node pairs with CSV summary
./run-benchmark.sh network --matrix

# Clean up between runs
./run-benchmark.sh cleanup
```

The script automatically:

- Deploys infrastructure (namespace, PVCs, ConfigMaps)
- Runs benchmarks and streams logs
- Copies results to timestamped subdirectories in
  `./results/{type}-{timestamp}/`
- Keeps namespace by default for troubleshooting (use `cleanup` to remove)

Results include `.md` reports, `.csv` data, and `.json` raw output.

### Common Options

```bash
# Run on specific node/nodes
./run-benchmark.sh storage --node k2
./run-benchmark.sh network --source k2 --dest k4

# Test specific storage types
./run-benchmark.sh storage --storage-type iscsi
./run-benchmark.sh storage --storage-type nfs-slow
./run-benchmark.sh storage --storage-type all  # iscsi, nfs, nfs-slow

# Fast mode (1 iteration instead of 3, no warmup)
./run-benchmark.sh storage --fast

# Dev mode (1G files, 10s runtime, 1 iteration, no warmup - for rapid testing)
./run-benchmark.sh storage --dev
```

## Architecture

The benchmark suite consists of two independent test systems:

1. **Storage Benchmarks** - Tests iSCSI and NFS storage performance using fio
2. **Network Benchmarks** - Tests raw network throughput between nodes using
   iperf3

## Storage Benchmarks

### What It Tests

- **Sequential Read/Write** (1M blocks, 32 queue depth, 180s) - Maximum
  throughput
- **Random 4K Read/Write** (4 jobs, 32 queue depth, 180s) - IOPS and latency
- **Mixed 70/30 Read/Write** (4 jobs, 8K blocks, 32 queue depth, 180s) -
  Realistic workload patterns

All tests use a 32GB dataset (4 files × 8GB) that persists across runs for
consistent performance measurement.

### Test Methodology

1. **Warmup Phase**: 1 iteration (discarded) to prime caches and establish
   baseline
   - Skipped in fast/dev modes
2. **Test Phase**: 3 measured iterations of all test patterns (1 in fast/dev
   modes)
3. **Report Generation**: Aggregates results with min/max/avg statistics
4. **File Persistence**: Test files (32GB dataset) persist across runs for
   performance
   - Files reused to avoid recreation overhead
   - Only removed via explicit `./run-benchmark.sh cleanup` command

### Storage Classes Used

- `synology-iscsi` - Fast iSCSI block storage (volume1 SSD) via democratic-csi
- `nfs` - Fast NFS file storage (volume1 SSD) via
  nfs-subdir-external-provisioner
- `nfs-slow` - Slow NFS file storage (volume2 HDD) via
  nfs-subdir-external-provisioner

### Running Storage Benchmarks

The `run-benchmark.sh` script handles infrastructure deployment, job execution,
log streaming, and results retrieval automatically.

#### Storage Type Options

- `iscsi` - iSCSI block storage only
- `nfs` - Fast NFS file storage only
- `nfs-slow` - Slow NFS file storage only
- `all` - All three storage types (default)

#### Test Modes

- **Standard** (default): 1 warmup iteration (discarded) + 3 measured iterations
  - 32GB dataset (4 files × 8GB), 180s per test
- **Fast** (`--fast`): 1 measured iteration, no warmup
  - Same dataset and duration as standard, faster completion
- **Dev** (`--dev`): 1 measured iteration, no warmup
  - 4GB dataset (4 files × 1GB), 10s per test - for rapid testing

#### Examples

```bash
# Test all storage types (iscsi, nfs, nfs-slow)
./run-benchmark.sh storage --storage-type all

# Test only iSCSI on specific node
./run-benchmark.sh storage --storage-type iscsi --node k2

# Fast mode for quick validation
./run-benchmark.sh storage --fast

# Dev mode for rapid iteration during development
./run-benchmark.sh storage --dev

# Comma-separated storage types
./run-benchmark.sh storage --storage-type iscsi,nfs
```

Jobs are deployed using Jinja2 templates (`job-storage-benchmark.yaml.j2`)
rendered at runtime for dynamic node selection and configuration.

## Network Benchmarks

### Network Test Coverage

- Raw TCP throughput between two specific nodes
- Network stability and consistency across multiple runs
- Retransmission rates under load

### Network Test Methodology

1. **Server Setup**: iperf3 server runs continuously on destination node
2. **Warmup Phase**: 1 test (10s, discarded)
3. **Test Phase**: 3 measured tests (30s each)
4. **Report Generation**: Statistics with min/max/avg bandwidth

### Running Network Benchmarks

The `run-benchmark.sh` script handles server deployment, job execution, and
results retrieval automatically.

```bash
# Single test with auto-selected nodes
./run-benchmark.sh network

# Specific node pair
./run-benchmark.sh network --source k2 --dest k4

# Matrix mode - test all node pairs (including k1)
./run-benchmark.sh network --matrix
```

#### Matrix Mode

Matrix mode tests all possible node pairs in your cluster, including the control
plane (k1). Useful for comprehensive network validation before/after upgrades.

For a 4-node cluster (k1, k2, k4, k5), matrix mode runs **12 tests**:

- k1 → k2, k1 → k4, k1 → k5
- k2 → k1, k2 → k4, k2 → k5
- k4 → k1, k4 → k2, k4 → k5
- k5 → k1, k5 → k2, k5 → k4

Results are saved with node pair names in
`./results/network-matrix-{timestamp}/` and a CSV summary file is generated for
easy comparison:

```csv
source,dest,bandwidth_gbps,retransmits
k1,k2,9.85,12
k1,k4,9.92,5
...
```

Jobs are deployed using Jinja2 templates (`job-network-benchmark.yaml.j2`)
rendered at runtime for dynamic node selection.

## Cleanup

Use the cleanup command to properly clean test volumes and remove the namespace:

```bash
./run-benchmark.sh cleanup
```

This performs:

- Runs `fstrim` on iSCSI block devices to reclaim space
- Deletes test files on all PVCs
- Removes namespace and all resources

The namespace is kept by default after benchmark runs for troubleshooting.
Always run cleanup between test runs for consistent results.

## References

- [fio documentation](https://fio.readthedocs.io/)
- [iperf3 documentation](https://iperf.fr/)
- [Kubernetes storage classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [democratic-csi](https://github.com/democratic-csi/democratic-csi)
- [nfs-subdir-external-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner)
