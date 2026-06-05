# NimKit Design

This document summarizes the architecture that is already in place for
Merenda's pure Nim UI layer. It keeps the completed work in a stable design
form, while `PLAN.md` tracks what still needs to be done.

For detailed layout input, invalidation, cache, and solver design, see
[`docs/layout.md`](layout.md).

## Design Goals

- Keep the public API Nim-native: value objects for data, `ref object` for
  identity-bearing UI objects, and proc/template convenience APIs where they
  make call sites clearer.
- Keep backend/runtime details private. Public NimKit APIs should expose Nim
  values and NimKit objects, not renderer, native-window, or foreign-runtime
  implementation details.
- Use selector-backed hooks where dynamic dispatch is useful: events, drawing,
  layout, actions, delegates, data sources, and responder commands.
- Keep ordinary widget state as plain fields behind mutation procs. Use `Sigil`
  as a signal bus or for genuinely observed state, not as default storage for
  frame, title, enabled, highlighted, text, or scalar control flags.
- Resolve visual metrics through `Theme`, inherited `Appearance`,
  `StyleContext`, typed style keys, tokens, and concrete style objects.
  Controls should consume resolved styles rather than inspect token names.

## Core Objects

NimKit currently covers the desktop-control foundation:

- `Application`, `Window`, `Responder`, and `View`
- `StackView`, `FormView`, and `GridView`
- `Control`, `Cell`, `ActionCell`, `Button`, checkbox/radio variants
- `TextField`, `ComboBox`, `PopupListView`, and `ListView`

Geometry, events, key identifiers, modifiers, popup options, control state, and
layout directions are plain Nim value types. `chroma.Color` is used directly
for color state because it is already the rendering/data interchange type.

Identity-bearing GUI objects are `ref object`s: applications, windows, views,
controls, widgets, responders, native handles, and target/action objects.

## Views And Responders

`View` owns the common geometry and lifecycle surface:

- frame/bounds geometry
- hierarchy and lifecycle hooks
- optional clipping
- coordinate conversion
- hit testing
- dirty-rect invalidation
- `needsLayout` and constraint-update lifecycle flags
- style identity and inherited appearance
- layout priorities, constraints, and generated layout state

`Responder` provides next-responder links, selector forwarding, first-responder
hooks, command fallback behavior, and key-view traversal support.

`Window` owns content, first-responder state, hover/active/focus-visible state,
key bindings, key-view loops, scale-aware coordinate conversion, mouse capture
during drag/up tracking, repeated click counts, scroll bubbling, popup
presentation, render flushing, and native window integration.

## Theme And Rendering

The theme system is the single source of drawing and measurement metrics:

- `Theme` stores typed style tokens and style rules.
- `Appearance` provides inherited theme resolution.
- `StyleContext` carries role, state, id, and classes.
- Concrete style values such as `ButtonStyle`, `ChoiceButtonStyle`,
  `TextFieldStyle`, `ComboBoxStyle`, `ListViewStyle`, and `ListItemStyle` are
  what rendering and measurement consume.

The default theme uses an Aqua-like control language with gradients, shadows,
focus rings, borders, corner radii, indicator metrics, arrow metrics, and
control text insets expressed through the common style system.

Rendering is FigDraw-based and selector-driven:

- `DrawContext` handles FigDraw node insertion, text layout, local-to-window
  geometry conversion, focus rings, shadows, and shared control drawing helpers.
- `rendering.nim` performs generic view traversal, display preparation/cleanup,
  appearance propagation, and per-widget draw selector dispatch.
- Built-in controls draw on the widget/cell side. Rendering traversal stays
  generic rather than growing control-specific branches.
- `buildRenders` keeps render construction testable without a live native
  window.

## Intrinsic Sizing

NimKit follows the Cocoa-style split where controls ask cells and resolved
style metrics for natural sizes:

- Plain `View` defaults to no intrinsic metric.
- `Control.sizeToFit` asks the installed cell for its measured size.
- Cell measurement owns control content sizing for button titles, checkbox and
  radio indicators, text-field text/editor chrome, and combo-box selected text
  plus arrow/list metrics.
- `intrinsicContentSize`, `invalidateIntrinsicContentSize`, `sizeThatFits`,
  and `sizeToFit` are distinct API concepts.
