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
constraints, stack/form/grid containers, buttons, text fields, combo boxes,
scroll views, list views, table views, basic text editing lifecycle, action
dispatch, AppKit-style in-process pasteboard/dragging foundations, and a pure
Nim accessibility metadata and protocol core.

The source tree is now organized around domain modules under
`accessibility`, `app`, `controls`, `containers`, `drawing`, `foundation`,
`responder`, `text`, and `view`. The stable public entry point remains
`merenda/nimkit`; internal code and tests should import the domain modules
directly when they need a narrower surface.

The next work should move NimKit toward the OpenSTEP/AppKit framework shape:
stabilize the remaining native/backend edges around application, window, and
semantic accessibility behavior, then add richer pasteboard, dragging,
graphics-resource, document, table, and outline systems. Avoid adding
widget-local special cases where AppKit solves the behavior through the
application, responder, view, window, accessibility, or control/cell layers.

## Recently Completed

- Reorganized NimKit into domain subdirectories and removed the old empty
  top-level module forwarders. The `merenda/nimkit` umbrella remains the
  compatibility import for users.
- Removed the leftover `src/merenda/nimkit/chromes/aquachrome.nim`
  compatibility shim; Aqua chrome now lives only at
  `src/merenda/nimkit/drawing/chromes/aquachrome.nim`.
- Added image resources on top of FigDraw: pixel/data/file construction, named
  image registration, cache policy storage, pasteboard image storage, image
  drawing nodes, and `ImageView` with intrinsic sizing and accessibility
  semantics.
- Expanded `ClipView` and `ScrollView` parity: clipped document ownership,
  constrained `scrollToPoint`, autoscroll, document/visible rect helpers,
  clip-view background policy, reflected scroll notifications, per-axis
  line/page scrolling, border/background policy, scroller insets, header/corner
  chrome, ruler placeholders, dynamic scrolling storage, and explicit scroller
  autohide policy. Updated `examples/scrollview_demo.nim` to exercise the new
  chrome and scrolling APIs.
- Expanded `TableView` and added initial `OutlineView`: table columns now carry
  hidden/sort/reuse metadata, header hit testing and resize/reorder/sort request
  helpers are in place, table selection tracks clicked row/column and selected
  columns, editable-cell begin/commit/cancel state is modeled with delegate
  hooks, column autosave records serialize table-owned column state, drag-info
  value objects and validation/acceptance hooks are staged, and `OutlineView`
  flattens expandable items into table rows with outline-column disclosure
  text, row/item mapping, and expansion/collapse APIs.
- Hardened the table/outline model toward AppKit-style behavior: table header
  cells now render and track hover/pressed, resize, reorder, and sort
  interactions; editing, column/header behavior, selection, dragging,
  persistence, and state capture/restore route through overridable table
  protocols while preserving typed public procs; hosted cell views have a reuse
  queue; table state snapshots can save/restore column state and selections
  through a backend-neutral state storage protocol; drag payloads integrate with
  named pasteboards; and `OutlineView` now has data-source/delegate protocols,
  disclosure hit testing, keyboard toggling, expansion persistence, and item
  drag helpers.
- Finished the latest table/outline API cleanup: table behavior and state
  protocols no longer pass the table view back into table-owned methods, state
  save/restore flows through the protocol surface without compatibility
  wrappers, and public selection/resize/editing/persistence procs delegate
  through those protocols consistently.
- Expanded `OutlineView` rendering and semantics with dedicated disclosure
  affordances instead of text prefixes, mouse down/up disclosure tracking,
  richer item identity helpers, expansion state capture/restore through the
  shared table state protocol, and accessibility roles/actions for outline rows
  and disclosure controls.
- Updated `examples/table_demo.nim` to use real table headers instead of fake
  temporary label headers, and constrained the title/table layout so the table
  resizes with the window without unstable vertical stretching.
- Expanded pasteboard and dragging foundations toward the OpenStep/AppKit
  shape: pasteboards now use generic item storage with named/unique registry
  lookup, change counts, release semantics, typed declarations, owner/lazy
  item callbacks, strings, text storage, data blobs, property lists, URLs/files,
  colors, font descriptors, and images; dragging now has generic operations as
  a set, pasteboard-backed drag items, drag sessions, source/destination
  protocols, lifecycle hooks, and promised-file item staging.
- Added a pure Nim accessibility core: roles, traits, notifications, typed
  attribute values, default view metadata, ignored/element state, flattened
  accessibility children, settable attribute helpers, and action dispatch.
