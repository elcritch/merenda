#!/usr/bin/env python3
"""Compare the paired row-boundary benchmark CSVs and print median results."""

import csv
import statistics
import sys
from pathlib import Path


def read(path, keys):
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    indexed = {tuple(row[key] for key in keys): row for row in rows}
    if len(indexed) != len(rows):
        raise ValueError(f"duplicate sample keys in {path}")
    return indexed


def compare(directory, kind):
    keys = ["rows", "operation", "sample"]
    if kind == "demo":
        keys.append("preview")
    samples = {"off": [], "on": []}
    pairs = 0
    for run in (1, 2):
        off = read(directory / f"{kind}-off-{run}.csv", keys)
        on = read(directory / f"{kind}-on-{run}.csv", keys)
        if off.keys() != on.keys():
            raise ValueError(f"{kind} run {run}: sample keys differ")
        expected = 150 if kind == "demo" else 60
        if len(off) != expected:
            raise ValueError(f"{kind} run {run}: expected {expected} samples")
        for key in off:
            left, right = off[key], on[key]
            for field in ("frame_hash", "priority_hash", "diagnostic_hash", "blocked"):
                if left[field] != right[field]:
                    raise ValueError(f"{kind} run {run} {key}: {field} differs")
            for row in (left, right):
                if row["blocked"] != "false" or row["solver_failures"] != "0":
                    raise ValueError(f"{kind} run {run} {key}: failed or blocked")
            if left["partitioned_roots"] != "0":
                raise ValueError(f"{kind} run {run} {key}: off build partitioned")
            if kind == "fixed" and right["partitioned_roots"] == "0":
                raise ValueError(f"{kind} run {run} {key}: on build did not partition")
            pairs += 1
        samples["off"].extend(off.values())
        samples["on"].extend(on.values())

    print(f"{kind}: {pairs} matching pairs")
    intrinsic = "vppIntrinsicMeasurement_calls" if kind == "demo" else "intrinsic_calls"
    for operation in ("edit", "counter", "reverse" if kind == "demo" else "reorder", "resize"):
        for preview in (["false", "true"] if kind == "demo" else [None]):
            result = []
            for mode in ("off", "on"):
                rows = [
                    row for row in samples[mode]
                    if row["rows"] == "100" and row["operation"] == operation
                    and (preview is None or row["preview"] == preview)
                ]
                if not rows:
                    raise ValueError(f"{kind} {mode} {operation}: no 100-row samples")
                median = lambda field: statistics.median(float(row[field]) for row in rows)
                result.append(
                    f"{median('wall_ns') / 1e6:.2f} ms, "
                    f"{median('solver_views'):.0f} views, "
                    f"{median('solver_passes'):.0f} passes, "
                    f"{median(intrinsic):.0f} intrinsic calls"
                )
            suffix = f" preview={preview}" if preview is not None else ""
            print(f"  {operation}{suffix}: off {result[0]}; on {result[1]}")
    print("  on partitioned roots:", sorted({r["partitioned_roots"] for r in samples["on"]}))


if __name__ == "__main__":
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/benchmarks/row-boundary")
    for fixture in ("demo", "fixed"):
        compare(path, fixture)
