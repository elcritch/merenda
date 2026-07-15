# NimKit Plan

## Goal

Build and evolve Merenda's pure Nim UI layer at `src/merenda/nimkit` as the
project's primary UI toolkit.

The public API should stay Nim-native: plain value types for data, ref objects
for identity-bearing UI objects, selector-backed hooks where dynamic dispatch is
useful, and backend/runtime details kept behind NimKit boundaries.

Completed architecture and design decisions live in [docs/design.md](docs/design.md).
Detailed layout, constraint, invalidation, and solver notes live in
[docs/layout.md](docs/layout.md).

## Current Focus

NimKit has the core desktop-control slice in place: views, responders, windows,
application/menu/modal infrastructure, theme/rendering, intrinsic sizing,
constraints, stack/form/grid/tab/split containers, buttons, switch/radio
buttons, sliders, steppers, progress indicators, text fields, combo boxes,
box/group containers, scroll views, popup lists, table views, outline views,
cascading column views, collection views, basic text editing lifecycle, action
dispatch, reusable pure Nim panel/dialog views, matrix cell grids, a themed
high-throughput monospace text view/editor with raw event policy controls,
document-controller infrastructure, Nim-native object/array/tree/selection
model controllers and widget binding adapters, view-controller content ownership
and containment, a responder-discovered undo-manager service,
AppKit-style in-process pasteboard/dragging foundations, a shared object-value
formatting, parsing, writeback, and validation layer for model-backed controls,
a typed notification center for broad app/window/document/defaults/undo/
selection/model broadcasts, and a pure Nim accessibility metadata,
notification, traversal, validation, and text semantics core.

The source tree is now organized around domain modules under
`accessibility`, `app`, `controls`, `containers`, `drawing`, `foundation`,
`responder`, `text`, and `view`. The stable public entry point remains
`merenda/nimkit`; internal code and tests should import the domain modules
directly when they need a narrower surface.

The first animation core is now in place through interpolation/timing,
deterministic scheduler/threading, selector-backed property animation surfaces,
Cocoa-style transaction sugar, application run-loop draining, and focused
examples. Keep future animation extension points on methods, protocols, and
selector dispatch rather than public callback hooks. Widget mutation should stay
routed through existing NimKit setters so layout, display invalidation,
responder state, and accessibility notifications remain the single source of
truth.

The pure Nim panel/dialog contracts are now reusable enough to support modal
and sheet workflows before native bridges land: alert button response mapping,
accessory views, open/save validation, live panel button validation, and
document-controller open/save integration are covered in tests and examples.

Model-backed widget work should now reuse the contracts proven by `TableView`,
`OutlineView`, `CollectionView`, `CascadingView`, `ComboBox`, menus,
`DocumentTabs`, and `Matrix`:
stable identifiers, `ObjectValue` conversion, controller adapters, incremental
update records, and model-mutation notifications. The next controls should
build on that vocabulary instead of adding parallel storage models.

## Recently Completed

- Reorganized NimKit under domain subdirectories while keeping
  `merenda/nimkit` as the stable umbrella import; completed the drawing/chrome
  split, image resources, view geometry/parity APIs, render alpha/shadow
  support, and tracking affordance storage.
- Hardened the responder, command, action, selector, application, window, menu,
  popup, modal, and sheet layers into a coherent pure Nim AppKit-style runtime:
  key/mouse/scroll/help events have explicit handled/unhandled contracts,
  responder-chain command dispatch is selector-backed, menus and popup menus are
  interactive, and application/window state now covers key/main transitions,
  modal blocking, activation, hide/unhide, autosave, and window-menu updates.
- Built the document/controller stack above the pure Nim window/application
  model: `WindowController`, `Document`, and `DocumentController` now manage
  window ownership, file metadata, edited state, recent documents, open/reopen,
  save/revert/close flows, responder-chain integration, and backend-neutral
  document defaults.
- Added the cross-cutting `UndoManager` architecture as a NimKit service rather
  than text-only history: grouped/nested undo transactions, redo replay, action
  names, discard/clear APIs, disabled registration scopes, clean-state tracking,
  and debug summaries are in place; documents and windows provide undo managers
  through the responder chain via `UndoManagerProvider`; documents track edited
  state from undo clean-state signals; and text storage, table selection/columns,
  combo choices, matrix selection, and document tabs register inverse operations
  through shared value, selection, and collection helpers.
- Expanded core containers and shared primitives: `ScrollView`/`ClipView`,
  `Box`, `SplitView`, form/grid/stack support, table row primitives, popup
  lists, and the list-to-row vocabulary cleanup are in place with themed
  rendering, intrinsic sizing, layout integration, and example coverage.
- Matured `TableView`, `OutlineView`, and `CascadingView` around protocols
  instead of ad hoc callbacks: headers, sorting, resizing, reordering, hosted
  cells, field-editor-backed editing, state persistence, drag/drop targets,
  disclosure affordances, keyboard behavior, and accessibility semantics are
  covered by focused tests and demos.
