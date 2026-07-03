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

## Current Verification

- `atlas-run tests` passes locally on macOS with the current domain module
  layout; the latest full run passed `2/2`.
- Focused NimKit coverage lives under `tests/nimkit/*.nim` and is aggregated
  by `tests/tnimkit.nim`; current modules cover controls, matrix,
  monospace text views, tables, outlines, collection views, documents,
  animations, rendering, accessibility, text storage/layout/views,
  pasteboards/dragging, document tabs, undo managers, object values, model
  controllers, notifications, responders, view controllers, windows/controllers,
  constraints, and themes.
- Demo coverage for recently completed work lives in
  `examples/panel_demo.nim`, `examples/stepper_demo.nim`,
  `examples/matrix_demo.nim`, `examples/modelcontrollers_demo.nim`,
  `examples/monotext_demo.nim`, `examples/progress_indicator_demo.nim`,
  `examples/cascading_demo.nim`, `examples/viewcontroller_demo.nim`,
  `examples/collectionview_demo.nim`, and `examples/controls_showcase.nim`.
- GitHub Actions is currently blocked before runner startup by account billing
  or spending-limit state, not by a Nim build or test failure. Rerun CI after
  the GitHub account issue is cleared.

## Near-Term Work

### CascadingView Model Backing

Move `CascadingView` toward a Browser-style tree model without making each
column own its own independent row storage. The selected path, visible columns,
and child lookups should be identity-backed across reloads and model mutations.

1. Share the tree-item vocabulary with future outline work:
   - define stable item identifiers, parent identifiers, display values, leaf
     state, optional icons, and opaque model payloads as plain value records
   - keep the existing `CascadingDataSource` compatibility path while adding
     object-value and item-identity lookups
2. Preserve selection by path identity:
   - restore selected paths by identifiers instead of column/row indexes
   - preserve focused column, visible column scroll, and activated item state
     after reloads, sorting, or filtering
3. Add incremental tree update hooks:
   - reload a parent, insert/remove/move children, and collapse invalid paths
     without forcing a full column rebuild
   - make accessibility notifications describe item/path changes instead of only
     table-row changes inside generated columns

### ComboBox Choice Model Backing

Make `ComboBox` and related choice popups use a small option model instead of a
string-only list. The control should own editing, popup presentation, highlight,
and selection UI state; the data source or optional adapter should own option
records.

1. Expand option values beyond strings:
   - add option identifiers, display text, object value, enabled/hidden state,
     separators, optional icon/image, tooltip, and search text
   - keep existing string item APIs as compatibility sugar over display text
2. Persist and restore selection by option identity:
   - use identifiers for selected/highlighted options when available, with index
     fallback for legacy string lists
   - make editable combo boxes distinguish typed text from selected object value
3. Add a reusable option-list adapter:
   - provide seq-backed option storage for tests/examples and simple apps
   - support filtered suggestions, type-ahead lookup, and popup row reloads
     without coupling `PopupListView` itself to model ownership

### Menu Item Model Backing

Back dynamic menus, popup buttons, and menu-like choice lists with a command/item
model. `PopupListView` should remain a presentation primitive; model ownership
belongs above it in menu and popup controls.

1. Define a shared menu item record:
   - identifier, title, subtitle/key equivalent, state, enabled/hidden,
     separator, submenu children, image, target/action selector, represented
     object, and validation metadata
   - keep menu item records as plain values unless a menu bridge needs identity
     for native handles
2. Route validation through model updates:
   - let responder-chain validation update enabled/state/title metadata before a
     menu opens
   - support dynamic child generation for document/window/recent-items menus
     without rebuilding unrelated menu state
3. Share accessibility and pasteboard semantics:
   - expose menu hierarchy and item actions from the model record
   - make popup/menu presentation reuse the same item model where practical

### DocumentTabs Model Backing

Tie `DocumentTabs` to document/window identity instead of treating tab items as
the durable source of truth. The tab bar should render and manipulate a document
tab model owned by the document/window controller layer.

1. Add document-backed tab item identity:
   - map tab identifiers to document/window/controller objects through a narrow
     represented-object hook
   - derive title, modified state, closeability, enabled state, style, accent
     color, and tooltip from the model when available
2. Preserve ordering and selection by document identity:
   - persist selected tab and tab order by stable document/window identifiers
   - keep drag reordering as a model mutation with delegate veto/notification
     hooks
3. Align close and activation flows with document ownership:
   - route close requests through document-controller validation
   - update tab state from document edited/title changes without rebuilding the
     whole tab bar

### Matrix Item Model Backing

Keep `Matrix` useful as an `NSMatrix`-style cell grid, but add an optional item
model for dynamic grids of choices. This should be lower-risk and smaller than
the collection/tree model work.

1. Add optional cell item descriptors:
   - identifier, title, state, enabled, tag/value, tooltip, image, and action
     metadata
   - keep direct `ButtonCell` ownership for legacy/manual matrix construction
2. Preserve selection by item identity:
   - expose selected item identifiers alongside selected indexes
   - keep radio/single/multiple selection modes consistent when items are
     inserted, removed, or reordered
3. Add adapter and tests for dynamic choices:
   - support seq-backed item grids and fixed row/column projection
   - verify keyboard movement, action dispatch, and accessibility still work when
     cells are generated from model items

### OutlineView Model Backing

Finish `OutlineView` last, after `TableView` and `CascadingView` establish the
shared row/object value and tree-item contracts. Outline should remain a
specialized table/tree presentation over a model, not a separate competing model
system.

1. Layer outline item data on the shared tree model:
   - reuse stable identifiers, parent-child lookup, item display values, leaf or
     expandable state, and opaque represented objects
   - keep existing `OutlineItem` and `OutlineViewDataSource` APIs as a
     compatibility path
2. Finish identity-based expansion and selection:
   - persist expanded items, selected rows, anchor/lead, and visible scroll row
     by stable item identity instead of visible row index
   - add migration behavior for renamed/moved items through aliases or resolver
     callbacks
3. Add incremental outline updates:
   - reload, insert, remove, and move children under a parent while preserving
     expansion, selection, row heights, hosted cells, and accessibility
     notifications
   - distinguish model mutations from purely visual disclosure toggles
4. Deepen outline drag/drop integration:
   - add distinct before/on/after insertion targets for outline items on top of
     the current item/cell drop target model
   - render insertion affordances that distinguish parent-child drops from
     before/after sibling insertion
   - validate and accept drops through model-aware delegate/data-source hooks


## Medium-Term Architecture

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
