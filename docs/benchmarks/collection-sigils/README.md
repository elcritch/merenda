# Collection observation cleanup, 2026-11-14

Apple M3 Pro, 36 GB RAM, macOS 15.7.9, Nim 2.4.2, release/ARC/useMalloc/threads.
Two sequential runs per variant, five batches each; tables report medians of ten
batch means. Builds and tests had completed before measurement. No native windows,
GPU presentation, input latency, or allocation counts are measured. Implementation
under test: `3ffd44d8`; the harnesses and raw results accompany this report.

## Binding notification workload

`tests/benchmark_collection_sigils.nim` compares the previous collection-wide
Sigil/linear getter idiom with a keyed collection/item observation. Each row has
its own BindingScope; a publication changes item 0 and drains the real main-thread
queue. This includes snapshot copying, validation/indexing, notification, getters,
and scheduling. The target is a simple responder: there are no widgets, undo,
layout or previews. Five warmup operations precede five batches of 20 operations.
Runtime assertions check the getter count for every batch.

| Rows | Whole Sigil + linear getters | Collection + indexed getter | Getter calls per edit |
| ---: | ---: | ---: | ---: |
| 3 | 0.941 µs | 0.677 µs | 3 → 1 |
| 100 | 35.340 µs | 7.904 µs | 100 → 1 |
| 1,000 | 489.109 µs | 44.257 µs | 1,000 → 1 |

At 1,000 observed rows, this workload takes about 11× less time and invokes one
getter rather than 1,000. This demonstrates narrower invalidation and indexed
lookup, not an 11× application-wide speedup. Snapshot publication remains
O(n + observed identities), including single-item assignment in this prototype.

## Actual direct demo

`tests/benchmark_direct_demo.nim` uses the actual demo commands and undo history.
`-d:directDemoSigilBaseline` loads the snapshot-Sigil demo from `61bfa142`; both
variants use the current shared runtime and natural StackView distributions.
The current demo also has view-owned components and the shared domain controller,
so this compares the complete cleanup rather than isolating collection storage.

Counter batches use 1,000 operations, command-only batches 100, and edit/reverse
plus preview batches two. Command-only queued work settles outside the timing
interval; history clears between batches. Flush cases drain the real GUI work
queue and include preview construction/layout/capture and live property writes.
They exclude live-tree layout, native drawing/presentation and the window loop.

| Operation | Rows | Snapshot Sigil demo | Collection demo |
| --- | ---: | ---: | ---: |
| Counter + queue flush | 3 | 1.670 µs | 1.695 µs |
| Edit command only | 3 | 0.981 µs | 1.054 µs |
| Edit + preview flush | 3 | 4.258 ms | 4.098 ms |
| Reverse + preview flush | 3 | 4.171 ms | 4.111 ms |
| Counter + queue flush | 100 | 1.636 µs | 1.662 µs |
| Edit command only | 100 | 9.675 µs | 11.322 µs |
| Edit + preview flush | 100 | 166.827 ms | 158.983 ms |
| Reverse + preview flush | 100 | 164.122 ms | 164.114 ms |

The 100-row command-only path is modestly slower: building/validating the key
index and snapshot comparison have a cost. The full edit/preview workload remains
around 160 ms, and reversal is essentially unchanged. Variation in capture-heavy
results is not evidence that the shared layout bottleneck has disappeared. The
small binding workload and the actual demo answer different performance questions.

The paired demo tests check validation, undo/redo, keyed field reuse, coalesced
previews, stale proposal rejection, and subscription cleanup. Other tests check
single-item notification among 1,000 bindings, duplicate-key atomicity, read-only
projections, recursive publication, component root replacement, and cancellation
of omitted/retired bindings. No new native IME or multi-document/async experiment
was run during this cleanup.

## Reproduce

```sh
nim ic --nimcache:deps/.nimcache/ -d:release -o:deps/benchmark_collection_sigils tests/benchmark_collection_sigils.nim
nim ic --nimcache:deps/.nimcache/ -d:release -d:directDemoSigilBaseline -o:deps/benchmark_direct_demo_sigil tests/benchmark_direct_demo.nim
nim ic --nimcache:deps/.nimcache/ -d:release -o:deps/benchmark_direct_demo_collection tests/benchmark_direct_demo.nim
./deps/benchmark_collection_sigils /tmp/bindings.csv
./deps/benchmark_direct_demo_sigil /tmp/demo-sigil.csv
./deps/benchmark_direct_demo_collection /tmp/demo-collection.csv
```

Repeat the three runs sequentially for a second set. The CSVs preserve all batch
means, including the 10-row actual-demo cases omitted from the compact table.
Earlier [P0/P7 measurements](../direct-views/README.md) are retained as historical
results, not silently replaced by this cleanup.