- Added `TableView` model backing: typed row/cell value records, explicit
  row-identifier lookups, data-source object-value writeback, a seq-backed
  `TableModel` adapter, ID-first selection persistence with alias/resolver
  migration, batched row-update signals, and row-identifier drag payloads.
- Completed the large-table and data-model scaling pass: `TableModel` now caches
  arranged source indexes and source/arranged identifier maps by revision;
  fixed-height row geometry uses arithmetic, variable-height geometry uses
  cached prefix offsets and binary search, and table intrinsic sizing defaults
  to explicit column widths with opt-in content measurement and data-source
  width hints. Popup and table row construction remains visible-range bounded.
- Coalesced cross-cutting layout work: appearance changes mark descendant state
  locally and emit one root invalidation, automatic window content minimums are
  deferred and flushed once, and repeated intrinsic-size invalidations no longer
  force a solver pass for every intermediate mutation.
- Added Control-owned, scheduler-backed pressed feedback for keyboard and
  programmatic activation. Buttons and switch buttons use the default cell
  highlight hook, while steppers override it for segment-specific feedback;
  mouse tracking takes over cleanly from an in-flight pulse. Moved the popup-menu
  double-arrow mark into its control-specific drawing implementation instead of
  exposing it through the general drawing API.
- Added scalable combo-box collection paths: bulk option replacement performs
  one invalidation without per-item undo registration; visible indexes,
  identifiers, normalized search text, and data-source counts are cached; and
  selected-item, widest-item, and preferred-width sizing policies avoid
  unrequested whole-model measurement.
- Added scalable cascading-view collection paths: bulk item replacement rebuilds
  local caches with one intrinsic invalidation; visible child indexes, items,
  identifier lookups, normalized type-selection text, and per-parent model counts
  are cached until reload or an incremental tree update. The settings demo also
  has an opt-in noninteractive startup benchmark for the font hierarchy.
- Added a process-cached, family-oriented system font catalog and lazy combo-box
  data source. Font choices retain stable family and face identifiers, language
  variants, styles, representative paths, searchable face names, cached width
  hints, and on-demand option materialization. `merenda_settings_demo.nim`
  consumes the cached catalog through a language-family-face `CascadingView`
  data source instead of eagerly loading every font file into a combo box.
- Added deterministic operation-count coverage with thousands of combo and table
  items for invalidation, lookup, measurement, arrangement, row geometry, and
  lazy font-option behavior. Wall-clock benchmarks remain diagnostic and are not
  timing-sensitive CI assertions.
- Added backend-neutral pasteboard and dragging foundations with typed item
  storage, named/unique pasteboards, lazy providers, strings/text/data/property
  lists/URLs/files/colors/fonts/images, drag sessions, promised-file staging,
  backend bridges for host-supported payloads, autoscroll/update dispatch, and
  table/outline/list integration.
- Added the pure Nim accessibility core and expanded built-in semantics across
  views, buttons, checkboxes, text fields, labels, menus, popup controls,
  combo boxes, tabs, scroll areas, table rows/cells, outline rows/disclosure
  controls, progress indicators, sliders, switches, and steppers.
- Routed accessibility notifications from committed semantic state transitions:
  focus, selection, value, and expand/collapse changes now post through the
  existing Sigils accessibility signal after state changes, while enabled-state
  mutations update attributes without noisy notifications and drawing/layout
  remain notification-free.
- Added backend-neutral semantic accessibility traversal helpers: ordered
  descendants/elements, stable element-at-point hit-testing, role/action support
  checks, and validation result helpers for tests and future native bridges.
- Added richer text accessibility hooks for text fields, text views, and
  monospace text views: selected ranges, insertion points, character counts,
  editable/selectable traits, selection-change notifications, character and
  range bounds, line ranges/bounds, and point-to-character lookup.
- Defined the first public `TextLayoutManager` value model: rune-indexed
  `TextRange` remains canonical, while typed glyph indexes/ranges, visual line
  indexes, line fragments, and layout snapshots now expose container-local
  metrics, hard-break/wrap metadata, glyph counts, used rects, and content size
  for tests and diagnostics.
- Added the first `TextLayoutManager` query layer: layout cache lifecycle,
  counts/bounds/content metrics, text-to-glyph mapping, point hit-testing,
  visual line fragment lookup/ranges/iteration, caret positions, selection
  rects, text bounds, character rects, and glyph bounds now share one
  container-local contract.
- Introduced the protocol-backed `TextLayoutManager` layer: manager lifecycle
  and query methods, the FigDraw-backed `TextLayoutBackendProtocol`,
  `TextLayoutClientProtocol` owner hooks, `TextStorageEditingEvents`
  will/did-edit signals, and layout invalidation/completion/geometry signals
  now provide AppKit-like semantic APIs with Sigils/Qt-style notification
  delivery.
- Reworked the FigDraw bridge behind the `TextLayoutManager` protocols:
  `GlyphArrangement` glyph/source ranges, visual lines, caret positions,
  merged selection bands, glyph metrics, and content sizing now map into
  NimKit records through narrow value-query helpers without leaking backend
  records into text view, field, or accessibility APIs.
