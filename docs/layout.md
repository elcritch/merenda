# NimKit Layout Design

This document describes NimKit's implemented layout model: constraints,
generated layout inputs, invalidation, transaction scheduling, and
container-owned layout. The public API remains Cocoa-like where that shape is
useful, while the implementation combines Kiwiberry solving with a Qt-like
coalesced update cycle and direct Nim container layout.

## Goals

- Keep normal widget state as plain Nim fields behind setter procs.
- Use a signal bus for layout invalidation events, not reactive `Sigil[T]`
  storage for scalar view properties.
- Run at most one constraints update, one solve, and one top-down layout
  traversal per update transaction.
- Coalesce invalidation discovered during a transaction into a later update
  instead of repeatedly invoking arbitrary widget callbacks in one frame.
- Keep container output separate from authored layout input so applying final
  geometry, visibility, or scroll position cannot feed back into the same
  calculation.
- Keep authored constraints Cocoa-like and easy to inspect.
- Allow richer internal equations than the public `LayoutConstraint` shape can
  express.
- Treat generated autoresizing-mask inputs as compatibility/debug data, not as
  normal user-authored constraints.
- Keep containers such as stack, form, grid, popup lists, tables, collections,
  and cascading views container-native instead of forcing every layout through
  the solver.
- Defer a full public solver DSL until examples and controls justify it.

## Current Baseline

NimKit already has the core pieces needed to build this direction:

- `View` is an identity-bearing `ref object` with plain fields for frame,
  bounds, subviews, display flags, layout flags, constraints, autoresizing
  mask state, and intrinsic-size priorities.
- `LayoutConstraint` is a Cocoa-shaped object:
  `first.attr relation second.attr * multiplier + constant`, with priority,
  active state, and an owning view.
- `StackView`, `FormView`, and `GridView` perform intrinsic-aware container
  layout on top of the view lifecycle.
- Kiwiberry is integrated as the solver for the constraint pass.
- Autoresizing-mask compatibility currently stores reference geometry in
  `AutoresizingState` and generates internal solver constraints when a framed
  child has no explicit active constraints.
- `layoutInputChanged` is the active invalidation bus. Setters emit layout
  reasons, and the slot maps those reasons to local dirty sources, aggregate
  dirty sources on ancestors, lifecycle flags, and autoresizing state.
- Generated solver inputs are cached per source on the current solve root.
  Dirty sources can rebuild only their source bucket, while structural and
  user-constraint changes still rebuild all generated buckets.
- Layout runs as a generation-tagged transaction with explicit constraints,
  solve, and layout phases. A callback runs at most once in each applicable
  phase of a transaction.
- Invalidation during a transaction records whether a follow-up cycle is
  required. The native rendering path preserves that request after the current
  render request has been cleared.
- Scroll views and text editors compute their final geometry before applying
  it. Their internally managed frames, bounds origins, and visibility use
  layout-owned application paths that do not become new authored inputs.
- Repeated cross-frame feedback records an actionable diagnostic rather than
  retrying layout callbacks up to a fixed pass limit.

New controls should build on this core without hand-wiring cache behavior:
emit semantic layout reasons through the bus, compute container output before
applying it, use layout-owned state application for owned children, and add
focused generated-input sources only when solver participation is needed.

## Public API Shape

The public layout API should stay close to the current model:

```nim
root.addSubview(child)
child.pinEdges(toGuide = root.contentLayoutGuide(initEdgeInsets(20.0)))
child[atWidth].constraint(equalToConstant = 120.0)
```

Authored constraints should remain inspectable as `LayoutConstraint` values.
They should be active by default when created by high-level convenience APIs.
Delayed activation can stay available for the uncommon case where a caller wants
to construct a group first.

The public API should not expose a rich multi-term equation DSL yet. Most
callers should use anchors, guides, stack/form/grid containers, intrinsic size,
and priority settings. Rich equations are needed internally for generated
compatibility inputs and future container-generated solver inputs, but exposing
them too early would make the public surface harder to stabilize.

## Internal Layout Inputs

The solver should consume a common internal input representation. Public
constraints are one kind of input; generated equations are another.

Core shape:

