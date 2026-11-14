# Retained container layout experiment

This synthetic benchmark constructs a FormView with two plain views per row and a
vertical StackView with one plain view per row. All rows are visible. It separately
times construction, unconstrained `sizeThatFits` on both containers, layout of
both subtrees, and one reversal of the stack's children, with no subsequent solve.
Reversal represents the arrangement portion of a direct-view update, not the complete update or preview.
It does not create a window or measure rendering, native event processing, or
interactive latency. `create` includes one-time initialization in its first sample.

Run from the repository root with the Atlas workspace and `nim.cfg` in place:

```sh
nim ic -d:release --nimcache:/tmp/merenda-layout-cache \
  --out:/tmp/merenda-layout-bench --path:src docs/benchmarks/layout/bench.nim
/tmp/merenda-layout-bench
```

To reproduce the before path, build the same benchmark against `ca3d752e` in a
separate checkout with equivalent Atlas dependencies. The benchmark selects the
original repeated-insertion algorithm when the batch API is absent. The after
path includes construction of the batch input in the reorder timing. Five samples
per row count were taken on macOS 15.7.9 arm64 with Nim 2.4.2, using release
builds; raw microseconds are in `before.csv` and `after.csv`. These are individual
runs on one machine, not a statistically controlled cross-platform study.

Median microseconds per operation:

| Rows | Create before / after | Measure before / after | Layout before / after | Reverse before / after |
| ---: | ---: | ---: | ---: | ---: |
| 10 | 566 / 646 | 7.42 / 9.00 | 461 / 531 | 11.29 / 4.21 |
| 100 | 5,944 / 5,907 | 58.17 / 57.42 | 13,822 / 13,669 | 1,229 / 26.54 |
| 300 | 21,675 / 21,509 | 311.92 / 293.50 | 103,755 / 101,430 | 25,953 / 90.33 |

The synthetic reversal improves substantially; these results do not establish an
end-to-end preview improvement. The layout result changes little relative to the
solver and subtree work in this fixture; measurement at 300 rows is noisy. FormView
now reads each visible row's child sizes once per layout pass, verified separately
by a counted regression test. Ancestor invalidation propagation and cross-pass
caching were left unchanged: this experiment does not isolate their costs or prove
that suppressing notifications would preserve all observers.

`noop.nim` compares repeated unchanged arrangements in one after-build binary.
It includes building the batch input and compares the old per-child loop against
the new prefix check. Build it using the same command above with `noop.nim` and
a distinct output path. Five sample medians in microseconds per arrangement were
0.54 / 0.23 (10), 30.69 / 0.75 (100), and 309.10 / 2.01 (300), old / batch.
Raw samples and iteration counts are in `noop.csv`. This isolates arrangement;
it is not a full direct-view update.
