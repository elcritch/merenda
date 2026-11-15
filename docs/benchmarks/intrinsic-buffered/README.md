# Intrinsic caching in a buffered editable collection

This comparison uses `direct_collection_demo` with 5,000 model items, a fixed
640 × 480 viewport and the half-viewport row buffer. Each operation starts with
a fresh fixture and an active editor in item `0`. The scroll workload keeps that
editor mounted when it leaves the buffered region. Both policies run in the same
binary compiled with `-d:merendaIntrinsicCache`; the uncached policy opts no row
controls in, and the cached policy explicitly opts the row's Label, TextField and
Button in. This is a comparison of runtime opt-in, not the cost of compiling the
cache into an otherwise uncached application.

These are historical results from before intrinsic caching became the default.
The original uncached policy left all views uncached; the current harness only
switches the row controls, while other views use the new default. Its results
therefore are not directly comparable to the table below.

## Current default-on implementation

After enabling the default and adding the subtree eligibility check, four
unprofiled headless runs on the same machine used alternating policy order and
two warmups plus seven measured samples per policy. The medians below combine
28 samples per policy. The harness checks matching frames, view trees, item
identifiers and field text for each paired sample. Only row controls change
policy; CollectionView itself opts out in both cases. These numbers include
the subtree check but do not characterize deep trees or native display latency.

| Operation | Row cache off | Row cache on | Change |
| --- | ---: | ---: | ---: |
| Edit active field | 20.18 ms | 13.35 ms | −33.8% |
| Scroll, retaining editor | 26.55 ms | 20.81 ms | −21.6% |
| Insert | 20.93 ms | 13.92 ms | −33.5% |
| Reorder | 20.09 ms | 13.19 ms | −34.3% |
| Resize | 11.71 ms | 9.23 ms | −21.2% |

## Earlier opt-in implementation

On Apple M3 Pro, macOS 15.7.9, Nim 2.4.2, release/ARC/threads/useMalloc, four
unprofiled headless runs alternated policy order: off/on, on/off, on/off, off/on.
Each operation has two warmups and seven measured samples per policy; the table
reports medians of 28 samples. No builds or tests ran during measurement. The
harness asserts matching cache-off/on fingerprints for the view tree, frames,
row identifiers and field text for each sample, including warmups. Fingerprints
are a useful check, not a proof of rendering equivalence.

| Operation | Cache off median | Cache on median | Change |
| --- | ---: | ---: | ---: |
| Edit active field | 20.27 ms | 13.31 ms | −34.4% |
| Scroll, retaining editor | 27.00 ms | 19.86 ms | −26.4% |
| Insert | 20.84 ms | 13.89 ms | −33.3% |
| Reorder | 20.13 ms | 13.32 ms | −33.8% |
| Resize | 11.58 ms | 9.18 ms | −20.7% |

At the top of the collection there were 12 visible and 17 mounted rows, with 20
controller/selection subscriptions. Scrolling to the middle mounted 24 buffered
rows plus the pinned editor, with 28 subscriptions. Resizing changed the window
width between 600 and 640 pixels. These are not measurements of a 5,000-row
materialized view, allocation counts, or native input-to-display latency.

Two separately profiled runs, in opposite policy orders, explain the edit
measurement. The uninstrumented timings above are preferable for A/B timing.
The cache-off edit made a median 329 uncached intrinsic-resolution requests; the
cache-on edit had 187 hits, 68 misses and 74 uncached requests. Exclusive
intrinsic-measurement time was 10.34 ms off and 3.48 ms on. Both recorded one
solver pass with a maximum of 92 solver views. Profiling adds overhead and its
nested phase timings must not be added together.

## Native renderer

A separate unprofiled benchmark created a real Metal-backed window with
`MERENDA_BACKGROUND=1`, dispatched synthetic text or changed the scroll offset,
and pumped the application loop until a subsequent native render was submitted and
the window was clean. It used the same alternating order and 28 samples per
policy. This is **dispatch-to-render-submission**, including event-loop polling;
it does not include hardware input, IME latency, GPU presentation, or display
scanout.

| Operation | Cache off median | Cache on median | Observed ranges, off / on |
| --- | ---: | ---: | ---: |
| Synthetic edit | 27.05 ms | 24.20 ms | 24.41–33.41 / 16.87–33.32 ms |
| Scroll | 38.86 ms | 28.47 ms | 27.80–42.50 / 20.50–30.59 ms |

The distributions overlap, particularly for edits. One machine and a small
sample do not establish that a user will perceive this improvement or that it
will generalize to other applications.

## Storage and process memory

For this compiler and architecture, `sizeof(typeof(default(View)[]))` was 1,288
bytes without the cache and 1,320 bytes with it, both before and after grouping the
intrinsic state in a value object. The 32-byte difference includes padding and is
paid for every `View` in a cache-enabled build, even when the view opts out.
Using the cache fills that existing entry and adds no per-view cache allocation. Profile
builds have additional diagnostic fields.

In a separate headless 5,000-item fixture after scrolling with one pinned editor,
there were 132 views in the mounted tree and 25 mounted rows. Four alternating
fresh-process peak-RSS samples per build ranged from 92.59 to 98.34 MiB without
the flag and 92.63 to 98.31 MiB with it. Noise was much larger than the expected
few KiB of inline fields, so these samples **do not establish a process-memory
increase or decrease**. They include initialization and teardown, and the tree
count excludes any detached reusable hosts.

## Run the current harness

Build first, then run each executable sequentially without concurrent builds:

```sh
nim ic -d:release -o:deps/intrinsic-buffered tests/benchmark_intrinsic_buffered.nim
nim ic -d:release -d:merendaProfile -o:deps/intrinsic-buffered-profile tests/benchmark_intrinsic_buffered.nim
nim ic -d:release -o:deps/intrinsic-native tests/benchmark_intrinsic_native.nim
nim ic -d:release -o:deps/intrinsic-memory-on tests/benchmark_intrinsic_memory.nim
./deps/intrinsic-buffered
./deps/intrinsic-buffered reverse
./deps/intrinsic-buffered reverse
./deps/intrinsic-buffered
./deps/intrinsic-buffered-profile
./deps/intrinsic-buffered-profile reverse
MERENDA_BACKGROUND=1 ./deps/intrinsic-native
MERENDA_BACKGROUND=1 ./deps/intrinsic-native reverse
MERENDA_BACKGROUND=1 ./deps/intrinsic-native reverse
MERENDA_BACKGROUND=1 ./deps/intrinsic-native
/usr/bin/time -l ./deps/intrinsic-memory-on
```

`/usr/bin/time -l` is macOS-specific. The historical RSS comparison alternated
two memory binaries four times each; the cache-free build predates the current
default. Raw measurements are not tracked.
