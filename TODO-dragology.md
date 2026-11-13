# TODO: Declarative dragging for NimKit

Source review: 2026-11-06. Implementation update: 2026-11-13.

The discrete native port now lives in `nimkit/interaction/`, with a two-column
example and shared NimKit tests. See [the usage guide](docs/declarative-dragging.md)
for implemented behavior and explicit limitations. The checklist below remains
the broader acceptance roadmap: performance/memory measurements, continuous
composition, and large-collection work are still outstanding.

Implement an optional NimKit interaction layer inspired by declarative dragging
(D2). Applications describe reachable model states, and the engine derives drag
targets and previews from their layouts. Start with discrete list reordering and
floating previews, then expand to interpolation and continuous parameters.

References:

- [Declarative Dragging paper](https://andrewblinn.com/papers/D2.pdf), especially
  sections 3–5 and 9.
- [Dragology source reviewed at d89d133](https://github.com/declarative-dragging/dragology/tree/d89d1337f7c0b1aa9dc379f5267d1c8658b291c4).

## Feasibility and first milestone

NimKit has suitable input dispatch, layout, retained rendering, animation timing,
and undo infrastructure. The main missing pieces are isolated speculative views,
stable correspondence between candidate states, and preview presentation that
does not mutate live widget layout.

The first milestone comprises phases 1–3: a declarative todo-list example with
derived targets, floating previews, animated rearrangement, cancellation, and
one undoable commit. Use this milestone to validate the architecture before
adding numerical optimization or adapting large collections.

Initially support one mouse drag inside one window and an explicitly supported
subset of model-driven views. Cross-application dragging, multitouch, arbitrary
widget cloning, and general SVG/path morphing are later concerns. Preserve the
existing pasteboard and dragging APIs; add adapters where their semantics fit.

## Interaction model

Dragging `B` in `[A, B, C]` exposes three reachable states:

```text
[B, A, C]       [A, B, C]       [A, C, B]
```

Build and lay out each candidate, find the same semantic element in each, and
measure where its grabbed point would appear. Select a valid outcome based on
the pointer and display a preview. Commit the selected model on release.
Enumerate local successors for the dragged item, not all permutations.

Keep the preview separate from the drop model. Interpolating appearances does
not require interpolating application data or constructing invalid intermediate
model states. The upstream behavior interface makes this separation explicit:
[DragBehavior.tsx](https://github.com/declarative-dragging/dragology/blob/d89d1337f7c0b1aa9dc379f5267d1c8658b291c4/src/DragBehavior.tsx).

| Behavior | Purpose | Phase |
| --- | --- | --- |
| Fixed candidate | Represent a reachable model state | 2 |
| `closest` | Select by pointer-to-target gap, with optional stickiness | 2 |
| `withFloating` | Float the dragged element over the selected preview | 3 |
| Branch/drop transitions | Animate candidate changes and drag completion | 3 |
| `dropTarget` | Provide explicit geometry for deletion and other actions | 4 |
| `whenFar`, snap radius | Compose nearby snapping with a fallback behavior | 4 |
| `between` | Interpolate rendered alternatives according to pointer position | 4 |
| `vary` | Adjust numeric model parameters to approach the pointer | 5 |
| Creation/following, chaining | Continue a drag across model/element changes | Later |

## Existing integration points

| Existing code | Reuse | Required extension |
| --- | --- | --- |
| [windows.nim](src/merenda/nimkit/app/windows.nim), mouse dispatch and capture | Responder routing and logical coordinates | Controller lifecycle and cancellation hooks |
| [views.nim](src/merenda/nimkit/view/views.nim), `layoutSubtreeIfNeeded` | Candidate layout | Isolated construction and explicit environment |
| [rendering.nim](src/merenda/nimkit/drawing/rendering.nim), `buildRenderScene` | Drawing capture and scene construction | Independent preview ownership |
| [renderscenes.nim](src/merenda/nimkit/drawing/renderscenes.nim) | Drawing fragments separated from placement transforms | Semantic correspondence and preview composition |
| [animations.nim](src/merenda/nimkit/app/animations.nim) | Scheduler, easing, and springs | Presentation animation targets |
| [dragging.nim](src/merenda/nimkit/app/dragging.nim) | Payload/destination conventions where applicable | Optional model-driven adapter |
| [undomanagers.nim](src/merenda/nimkit/foundation/undomanagers.nim) | Undo grouping | One model transition per completed drag |
| [todo_stack_drag.nim](examples/todo_stack_drag.nim) | Baseline interaction and comparison | Separate declarative example |

`buildRenderScene` runs layout, updates caches, and acknowledges display state.
It is not a pure snapshot operation. Speculation must operate on independently
owned trees and scenes, not temporarily mutate and restore the live tree.

`RenderViewId` identifies a particular view instance. Reconstructing candidate
trees creates different instances, so it cannot identify corresponding model
elements across candidates.

The current [animation property helpers](src/merenda/nimkit/app/animationproperties.nim)
write live properties such as `view.frame`. Reuse animation timing while keeping
drag preview geometry independent of live layout and its invalidation paths.

## Proposed architecture and contracts

Keep the behavior engine independent of windows, native input, and concrete
widgets. A NimKit adapter supplies geometry, presentation, and commitment.
Names below are proposals, not existing APIs.

```text
snapshotModel()                  -> isolated model value + revision
buildPreview(model, environment)  -> detached view tree
describeDrag(model, elementId)    -> composable drag specification
commit(expectedRevision, model)  -> accepted/rejected
```

- [ ] Define plain value types for element IDs, options, geometry, environment,
  specifications, and evaluation results. Use a controller/host GUI object for
  session identity; keep ordinary session state in plain fields.
- [ ] Require semantic IDs unique within a drag host and stable across reorder
  and reparent operations. A scoped `DragElementId` may map to existing view
  identifiers, with duplicate detection.
- [ ] Define model snapshot ownership explicitly. An `object` containing mutable
  references is not automatically isolated. Applications must supply independent
  state or an immutable representation; speculation must not mutate shared data.
- [ ] Capture available size, appearance/style revision, scale, and relevant
  scroll geometry in the preview environment.
- [ ] Require preview builders to avoid application actions, subscriptions,
  timers, worker launches, and external effects. Start with an audited subset of
  views; being detached from a window does not alone guarantee isolation.
- [ ] Return the proposed drop model, preview description, achieved grab
  position, remaining gap, and explicit commit eligibility from evaluation.
- [ ] Preserve the local grab anchor through coordinate conversions. Do not
  substitute the center of the dragged element for the actual grabbed point.
- [ ] Keep commitment application-owned and validate the expected model revision.
  Reject stale results without overwriting newer edits. Initially cancel on a
  model revision change; add rebasing only with an explicit application contract.
- [ ] Provide an optional geometry-only evaluation path with the same placement
  semantics as full preview construction. Validate agreement before using it.
- [ ] Treat captured drawing and resources as independently owned preview data.
  Retain resources until render consumers release them, including cancellation
  and interrupted transitions. Keep live views on their owning application thread.

Suggested module boundaries, to confirm after the first prototype:

- `nimkit/interaction/dragtypes.nim`: public values and callback contracts.
- `nimkit/interaction/dragbehaviors.nim`: specification construction and evaluation.
- `nimkit/interaction/dragpreviews.nim`: candidate geometry and presentation.
- `nimkit/interaction/dragcontrollers.nim`: input, lifecycle, and commit orchestration.
- Add optimization and 2D interpolation modules only when those phases need them.

Use procs and generics for the engine, and narrow protocols/callbacks for GUI
integration. Avoid widget subclass checks in shared orchestration. Add no new
reactive property wrappers unless a property is actually observed or bound.

## Phase 1: Prove isolated layout and rendering

- [ ] Build a small model-driven list with stable item IDs and a shared builder
  for the visible state and detached candidate views.
- [ ] Lay out candidates under the same size and appearance conditions as the
  visible list; extract bounds and grab positions in a common host coordinate space.
- [ ] Capture independent previews without creating native windows.
- [ ] Compare candidate geometry with the geometry after committing that state.
- [ ] Verify that speculation leaves live model data, focus, subscriptions,
  hierarchy, layout flags, and display caches untouched.
- [ ] Verify cleanup of detached trees, cached drawing, and resource ownership.
- [ ] Measure candidate construction, layout, drawing capture, and memory
  separately, including variable-height rows and nested stacks.

Acceptance: candidate and committed geometry agree, and speculation is isolated.
This is the architectural gate. If existing widget construction has unavoidable
effects, narrow the supported builder surface before proceeding.

## Phase 2: Discrete drag engine

- [ ] Implement fixed candidates and `closest`, with deterministic ties and
  configurable stickiness to prevent oscillation near boundaries.
- [ ] Include a no-change candidate and define empty/all-invalid candidate
  behavior. An infinite gap or missing dragged element must not accidentally
  select an eligible drop.
- [ ] Diagnose missing/duplicate IDs and define how spatially coincident
  candidates are resolved or rejected.
- [ ] Add controller states for idle, armed, dragging, and settling, with a single
  cleanup path. Establish ownership before starting preview work.
- [ ] Integrate mouse down/drag/up through responder protocols and preserve
  ordinary clicks until the drag threshold is crossed.
- [ ] Cancel on Escape, host removal, window closure, lost interaction ownership,
  or a stale model revision. Release capture and discard previews consistently.
- [ ] Define release behavior outside valid targets and outside the window.
- [ ] Add `examples/declarative_drag_demo.nim` as a comparison with the existing
  todo example. Keep its model unchanged during preview.
- [ ] Commit once on release and register one undoable model transition. A
  cancelled or unchanged drag creates no undo entry.

Acceptance: reordering, cancellation, and undo work without application-authored
drop-coordinate calculations. Automated input tests include a noncentral grab
anchor and nested coordinate conversions.

## Phase 3: Floating previews and transitions

- [ ] Add a preview presentation layer keyed by semantic element IDs, separate
  from live frames and constraint inputs.
- [ ] Float the grabbed element above the candidate backdrop; support an optional
  destination ghost and avoid drawing the same element twice accidentally.
- [ ] Animate rearrangement of other elements when the selected candidate changes.
- [ ] Animate drop/cancel settlement using the existing scheduler and timing curves.
  Retarget interrupted transitions from their current presented geometry.
- [ ] Start with translation and opacity. Define explicit fallbacks for resized
  content, changed drawing, appearing/disappearing nodes, and unsupported morphs.
- [ ] Handle clipping, z-order, bounds origins, and cross-parent movement in host
  coordinates. Preview decorations must not steal input or accessibility focus.
- [ ] Preserve the captured live responder throughout the drag; rebuilding a
  candidate must not replace the active input target.
- [ ] Verify final presentation matches the committed live layout without a jump.

Acceptance: variable-height list reorder and movement between two stacks remain
visually continuous. Phases 1–3 constitute the first implementation milestone.

## Phase 4: Composition and interpolation

- [ ] Add explicit `dropTarget` geometry for deletion and other outcomes where
  the dragged element no longer exists. Allow target geometry to come from a
  different state than the drop model.
- [ ] Add `whenFar` and snap-radius modifiers with defined distance units and
  consistent behavior at boundaries.
- [ ] Implement `between` for two endpoints and collinear candidates first.
  Blend preview attributes while keeping the selected drop model discrete.
- [ ] Handle zero-length segments and coincident targets explicitly.
- [ ] Add 2D Delaunay/barycentric interpolation after the simpler cases work;
  consider natural-neighbor interpolation only if smoother motion warrants it.
- [ ] Add switch, two-list transfer, and delete-target examples using the same
  behavior engine and preview adapter.

Acceptance: operators compose without application-specific event handlers.
Interpolation endpoints reproduce their candidate appearances, and degenerate
geometry has a tested, documented outcome.

Upstream references:
[between.tsx](https://github.com/declarative-dragging/dragology/blob/d89d1337f7c0b1aa9dc379f5267d1c8658b291c4/src/ops/between.tsx),
[dropTarget.tsx](https://github.com/declarative-dragging/dragology/blob/d89d1337f7c0b1aa9dc379f5267d1c8658b291c4/src/ops/dropTarget.tsx).

## Phase 5: Continuous model parameters

- [ ] Introduce typed parameter accessors or a `stateFromParameters` callback,
  with constraints and scaling explicit in the contract.
- [ ] Evaluate a bounded nonlinear optimizer for `vary`. Reuse the previous
  solution as the starting point and bound work per interaction update.
- [ ] Use geometry-only evaluation for the optimization objective, then build
  the selected visual preview. Avoid full widget reconstruction for every probe.
- [ ] Validate returned parameters and constraints; retain the last feasible
  result or cancel when no valid result exists. Never silently commit an invalid
  optimizer result.
- [ ] Test infeasible constraints, non-finite results, missing geometry, poor
  parameter scaling, discontinuous layouts, and budget exhaustion.
- [ ] Add a slider, rotary control, and constrained timeline handle.
- [ ] Review upstream and transitive license notices before porting algorithms;
  preserve required attribution for any reused implementation.

Acceptance: continuous examples meet measured interaction budgets and remain
responsive under difficult inputs. NimKit's layout solver solves view geometry;
it does not directly invert an arbitrary model-to-view function.

Upstream uses COBYLA with warm starts and up to 200 objective evaluations per
minimization, making cheap geometry evaluation important:
[optimization.ts](https://github.com/declarative-dragging/dragology/blob/d89d1337f7c0b1aa9dc379f5267d1c8658b291c4/src/math/optimization.ts).

## Phase 6: Production integration

- [ ] Handle autoscroll and refresh target geometry as the viewport changes.
- [ ] Invalidate or rebuild candidates on size, scale, font, or appearance changes.
  Initially cancel when an environment change cannot be handled consistently.
- [ ] Add keyboard-accessible equivalents through the same model transitions,
  appropriate announcements, and reduced-motion behavior.
- [ ] Add diagnostics for candidate positions, selected behavior, invalid IDs,
  evaluation counts, time, and retained preview memory.
- [ ] Adapt tables and collections only after the generic contract is stable.
  Use specialized geometry providers for virtualized/offscreen items, and verify
  consistency with actual layout rather than eagerly constructing every view.
- [ ] Consider creation/following and chaining with explicit transaction, undo,
  and cancellation semantics across intermediate states.
- [ ] Add a focused `docs/` guide and update `CHANGES.md` when functionality lands.
  Keep README changes limited to material getting-started information.

## Performance plan

- [ ] Benchmark drag initialization separately from steady-state movement and
  settlement. Record candidate count, view count, layout count, elapsed time,
  retained memory, transient peak memory, and allocation traffic.
- [ ] Use increasing list sizes and candidate counts, variable-height rows,
  nested containers, and multiple continuous parameters as separate workloads.
- [ ] Cache candidate geometry for a stable model/environment revision; build
  expensive visual previews lazily and cap cached candidate resources.
- [ ] Establish numerical budgets from measurements, including a total drag
  preparation budget in addition to existing per-layout solve limits.
- [ ] Bound preparation across event-loop turns when necessary. Define the
  pending state and cancel stale preparation; do not accept a partially prepared
  target set as if it were complete.
- [ ] Coalesce pointer movement when evaluation is expensive, but evaluate the
  final release position before committing.

Naively laying out an entire list for every insertion position can make drag
initialization quadratic. The paper identifies this limitation in section 9.
Measure before promising performance for large collections; geometry-only
evaluation and specialized container adapters are likely necessary there.

## Validation and repository workflow

- [ ] Add deterministic component tests under `tests/nimkit/` and import them
  through `tests/tnimkit.nim`; do not create another top-level component runner.
- [ ] Cover model isolation, identity, anchors, coordinate conversion, ties,
  invalid candidates, cancellation, stale revisions, commit counts, undo/redo,
  preview resource cleanup, clipping, and interpolation endpoints.
- [ ] Keep native/process lifecycle tests under `tests/integrations/`, imported
  through `tests/tintegrations.nim`. Terminate and reap any child apps in teardown.
- [ ] Use observable readiness and monotonic deadlines for asynchronous tests;
  pump the owning event loop nonblockingly between short sleeps.
- [ ] Add the new example to the compile-only example bundle.
- [ ] Inspect live drag and settlement frames using [dev control](docs/dev-control.md)
  with `-d:merenda.devControl` and `MERENDA_BACKGROUND=1` where supported. Compare
  candidate, mid-drag, committed, and cancelled states.
- [ ] Format touched Nim code with `nph` and run the applicable checks below.

```sh
atlas-run tests --nimcache:deps/.nimcache/ --backend:ic nimkit
atlas-run tests --nimcache:deps/.nimcache/ --backend:ic --compile-only examples/all_compile.nim
nim test
nim integration
```

Use Atlas and the existing `deps/` and `nim.cfg` configuration for any new
dependency; do not use Nimble or introduce Atlas lockfiles. Keep CI's compiler
backend unchanged and retain the existing CI test command.
