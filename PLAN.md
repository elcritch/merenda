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

NimKit now provides a broad desktop-control foundation across views, responders,
windows, application/menu/modal infrastructure, themes, rendering, constraints,
containers, text, model-backed controls, documents, undo, pasteboards, dragging,
animations, accessibility, and resource construction. The source tree is grouped
under `accessibility`, `app`, `controls`, `containers`, `drawing`, `foundation`,
`responder`, `text`, and `view`; `merenda/nimkit` remains the stable public
umbrella import.

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
  UTF-8 gap-backed storage path. Public text positions remain rune-indexed.
- A backend-neutral resource system with canonical serialization, validation,
  document editing and undo, identity-preserving preview reconciliation,
  constraints and guides, Sigils-discovered properties, and the Tekton builder.
- A FigDraw rendering path that supports direct rendering and dedicated static
  Metal/Vulkan runtimes, with application-owned resource leases, moved render
  snapshots, renderer acknowledgements, and atlas recovery.

## Current Priorities

1. Turn Tekton's constrained resource editor into a broader authoring tool:
   typed non-view edits, richer property metadata, direct constraint authoring,
   reusable components, and package-relative assets.
2. Introduce a backend-neutral workspace/services boundary for file, URL,
   application, pasteboard, and promised-file handoff.
3. Add native accessibility and document/workspace adapters without leaking
   platform types into core NimKit modules.
4. Profile text storage and layout before committing to virtual or
   visible-range-only layout.

## Recently Completed — Consolidated July 2026

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

### Rendering and Managed Resources

- Kept application state, native windows, input, menus, IME, accessibility, and
  lifecycle on the platform thread while allowing static Metal/Vulkan rendering
  on a dedicated runtime. Render trees are moved and coalesced per window;
  unsupported backends retain direct rendering.
- Added managed FigDraw font/image leases, render-resource manifests,
  acknowledgement-based snapshot lifetime, rebuildable image sources,
  renderer-local atlas generations, pressure recovery, and multi-renderer cache
  event delivery.

## Verification

- Run the full suite with `atlas-run tests`. Focused NimKit tests live under
  `tests/nimkit/*.nim` and are aggregated by `tests/tnimkit.nim`.
- Compile the example bundle with
  `atlas-run tests --compile-only examples/all_compile.nim`; do not run the
  bundle as a test.
- Resource serialization/construction coverage lives in `tests/tresources.nim`.
  Tekton document, preview, editor, and user-workflow coverage is aggregated by
  `tests/ttekton.nim`.
- The full Atlas suite and example bundle compile currently pass on macOS.

## Near-Term Work

### Resource Builder

The current baseline is a standalone Tekton app built directly on
`ResourceBundle`, with no parallel declarative model. It retains invalid drafts
beside the last valid preview and preserves selection and compatible runtime
identities across valid revisions.

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

- Profile gap-backed mutation and the existing layout manager together. Add true
  virtual or visible-range layout only if layout remains the measured bottleneck.
- Add attachment layout, non-contiguous layout, and advanced bidi/grapheme
  navigation only after the core rune/glyph/line contracts remain stable under
  real editor workloads.
- Keep full Cocoa compatibility names as aliases over Nim-native APIs rather than
  allowing them to define the internal model.

### Native Integration

- Keep render and accessibility construction unit-testable without a live native
  window; keep native handles behind narrow diagnostic escape hatches.
- Add accessibility adapters for NSAccessibility, UI Automation, and AT-SPI-style
  APIs without importing platform modules into the core accessibility layer.
- Verify activation, hide/unhide, focus, key/main-window transitions, and modal
  blocking on macOS, X11, Wayland, and inline-windowless targets. Native events
  must route through the same `Application` and `Window` transitions used by
  tests.
- Add optional native-menu bridging after the pure Nim menu path remains stable
  across examples.
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
  chrome colors and metrics into `Theme` and `Appearance`; keep only
  geometry-derived ratios local to controls.
- Resolve duplicated `Control`/`ActionCell` ownership of target/action and
  control values. Keep control setters authoritative for invalidation and
  highlighting/tracking side effects, with cells owning measurement and drawing.
- Preserve `LayoutLength` values through anchor and constraint expressions
  instead of resolving `em` immediately against `defaultFontSize()`. Add
  view/theme/font-context resolution and a two-axis `LayoutSize` value.

### Rendering Constraints

- Keep the render boundary limited to moved `Renders`, logical size and target
  generations, renderer-local resource messages, acknowledgements, diagnostics,
  and shutdown. Ordinary application/window commands must not cross it.
- Create, resize, replace, and destroy native presentation targets on the UI
  thread. Renderer target replacement and shutdown require generation-aware
  release acknowledgement.
- Keep logical resource ownership separate from renderer-local atlas residency.
  Rebuild at frame boundaries from live manifests/preloads, and reject stale
  generation-stamped uploads.
- Keep `useNativeDynlib` unsupported for managed resources until its ABI gains
  equivalent font/image retain/release and renderer-targeted rebuild primitives.
  It must not silently fall back to unmanaged ownership.

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
- Should container-generated layout inputs become a distinct source before more
  collection-style controls are added?
- Should generated layout summaries expose richer item, attribute, priority,
  conflict, or cache-generation diagnostics?
- How much of the layout invalidation bus should remain public? It is useful for
  diagnostics, but most callers should not emit layout signals directly.