```nim
type
  LayoutInputSource = enum
    lisUser
    lisAutoresizingMask
    lisIntrinsic
    lisContainer

  LayoutInputKind = enum
    likConstraint
    likEquation

  LayoutTerm = object
    item: View
    attribute: LayoutAttribute
    multiplier: float32

  LayoutEquation = object
    terms: seq[LayoutTerm]
    relation: LayoutRelation
    constant: float32
    priority: LayoutPriority
    source: LayoutInputSource

  LayoutInput = object
    case kind: LayoutInputKind
    of likConstraint:
      constraint: LayoutConstraint
    of likEquation:
      equation: LayoutEquation
```

This lets the public API stay simple while internal generators can express
Kiwiberry equations such as:

```text
child.left = parent.left + parent.width * share + constant
child.width = parent.width * share + constant
```

That shape is useful for autoresizing masks because the resulting child frame is
a function of the superview's current size, the reference geometry, and the
flexible margin/size bits.

## Generated Inputs

Generated layout inputs should be source-tagged and separated from authored
constraints.

Generated input sources:

- `lisAutoresizingMask`: compatibility inputs generated from frame,
  autoresizing mask, reference rect, and reference superview rect.
- `lisIntrinsic`: compression resistance and hugging inequalities generated
  from intrinsic content size, priorities, appearance metrics, and native
  container metrics such as spacing and insets.
- `lisContainer`: future container-generated relationships when a native
  container needs solver participation.

Generated inputs should be inspectable in debug APIs, but should not appear as
normal authored constraints returned by `view.constraints()`.

Current summary debug APIs:

```nim
view.constraints()               # authored constraints only
view.generatedLayoutSummary()     # generated input counts grouped by source
view.constraintsAffectingLayout() # authored/generated summary grouped by source
```

Raw generated `LayoutInput` values can remain available to focused internal
modules and tests, but the normal public API should prefer summaries so callers
do not couple to the internal equation representation.

## Signal Bus

The signal bus should be a core invalidation primitive. It should describe what
changed, then let layout storage decide which caches and flags to dirty.

Current reason enum:

```nim
type
  LayoutInvalidationReason = enum
    lirFrame
    lirBounds
    lirSuperview
    lirSuperviewGeometry
    lirSubviews # legacy broad descendant/hierarchy reason
    lirHierarchy
    lirDescendantGeometry
    lirDescendantIntrinsic
    lirHidden
    lirAutoresizingMask
    lirConstraints
    lirIntrinsic
    lirAppearanceMetrics
    lirContainerMetrics
    lirExplicit # direct needsLayout requests
```

Current signal and slot shape:

```nim
protocol ViewLayoutInputEvents:
  proc layoutInputChanged*(view: View, reason: LayoutInvalidationReason) {.signal.}

protocol ViewGeometryEvents:
  proc geometryDidChange*(view: View) {.signal.}

proc markLayoutInputDirty(view: View, reason: LayoutInvalidationReason) {.slot.} =
  let
    source = reason.sourceFor()
    structureDirty = reason.isStructureDirtyReason()

  view.xLayoutInputCache.dirtySources.incl source
  if structureDirty:
    view.xLayoutInputCache.structureDirty = true

  case reason
  of lirFrame, lirSuperview, lirAutoresizingMask:
    view.xAutoresizingState.referenceDirty = true
    view.xAutoresizingState.inputsDirty = true
  of lirBounds, lirSuperviewGeometry, lirSubviews:
    view.xAutoresizingState.inputsDirty = true
  else:
    discard

  view.noteLayoutInvalidation(reason, affectsConstraints = true)
  view.markAggregateLayoutInputDirty(source, structureDirty)
```

The exact cache fields can evolve, but the event model should stay narrow:
mutating procs emit layout invalidation reasons; the layout layer maps reasons
to dirty flags and lifecycle flags.

Superview geometry is a separate bus because child autoresizing depends on the
parent's actual frame or bounds, including frames applied by native container
layout. Child views observe their current superview's `geometryDidChange`
signal and translate that into `lirSuperviewGeometry` locally. Lifecycle slots
bind and unbind that observation when a view moves between superviews, which
avoids stale dirtying from an old parent.

When the event source and observer are both `View`, internal slots use Sigils'
`slotFor` pragma to keep descriptive implementation names such as
`markLayoutInputDirty` while binding them to public event names such as
`layoutInputChanged`. This avoids Nim-level ambiguity between the signal helper
and a same-signature slot while keeping protocol-declared event surfaces public
and inspectable.

