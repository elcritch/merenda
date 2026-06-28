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
cascading column views, basic text editing lifecycle, action dispatch, reusable
pure Nim panel/dialog views, matrix cell grids, a themed high-throughput
monospace text view/editor with raw event policy controls, document-controller
infrastructure, AppKit-style in-process pasteboard/dragging foundations, and a
pure Nim accessibility metadata, notification, traversal, validation, and text
semantics core.

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
- Expanded core containers and shared primitives: `ScrollView`/`ClipView`,
  `Box`, `SplitView`, form/grid/stack support, table row primitives, popup
  lists, and the list-to-row vocabulary cleanup are in place with themed
  rendering, intrinsic sizing, layout integration, and example coverage.
- Matured `TableView`, `OutlineView`, and `CascadingView` around protocols
  instead of ad hoc callbacks: headers, sorting, resizing, reordering, hosted
  cells, field-editor-backed editing, state persistence, drag/drop targets,
  disclosure affordances, keyboard behavior, and accessibility semantics are
  covered by focused tests and demos.
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
  `TextLayoutClientProtocol` owner hooks, `TextStorageEditingProtocol`
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
- Drew the first text-layout milestone boundary: multiple text containers,
  exclusion paths, attachment layout, non-contiguous layout, full Cocoa
  `NSLayoutManager` compatibility aliases, and advanced bidi/grapheme
  navigation are explicitly deferred until the core single-container contract
  is proven.
- Added the first Cocoa/TextKit-compatible text model layer without native
  bridge types: richer `TextAttributes` now cover paragraph styles, tab stops,
  line breaking, writing direction, baseline/kerning/ligature/expansion
  fields, backgrounds, shadows, links, decorations, and attachment metadata;
  `TextStorage` exposes mutable attributed-string aliases and rune-indexed
  edit/query helpers; and text transfer/pasteboard contracts cover plain text,
  attributed text, RTF, RTFD-style package payloads, HTML fragments, URLs, and
  file promises.
- Filled out the current desktop control set: buttons, checkboxes, radio
  buttons, switches, text fields/editors, combo boxes, popup/menu buttons,
  progress indicators, sliders, steppers, dialog button boxes, group boxes, and
  image views now route state through NimKit setters, target/action dispatch,
  rendering invalidation, layout metrics, and accessibility notifications.
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

## Current Verification

- `atlas-run tests` passes locally on macOS with the current domain module
  layout; the latest full run passed `40/40`.
- Focused suites cover the main widget/runtime seams:
  `tests/tnimkit_controls.nim`, `tests/tnimkit_matrix.nim`,
  `tests/tnimkit_monotextviews.nim`, `tests/tnimkit_tableviews.nim`,
  `tests/tnimkit_outlineviews.nim`, `tests/tnimkit_documents.nim`,
  `tests/tnimkit_animations.nim`, `tests/tnimkit_rendering.nim`,
  `tests/tnimkit_accessibility.nim`, and `tests/tnimkit_textlayout.nim`.
- Demo coverage for recently completed work lives in
  `examples/panel_demo.nim`, `examples/stepper_demo.nim`,
  `examples/matrix_demo.nim`, `examples/monotext_demo.nim`,
  `examples/progress_indicator_demo.nim`, `examples/cascading_demo.nim`, and
  `examples/controls_showcase.nim`.
- GitHub Actions is currently blocked before runner startup by account billing
  or spending-limit state, not by a Nim build or test failure. Rerun CI after
  the GitHub account issue is cleared.

## Near-Term Work

### TextLayoutManager

Turn the current FigDraw-backed helper into the stable text layout contract used
by `TextView`, `TextField`, accessibility, selection drawing, hit-testing, and
future text backends. Do this as a NimKit API first, not as a full
`NSLayoutManager` clone: expose plain Nim value records and protocol methods
over rune-indexed `TextRange`/`TextIndex`, while keeping FigDraw placement data
private except for diagnostics.

9. Bring `TextStorage` close to `NSTextStorage` behavior:
   - add `beginEditing`/`endEditing`, edited masks for characters vs
     attributes, edited range/change-in-length tracking, and coalesced
     `processEditing` dispatch
   - add `TextStorageDelegateProtocol` and Sigils signals matching the Cocoa
     notification order: will process editing, did process editing, and storage
     value/attribute changes after mutation has committed
   - support attribute fixing hooks, paragraph-range expansion, font fallback
     fixing, and optional lazy backing storage for very large documents
   - allow multiple layout managers to observe one storage instance while
     preserving deterministic invalidation and avoiding view-specific storage
     callbacks
