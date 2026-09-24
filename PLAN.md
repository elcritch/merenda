# NimKit Plan

## Goal

Build and evolve Merenda's pure Nim UI layer at `src/merenda/nimkit` as the
project's primary UI toolkit.

The public API should stay Nim-native: plain value types for data, `ref object`
for identity-bearing UI objects, selector-backed hooks where dynamic dispatch is
useful, and backend/runtime details kept behind NimKit boundaries.

Completed architecture and design decisions live in [docs/design.md](docs/design.md).
Detailed layout, constraint, invalidation, and solver notes live in
[docs/layout.md](docs/layout.md). This file tracks current state, active work,
deferred architecture, and open decisions rather than serving as a change log.

## Current State

Reviewed on **2026-09-24** against source, test coverage, and repository history
through `c49aa298` (Merenda `0.21.3`), plus the working-tree reliability updates
described below. Test execution status is recorded separately
under Verification.

NimKit now provides a broad desktop-control foundation across views, responders,
windows, application/menu/modal infrastructure, themes, rendering, constraints,
containers, text, model-backed controls, documents, undo, pasteboards, dragging,
animations, accessibility, workspace services, file browsing, terminals,
Markdown, and resource construction. `merenda/nimkit` remains the stable public
umbrella import; Kosmo is the workspace/editor application and Tekton is the
resource-authoring application.

The main established layers are:

- A pure Nim application and responder runtime with window, menu, popup, modal,
  sheet, document-controller, undo-manager, notification, pasteboard, dragging,
  and animation services.
- A shared model vocabulary based on stable identifiers, `ObjectValue`,
  controller adapters, incremental updates, and model-mutation notifications.
  Tables, outlines, collections, cascading views, combo boxes, menus, document
  tabs, and matrices use this vocabulary instead of parallel storage models.
- A TextKit-shaped text stack with attributed storage, layout-manager protocols,
  selection and input-client behavior, accessibility geometry, and an optional
  UTF-8 gap-backed storage path. Plain text APIs use `Utf8Runes`, while public
  text positions remain rune-indexed. Worker layout snapshots and viewport-bound
  Markdown rendering are implemented; general visible-range text layout remains
  deferred.
- A backend-neutral resource system with canonical serialization, validation,
  document editing and undo, identity-preserving preview reconciliation,
  constraints and guides, Sigils-discovered properties, and the Tekton builder.
- Retained per-view FigDraw render scenes, independently invalidated drawing
  slots, and direct fragment traversal in static builds. With ARC, dedicated
  Metal/Vulkan runtimes receive independently owned, generation-stamped updates;
  `useNativeDynlib` retains the monolithic render path through FigDraw's facade.
  Both paths retain managed resource ownership and acknowledgement contracts.
- A backend-neutral workspace/services boundary, basic macOS workspace
  operations, native macOS menu bridging, and portable URL/asset handling.
- A Kosmo workspace pipeline with shared asynchronous file inventories,
  dmon notifications, bounded Git commands, lazy Git diff sections, Moe editing,
  Terminex terminals, and persisted appearance/settings choices.

## Current Priorities

1. Extend the bounded lifecycle regression with representative memory soaks
   described in [docs/reliability.md](docs/reliability.md), then set aggregate
   cache budgets for images, Markdown, Git diffs, and downloaded files.
2. Turn Tekton's constrained resource editor into a broader authoring tool:
   typed non-view edits, richer property metadata, direct constraint authoring,
   reusable components, and package-relative assets.
3. Extend the existing workspace/services boundary with native adapters for
   selected-text/file services, pasteboard services, promised-file handoff, and
   additional platforms.
4. Add native accessibility and document/workspace adapters without leaking
   platform types into core NimKit modules.
5. Profile the current UTF-8 storage, worker layout, and retained viewport
   rendering together before adding general visible-range-only text layout.

## Open Reliability Issues

Kosmo subprocess-resource exhaustion is **partially addressed**, with the
original extended-use failure still requiring closure evidence. The reported
macOS session had two windows, five terminals, 255 open file descriptors
(219 pipes), and 78 unreaped children against a descriptor limit of 256; opening
a new terminal silently failed.

- [x] Route workspace discovery, status, search discovery, and diff commands
  through `foundation/gitprocesses.nim`, which drains output and bounds command
  time/output, terminates and reaps children, and closes process handles.