This keeps Sigils useful as a bus without making frame, bounds, size, title,
enabled state, or other widget fields reactive values. That is less surprising
for NimKit users and keeps the current plain-field view model intact.

## Layout Transactions

Each update cycle runs one layout transaction for a dirty root:

1. A setter mutates normal view/widget state and emits a semantic
   `layoutInputChanged(view, reason)` event when the change affects layout.
2. The invalidation slot marks local and aggregate cache sources dirty and sets
   the constraints/layout lifecycle flags.
3. The transaction receives a new generation and enters
   `ltpUpdatingConstraints`. Constraint callbacks are visited bottom-up once.
4. The transaction enters `ltpSolvingConstraints`. Dirty generated inputs are
   refreshed and Kiwiberry solves the subtree once. Internal iteration inside
   Kiwiberry is still valid because it operates on mathematical state, not
   arbitrary widget callbacks.
5. Solved frames are applied through the solver-owned path, and autoresizing
   reference state is refreshed.
6. The transaction enters `ltpLayingOut`. Native container callbacks are
   visited top-down once.
7. The transaction returns to `ltpIdle`. Display preparation and drawing remain
   separate from layout.

Every view records the generation in which its constraints and layout callbacks
were visited. This gives invalidation deterministic scheduling rules:

- A not-yet-visited descendant can join the current traversal naturally.
- Invalidation of self, an ancestor, or an already-visited view is retained as
  one coalesced request for the next transaction.
- Constraint-affecting invalidation during the solve or layout phase always
  requests a follow-up transaction.
- Nested calls to `layoutSubtreeIfNeeded` do not start another transaction while
  an ancestor transaction is active.
- Repeated invalidations in one transaction set flags and update diagnostic
  metadata; they do not schedule duplicate native renders.

This is intentionally similar to Qt's deferred layout/update-event model: work
is coalesced at the update-cycle boundary. Sigils signals carry typed change
notifications, but scalar geometry does not become a reactive graph and
same-thread layout callbacks do not recursively restart layout.

## Render Scheduling

The native backend already coalesces render requests. `requestRender` returns
when a request is pending, so multiple invalidations before a frame produce one
native redraw request.

Rendering can itself discover deferred layout—for example, an asynchronous text
layout completion can arrive while the current frame is being prepared. The
window therefore records whether display/layout work remains after
`buildRenders`, submits and clears the current native request, and only then
requests the follow-up render. This preserves work discovered during rendering
without recursively rendering or losing it when the current request is cleared.

## Container-Owned State

The important feedback-loop rule is that authored input, solver output, and
container output are different operations:

- `view.frame = ...` is an authored change. It invalidates layout inputs,
  updates autoresizing reference geometry, and emits geometry changes.
- Solver frame application updates solved geometry without treating it as a new
  authored edit.
- `setFrameFromLayout` applies a container-owned child frame. It updates visible
  geometry and display state without invalidating the container's inputs.
- `setHiddenFromLayout` and `setBoundsOriginFromLayout` provide the same
  ownership rule for computed visibility and scroll offsets.

Containers must compute final geometry before applying it. A scroll view first
resolves its clip, header, corner, and scroller geometry, then applies those
results in one direction. A text editor similarly converges viewport and
document size as local mathematical state before applying its scroll-view frame,
document frame, and text container.

Manually laid-out scroll-view internals disable autoresizing-mask constraints.
Their frames, visibility, and clip bounds are owned by `ScrollView.tile`, so
that output must not regenerate solver inputs or tile the hierarchy from a draw
callback. Text layout signals remain observable, but container-owned text views
can disable propagation of intrinsic-size changes; `TextEditor` receives the
semantic text/layout signals and schedules its own layout directly.

## Feedback Diagnostics

NimKit does not retry arbitrary layout callbacks within one transaction. If a
root remains dirty across update cycles, it counts consecutive feedback cycles.
After three cycles it emits one diagnostic containing:

- transaction generation
- invalidating view
- invalidation target
- transaction phase
- invalidation reason

The latest data is also available through `layoutGeneration`, `layoutPhase`,
`layoutFeedbackCycles`, and `lastLayoutInvalidation`. A transaction that settles
resets the feedback count and diagnostic. This makes cross-frame feedback
actionable without freezing a frame in a 64-pass retry loop.

## Caching

`LayoutInputCache` is local to a layout root or container-sized subtree, not
global. That keeps solver systems small and makes invalidation bounded.

