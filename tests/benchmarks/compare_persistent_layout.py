#!/usr/bin/env python3
"""Verify paired persistent-layout samples and report 100-row medians."""

import csv
import statistics
import sys
from pathlib import Path


def read(path):
    keys = ("scenario", "preview", "rows", "operation", "sample")
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    indexed = {tuple(row[key] for key in keys): row for row in rows}
    if len(rows) != 60 or len(indexed) != len(rows):
        raise ValueError(f"expected 60 uniquely keyed samples in {path}")
    return indexed


def main(directory):
    samples = {"off": [], "on": []}
    pairs = 0
    for run in (1, 2):
        off = read(directory / f"off-{run}.csv")
        on = read(directory / f"on-{run}.csv")
        if off.keys() != on.keys():
            raise ValueError(f"run {run}: sample keys differ")
        for key in off:
            left, right = off[key], on[key]
            for field in ("frame_hash", "priority_hash", "diagnostic_hash", "blocked"):
                if left[field] != right[field]:
                    raise ValueError(f"run {run} {key}: {field} differs")
            for row in (left, right):
                if row["blocked"] != "false" or row["solver_failures"] != "0":
                    raise ValueError(f"run {run} {key}: failed or blocked")
            if key[0] == "fixed" and key[3] != "reorder" and right["persistent_reuses"] == "0":
                raise ValueError(f"run {run} {key}: expected solver reuse")
            if key[0] == "fixed" and key[3] == "reorder" and right["persistent_fallbacks"] == "0":
                raise ValueError(f"run {run} {key}: expected hierarchy fallback")
            pairs += 1
        samples["off"].extend(off.values())
        samples["on"].extend(on.values())

    print(f"{pairs} matching pairs")
    for scenario, previews in (("fixed", ["false"]), ("demo", ["false", "true"])):
        for preview in previews:
            for operation in ("edit", "counter", "reorder", "resize"):
                result = []
                for mode in ("off", "on"):
                    rows = [
                        row for row in samples[mode]
                        if row["scenario"] == scenario and row["preview"] == preview
                        and row["operation"] == operation
                    ]
                    median = lambda field: statistics.median(float(row[field]) for row in rows)
                    result.append(
                        f"{median('wall_ns') / 1e6:.2f} ms, "
                        f"{median('insertion_scopes'):.0f} insertion scopes, "
                        f"{median('persistent_reuses'):.0f} reuses, "
                        f"{median('persistent_fallbacks'):.0f} fallbacks"
                    )
                print(f"{scenario} preview={preview} {operation}: off {result[0]}; on {result[1]}")


if __name__ == "__main__":
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/benchmarks/persistent-layout")
    main(path)