- [x] Add Git output-draining, failure-recovery, and timeout/reaping coverage in
  `tests/nimkit/gitstatus.nim`. Terminex-backed terminal coverage also checks
  closing a live PTY and repeated close calls in `tests/integrations/terminals.nim`.
- [x] Add `tests/integrations/resourcelifetimes.nim`: six cycles after warmup,
  each with two windows, five live terminals, workspace/Git activity, and Markdown.
  The macOS regression returns children and descriptors to baseline; RSS and
  total process threads are diagnostic checkpoints.
  Extended interactive soak testing remains useful beyond this bounded workload.
- [x] Present terminal-start failures in a dismissible error dialog, preserve the
  active tab, and reject missing working directories before starting a process.
  Dialog close also aborts running modal sessions, preserves nested-modal focus,
  and tolerates repeated cleanup.
- [x] Stream URL assets to disk with an enforced byte limit and bounded transfer
  concurrency/request admission; test chunked overflow and cancellation.
- [x] Add process resource diagnostics and `tests/benchmark_memory.nim`.
- [x] Compact queued renderer updates so unchanged views carry placement order
  instead of full empty frame payloads. The 1,001-view benchmark's one-view
  update fell from 1,145,272 to 25,296 array bytes (97.8%).
- [x] Bind container removal handlers explicitly; repair selected-tab constraint
  resizing and cached table-header invalidation after direct scrolling.
- [x] Keep native rendering on the UI thread under ORC, avoiding a confirmed
  cross-thread cycle-root unregister crash. ARC retains dedicated rendering.
- [ ] Establish aggregate budgets for independent decoded-image, Markdown,
  Git-diff, and disk caches using measured representative workspace workloads.

## Implemented Baseline

### Resource System and Tekton

- Completed the first four builder milestones. `ResourceDocument` owns value-only
  drafts, validation, stable paths, selection, revisions, and undo;
  `ResourcePreview` reconciles valid revisions transactionally while preserving
  compatible view/controller identities; and `ResourceEditor` provides canonical
  CBOR persistence, hierarchy/canvas selection, diagnostics, property editing,
  direct movement and sizing, duplication, reordering, deletion, and undo.
- Expanded the backend-neutral schema and construction layer across views,
  controllers, windows/panels, menus, commands, images, localization, key
  bindings, themes, layout guides, and constraints. Resource identifiers remain
  the connection boundary, and the default palette exposes 13 registered kinds.
- Kept editor presentation metadata separate from runtime property discovery.
  Editable runtime properties continue to come from Sigils protocols and shared
  resource-value conversion rather than builder-specific setter tables.

### Text Storage, Layout, and Editing

- Established the attributed text model, `TextStorage` edit lifecycle,
  `TextContainer`, protocol-backed `TextLayoutManager`, FigDraw layout bridge,
  glyph/text/line query APIs, invalidation signals, temporary attributes, and
  multi-container records without exposing backend layout types.
- Migrated text fields, text views, editors, field editors, selection drawing,
  hit testing, movement, marked text, accessibility geometry, find/checking,
  completion, transfer, and paragraph editing onto the shared storage/layout
  contracts.
- Reworked `GapTextBuffer` around ARC-owned UTF-8 byte segments with private
  rune/byte coordinate helpers and sparse rune/line checkpoints. SynEdit now uses
  gap-backed storage and caches token spans, shifting and invalidating affected
  ranges while applying attributes through normal `TextStorage` APIs only where
  highlighting changed.
- Migrated plain text APIs and FigDraw glyph arrangements to `Utf8Runes`, with
  rune-indexed editing/selection and search paths that avoid repeated sparse-index
  rescans. Text layout can run on workers and reject obsolete reflow snapshots.
- Added a native Markdown view with worker parsing, incremental owner-thread
  application, Matter syntax highlighting, cached URL/local images, and bounded
  visible-line rendering. Offscreen code/table views are materialized near the
  viewport; this does not yet make the general layout manager virtual.

### Controls, Models, and Application Services

- Completed the current desktop control/container slice, including scroll,
  stack, form, grid, tab, split, box, table, outline, collection, cascading,
  combo, matrix, editor, monospace text, panel, and dialog foundations.
- Added shared object-value conversion and validation plus object, array, tree,
  and selection controllers. Model-backed widgets now preserve identity and
  selection across sorting, filtering, reloads, and incremental mutation.
- Added document/window controllers, responder-discovered undo, typed
  notifications, view-controller containment, pure Nim panels, animation
  scheduling, backend-neutral pasteboards/dragging, and broad accessibility
  semantics and notifications.
