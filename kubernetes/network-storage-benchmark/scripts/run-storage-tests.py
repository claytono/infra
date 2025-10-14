#!/usr/bin/env python3
"""
Storage Benchmark Test Runner

Orchestrates fio benchmark execution, parses results, and generates reports.
"""

import csv
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple


class Config:
    """Test configuration from environment variables."""

    def __init__(self):
        self.storage_type = os.getenv("STORAGE_TYPE", "unknown")
        self.mount_path = Path(os.getenv("MOUNT_PATH", "/mnt/test"))
        self.output_dir = Path(os.getenv("OUTPUT_DIR", "/results"))
        self.fast_mode = os.getenv("FAST_MODE", "false").lower() == "true"
        self.dev_mode = os.getenv("DEV_MODE", "false").lower() == "true"
        self.node_name = os.getenv("NODE_NAME", "unknown")
        self.timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        self.iterations = 1 if (self.fast_mode or self.dev_mode) else 3
        self.fio_jobs_dir = Path("/fio-jobs")

        # Test names
        self.tests = [
            "seq-read",
            "seq-write",
            "rand-4k-read",
            "rand-4k-write",
            "mixed-rw",
        ]

        # Dev mode overrides for fio
        if self.dev_mode:
            self.fio_size = "1G"
            self.fio_runtime = "10"
        else:
            self.fio_size = None
            self.fio_runtime = None

        # Create run output directory
        self.run_output = self.output_dir / f"{self.storage_type}-{self.timestamp}"
        self.run_output.mkdir(parents=True, exist_ok=True)

    def get_json_path(self, test_name: str, iteration: int) -> Path:
        """Get path to JSON results file for a test iteration."""
        return self.run_output / f"{test_name}-iter{iteration}.json"

    def get_report_path(self) -> Path:
        """Get path to markdown report file."""
        return self.run_output / "report.md"

    def get_csv_path(self) -> Path:
        """Get path to CSV results file."""
        return self.run_output / "results.csv"


class FioRunner:
    """Handles fio execution and output processing."""

    def __init__(self, config: Config):
        self.config = config

    def run_test(
        self, test_name: str, iteration: Optional[int] = None
    ) -> Tuple[Path, Path]:
        """
        Run a single fio test.

        Returns:
            Tuple of (json_file_path, txt_file_path)
        """
        if iteration is None:
            base_path = Path(f"/tmp/warmup-{test_name}")
        else:
            base_path = self.config.run_output / f"{test_name}-iter{iteration}"

        all_output = base_path.with_suffix(".all")
        json_output = base_path.with_suffix(".json")
        txt_output = base_path.with_suffix(".txt")

        fio_job = self.config.fio_jobs_dir / f"{test_name}.fio"

        import re

        with open(fio_job, "r") as f:
            job_content = f.read()

        modified = False

        if self.config.dev_mode:
            job_content = re.sub(
                r"^filesize=.*$",
                f"filesize={self.config.fio_size}",
                job_content,
                flags=re.MULTILINE,
            )
            job_content = re.sub(
                r"^runtime=.*$",
                f"runtime={self.config.fio_runtime}",
                job_content,
                flags=re.MULTILINE,
            )
            modified = True

        temp_job = None
        if modified:
            temp_job = Path(
                f"/tmp/{test_name}-{iteration if iteration else 'warmup'}.fio"
            )
            with open(temp_job, "w") as f:
                f.write(job_content)
            fio_job = temp_job

        cmd = [
            "fio",
            str(fio_job),
            f"--directory={self.config.mount_path}",
            "--output-format=json,normal",
            f"--output={all_output}",
            "--eta=always",  # Always show ETA progress
            "--eta-newline=2",  # New line every 2 seconds for readable logs
        ]

        try:
            subprocess.run(cmd, check=True, capture_output=False)
        except subprocess.CalledProcessError as e:
            print(f"Error running fio for {test_name}: {e}", file=sys.stderr)
            print(
                f"Command: {' '.join(cmd)}",
                file=sys.stderr,
            )
            print(
                f"Exit code: {e.returncode}",
                file=sys.stderr,
            )
            raise
        finally:
            # Clean up temporary fio config file
            if temp_job and temp_job.exists():
                temp_job.unlink()

        self._split_output(all_output, json_output, txt_output)

        print(all_output.read_text())

        # Don't clean up test files - they persist across runs for reuse
        # Files are only removed by explicit './run-benchmark.sh cleanup' command

        return json_output, txt_output

    def _split_output(self, all_file: Path, json_file: Path, txt_file: Path):
        """Split combined fio output into JSON and text files."""
        content = all_file.read_text()

        # Find JSON block (starts with { and ends with matching })
        json_start = content.find("{")
        if json_start == -1:
            raise ValueError(f"No JSON found in {all_file}")

        # Parse JSON to find its end
        depth = 0
        json_end = json_start
        in_string = False
        escape_next = False

        for i, char in enumerate(content[json_start:], start=json_start):
            if escape_next:
                escape_next = False
                continue

            if char == "\\":
                escape_next = True
                continue

            if char == '"' and not in_string:
                in_string = True
            elif char == '"' and in_string:
                in_string = False
            elif char == "{" and not in_string:
                depth += 1
            elif char == "}" and not in_string:
                depth -= 1
                if depth == 0:
                    json_end = i + 1
                    break

        # Extract and validate JSON
        json_text = content[json_start:json_end]
        try:
            json_data = json.loads(json_text)
            # Pretty-print JSON
            json_file.write_text(json.dumps(json_data, indent=2))
        except json.JSONDecodeError as e:
            print(f"Warning: Invalid JSON in {all_file}: {e}", file=sys.stderr)
            json_file.write_text(json_text)

        # Save full output as text
        txt_file.write_text(content)


