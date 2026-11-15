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

## Intrinsic diagnostics

Compile with `-d:merendaProfile` and install a classifier on the GUI thread to
collect intrinsic-cache decisions by widget category:

```nim
import merenda/nimkit/foundation/viewprofiling
import merenda/nimkit/intrinsicprofiling
import merenda/nimkit/view/viewgeometry

useDefaultIntrinsicProfileCategories()
resetViewProfile()
# Perform the layout or update to measure here.
for count in currentIntrinsicProfile():
  echo count.widgetType, " ", count.event, " ", count.reason, " ", count.count
setIntrinsicProfileClassifier(nil)
```

The built-in classifier groups subclasses into the first matching known category;
unrecognized views are `OtherView`. Applications can install a custom
`IntrinsicProfileClassifier` to distinguish other types. It must return bounded
category names and must not mutate or retain the view. Counters are thread-local,
and resetting the profile clears them without changing the classifier.

Each resolution records one of cache-disabled, cold miss, invalidated miss,
revision mismatch, or hit. Discarded and failed measurements are additional events.
An invalidated miss reports the first invalidation that cleared its previous valid
entry. `layoutFrame` and `descendantLayoutFrame` identify layout-owned geometry
changes; other names use `LayoutInvalidationReason`. A cache entry can be
invalidated before the current measurement interval begins, so the reason is not
necessarily an event in that interval. The diagnostic does not retain views. Profile
builds track cache invalidation bookkeeping even without a classifier, but collect
no category counts until one is installed; normal builds compile it out.

DirectViews also install final StackView child order in a batch, with a cheap
unchanged-order check. That optimization produced the large reversal improvement
in the [container benchmark](benchmarks/layout/README.md). It is separate from
measurement caching and excludes the subsequent solve and drawing.

The [DirectView leaf-control experiment](benchmarks/intrinsic-reuse/README.md)
compares explicit caching of the demo's Label, TextField and Button instances
against the same uncached tree. It includes paired geometry and invalidation
checks. This does not make caching automatic for controls or their subclasses.

## Ancestor invalidation

Outside a layout transaction, feedback reset and aggregate dirty propagation now
share one ancestor walk. The optimization preserves notifications, revision
increments, and synchronous observer/reentrant behavior. A five-view chain uses
15 visits in the fused loop versus 30 across the previous two loops.

The notification cascade still emits along the ancestor chain, so its worst-case
depth cost remains quadratic. Active layout transactions retain their existing
feedback logic.

## Experimental persistent solver

Compile with `-d:merendaPersistentLayout` and set
`root[vpPersistentLayout] = true` to opt a stable live root into a conservative
solver cache. Fitting remains fresh. Every view must use autoresizing constraints,
and the tree must have no active authored constraints or CSS layout rules.
Unverified changes fall back to a fresh solve.
The [prototype comparison](benchmarks/persistent-layout/README.md) records its
lifecycle, budget semantics, correctness coverage, and measured limitations.

## Experimental row graph boundary

Compile with `-d:merendaRowLayoutBoundaries` to try separate solves for eligible
DirectView collection rows. The outer solve includes each row host; the layout
transaction then fixes its solved rectangle and solves its descendants before
container arrangement, matching the existing ordering. Fitting-size solves continue
to use the full graph.

This first experiment accepts only trees with no active authored constraints or
CSS layout rules anywhere in the transaction. The path from the solve root to the
row host and every row descendant must use autoresizing constraints without flexible
width or height. This fixes the host's rectangle independently of descendant stays.
Intrinsic-driven views on that path or in the row, flexible sizes, authored anchors
(including baselines), and CSS all fall back to the existing full solve. These
restrictions avoid unproven coordinate and intrinsic dependencies, and mean typical
intrinsic-sized rows may not qualify.
If an input changes during graph construction, the transaction retries with the full
graph before applying frames.
The experiment is off by default and does not demonstrate a speedup by itself;
each eligible row adds a solver pass, so compare total time as well as graph size.
In the four-view regression fixture, the largest graph drops from four views to
three and the number of solves rises from one to two. This is a structural check,
not a representative timing benchmark.
Changing autoresizing translation also invalidates the intrinsic equation bucket,
because translation determines whether those equations participate in a solve.
The [paired comparison](benchmarks/row-boundary/README.md) measures both the
original demo and a deliberately eligible row tree. It found no intrinsic-read
reduction and found different solver-budget failure behavior; keep the boundary
experimental until transaction-wide failure handling is resolved.

Regression coverage lives in `tests/nimkit/intrinsiccache.nim`, `stackviews.nim`,
`formviews.nim` and `constraints.nim`, all in the shared NimKit runner. Measurements
and their workload limits are recorded with the benchmark artifacts.
