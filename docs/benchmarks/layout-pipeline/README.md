# DirectView layout pipeline, 2026-11-15

These historical samples predate the task demo's explicit leaf-control cache
opt-in. Running the harness against the current demo also measures that change.

Two instrumented and two uninstrumented runs on Apple M3 Pro, macOS 15.7.9,
Nim 2.4.2, release/ARC/threads/useMalloc. Builds and tests were not running during
measurements. The benchmark uses the actual DirectView task demo's controller,
row builder, actions and bindings. It compares its live tree alone with the
normal demo tree containing the detached Dragology preview. The live-only tree
omits the preview column, so the two trees have different chrome as well as
different preview work. Both use a 1240 × 540 root and run headlessly.

Each fixture starts with 10, 50 or 100 tasks. It warms each operation twice,
then records five individual samples. Each operation updates the model or frame,
drains the real main-thread queue, and builds the live render tree. The operation
order is clean, counter, edit, reverse, resize; resize alternates the width between
1200 and 1240. Undo history is cleared outside the timed interval. The four runs
were ordered uninstrumented, instrumented, uninstrumented, instrumented. Tables
show medians of ten individual samples. Raw sample files are not tracked.
Phase and solver counters in the plain CSVs are zero because instrumentation is
compiled out, not because those operations did no work.
The numbers describe one machine, one order of workloads and no native window,
GPU presentation, real input latency, or allocation bytes. They do not establish
cross-platform results or full drag-gesture cost.

All instrumented samples completed without a recorded solver failure or blocked
live layout. The uninstrumented binary checks the live tree but cannot detect a
failure inside a detached preview; its paired instrumented samples recorded none.
Instrumented and uninstrumented wall-time medians for the non-clean workloads
varied by approximately −3.4% to +0.9%; noise and measurement order prevent
interpreting that as a precise overhead estimate. Clean redraw medians are about
0.3–2.3 µs, and timer overhead is a much larger fraction of those operations.

## End-to-end work

Milliseconds per update with instrumentation enabled. A clean redraw had no solve,
measurement, or draw callbacks in these warmed cases. Each other live-only update
performed one solve; editing, reversing, and resizing with preview performed two
solves and one detached preview build/capture. The counter does not rebuild the
preview.

| Rows | Operation | Live only | Live + preview |
| ---: | --- | ---: | ---: |
| 10 | counter / edit / reverse / resize | 17.9 / 18.1 / 18.6 / 11.5 | 24.6 / 39.7 / 38.4 / 27.9 |
| 50 | counter / edit / reverse / resize | 88.2 / 88.0 / 89.0 / 56.7 | 104.1 / 170.9 / 171.4 / 132.5 |
| 100 | counter / edit / reverse / resize | 199.5 / 197.9 / 202.4 / 136.5 | 226.3 / 383.6 / 384.2 / 309.6 |

The preview workload includes building a fresh detached tree, laying it out,
capturing its drawable subtrees, updating the live view, and building the live
render tree. It is not an input-to-present time. A separately measured preview
build/capture was 155.5 ms inclusive for the 100-row edit. That number overlaps
the phases below and must not be added to them.

## 100-row phase breakdown

Milliseconds per operation, medians of ten samples. The phase columns are
**exclusive** of nested instrumented phases. Their sum is not an end-to-end
measurement: timer bookkeeping, model work, queue scheduling and other work may
fall outside them or remain in a broader phase. Corresponding inclusive counters,
including call counts and wider enclosing phases, are in the raw CSVs.

| Phase | Edit live only | Edit + preview | Resize live only |
| --- | ---: | ---: | ---: |
| Binding value application | 0.011 | 0.215 | 0.000 |
| Intrinsic measurement | 111.6 | 209.7 | 49.6 |
| Generated layout inputs, excluding measurement | 0.34 | 0.71 | 0.05 |
| Constraint expression construction | 1.79 | 3.22 | 1.66 |
| Constraint insertion and incremental solver optimization | 50.8 | 102.4 | 50.5 |
| Publish solved variable values | 0.038 | 0.076 | 0.038 |
| Apply solved frames | 0.096 | 0.136 | 0.097 |
| Stack arrangement and prefix reconciliation | 0.35 | 2.04 | 0.35 |
| View draw callbacks | 18.6 | 19.1 | 19.8 |
| Remaining layout transaction work | 9.86 | 20.32 | 9.80 |
| Remaining live render-build work | 4.06 | 4.55 | 4.11 |