10. Expand `TextContainer` toward `NSTextContainer` parity:
   - support container size tracking, line fragment padding, width/height tracks
     text view flags, maximum number of lines, line break mode, and exclusion
     paths
   - add multiple text containers per layout manager for paged, column, and
     flowed text layouts, with explicit container indexes in line fragments and
     hit-testing results
   - expose container replacement and invalidation hooks so scroll views,
     print/page layout, and multi-container text views can share the same model
11. Expand `TextLayoutManager` toward `NSLayoutManager`/TextKit 2 parity:
   - add glyph generation and glyph property APIs, character-to-glyph and
     glyph-to-character mappings, glyph ranges for bounding rects, bounding
     rects for glyph ranges, line fragment rect/used rect queries, extra line
     fragment metrics, and temporary attributes
   - add invalidation APIs for characters, glyphs, layout, display, and
     containers, keeping range invalidation observable and testable
   - add delegate/protocol hooks for should-generate-glyphs, line spacing,
     paragraph spacing, hyphenation decisions, layout completion, and temporary
     rendering attributes
   - support background layout, optional non-contiguous layout, and partial
     relayout once the deterministic single-container path is well covered
   - keep Cocoa selector-compatible aliases as a compatibility layer over
     NimKit names rather than making Objective-C naming the primary Nim API
12. Bring `TextView` close to `NSTextView` behavior:
   - add selection affinity/granularity, rectangular selection hooks, multiple
     selected ranges if needed for compatibility, typing attributes, selected
     text attributes, insertion point color/blink policy, marked text rendering,
     find indicators, and spelling/grammar underline attributes
   - add delegate/protocol hooks for should/did begin editing, should/did
     change text, selection changes, clicked links/attachments, completions,
     menu validation, and command validation
   - support undo grouping, smart insert/delete, quote/dash/link substitution,
     data detectors as optional text checking hooks, find/replace, spell check,
     grammar check, and completion panels as reusable pure Nim contracts
   - add ruler/tab-stop and paragraph-style editing hooks without making rulers
     mandatory for simple text fields
13. Harden input, command, and field-editor parity:
   - complete `NSTextInputClient`-style marked text, selected range,
     attributed substring, valid attributes for marked text, first rect for
     character range, character index for point, and IME command dispatch
   - route key bindings through selector-backed commands so Cocoa-style
     movement/editing selectors, responder-chain validation, and Qt-style
     signal observers can coexist
   - keep the shared field editor model for text fields, table cells, outline
     cells, combo boxes, and form controls, with visible tests for geometry and
     selection stability
14. Add rich editing integrations expected by Cocoa text users:
   - drag/drop selected text and attachments, services-style selected text
     requests, contextual menus, link opening, attachment cells/views, image
     attachments, file promises, and document-controller save/open integration
   - add accessibility text parameterized attributes: attributed string for
     range, range for line, range for position, bounds for range, visible
     character range, selected ranges, and insertion point line
   - add print/page layout hooks, pagination containers, ruler metrics, and
     snapshot tests for layout stability across display scale and font changes


### OutlineView

Continue growing the protocol-backed outline API into a production AppKit-style
widget.

1. Harden outline behavior on top of the current disclosure rendering path:
   - add richer outline keyboard navigation, multi-selection behavior aligned
     with `TableView`, type-ahead/find-style selection, and optional delegate
     hooks for disclosure rendering and indent metrics
2. Finish identity-based persistence:
   - persist selection by stable item identity instead of only visible row
     indexes
   - add migration behavior for renamed/moved items
   - verify expansion and selection autosave restore timing through the same
     application, workspace, document, and window lifecycle paths used by table
     state storage
3. Finish outline drag/drop integration beyond the baseline item target:
   - add distinct before/on/after insertion targets for outline items on top of
     the current item/cell drop target model
   - render insertion affordances that distinguish parent-child drops from
     before/after sibling insertion
   - deepen outline delegate validation and acceptance hooks for proposed
     operation, target, and insertion position before completing a drop


## Medium-Term Architecture

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