- Completed scaling passes for tables, combo boxes, cascading views, visible-row
  construction, row geometry, cached lookups, system font catalogs, and lazy
  option materialization. Deterministic operation-count tests cover the large
  collection paths.
- Added reusable popup hosts, filter-row controls, date/date-range pickers,
  token fields, docking, lazy file browsing, and Terminex-backed terminal views.
- Introduced immutable theme snapshots and `ThemeBuilder`, exact system font
  faces, and settings persistence hooks. Kosmo persists committed Merenda
  appearance, font, and UI-scale choices; generic window-frame autosave still
  uses an in-process store.
- Made layout a generation-tagged transaction with bounded callbacks, explicit
  follow-up invalidation, container-owned geometry, and feedback diagnostics.
  Solver budgets preserve existing frames on failure and retry after relevant
  input changes.

### Workspace Services and Kosmo

- Added `WorkspaceProviderProtocol` and typed requests/responses for file/URL
  operations, applications, services, promised files, handoff, and recent
  documents, plus portable system-location lookup. The static macOS provider
  implements open/reveal/launch/activate operations; the broader service and
  recent-document adapters remain pending.
- Added native macOS main, Windows, and Services menu integration with selectable
  native/in-window presentation. Other platforms retain the pure Nim menu path.
- Shared asynchronous workspace inventories between the file browser and quick
  open, with generation rejection, coalesced refreshes, ignore filtering, and
  preserved expansion/selection. Native watches cover roots, browsed folders,
  Git/worktree metadata, and open buffers outside project roots.
- Added event-driven Git refresh, two-minute reconciliation after accepted
  inventory snapshots, and a three-second fallback when native watch coverage
  is unavailable. Linux still explicitly uses the fallback.
- Added multi-root/multi-window workflows, independent split-pane editing state,
  CLI file/diff handoff, terminal search/links, and bounded, lazy Git diff review
  with staged/unstaged and branch comparisons. See
  [docs/kosmo-workspace.md](docs/kosmo-workspace.md) for workspace behavior.

### Rendering and Managed Resources

- Kept application state, native windows, input, menus, IME, accessibility, and
  lifecycle on the platform thread while allowing static Metal/Vulkan rendering
  on a dedicated runtime. Render trees are moved and coalesced per window;
  unsupported backends retain direct rendering.
- Added managed FigDraw font/image leases, render-resource manifests,
  acknowledgement-based snapshot lifetime, rebuildable image sources,
  renderer-local atlas generations, pressure recovery, and multi-renderer cache
  event delivery.
- Adopted FigDraw fragments with stable per-view placement/content identities,
  independent drawing slots, retained text-line/row contributions, and transform
  updates for scrolling. Static direct rendering traverses the fragment graph;
  `buildRenders` remains available for monolithic snapshots and diagnostics.
- Added cumulative scene updates from the acknowledged generation, renderer-local
  replicas, stale-update rejection, full-snapshot ordering barriers, and resource
  retirement after acknowledgement. Fragment and threading tests cover retained
  identities, ordering, coalescing, and resource lifetimes.
- Integrated the FigDraw native-window/dynlib facade while keeping fragment
  implementation types outside the native ABI. Idle native events and worker
  wakeups no longer force redraws; native surface damage still requests a frame.

## Verification

- Run the full suite with `atlas-run tests`. Focused NimKit tests live under
  `tests/nimkit/*.nim` and are aggregated by `tests/tnimkit.nim`.
- Compile the example bundle with
  `atlas-run tests --compile-only examples/all_compile.nim`; do not run the
  bundle as a test.
- Resource serialization/construction coverage now lives in
  `tests/nimkit/resources.nim`, imported by `tests/tnimkit.nim`.
  Tekton preview, editor, and user-workflow coverage is aggregated by
  `tests/ttekton.nim`; Kosmo coverage uses `tests/tkosmo.nim`, and native/process
  integration coverage uses `tests/tintegrations.nim`.
- Fragment/cache and renderer-transfer coverage lives in
  `tests/nimkit/renderfragments.nim` and `tests/nimkit/threading.nim`; those modules
  are excluded from `useNativeDynlib` builds. Workspace monitoring coverage lives
  in `tests/kosmo/workspacefiles.nim`.
- The checked-in CI workflow runs the four shared runners on macOS and Linux
  (X11 for native integration), and compiles examples on macOS, Linux, and
  Windows.
