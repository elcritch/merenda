# Merenda Work Plan

Updated **2026-10-14**. Focus on reliable long-running Kosmo sessions and bounded
memory use, then extend Tekton's authoring workflow.

Architecture and API decisions live in [design](docs/design.md) and
[layout](docs/layout.md). Test procedures, ownership contracts, and memory
measurements live in [reliability](docs/reliability.md); workspace behavior is
covered in [Kosmo workspace](docs/kosmo-workspace.md).

## 1. Lifecycle and platform reliability — active

The bounded multi-window/terminal regression passes, and dedicated rendering
works with ARC and ORC. The remaining work is to close platform lifecycle gaps
and verify extended use.

- [ ] Add an earlier close barrier in Siwin's Windows/X11 OS-close paths so GPU
  completion and renderer destruction finish before native window teardown.
  Cover OS-driven close, runtime shutdown, and repeated close in integration tests.
- [ ] Run extended sessions with multiple windows, terminals, Git activity, and
  Markdown. Track children, descriptors, owned workers, and memory after warmup;
  investigate growth and turn reproducible failures into bounded regressions.
- [ ] Reproduce the reported Kosmo 0.24.0 `Too many open files` crash with a mix
  of editor files, Git diffs, and Markdown open. No stack trace was available;
  the preceding layout warning does not establish the source of the exhausted
  descriptors. The current branch passes eight repeated mixed-document lifetimes
  with three Git refreshes per cycle and bounded descriptors/children in
  `tests/integrations/resourcelifetimes.nim`. Terminal-watch, workspace-watch,
  and Git-process cleanup code is unchanged from 0.24.0. Capture descriptor
  types/counts and the failing allocation in an extended session; this report
  remains unresolved.
- [ ] Verify dmon's Linux recursion fix before removing Kosmo's forced polling
  fallback. Exercise deep trees, multiple windows, missed events, and shutdown.

**Completion evidence:** supported close paths preserve window lifetime through
render cleanup, and repeated sessions return owned resources to their warmed
baseline. Native Windows/Linux behavior needs validation beyond macOS results.

## 2. Memory and responsiveness — next

Downloads are bounded, incremental render updates are compact, and streamed
Markdown color updates now change local runs. The next step is to measure retained
memory across the whole workspace and budget its caches.

- [ ] Profile representative workspaces using `tests/benchmark_memory.nim` and
  longer sessions. Separate live allocations and cache contents from allocator
  retention; measure decoded images, Markdown, Git diffs, and downloaded files.
- [ ] Set aggregate cache budgets and eviction policies from those measurements.
  Verify that closing documents releases their working sets and that reopening
  evicted content recovers correctly.
- [ ] Profile editing and scrolling with UTF-8 gap storage, worker layout, and
  retained rendering together. Use the fragment/snapshot benchmarks to identify
  remaining costs. Add general visible-range text layout only if profiling
  shows it is needed.
- [ ] Revisit suffix copying when streamed edits change Moe segment counts.
  Merenda's adapter currently shifts the remainder of Moe's flat segment array
  for each replacement; the isolated diagnostic took about 131/496 ms for
  32k/64k rows when replacing seven segments per row with one. A chunked or
  indexed segment representation would require reviewing Moe's consumers.
  **Do not modify Moe or open a Moe PR for this work.** Record required Moe
  changes here for a later decision. The URI batch optimization is implemented
  entirely in Merenda's adapter.

**Completion evidence:** cache growth is bounded under the chosen workload, with
before/after memory and latency measurements and coverage for eviction/recovery.

## 3. Tekton authoring — remaining work

View, guide, constraint, and flat resource editing now share undo, validation, and
save/reload workflows. Property edits reuse the preview graph; guide outlines,
constraint endpoint highlights, and unsatisfied-constraint diagnostics are available.
See [the review and measurements](docs/tekton-review.md).

- [ ] Add tree operations and editable inspectors for controllers and menus, and
  collection editors for localization strings, key bindings, and theme rules.
- [ ] Add visual reparenting, anchor handles, multi-selection, alignment, and snapping.
- [ ] Add inspection and change tracking for an attached running application's
  resource graph, including custom view and controller types.
- [ ] Add ambiguity diagnostics and runtime conflict attribution to generated layout
  inputs; current diagnostics report authored constraints that remain unsatisfied.
- [ ] Extend the palette to the remaining container/model-backed controls with
  explicit serialization contracts, and add application command/outlet wiring.