class MetricsExtractor:
    """Extracts and calculates metrics from fio JSON results."""

    @staticmethod
    def extract_metric(json_file: Path, metric_path: str) -> float:
        """Extract a single metric from fio JSON output."""
        try:
            with open(json_file) as f:
                data = json.load(f)

            # Navigate through the JSON path (e.g., "jobs[0].read.iops")
            parts = metric_path.replace("[", ".").replace("]", "").split(".")
            value = data
            for part in parts:
                if part.isdigit():
                    value = value[int(part)]
                else:
                    value = value[part]

            return float(value) if value is not None else 0.0
        except (
            FileNotFoundError,
            json.JSONDecodeError,
            KeyError,
            IndexError,
            TypeError,
        ):
            return 0.0

    @staticmethod
    def calculate_stats(values: List[float]) -> Dict[str, float]:
        """Calculate avg, min, max from a list of values."""
        non_zero = [v for v in values if v != 0]
        if not non_zero:
            return {"avg": 0.0, "min": 0.0, "max": 0.0}

        return {
            "avg": sum(non_zero) / len(non_zero),
            "min": min(non_zero),
            "max": max(non_zero),
        }


class ReportGenerator:
    """Generates Markdown and CSV reports from benchmark results."""

    def __init__(self, config: Config):
        self.config = config
        self.extractor = MetricsExtractor()

    def generate_reports(self):
        """Generate both Markdown and CSV reports."""
        self._generate_markdown()
        self._generate_csv()

    def _get_metrics_for_test(
        self, test_name: str, metric_type: str
    ) -> Dict[str, List[float]]:
        """Get all metrics for a test across iterations."""
        metrics = {"iops": [], "bw_mbps": []}

        for i in range(1, self.config.iterations + 1):
            json_file = self.config.get_json_path(test_name, i)

            # IOPS
            iops = self.extractor.extract_metric(
                json_file, f"jobs.0.{metric_type}.iops"
            )
            metrics["iops"].append(iops)

            # Bandwidth (KB/s -> MB/s)
            bw_kbs = self.extractor.extract_metric(
                json_file, f"jobs.0.{metric_type}.bw"
            )
            metrics["bw_mbps"].append(bw_kbs / 1024)

        return metrics

    def _generate_markdown(self):
        """Generate Markdown report."""
        report_file = self.config.get_report_path()

        with open(report_file, "w") as f:
            # Header
            f.write(f"# Storage Benchmark Report: {self.config.storage_type}\n\n")
            f.write(f"**Timestamp:** {self.config.timestamp}\n")
            f.write(f"**Storage Type:** {self.config.storage_type}\n")
            f.write(f"**Node:** {self.config.node_name}\n\n")

            # Test configuration
            f.write("## Test Configuration\n\n")
            warmup_text = (
                "0 (skipped in fast/dev mode)"
                if (self.config.fast_mode or self.config.dev_mode)
                else "1 (discarded)"
            )
            f.write(f"- Warmup iterations: {warmup_text}\n")
            f.write(f"- Measured iterations: {self.config.iterations}\n")
            f.write("- Test duration: 180 seconds per test\n\n")

            # Results
            f.write("## Results Summary\n\n")

            # Standard tests
            for test in self.config.tests[:-1]:  # All except mixed-rw
                metric_type = "read" if "read" in test else "write"
                self._write_test_section(f, test, metric_type)

            # Mixed workload has both read and write
            f.write("### mixed-rw (read)\n\n")
            self._write_test_metrics(f, "mixed-rw", "read")
            f.write("### mixed-rw (write)\n\n")
            self._write_test_metrics(f, "mixed-rw", "write")

            # Footer
            f.write("\n---\n")
            f.write(
                f"Report generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
            )

        print(f"Report generated: {report_file}")
        return report_file

    def _write_test_section(self, f, test_name: str, metric_type: str):
        """Write a complete test section to markdown file."""
        f.write(f"### {test_name} ({metric_type})\n\n")
        self._write_test_metrics(f, test_name, metric_type)

    def _write_test_metrics(self, f, test_name: str, metric_type: str):
        """Write metrics table for a test."""
        metrics = self._get_metrics_for_test(test_name, metric_type)

        # Table header
        f.write("| Metric | Iter 1 | Iter 2 | Iter 3 | Avg | Min | Max |\n")
        f.write("|--------|--------|--------|--------|-----|-----|-----|\n")

        # IOPS
        iops_stats = self.extractor.calculate_stats(metrics["iops"])
        f.write(f"| IOPS | {metrics['iops'][0]:.0f} | ")
        f.write(f"{metrics['iops'][1]:.0f} | " if len(metrics["iops"]) > 1 else "0 | ")
        f.write(f"{metrics['iops'][2]:.0f} | " if len(metrics["iops"]) > 2 else "0 | ")
        f.write(
            f"{iops_stats['avg']:.0f} | {iops_stats['min']:.0f} | {iops_stats['max']:.0f} |\n"
        )

        # Bandwidth
        bw_stats = self.extractor.calculate_stats(metrics["bw_mbps"])
        f.write(f"| BW (MB/s) | {metrics['bw_mbps'][0]:.2f} | ")
        f.write(
            f"{metrics['bw_mbps'][1]:.2f} | "
            if len(metrics["bw_mbps"]) > 1
            else "0.00 | "
        )
        f.write(
            f"{metrics['bw_mbps'][2]:.2f} | "
            if len(metrics["bw_mbps"]) > 2
            else "0.00 | "
        )
        f.write(
            f"{bw_stats['avg']:.2f} | {bw_stats['min']:.2f} | {bw_stats['max']:.2f} |\n\n"
        )

    def _generate_csv(self):
        """Generate CSV report."""
        csv_file = self.config.get_csv_path()

        # Collect all rows first so we can sort them
        rows = []

        # Standard tests
        for test in self.config.tests[:-1]:
            metric_type = "read" if "read" in test else "write"
            rows.extend(self._get_csv_rows(test, metric_type))

        # Mixed workload
        rows.extend(self._get_csv_rows("mixed-rw", "read"))
        rows.extend(self._get_csv_rows("mixed-rw", "write"))

        # Sort by test_type, then operation
        rows.sort(key=lambda x: (x["test_type"], x["operation"]))

        # Write sorted rows using csv.DictWriter
        with open(csv_file, "w", newline="") as f:
            fieldnames = [
                "test_type",
                "operation",
                "bw_mbps_avg",
                "iops_avg",
                "bw_mbps_min",
                "iops_min",
                "bw_mbps_max",
                "iops_max",
                "bw_mbps_iter1",
                "iops_iter1",
                "bw_mbps_iter2",
                "iops_iter2",
                "bw_mbps_iter3",
                "iops_iter3",
            ]
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

        print(f"CSV report generated: {csv_file}")

    def _get_csv_rows(self, test_name: str, metric_type: str) -> List[Dict[str, str]]:
        """Get CSV rows for a test as a list of dicts."""
        metrics = self._get_metrics_for_test(test_name, metric_type)

        # Extract test type from test_name (seq, rand, mixed)
        test_type = test_name.split("-")[0]

        # Calculate statistics
        iops_stats = self.extractor.calculate_stats(metrics["iops"])
        bw_stats = self.extractor.calculate_stats(metrics["bw_mbps"])

        # Create single row with both IOPS and bandwidth
        row = {
            "test_type": test_type,
            "operation": metric_type,
            # Aggregated metrics first
            "iops_avg": f"{iops_stats['avg']:.0f}",
            "iops_min": f"{iops_stats['min']:.0f}",
            "iops_max": f"{iops_stats['max']:.0f}",
            "bw_mbps_avg": f"{bw_stats['avg']:.2f}",
            "bw_mbps_min": f"{bw_stats['min']:.2f}",
            "bw_mbps_max": f"{bw_stats['max']:.2f}",
            # Per-iteration metrics at the end
            "iops_iter1": f"{metrics['iops'][0]:.0f}",
            "iops_iter2": f"{metrics['iops'][1]:.0f}"
            if len(metrics["iops"]) > 1
            else "0",
            "iops_iter3": f"{metrics['iops'][2]:.0f}"
            if len(metrics["iops"]) > 2
            else "0",
            "bw_mbps_iter1": f"{metrics['bw_mbps'][0]:.2f}",
            "bw_mbps_iter2": f"{metrics['bw_mbps'][1]:.2f}"
            if len(metrics["bw_mbps"]) > 1
            else "0.00",
            "bw_mbps_iter3": f"{metrics['bw_mbps'][2]:.2f}"
            if len(metrics["bw_mbps"]) > 2
            else "0.00",
        }

        return [row]


