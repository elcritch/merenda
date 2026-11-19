# P7 direct views versus P0, 2026-11-14

These are the pre-cleanup results. The demos now share a keyed collection
controller and owned bindings; see the later [collection comparison](../collection-sigils/README.md).

Diagnostic comparison on Apple M3 Pro, 36 GB, macOS 15.7.9, Nim 2.4.2,
release/ARC/useMalloc/threads, Clang 17. No native window or GPU. Two sequential
runs of each variant, five calibrated batches per case per run; results below
are medians of the ten batch means. No competing test/build jobs were run during
measurement. Raw CSV files in this directory retain individual batches and
blocked results. They supplement the original P0 measurements in
`../declarative-views/`; those files have not been replaced.

Build and reproduce from the P7 implementation revision:

```sh
nim ic -d:release -o:deps/benchmark_declarative_views tests/benchmark_declarative_views.nim
nim ic -d:release -o:deps/benchmark_direct_views tests/benchmark_direct_views.nim
./deps/benchmark_declarative_views --csv:/tmp/p0.csv
./deps/benchmark_direct_views --csv:/tmp/p7.csv
```

Both workloads contain `4N + 2` widgets plus a host: a counter and keyed rows with
a label, text field and remove button. Both install two event handlers per row.
P7 uses a reused text binding and an inline remove handler; P0 constructs two
ViewAction adapters per description. Field sizing matches with
`svspFillAvailableWidth`, and both inner stacks use `svdNatural`. The early
P7 smoke run inherited StackView's `svdFill` default; the committed runs correct
that mismatch. This measures the two implementations, including their
different binding and reconciliation costs; it is not an isolated measurement
of ViewSpec allocation.

P7's benchmark uses an observed controller per row, with plain title fields.
The title case invalidates one row binding. The evaluation demo instead uses
a Sigil containing plain task values, which invalidates
all title bindings; **the one-row title timing is not the demo's edit latency**.
Both P7 bound-value cases explicitly traverse session scopes with
`flushBindings`, using a manual scheduling hook. This includes that traversal,
but excludes the live main-thread queue's scheduling/draining cost. The default
application path queues only affected scopes. Neither measurement is an
input-to-present latency or an allocation count.

| Operation, 100 rows | P0 (ms) | P7 (ms) |
| --- | ---: | ---: |
| Full rebuilt no-op / full direct recomposition | 1.066 | 0.507 |
| Cached ViewSpec no-op | 0.384 | — |
| Reverse and update/recompose | 2.394 | 2.044 |
| Counter update (full P0 vs scoped P7) | 1.067 | 0.0083 |
| Title update (full P0 vs one-row P7 binding) | 1.064 | 0.0086 |
| Counter update and layout | 138.160 | 139.659 |
| Mount and clear/close | 32.576 | 33.358 |
| Detached build and drop | 31.069 | 32.190 |
| One Dragology preview capture | 184.521 | 190.555 |

P7 reduces whole-body update work and gives much smaller scoped updates. It is
slower than P0's cached-description no-op in this run, and mount/close, layout and
capture do not improve. Timing differences in the latter cases are not evidence
of a new allocation bottleneck: no allocation bytes/counts were collected.

At 300 rows **both variants fail the 500 ms solver budget** for layout and preview
capture. Those CSV records are blocked results, not successful frame timings.
P7's direct construction does not solve the shared layout limitation. At 300 rows
its reverse still takes about 30 ms: the existing StackView per-child reorder path
remains important. A complete drag evaluates multiple candidates, so one capture
is not total drag-start time.

Keep P7 as a prototype and measure real application input, collection viewport
workloads, coarse controller invalidation, queue overhead and allocation counts
before choosing it as the final public DSL.

## Actual demo: before and after the Sigil simplification

`tests/benchmark_direct_demo.nim` exercises the example's actual controller commands,
undo registration, bindings and queued preview refresh. The baseline option loads
`1cfc3247` and normalizes its stack distribution to the current demo; the current
version is `42fe54d3`. This compares MVC coordination with equal stack policies,
not the earlier visually stretched layout. Raw results are the `demo-before` and
`demo-sigil` CSV files alongside the microbenchmarks.