Current cache contents:

- generated inputs bucketed by `LayoutInputSource`
- local dirty flags grouped by source
- aggregate dirty flags grouped by source for the view's subtree
- a structural-dirty flag for hierarchy/visibility changes that require a
  broader generated-input refresh
- an aggregate structural-dirty flag for hierarchy/visibility changes anywhere
  in the view's subtree
- per-source generation counters for diagnostics
- a solve/cache generation number for diagnostics

The cache now rebuilds only the generated sources dirtied by the signal bus
where that is practical. First solve, user-constraint changes, and structural
changes rebuild all generated buckets because constraint participation and
view membership can change. Superview geometry changes can rebuild only
autoresizing-mask equations, and intrinsic invalidations can rebuild only
intrinsic equations.

The generated-cache refresh reads the solve root's local and aggregate dirty
state directly. It no longer scans the subtree to rediscover dirty sources
before deciding which generated source buckets to rebuild.

The solver itself is still rebuilt for the full subtree on each layout
transaction.
That keeps correctness straightforward while the cache model settles. A future
incremental solver cache can build on the same source buckets and generation
counters if examples show real pressure.

## Autoresizing Masks

Autoresizing masks should remain a compatibility path for framed views:

- A view with explicit active constraints should not also receive generated
  autoresizing constraints.
- A view with `autoresizingMaskConstraints = true` and no explicit active
  constraint participation may receive generated internal equations.
- Container-owned scroll internals and document views set
  `autoresizingMaskConstraints = false`; their owner applies frames through
  `setFrameFromLayout`.
- Generated autoresizing equations use `AutoresizingState` reference geometry
  to translate flexible margins and sizable dimensions into parent-size
  dependent equations.
- `AutoresizingState.referenceDirty` means the view's local frame, superview
  relationship, or mask changed and its stored reference geometry should be
  refreshed. `AutoresizingState.inputsDirty` means generated equations should
  be rebuilt; superview geometry changes set this without replacing the stored
  reference before the solver runs.
- These generated equations are source-tagged as `lisAutoresizingMask`.

This avoids the common Cocoa debugging problem where generated
`NSAutoresizingMaskLayoutConstraint` values look like authored constraints.

## Intrinsic Size

Intrinsic content size should continue to produce solver inputs only where it
matters:

- compression resistance produces minimum-size inequalities
- hugging priority produces maximum-size inequalities
- controls and containers invalidate intrinsic inputs when text, theme metrics,
  spacing, insets, or content changes
- a container-owned `TextView` can keep receiving text-layout signals while
  suppressing redundant intrinsic invalidation propagation; its owning editor
  schedules document layout from the semantic signal instead

The signal reason should be `lirIntrinsic`, `lirAppearanceMetrics`, or
`lirContainerMetrics` depending on the source. These currently dirty the
`lisIntrinsic` bucket because the generated equations are still intrinsic-size
inputs. `lisContainer` remains reserved for future container-generated
relationships that need solver participation. The solver should still consume
the resulting inputs through the same `LayoutInput` model.

## Containers

Stack, form, grid, popup-list, table, collection, and cascading controls remain
container-native when their layout is clearer as direct measurement and
allocation. The solver is used for explicit cross-view relationships, priority
conflicts, generated compatibility inputs, and cases where a container needs to
participate in external constraints.

A native container callback is a one-way allocation step. It should compute a
complete layout value first, then apply owned frames and state through
layout-owned setters. It must not mutate hierarchy or retile itself while
drawing, and it must not depend on a later callback in the same transaction to
correct partially applied geometry. Visible row/cell synchronization belongs in
layout, not drawing.

This avoids turning simple row/column/list layout into harder-to-debug
constraint systems while preserving the ability to compose with constraints.

## Reasons For This Direction

- A signal bus gives us a single invalidation vocabulary without making every
  property reactive.
- A generation-tagged, coalesced transaction gives the useful part of Qt's
  update-event behavior without introducing a second object/property system.
- One callback traversal per transaction keeps widget work deterministic;
  mathematical convergence remains inside the solver or local geometry
  calculation where it belongs.
- Explicit container-owned application paths prevent output-to-input feedback
  while retaining normal display and geometry notification behavior.
- Source-tagged `LayoutInput` values keep generated constraints debuggable and
  separate from user-authored constraints.