- Property changes invalidate intrinsic size and parent layout lazily; ordinary
  content changes do not resize frames immediately.
- Content hugging and compression resistance priorities are stored per axis and
  contribute to generated solver inputs when a view participates in layout.

Measurement and rendering use the same resolved style values so text/chrome
rectangles agree in tests and examples.

## Constraints And Layout

The layout core is Cocoa-like at the public edge and more direct internally:

- `View` has a constraint update lifecycle:
  `needsUpdateConstraints`, `setNeedsUpdateConstraints`, `updateConstraints`,
  and `updateConstraintsForSubtreeIfNeeded`.
- `LayoutConstraint` stores authored constraints as
  `first.attr relation second.attr * multiplier + constant`, with priority,
  active state, and owner storage.
- Typed anchors, content layout guides, edge-pinning helpers, property-style
  constraint mutation, and varargs activation/storage helpers sit on top of
  that model.
- Common edge-pinning helpers activate constraints by default. Inactive
  builders remain available for delayed activation.
- Kiwiberry/Cassowary solves active constraints per view subtree after
  constraint updates and before layout hooks.
- The solver keeps the subtree root fixed, preserves descendant geometry with
  edit-variable stays, scopes variables to the collected subtree, supports
  sibling constraints, and honors stronger soft priorities.
- Intrinsic sizes generate compression and hugging inequalities for opted-in
  or constraint-participating views.

Autoresizing masks are a compatibility path rather than normal authored
constraints. `AutoresizingState` stores reference geometry and separates local
reference refresh from generated input rebuilds, so superview geometry changes
can rebuild equations without replacing the stored reference too early.

Generated layout inputs are source-tagged, cached by source, and exposed
through summaries such as `generatedLayoutSummary` and
`constraintsAffectingLayout` rather than mixed into `view.constraints()`.

## Layout Invalidation

The layout invalidation bus is the core primitive for cache and lifecycle
dirtying:

- Setters emit `layoutInputChanged(view, reason)` when a mutation affects
  constraints, intrinsic size, generated inputs, or layout.
- The layout slot maps reasons to local dirty sources, aggregate dirty sources,
  lifecycle flags, and autoresizing state.
- The generated input cache can rebuild per-source buckets where practical.
- First solve, user-constraint changes, and structural changes still rebuild
  all generated buckets for correctness.

Display invalidation remains separate from layout-input invalidation.

## Containers

Simple containers stay native instead of forcing every layout through solver
constraints:

- `StackView` owns arranged subviews, orientation, spacing, edge insets,
  cross-axis alignment, fill/fill-equally distribution, intrinsic measurement,
  priority-guided growth/shrink, hidden-view omission, and lifecycle-driven
  layout.
- `FormView` owns label/field rows, max label-column measurement,
  field-column stretching, row/column spacing, edge insets, label/row
  alignment, minimum field width, hidden row omission, intrinsic measurement,
  and lifecycle-driven layout.
- `GridView` owns explicit row/column placement, row/column spacing, edge
  insets, directional cell alignment, spanning items, hidden-view omission,
  intrinsic measurement, and lifecycle-driven layout.

Containers can participate in external constraints through intrinsic size and
the same view lifecycle, but they do not need to express their internal
row/column allocation as public constraints.

## Controls And Widgets

Controls are kept thin and cell-driven:

- `Cell` and `ActionCell` store control-view back references, enabled and
  highlighted state, button state cycling, and target/action storage.
- `Control` owns cell installation, cell selector forwarding, enabled state,
  target/action, and closure-backed action targets.
- `Button` owns title, state cycling, mixed-state support, checkbox/radio
  variants, highlight/tracking behavior, keyboard activation, and release
  outside cancellation.
- `TextField` owns string value, alignment, text color, editable/selectable
  flags, selected range/insertion state, delegate hooks, first-responder
  editing state, and default text editing command handlers.
- `ComboBox` owns local item storage through `ComboBoxCell`,
  selector-backed data source/delegate hooks, popup presentation preference,
  popup open policy, selected string/index syncing, and text selector
  compatibility.

Popup and list behavior shares a narrow base:

- `ScrollView` owns a `ClipView`, optional axis scrollers, and a document view.
  Scrollers are real child views: they draw their track/knob, page on gutter
  clicks, and drag the knob by translating track position into content offset.
