# TODO: Compare declarative NimKit view designs

Baseline reviewed and measured on 2026-11-14: implementation `d22ea40d`,
benchmark harness `0c2a630d`, [draft PR #224](https://github.com/elcritch/merenda/pull/224).
This records the current prototype, not a commitment to its final architecture.
See [the usage guide](docs/declarative-views.md) and
[the editable-list demo](examples/declarative_views_demo.nim).

## What this approach actually does

`viewBody:` rewrites capitalized `VStack`, `HStack`, `Label`, `Button`, and
`TextField` nodes into ordinary constructors returning a `ViewSpec` object.
Component procedures and `keyed(id)` compose those values. A `DeclarativeView`
validates and walks a complete description, matches children by sibling identity,
patches existing widgets through their setters, and reorders retained children.
Applications own their models and explicitly request updates.

Inline event blocks create existing ActionTarget adapters with weak receivers,
non-capturing handlers, and optional explicit context such as a task ID. A second
path, `buildDetachedView`, constructs fresh widgets without installing event
bindings, so the same descriptions can supply Dragology's layout/render previews.

This is a value-description tree plus a retained-widget reconciler. It does not
yet provide dependency tracking, remembered component state, a recomposition
scheduler, or a general widget adapter protocol. The SwiftUI-like spelling should
not be mistaken for those runtime guarantees.

## Evaluation contract to keep across alternatives

The target remains an editable, keyed, reorderable task list:

- [x] Insert/reorder rows and change an unrelated counter while retaining the
  same text field, field editor, focus, selection, and marked text.
- [x] Echo user edits through the model without resetting the editor.
- [x] Refresh handlers and explicit task context after keyed moves; prevent
  removed controls from continuing to invoke the model.
- [x] Reject duplicate sibling identities before changing the live hierarchy.
- [x] Build detached previews without invoking application handlers; compare
  their row geometry with the live tree.
- [x] Keep a controller's inline handlers from retaining that controller.
- [ ] Extend the contract to validation, formatted inputs, undo grouping,
  asynchronous model changes, nested components, and conditional helper roots.
- [ ] Specify deletion of the actively edited row, focus restoration, and
  cross-parent moves rather than relying on incidental widget behavior.

The checked items have coverage in
[the shared declarative tests](tests/nimkit/declarativeviews.nim). Native demo
automation also exercised editing, selection, insertion, reversal, counter
changes, and preview drag commits. Marked-text preservation is covered by editor
tests; those checks do not replace testing real platform IMEs and accessibility
tools. Performance measurements below do not exercise a live editing session.

## Advantages and their costs

| Current choice | Advantage | Cost or limitation |
| --- | --- | --- |
| Small macro over typed constructors | Ordinary Nim composition and control flow; the non-macro API permits separate syntax/runtime comparisons. | Contextual syntax, a restricted AST grammar, and weaker editor assistance than ordinary constructors. |
| One closed `ViewSpec` variant | Easy to inspect, validate, and interpret for both live and detached views. | Only four widget kinds; adding one changes the variant and mounting/property interpreter. It is not an open third-party extension surface. |
| Explicit model ownership and updates | Scheduling and effects are visible; no hidden observation graph. | Every refresh rebuilds and traverses the whole supplied body, even for an unrelated counter. Callers must remember to refresh. |
| Keys plus structural slots | Reorder keeps real widget identity; an optional preceding sibling does not shift later slots. | Keys are sibling-scoped. Slots describe syntax positions, not durable application identities or full component-state identity. |
| Existing widget setters and layout | Reuses NimKit's editing, responder, theme, accessibility, and invalidation behavior. | Inherits their costs and failure behavior; a successful diff is not a cheap frame. |
| Weak-receiver ActionTarget handlers | Events live beside controls; receiver lifetime and row context are explicit; accidental captures are rejected. | Verbose typed handlers/sender casts; new adapters are allocated on description evaluation. Arbitrary owning references in context still retain their objects. |
| Detached widget materialization | Live and speculative paths share description and layout semantics. | Each preview still constructs widgets, lays them out, and captures drawing. This is not a lightweight geometry-only evaluator. |
| Changed-property patching | Avoids many setters and preserves live editor state on unrelated updates. | The description is compared with the previous description, not all current widget state. External mutation of managed properties can leave the model and widget out of sync. |

## Limitations and issues to resolve

### Update cost and scaling

The current reconciler has no subtree dirty flags, equality cutoff, dependency
tracking, or scheduling/coalescing layer. Even a cached unchanged description is
validated and reconciled again. Rebuilding a description additionally creates
strings, child sequences, and inline event adapters. `updateStats.created == 0`
counts newly created widgets; it does **not** mean zero allocations or zero work.

The sibling hash table does not make a complete update linear. For every retained
child, the current code reads the arranged-subview sequence and calls
`setArrangedSubviewSizingPolicy`, which scans for that child even when its sizing
policy is unchanged. A wide parent therefore has repeated linear scans on the
no-op path. Reordering repeatedly calls `insertArrangedSubview`, which rebuilds
child order, scans membership, and can sort with comparators that also search.
These are concrete implementation costs, not inherent requirements of a
declarative API. See [mounts](src/merenda/nimkit/declarative/mounts.nim) and
[StackView](src/merenda/nimkit/containers/stackviews.nim).

`remember` assigns a complete specification before clearing its child sequence.
The cost of these value copies and temporary sequences needs allocation profiling.
So do `arrangedSubviews` copies and the temporary matching tables. Avoid assuming
that a plain `object` is allocation-free or cheap to copy.

There is no virtualization. Off-screen rows still have widgets, descriptions,
adapters, and layout work. Dragology can multiply preview cost by the number of
candidate states. The demo also refreshes its preview after each title edit;
typing latency includes work outside the live reconciler.

### Identity is intentionally narrow, and has unresolved edges

- Explicit keys are unique among siblings, not across the entire tree. Moving a
  keyed row to another parent creates a new instance. Changed widget kinds reset
  identity; `HStack` and `VStack` are the same stack kind with different properties.
- Unkeyed repeated nodes are rejected when they produce duplicate slots. A loop
  that happened to produce one node can start failing when a second item appears.
- Macro slots are expansion-local ordinals. They are not persistence/restoration
  keys, and changing source structure can change them.
- A helper call overwrites its returned root's slot with the caller's slot.
  Conditional roots of the same widget kind inside a helper can consequently
  share identity. We need an explicit component/branch identity contract and
  targeted tests; use explicit keys when a root must reset today.
- Reusing an ID for a different model entity can preserve the wrong editor/state.
  The framework cannot infer semantic identity from an item's current position.

### Editing is a policy, not a complete binding system

An unchanged authored text value leaves live editing alone. An echoed value that
already matches the editor is not rewritten. A different external value is
authoritative and can replace editing contents. These rules work for the current
evaluation, but do not settle formatting, validation, commit/cancel, conflict
resolution, or undo semantics. A normalizer that changes the model on every
keystroke may legitimately trigger a disruptive write.

Only the declarative `onChange` is suppressed during a programmatic patch. Other
NimKit observers keep their existing behavior. Updates are synchronous on the GUI
thread; slow builders or setters block that thread. There is no batching,
transaction boundary, effect lifecycle, or asynchronous cancellation contract.

### Ownership, purity, teardown, and exceptions

- `ViewSpec` is a value object, but its event bindings retain identity-bearing
  action adapters. It is not a serializable, independently owned, or automatically
  thread-safe snapshot. Normal Nim reference semantics still apply to context.
- Inline action creation initializes adapters and weak receiver links even when
  the resulting description will only be used for a detached preview. Detached
  materialization omits wiring; it does not remove builder-time costs or enforce
  purity. Builders can still run arbitrary Nim code and cause effects.
- Explicit closure adapters can create ownership cycles. Weak receiver handlers
  avoid retaining the receiver only if their context does not retain it indirectly.
- Call `host.clear()` when externally retained controls might outlive the host.
  Dropping the host is not a substitute for the explicit deactivation contract.
- Duplicate-identity validation precedes mutation. Exceptions from widget setters
  or lifecycle hooks can still leave a partially applied hierarchy and mount
  bookkeeping. There is no rollback/recovery guarantee. Add fault-injection tests
  before presenting updates as transactional.
- Recursive updates during patching are rejected. Ordinary event handlers can
  update or clear a host synchronously, but that is not a general reentrancy model.

### Surface area and tooling

The built-in widget set, exposed properties, and layout choices are small. There
are no general modifiers, style/environment scopes, bindings, reusable local
state slots, fragments, portals, lazy lists, or arbitrary imperative-view adapters.
One root is required and checked at runtime. Control blocks support one event
binding. Only the documented control-flow forms are rewritten; unsupported
constructs need better diagnostics.

Capitalized nodes are macro syntax, not direct widget construction. This improves
the layout's readability but needs tooling/documentation support. Public mutable
`ViewSpec` fields and slot metadata also expose implementation details that a
future adapter design may want to hide. Stable API naming and constructor defaults
should be revisited before promising compatibility.

## Basic benchmark baseline

The [harness](tests/benchmark_declarative_views.nim) is deliberately separate from
pass/fail unit tests and does not impose machine-dependent timing thresholds.

### Setup and reproduction

- Apple M3 Pro, arm64, 36 GiB RAM; macOS 15.7.9 (24G830).
- Nim 2.4.2 (`b27dcb4f`), `nim ic`, Apple Clang 17.0.0; release, ARC,
  threads enabled, `useMalloc`, repository/test configuration unchanged.
- Two separate sequential process runs, five measured batches per case/run.
  Each case has two warmup operations and a calibration operation. Batches aim
  for 20 ms, with 1–2,000 operations depending on cost. The table reports the
  median of the ten batch means, in **milliseconds per operation**. These are
  not p95 input latencies or confidence intervals.
- Each row has a stack, label, text field, and button. The body adds a root stack
  and counter label: `4N + 2` described widgets, plus the live host. There are
  two event bindings per row in all cases except `describe_no_actions`.
- Layout uses a 600-point-wide, `54N + 50`-point-high eager tree and the default
  appearance. All rows participate; there is no scrolling or virtualization.
- No native window, event-loop pumping, GPU presentation, or active field editor.
  Update-only cases never flush layout; repeated invalidations can coalesce.
  The layout/capture cases include a guard walk rejecting blocked solves.
- Description-only cases include releasing the generated descriptions/adapters.
  Mount, detached-build, and capture cases use a prebuilt description and include
  teardown; they exclude description generation. Global/font caches are warmed,
  so “mount” does not mean first application launch.
- Correctness guards check retained widget identity, expected create/remove/move
  counts, suppressed model callbacks, preview element count, and layout budgets.
  Blocked layout produces a status record with no timing, not a fast sample.

```sh
nim ic -d:release -o:deps/benchmark_declarative_views tests/benchmark_declarative_views.nim
MERENDA_BACKGROUND=1 ./deps/benchmark_declarative_views --csv:/tmp/declarative-run1.csv
MERENDA_BACKGROUND=1 ./deps/benchmark_declarative_views --csv:/tmp/declarative-run2.csv
# Optional smaller or alternative sample:
MERENDA_BACKGROUND=1 ./deps/benchmark_declarative_views --rows:10,100 --samples:5
```

Raw samples, including each batch's iteration count and blocked-case diagnostics:
[run 1](docs/benchmarks/declarative-views/2026-11-14-m3pro-run1.csv),
[run 2](docs/benchmarks/declarative-views/2026-11-14-m3pro-run2.csv).
Each file has 185 valid batch samples and two explicit blocked-case records.
Filter on `status == "ok"` before aggregating `us_per_op`; divide by 1,000 for ms.

### Results

| Timed operation | 10 rows | 100 rows | 300 rows |
| --- | ---: | ---: | ---: |
| Description only, no event bindings | 0.023 | 0.223 | 0.676 |
| Description only, two inline actions/row | 0.062 | 0.627 | 1.916 |
| Update a cached, identical description | 0.037 | 0.378 | 2.141 |
| Rebuild body + unchanged update | 0.104 | 1.041 | 3.461 |
| Rebuild body + unrelated counter change | 0.106 | 1.043 | 3.467 |
| Rebuild body + one title change | 0.107 | 1.043 | 3.457 |
| Reverse model + rebuild body + update | 0.121 | 2.308 | 29.316 |
| Insert at head, then remove (two updates) | 0.527 | 2.397 | 7.465 |
| Counter change + update + layout | 9.533 | 133.862 | **Blocked** |
| Direct counter-label setter only | 0.0016 | 0.0017 | 0.0015 |
| Mount prebuilt description + clear/drop | 3.202 | 31.826 | 100.737 |
| Build detached widgets + drop | 3.056 | 30.048 | 95.691 |
| Detached build + layout/render capture + drop | 14.000 | 180.243 | **Blocked** |

**The 300-row layout failure is part of the result.** Both runs hit the unchanged
500 ms cooperative solver time budget (`lslTime`) in the live layout and detached
preview cases. Their diagnostic roots contain 1,203 and 1,202 views respectively.
No successful layout/preview latency is reported for these cases. Update-only
and construction results at 300 rows do not establish that a usable 300-row UI
can be laid out by this path. See also [the solver roadmap](TODO-solver.md).

The capture API can still return elements after a budget-blocked layout; the
benchmark's subsequent layout-state check rejects that result. A nonempty preview
is therefore not proof of valid layout. Propagating failure to candidate selection,
or deliberately retaining known-good geometry, needs an explicit contract.

The largest difference between the two runs' successful per-case medians was
6.9% (300-row reversal). Its batch means ranged from 28.33 to 30.65 ms. At 100
rows, counter-plus-layout ranged from 133.65 to 134.32 ms, and preview capture
from 177.02 to 183.81 ms. These are local desktop microbenchmarks without CPU
pinning or fixed clocks; report the raw samples alongside future comparisons.

### What these measurements suggest

1. **Retaining widgets works, but no-op updates are not free.** A cached 100-row
   description still takes 0.378 ms to validate/reconcile. Regenerating its body
   raises this to 1.041 ms despite zero newly created widgets. The corresponding
   300-row costs are 2.141 and 3.461 ms.
2. **Inline action construction has measurable cost.** Building the 100-row
   description with two bindings per row takes 0.627 ms versus 0.223 ms without
   them, about 2.8 times as much. This measures adapter creation/lifetime work,
   not event dispatch. Consider separating handler descriptions from installation.
3. **An unrelated change pays for the whole body.** A 100-row counter update
   costs 1.043 ms without layout, while directly setting that label costs about
   1.7 microseconds. The latter is only a lower-bound comparison for this one
   mutation, not a complete alternative framework with equivalent behavior.
4. **Reordering scales worse than ordinary updates.** Going from 100 to 300
   rows triples the row count but increases reversal time about 12.7 times, to
   29.316 ms before layout. Retained identity alone does not make rearrangement
   cheap. The repeated StackView scans/sorts are a profiling target; these timings
   alone do not attribute all cost to one function or prove an asymptotic bound.
5. **Layout dominates this eager workload.** The 100-row counter-plus-layout
   path takes 133.862 ms, compared with 1.043 ms for update alone. This is already
   much longer than a 16.7 ms frame interval, even without rendering to a window.
   Small diff timings must not be presented as evidence of interactive frame rate.
6. **Detached previews preserve isolation, not low cost.** One 100-row preview
   takes 180.243 ms including widget construction, layout, capture, and release.
   Building/dropping its detached widgets alone takes 30.048 ms. The full set of
   Dragology candidates was not timed; a single capture is not drag-start latency.

Not measured: allocator counts/bytes, peak RSS, native frame/input latency, real
IME sessions, GPU work, cold startup, compile time, binary size, complete drag
candidate enumeration, or another OS/machine. `sizeof(ViewSpec)` was 136 bytes on
this target; this excludes strings, child buffers, adapters, widgets, and shared
resources and must not be used as a total-memory estimate. There are no measured
results yet for the alternative architectures below.

## Declarative composition and MVC

Source review on 2026-11-14, against the prototype and existing NimKit MVC
implementation. The recommendations below are proposed experiments, not features
already provided by `viewBody`.

### They describe different architectural choices

MVC assigns responsibilities: the model holds application data, the controller
coordinates operations and presentation, and views handle display and interaction.
A declarative body specifies how to describe and update those views. The current
demo already combines the two: `TaskModel` is a plain value, `TaskController` is a
`ViewController`, and `viewBody` produces the controller's view description.

The useful comparison is therefore between different ways of implementing the
view/synchronization part of MVC, rather than between MVC and its replacement.

| Concern | Direct retained-view MVC | Current declarative prototype | Proposed combination |
| --- | --- | --- | --- |
| Composition | Controller constructs and arranges widgets. | Body constructs values; mount creates widgets. | Keep the body syntax and ordinary Nim helpers. |
| Synchronization | Controller updates known widgets and reconciles structural changes explicitly. | Caller refreshes a whole body; mount reconciles it. | Controller/model events invalidate explicit body scopes; mount reconciles within each scope. |
| Identity | Controller or collection owns widget/item correspondence. | Sibling keys and structural slots retain widgets. | Use entity IDs consistently, while keeping model identity, view keys, and reuse IDs distinct. |
| Commands | Target/action, responder chain, validation, and undo can share a controller operation. | Inline handlers use ActionTarget but directly mutate the demo model and refresh. | Keep inline wiring; delegate reusable operations to controller/domain commands. |
| Editing | Existing controls own editors, provisional text, formatting, and validation. | Text patches preserve an editor; the DSL exposes text-change callbacks. | Add explicit binding/commit policies over existing editing protocols. |
| Lifetime | Controller loading, containment, appearance, and teardown. | Host lifetime and `clear()` are managed by the caller. | Attach mounts and subscriptions to controller lifetime. |
| Speculation | Application must provide a separate construction/projection path. | Same descriptions can build detached Dragology previews. | Keep a pure model-to-description path alongside live MVC infrastructure. |

The declarative layer should own composition, matching, property patching, and
binding installation. Domain rules, document persistence, command validation, and
undo belong to the existing application/controller layers. Dependency discovery
is a separate choice: MVC does not require automatic observation, and declarative
composition does not require every field to become a Sigil.

### Reuse controller lifecycle and commands

[ViewController](src/merenda/nimkit/app/viewcontrollers.nim) already provides lazy
`makeView`, represented-object changes, child containment, responder-chain
installation, UI validation, undo-manager lookup, and explicit teardown events.
An integration can own a declarative host and its subscriptions there. In
particular, use `willTeardown` to disconnect bindings and clear the host; hiding a
view should not implicitly destroy its editing state. The demo currently calls
`live.clear()` in a `defer`; controller integration is not automatic today.

Use a controller for a screen or independently managed panel, not one controller
per label or scalar field. A smaller body-update scope need not be a new controller.

Keep event wiring beside the control, as requested for this DSL. For example, an
inline Reverse handler could call a proposed `receiver.reverseTasks()` operation.
That operation can also serve a menu or keyboard action without duplicating model
mutation, undo registration, and invalidation in each handler. This preserves the
layout integration without returning to detached callback variables and manual
weak-receiver lookups.

There is an actual routing gap to address. Ordinary
[Control.sendAction](src/merenda/nimkit/controls/controls.nim) uses the window's
responder chain when no explicit target is supplied. In contrast,
[dispatchViewAction](src/merenda/nimkit/declarative/actions.nim) only sends locally
to an explicit target. The mount also installs a private `declarativeViewAction`
selector on buttons, obscuring the underlying application's command selector.
Named-command routing and validation therefore need deliberate integration.

Support both inline receiver/context handlers and named commands. Preserve the
real command selector for validation and distinguish intentional responder-chain
dispatch from an expired weak receiver: the latter must remain inert. Existing
[resource commands](src/merenda/nimkit/resources/resrccore.nim) already distinguish
responder-chain, application, and explicit targets; use that vocabulary where
appropriate instead of inventing unrelated semantics.

### Use model events as explicit invalidation boundaries

[Model controllers](src/merenda/nimkit/app/modelcontrollers.nim) already offer
ObjectController, ArrayController, TreeController, and identifier-based
SelectionController. They expose change signals and post `nkModelMutationDidChange`
notifications carrying identifiers, field keys, an index, and a count. These are
useful inputs to scoped updates:

- A counter change invalidates the counter region.
- A title change invalidates that task's row and affected preview content.
- A task insertion or reorder invalidates list membership/order.
- Sorting or filtering can change the presentation order even when one field
  changed, so it may invalidate the list rather than just a row.

This requires an explicit dependency mapping or subscriptions. A helper such as
`taskRows()` currently returns ordinary values and does **not** establish a cached
component or an independently invalidatable mount. Model events alone cannot
infer which arbitrary Nim expressions depend on a changed field.

The notifications are also not a complete collection edit script. ArrayController
insert, remove, and move currently all report `mmkItemsChanged`; the payload does
not supply a full before/after index mapping. Source indexes can differ from
sorted/filtered indexes. Recompute keyed presentation membership or introduce a
well-defined change-set contract before driving incremental widget operations.
Existing `bindTableView`/`bindCollectionView` helpers wire data sources and perform
an initial reload; they do not themselves install automatic model-mutation-driven
incremental refreshes.

A controller-owned invalidation queue could coalesce notifications and flush on
the GUI thread, with a deterministic flush for tests and synchronous consumers.
Specify reentrant changes, notification order, and teardown before relying on it.
Explicit scope dependencies can become stale when a body starts reading another
field; this is the main correctness cost versus automatic dependency tracking.

Keep the typed `TaskModel` as the source of truth. ArrayController's `ModelItem` and
`ObjectValue` representation is useful for generic data-source widgets, but forcing
every application through it would lose type precision and can create a second,
unsynchronized model. A typed controller can publish equivalent changes directly,
or expose an adapter over the model. SelectionController is independently reusable.

### Build repeated-content support on existing collections, with fixes

[CollectionView](src/merenda/nimkit/containers/collectionviews.nim) already queries a
data source for item identity/content, creates visible item views, recycles views
by reuse identifier, and delegates layout and configuration. This is already a
form of declarative projection: the application supplies what an item is, while
the collection owns its widget lifetime. A declarative row body could fit into
`viewForCollectionItem`/`configureCollectionItemView` instead of requiring a second
collection framework.

However, the current implementation needs work before it meets our evaluation
contract:

- `applyCollectionUpdates` clears all mounted item and supplementary slots for
  every update kind, then retiles. Reuse does not guarantee the same task retains
  the same text field or field editor after a move.
- Visible slots are matched by index during viewport synchronization, and rows
  leaving the viewport are recycled. An actively edited row needs a defined
  pinning, commit, or cancellation policy before reuse for another entity.
- The default visible-index calculation scans every item. Bounding live widget
  count does not by itself make all list work proportional to visible rows.
- `CollectionView` is not one of the current `ViewSpec` node kinds. Integration
  needs a widget adapter or an explicit composition boundary.

Improve stable identifier matching and editor lifetime in the shared collection
implementation so imperative MVC and declarative clients both benefit. A reuse
identifier describes a compatible widget shape; it is not an entity ID. Similarly,
`keyed(taskId)` is local to a declarative sibling group, while `View.identifier`
also serves lookup/Dragology. These concepts should remain distinct even when
their values derive from the same task ID.

### Reuse editing, validation, document, and undo mechanisms

[Control](src/merenda/nimkit/controls/controls.nim) already supports formatting,
parsing, `validateValue`, `shouldCommitValue`, and commit/failure notifications.
[TextField](src/merenda/nimkit/text/textfields.nim) uses these when deciding whether
editing may end and when committing the editor's contents. A future binding needs
an explicit choice between provisional text updates and validated model commits.
Keep cursor, selection, and IME composition in the existing editor; do not make
re-evaluated view descriptions the sole owner of that transient state.

The current DSL's `onChange` subscription does not install the receiver as the
text field's validation target. Adding a model callback therefore does not yet
connect controller validation protocols. An adapter must preserve or forward that
target relationship and avoid confusing programmatic value changes with user
commits. Failed validation, cancellation, and external changes during editing need
defined behavior, not just text equality checks.

[Document](src/merenda/nimkit/app/documents.nim) and
[UndoManager](src/merenda/nimkit/foundation/undomanagers.nim) already provide
persistence lifecycle, clean-state tracking, grouped edits, value changes, and
collection undo operations. Register undo at the accepted controller/domain
operation, not during body evaluation or speculative preview construction. The
toolbar and drag commit should share those operations; a completed text edit may
need one undo group rather than one application-level undo entry per keystroke.
Multiple controllers can project the same document without each owning a copy of
its persistent state.

### Keep Dragology's snapshot boundary explicit

The reusable part is a model transition and its view projection. Preview a proposed
transition using plain model values and detached descriptions; validate and commit
it through the live controller exactly once. Do not create live controllers,
subscriptions, or undo entries for each candidate. Observation and other effects
belong to the live mount/commit path, not to the body builder.

Scoped invalidation exposes an important edge in
[the demo](examples/declarative_views_demo.nim): its drag commit replaces the whole
`TaskModel`, including the unrelated counter. Currently every ordinary refresh
also assigns `preview.model`, and
[that setter](src/merenda/nimkit/interaction/dragcontrollers.nim) cancels the active
drag and rebuilds its snapshot. Simply skipping that assignment for counter
changes would leave stale candidate models that could overwrite a newer counter.

Before caching preview geometry independently, choose a consistency policy:
cancel/rebuild on relevant model revisions, reject stale commits, or commit an
operation such as moving a task by stable IDs against the current model. Reusing
unchanged geometry must not mean reusing stale application state. A narrow task
snapshot/transition is another option, provided commit preserves unrelated state
and checks that its task assumptions still hold.

### Next comparison to run

The most useful next experiment is **controller-owned scoped declarative updates**
using the existing retained widgets. It can retain `viewBody`, inline action wiring,
and the detached preview path while testing MVC reuse independently of a syntax
rewrite or a new state system:

1. Put reusable model operations behind controller methods, and connect mount
   teardown to controller teardown. Exercise menu/keyboard/button parity and
   command validation as named-action support is added.
2. Give the counter and task list separate update scopes, driven by explicit
   controller changes. A counter update must not evaluate task row bodies or
   allocate their handlers. Keep preview state coherent using the policy above.
3. Add validated edit/undo and external model-change cases to the existing keyed
   editor-preservation contract. Measure the same eager-list workload first.
4. Separately test a CollectionView row adapter after fixing identity-preserving
   updates. Compare equal viewport sizes and scroll/edit behavior; report this as
   a different workload from the existing all-rows-visible benchmark.

The current 100-row counter result is 1.043 ms for body/update and 133.862 ms with
layout; the 0.0017 ms direct setter excludes layout and reconciliation. These
suggest testing narrower invalidation, not claiming that MVC is thousands of times
faster. Both designs can incur the same eager StackView layout cost, including the
300-row solver-budget failure. Measure body evaluations, adapter allocations,
widget/editor identity, update time, layout time, and preview rebuilds separately.
There are no performance measurements of this proposed hybrid yet.

## Comparison with SwiftUI and Kotlin Compose

Official documentation reviewed on 2026-11-14. Here, Compose refers to the
compiler/runtime model shared by Jetpack Compose and Compose Multiplatform;
Android-specific interoperability APIs below are examples, not portable APIs we
would import into NimKit. JetBrains documents the shared foundation and the
platform-specific differences in its
[Compose relationship guide](https://kotlinlang.org/docs/multiplatform/compose-multiplatform-and-jetpack-compose.html).
This is an architectural comparison, not a measured performance comparison.

### Similar syntax, different execution models

**SwiftUI** exposes custom types conforming to `View`, with a `body` composed from
other views. Its modifiers return modified view values. Builder syntax supports
nested and conditional content, but the precise builder lowering depends on the
toolchain; we should compare the public composition contract rather than assume
a particular internal tree representation.
[View](https://developer.apple.com/documentation/swiftui/view),
[ViewBuilder](https://developer.apple.com/documentation/swiftui/viewbuilder).

**Compose** defines components as `@Composable` functions participating in a
compiler-supported runtime. UI-emitting functions conventionally return `Unit`
and use capitalized names; `Button(...)` is a function call, not construction of
a `Button` description object. Value-returning composable helpers follow ordinary
Kotlin function naming. Running composables establishes a Composition that the
runtime subsequently updates through recomposition.
[Compose API guidelines](https://android.googlesource.com/platform/frameworks/support/+/androidx-main/compose/docs/compose-api-guidelines.md),
[Composition lifecycle](https://developer.android.com/develop/ui/compose/lifecycle).

**NimKit today** expands capitalized nodes into ordinary constructors returning
one closed `ViewSpec` variant. Helpers return those values without needing an
active composition runtime, and callers explicitly pass them to a live or detached
interpreter. Built-in capitalization is a readability rule, not evidence that we
have SwiftUI's type system or Compose's compiler/runtime semantics. In particular,
our lowercase `taskRow()` helper produces a value; it is not a Compose component
with its own remembered state and restart boundary.

Our design inference is that the current value-producing API is closer to
SwiftUI's description model, while its source slots and inline event syntax have
useful parallels with Compose. Neither similarity supplies automatic observation,
state storage, or scheduling. An open typed component/adapter system would also
be a separate step beyond our four built-in node kinds.

### State ownership, identity, and updates

| Concern | SwiftUI | Compose | NimKit prototype |
| --- | --- | --- | --- |
| Local state lifetime | `State` storage follows view identity, independently of temporary view values. | `remember` retains values at a composition location; leaving that location forgets them. | Controllers/models and retained widgets own state; there is no DSL-managed local state store. |
| Identity | Structural identity and explicit data identity distinguish view lifetimes. | Call sites, execution order for repeated calls, and explicit keys distinguish instances. | Sibling keys, macro slots, and positional fallback match mounted widgets. |
| Update trigger | State and observed dependencies schedule view updates. | Observed state reads and changed inputs participate in recomposition. | Application code explicitly calls `update` with a description. |
| Read/write connection | `Binding` refers to a source of truth stored elsewhere. | State hoisting can expose a value plus events requesting changes. | Description values flow down; ActionTarget handlers currently read the sender and mutate the model. |

SwiftUI ties persistent state to identity; changing identity can reset it even if
the new view looks the same. With Observation, a body's reads of an observable
model's properties establish dependencies, allowing unrelated property changes
to avoid updating that view. This Observation path requires iOS 17/macOS 14 or
later; it should not be conflated with the older ObservableObject mechanism.
Bindings provide access to existing storage rather than introducing a second
source of truth.
[SwiftUI identity and lifetime](https://developer.apple.com/videos/play/wwdc2021/10022/),
[Model Observation](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app),
[Binding](https://developer.apple.com/documentation/swiftui/binding).

Compose similarly requires stable identity when repeated components move.
`remember` alone is neither observation nor durable persistence: an ordinary
mutable object can be remembered without its field writes scheduling updates.
Observable state supplies that notification, and `rememberSaveable` addresses
restoration separately. State hoisting separates ownership from presentation by
passing current values and change requests to a component.
[State and Compose](https://developer.android.com/develop/ui/compose/state),
[Composition identity](https://developer.android.com/develop/ui/compose/lifecycle).

For NimKit, preserving a TextField instance is already valuable, but it is a
narrower promise than retaining arbitrary component-local state. Before adding
`remember`-like syntax, specify what happens when a helper changes its root type,
a branch disappears, a key is reused, or a row moves to another parent. Stable
keys alone do not define those lifetimes. Keep plain domain values; observation
should be an explicit boundary around actual dependencies, not a wrapper around
every scalar widget field.

### Selective work is a runtime contract

Compose distinguishes observing state from deciding whether a composable can be
skipped. Its current strong-skipping mode makes restartable composables skippable
even with unstable parameters, using identity or equality comparisons according
to parameter stability. It also memoizes lambdas using their captures. This is
more precise than the outdated generalization that unstable parameters always
prevent skipping.
[Strong skipping](https://developer.android.com/develop/ui/compose/performance/stability/strongskipping).

Compose also tracks state reads across composition, layout, and drawing, allowing
some changes to restart a later phase without repeating composition. Skipping a
body and avoiding layout are different optimizations.
[Compose phases](https://developer.android.com/develop/ui/compose/phases).

NimKit currently performs neither dependency-based body scheduling nor subtree
skipping. Even a cached identical `ViewSpec` is traversed, and freshly evaluated
inline actions allocate adapters. The corresponding experiment is to separate
stable mount/event-adapter identity from updated handler context and to compare
explicit controller invalidation with observed scopes. Any equality shortcut must
account for all relevant inputs, including theme/layout environment and current
event context; comparing only visible text is insufficient.

Automatic observation reduces manual dependency bookkeeping but introduces a
runtime contract developers must understand. Explicit MVC scopes are easier to
introduce into NimKit, but authors can forget to invalidate a scope when adding a
new dependency. Generated patch code may remove description work, yet still needs
correct invalidation. These are independent design choices, not consequences of
capitalized syntax.

### MVC, bindings, and effects can coexist with declarative views

SwiftUI's observable models and bindings leave a distinct model owner outside a
reusable view. Compose explicitly supports moving state into a plain state holder
or a ViewModel when ownership or business logic requires it. The architectural
lesson is to locate state and operations at an appropriate owner; it does not
require moving every operation into a view body.
[SwiftUI model ownership](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app),
[Compose state hoisting](https://developer.android.com/develop/ui/compose/state-hoisting).

NimKit's controller can serve that ownership role while retaining its additional
responder, document, and undo responsibilities. It is not API-equivalent to an
Android ViewModel. Keep inline ActionTarget wiring, allow shared named commands,
and design typed value/commit bindings over existing editing protocols. A binding
must define validation and undo policy as well as how to read and write a value.

Both frameworks provide lifecycle-aware places for effects. SwiftUI's `.task`
starts asynchronous work associated with a displayed view and cancels it when the
view leaves the hierarchy. Compose's `LaunchedEffect` cancels/restarts work with
its keys and lifetime; `DisposableEffect` handles cleanup; `rememberUpdatedState`
lets a long-lived effect use a current value without restarting just for that
change.
[SwiftUI asynchronous work](https://developer.apple.com/tutorials/instruments/executing-work-asynchronously),
[Compose effects](https://developer.android.com/develop/ui/compose/side-effects).

Those are useful contracts to borrow, but NimKit can initially implement ownership
through existing controller/mount teardown. Do not launch tasks or subscribe to
models merely by evaluating a `ViewSpec` builder: Dragology may evaluate it many
times for uncommitted alternatives. A later effects API must distinguish live
installation, dependency changes, removal, cancellation, and preview evaluation.
Retaining the latest handler context without repeatedly reinstalling an observer
is especially relevant to our existing adapter-churn benchmark.

### Existing-widget integration is a useful precedent

SwiftUI's `NSViewRepresentable` separates creation, update, and teardown of an
AppKit view, with a coordinator available to bridge delegate/target-action
interactions. On Android, Compose's `AndroidView` separates `factory` and `update`,
and its reuse-capable overload adds `onReset` and `onRelease`.
[NSViewRepresentable](https://developer.apple.com/documentation/swiftui/nsviewrepresentable),
[AndroidView integration](https://developer.android.com/develop/ui/compose/migrate/interoperability-apis/views-in-compose).

This is a concrete precedent for an open NimKit adapter contract. All our current
nodes already materialize existing NimKit widgets, so creation, property patching,
event connection, reuse, and disposal should be explicit extension points. Reuse
for another entity must be distinguishable from updating the same entity; resetting
a text editor on every update would violate our evaluation contract. Preserve the
existing widget setter boundaries and specify which layer owns each property.

These bridges also show why declarative composition does not eliminate lifecycle
or MVC coordination. NimKit can make that integration central to the DSL instead
of treating its established controllers and widgets as a separate legacy system.

### Dragology and the next design decisions

Our ordinary model-to-`ViewSpec` function is directly usable for speculative
candidate descriptions. A Compose UI function normally contributes to an active
Composition rather than returning a detached `ViewSpec`-like value; a comparable
candidate evaluator would need a managed composition/rendering host. That is a
design inference from the composition contracts above, not a claim that Compose
cannot implement Dragology.

SwiftUI already offers `ImageRenderer` to render supplied view content on demand.
Its documented coverage excludes content composited through Core Animation,
including most UIKit/AppKit views, so a preview adapter must check which controls
it can capture. Rendering an image is also only part of Dragology's contract:
candidate geometry/identity, effect isolation, capture validity, and commit behavior
still need integration.
[ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer).

For the next NimKit iteration:

- **Borrow explicit state ownership and identity lifetimes.** Keep controller/domain
  state, editor state, and any future component-local state distinct. Add lifetime
  semantics before a convenience state keyword.
- **Compare observation and explicit scopes independently of syntax.** Use the
  same editable-list test, with an unrelated counter, conditional content, and
  reordered rows. Count body evaluations and adapter allocations as well as time.
- **Borrow creation/update/reuse/disposal contracts.** Test one existing custom
  widget and one CollectionView row adapter; keep preview behavior explicit.
- **Preserve a pure description path.** Live subscription/effect installation
  should remain separate so preview candidates cannot start application work.
- **Evaluate convenience against implementation cost.** SwiftUI-style bindings
  could reduce sender casts and writeback boilerplate; Compose-style explicit
  value/events fit controller commands. Prototype both over the same validation
  and undo behavior before choosing public syntax.

The present tradeoff is a small, inspectable value API with explicit MVC ownership,
at the cost of manual refreshes, whole-body work, and limited extension/lifetime
support. The two reference frameworks demonstrate richer contracts to evaluate;
matching their surface syntax does not establish those contracts. The existing
NimKit timings remain an internal baseline. Any future cross-toolkit benchmark
must match visible content, editing behavior, rendering scope, build mode, and
hardware, and report layout/render work separately from body evaluation.

## Alternatives to compare

These are design experiments, not performance claims about SwiftUI, Compose, GTK,
or any unimplemented NimKit alternative. Several choices can be combined.

| Alternative | Potential benefit | What it must prove against this baseline |
| --- | --- | --- |
| Direct imperative retained widgets | Updates touch only known changed controls; no intermediate description tree. | Equivalent identity/editing/lifecycle behavior, plus the maintenance cost of manual reconciliation and separate preview construction. The direct-label benchmark measures only one tiny part. |
| MVC with scoped declarative bodies | Reuses controller lifecycle, commands, and model events while preserving the DSL and keyed mounts. | Correct scope dependencies, command/validation routing, coherent preview snapshots, and reduced work on the same evaluation contract; see the MVC analysis above. |
| Macro-generated patch code | Avoid a generic interpreter and some transient descriptions; retain the layout syntax. | Control-flow/key semantics, compile times, code size, useful diagnostics, and a detached preview path without duplicating UI logic. |
| Scoped reactive subscriptions or invalidation | Reevaluate only dependent components; coalesce repeated changes. | Subscription ownership, stale-read prevention, dynamic branches, reentrancy, deterministic flushes, and predictable editor/IME behavior. |
| Typed/open widget adapters with explicit create/update/dispose | Third-party controls and per-widget patch policies without growing a central enum. | Safe type erasure or specialization, update compatibility, adapter lifetime, and an explicit preview-safe contract. |
| Persistent descriptions with cached handlers/subtrees | Reduce allocation and unchanged-body traversal while keeping the current reconciler. | Correct invalidation, current event context, bounded retained memory, and a measurable improvement over cached-description updates. |
| Geometry/render descriptions without speculative widgets | Reduce Dragology candidate construction and capture work. | Identical placement, text metrics, theme resolution, clipping, and accessibility/focus separation; avoid maintaining a second inconsistent layout engine. |
| Virtualized/lazy keyed collections | Bound work by visible rows for large lists. | Focused/marked text during scrolling, off-screen state lifetime, key lookup, drag targets for unmounted rows, and scroll anchoring. |

Keep syntax, identity, state ownership, invalidation, widget adaptation, and
preview materialization as separate comparison axes. Replacing `viewBody` syntax
alone will not fix StackView ordering or layout costs.

## Next logical steps

- [ ] **Specify semantic edges first:** conditional helper roots, key reuse,
  cross-parent moves, focused-row deletion, formatted input, and teardown with
  externally retained controls. Carry the same acceptance tests to every design.
- [ ] **Profile the measured hot paths:** allocation counts/bytes, description
  copies, action-adapter churn, no-op sizing lookups, child-order rebuilding, and
  layout/capture. Keep the unoptimized baseline results for comparison.
- [ ] **Propagate layout/capture validity:** reject or deliberately fall back for
  budget-blocked previews; do not score candidates using uncommitted geometry.
- [ ] **Try a batched StackView reorder/update API:** preserve the editing session
  while avoiding per-child membership scans and repeated sorting. Measure no-op,
  reversal, head insertion, and keyboard traversal correctness.
- [ ] **Try one subtree invalidation boundary:** the unrelated counter should not
  require row body evaluation or handler recreation. Compare explicit invalidation
  driven by controller changes with a scoped Sigil subscription before adding a
  general state system. Preserve current preview state even if its geometry is
  unchanged; whole-model drag commits must not overwrite unrelated newer edits.
- [ ] **Integrate existing MVC contracts:** controller-owned mount teardown,
  named-command/responder-chain routing alongside inline handlers, validation
  targets, and shared undoable operations. Keep expired weak targets inert.
- [ ] **Evaluate CollectionView as the repeated-content host:** first preserve
  item identity through updates and define editor lifetime during reuse. Measure
  declarative row mounts without assuming current incremental APIs preserve them.
- [ ] **Try one custom widget adapter:** define create/patch/dispose and detached
  preview behavior without expanding a centralized case statement for every widget.
- [ ] **Separate binding description from adapter installation:** test whether
  handlers/context can be refreshed without allocating new adapters per body or
  during preview-only evaluation, while retaining weak receiver ownership.
- [ ] **Measure whole drag interactions:** candidate enumeration, all preview
  captures, peak memory, settling frames, and cancellation. A single-preview
  number is not drag-start latency.
- [ ] **Add user-facing latency measurements:** p50/p95 input-to-present, live IME,
  resizing, native rendering, and realistic scroll viewports on more than one OS.
- [ ] **Compare build/tooling cost:** clean and incremental compile times, binary
  size, diagnostics, completion, and debugging for value trees versus generated
  or typed adapters.
- [ ] **Publish the next comparison with the same harness/workload:** preserve
  widget counts and semantics, record any changed exclusions, and report regressions
  as well as improvements. Add timing gates only after stable baselines exist.
