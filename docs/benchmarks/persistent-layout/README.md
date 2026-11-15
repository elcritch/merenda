# Persistent layout prototype

The recorded demo samples predate its explicit leaf-control cache opt-in; a
rerun with the current demo also includes that separate optimization.

This experiment requires both `-d:merendaPersistentLayout` and an explicit
`root{vpPersistentLayout} = true` on a stable layout root. Disabling the property
or releasing generated layout inputs drops its retained solver. Views are held
through non-owning references; the Kiwi solver holds its own variables and
constraints. A newly built detached preview is not opted in automatically.
The property belongs on the actual solve root; setting it on a descendant does not
split an ancestor's graph or create a separate solve.
The compile-time switch adds value storage for the cache to every view, even when
that view is not opted in; the size and allocation overhead have not been measured.
Hierarchy changes are checked on the next layout; until then, the old solver's
allocation can remain attached to the root, but it does not retain removed views.

Only normal layout is retained. Fitting uses a fresh solver and separate
variables. A tree is eligible unless any view has CSS layout rules: autoresizing,
intrinsic, container and authored constraints are all supported. Each attempted
reuse verifies the hierarchy order and regenerates every input in the same order
as a fresh solve. The number of constraints must match; any constraint whose
expression, relation, strength or constant differs is removed and re-added in the
retained solver. Any rejected constraint prevents a cache from being saved. A
changed hierarchy, CSS, a different constraint count, budget failure, or incremental
conflict discards the retained solver and uses the fresh path.

The first version accepted only trees fully determined by required autoresizing
equations, because non-required constraints can have several equally good
solutions and an incrementally updated solver might choose a different one than a
fresh solve. Weak stays toward current frames make such ties rare but do not rule
them out. A seeded 120-step test edits text, sizes, constraint constants and
priorities in an intrinsic StackView tree with competing authored priorities, and
requires every frame to equal a fresh solve after each step; the demo comparison
below matched frame fingerprints in every sample. Neither proves equivalence for
arbitrary graphs.

Updates to Kiwi happen before frames are applied. A failed incremental update
discards the mutated tableau before a fresh solve; it is not used as a rollback
snapshot. The verification and fresh retry share the layout attempt's elapsed-time
budget. View, constraint, coefficient and projected-memory limits are checked for
each attempted graph; the projected-memory estimate is a solver heuristic, not
an allocation measurement. Cache publication happens after frame commit and is
not separately timed against the solve budget. Faster or slower work near a time
limit can naturally change timeout outcomes.

## Measurement

Two profiled, warmed runs per configuration on an Apple M3 Pro, macOS 15.7.9,
Nim 2.4.2, release/ARC/threads/useMalloc. Builds and tests were not running during
measurement. All work was headless; results are not native input-to-presentation
latency. Timings include instrumentation overhead. Each operation starts from a
fresh fixture, warms twice, and records five samples. Runs were ordered off, on,
on, off. Values below are medians of ten samples.

The **fixed** fixture has a 1240 × 540 root with 100 materialized DirectView row
hosts and fixed Label, TextField and Button children. Every participating view is
explicitly configured for autoresizing constraints, and row widths follow root
width. Rows extend beyond the viewport; there is no virtualization, model binding,
or active editor. The **demo** uses the actual DirectView task controller and
row builder, with the live root opted in, both with and without its detached
preview. The demo's intrinsic-sized tree is ineligible and uses fresh solves.

At 100 rows, milliseconds per operation:

| Operation | Fixed fresh / persistent | Demo live fresh / persistent | Demo + preview fresh / persistent |
| --- | ---: | ---: | ---: |
| Edit | 45.18 / 4.34 | 200.61 / 203.17 | 390.09 / 393.22 |
| Counter | 44.35 / 4.37 | 201.42 / 203.65 | 231.88 / 233.82 |
| Reorder | 78.81 / 80.99 | 203.46 / 206.75 | 390.82 / 395.97 |
| Resize | 45.78 / 21.47 | 139.85 / 141.79 | 313.65 / 320.49 |

