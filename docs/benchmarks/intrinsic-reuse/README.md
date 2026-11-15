# Intrinsic measurement reuse, 2026-11-15

This experiment uses the actual DirectView task demo's live-only controller and
row builder, with 100 tasks and a 1240 × 540 root. It does not create the demo's
detached Dragology preview. The comparison leaves caching off or explicitly enables
the existing `vpCacheIntrinsicSize` property on the fixture's Label, TextField and
Button instances. StackViews and other views remain uncached. The policy is applied
to the already constructed tree; the workload does not add new row instances.
Caching remains off by default in NimKit.

After this experiment, the demo opted its own built-in leaf controls into the
cache as they are created, including inserted rows and detached preview rows,
when compiled with `-d:merendaIntrinsicCache`.
The comparison harness explicitly disables them in its uncached variant. These
historical measurements predate that change; they do not measure native latency
or the cost of detached previews.

Two profiled and two unprofiled runs were collected sequentially, in the order
plain/profile/plain/profile. Within each run the uncached fixture runs first.
Every operation has two warmups and five measured samples. Each sample updates
model or frame, drains the GUI-thread queue, and builds the live render tree.
Medians below combine ten samples per case. Runs used Apple M3 Pro, macOS 15.7.9,
Nim 2.4.2, release/ARC/threads/useMalloc, with no concurrent test or build jobs.
They are headless measurements from one machine, not native input-to-present or
allocation measurements. Fixed ordering and the small sample count limit the claims.

| Operation | Uncached median | Leaf cache median | Change |
| --- | ---: | ---: | ---: |
| Counter update | 204.5 ms | 114.1 ms | −44.2% |
| Edit one title | 197.9 ms | 116.9 ms | −40.9% |
| Reverse rows | 199.6 ms | 114.7 ms | −42.5% |
| Resize root | 142.1 ms | 102.0 ms | −28.2% |

These are unprofiled wall times. In the separately instrumented runs, the edit
median was 198.8 ms uncached and 114.5 ms with the leaf cache. The exclusive
intrinsic-measurement phase was 111.9 ms and 26.9 ms respectively. Both variants
still performed one solve with 413 views and 4,130 constraints: this experiment
does not reduce the solver graph or prove an application-wide speedup.

## Where the requests go

The profiled 100-row edit issued 3,469 `resolvedIntrinsicContentSize` requests in
both variants. These are calls to the wrapper, including hits, not necessarily
new measurements. Counts below are medians per edit; in this workload the same
counts occurred in all ten samples.

| Widget category | Uncached calls | Cache hits | Invalidated misses | Cache disabled |
| --- | ---: | ---: | ---: | ---: |
| Button | 935 | 725 | 210 | 0 |
| Label | 920 | 712 | 208 | 0 |
| TextField | 900 | 700 | 200 | 0 |
| StackView | 713 | 0 | 0 | 713 |
| DirectView | 1 | 0 | 0 | 1 |

The cached version has 2,137 hits, 618 invalidated misses and 714 uncached calls;
there were no cold misses, revision mismatches, discarded measurements, or failed
measurements in the measured edit samples. All 618 misses reported `layoutFrame`
as the first invalidation of their prior cached entry. That cause can predate the
current sample; it is not proof that a frame change actually changes a particular
control's intrinsic size. Invalidation is intentionally conservative because
custom intrinsic methods can depend on frame geometry. See
[cache contracts](../../layout-measurement.md).

The harness hashes every view's identifier and frame after each measured update;
all 80 cache-off/on pairs matched across the four runs. Hashes are a broad signal,
not proof of complete rendering equivalence. Paired tests also compare uncached
and cached control sizes and frames after text, font family and size, style,
visibility, root-frame, and active field-editor input changes. A separate custom
view test changes and invalidates its measurement reentrantly and checks that no
stale result is retained. These tests cover the exercised standard mutation paths;
they do not establish safety for arbitrary subclasses, replaced measurement
protocols, external dependencies, native IME, or every custom theme.

The profiler categories group subclasses under the first matching built-in type
and group unrecognized types as `OtherView`. A custom classifier can distinguish
additional types. The per-thread counters do not retain views. Disabled builds and
builds without an installed classifier do not collect these category counts. The
profiling build includes counting overhead; use the unprofiled timings for the
A/B comparison. Raw sample files are not tracked.

## Reproduce

```sh
nim ic --nimcache:deps/.nimcache/ -d:release -d:merendaIntrinsicCache -o:deps/benchmark_intrinsic_plain tests/benchmark_intrinsic_reuse.nim
nim ic --nimcache:deps/.nimcache/ -d:release -d:merendaIntrinsicCache -d:merendaProfile -o:deps/benchmark_intrinsic_profile tests/benchmark_intrinsic_reuse.nim
./deps/benchmark_intrinsic_plain /tmp/intrinsic-plain-1
./deps/benchmark_intrinsic_profile /tmp/intrinsic-profile-1
./deps/benchmark_intrinsic_plain /tmp/intrinsic-plain-2
./deps/benchmark_intrinsic_profile /tmp/intrinsic-profile-2
```

Each invocation writes `-summary.csv` and `-counts.csv`; the unprofiled counts
file contains only its header. The harness asserts matching cache-off/on frame
hashes for each completed sample and marks a blocked live solve in the summary.
