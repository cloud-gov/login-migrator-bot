#!/usr/bin/env python3
"""Summarize the cloud.gov -> login.gov migration trend over time.

Reads the timestamped UAA query result snapshots produced by
ci/uaa-queries.sh and mirrored locally by ci/download-uaa-results.sh:

    <root>/uaa/YYYY/MM/DD/HH/MM/SS/active-users-by-origin.json

Each active-users-by-origin.json is a JSON array of {"origin", "count"} rows.
For each snapshot we extract the active-user counts for origin 'cloud.gov'
(not yet migrated) and 'login.gov' (migrated), compute the migration
percentage, and print a time-ordered table plus a simple ASCII trend chart.
No third-party libraries are required.

Usage:
    ci/summarize-migration-trend.py [-d ROOT_DIR]

    -d ROOT_DIR   Directory containing the uaa/ tree
                  (default: ./uaa-results, matching download-uaa-results.sh)
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# uaa/YYYY/MM/DD/HH/MM/SS/active-users-by-origin.json
TS_RE = re.compile(
    r"uaa/(\d{4})/(\d{2})/(\d{2})/(\d{2})/(\d{2})/(\d{2})/"
    r"active-users-by-origin\.json$"
)


def parse_timestamp(path: Path):
    """Return a UTC datetime parsed from the key path, or None if it doesn't match."""
    m = TS_RE.search(path.as_posix())
    if not m:
        return None
    y, mo, d, h, mi, s = (int(x) for x in m.groups())
    try:
        return datetime(y, mo, d, h, mi, s, tzinfo=timezone.utc)
    except ValueError:
        return None


def load_counts(path: Path):
    """Return {origin: count} from an active-users-by-origin.json snapshot."""
    with path.open() as fh:
        rows = json.load(fh)
    counts = {}
    for row in rows:
        origin = row.get("origin")
        count = row.get("count")
        if origin is None or count is None:
            continue
        counts[origin] = int(count)
    return counts


def collect(root: Path):
    """Return a time-ordered list of (datetime, counts-dict) snapshots."""
    snapshots = []
    for path in root.rglob("active-users-by-origin.json"):
        ts = parse_timestamp(path)
        if ts is None:
            print(f"WARNING: skipping unrecognized path {path}", file=sys.stderr)
            continue
        try:
            counts = load_counts(path)
        except (json.JSONDecodeError, OSError, ValueError) as exc:
            print(f"WARNING: skipping unreadable {path}: {exc}", file=sys.stderr)
            continue
        snapshots.append((ts, counts))
    snapshots.sort(key=lambda item: item[0])
    return snapshots


def ascii_chart(values, width=50):
    """Return a list of bar strings scaled to `width` for the given values."""
    if not values:
        return []
    hi = max(values) or 1
    bars = []
    for v in values:
        filled = int(round((v / hi) * width))
        bars.append("#" * filled)
    return bars


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Summarize the cloud.gov -> login.gov migration trend."
    )
    parser.add_argument(
        "-d",
        "--dir",
        default="./uaa-results",
        help="Directory containing the uaa/ tree (default: ./uaa-results)",
    )
    args = parser.parse_args(argv)

    root = Path(args.dir)
    if not root.exists():
        print(f"ERROR: directory not found: {root}", file=sys.stderr)
        return 1

    snapshots = collect(root)
    if not snapshots:
        print(
            f"ERROR: no active-users-by-origin.json snapshots found under {root}/uaa/",
            file=sys.stderr,
        )
        return 1

    # Table
    header = (
        f"{'timestamp (UTC)':<20} {'cloud.gov':>10} {'login.gov':>10} "
        f"{'total':>8} {'migrated %':>11}"
    )
    print(header)
    print("-" * len(header))

    migrated_pcts = []
    login_counts = []
    rows = []
    for ts, counts in snapshots:
        cg = counts.get("cloud.gov", 0)
        lg = counts.get("login.gov", 0)
        migrated_total = cg + lg
        pct = (lg / migrated_total * 100) if migrated_total else 0.0
        migrated_pcts.append(pct)
        login_counts.append(lg)
        rows.append((ts, cg, lg))
        print(
            f"{ts.strftime('%Y-%m-%d %H:%M:%S'):<20} {cg:>10d} {lg:>10d} "
            f"{migrated_total:>8d} {pct:>10.1f}%"
        )

    # Net change summary
    first_ts, first_cg, first_lg = rows[0]
    last_ts, last_cg, last_lg = rows[-1]
    print()
    print(
        f"Span: {first_ts.strftime('%Y-%m-%d %H:%M')} -> "
        f"{last_ts.strftime('%Y-%m-%d %H:%M')} UTC "
        f"({len(rows)} snapshot(s))"
    )
    print(
        f"login.gov active users: {first_lg} -> {last_lg} "
        f"({last_lg - first_lg:+d})"
    )
    print(
        f"cloud.gov active users: {first_cg} -> {last_cg} "
        f"({last_cg - first_cg:+d})"
    )
    print(
        f"Migration: {migrated_pcts[0]:.1f}% -> {migrated_pcts[-1]:.1f}% "
        f"({migrated_pcts[-1] - migrated_pcts[0]:+.1f} pts)"
    )

    # ASCII trend chart of login.gov (migrated) active users
    print()
    print("login.gov active users over time (relative bars):")
    bars = ascii_chart(login_counts)
    for (ts, _cg, lg), bar in zip(rows, bars):
        print(f"  {ts.strftime('%Y-%m-%d %H:%M')}  {lg:>6d} | {bar}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
