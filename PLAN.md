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
theme/rendering, intrinsic sizing, constraints, stack/form/grid containers,
buttons, text fields, combo boxes, scroll views, list views, table views, basic
text editing lifecycle, action dispatch, and in-process pasteboard support.

The next work should move NimKit toward the OpenSTEP/AppKit framework shape:
application/window/menu/responder infrastructure first, then richer view,
pasteboard, dragging, graphics-resource, document, table, and outline systems.
Avoid adding widget-local special cases where AppKit solves the behavior through
the application, responder, view, window, or control/cell layers.

## Recently Completed

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

## Near-Term Work

### OpenSTEP Application Spine

Build the framework-level pieces that AppKit treats as core infrastructure.

1. Add real menu infrastructure:
   - `Menu` and `MenuItem` objects with title, action, target, state, enabled
     state, key equivalent, modifier mask, submenu, separator item, tag, and
     optional represented/user info
   - application `mainMenu` and `windowsMenu`
   - menu validation through the responder/action chain
   - key-equivalent dispatch before normal key handling
   - menu delegate hooks such as update/open/close notifications
2. Strengthen `Application`:
   - track current event, key window, main window, active/running/hidden state
   - add activation, hide/unhide, termination request/reply, and application
     delegate lifecycle hooks
   - add modal sessions as a first-class application/window flow instead of
     ad-hoc control state
3. Strengthen `Window`:
   - style masks, levels, key/main window roles, delegates, min/max sizes,
     resize increments, autosave names, initial/future first responder, and
     richer screen/window/view coordinate conversion
   - modal sheets, panels, alerts, and open/save panels after the core window
     delegate and modal-session model is stable

### Pasteboard And Dragging

Turn the current in-process text pasteboard into an AppKit-like data exchange
foundation.

1. Add named pasteboards:
   - general, drag, find, font, ruler, and unique pasteboards
   - change counts, global release semantics where a backend supports them, and
     typed data declarations
2. Add richer pasteboard payloads:
   - strings, text storage, data blobs, property lists, URLs/files, colors,
     fonts, and images as the resource types land
   - owner/lazy-data callbacks for expensive values
3. Add dragging protocols:
   - source and destination hooks, drag operations, dragging info, session
     lifecycle, promised files, and control/table/list integration

### Graphics Resources

Keep FigDraw as the renderer boundary, but add AppKit-style resource objects on
top of it.

1. Add richer color support:
   - color spaces, grayscale/RGB/HSB/CMYK constructors, system colors, theme
     conversion, and pasteboard support
2. Add font resources:
   - system/user/fixed fonts, traits, metrics, descriptors, and typing
     attribute integration
3. Add image resources:
   - file/data/pasteboard construction, named images, size/cache policy, image
     views, and image drawing nodes

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

### ScrollView And ClipView Parity

Keep treating `ScrollView` as a primitive container like AppKit does.

1. Expand `ClipView` responsibilities:
   - document cursor, `scrollToPoint`, `constrainScrollPoint`, autoscroll,
     document rect, visible rect, background/draws-background policy, and
     `reflectScrolledClipView` notifications
2. Expand `ScrollView` chrome:
   - horizontal/vertical line and page scroll values, border/background policy,
     scroller insets, header/corner views, ruler placeholders, dynamic
     scrolling, and autohide policy

### TableView And OutlineView

Continue growing `TableView` after the application, responder, view, pasteboard,
and dragging foundations can support it.

1. Add table headers and column behavior:
   - header band, column hover/pressed state, hit testing, resizing with
     min/max constraints, sort request state, sort indicator rendering, and
     column reordering
2. Add table selection and editing:
   - cell and column selection, clicked row/column reporting, editable cells,
     commit/cancel flow, row views, and reuse identifiers
3. Add drag/drop and persistence:
   - row/column drag behavior, column autosave, selection persistence helpers,
     and integration with named pasteboards
4. Add `OutlineView` after `TableView` is stable:
   - item tree data source, expansion/collapse, row/item mappings,
     indentation, outline column, disclosure rows, persistence, and drag/drop

### Native Integration

- Continue testing scaled input against rendering on macOS, X11, Wayland, and
  inline-windowless targets.
- Keep render construction unit-testable without a live native window.
- Keep native handles private behind `nativeWindowOrNil`/`rendererOrNil` style
  escape hatches for tests and diagnostics.

## Medium-Term Architecture

- Add a formal backend boundary when `Application`/`Window` start accumulating
  more siwin-specific logic. Window creation, event polling, native handle
  lookup, renderer ownership, and backend operations should sit behind a small
  NimKit backend interface.
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
- Whether container-generated layout inputs should become a real source before
  adding more collection-style controls.
- Whether generated layout summaries should expose richer diagnostics such as
  item names, attributes, priorities, conflicts, or cache-generation metadata.
- How much of the layout invalidation bus should be public. It is useful for
  diagnostics, but most callers should not need to emit layout signals directly.
