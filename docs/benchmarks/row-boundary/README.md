# Fixed-row graph boundary comparison

Two profiled, warmed runs per configuration on an Apple M3 Pro, macOS 15.7.9,
Nim 2.4.2, release/ARC/threads/useMalloc. All rendering was headless. Builds and
tests were not running during measurements. These are wall times on one machine,
not native input-to-presentation latency. The timers add instrumentation overhead.

The **demo** uses the same DirectView task controller and row builder as the
[layout-pipeline profile](../layout-pipeline/README.md): 10, 50 or 100 rows in a
1240 × 540 root, with and without the detached preview. It warms each operation
twice, then records five samples each for clean redraw, counter, edit, reverse,
and alternating-width resize. Runs were ordered off, on, on, off. The switch did
not partition any root in this demo: it does not use CollectionRows, and its
intrinsic-sized rows do not satisfy this experiment's eligibility rules.

The **fixed-row fixture** exercises the boundary itself. It mounts 10, 50 or 100
DirectView hosts under a 1240 × 540 root, with fixed-size Label, TextField and
Button subviews, and marks the hosts with the same internal boundary flag used by
CollectionRows. It changes a field's text, updates a counter label, reverses row
order and positions, or alternates the root width. Each operation uses a fresh
fixture, two warmups and five samples; runs were ordered off, on, on, off. The
100-row tree extends beyond the viewport and is **materialized**, not virtualized.
It has no ArrayController bindings or active field editor. It isolates the graph
experiment and is not a benchmark of collection scrolling or real edit latency.

Each row below is the median of ten individual samples. Solver views and
constraints are the largest **single** graph in an operation; passes count all
solves. Insertion times cover all solves and include Kiwi's incremental
optimization. They are exclusive of nested instrumented phases; do not add them
to inclusive timings. The insertion scope has no nested instrumented phases, so
its inclusive and exclusive times are equal. Raw sample files are not tracked.

## Cost

At 100 rows, milliseconds per operation in the actual demo:

| Operation | Live off / on | Live + preview off / on |
| --- | ---: | ---: |
| Edit | 198.56 / 198.87 | 385.34 / 383.65 |
| Counter | 199.40 / 199.21 | 229.40 / 230.84 |
| Reorder | 200.74 / 200.52 | 385.28 / 387.03 |
| Resize | 137.15 / 137.88 | 310.54 / 310.21 |

For live-only edits, both configurations used one 413-view, 4,130-constraint
graph and made 3,469 intrinsic-resolution calls. Resize used 1,528 calls in
both. The small timing differences cannot establish an improvement; no row
boundary was active.

At 100 fixed rows, milliseconds and intrinsic-resolution calls per operation:

| Operation | Wall off / on | Intrinsic calls off / on |
| --- | ---: | ---: |
| Edit | 45.12 / 8.95 | 1 / 1 |
| Counter | 44.60 / 9.26 | 1 / 1 |
| Reorder | 78.73 / 42.17 | 1 / 1 |
| Resize | 45.12 / 8.87 | 0 / 1 |

The largest graph fell from 402 views / 4,016 constraints to 102 / 1,016, while
passes rose from 1 to 101. For edit, total constraint insertion and optimization
fell from 40.48 ms to 4.13 ms. These figures show potential in this deliberately
eligible tree, not a predicted speedup for the demo. The experiment did **not**
reduce intrinsic reads here: fixed descendants already bypass those equations,
and a partitioned resize rebuilt the counter's intrinsic input once where the
cached full graph rebuilt none.

## Correctness and failure behavior

All 300 paired demo samples and 120 paired fixed-row samples had equal live-tree
frame, hugging/compression-priority, and diagnostic fingerprints, and no recorded
blocked layouts or solver failures. The detached preview tree is not included in
the live-tree fingerprint. Fingerprints are a broad comparison, not a substitute
for exact assertions or proof against hash collisions.

The focused tests compare exact frames with flipped ancestors and row hosts,
ancestor-owned positional anchors, competing authored priorities, and CSS
rejection diagnostics. Authored and CSS cases fall back to the full graph.
An ancestor-owned constraint with a low root view limit also produced the same
full-graph failure, diagnostic counts and unchanged frames in both configurations.

**Failure behavior is not equivalent when partitioning actually occurs.** With a
four-view tree and root `maxViews = 3`, the full graph fails with `lslViews`,
while the split parent and local graphs each fit and succeed. Conversely, if a
row's own view limit is one, the full root solve succeeds while the split row
solve fails after the parent has succeeded; the root diagnostic still reports
success and the row frames differ. The focused tests preserve these observations.
Limits currently apply to individual solves, and the split is not an atomic
replacement for the original transaction.

Keep this experiment opt-in and do not expand its eligibility on this evidence.
Before that, decide how transaction-wide budgets and failure diagnostics should
work across local solves, and preserve or roll back frames on a local failure.
Then repeat a paired benchmark using eligible, virtualized CollectionRows and a
real editing workload; measure native input latency separately.

## Reproduce

Build the four profiled binaries first, then run each sequentially with the output
path shown below. No compilation should run during timing. The second pair reverses
the order. `nim.cfg` supplies ARC, threads, release and `useMalloc`.

```sh
nim ic --nimcache:deps/.nimcache/ -d:release -d:merendaProfile -o:deps/benchmark_layout_boundary_off tests/benchmark_layout_pipeline.nim
nim ic --nimcache:deps/.nimcache/ -d:release -d:merendaProfile -d:merendaRowLayoutBoundaries -o:deps/benchmark_layout_boundary_on tests/benchmark_layout_pipeline.nim
nim ic --nimcache:deps/.nimcache/ -d:release -d:merendaProfile -o:deps/benchmark_fixed_boundary_off tests/benchmark_row_boundary_fixed.nim
nim ic --nimcache:deps/.nimcache/ -d:release -d:merendaProfile -d:merendaRowLayoutBoundaries -o:deps/benchmark_fixed_boundary_on tests/benchmark_row_boundary_fixed.nim
./deps/benchmark_fixed_boundary_off docs/benchmarks/row-boundary/fixed-off-1.csv
./deps/benchmark_fixed_boundary_on docs/benchmarks/row-boundary/fixed-on-1.csv
./deps/benchmark_layout_boundary_off docs/benchmarks/row-boundary/demo-off-1.csv
./deps/benchmark_layout_boundary_on docs/benchmarks/row-boundary/demo-on-1.csv
./deps/benchmark_fixed_boundary_on docs/benchmarks/row-boundary/fixed-on-2.csv
./deps/benchmark_fixed_boundary_off docs/benchmarks/row-boundary/fixed-off-2.csv
./deps/benchmark_layout_boundary_on docs/benchmarks/row-boundary/demo-on-2.csv
./deps/benchmark_layout_boundary_off docs/benchmarks/row-boundary/demo-off-2.csv
python3 tests/benchmarks/compare_row_boundaries.py
```
