"""Summarize a single-window benchmark_terminal_native JSONL trace (milliseconds)."""

import collections
import json
import sys


def summary(values):
    values = sorted(value / 1_000_000 for value in values)
    if not values:
        return None
    count = len(values)
    return {
        "count": count,
        "p50_ms": round(values[count // 2], 3),
        "p95_ms": round(values[min(count - 1, count * 95 // 100)], 3),
        "max_ms": round(values[-1], 3),
    }


def analyze(path):
    with open(path) as source:
        events = sorted(map(json.loads, source), key=lambda event: event["ticks"])
    first = next(event["ticks"] for event in events if event["stage"] == "workload-start")
    last = next(event["ticks"] for event in events if event["stage"] == "workload-end")
    events = [event for event in events if first <= event["ticks"] <= last]
    result = {}
    for begin, end in [
        ("ready", "ui-ready"),
        ("poll-start", "poll-end"),
        ("worker-poll-start", "worker-poll-end"),
        ("grid-start", "grid-end"),
        ("frame-start", "frame-end"),
        ("submit-start", "submit-end"),
        ("submit-start", "render-start"),
        ("render-start", "present"),
        ("render-start", "render-prepared"),
        ("render-prepared", "render-begun"),
        ("render-begun", "render-drawn"),
        ("render-drawn", "present"),
        ("native-poll-start", "native-poll-end"),
        ("application-frame-start", "application-frame-end"),
    ]:
        pending = {}
        durations = []
        for event in events:
            key = event["identity"]
            if begin == "submit-start" or begin.startswith("render-"):
                key = (key, event["detail"])
            if event["stage"] == begin:
                pending[key] = event["ticks"]
            elif event["stage"] == end and key in pending:
                durations.append(event["ticks"] - pending.pop(key))
        result[f"{begin} -> {end}"] = summary(durations)

    # The benchmark has one terminal and one window. Snapshots are cumulative:
    # a later presented render includes output from skipped submissions too.
    worker_trace = any(event["stage"] == "worker-output" for event in events)
    worker_reads = collections.defaultdict(list)
    readiness = {}
    delivered = None
    callback = None
    awaiting_grid = []
    read_ends = []
    unsent = []
    submitted = collections.defaultdict(list)
    latency = []
    callback_wait = []
    batch_wait = []
    grid_wait = []
    last_grid = None
    for event in events:
        stage, ticks = event["stage"], event["ticks"]
        if stage == "worker-output":
            worker_reads[event["identity"]].append((event["detail"], ticks))
        elif stage == "grid-snapshot" and worker_trace:
            records = worker_reads[event["identity"]]
            awaiting_grid.extend(ready for serial, ready in records if serial <= event["detail"])
            worker_reads[event["identity"]] = [
                (serial, ready) for serial, ready in records if serial > event["detail"]
            ]
        elif stage == "ready":
            readiness[event["identity"]] = ticks
        elif stage == "ui-ready":
            delivered = readiness.pop(event["identity"], None)
            callback = ticks
        elif stage == "poll-start" and callback is not None:
            callback_wait.append(ticks - callback)
            callback = None
        elif stage == "poll-end":
            if event["detail"]:
                read_ends.append(ticks)
                if delivered is not None and not worker_trace:
                    awaiting_grid.append(delivered)
            delivered = None
        elif stage == "grid-start":
            batch_wait.extend(ticks - end for end in read_ends)
            read_ends.clear()
        elif stage == "grid-end":
            unsent.extend(awaiting_grid)
            awaiting_grid.clear()
            last_grid = ticks
        elif stage == "frame-start" and last_grid is not None:
            grid_wait.append(ticks - last_grid)
            last_grid = None
        elif stage == "submit-start":
            submitted[event["identity"]].extend(
                (event["detail"], ready) for ready in unsent
            )
            unsent.clear()
        elif stage == "present":
            records = submitted[event["identity"]]
            latency.extend(ticks - ready for render, ready in records if render <= event["detail"])
            submitted[event["identity"]] = [
                (render, ready) for render, ready in records if render > event["detail"]
            ]
    result["grid -> frame"] = summary(grid_wait)
    result["UI callback -> poll"] = summary(callback_wait)
    result["poll -> grid"] = summary(batch_wait)
    result["ready -> native present submission"] = summary(latency)
    presented = [event["ticks"] for event in events if event["stage"] == "present"]
    result["presentation gaps"] = summary(
        [right - left for left, right in zip(presented, presented[1:])]
    )
    result["counts"] = dict(collections.Counter(event["stage"] for event in events))
    read_stage = "worker-poll-end" if worker_trace else "poll-end"
    result["bytes"] = sum(event["detail"] for event in events if event["stage"] == read_stage)
    return result


if __name__ == "__main__":
    for path in sys.argv[1:]:
        print(json.dumps({"trace": path, "summary": analyze(path)}, indent=2))
