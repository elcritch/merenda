# Intrinsic measurement and retained layout

Views cache one intrinsic-size result by default:

```nim
let field = newTextField("Amount")
discard field.sizeThatFits()
discard field.sizeThatFits() # reuses the intrinsic result if inputs are unchanged
field.stringValue = "A different amount" # normal setters invalidate measurements
field{vpCacheIntrinsicSize} = false # opt out if dependencies cannot be tracked
```

The cache wraps
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

Custom views must call `invalidateIntrinsicContentSize()`
when any otherwise untracked measurement input changes. This includes external
model state, direct custom-field mutations and replacement of the intrinsic
protocol implementation. If an intrinsic callback depends on other views or
external state, the application must establish the corresponding invalidation
connection. Set `vpCacheIntrinsicSize` to false for a view whose measurement
dependencies cannot be tracked reliably.

CollectionView, DocumentTabs and MenuBar opt out by default because their layout,
tab items or menu items can be mutated independently. A view whose subtree
contains an opted-out view also recomputes its intrinsic size so that an ancestor
cannot retain an outdated result. Policy and hierarchy changes update an
uncached-subtree count up the parent chain, so eligibility checks do not scan
descendants on every cache hit.

The audited built-in paths include:

| Measurement | Inputs and invalidation |
| --- | --- |
| Label and TextField | Text, font and theme/style metrics affect their cell measurement; normal text and appearance changes invalidate it. Editable or selectable text fields use their cell's natural-width policy. |
| Button | Title, reserved titles, type, icon and appearance metrics affect its cell measurement; the control and cell mutation paths invalidate the result. |
| Custom cells and protocols | Replacing a cell invalidates its control; a cell whose metrics change must call `invalidateControlMetrics`. Replacing an intrinsic protocol or changing an external dependency requires the view to invalidate explicitly. |

The paired cache-on/off regression tests exercise state-dependent theme metrics,
cell replacement, reserved titles, external dependencies, protocol replacement,
reentrant invalidation, editing and composition, including resulting frames. They
do not establish correctness for arbitrary user-defined measurement dependencies.

The entry is a plain value stored on the view. It creates no Sigil or separate
identity object per measurement. It retains one result rather than a map of
proposals. Geometry invalidation is conservative: frame changes can invalidate a
cache even when a particular widget's intrinsic measurement would be unchanged.
On the measured arm64 build the cache adds 32 bytes per `View`, including padding,
whether or not that view opts out; the exact size depends on compiler and target.

## What is reused

FormView now records label and field measurements when collecting metrics and
reuses them for placement. StackView already collected natural child sizes once
per arrangement. Its additional reads occurred in separate intrinsic/constraint
phases, where geometry can change. The cache allows those queries to reuse
intrinsic results when dependencies remain valid; it does not blindly share a
snapshot across a solver frame change.

## Intrinsic diagnostics

Compile with `-d:merendaProfile` and install a classifier on the GUI thread to
collect intrinsic-cache decisions by widget category:

```nim
import merenda/nimkit/debug/viewprofiling
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
checks. It predates enabling caching by default.
The [buffered collection comparison](benchmarks/intrinsic-buffered/README.md)
adds editing, scrolling, insertion, reorder, resize, native render submission,
and storage measurements for the current virtualized demo.

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
`root{vpPersistentLayout} = true` to opt a stable live root into a retained
solver. Fitting remains fresh. Trees with CSS layout rules are ineligible;
autoresizing, intrinsic, container and authored constraints are supported. Each
reuse regenerates and compares every input, replaces changed constraints in place,
and falls back to a fresh solve when the hierarchy or constraint count changes.
Non-required constraints can tie, so equivalence with a fresh solve is tested, not
proven.
The [prototype comparison](benchmarks/persistent-layout/README.md) records its
lifecycle, budget semantics, correctness coverage, and measured limitations.

Changing autoresizing translation also invalidates the intrinsic equation bucket,
because translation determines whether those equations participate in a solve.

Regression coverage lives in `tests/nimkit/intrinsiccache.nim`, `stackviews.nim`,
`formviews.nim` and `constraints.nim`, all in the shared NimKit runner. Measurements
and their workload limits are recorded with the benchmark artifacts.
