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
pure Nim panel/dialog views, document-controller infrastructure, AppKit-style
in-process pasteboard/dragging foundations, and a pure Nim accessibility
metadata and protocol core.

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

## Current Verification

- `atlas-run tests` passes locally on macOS with the current domain module
  layout.
- After removing standalone `ListView`, `atlas-run tests` passed `32/32` and
  `nim examples` compiled successfully.
- The latest table row/action and header polish was checked with
  `atlas-run tests tnimkit_tableviews tnimkit_rendering tnimkit_theme`;
  examples were compile checked with
  `atlas-run tests --compile-only 'examples/*.nim'`.
- The latest table drag/drop target integration was checked with
  `atlas-run tests tests/tnimkit_tableviews.nim`,
  `atlas-run tests tests/tnimkit_pasteboards_dragging.nim`, and a full
  `atlas-run tests` run passing `32/32`.
- The latest table persistence integration was checked with
  `atlas-run tests tests/tnimkit_tableviews.nim`,
  `atlas-run tests tests/tnimkit_documents.nim`,
  `atlas-run tests tests/tnimkit_application.nim`, and
  `atlas-run tests tests/tnimkit_outlineviews.nim`.
- The current box and pure Nim panel/dialog coverage lives in
  `tests/tnimkit_boxes.nim`, `tests/integration_application.nim`,
  `tests/tnimkit_documents.nim`, and `examples/panel_demo.nim`.
- The first `SplitView` pass was checked with
  `atlas-run tests tests/tnimkit_splitviews.nim tests/tnimkit_theme.nim tests/tnimkit_rendering.nim`,
  `atlas-run tests --compile-only examples/splitview_demo.nim`, and a full
  `atlas-run tests` run passing `35/35`.
- The new slider/progress/cascading widget coverage lives in
  `tests/tnimkit_controls.nim`, `tests/tnimkit_cascadingviews.nim`,
  `examples/progress_indicator_demo.nim`, `examples/cascading_demo.nim`,
  `examples/controls_showcase.nim`, and `examples/preferences_demo.nim`.
- The Stepper pass was checked with `atlas-run tests nimkit_controls.nim`,
  `nim c examples/stepper_demo.nim`, and
  `nim c examples/controls_showcase.nim`.
- The first animation core, interpolation/timing, scheduler/threading, and
  property animation surface passes are covered by
  `tests/tnimkit_animations.nim`; umbrella export and affected widget fallout
  were checked with
  `atlas-run tests nimkit_controls nimkit_splitviews nimkit_cascadingviews`.
- The completed animation transaction/examples pass was checked with
  `atlas-run tests tnimkit_animations`,
  `atlas-run tests --compile-only 'examples/*.nim'`, and a full
  `atlas-run tests` run passing `37/37`.
- The panel/dialog hardening pass was checked with
  `nim c examples/panel_demo.nim`, `nim r tests/integration_application.nim`,
  `atlas-run tests nimkit_documents.nim`,
  `atlas-run tests nimkit_animations.nim`, and a full `atlas-run tests` run
  passing `37/37`.
- GitHub Actions is currently blocked before runner startup by account billing
  or spending-limit state, not by a Nim build or test failure. Rerun CI after
  the GitHub account issue is cleared.

## Near-Term Work

### OpenStep Compatibility Widgets

With the first animation, pure Nim panel/dialog hardening, and Stepper passes
landed, add the next missing OpenStep/AppKit-style widgets in an order that
hardens shared control, cell, layout, responder, drawing, accessibility, and
animation behavior instead of producing isolated one-off controls.

Recommended implementation order:

1. `Matrix`
   - Add legacy `NSMatrix`-style cell grids for radio/check/button cells,
     selection modes, keyboard movement, and cell reuse.
   - Use this to further harden the control/cell split.
2. `ColorWell`
   - Add color swatch rendering, target/action on color changes, pasteboard
     color payload integration, and drag affordances.
   - Stage a full color panel separately after the color well proves the
     pasteboard, target/action, and modal accessory-view contracts.
3. CascadingView hardening
   - Keep the new Miller Column implementation aligned with table/scroll
     behavior as those primitives evolve: richer column keyboard movement,
     persisted selection paths, drag/drop between hierarchy levels, and optional
     custom row/detail rendering hooks.

### Accessibility Core

Keep accessibility backend-neutral and driven by the same state mutations that
update widgets, responder state, and rendering.

1. Route focus, selection, enabled-state, expanded/collapsed, and value-change
   notifications from the same mutation procs that already update rendering or
   responder state.
2. Add semantic traversal helpers:
   - ordered accessibility descendants
   - role/action validation helpers for tests and future backend bridges
   - accessibility element at point once inspection or native hit-testing needs
     a stable semantic hit-test contract
3. Add richer text accessibility hooks:
   - selected range, insertion point, and editable/selectable traits
   - basic line/character geometry only after text layout exposes stable offset
     and line metrics

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