- Shared runners now import all component test modules. CI's
  `.github/scripts/check_test_imports.nims` rejects missing imports; static-only
  renderer tests remain gated for `useNativeDynlib`.
- Added ARC/ORC sanitizer configurations for the focused ownership subset.
- Local validation on **2026-09-24**, macOS/arm64 with Nim **2.2.12**:
  `atlas-run tests` passed all four runners, with **1,463 tests passing** and no
  reported failures or skips.
- `atlas-run tests --compile-only examples/all_compile.nim` passed.
- The ownership subset passed **90 tests each under ARC and ORC**, using Clang
  AddressSanitizer/UndefinedBehaviorSanitizer with `UBSAN_OPTIONS=halt_on_error=1`.
  Native Metal exception cleanup ran in both configurations, alongside modal,
  back-reference, text, fragment, and transfer coverage.
- `nim r tests/benchmark_memory.nim` passed and recorded the queued-snapshot
  measurements above. Shared-runner import coverage, workflow YAML/shell syntax,
  formatting, and whitespace checks passed.
- Linux/X11 sanitizer jobs are configured in CI; they were not run locally.

## Near-Term Work

### Workspace File Browser

The shared inventory and dmon-backed invalidation are implemented. A 100 ms
GUI-thread timer drains queued notifications; it does not itself scan the tree.
Native watch registrations are shallow and bounded, with periodic reconciliation
and polling fallback protecting incomplete or missed coverage.

- Verify the dmon Linux recursion fix before removing Kosmo's forced polling
  fallback; the source still carries that workaround despite the newer dependency
  requirement.
- Keep deep/large-workspace and multi-window coverage focused on bounded watch
  counts, lazy directory invalidation, coalesced work, shutdown, and recovery from
  missed events. The bounded process-resource regression above passes locally;
  extended interactive soak testing remains open.

### Resource Builder

The current baseline is a standalone Tekton app built directly on
`ResourceBundle`, with no parallel declarative model. It retains invalid drafts
beside the last valid preview and preserves selection and compatible runtime
identities across valid revisions.

Typed mutations currently cover view nodes and view properties. Non-view
resources have lookup/inspection support, but their typed mutation and authoring
work below is still pending; the first four builder milestones remain the
completed baseline.

- Add typed insert, remove, move, and replace operations for constraints, guides,
  controllers, windows, menus, commands, assets, localization catalogs, key
  bindings, and themes. Support grouped transactions for related edits.
- Add optional editor metadata for labels, categories, palette order, default
  frames, numeric ranges, asset pickers, multiline text, and other presentation
  hints. Enum choices should continue to come from runtime descriptors.
- Extend direct layout authoring with resize handles, guide overlays, snapping,
  anchor handles, constant/priority/activation editing, ownership visualization,
  and conflict or ambiguity diagnostics.
- Replace read-only resource detail surfaces with structured editors for
  target/action connections, controller ownership, menus, commands, images,
  localized strings, key bindings, and theme fragments. All commits should use
  typed document operations and retain invalid draft input when appropriate.
- Add reusable components/templates, copy/paste and drag/drop payloads,
  multi-selection transforms, and package-relative asset management. Extend
  duplicate-ID remapping from view subtrees to related constraints, connections,
  and non-view resources.
- Define schema migrations and optional nib/storyboard and GNUstep import/export
  adapters. Adapters must report lossy mappings and translate through
  `ResourceBundle` rather than expose platform resource types.

## Medium-Term Architecture

### Text Scaling and Layout

- Worker reflow, UTF-8 glyph arrangements, retained visual-line slots, and
  Markdown viewport rendering are implemented. Profile those paths with
  gap-backed mutation before introducing general virtual or visible-range layout.
- Extend general text attachment layout, non-contiguous layout, and advanced
  bidi/grapheme navigation only after the core rune/glyph/line contracts remain
  stable under real editor workloads. Markdown image attachments already have a
  rendering path.
- Keep full Cocoa compatibility names as aliases over Nim-native APIs rather than
  allowing them to define the internal model.

### Native Integration

- Keep render and accessibility construction unit-testable without a live native
  window; keep native handles behind narrow diagnostic escape hatches.
- Add accessibility adapters for NSAccessibility, UI Automation, and AT-SPI-style
  APIs without importing platform modules into the core accessibility layer.
- Native activation, lifecycle, repaint, and scale integration tests now exist.
  Extend verification of hide/unhide, focus, key/main-window transitions, and
  modal blocking across macOS, X11, Wayland, and inline-windowless targets.
  Native events must continue through the same `Application` and `Window`
  transitions used by tests; current CI does not establish full platform parity.
