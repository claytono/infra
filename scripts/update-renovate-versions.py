#!/usr/bin/env python3
"""
Update Renovate version constraints based on endoflife.date and PyPI data.

Rules:
- MariaDB: LTS releases at least 6 months old
- PostgreSQL: Major versions at least 6 months old
- Kubernetes: Latest version minus 1 (N-1)
- Home Assistant: One month behind latest stable (YYYY.MM format)
- ESPHome: One month behind latest stable (YYYY.MM format)
"""

import json
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path
from urllib.request import urlopen
from urllib.error import URLError


def fetch_json(url: str) -> dict | list | None:
    """Fetch JSON from a URL."""
    try:
        with urlopen(url, timeout=30) as response:
            return json.loads(response.read().decode())
    except URLError as e:
        print(f"Error fetching {url}: {e}", file=sys.stderr)
        return None


def get_mariadb_allowed_versions() -> str | None:
    """Get MariaDB LTS versions at least 6 months old and not EOL."""
    data = fetch_json("https://endoflife.date/api/mariadb.json")
    if not data:
        return None

    now = datetime.now()
    six_months_ago = now - timedelta(days=180)
    lts_cycles = []

    for release in data:
        if not release.get("lts"):
            continue
        # Skip EOL'd versions (eol can be true, false, or a date string)
        eol = release.get("eol")
        if eol is True:
            continue
        if eol:
            eol_date = datetime.strptime(eol, "%Y-%m-%d")
            if eol_date < now:
                continue
        release_date = datetime.strptime(release["releaseDate"], "%Y-%m-%d")
        if release_date <= six_months_ago:
            # Escape dots for regex
            cycle = release["cycle"].replace(".", "\\.")
            lts_cycles.append(cycle)

    if not lts_cycles:
        print("Warning: No MariaDB LTS versions found >= 6 months old", file=sys.stderr)
        return None

    return f"/^({"|".join(lts_cycles)})\\./"


def get_postgresql_allowed_versions() -> str | None:
    """Get PostgreSQL major versions at least 6 months old and not EOL."""
    data = fetch_json("https://endoflife.date/api/postgresql.json")
    if not data:
        return None

    now = datetime.now()
    six_months_ago = now - timedelta(days=180)
    cycles = []

    for release in data:
        # Skip EOL'd versions (eol can be true, false, or a date string)
        eol = release.get("eol")
        if eol is True:
            continue
        if eol:
            eol_date = datetime.strptime(eol, "%Y-%m-%d")
            if eol_date < now:
                continue
        release_date = datetime.strptime(release["releaseDate"], "%Y-%m-%d")
        if release_date <= six_months_ago:
            cycles.append(release["cycle"])

    if not cycles:
        print(
            "Warning: No PostgreSQL versions found >= 6 months old", file=sys.stderr
        )
        return None

    return f"/^({"|".join(cycles)})\\./"


def get_kubernetes_allowed_versions() -> str | None:
    """Get Kubernetes N-1 version (latest minus one)."""
    data = fetch_json("https://endoflife.date/api/kubernetes.json")
    if not data:
        return None

    # Sort by cycle version descending
    sorted_releases = sorted(
        data, key=lambda x: [int(p) for p in x["cycle"].split(".")], reverse=True
    )

    if len(sorted_releases) < 2:
        print("Warning: Not enough Kubernetes versions found", file=sys.stderr)
        return None

    # Get N-1 (second latest)
    n_minus_1 = sorted_releases[1]["cycle"]
    # Allow this version and all older
    major, minor = n_minus_1.split(".")
    return f"<={major}.{minor}"


def get_pypi_latest_stable(package: str) -> str | None:
    """Get latest stable version from PyPI (excluding pre-releases)."""
    data = fetch_json(f"https://pypi.org/pypi/{package}/json")
    if not data:
        return None

    # Get all versions, filter out pre-releases
    versions = []
    for version in data.get("releases", {}).keys():
        # Skip pre-releases (alpha, beta, rc, dev)
        if re.search(r"(a|b|rc|dev|alpha|beta)\d*$", version, re.IGNORECASE):
            continue
        versions.append(version)

    if not versions:
        return None

    # Sort by version parts and return latest
    def version_key(v):
        # Handle YYYY.MM.patch format
        parts = v.split(".")
        return [int(p) if p.isdigit() else 0 for p in parts]

    versions.sort(key=version_key, reverse=True)
    return versions[0]


def get_previous_month_version(version: str) -> str | None:
    """
    Get the previous month's version for YYYY.MM format.
    E.g., 2026.1.1 -> 2025.12, 2025.12.5 -> 2025.11
    """
    parts = version.split(".")
    if len(parts) < 2:
        return None

    try:
        year = int(parts[0])
        month = int(parts[1])
    except ValueError:
        return None

    # Go back one month
    if month == 1:
        year -= 1
        month = 12
    else:
        month -= 1

    return f"{year}.{month}"


