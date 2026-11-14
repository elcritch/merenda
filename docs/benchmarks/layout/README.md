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

## Opt-in intrinsic cache experiment

`cache.nim` uses fixed-size custom views in a StackView and times one intrinsic
measurement followed by one direct arrangement, repeated ten times per sample.
It warms the fixture first so child frames are stable. It compares the same build
with caching disabled and explicitly enabled on each child; this is a warm-cache
microbenchmark, not a constraint solver, render, or complete layout transaction.
Use the build command above with `cache.nim` and a distinct output path.

| Rows | Disabled µs/pair | Enabled µs/pair | Intrinsic reads per 10 pairs, disabled / enabled |
| ---: | ---: | ---: | ---: |
| 10 | 7.53 | 6.15 | 200 / 0 |
| 100 | 58.18 | 44.67 | 2,000 / 0 |
| 300 | 180.42 | 151.28 | 6,000 / 0 |

Values are medians of five samples on the same machine and compiler described
above; raw samples are in `cache.csv`. The cache stores intrinsic results only,
is disabled by default, and is appropriate only when the view's intrinsic inputs
are invalidated when changed. The StackView arrangement itself already measures
one fitting size per visible child and reuses it for both axes; this experiment
measures opt-in reuse across otherwise separate calls. Geometry or intrinsic
invalidation causes a fresh measurement. These numbers do not establish an
end-to-end preview or native latency improvement.

## Opt-in cache: default-off comparison

The intrinsic cache is disabled by default. To estimate its cost in that mode,
we built this same fixture from cache parent `af3659a8` and cache commit `be12b48d`
in separate detached worktrees. Both used the existing Atlas `deps/` and `nim.cfg`,
Nim 2.4.2, release flags, and the same machine. The exact build command in each
worktree was:

```sh
nim ic -d:release --nimcache:/tmp/merenda-layout-cache-<version>-ic \
  --out:/tmp/merenda-layout-cache-<version>-bin --path:src \
  docs/benchmarks/layout/bench.nim
```

Each binary ran three times in alternating order, giving 15 samples per row
count and version. The raw samples are [before](default-off-before.csv) and
[after](default-off-after.csv). Median time changes follow; positive numbers mean
the cache build took longer.

| Rows | Create | Measure | Layout | Reverse |
| ---: | ---: | ---: | ---: | ---: |
| 10 | +1.5% | +3.1% | +0.6% | +1.1% |
| 100 | +0.5% | -0.7% | +0.6% | -2.9% |
| 300 | +0.4% | +3.1% | -0.3% | +1.8% |

These small differences are noisy measurements of this synthetic fixture on one
machine, not a guarantee of zero overhead or a native interaction benchmark. The
cache also adds bounded per-view storage even when disabled. The change in layout
measurement is distinct from the separate opt-in cache-hit benchmark.