- Migrated text consumers onto the `TextLayoutManager` contract: TextView and
  TextField selection drawing, caret/line movement, mouse hit-testing,
  field-editor geometry, and accessibility text geometry now query committed
  layout-manager state, while MonoText exposes matching fixed-grid geometry
  helper names for shared accessibility expectations.
- Locked down the first `TextLayoutManager` contract tests: backend-free
  snapshots now cover empty text, hard breaks, wrapping, trailing lines, and
  text/attribute invalidation requests, while deterministic FigDraw-backed
  tests cover wrapped selections, caret affinity, point hit-testing,
  glyph/text range round trips, field-editor text rect offsets, and
  accessibility line geometry.
- Drew the first text-layout milestone boundary: attachment layout,
  non-contiguous layout, full Cocoa `NSLayoutManager` compatibility aliases,
  and advanced bidi/grapheme navigation are explicitly deferred until the core
  layout contract is proven.
- Added the first Cocoa/TextKit-compatible text model layer without native
  bridge types: richer `TextAttributes` now cover paragraph styles, tab stops,
  line breaking, writing direction, baseline/kerning/ligature/expansion
  fields, backgrounds, shadows, links, decorations, and attachment metadata;
  `TextStorage` exposes mutable attributed-string aliases and rune-indexed
  edit/query helpers; and text transfer/pasteboard contracts cover plain text,
  attributed text, RTF, RTFD-style package payloads, HTML fragments, URLs, and
  file promises.
- Brought `TextStorage` closer to `NSTextStorage` while keeping NimKit's
  Qt-style event path: `beginEditing`/`endEditing`, edited masks/ranges,
  change-in-length tracking, coalesced `processEditing`, value/attribute
  change signals, delegate-backed attribute fixing and font fallback hooks,
  paragraph-range expansion, lazy materialization, and multiple layout-manager
  observers now share one deterministic storage signal contract.
  `TextStorageEditDispatchProtocol` is the explicit overridable delivery seam
  for external editor bridges, coalescing, suppression, mirroring, and
  instrumentation before `TextStorageEditingEvents` observers receive signals;
  layout notifications now emit directly through Sigils signals.
- Expanded `TextContainer` toward `NSTextContainer` parity: containers now carry
  origin, size, line fragment padding, width/height tracking flags, maximum line
  counts, line break modes, and exclusion rects; `TextLayoutManager` supports
  multiple containers with container indexes in line fragments, caret positions,
  snapshots, and semantic hit-test results, plus container replacement and
  invalidation signals for paged, column, and flowed text models.
- Expanded `TextLayoutManager` toward `NSLayoutManager`/TextKit 2 parity while
  keeping NimKit names primary: glyph generation now exposes `TextGlyph`
  records, glyph properties, character/glyph mapping helpers, bounding rect
  queries, line-fragment rect/used-rect metrics, extra line fragments,
  temporary rendering attributes, typed character/glyph/layout/display/container
  invalidation payloads, delegate hooks for glyph generation, spacing,
  hyphenation, completion, and temporary attributes, explicit background and
  non-contiguous layout switches, partial-layout entry points, and Cocoa-shaped
  aliases layered over the Nim-native API.
- Brought `TextView` closer to `NSTextView` behavior while keeping the surface
  pure Nim: selection affinity/granularity, multiple and rectangular selection
  hooks, selected/marked text overlays, insertion-point color/visibility/blink
  policy, find indicators, checking results, optional data detection, spelling
  and grammar underline application, delegate protocols for edit lifecycle,
  text changes, selection, clicked links/attachments, completions, and command
  validation, undo grouping, smart insert/delete, quote/dash substitution,
  find/replace helpers, completion panels, and paragraph/tab-stop editing now
  share the existing storage/layout contracts.
- Hardened text input, command, and field-editor parity: TextView/TextField/
  TextEditor now expose NSTextInputClient-style marked-text, selected-range,
  attributed-substring, marked-attribute, first-rect, and point-to-index query
  contracts; keybindings and IME command dispatch route through selector-backed
  responder command validation with Sigils command observers; and the shared
  field editor keeps text-field and hosted-cell geometry/selection stable while
  edits sync back to clients.
- Filled out the current desktop control set: buttons, checkboxes, radio
  buttons, switches, text fields/editors, combo boxes, popup/menu buttons,
  progress indicators, sliders, steppers, dialog button boxes, group boxes, and
  image views now route state through NimKit setters, target/action dispatch,
  rendering invalidation, layout metrics, and accessibility notifications.
- Added the shared object-value layer for model-backed controls:
  `ObjectValue` now covers strings, numbers, booleans, temporal values, colors,
  images, attributed text, links, dynamic agents, nil/empty values, and
  validation failures; formatter/parser protocols provide role-aware display
  and edited-text parse/writeback; text fields, table cells, combo boxes, menus,
  sliders, steppers, and form rows now share typed value conversion and
  structured validation state instead of each inventing its own string bridge.
