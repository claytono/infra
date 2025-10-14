#!/usr/bin/env python3
import json
import sys

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} <json_file> <iteration>", file=sys.stderr)
    sys.exit(1)

json_file = sys.argv[1]
iteration = sys.argv[2]

try:
    with open(json_file) as f:
        data = json.load(f)

    bps = data["end"]["sum_sent"]["bits_per_second"]
    gbps = bps / 1000000000
    retrans = data["end"]["sum_sent"]["retransmits"]

    print(f"Iteration {iteration}:")
    print(f"  Bandwidth:    {gbps:.2f} Gbits/sec")
    print(f"  Retransmits:  {retrans}")
    print()

except FileNotFoundError:
    print(f"Error: File not found: {json_file}", file=sys.stderr)
    sys.exit(1)
except json.JSONDecodeError as e:
    print(f"Error: Invalid JSON in {json_file}: {e}", file=sys.stderr)
    sys.exit(1)
except KeyError as e:
    print(f"Error: Missing expected field in JSON: {e}", file=sys.stderr)
    print(f"File: {json_file}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
