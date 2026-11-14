# Intrinsic measurement and retained layout

Views can opt into one bounded intrinsic-size cache entry:

```nim
let field = newTextField("Amount")
field[vpCacheIntrinsicSize] = true
discard field.sizeThatFits()
discard field.sizeThatFits() # reuses the intrinsic result if inputs are unchanged
field.stringValue = "A different amount" # normal setters invalidate measurements
```

Caching is off by default, including for custom widgets. The cache wraps
`resolvedIntrinsicContentSize`; it does not cache a constraint solve, arrangement,
or the full result of `sizeThatFits`. A fitting proposal and any fallback to current
bounds are still evaluated for each call. Direct calls to a concrete widget's
intrinsic implementation bypass this wrapper.

## Dependency contract

Standard intrinsic/layout, hierarchy, visibility, appearance and geometry
invalidation clear affected cached results. Appearance changes invalidate the
affected subtree. Authored and layout-owned geometry changes invalidate the view
and dependent ancestors; unchanged layout frames preserve the entry. A separate
measurement revision prevents a callback that invalidates during measurement from
publishing its result as a valid cache entry.

Opting in asserts that a custom view will call `invalidateIntrinsicContentSize()`
when any otherwise untracked measurement input changes. This includes external
model state, direct custom-field mutations and replacement of the intrinsic
protocol implementation. If an intrinsic callback depends on other views or
external state, the application must establish the corresponding invalidation
connection. Opt-in is not a promise that arbitrary custom callbacks are pure.

The entry is a plain value stored on the view. It creates no Sigil or separate
identity object per measurement. It retains one result rather than a map of
proposals. Geometry invalidation is conservative: frame changes can invalidate a
cache even when a particular widget's intrinsic measurement would be unchanged.

## What is reused

FormView now records label and field measurements when collecting metrics and
reuses them for placement. StackView already collected natural child sizes once
per arrangement. Its additional reads occurred in separate intrinsic/constraint
phases, where geometry can change. The opt-in cache allows those queries to reuse
intrinsic results when dependencies remain valid; it does not blindly share a
snapshot across a solver frame change.

DirectViews also install final StackView child order in a batch, with a cheap
unchanged-order check. That optimization produced the large reversal improvement
in the [container benchmark](benchmarks/layout/README.md). It is separate from
measurement caching and excludes the subsequent solve and drawing.

## Ancestor invalidation

Outside a layout transaction, feedback reset and aggregate dirty propagation now
share one ancestor walk. The optimization preserves notifications, revision
increments, and synchronous observer/reentrant behavior. A five-view chain uses
15 visits in the fused loop versus 30 across the previous two loops.

The notification cascade still emits along the ancestor chain, so its worst-case
depth cost remains quadratic. Active layout transactions retain their existing
feedback logic. This change does not introduce a persistent constraint solver or
independent constraint islands.

Regression coverage lives in `tests/nimkit/intrinsiccache.nim`, `stackviews.nim`,
`formviews.nim` and `constraints.nim`, all in the shared NimKit runner. Measurements
and their workload limits are recorded with the benchmark artifacts.