- Added the first controller and bindings layer for model-backed widgets:
  `ObjectController`, `ArrayController`, `TreeController`, and
  `SelectionController` now expose Nim-native identity, value, sort/filter, and
  mutation APIs over `ModelItem`/`ModelColumn`/`ModelTreeItem` records. Shared
  adapter protocols now feed table, outline, cascading, combo, menu,
  document-tab, and matrix controls from the same object-value model vocabulary,
  including typed table editing/writeback and structured parse validation.
- Added model-backed `CollectionView` for reusable repeated-content views:
  layout strategies stay separate from item storage, while data-source and
  delegate protocols cover stable item identifiers, object values, identity
  selection, reusable item/supplementary views, item state/accessibility,
  incremental insert/remove/move/reload updates, and model-aware drag/drop
  targets. `ArrayController` can now bind collection views using the same
  sorted/filtered `ModelItem` vocabulary as tables, combo boxes, menus, tabs,
  and matrices.
- Implemented `CascadingView` model backing around stable `CascadingItem`
  identifiers, parent identifiers, display/object values, leaf/hidden/image
  metadata, represented objects, identity-backed selected paths, data-source
  and delegate hooks, incremental tree insert/remove/move/reload updates,
  batched update signals, model-mutation notifications, table-column row
  adapters, and `TreeController` binding coverage.
- Implemented `ComboBox` choice model backing around plain `ComboBoxOption`
  records, option identifiers, display text, object values, enabled/hidden/
  separator/image/tooltip/search metadata, identity-backed selected and
  highlighted options, old string-item compatibility APIs, a seq-backed
  `ComboBoxOptionList` data-source adapter with filtering, type-ahead lookup,
  popup separator/disabled-row semantics, and `ArrayController` option-record
  binding with selection writeback.
- Implemented menu item model backing around plain `MenuItemModel` records,
  item identifiers, subtitle/key-equivalent metadata, object values, enabled/
  hidden/separator/image/state/action/target/represented-object fields,
  submenu child records, model-to-`MenuItem` bridge generation, data-source
  reload hooks, validation writeback into model records before popup opening,
  identifier-based menu activation signals, and `ArrayController` menu/popup
  binding with selection writeback.
- Implemented `DocumentTabs` model backing around plain `DocumentTabModel`
  records, stable document/tab identifiers, object values, hidden/closeable/
  modified/enabled/style/accent/tooltip metadata, represented document/object
  hooks, data-source reloads, identifier-backed selection and order state,
  model-aware add/remove/move operations, `ArrayController` tab binding with
  selection writeback, and `DocumentController` tab binding that routes close
  requests through document ownership.
- Implemented `Matrix` item model backing around plain `MatrixItemModel`
  records, stable item identifiers, object values, enabled/hidden/state/tag/
  tooltip/image/action metadata, data-source reloads, fixed column projection,
  identifier-backed selection, model-aware insert/remove/reorder operations,
  generated `ButtonCell` action dispatch, and `ArrayController` matrix binding
  with selection writeback.
- Implemented `OutlineView` model backing around expanded `OutlineItem`
  records, stable item identifiers, parent/child lookup, object and column
  values, enabled/hidden/leaf/image/tooltip/represented-object metadata,
  identifier-backed expansion and selection state, local insert/remove/move
  mutation helpers, table object-value read/write integration, and
  `TreeController` binding with model-change reloads and selection writeback.
- Added the typed notification center for cross-cutting observation:
  `NotificationKind`, `Notification`, observer tokens, typed payload records,
  and the Sigils-backed `notificationPosted` signal now cover application,
  window, document, document-controller, defaults, appearance, undo, selection,
  and model-mutation broadcasts while keeping direct owner/delegate wiring on
  local Sigils signals.
- Added the first `ViewController` architecture: controllers now lazily build
  views through selector-backed loading protocols, emit Sigils lifecycle
  signals, carry represented objects and optional undo managers, participate in
  responder validation/target-action routing, support child-controller
  containment, and can be owned/swapped by `WindowController` while documents
  seed document-backed content controllers with represented objects.
- Hardened reusable pure Nim panel/dialog contracts: `Alert`, `OpenPanel`, and
  `SavePanel` now build modal and sheet content with buttons, accessory views,
  response mapping, file-type validation, selected URL helpers, modal
  preparation hooks, document-controller integration, and demo coverage.
- Added the first animation layer: value/property animations, groups, timing
  curves, scheduler/clock plumbing, transaction sugar, selector-backed property
  dispatch, setter-routed mutation, and demos for progress indicators and
  animation workflows.
- Added legacy `NSMatrix`-style button cell grids with radio/check/button
  modes, cell reuse, keyboard movement, selection behavior, target/action
  dispatch, intrinsic sizing, rendering, accessibility semantics, and
  `examples/matrix_demo.nim` coverage.
- Added the first `MonoTextView`/`MonoTextEditor` pass: themed chrome-backed
  monospace rendering, visible-row culling, grid/cell APIs, editable cursor
  behavior, raw key/mouse/scroll forwarding and capture policies, host-style
  text input dispatch, and an interactive `examples/monotext_demo.nim`.