- Added built-in accessibility semantics for views, buttons, checkboxes, text
  fields, labels, and value-change notifications, with
  `tests/tnimkit_accessibility.nim` covering the core behavior.
- Expanded responder event coverage for key up, modifier flag changes,
  right/other mouse events, scroll phases, help requests, and cursor/tracking
  events.
- Added responder-chain command/action helpers for `performKeyEquivalent`,
  `tryToPerform`, `doCommandBySelector`, valid requestor lookup, and
  undo-manager lookup.
- Broadened selector coverage for text movement/editing, menu commands, and
  collection-like controls.
- Made the event return contract explicit: handlers return whether they
  consumed an event/action, unhandled events continue through `nextResponder`,
  and controls may apply policy before forwarding.
- Updated tests and design notes for the responder contract.
- Added core `NSView` parity APIs for identity and hierarchy management:
  `tag`, `identifier`, recursive tag lookup, positioned/indexed subview
  insertion, replacement, sorting, and lifecycle-preserving hierarchy updates.
- Added flipped coordinate conversion support while preserving NimKit's
  existing y-down default, plus view-level focus-ring type, alpha, and shadow
  properties.
- Wired view alpha and shadows into render construction for view background
  nodes.
- Added view tracking affordance storage for cursor rects, tracking areas,
  tooltips, drag type registration, and a default autoscroll hook.
- Added OpenSTEP-style menu infrastructure: `Menu`, `MenuItem`, application
  `mainMenu`/`windowsMenu`, responder-chain validation, key-equivalent dispatch,
  delegate update/open/close hooks, submenu/separator/key-equivalent rendering,
  and a menu demo.
- Added popup menu presentation infrastructure with inline/window popup policy,
  a `PopupMenuButton`, popup list rows for menu items, separator rows, submenu
  indicators, key-equivalent columns, menu-bar pull-down buttons, and hover/open
  highlighting.
- Added overridable menu protocols for menu lifecycle, menu key-equivalent
  dispatch, popup menu open/close, and menu bar reload while preserving the
  typed public proc API.
- Strengthened `Application` with current-event, key/main-window,
  active/running/hidden state, launch/activation/hide/termination delegate
  lifecycle, termination reply flow, main-menu key-equivalent dispatch, and
  first-class modal sessions.
- Strengthened `Window` with style masks, levels, key/main roles, delegates,
  min/max sizes, resize increments, autosave names, initial/future first
  responder hooks, richer screen/window/view coordinate conversion, transient
  popup sessions, and sheet attachment lifecycle.
- Finished the pure Nim menu-tracking path with cascading submenu popups,
  menu-bar hover switching across open top-level menus, keyboard navigation,
  first-enabled-item selection, separator/disabled skipping, checked/mixed state
  rendering, and disabled item rendering/activation behavior.
- Integrated application `windowsMenu` population and validation with the main
  menu model, including order-front actions and checked main-window state.
- Built modal sessions and sheet presentation on the application/window model,
  including app-modal and window-modal modes, visible attached sheet windows,
  modal result propagation, alert/open/save panel entry points, and termination
  deferral while a modal session is active.
- Added application/window integration for programmatic activation, key/main
  transitions, hide/unhide window restore, frame autosave helpers, and window
  menu refresh when windows are added, removed, activated, or closed.

## Current Verification

- `nim test` passes locally on macOS with the current domain module layout.
- GitHub Actions is currently blocked before runner startup by account billing
  or spending-limit state, not by a Nim build or test failure. Rerun CI after
  the GitHub account issue is cleared.

## Near-Term Work

### Accessibility Core

Keep accessibility backend-neutral until the native application/window backend
boundary is ready.

1. Fill out role and trait defaults for menus, popup lists, combo box popup
   rows, tabs, scroll areas, list rows, table rows, and table cells.
2. Route focus, selection, enabled-state, expanded/collapsed, and value-change
   notifications from the same mutation procs that already update rendering or
   responder state.
3. Add semantic traversal helpers:
   - accessibility element at point
   - ordered accessibility descendants
   - role/action validation helpers for tests and future backend bridges
4. Add richer text accessibility hooks:
   - selected range, insertion point, editable/selectable traits, and basic
     line/character geometry once text layout exposes stable offsets
5. Stage native bridge work later behind a backend adapter for NSAccessibility,
   UI Automation, and AT-SPI-style APIs; do not put platform imports in the core
   accessibility modules.

### Application And Window Hardening

