#!/usr/bin/env python3
"""Daily cloud.gov / login.gov active-user summary.

Reads the timestamped UAA query result snapshots produced by
ci/uaa-queries.sh and mirrored locally by ci/download-uaa-results.sh:

    <root>/uaa/YYYY/MM/DD/HH/MM/SS/active-users-by-origin.json

Collapses each UTC day to a single row using the LAST snapshot of that day
(latest HH/MM/SS), and emits just the active-user counts for origin
'cloud.gov' and 'login.gov'. No third-party libraries are required.

Usage:
    ci/summarize-migration-daily.py [-d ROOT_DIR]

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


def collect_daily_last(root: Path):
    """Return an ordered list of (date, counts-dict) using each day's last snapshot."""
    # date -> (latest_ts, counts)
    per_day = {}
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
        day = ts.date()
        existing = per_day.get(day)
        if existing is None or ts > existing[0]:
            per_day[day] = (ts, counts)
    return [(day, per_day[day][1]) for day in sorted(per_day)]


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Daily cloud.gov / login.gov active-user summary "
        "(last snapshot of each UTC day)."
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

    daily = collect_daily_last(root)
    if not daily:
        print(
            f"ERROR: no active-users-by-origin.json snapshots found under {root}/uaa/",
            file=sys.stderr,
        )
        return 1

    header = f"{'date (UTC)':<12} {'cloud.gov':>10} {'login.gov':>10}"
    print(header)
    print("-" * len(header))
    for day, counts in daily:
        cg = counts.get("cloud.gov", 0)
        lg = counts.get("login.gov", 0)
        print(f"{day.isoformat():<12} {cg:>10d} {lg:>10d}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