- Added the first gap-buffer-backed text storage path while preserving NimKit
  editor interactions: `GapTextBuffer` now provides rune-indexed replace,
  substring, line-count, and line-range operations; `TextGapStorage` subclasses
  `TextStorage` for that backing through `newTextGapStorage` and public storage
  primitive methods; edit dispatch, attributes, undo snapshots, layout
  invalidation, accessibility observers, and `TextEditor` storage assignment
  keep using the existing NimKit contracts.
- Fixed pasteboard provider cache invalidation so provider change counts clear
  materialized local items/types before reads, provider swaps discard stale
  local cache and owner state, and the native clipboard provider reports host
  clipboard changes through platform change counts or a synthetic fingerprint.
- Kept the application, native windows, input, menus, and platform services on
  the main thread while adding an optional dedicated FigDraw renderer runtime.
  Supported Metal and Vulkan backends receive moved, coalesced render trees;
  unsupported backends retain direct main-thread rendering. Render-resource
  manifests remain on the application thread until their render IDs are
  acknowledged, and the build uses regular ARC with explicit ownership
  transfers at thread boundaries.
- Added managed FigDraw font and image resources for the static renderer:
  cached render roots and text layouts retain deduplicated FigDraw leases,
  image resources preserve rebuildable sources with bounded preload/pin policy,
  threaded snapshots carry value-only sources, and each host renderer recovers
  its working set across atlas generations and pressure rebuilds. FigDraw now
  broadcasts retain/release and cache events to every renderer, reports
  renderer-local generations and rebuild metrics, and supports measurement-only
  text layout without transient glyph uploads.

## Current Verification

- `atlas-run tests` passes locally on macOS with the current domain module
  layout; the latest full run passed `2/2`.
- Focused NimKit coverage lives under `tests/nimkit/*.nim` and is aggregated
  by `tests/tnimkit.nim`; current modules cover controls, matrix,
  monospace text views, tables, outlines, cascading views, collection views,
  documents, animations, rendering, accessibility, text storage/layout/views,
  pasteboards/dragging, document tabs, undo managers, object values, model
  controllers, notifications, responders, view controllers, windows/controllers,
  constraints, themes, the renderer/application threading boundary, and managed
  font/image resource retention and atlas recovery.
- Demo coverage for recently completed work lives in
  `examples/panel_demo.nim`, `examples/stepper_demo.nim`,
  `examples/matrix_demo.nim`, `examples/modelcontrollers_demo.nim`,
  `examples/monotext_demo.nim`, `examples/progress_indicator_demo.nim`,
  `examples/cascading_demo.nim`, `examples/viewcontroller_demo.nim`,
  `examples/collectionview_demo.nim`, `examples/controls_showcase.nim`, and
  `examples/merenda_settings_demo.nim`.

## Completed Design Reference

### FigDraw Managed Font and Image Resources (Completed 2026-07-15)

Implemented for the static FigDraw build. The design remains here as the
ownership and renderer-recovery contract; native-dynlib support remains gated
on equivalent managed-resource ABI primitives.

Migrate NimKit drawing and cached layouts from unmanaged `FigFont`/`ImageId`
lifetime handling to a hybrid ownership model: Merenda owns resource-lifetime
policy and lease scopes, while FigDraw's `FontRef` and `ImageRef` own the
underlying retain/release bookkeeping and final backend cleanup. Keep rendering
data cheap and copyable while ensuring that visible and preloaded resources stay
resident, unused resources become eligible for eviction, and every renderer can
recover after its image atlas is rebuilt.

- Keep `TextStyle`, `TextAttributes`, theme values, model records, and FigDraw
  nodes as plain descriptors or raw IDs. Do not embed thread-affine `FontRef` or
  `ImageRef` values in broadly copied or cross-thread data. Treat FigDraw refs as
  the internal lease implementation rather than as NimKit's public resource
  identity.
- Store a `RenderResourceManifest` beside each cached root `Renders`. It
  deduplicates and owns app-thread `FontRef` and `ImageRef` handles while nodes
  keep only raw IDs. `ImageResource` remains the reload source, but is not itself
  pinned merely because a model or hidden view retains it.
- Build the replacement manifest before releasing the previous one so unchanged
  resources never pass through a zero-owner gap. Let ARC/ORC destroy the
  contained FigDraw refs normally; their existing destructors provide the actual
  release operation, so NimKit defines no duplicate resource ownership hooks.
- For threaded rendering, keep manifests on the application thread. Assign each
  moved render tree an ID and retain its manifest in a pending lease queue until
  the renderer acknowledges that ID. The render snapshot contains only the moved
  `Renders`, logical size, and ID; it never copies pixels or crosses threads with
  `FontRef`, `ImageRef`, or `ImageResource` values.
- Never use a force-clear, `clearImageCache`, or raw-ID eviction as the normal
  release path. Dropping Merenda's last lease only makes the logical resource
  eligible for FigDraw eviction; renderer-local atlas clearing and rebuilding are
  separate pressure/recovery operations coordinated at a frame boundary.