`vppSolve` in the CSV is the **whole** graph setup and solve pipeline, not a
separate numerical-solver phase. Its exclusive remainder includes solver-view
collection and other setup outside the more specific timers. The generation and
construction timers cover the instrumented input and equation paths; construction
is not a complete count of every allocation used to build a graph. The insertion
timer includes budget checks and Kiwi's `addConstraint`, which creates a row,
substitutes it and optimizes incrementally. Kiwi's later `updateVariables` only
writes solved values back. We cannot separate its row construction from its
optimization without instrumenting Kiwi itself. Draw timings cover view callbacks;
scene reconciliation and materialization remain in broader render/preview scopes.
Intrinsic measurements, drawing and drag preview work are on the measured thread;
background worker activity is not aggregated into these counters.

In the live-only counter case, the graph grew from 53 views / 530 constraints at
10 rows to 213 / 2,130 at 50 and 413 / 4,130 at 100. Median insertion time grew
from 1.05 to 14.1 to 51.4 ms; intrinsic measurement grew from 13.3 to 56.8 to
112.1 ms. These three sizes show increasing cost for this tree, not a general
complexity proof. An edit caused 3,469 intrinsic-resolution calls at 100 rows;
the preview version caused 6,522. Recursive calls are counted individually, but
exclusive durations avoid counting their nested time twice.

## Decision and next experiment

Prioritize **smaller independent layout graphs and less repeated intrinsic
measurement**. Even the unrelated counter update traverses and solves the eager
100-row live tree, and the detached preview builds and solves another tree. A
persistent solver alone would not eliminate the fresh preview graph or the larger
measurement and drawing costs. Virtualized CollectionView rows already demonstrate
one way to bound the visible tree, but their separate [measurement](../collection-rows/README.md)
is a different workload and cannot be treated as a direct speedup here.

A persistent solver is still worth a **controlled prototype** for stable live
hierarchies: on live-only resize the cached generated-input phase is just 0.05 ms,
while reinserting and optimizing the graph takes 50.5 ms. That phase time is
not a prediction of the savings from reuse. Such a
prototype must measure actual changed constraints, variable and constraint identity,
removal/replacement cost, required-conflict rollback, CSS invalidation, memory,
and budget/failure semantics. It must compare resize, content edits and structural
reorder separately; a rebuilt detached preview cannot reuse a previous solver
without a different preview lifetime. Do not ship solver persistence based on these
numbers alone.

A graph-partition experiment must preserve ancestor-owned and cross-subtree
constraints, coordinate spaces, priorities and update ordering. Measure it against
the same fixture, including correctness checks and default-off overhead. In
parallel, count intrinsic-cache hits and invalidations on the real tree before
expanding caching: the existing [warm-cache microbenchmark](../layout/README.md)
does not establish correctness or savings for arbitrary widget dependencies.

The later [row-boundary comparison](../row-boundary/README.md) found that the
original demo does not qualify for the prototype. A controlled fixed-row tree had
smaller graphs and lower solve costs, but exposed different budget and local-failure
behavior. That experiment does not establish a speedup for this demo.

The later [persistent-solver prototype](../persistent-layout/README.md) reduced
resize insertion work for a fully autoresizing fixture. The original demo did not
qualify, so its overall measured layout cost remains unresolved.

## Reproduce

From the repository root, build both versions before measuring, then run them
sequentially. `nim.cfg` supplies ARC, threads, release and `useMalloc`.

```sh
nim ic --nimcache:deps/.nimcache/ -d:release -o:deps/benchmark_layout_pipeline_plain tests/benchmark_layout_pipeline.nim
nim ic --nimcache:deps/.nimcache/ -d:release -d:merendaProfile -o:deps/benchmark_layout_pipeline_profile tests/benchmark_layout_pipeline.nim
./deps/benchmark_layout_pipeline_plain /tmp/layout-plain-1.csv
./deps/benchmark_layout_pipeline_profile /tmp/layout-profile-1.csv
./deps/benchmark_layout_pipeline_plain /tmp/layout-plain-2.csv
./deps/benchmark_layout_pipeline_profile /tmp/layout-profile-2.csv
```

The profiler is thread-local. `nanoseconds` is inclusive and recursive scopes
can overlap; `exclusiveNanoseconds` subtracts direct nested instrumented scopes.
Both include instrumentation overhead. Reset only between completed operations.