def main():
    """Main entry point."""
    # Load configuration
    config = Config()

    print("=" * 40)
    print("Storage Benchmark Test Runner")
    print(f"Storage Type: {config.storage_type}")
    print(f"Mount Path: {config.mount_path}")

    if config.dev_mode:
        print("Dev Mode: enabled (1G files, 10s runtime, 1 iteration, no warmup)")
    elif config.fast_mode:
        print(f"Fast Mode: enabled ({config.iterations} iteration(s))")
    else:
        print(f"Standard Mode: {config.iterations} iterations with warmup")

    print(f"Timestamp: {config.timestamp}")
    print("=" * 40)

    # Initialize runner
    runner = FioRunner(config)

    # Run warmup (skip in fast mode or dev mode)
    if not config.fast_mode and not config.dev_mode:
        print("\n=== Running Warmup Iteration ===")
        for test in config.tests:
            print(f"Warmup: {test}")
            runner.run_test(test, iteration=None)
    else:
        mode = "dev mode" if config.dev_mode else "fast mode"
        print(f"\n=== Skipping Warmup ({mode}) ===")

    # Run measured iterations
    for iteration in range(1, config.iterations + 1):
        print(f"\n=== Running Measured Iteration {iteration}/{config.iterations} ===")
        for test in config.tests:
            print(f"Iteration {iteration}: {test}")
            runner.run_test(test, iteration=iteration)

    print("\n=== Test Run Complete ===")
    print(f"Results stored in: {config.run_output}")

    # Generate reports
    print("\n=== Generating Reports ===")
    report_gen = ReportGenerator(config)
    report_gen.generate_reports()

    # Show preview
    report_file = config.get_report_path()
    print("\n=== Report Preview ===")
    lines = report_file.read_text().split("\n")
    for line in lines[:50]:
        print(line)

    print("\n=== Benchmark Complete ===")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