def get_home_assistant_allowed_versions() -> str | None:
    """Get Home Assistant N-1 month version."""
    latest = get_pypi_latest_stable("homeassistant")
    if not latest:
        return None

    prev_month = get_previous_month_version(latest)
    if not prev_month:
        return None

    # Allow versions up to and including prev_month.x
    escaped = prev_month.replace(".", "\\.")
    return f"/^{escaped}\\./"


def get_esphome_allowed_versions() -> str | None:
    """Get ESPHome N-1 month version."""
    latest = get_pypi_latest_stable("esphome")
    if not latest:
        return None

    prev_month = get_previous_month_version(latest)
    if not prev_month:
        return None

    escaped = prev_month.replace(".", "\\.")
    return f"/^{escaped}\\./"


def update_renovaterc(renovaterc_path: Path, dry_run: bool = False) -> bool:
    """Update .renovaterc with new version constraints."""
    with open(renovaterc_path) as f:
        config = json.load(f)

    package_rules = config.get("packageRules", [])
    changes_made = False

    # Define the rules we want to manage
    managed_rules = {
        "mariadb-lts": {
            "description": "MariaDB: LTS versions at least 6 months old (auto-managed)",
            "matchDatasources": ["docker"],
            "matchPackageNames": ["mariadb"],
            "get_allowed": get_mariadb_allowed_versions,
        },
        "postgresql-stable": {
            "description": "PostgreSQL: Major versions at least 6 months old (auto-managed)",
            "matchDatasources": ["docker"],
            "matchPackageNames": ["ghcr.io/cloudnative-pg/postgresql"],
            "get_allowed": get_postgresql_allowed_versions,
        },
        # TODO: Kubernetes version tracking requires a custom regex manager
        # to be added to .renovaterc first. The manager would need to match
        # kubernetes_version in ansible/group_vars/kubernetes.yaml
        # "kubernetes-n-minus-1": {
        #     "description": "Kubernetes: N-1 version policy (auto-managed)",
        #     "matchManagers": ["custom.regex"],
        #     "matchFileNames": ["ansible/group_vars/kubernetes.yaml"],
        #     "matchPackageNames": ["kubernetes/kubernetes"],
        #     "get_allowed": get_kubernetes_allowed_versions,
        # },
        "home-assistant-n-minus-1": {
            "description": "Home Assistant: One month behind latest (auto-managed)",
            "matchDatasources": ["docker"],
            "matchPackageNames": ["ghcr.io/home-assistant/home-assistant"],
            "get_allowed": get_home_assistant_allowed_versions,
        },
        "esphome-n-minus-1": {
            "description": "ESPHome: One month behind latest (auto-managed)",
            "matchDatasources": ["pypi"],
            "matchPackageNames": ["esphome"],
            "get_allowed": get_esphome_allowed_versions,
        },
    }

    for rule_id, rule_config in managed_rules.items():
        allowed_versions = rule_config["get_allowed"]()
        if not allowed_versions:
            print(f"Skipping {rule_id}: could not determine allowed versions")
            continue

        # Find existing rule by description
        existing_idx = None
        for idx, rule in enumerate(package_rules):
            if rule.get("description", "").startswith(rule_config["description"].split(" (")[0]):
                existing_idx = idx
                break

        new_rule = {
            "description": rule_config["description"],
            "allowedVersions": allowed_versions,
        }

        # Add matching criteria
        for key in ["matchDatasources", "matchPackageNames", "matchManagers", "matchFileNames"]:
            if key in rule_config:
                new_rule[key] = rule_config[key]

        if existing_idx is not None:
            old_allowed = package_rules[existing_idx].get("allowedVersions")
            if old_allowed != allowed_versions:
                print(f"{rule_id}: {old_allowed} -> {allowed_versions}")
                package_rules[existing_idx] = new_rule
                changes_made = True
            else:
                print(f"{rule_id}: unchanged ({allowed_versions})")
        else:
            print(f"{rule_id}: adding new rule ({allowed_versions})")
            package_rules.append(new_rule)
            changes_made = True

    if changes_made and not dry_run:
        config["packageRules"] = package_rules
        with open(renovaterc_path, "w") as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"\nUpdated {renovaterc_path}")
    elif changes_made:
        print("\nDry run: no changes written")
    else:
        print("\nNo changes needed")

    return changes_made


def main():
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would change without writing",
    )
    parser.add_argument(
        "--renovaterc",
        type=Path,
        default=Path(".renovaterc"),
        help="Path to .renovaterc file",
    )
    args = parser.parse_args()

    if not args.renovaterc.exists():
        print(f"Error: {args.renovaterc} not found", file=sys.stderr)
        sys.exit(1)

    update_renovaterc(args.renovaterc, args.dry_run)


if __name__ == "__main__":
    main()