- Clip-view scroll position is represented by bounds origin. Core frame and
  layout-frame updates preserve existing bounds origins while updating bounds
  sizes, so scroll offsets survive normal layout passes.
- `ListViewport` stores visible-row window state and common row geometry.
- `PopupListView` handles transient single-column popup drawing, row tracking,
  scrolling, highlighting, activation, and close callbacks.
- `Window` owns a transient popup/session layer with owner responder,
  optional transient window, dismissal reason, callback, and focus restoration.
- `ListView` is the first narrow public list control. It supports local string
  items, selector-backed row count/value data sources, delegate notifications
  for selection, activation, visible-row drawing, row enabled policy, and row
  selectability policy, none/single/multiple/extended selection, Shift range
  extension, command/control discontiguous toggles, keyboard and mouse
  navigation, wheel scrolling, intrinsic sizing, target/action activation,
  dedicated `srListView` and `srListItem` theme roles, and shared
  `ListRowState` row rendering.
- `ListContentView` is the internal row document for standalone `ListView`.
  It stays non-focusable and manually tiled by the list, keeping selection and
  keyboard behavior on `ListView` while giving future scroll-hosted lists a
  concrete content-view boundary.
- Standalone `ListView` virtualizes fixed-height rows as private reusable row
  views under `ListContentView`. Row views hold plain `ListRowState` values,
  draw through the shared row renderer, do not participate in hit testing or
  focus, and are retargeted from the clip-view visible rect as scrolling or
  resizing changes the visible window.
- `listViewDrawRow` receives row-local drawing bounds plus `ListRowState`.
  Callers that want stock styling with small additions can call
  `drawListRow(listView, context, rect, row)` from inside the delegate hook.
- `listViewRowIsEnabled` feeds `ListRowState.enabled`, while
  `listViewShouldSelectRow` controls whether mouse, keyboard, and programmatic
  selection can include a row. Disabled rows are also treated as
  nonselectable.

The transient session layer is intentionally smaller than a full AppKit modal
system. It gives menus, popovers, combo boxes, and future drag/tracking flows a
common dismissal/focus base without committing to full modal behavior too early.

## Native Integration

NimKit uses siwin-backed native windows and FigDraw renderers internally:

- popup presentation can be automatic, native-window-backed, or inline
- input conversion is native-scale-aware
- run-loop helpers support frame-limited tests
- native handles and renderers remain behind diagnostics/test escape hatches

Public rendering tests can construct FigDraw render trees without opening a
native window, while application tests still cover native pumping.

## Module Guide

- `nimkit.nim`: public API aggregator.
- `types.nim`: geometry, colors, events, key/modifier enums, control enums,
  popup options, layout directions, and related value types.
- `selectors.nim`: typed selectors for actions, drawing, events, text editing,
  key-view commands, combo-box hooks, and layout hooks.
- `responders.nim`: responder chain and command fallback.
- `drawing.nim`: `DrawContext`, FigDraw insertion, text layout, geometry
  helpers, focus rings, shadows, and shared drawing helpers.
- `keybindings.nim`: platform key binding profiles and selector mappings.
- `viewbase.nim`, `viewgeometry.nim`, `viewprotos.nim`, `views.nim`: view
  storage, geometry helpers, lifecycle protocols, and view behavior.
- `viewconstraints.nim`: constraints, anchors, guides, solver integration,
  generated layout inputs, and layout debugging summaries.
- `stackviews.nim`, `formviews.nim`, `gridviews.nim`: native layout
  containers.
- `cells.nim`, `controls.nim`, `buttons.nim`, `textfields.nim`,
  `comboboxes.nim`, `listviews.nim`: controls, cells, popups, and list
  widgets.
- `theme.nim`: style keys, tokens, rules, appearances, resolved styles,
  insets, shadows, metrics, and default themes.
- `rendering.nim`: generic render traversal and render-tree construction.
- `backend.nim`, `windows.nim`, `application.nim`: native backend, window
  behavior, and application lifetime.

## Examples And Tests

Runnable examples cover hello/button demos, button counter, checkbox/radio,
text field, combo box, combo scroll, list view, controls showcase, layout
showcase, and grid preferences.

Focused tests cover value types, views, layout containers, controls, text
fields, combo boxes, list views, responders, key bindings, rendering,
screenshots, and native application pumping.
