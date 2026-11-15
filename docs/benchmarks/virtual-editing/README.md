# Editable virtualized collection: preliminary comparison

These historical samples predate the half-viewport materialization buffer; the
current demo can mount more rows than the counts recorded here.

The `direct_collection_demo` row builder mounts editable DirectView rows in a
fixed 640 × 480 CollectionView backed by 5,000 items. Labels, text fields,
and buttons opt into intrinsic caching as each row is built. The benchmark
constructs the same fixture with caching off and on. Each operation has two
warmups and five samples. It runs cache-off first, then cache-on, on one machine
(Apple M3 Pro, macOS, Nim 2.4.2, release ARC). These are preliminary profiled,
headless measurements, not input-to-present latency. Timing phases can overlap.

| Operation | Cache off median | Cache on median |
| --- | ---: | ---: |
| Model title update | 14.84 ms | 9.93 ms |
| Scroll | 19.14 ms | 14.83 ms |
| Insert | 15.79 ms | 10.83 ms |
| Reorder | 15.13 ms | 10.14 ms |
| Resize | 8.33 ms | 6.61 ms |

The samples have 12 mounted rows. These small, fixed-order samples do not
establish native latency, memory use, subscription counts, frame equivalence,
or speedups for other applications. The edit operation changes the model; it is
not a timed keyboard interaction. The separate regression test exercises an
active editor through selection, scrolling, insertion, reorder and deletion in
both cache configurations. Raw sample files are not tracked. Reproduce with:

```sh
nim ic -r -d:release -d:merendaProfile tests/benchmark_virtual_editing.nim
```
