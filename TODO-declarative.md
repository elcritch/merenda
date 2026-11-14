# Declarative NimKit: direction and remaining work

DirectViews (P7), backed by ordinary MVC objects and scope-owned Sigils bindings,
is our main experimental direction. ViewSpec (P0) remains a comparison baseline.
[PR #224](https://github.com/elcritch/merenda/pull/224) contains both prototypes;
merging it would make the experiments available, not stabilize their APIs.

Both DSLs require explicit imports:

```nim
import merenda/nimkit
import merenda/nimkit/directviews # Retained actual views; primary experiment.
# import merenda/nimkit/declarative # ViewSpec comparison baseline.
```

The standard NimKit import continues to expose shared MVC and binding facilities.
The experimental facades may change incompatibly. This document records decisions,
current limits, and the next experiments; usage details live in the linked guides.

## Why we chose this direction

The initial ViewSpec prototype made structure inspectable and let us interpret the
same description into a live tree or a detached drag preview. Its preflight checks
and explicit property descriptions remain useful. However, each widget and property
needs an adapter, and an immutable description does not fully describe a live editor
once bindings and imperative editing own part of its state.

Figuro suggested a simpler construction model: compose actual retained widgets.
NimKit can combine that idea with its existing documents, controllers, actions,
collections, tables, and undo infrastructure. DirectViews avoids a second widget
schema while preserving ordinary property setters and typed Nim component helpers.
It does not make arbitrary body execution transactional or automatically cheap.

Our SwiftUI and Compose comparison led us to prioritize ownership, stable identity,
scoped observation, and explicit creation/update/disposal rules. Copying their
syntax alone would not provide those contracts. We are not attempting to reproduce
their complete compiler or composition runtimes, and our measurements do not compare
NimKit's performance with either framework.

The experiments also changed where we put complexity:

- Whole-collection observation was convenient but woke unrelated row getters.
  `CollectionSigil` separates order and item observation while keeping the model's
  snapshot authoritative.
- Node-owned binding scopes and ordinary components removed application-managed
  session bookkeeping from the main DirectView examples.
- Two-document and form experiments put drafts, validation, accepted edits, and
  history in MVC objects that can be tested independently of either DSL.
- `GuardedCommand` duplicated ownership already expressed by `ActionTarget`.
  We removed it. Weak receivers plus captured context and a shared controller
  validity predicate express the required checks more directly.
- Layout measurements showed that removing ViewSpec allocation alone would not
  solve the shared layout/capture cost. Container and measurement improvements
  belong below the DSLs.

The [earlier design notebook](https://github.com/elcritch/merenda/blob/5a8bf0c2/TODO-declarative.md)
retains the detailed research, debates, and superseded proposals. The alternatives
below explain what remains worth comparing without carrying old plans as current TODOs.

## Ownership and update contracts

| Owner | Responsibility |
| --- | --- |
| Document/model | Accepted data, revisions, domain commands, undo history, and document-owned work such as saving. |
| Editor/controller | Draft policy, selection, navigation generation, validation, and command validity. Drafts may deliberately be local or shared. |
| BindingScope | Observation subscriptions, weak targets, coalesced source-to-view refresh, and disconnection. |
| DirectView/component | Retained widget identity, child metadata, and owned binding scopes. Components add no wrapper widget and produce exactly one actual root. |
| Widget | Plain internal state and existing setters that perform layout, display, and responder side effects. |

A structural key identifies a sibling within its parent. Moving a key across
parents recreates its view. Reusing a domain ID may require an application-level
incarnation or generation check; a widget key is not an async validity token.

In DirectViews, named properties and body setters run on each evaluation. Omitted
setters leave the current value. Positional constructor arguments are creation-only,
except the first Button argument, which updates its title. Binding/property handoff
retires the previous owner before writing; this is not a global arbitration system
for arbitrary competing writers.

Actions use existing `onAction(owner, context)` weak receivers. Checked controller
methods such as `removeTask(owner, context)` verify the editor/document is open,
the generation matches, and the item still exists before calling the ID-based
operation. Text reads/edits and queued validation use the same validity policy.

View visibility does not decide the lifetime of document work. Suspension pauses
source-to-view refresh; it does not disable ordinary actions or text edit commands.
Closing an editor invalidates editor-specific results, while an already submitted
document save may finish independently.

## What is implemented

- **Both editable-list prototypes:** common domain commands, validation, undo/redo,
  drag snapshots, preview coalescing, stale-drag rejection, and paired tests.
  P0 retains a description interpreter; P7 retains actual typed views and supports
  independently observed components. See the [P0 guide](docs/declarative-views.md),
  [P7 guide](docs/declarative-direct-views.md), and their
  [ViewSpec](examples/declarative_views_demo.nim) /
  [DirectView](examples/direct_views_demo.nim) examples.
- **Collection observation:** indexed key lookup, read-only order/item projections,
  duplicate-key validation before publication, and coherent changed-item updates.
  Publication remains O(n + observed items); a single-item assignment still copies
  and validates a snapshot. The [local integration](docs/collection-sigils.md)
  remains separate from adopting [Sigils PR #70](https://github.com/elcritch/sigils/pull/70).
- **Property ownership and retained editing:** binding-to-property transitions,
  row reorder/removal, and field-editor focus/selection/marked-text coverage.
  CollectionView identity retention and opt-in TableView retained-cell refresh are
  available; a virtualized DirectView editor experiment is still outstanding.
- **Two documents:** independent drafts/history, switching, actual closure and
  same-ID reopening, stale queued results, and teardown checks for both renderers.
  See the [experiment and its acceptance checks](docs/declarative-two-documents.md).
- **Forms:** explicit local/shared drafts, incomplete numeric text, formatting on
  blur, Apply/Cancel, conservative revision conflicts, and external-update policy.
  The [form experiment](docs/declarative-forms.md) uses a DirectView-owned custom
  FormView with a node-owned BindingScope. Its P0 comparison supplies ViewSpec
  toolbar actions around that form; it is not a general P0 custom-widget adapter.
- **Undo:** typed semantic coalescing with identity/continuity checks, explicit
  boundaries, clean checkpoints, and a total group-count limit. New coalescing
  apply operations are non-raising. Native draft history is distinct from accepted
  document history. See [undo contracts](docs/undo-history.md).
- **Async save:** a real background write owned by the document, snapshot/revision
  capture, one in-flight save, owner-thread completion, and rejection of obsolete
  clean-state publication. A closed document can let the submitted write finish
  without publishing its result. The example writes to a private temporary
  directory; Save/Close's in-memory checkpoint is a separate policy.
- **Optional suspension:** `suspendUpdates`/`resumeUpdates`, lifecycle-hook example,
  queued-ticket invalidation, coalescing while hidden, parent-first refresh on
  resume, and reentrant teardown tests. Hiding does not suspend by default.
  Widgets and subscriptions are retained; resuming reads current state. See the
  [lifetime example](examples/direct_lifetimes_demo.nim).
- **Layout work:** P7 commits StackView child order in one batch; FormView reuses
  measurements within a pass. Outside an active layout transaction, feedback
  reset and dirty marking share an ancestor walk while preserving notifications.
  Opt-in `view[vpCacheIntrinsicSize] = true` caches resolved intrinsic measurements.
  See [cache contracts](docs/layout-measurement.md) and
  [layout measurements](docs/benchmarks/layout/README.md).

## Current limitations

- DirectViews streams setters and structural changes; a later failure can leave
  earlier mutations applied. P0's duplicate-key preflight is stronger in this
  respect. Neither is an application transaction system.
- Components currently have one actual root, and general child reconciliation is
  centered on StackView. Custom containers require explicit integration.
- Both list demos eagerly create rows. Collection observation is more selective,
  but snapshot copying/publication and structural action-adapter creation remain.
  We have not measured heap allocation counts or native input latency.
- Draft preservation and stale-result rejection require explicit domain policy.
  The demos' document revision check can reject an edit after an unrelated change;
  field/entity revisions and async cancellation are future work.
- Undo is bounded by group count, not bytes, and offers no transactional rollback
  if arbitrary application code fails during replay. Coarse snapshots can still
  be expensive. External updates currently use a conservative history policy.
- The async-save example is not production atomic persistence, recovery, or a
  multi-writer conflict protocol.
- The intrinsic cache is default-off and stores one entry/revision per view even
  when disabled. Standard mutation paths invalidate conservatively; custom or
  external inputs and protocol replacement need explicit invalidation. Proposal
  and bounds fallback remain freshly resolved. It is not a constraint-solver cache.
- The ancestor notification cascade remains quadratic with depth. Fusing two
  walks reduces repeated work without changing that asymptotic behavior.
- Suspension must not occur during composition. It pauses refresh, not editing
  or all effects; closing, hiding, and disposing remain distinct operations.

## What the measurements establish

These are historical measurements of different workloads, not one cumulative
speedup or a current cross-framework benchmark. Reports preserve harness details,
raw data, and exclusions.

| Workload | Result | Interpretation |
| --- | --- | --- |
| 1,000-row widgetless collection edit | 489.109 → 44.257 µs; getters 1,000 → 1 | Selective observation works. [Collection report](docs/benchmarks/collection-sigils/README.md). |
| Actual 100-row command publication | 9.675 → 11.322 µs | Snapshot publication regressed in this workload; do not hide it behind notification savings. |
| Actual 100-row edit plus detached preview | 166.827 → 158.983 ms | Layout/capture dominates; reversal plus preview stayed about 164 ms. Live presentation is excluded. |
| Early 100-row structural rebuild | P0 1.066 ms; P7 0.507 ms; cached P0 0.384 ms | Description removal alone does not establish a universal win. [Initial comparison](docs/benchmarks/direct-views/README.md). |
| 300 plain children reversed | 25,953 → 90.33 µs | One batch order commit; excludes subsequent constraint solve and draw. [Layout report](docs/benchmarks/layout/README.md). |
| Unchanged 300-child arrangement | 309.10 → 2.01 µs | Avoiding repeated order work, including batch input cost. |
| Warm 300-child intrinsic query + arrangement | 180.42 → 151.28 µs, cache off/on | Stable custom measurements reused; no constraint solve. |

The default-off cache comparison varied approximately −3% to +3% across the
sampled workloads; that is not a guarantee of zero overhead. The early full-layout
comparison still encountered a 500 ms solver limit at 300 rows. The later plain-view
ordering benchmark does not establish that this solver limit is fixed.

## Before merging this experimental PR

- [x] Require explicit DSL imports, preserve shared MVC/binding exports, and add
  compile-time checks of the import boundary.
- [x] Run final local validation and investigate earlier failures against an
  independent baseline; record exact revisions and limits in the
  [validation report](docs/declarative-validation.md). The earlier intermittent
  native-focus failure still requires careful interpretation despite fresh passes.
- [ ] Check the final pushed revision's GitHub workflows and resolve or explicitly
  account for failures. Earlier local focused passes do not make CI green.
- [x] Refresh the PR description and this status with implemented scope and
  explicit validation results; keep final-head CI status in the PR.

Fresh local runs passed 1,623 NimKit tests, 49 Tekton tests, 587 Kosmo tests,
and all 176 tests in the shared integration runner; the example bundle compiled.
These were separate commands and compiler configurations, recorded in the report.
Earlier Git subprocess, native activation, and shutdown-teardown failures remain
documented there, including the limits of attributing intermittent failures.
The CI run on `fa78d0e2` reproduced a Linux Kosmo repository-scope assertion that
also failed in two earlier `main` workflows. The report links those independent
reproductions; this establishes prior occurrence, not the underlying cause.
The later experiments below need not all be completed before an experimental merge.

## Next experiments, in order

### 1. Virtualized editable collections through MVC

- [ ] Host DirectView rows in existing CollectionView/TableView presentation with
  thousands of model items and a bounded viewport.
- [ ] Define offscreen active-editor behavior, focus restoration, removal, and reuse.
  Keep durable drafts in the model/controller, independent of row lifetime.
- [ ] Test reorder/removal while editing, scrolling away/back, and same-ID reuse.
  Measure live view count, getter calls, allocation, and edit/scroll latency.

This is the next major scalability test. Better collection signals alone do not
prove that a large editable application scales.

### 2. Profile and improve the full layout pipeline

- [ ] Measure constraint construction/installation/solve separately from intrinsic
  measurement, arrangement, capture, and drawing on representative editor trees.
- [ ] Investigate smaller constraint graphs or persistent solving only after those
  measurements identify the dominant phase.
- [ ] Investigate further ancestor propagation reduction while preserving observers,
  revisions, reentrancy, and active-transaction behavior.
- [ ] Exercise cache invalidation under content/font/style/visibility changes and
  custom measurement dependencies; expand caching only when evidence supports it.

### 3. Evaluate the complete Dragology interaction

- [ ] Measure all candidates per gesture, not just one detached capture.
- [ ] Define candidate capture validity, budget exhaustion, and failed-layout behavior.
  Never score invalid geometry as if it were a valid candidate.
- [ ] Keep previews effect-isolated and reject stale commits; test model changes
  during the gesture and report end-to-end latency.

### 4. Extend forms and document policy

- [ ] Apply/Cancel a multi-field draft as one accepted undo operation.
- [ ] Compare field-level conflicts with current document-wide revision checks and
  specify shared versus isolated editor drafts.
- [ ] Define dirty/save/close policy, async cancellation, and durable save recovery.
- [ ] Evaluate byte-bounded history and delta-based commands where snapshot cost
  warrants them; test continuity and conflict behavior independently of the view.

### 5. Validate native application behavior and tooling

- [ ] Test real IME composition, accessibility, and focus across scrolling, hiding,
  closure, and multiple windows on supported platforms.
- [ ] Measure input-to-presentation p50/p95, resizing, and scrolling, separately from
  headless command/preview timings.
- [ ] Record clean/incremental build time, binary size, and macro diagnostic quality.
- [ ] Evaluate upstream CollectionSigil adoption independently of DSL stabilization.

## Proposed alternative prototypes

These labels preserve the earlier comparison vocabulary. P1–P5 are design options,
not completed and benchmarked implementations.

| Prototype | Place in the current direction |
| --- | --- |
| P0 — ViewSpec interpreter | Implemented comparison baseline: inspectable structure and preflight, with widget/property adapter cost. Keep it while it helps evaluate P7. |
| P1 — Construction DSL plus explicit MVC updates | Simpler fallback for screens where ordinary retained widgets and explicit updates suffice. |
| P2 — Controller-scoped description bodies | Useful scoping idea, largely addressed by component/binding ownership; a separate description architecture is not currently needed. |
| P3 — Open typed description adapters | Possible extension for P0 if a real comparison needs custom widgets; not a prerequisite for P7. |
| P4 — Generated retained patch code | Potential reduction in runtime metadata, at the cost of macro/compiler complexity. Defer until profiling justifies it. |
| P5 — Larger observed composition runtime | Could add implicit local state/effect machinery, but would need stronger lifetime and debugging contracts. Not the chosen next step. |
| P6 — MVC collection hosts with declarative rows | Complementary to P7 and the next large-list experiment, rather than a replacement architecture. |
| P7 — Actual DirectViews plus MVC bindings | Implemented primary direction. Extend the MVC, binding, and container contracts before adding another general runtime abstraction. |