**Completion evidence:** users can author a multi-window interface, wire its
controllers and actions, and inspect the running application without losing history
or live object identities.

## 4. Cleanup

Five independent options from the 2026-10-14 Astra review, ordered by suggested
implementation priority. Estimates are net production LOC removed after adding
helpers and adapters; tests are excluded. Combined estimated reduction:
**385–515 LOC**.

- [ ] **Simplify SVG stroke parsing — 105–120 LOC; small effort.** In
  `src/merenda/nimkit/drawing/svgpathloader.nim`, replace `strokeSegments`' full
  SVG decoder with a reader for the absolute `M/L/C/Q/Z` commands already emitted
  by `normalizePathArcs`. Preserve transforms, quadratic/cubic segment types,
  zero-length line suppression, subpath closure, and incomplete-result fallback.
  Cover relative and reflected commands, arcs, and multiple closed subpaths.
- [ ] **Share button painting — 60–85 LOC; small–medium effort.** In
  `src/merenda/nimkit/controls/buttons.nim`, extract shared choice/push painting
  helpers for ButtonCell and Button. Keep caller-specific style resolution,
  property proc boundaries, widget hover interpolation, matrix-cell state,
  focus rings, icon/text placement, and active field-editor behavior.
- [ ] **Consolidate Kosmo command dispatch — 55–75 LOC; small–medium effort.**
  In `src/merenda/kosmo/application_editor.nim`, share action execution between
  `KosmoEditorCommandDispatch` and `KosmoEditorPaneCommandDispatch` through an
  explicit editor/pane context and thin protocol adapters. Preserve pane-document
  versus buffer saving, standalone-view fallbacks, focused-group routing, and
  selection synchronization. Keep Markdown read-only handling in its adapter.
- [ ] **Share shortcut JSON loading — 35–55 LOC; small effort.** Reuse the
  validation and atomic replacement workflow in
  `src/merenda/nimkit/responder/keybindingjson.nim` from
  `src/merenda/kosmo/shortcuts.nim`, with narrow sequence-parser and insertion
  hooks and shared prefix comparison. Preserve Kosmo's profile/platform parsing
  and duplicate rejection, NimKit's exact-sequence replacement, diagnostics,
  allowed-command checks, and null/empty-array disabling.
- [ ] **Share picker-button popup behavior — 130–180 LOC; medium effort.** In
  `src/merenda/nimkit/controls/datepickers.nim`, use a private GUI base for Date,
  Time, and DateTime button popup lifecycle, events, and common accessibility
  behavior. Keep typed values, property setters, selection callbacks, and
  accessibility value text concrete. Preserve stale-host guards, failed-open
  cleanup, responder restoration, presentation switching, and open-state
  invalidation. Retain Date's immediate selection and Time/DateTime's draft/Done
  semantics; cover stale dismissals and presentation changes while open.

**Completion evidence:** measure net LOC after each refactor and preserve behavior
through the relevant existing NimKit/Kosmo tests and focused regression coverage.
Keep public property hooks and ownership boundaries intact.

### Shared item-model and item-view architecture

The core NimKit review identified a coordinated migration with an estimated
**1,200–1,600 net production LOC reduction**, after shared implementations and
compatibility adapters. These are planning estimates, to be replaced by measured
results as each phase lands. Keep widget presentation typed, property proc hooks
intact, and mutable algorithm state in plain value objects owned by GUI objects.

- [ ] **Shared collection engine — 300–400 LOC estimated.** Move stable identity,
  source/visible index mapping, hidden/filter/sort arrangement, revision caching,
  and collection mutation below both views and controllers. Migrate `TableModel`
  and `ArrayController` to that engine while retaining their public entry points,
  strict/optional lookup behavior, and controller notifications. Start with
  TableModel's cached arrangement; preserve existing comparison policies, column
  metadata, and per-view formatting/parsing adapters.
- [ ] **Common item-provider contract — 150–200 LOC estimated.** Replace repeated
  count/value/identifier controller adapters with a narrow provider contract and
  typed per-view projections. Preserve lazy source access, widget-dependent
  source context, mutation observation, and explicit selection binding.
- [ ] **Local/provider reconciliation — 250–350 LOC estimated.** Share source
  switching, hidden-item projection, identity lookup, and reload reconciliation
  across menus, document tabs, matrices, and combo boxes. Retain live presentation
  object identities, native-menu synchronization, selection fallback policies,
  combo-box filtering, and specialized realization callbacks.