- Keep refs on the application thread that created them. Background text layout or
  image decoding may pass `FigFont`, `FontId`, `TypefaceId`, `ImageId`, encoded
  data, or decoded pixels back to that thread, but must create its own ref if it
  needs ownership. Do not pass `FontRef` or `ImageRef` through signals, render
  queues, pasteboard providers, or worker-thread result records.

Font migration:

- Change the internal style resolver so a concrete font is acquired as a
  `FontRef`; use the FontRef overloads of `fs`, `span`, `typeset`, and
  `placeGlyphs`. Continue caching name/fallback resolution as `TypefaceId`s, but
  do not keep every resolved size alive in a process-wide FontRef cache.
- Capture every distinct `FontId` referenced by a committed
  `GlyphArrangement`, including fallback faces, into its owning
  `TextLayoutManager` and into any render snapshot that copies the arrangement.
  Replacing or invalidating a layout must acquire the new refs before dropping
  the old refs; destroying the last layout/render owner should allow FigDraw to
  recycle that font's glyph entries.
- Route simple labels, natural-size queries, explicit glyph placement, UI-relay
  fonts, and externally supplied layouts through the same acquisition path.
  Add or use a FigDraw measurement-only typesetting mode that does not rasterize
  glyphs so transient intrinsic-size queries do not create and immediately evict
  atlas entries.
- Treat FigDraw's parsed typeface registry separately from concrete font/glyph
  ownership. This migration recycles glyph entries through `FontRef`; parsed
  typefaces remain process-cached until FigDraw exposes a safe typeface-release
  contract.

Image migration:

- Keep `ImageResource` as NimKit's identity-bearing metadata and reload-source
  object, but acquire an `ImageRef` only for an active render snapshot, explicit
  preload, or pinned named image. Merely storing an `ImageResource` in a model,
  hidden view, pasteboard item, or off-screen row must not pin its atlas entry.
- Store a rebuildable source for every drawable image: a file path, encoded
  bytes, or an owned copy of direct pixels. File/data resources may discard
  decoded pixels when inactive; direct-pixel and snapshot resources must retain
  a source until the resource itself dies. Preserve the current constructors,
  metadata accessors, `imageId`, and named-image lookup while adding one internal
  acquire/reload path used by all drawing.
- Define the existing `ImageCachePolicy` values in terms of source retention,
  preload admission, and explicit pinning; no policy may create a short-lived
  `ImageRef` and leave a longer-lived node with only its ID. Audit
  `copyImageResource` so pasteboard/drag snapshots have independent source and
  stable-ID semantics instead of accidentally replacing another live image with
  the same ID.
- Make `DrawContext.addImage` retain the acquired `ImageRef` in its manifest
  before emitting an image node. Normal assignments may share an
  `ImageResource`; the named registry and explicit preload APIs are the only
  long-lived strong caches, and removal/window teardown must release their refs.

Atlas rebuild and pressure handling:

- Separate FigDraw's logical ref ownership from renderer-local atlas residency.
  Retain/release and cache-reset events must be broadcast to every registered
  renderer (or read through a generation-stamped event log with a cursor per
  renderer); a single host draining the current global queue must not consume an
  event that another window or popup atlas also needs. Final release should make
  the ID evictable in every renderer without requiring refs to be renderer-bound.
- Add or require a per-renderer FigDraw atlas generation that changes on manual
  cache clears, automatic atlas growth, backend recreation, and device/context
  loss. Expose a renderer-targeted `ensureImage`/rebuild operation; do not infer
  residency from FigDraw's current process-global `hasImage` set or last-renderer
  `atlasUsageSnapshot`, because each NimKit `HostWindow` and popup owns a distinct
  renderer atlas.
- Rebuild at a frame boundary by creating a fresh FigDraw renderer subscription.
  FigDraw replays independently copied current image and glyph messages into that
  renderer's atlas. If replay itself grows the atlas, resubscribe and replay until
  its generation stabilizes before drawing. App-thread manifests and explicit
  preload/pin handles keep the corresponding logical resources alive throughout.
- Make automatic FigDraw atlas growth generation-aware. The current backend
  `grow` implementations clear lookup tables while the logical cache still says
  images are loaded; this must either preserve/copy existing entries or publish a
  new generation and repack all live sources before drawing continues. Treat the
  renderer-targeted generation/rebuild API as a prerequisite rather than hiding
  the race behind NimKit retries or `compiles` fallbacks.
- Monitor exact `renderer.atlasUsage().packedRatio()` per host renderer. Use a
  configurable high-water threshold, hysteresis/cooldown, and a rebuild counter;
  rebuild only the visible/preloaded working set. If that live set cannot fit,
  grow to a planned capacity before repacking instead of repeatedly clearing the
  atlas. Decode reload sources before entering the render-critical upload phase.
- Preserve FigDraw upload generations so stale queued uploads cannot repopulate a
  newly rebuilt atlas. Coalesce concurrent release, reload, and rebuild requests
  at the frame boundary, then request another frame for every window whose atlas
  generation changed.

Verification and rollout:

- Add deterministic tests for copy/move/final-release behavior, overlapping
  render-cache replacement, layout invalidation, hidden/off-screen resources,
  named-image pin/unpin, pasteboard snapshots, and last-owner glyph/image
  eviction under ARC and ORC. Since FigDraw owns the hooks, verify delegation and
  message counts rather than defining duplicate NimKit hooks.
- Force tiny atlases in backend tests to cover automatic growth, explicit
  pressure rebuilds, stale uploads, repeated rebuilds, glyph regeneration, and
  image re-upload without a blank frame. Add two-window and popup-window tests to
  prove that renderer-local residency and generations do not leak across atlases.
- Record replay and generation-recovery counts plus atlas used/packed ratios and
  rebuild counts. Use operation counts for CI and keep wall-clock/frame-time
  measurements diagnostic.
- Migrate the static FigDraw build first. `useNativeDynlib` currently aliases
  `ImageRef` to a raw ID and has no managed `FontRef` ABI; leave that mode
  explicitly unsupported until the native ABI gains retain/release and
  renderer-targeted rebuild primitives. Do not add `compiles` shims that silently
  restore unmanaged behavior.
- Update image, text-layout, rendering, UI-relay, pasteboard/dragging, multiwindow,
  and example coverage, then remove internal raw-font/raw-image upload paths only
  after all NimKit render entry points retain managed resources correctly.

### Main-Thread Application with Optional Render Runtime (Completed 2026-07-15)

Implemented for static FigDraw Metal and Vulkan backends, with direct
main-thread rendering retained for unsupported backends and runtime fallbacks.

Invert the current desktop threading split so the NimKit application, responder
tree, native windows, event dispatch, menus, clipboard, IME, accessibility, and
window lifecycle stay on the platform main thread. Move only FigDraw rendering
behind an optional backend-owned render runtime. This is the natural topology
for UIKit and Android's UI thread while retaining a dedicated renderer where a
presentation backend supports it.

- Treat the platform/UI thread, NimKit application state, renderer, and worker
  pool as explicit roles. A backend may colocate roles, but application and
  widget code must not depend on a particular placement.
- Keep the render boundary narrow: moved `Renders` snapshots, renderer-local
  resource messages, presentation-target size/lifecycle changes, render
  acknowledgements, diagnostics, and shutdown. Do not send input, focus,
  popup, menu, title, visibility, clipboard, or ordinary window commands
  through it.
- Make the render execution mode backend-selected: automatic, direct/main
  thread, or dedicated thread. Use a dedicated thread only after the backend
  can prove that its graphics context and presentation target obey the required
  ownership rules; retain the direct path for unsupported and test backends.
- Use FigDraw's backend capability for application-level selection, then verify
  each configured renderer before moving it. Static Siwin builds support Metal
  and Vulkan presentation targets; OpenGL and failed runtime fallbacks remain
  on the main thread.
- Keep each `Application` and native window on the platform main thread.
  Expensive parsing, indexing, I/O, image decoding, and project work belong in
  Sigil worker actors, with bounded, cancellable, generation-stamped results
  returned to the UI thread.
- Keep `Renders` as a `var`, transfer it with `ensureMove`, and invalidate the
  source render cache immediately. Coalesce pending snapshots per window so a
  renderer never works through stale intermediate frames.
- Have the main thread create, resize, and destroy native presentation targets.
  The renderer exclusively owns its FigDraw context, command encoding, GPU
  cache, and resource replay. Surface replacement/destruction needs an explicit
  generation and release acknowledgement before its target is discarded.
- For Metal, use a custom `CAMetalLayer` host rather than assuming an
  `MTKView` delegate can leave the main actor. For Android, keep Activity/View,
  input, IME, and lifecycle on the main Looper while a surface-backed renderer
  may own EGL/Vulkan work on a dedicated thread.
- Add focused tests for main-thread event dispatch, moved latest-frame delivery,
  renderer shutdown/target release, resize generation ordering, direct fallback,
  and render-resource lease lifetime. Benchmark end-to-end queue/wakeup and
  frame latency separately from the existing ownership-transfer benchmark.

## Near-Term Work

### Resource-Backed UI Construction

Add a Nim-native resource construction layer for UI assets and declarative
structure without committing to Cocoa nib/storyboard compatibility. The goal is
repeatable loading, inspection, and backend bridging for menus, windows, panels,
images, key bindings, and themes.

- Define stable resource records for view/controller trees, menus, commands,
  images, localized strings, key bindings, and theme fragments.
- Keep loaded resources as plain Nim data until they are instantiated into
  identity-bearing views, controls, windows, or controllers.
- Add validation and diagnostics for missing identifiers, selector mismatches,
  unavailable assets, and incompatible resource versions.
- Leave room for future native nib/storyboard or GNUstep resource bridge layers
  without exposing platform resource types in core NimKit APIs.


## Medium-Term Architecture

### Gap-Buffer Text Follow-Ups

Build on the first `GapTextBuffer`/`TextGapStorage` implementation without
changing the `TextEditor`/`TextView` interaction model.

- Keep syntax highlighting as a cache layered beside the buffer: edits should
  invalidate affected line/token ranges, then apply attributes back through
  the normal `TextStorage` APIs for visible or changed ranges.
