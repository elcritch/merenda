# DirectView collection rows: diagnostic comparison

One sequential diagnostic run on Apple M3 Pro, macOS 15.7.9, Nim 2.4.2,
release/ARC/threads/useMalloc with `-d:merendaProfile`. The [raw output](2026-11-15-profile.txt)
contains all phase counts and inclusive timings. These are single observations,
not statistical estimates. Materialized cases run first and the initial case
includes font initialization; there are no warmup iterations. Instrumentation has
a cost, especially for each
constraint insertion. There is no native window, GPU presentation, allocation
count, input latency, or live IME measurement.

Both variants use the same DirectView row: a label, a text field with one
controller subscription, and a button. The materialized version places all rows
in a StackView in a ScrollView; the virtualized version uses CollectionView and
the row adapter. Each uses the same 240-pixel-wide viewport and scrolls halfway
through the model. Counts describe row hosts and subscriptions installed by this
harness (one per mounted row, plus the virtual adapter's immediate model, coalesced
model, and selection subscriptions). The virtual scroll asserts that the
destination row is mounted.
The solver size is the largest number of views and constraints in a solve call;
passes count solve calls, including a failed call. Nested timings overlap and must
not be summed; recursive calls in one phase can make its total exceed wall time.

| Items | Height | Variant | Mounted / subscriptions | Mount ms | Scroll ms | Solver views / constraints on mount |
| ---: | ---: | --- | ---: | ---: | ---: | ---: |
| 100 | 90 | materialized | 100 / 100 | 276.850 | 1.116 | 505 / 5,034 |
| 100 | 90 | virtualized | 3 / 6 | 5.154 | 4.588 | 21 / 186 |
| 100 | 180 | materialized | 100 / 100 | 213.038 | 1.813 | 505 / 5,034 |
| 100 | 180 | virtualized | 6 / 9 | 9.847 | 9.514 | 36 / 336 |
| 1,000 | 90 | materialized | 1,000 / 1,000 | blocked | blocked | 5,005 / 5,213* |
| 1,000 | 90 | virtualized | 3 / 6 | 5.925 | 4.798 | 21 / 186 |
| 1,000 | 180 | materialized | 1,000 / 1,000 | blocked | blocked | 5,005 / 5,244* |
| 1,000 | 180 | virtualized | 6 / 9 | 10.250 | 9.348 | 36 / 336 |

\* The materialized 1,000-row solve hit the 500 ms budget; its reported
constraint count is a partial count, and its elapsed time is not a valid frame
timing. At 100 rows the materialized scroll reuses an already laid out tree;
the virtualized scroll builds and lays out the newly mounted rows. This run
shows bounded row and solver size for the sampled virtual view, and also the
cost of replacing rows on a scroll. It does not show input-to-display latency.
The default fixed layout computes candidate row ranges arithmetically; model
reload reconciliation still scans model identities.

Reproduce from the repository root:

```sh
nim ic --nimcache:deps/.nimcache/ -d:release -d:merendaProfile -o:deps/benchmark_collection_rows tests/benchmark_collection_rows.nim
./deps/benchmark_collection_rows
```
