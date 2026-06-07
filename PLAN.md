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

### TableView

Build `TableView` as a sibling control that reuses the durable parts of
`ListView`: scroll integration, fixed-height row virtualization, selection
ranges, keyboard/focus behavior, row activation, row states, and list drawing
affordances. Keep `ListView` as the simple single-column control; extract shared
row infrastructure only when the table implementation proves the boundary.

1. Establish the core table model:
   - add `TableView` as a scroll-backed data control
   - add `TableColumn` objects with stable identifiers, title text, width,
     minimum/maximum width, alignment, resize policy, style id/classes, and
     optional user info
   - provide column collection APIs: `addColumn`, `insertColumn`, `removeColumn`,
     `columnCount`, `columnAt`, lookup by identifier, and iteration
   - keep row selection as the first selection mode; defer cell and column
     selection until row tables are stable
2. Add NSTableView-like data source and delegate hooks:
   - `method numberOfRows(tableView: TableView): int`
   - `method viewForCell(tableView: TableView, row: int,
     column: TableColumn): View`
   - optional lightweight fallback hooks such as `textForCell`, `rowHeight`,
     `isRowEnabled`, `shouldSelectRow`, and `didActivateRow`
   - keep hooks selector-backed and explicit so callers can customize behavior
     without subclass-style inheritance requirements
   - strengthen the control/cell split as needed while adding table cells:
     centralize cell invalidation, value conversion, target/action storage,
     highlight/tracking behavior, and default cell construction instead of
     duplicating those paths in table-specific code
3. Reuse and generalize row virtualization:
   - virtualize rows first and render all visible columns for each visible row
   - keep reusable row/cell slots private until custom cell lifetime and reuse
     semantics are clear
   - support hosted views per visible cell, plus a cheaper text-cell path for
     common data browsers
   - preserve ListView's visible-row summaries and activation behavior where the
     concepts still apply
4. Implement table layout and headers:
   - compute column frames from ordered `TableColumn` widths
   - add a header band with column title rendering, hover/pressed state, focus
     handoff, and hit testing
   - support vertical scrolling in the first milestone; add horizontal scrolling
     once total column width can exceed the viewport
   - keep header, row, cell, and grid metrics in theme/appearance types
5. Add table affordances in AppKit order:
   - alternating row backgrounds, row hover/pressed states, separators, and grid
     lines using existing `WidgetState` and theme roles
   - column resizing with minimum/maximum constraints
   - sort request state and sort indicator rendering; let callers own the data
     ordering instead of sorting opaque data internally
   - column reordering after resizing and sorting are solid
6. Defer advanced table/outline behavior until the base is solid:
   - editable cells and commit/cancel flow
   - cell selection and column selection
   - drag reordering
   - tree disclosure rows and `OutlineView`
   - frozen columns, column groups, and very-wide column virtualization

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
  adding a table-style control.
- Whether generated layout summaries should expose richer diagnostics such as
  item names, attributes, priorities, conflicts, or cache-generation metadata.
- How much of the layout invalidation bus should be public. It is useful for
  diagnostics, but most callers should not need to emit layout signals directly.