- Internal `LayoutEquation` values let NimKit use Kiwiberry's real linear
  expression support without prematurely exposing a public DSL.
- Per-root caches and dirty reasons give us a path to better performance
  without blocking the current implementation on a complicated incremental
  solver cache.
- Keeping simple containers native follows the same practical split used by
  other UI systems: direct measurement/allocation for common structure, solver
  constraints for relationships and priorities.
- Active-by-default convenience APIs avoid the awkwardness of requiring callers
  to wrap common helper output in a separate activation call.

## Open Questions

- How far to take public export narrowing for `View.x*` storage. The current
  umbrella import hides raw layout-input/cache type names, but full field
  hiding needs a deeper internal accessor or module-organization refactor
  because Nim object field visibility is attached to the public `View` type.
- Whether generated input summaries should grow richer fields, such as item
  names, attributes, priorities, or conflict diagnostics, before exposing any
  raw internal objects broadly.
- How much of the signal bus should be public. The reason enum is useful for
  diagnostics, but most callers should not need to emit layout signals directly.
- Whether the existing table and collection layout patterns justify generating
  any `lisContainer` solver inputs, or should remain entirely direct.
- Whether generated input summaries should expose rebuild/cache metadata beside
  the transaction feedback diagnostic.
- Whether container ownership should eventually become explicit inspectable
  metadata, beyond the current layout-owned application procs and disabled
  autoresizing-mask inputs.

## Sources Reviewed

Apple sources:

- Auto Layout Guide, Anatomy of a Constraint: https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/AutolayoutPG/AnatomyofaConstraint.html
- Auto Layout Guide, Unsatisfiable Layouts: https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/AutolayoutPG/ConflictingLayouts.html
- Auto Layout Guide, Debugging Tricks and Tips: https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/AutolayoutPG/DebuggingTricksandTips.html
- NSLayoutConstraint documentation: https://developer.apple.com/documentation/appkit/nslayoutconstraint
- WWDC 2011 Cocoa Auto Layout session PDF: https://docs.huihoo.com/apple/wwdc/2011/session_103__cocoa_autolayout.pdf

Non-Apple sources:

- objc.io, "Auto Layout with Key Paths": https://www.objc.io/blog/2018/10/30/auto-layout-with-key-paths/
- INNOQ, "Solving Common Auto Layout Problems": https://www.innoq.com/en/blog/2015/10/ios-auto-layout-problem/
- Swift with Vincent, `translatesAutoresizingMaskIntoConstraints`: https://www.swiftwithvincent.com/blog/do-you-know-what-translatesautoresizingmaskintoconstraints-actually-does
- StackOverflow, autoresizing mask constraint debug strings: https://stackoverflow.com/questions/14290100/when-debugging-autolayout-what-is-the-meaning-of-the-autoresizing-mask-strings-s
- Qt layout invalidation notes: https://runebook.dev/en/docs/qt/qlayout/invalidate
- QtCentre, size hint and layout update discussion: https://www.qtcentre.org/threads/20453-Layout-not-updated-when-sizeHint-changes
- web.dev, "How browsers work": https://web.dev/articles/howbrowserswork
- webperf.tips, layout thrashing: https://webperf.tips/tip/layout-thrashing/
- GTK Blog, layout managers in GTK 4: https://blog.gtk.org/2019/03/27/layout-managers-in-gtk-4/
- Kiwisolver Enaml use case: https://kiwisolver.readthedocs.io/en/latest/use_cases/enaml.html
- Enaml constraints layout guide: https://enaml.readthedocs.io/en/latest/get_started/layout.html
- Cassowary docs, theory: https://cassowary.readthedocs.io/en/latest/topics/theory.html
- Atomic Object, ConstraintLayout vs Auto Layout: https://spin.atomicobject.com/constraintlayout-vs-autolayout/
- Android ConstraintLayout chains/barriers/guides overview: https://www.suridevs.com/blog/posts/android-constraintlayout-chains-barriers-guide/
- Reddit Android developer discussion on ConstraintLayout in Compose: https://www.reddit.com/r/androiddev/comments/1j0xrqx/is_there_any_need_for_constraint_layout_in_compose/
- Reddit Swift discussion on chainable Auto Layout helpers: https://www.reddit.com/r/swift/comments/dieljs/github_simplified_and_chainable_autolayout/
