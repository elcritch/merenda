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

## Alternatives to compare

These are design experiments, not performance claims about SwiftUI, Compose, GTK,
or any unimplemented NimKit alternative. Several choices can be combined.

| Alternative | Potential benefit | What it must prove against this baseline |
| --- | --- | --- |
| Direct imperative retained widgets | Updates touch only known changed controls; no intermediate description tree. | Equivalent identity/editing/lifecycle behavior, plus the maintenance cost of manual reconciliation and separate preview construction. The direct-label benchmark measures only one tiny part. |
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
  with a scoped Sigil subscription before adding a general state system.
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