- Native macOS menu bridging is implemented. Keep the in-window menu path and
  native/dynlib menu behavior covered as popup presentation evolves.
- Extend native workspace capabilities beyond the basic static macOS provider.
  Other platforms and the dynlib workspace provider currently report no native
  operation features; selected-text/file services, promised files, and native
  recent-document handling still need adapters.
- Move window-frame autosave from the in-process helper store to a backend or
  user-defaults persistence adapter.
- Add native open/save panels, recent-document integration, represented-file URL
  and proxy metadata, and native print/page setup only after the pure Nim
  document/controller contracts remain stable.

### Framework Refinements

- Profile coordinate conversion in deep, scrolling view hierarchies. Add caching
  only if it is a measured cost, with explicit invalidation for frame, bounds,
  superview, and clipping changes.
- Move the remaining hard-coded popup, list, document-tab, and color-picker
  chrome colors and metrics into the existing immutable `Theme`/`ThemeBuilder`
  and `Appearance` system; keep only geometry-derived ratios local to controls.
- Resolve duplicated `Control`/`ActionCell` ownership of target/action and
  control values. Keep control setters authoritative for invalidation and
  highlighting/tracking side effects, with cells owning measurement and drawing.
- Preserve `LayoutLength` values through anchor and constraint expressions
  instead of resolving `em` immediately against `defaultFontSize()`. Add
  view/theme/font-context resolution and a two-axis `LayoutSize` value.

### Incremental Render Fragments

The adoption milestones are implemented for static builds: `DrawContext` records
per-view/slot contributions, `RenderScene` retains clean fragments, direct
rendering traverses them, and dedicated renderers apply independently owned
scene updates. FigDraw cursors carry owner/generation checks and its layer
accessors return detached copies. NimKit tests cover ordering, retained drawing,
resource manifests, acknowledgement, and cumulative update coalescing.

- Continue profiling retained scenes with `tests/benchmark_render_fragments.nim`
  and `tests/benchmark_render_snapshots.nim`, extending operation-count and
  output-equivalence coverage when a new control or invalidation path needs it.
- Preserve layer, clipping, popup, focus/selection overlay, and resource-lifetime
  invariants when changing slot placement or scene reconciliation.
- Keep `useNativeDynlib` on the managed monolithic path unless a deliberate ABI
  extension provides equivalent fragment transfer and lifetime guarantees.
  Mutable fragment graphs must remain local to their owning thread.

### Rendering Constraints

- Keep the render boundary limited to moved `Renders` or ownership-safe fragment
  snapshots/replacements, logical size and target generations, renderer-local
  resource messages, acknowledgements, diagnostics, and shutdown. Ordinary
  application/window commands must not cross it.
- Create, resize, replace, and destroy native presentation targets on the UI
  thread. Renderer target replacement and shutdown require generation-aware
  release acknowledgement.
- Keep logical resource ownership separate from renderer-local atlas residency.
  Rebuild at frame boundaries from live manifests/preloads, and reject stale
  generation-stamped uploads.
- Keep `useNativeDynlib` managed resources on the explicit ABI operations for
  renderer-targeted replay, rebuild, and manifest retention. It must not
  silently fall back to unmanaged ownership.

## Long-Term Architecture

### Printing and Page Layout

- Define backend-neutral page setup, printable-range, pagination-container,
  margin, paper-size, scale, header/footer, and print-job records.
- Let text, table/collection, image, and custom drawing produce page-fragment
  geometry without a live window.
- Add document-controller hooks for page setup, print preview, print validation,
  and edited-state-safe print flows.
- Defer native print panels and spooler integration until pure Nim pagination and
  render snapshots are testable.

## Open Questions

- How far should public export narrowing go for `View.x*` storage? Fully hiding
  it requires a deeper internal accessor or module-organization refactor.
- Should accessibility storage remain directly on `View`, or move behind a
  per-view semantic record if more role-specific state accumulates?
- Which containers should emit solver relationships through the existing
  `lisContainer` source, which is currently reserved, and which should continue
  to own their geometry directly?
- Generated layout summaries expose per-source counts, and transaction/solver
  diagnostics expose invalidation and budget failures. Should summaries also
  expose item, attribute, priority, conflict, or cache-generation details?
- How much of the layout invalidation bus should remain public? It is useful for
  diagnostics, but most callers should not emit layout signals directly.