Keep the pure Nim application spine stable while connecting more behavior to
real native backends.

1. Deepen native activation behavior:
   - verify activation, hide/unhide, focus changes, and key/main-window
     transitions on macOS, X11, Wayland, and inline-windowless targets
   - route native focus/resign/key-window notifications through the same
     `Application` and `Window` state transitions used by tests
2. Harden modal and termination flows:
   - extend termination review from active modal panels to document-driven
     unsaved-change review once the document layer lands
   - make window-modal event blocking enforceable at the backend dispatch
     boundary, not only through application state queries
3. Round out menu and persistence integration:
   - add optional native-menu bridging after the pure Nim menu path remains
     stable across examples
   - move window frame autosave from the current in-process helper store to a
     backend/user-defaults persistence layer
   - add richer window-level menu validation for close/minimize/zoom and
     document-window commands

### Pasteboard And Dragging

Harden the new in-process AppKit-style pasteboard and dragging foundations and
connect them to widgets and native backends.

1. Add backend provider coverage beyond text:
   - bridge data blobs, URLs/files, images, colors, fonts, and native change
     counts where the host backend exposes them
   - map `releaseGlobally` to true global pasteboard release where supported
2. Integrate generic drag sessions with controls and containers:
   - migrate table/outline drag helpers from `TableDraggingInfo` staging to
     `DraggingSession`/`DraggingInfo`
   - add list/control source and destination hooks, row/item drop targeting,
     and autoscroll during active sessions
3. Finish promised-file behavior:
   - turn promised-file drag items into backend callbacks for real native drag
     sessions while keeping the pure Nim in-process fallback

### Documents And Controllers

Add the document/window-controller layer after application, menu, and window
semantics are stable enough to host it.

1. Add `WindowController`:
   - owns a window, controls loading/showing/closing, synchronizes titles, and
     bridges window delegates without making every document own window details
2. Add `Document`:
   - file URL/name/type, display name, edited state, undo manager, window
     controllers, readable/writable type hooks, save/revert/close lifecycle, and
     print hooks as backend support appears
3. Add `DocumentController`:
   - shared controller, new/open/reopen document flow, recent documents,
     document lookup by window/URL, close-all/review-unsaved flow, and menu
     validation for document actions

### TableView And OutlineView

Continue growing the protocol-backed table and outline APIs into production
AppKit-style widgets.

1. Connect real editing surfaces:
   - attach field editors or hosted cell editors to the protocol-backed
     begin/commit/cancel flow, support validation errors, and route tab/return
     navigation between editable cells
2. Finish native-feeling header interaction:
   - add resize cursors/tracking areas, richer sort indicator rendering,
     visible column drag insertion affordances, and autoscroll while reordering
     columns
3. Finish drag/drop integration:
   - connect `TableDraggingInfo` and outline item dragging to full dragging
     sessions, source/destination lifecycle hooks, row/column drop targets,
     promised data, and named pasteboard payload declarations
4. Finish persistence integration:
   - back the table state storage protocol with application/user-defaults,
     document/workspace-specific state stores, migration behavior for renamed
     columns/items, and restore timing tied to window/document lifecycle
5. Harden outline behavior on top of the new rendering path:
   - add richer outline keyboard navigation, row/item drop targeting, selection
     persistence by stable item identity, and optional delegate hooks for
     disclosure rendering/indent metrics

### Native Integration

- Keep render construction unit-testable without a live native window.
- Keep accessibility construction and notification tests backend-free until the native bridge exists.
- Keep native handles private behind `nativeWindowOrNil`/`rendererOrNil` style escape hatches for tests and diagnostics.

## Medium-Term Architecture

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
  editors, list views, table views, outline views, collection views, and large
  forms should be able to build on the same clipped document-view and scrolling
  model.
- Keep `ListView` as the simple single-column data widget. Share row
  infrastructure with table/outline controls only when the reuse boundary is
  proven by real table and outline behavior.
- Stage layout work conservatively. Expand constraints through the existing
  Cocoa-like lifecycle/model and Kiwiberry-backed solver, then add compatibility
  conveniences only when controls and examples prove the need.
- Expand layout length support beyond the current fixed-font `em` dimension
  constant shortcut. A fuller `LayoutSize`/`LayoutLength` model should preserve
  unresolved units through anchor expressions, resolve them against the relevant
  view/theme/font context, and support offsets such as
  `cx(label.topAnchor == field.bottomAnchor + 1'em)` without converting to
  points too early.

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
