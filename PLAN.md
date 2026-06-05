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
buttons, text fields, combo boxes, popup list infrastructure, and the first
standalone `ListView`.

The next work should keep building on that stable core rather than reopening the
layout model unless a new control proves a missing shape.

## Near-Term Work

### ScrollView And ListView

Build this stage as reusable infrastructure, not as list-only behavior. The
target is enough Cocoa/AppKit-like behavior to support complex applications:
sidebars, inspectors, pickers, logs, search results, simple data browsers, and
future table/outline-style controls.

Recently completed:
- `ScrollView` now has a real `ClipView`, explicit document/content ownership,
  content offsets derived from clip-view bounds, intrinsic sizing separated from
  document size, and sibling scroller views tiled through one reflection path.
- Scroller views now handle direct interaction: gutter clicks page content along
  the scroller axis, and knob dragging maps track motion back to content
  offsets with normal clamping.
- Scroll routing now carries phase/momentum metadata, preserves momentum target
  routing, uses `wantsForwardedScrollEvents`, and keeps edge-forwarding policy
  out of the main public scroll API.
- Programmatic scroll helpers include exact offsets, `scrollRectToVisible`, and
  normalized fraction scrolling with independent `x`/`y` axes.
- List and popup row-window math now flows through `ListViewport` backed by the
  shared `ScrollViewport` helpers, covering row offset clamping, scroll-by,
  scroll-to-visible, and scroll indicator progress.
- Standalone `ListView` now owns a non-hit-testable `ClipView` and a
  non-focusable `ListContentView` row document. Row sizing, visible-row drawing,
  point-to-row mapping, and `firstVisibleIndex` now flow through the clip
  bounds origin while `ListView` keeps the public control, selection, keyboard,
  and target/action surface.
- Standalone `ListView` now owns a sibling `ListScroller` above its clipped row
  document. The list scroller uses the shared `ScrollView` scroller metrics and
  renderer, reserves a scroller strip from row content, and supports gutter
  paging plus knob dragging while preserving the row-based public scroll API.
- `ListView` now has selector-backed data source hooks for row count and row
  value lookup, delegate hooks for selection changes and activation, and a
  first real selection model with none, single, multiple, and extended modes.
  Extended selection tracks anchor/lead rows, supports Shift range extension
  from mouse and keyboard, and supports command/control discontiguous toggles.
- View frame/layout updates now preserve existing bounds origins, so clip-view
  scroll positions survive display preparation and constraint/layout passes.
- `ListContentView` now virtualizes fixed-height rows as reusable private row
  views. The row slots are non-focusable, non-hit-testable, retargeted from the
  clip-view visible rect, and keep row reuse separate from data ownership.
- `ListView` delegates can override visible row rendering through
  `listViewDrawRow` with a plain `ListRowState` and row-local bounds. Custom
  renderers can call `drawListRow` to reuse the default themed row drawing
  without depending on private reusable row views.

1. Finish `ListView` data/delegate policy hooks:
   - keep local `items` as the simple default path
   - add delegate hooks for row height and optional row styling
   - consider disabled or nonselectable rows if examples justify the policy
   - keep row state as plain values: index, selected, highlighted, focused,
     enabled
2. Polish selection APIs and diagnostics:
   - add selected range convenience APIs if callers need them
   - add scroll-to-selection helpers
   - add accessibility/debug summaries for visible rows and selection state
   - keep delegate notifications before and after real selection changes
3. Finish row virtualization polish:
   - add variable row heights after fixed-height behavior is stable
   - keep reusable row slots private until the cell/view customization shape is
     clear
4. Add AppKit-like keyboard and focus behavior:
   - up/down/page/home/end are in place for fixed-height rows
   - type-select or incremental search
   - focus ring and first-responder behavior
   - activation through Enter/Return/double-click
5. Add richer list affordances:
   - empty state rendering hook
   - alternating row backgrounds
   - separators/grid lines if theme roles support them
   - row hover and pressed states
6. Defer full table/outline APIs until this base is solid:
   - column headers
   - sortable columns
   - resizable/reorderable columns
   - tree disclosure rows
   - drag reordering
   - cell editing

### Controls

- Keep text editing scoped to single-line control behavior for now. Grow
  command selectors and key bindings before adding multiline editor features.
- Add new controls only after their default frame behavior, intrinsic sizing,
  focus handling, theme metrics, and examples can use the existing measurement
  path from the start.
- Keep delegate/custom policy hooks selector-based and explicit where they
  affect behavior. Use generic forwarding for control-to-cell delegation, not
  for arbitrary view or delegate dispatch.

### Rendering And Events

- Keep whole-window FigDraw rebuilds until they become measurable. Preserve
  dirty-rect metadata and explicit display traversal so a later backend can
  narrow rendering without changing view APIs.
- Add clipped dirty-rect rendering only when the FigDraw/backend boundary has a
  concrete partial-present path.
- Grow the default key binding table only as new text editing commands, menu
  shortcuts, and richer key equivalents need it.
- Build future menus, popovers, and drag/tracking behavior on the existing
  transient popup/session base so dismissal and focus restoration stay shared.

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
- Treat `ListView` as the first serious scroll-backed data widget. It should
  become feature-complete enough for complex app use before adding a full table
  view.
- Stage layout work conservatively. Expand constraints through the existing
  Cocoa-like lifecycle/model and Kiwiberry-backed solver, then add compatibility
  conveniences only when controls and examples prove the need.

## Open Questions

- How far to take public export narrowing for `View.x*` storage. The umbrella
  import already hides raw layout-input/cache type names, but fully hiding view
  storage needs a deeper internal accessor or module organization refactor.
- Whether container-generated layout inputs should become a real source before
  adding a table-style control.
- Whether generated layout summaries should expose richer diagnostics such as
  item names, attributes, priorities, conflicts, or cache-generation metadata.
- How much of the layout invalidation bus should be public. It is useful for
  diagnostics, but most callers should not need to emit layout signals directly.
