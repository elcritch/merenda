#!/usr/bin/env python3
"""Capture macOS allocation stacks from a benchmark stopped at a checkpoint.

Compile the tracked Nim probes with the project's Atlas configuration first:
  python3 tests/benchmarks/capture_allocations.py markdown /tmp/md /tmp/md-graph table storage 2000
  python3 tests/benchmarks/capture_allocations.py markdown /tmp/md /tmp/view-graph table view 500
  python3 tests/benchmarks/capture_allocations.py synedit /tmp/syn /tmp/syn-graph

Run baseline and changed builds with identical settings, without other builds.
The full-history graph can contain program memory; keep it in a safe location.
"""
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time


def main():
    if len(sys.argv) < 4 or sys.argv[1] not in ("markdown", "synedit"):
        raise SystemExit("usage: capture_allocations.py markdown|synedit BINARY OUTPUT_PREFIX [workload mode count]")
    kind, binary, prefix = sys.argv[1:4]
    arguments = sys.argv[4:]
    if kind == "markdown" and (len(arguments) != 3 or arguments[1] not in ("storage", "view")):
        raise SystemExit("markdown requires: table|prose storage|view count")
    if kind == "synedit" and arguments:
        raise SystemExit("synedit takes no extra arguments")
    command = [binary] + (arguments if kind == "markdown" else ["pause"])
    output = Path(prefix)
    output.parent.mkdir(parents=True, exist_ok=True)
    if Path(str(output) + ".memgraph").exists():
        raise SystemExit("choose a fresh output prefix; the memory graph already exists")
    env = os.environ.copy()
    env["MallocStackLogging"] = "1"
    child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, bufsize=0, env=env)
    log = bytearray()
    selector = selectors.DefaultSelector()
    selector.register(child.stdout, selectors.EVENT_READ)
    ready = False
    pending = b""
    try:
        deadline = time.monotonic() + 120
        while not ready and time.monotonic() < deadline:
            if not selector.select(timeout=min(1, max(0, deadline - time.monotonic()))):
                if child.poll() is not None:
                    break
                continue
            chunk = os.read(child.stdout.fileno(), 65536)
            if not chunk:
                break
            log.extend(chunk)
            pending += chunk
            lines = pending.split(b"\n")
            pending = lines.pop()
            for line in lines:
                if kind == "synedit":
                    ready |= line.startswith(b"source bytes=8388608 spans=1")
                elif line.startswith(b"{"):
                    stage = json.loads(line)["stage"]
                    ready |= stage == ("storage" if arguments[1] == "storage" else "firstRender")
        if not ready:
            raise RuntimeError("benchmark exited or failed to reach checkpoint within 120 seconds")
        graph = str(output) + ".memgraph"
        capture = subprocess.run(["leaks", "--fullStackHistory", "--outputGraph=" + graph,
                                  str(child.pid)], capture_output=True, timeout=180)
        Path(str(output) + "-leaks.log").write_bytes(capture.stdout + capture.stderr)
        if not Path(graph).is_file():
            raise RuntimeError("leaks did not produce a memory graph")
        # leaks can return nonzero for detected leaks while writing a valid graph.
        for name, flags in (("live", []), ("high", ["-highWaterMark"])):
            report = subprocess.run(["malloc_history", graph, *flags, "-callTree", "-invert",
                                     "-ignoreThreads", "-consolidateAllBySymbol"],
                                    capture_output=True, timeout=180, check=True)
            Path(str(output) + "-" + name + ".txt").write_bytes(report.stdout + report.stderr)
    finally:
        selector.close()
        if child.poll() is None:
            try:
                child.stdin.write(b"\n")
                child.stdin.flush()
                tail = child.communicate(timeout=60)[0]
            except (BrokenPipeError, subprocess.TimeoutExpired):
                child.kill()
                tail = child.communicate()[0]
            log.extend(tail or b"")
        Path(str(output) + "-target.log").write_bytes(log)


if __name__ == "__main__":
    main()