- Add a UTF-8-backed gap storage path for large files while keeping public
  `TextRange` semantics rune-indexed. Use explicit internal `RuneIndex` and
  `ByteOffset` helpers, plus sparse line/byte index caches, so edits can move
  ARC-owned byte buffers cheaply without exposing byte offsets through the text
  API.
- Defer true virtual/visible-range text layout until profiling shows the
  existing layout manager remains the bottleneck after storage mutation is
  gap-buffer-backed.

### Workspace and Services Layer

Add a backend-neutral workspace/service boundary for app-to-system integration.
This should gather file, URL, service-request, app activation, and promised-file
handoff behavior under one architecture instead of scattering it across panels,
documents, pasteboards, and native adapters.

- Add workspace operations for opening URLs/files, revealing files, launching or
  activating apps where supported, and querying common system locations.
- Route Services-style selected text, selected files, pasteboard requests, and
  promised-file completions through typed service request/response records.
- Integrate recent documents, document-controller open/save flows, pasteboard
  promises, and drag/drop file handoff without making any backend mandatory.
- Keep platform-specific workspace capabilities behind explicit feature checks.

### Native Integration

- Keep render construction unit-testable without a live native window.
- Keep accessibility construction and notification tests backend-free until the native bridge exists.
- Keep native handles private behind `nativeWindowOrNil`/`rendererOrNil` style escape hatches for tests and diagnostics.
- Add accessibility backend adapters for NSAccessibility, UI Automation, and
  AT-SPI-style APIs after the core semantic tree, notifications, and traversal
  helpers are stable; do not put platform imports in the core accessibility
  modules.
- Verify activation, hide/unhide, focus changes, and key/main-window
  transitions on macOS, X11, Wayland, and inline-windowless targets.
- Route native focus/resign/key-window notifications through the same
  `Application` and `Window` state transitions used by tests.
- Enforce window-modal event blocking at the backend dispatch boundary after
  the pure Nim modal blocking contract is stable.
- Add optional native-menu bridging after the pure Nim menu path remains stable
  across examples.
- Move window frame autosave from the current in-process helper store to a
  backend/user-defaults persistence layer when the backend adapter owns
  platform persistence.
- Add native open/save panels, recent-documents integration, represented file
  URLs/proxy metadata, and native print/page setup only after the pure Nim
  document/controller contracts are stable.

### Medium-Term Architecture Updates

- Keep popup presentation policy on `Window`/control instances. Do not add
  global popup state; platforms without native popup windows should keep using
  the same inline FigDraw path.
- Add coordinate caching only after profiling shows the current uncached
  conversion helpers are a measurable cost. Keep frame, bounds, superview, and
  clipping invalidation explicit if caching lands.
- Keep growing the theme/metrics boundary. `Theme` and `Appearance` should
  centralize borders, shadows, focus rings, control metrics, popup/list
  metrics, and state-specific colors as features are added.
- Keep strengthening the control/cell split. Centralize cell invalidation,
  value conversion, target/action storage, highlight/tracking behavior, and
  default cell construction so controls stay thin.
- Treat `ScrollView` as a primitive container like AppKit does. Future text
  editors, table views, outline views, collection views, and large
  forms should be able to build on the same clipped document-view and scrolling
  model.
- Stage layout work conservatively. Expand constraints through the existing
  Cocoa-like lifecycle/model and Kiwiberry-backed solver, then add compatibility
  conveniences only when controls and examples prove the need.
- Expand layout length support beyond the current fixed-font `em` dimension
  constant shortcut. A fuller `LayoutSize`/`LayoutLength` model should preserve
  unresolved units through anchor expressions, resolve them against the relevant
  view/theme/font context

## Long-Term Architecture

### Printing and Page Layout

Treat printing and page layout as a long-term architecture track. The immediate
goal is to avoid painting NimKit into a corner; full print operation, native
print panels, and paginated rendering can land after text, table, document, and
native backend contracts are stable.

- Define page setup records, printable content ranges, pagination containers,
  margins, paper sizes, scale modes, headers/footers, and print job metadata as
  backend-neutral value types.
- Make text layout, table/collection layouts, image views, and custom drawing
  able to produce page-fragment geometry without depending on a live window.
- Add document-controller hooks for page setup, print preview, print operation
  validation, and edited-state-safe print flows.
- Defer native print panel bridges and platform spooler integration until the
  pure Nim pagination and render snapshot contracts are testable.

## Open Questions

- How far to take public export narrowing for `View.x*` storage. The umbrella
  import already hides raw layout-input/cache type names, but fully hiding view
  storage needs a deeper internal accessor or module organization refactor.
- Whether accessibility storage should stay directly on `View` or move behind a
  small per-view semantic record if more role-specific state accumulates.
- Whether container-generated layout inputs should become a real source before
  adding more collection-style controls.
- Whether generated layout summaries should expose richer diagnostics such as
  item names, attributes, priorities, conflicts, or cache-generation metadata.
- How much of the layout invalidation bus should be public. It is useful for
  diagnostics, but most callers should not need to emit layout signals directly.