The fixed tree kept the same 402-view, 4,016-constraint graph. A warmed resize
reused the solver and replaced a median of 101 root-pin or stay constraints;
the fresh solve inserted all 4,016. Inclusive constraint insertion/optimization
time fell from 40.59 ms to 16.19 ms. These nested timings overlap the wall time
and must not be added to it. Text and counter changes in this fixture changed no
solver constraints, so the reused solver performed no insertion. Reorder changed
the hierarchy order and fell back to a fresh solve on every measured sample.

The actual demo recorded no persistent builds or reuses: its tree does not meet
the prototype's requirements. Its live-only resize still inserted 4,130
constraints and made 1,528 intrinsic-resolution calls in both configurations.
The small on/off timing differences do not establish a demo improvement. A fresh
detached preview has no previous solver to reuse and was not automatically opted in.

All 120 paired samples had matching live-tree frame, hugging/compression-priority,
and diagnostic fingerprints, with no recorded blocked layouts or solver failures.
The detached preview tree is not part of that fingerprint. Hash comparisons do not
prove equality; focused tests also compare exact frames and fitting results and
exercise removal, CSS and authored-constraint fallback, required conflicts,
rollback, budgets, opt-out, and root/child lifetime under ARC.
The focused persistence suite was also run under ORC.

This is evidence that retaining the solver is worthwhile to investigate for
stable, fully determined graphs. It does **not** solve the demo's measured overall
layout cost. Supporting intrinsic-sized controls, authored constraints or CSS
requires a stronger proof of graph equivalence and conflict handling before reuse.
Memory overhead and native interaction latency have not been measured.

Raw sample files are not tracked. The insertion scope is inclusive. A fresh insertion scope
adds one constraint; an incremental insertion scope removes and adds one changed
constraint. Profile counters distinguish persistent builds, reuses and fallbacks.
An abandoned incremental attempt is counted as a fallback and contributes timing,
but is not an additional `solverPasses` count; the subsequent fresh attempt is.

## Intrinsic-sized trees

After intrinsic, container and authored constraints became eligible, a re-run on
the same machine and method (off, on, on, off; medians of ten samples at 100 rows,
milliseconds) gave:

| Operation | Demo live fresh / persistent | Demo + preview fresh / persistent | Fixed fresh / persistent |
| --- | ---: | ---: | ---: |
| Edit | 114.98 / 61.03 | 233.82 / 180.58 | 44.00 / 4.05 |
| Counter | 113.26 / 61.15 | 116.36 / 62.66 | 44.81 / 4.23 |
| Reorder | 115.71 / 116.44 | 235.51 / 236.82 | 78.05 / 80.83 |
| Resize | 102.04 / 84.43 | 221.69 / 204.78 | 45.68 / 20.67 |

The demo now reused its solver on every edit, counter and resize sample; reorder
changes hierarchy order and rebuilt on every sample. Fresh demo times are lower than
in the table above because intrinsic caching is now on by default. Live-tree frame
fingerprints matched between configurations for every operation, with no solver
failures. The detached preview is still built fresh. These are headless wall times on
one machine, not native input latency.

## Reproduce

Build both binaries first, then run sequentially with no builds or tests in
parallel. The second pair reverses the order. `nim.cfg` supplies ARC, threads,
release and `useMalloc`.

```sh
nim ic --nimcache:deps/.nimcache/ -d:release -d:merendaProfile -o:deps/benchmark_persistent_off tests/benchmark_persistent_layout.nim
nim ic --nimcache:deps/.nimcache/ -d:release -d:merendaProfile -d:merendaPersistentLayout -o:deps/benchmark_persistent_on tests/benchmark_persistent_layout.nim
./deps/benchmark_persistent_off docs/benchmarks/persistent-layout/off-1.csv
./deps/benchmark_persistent_on docs/benchmarks/persistent-layout/on-1.csv
./deps/benchmark_persistent_on docs/benchmarks/persistent-layout/on-2.csv
./deps/benchmark_persistent_off docs/benchmarks/persistent-layout/off-2.csv
python3 tests/benchmarks/compare_persistent_layout.py
```