```sh
nim ic -d:release -d:directDemoBaseline -o:deps/benchmark_direct_demo_before tests/benchmark_direct_demo.nim
nim ic -d:release -o:deps/benchmark_direct_demo tests/benchmark_direct_demo.nim
./deps/benchmark_direct_demo_before /tmp/demo-before.csv
./deps/benchmark_direct_demo /tmp/demo-sigil.csv
```

Two sequential runs, five batches each. Counter batches use 1,000 operations;
queue-only edit batches use 100; edit/reverse plus preview flush use two.
Queue-only batches settle outside the timing interval and undo history is cleared
between batches. Those command timings measure coalesced publication throughput,
not isolated input latency. Flush cases drain the real main-thread work queue.
They include preview layout/capture and live property writes, but not live-tree
layout, native drawing/presentation or the window event loop.

| Actual demo operation | Rows | Before | Task snapshot Sigil |
| --- | ---: | ---: | ---: |
| Counter and queue flush | 3 | 1.819 µs | 1.726 µs |
| Edit command only | 3 | 0.718 µs | 0.940 µs |
| Edit and preview flush | 3 | 4.102 ms | 4.126 ms |
| Reverse and preview flush | 3 | 4.107 ms | 4.122 ms |
| Counter and queue flush | 100 | 1.799 µs | 1.675 µs |
| Edit command only | 100 | 6.441 µs | 10.054 µs |
| Edit and preview flush | 100 | 159.325 ms | 160.168 ms |
| Reverse and preview flush | 100 | 159.745 ms | 161.217 ms |

The snapshot Sigil simplifies notification ownership at a modest model-publication
cost. Overall edit/preview time is essentially unchanged in these runs; do not
interpret sub-percent differences as an established speedup or regression.
The ID projection avoids structural body evaluation on title edits (also covered
by a behavioral test). It does not avoid checking the projected IDs or evaluating
all row title bindings on a collection-wide notification. Per-item notifications
and indexed model lookup remain worthwhile comparisons for larger lists.

## DirectView setup, 2026-11-19

The setup-only case times `newDirectView(frame)` through the return of its first
`viewBody`. It builds the keyed rows, installs the bindings and actions, and
attaches the widgets. Each sample uses a fresh host. Model creation, the widget
count check, and teardown run outside the timer. First layout and drawing are
excluded. Two warmups per row count let process-wide font and theme data settle.

| Keyed rows | Before | After | Setup time saved |
| ---: | ---: | ---: | ---: |
| 10 | 3.00 ms | 2.14 ms | 29% |
| 100 | 29.47 ms | 21.16 ms | 28% |
| 300 | 90.34 ms | 65.74 ms | 27% |

On Apple M3 Pro, macOS 15.7.9, Nim 2.4.3, release/ARC, these are the medians
of 30 individual builds per cell. Both binaries used the same benchmark, with
the baseline built against library revision `90deea7e`. Run order was baseline,
changed, changed, baseline, with 15 samples per size per run.

A macOS CPU sample of the 100-row baseline showed label and text-field constructors
measuring their initial frames. That path resolved the entire text-field style
twice, including once to obtain only its text color. The color getter now looks
up that single property. CSS matching also borrows each candidate rule from the
immutable theme snapshot and passes the role separately to avoid copying the
style context.

In separate CPU samples of the 100-row workload, `ruleValue` appeared in 742 of
2,364 first-body samples before the change (31%) and 156 of 2,113 after (7%).
The largest remaining cost in the second profile was installing widget protocol
methods through Sigils' `replaceMethods` (924 samples, 44%). These are inclusive
stack counts within the first body, with nested calls to the same function counted
once.

```sh
source deps/nim-bif-symlink-dedup/activate.sh
nim ic -d:release -o:deps/benchmark_direct_views tests/benchmark_direct_views.nim
./deps/benchmark_direct_views --setup-only --rows:10,100,300 --samples:15 --csv:/tmp/direct-setup.csv
```