- [ ] **Shared item selection — 250–350 LOC estimated.** Migrate table/collection
  normalization, anchors, ranges, navigation, undo, and notification transactions
  to common value-state algorithms with narrow lookup/policy hooks. Preserve
  index-only table sources, identifier-based collection sources, invalid-anchor
  policies, focused-column behavior, and public event/delegate ordering.
- [ ] **View reuse and pointer/drag lifecycle — 220–340 LOC estimated.** Share
  visible-slot reconciliation, reuse-pool mechanics, tracking, and drag-session
  transitions. Keep painted table cells, hosted cells, collection layouts and
  supplementary views, reuse cleanup policies, payloads, hit testing, and delegate
  fallbacks explicit. Preserve bounded live-view counts and cached source calls.

**Delivery:** begin with a focused shared-engine PR, then migrate provider,
selection, and presentation ownership in reviewable increments. OutlineView
already inherits TableView, and CascadingView already uses tables for its columns;
do not count those as independent list engines or assume further tree savings.

**Completion evidence:** run the existing NimKit shared runner and affected
Kosmo/Tekton coverage, compile the example bundle, and validate the full suite.
Retain identity across sorting/filtering/reloads, typed edit writeback, fractional
scroll anchors, undo/notification order, provider laziness, and reuse lifetimes.
Add focused regressions for shared contracts and record actual LOC changes per PR.

## Validation

### NimKit test audit: unresolved validation

- [ ] Investigate native window ordering on the local macOS desktop. The
  streaming-memory follow-up's full run and isolated integration retry failed
  `nativeDocumentOrder(windows) == before` and `waitForNativeFront` in
  `tests/integrations/nativewindowactivation.nim`. The same activation tests
  also failed on Merenda commit `52a84ee9` with the same dependency checkouts.
  That commit's GitHub Actions run `36279008824` passed. A 2026-09-29 full run
  again failed `waitForNativeFront` at line 147 while the other three shared
  runners passed. Reproduce desktop activation and modal/context-menu ordering
  before changing window code or weakening the assertions; the local failure is
  not explained yet.
- [ ] Audit macOS standard-menu application lifetime. A freshly created
  `Application` remains alive under ARC even without windows: it owns its
  default menu, whose items target the application, and the native-menu
  dispatch closure also captures it. Decide the intended owner and teardown
  boundary before changing menu target retention; menu-created action targets
  may need to remain owned. Cover both native and in-window menu dispatch.
- [ ] Review eventual Chronos dispatcher teardown in Sigils. Main now retains
  the shared animation worker between clock users, avoiding the per-restart
  descriptor growth seen in PR #118's older Linux CI run 36078254071. Preserve
  that fix and the enabled `repeated Chronos clock starts reuse dispatcher
  descriptors` regression in `tests/nimkit/animations.nim`. Before replacing
  process-lifetime reuse with full teardown, review thread-local dispatcher
  ownership, pending timers/signals, channel and lock cleanup, and reclamation
  of the shared thread allocation. Validate repeated starts, shared users
  stopping in either order, active timers, and immediate shutdown on Linux and
  macOS under ARC/ORC. This is follow-up lifecycle work, not a claim that the
  old restart leak still reproduces on the rebased branch.
- [ ] Investigate intermittent Kosmo Git-diff completion during full-suite
  validation. On macOS with Nim 2.2.12, `summary and expanded files share wheel
  scrolling` failed at its initial `panel.waitForDiff()` both in the full run
  and a standalone retry, then passed nine focused runs and a complete Kosmo
  run after rebuilding without a behavior change. Keep the regression and its
  deadline intact.
  Reproduce with `atlas-run tests kosmo`, or filter the compiled shared runner
  with `Kosmo Git diff::summary and expanded files share wheel scrolling`.
  Capture pending repository, patch/highlight, Markdown, and background-layout
  work at the timeout to establish whether a completion is lost or relayout
  does not converge. No root cause or large rewrite has been established;
  review that evidence before changing worker/layout ownership.

For each code increment, run the relevant shared runner and `atlas-run tests`.
Compile examples with `atlas-run tests --compile-only examples/all_compile.nim`.
Ownership changes also need ARC/ORC sanitizer coverage from the reliability
guide. Record platform limitations and measured outcomes with the change;
keep this plan focused on unfinished work.
