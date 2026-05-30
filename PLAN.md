# NimKit Current Plan

## Goal

Build and evolve Merenda's pure Nim UI layer at `src/merenda/nimkit` as the
project's primary UI toolkit.

The public API should stay Nim-native: plain value types for data, ref objects
for identity-bearing UI objects, selector-backed hooks where dynamic dispatch is
useful, and backend/runtime details kept behind NimKit boundaries.

## Current State

NimKit currently includes:

- `Application`, `Window`, `Responder`, `View`, `Control`, `Button`,
  checkbox/radio button variants, `TextField`, and `ComboBox`.
- Plain Nim value types for geometry, events, and control options, with
  `chroma.Color` used directly for color state.
- Responder/action and key-command dispatch through `sigils/selectors`.
- Desktop UI object boundaries: views own hierarchy, geometry, drawing,
  tracking, layout, and appearance directly; controls are the cell-backed
  branch; delegates/data sources are explicit selector hooks rather than
  generic forwarding targets.
- View hierarchy, lifecycle hooks, optional clipping, dirty-rect invalidation,
  hit testing, and first-responder dispatch.
- Application/window/view appearance inheritance through `effectiveAppearance`,
  plus stable view `styleId`/`styleClasses` for future query-like theme
  matching.
- Mouse entered/exited tracking, hover/active view state, and a basic
  `needsLayout` lifecycle with selector-backed `layoutSubviews`/`layout` hooks.
- Mouse and scroll events carry modifier and timestamp metadata. Hit-tested
  mouse/scroll dispatch walks the responder chain with view-local coordinate
  conversion at each step, and repeated click counts stay scoped to the clicked
  target.
- Window key bindings map text/typed-key/key-code plus modifier combinations to
  command selectors, dispatch them through the responder chain before raw
  `keyDown`, and fall through cleanly when no responder handles the command.
  macOS/Windows/Linux/BSD profiles are switchable at runtime.
- Text fields are editable/selectable first-responder controls with selected
  ranges, insertion points, click focus, text insertion, select-all, arrow
  movement, shift-selection movement, and forward/backward deletion. Combo boxes
  provide local items, selector-backed data source/delegate hooks, inline or
  window-backed popups, popup tracking, keyboard navigation, and action dispatch
  on selection.
- Tab and backtab traverse automatic or manual key-view loops, and focus-visible
  rings are driven by keyboard focus rather than mouse focus.
- figdraw rendering for view backgrounds, per-widget selector-backed drawing,
  button rectangles, single-line text, text-field selection/caret affordances,
  combo-box popups, and style-resolved control metrics.
- siwin native windows, modifier-aware mouse/scroll dispatch, key/text input
  dispatch, and framebuffer/UI-scale-aware mouse coordinate conversion.
- Runnable examples:
  `examples/nimkit_hello.nim`,
  `examples/nimkit_button_demo.nim`,
  `examples/nimkit_button_counter.nim`,
  `examples/nimkit_checkbox_demo.nim`,
  `examples/nimkit_radio_demo.nim`,
  `examples/nimkit_textfield_demo.nim`,
  `examples/nimkit_combobox_demo.nim`,
  `examples/nimkit_controls_showcase.nim`.
- Focused tests for values, views, controls, responders, rendering,
  screenshots, and native application pumping.

## Coding Style

- Keep geometry, event, and option data as plain Nim value types: `object`,
  enums, sets. Use established library value types where they are already the
  rendering/data interchange type, such as `chroma.Color` for color. Do not wrap
  geometry-like data or scalar widget state in `ref object`, backend wrappers,
  or `Sigil`.
- Use `ref object` for identity-bearing GUI objects only: applications,
  windows, responders, views, controls, widgets, native handles, and
  target/action objects.
- Use plain backing fields for internal widget state such as frame, bounds,
  hidden, needs-display, title, enabled, highlighted, state, text, colors, and
  flags.
- Use `Sigil` only when a property is actually observed, bound, or participates
  in a reactive graph. Do not use it as default storage for ordinary widget
  fields.
- Keep proc-based getter/setter boundaries for properties that may need
  swizzling, overriding, validation, layout hooks, instrumentation, native
  updates, invalidation, or responder side effects.
- Do not add getter/setter pairs only for compatibility when direct Nim access
  is clearer and no future hook point is expected.
- Keep backend/runtime handles out of NimKit's public surface. Public NimKit
  APIs should expose Nim values and NimKit objects, not native-window,
  renderer, or foreign-runtime implementation details.

## Module Layout

- `src/merenda/nimkit.nim`:
  Aggregating import for the public API.
- `src/merenda/nimkit/types.nim`:
  Geometry, colors, button/control enums, and mouse/scroll/key event value
  objects.
- `src/merenda/nimkit/selectors.nim`:
  Typed selector declarations, action/event argument objects, drawing hooks,
  mouse enter/exit hooks, scroll hooks, text input/editing command hooks, and
  layout hooks.
- `src/merenda/nimkit/responders.nim`:
  `Responder`, next-responder links, selector forwarding, first-responder hooks,
  and command fallback behavior.
- `src/merenda/nimkit/drawing.nim`:
  `DrawContext`, FigDraw node insertion, and local-to-window drawing geometry
  helpers used by selector-backed custom drawing.
- `src/merenda/nimkit/keybindings.nim`:
  Plain `KeyStroke`, `KeyBinding`, and `KeyBindingTable` values for mapping
  key/modifier combinations to command selectors, including platform-primary
  shortcut modifiers and default text-editing command bindings.
- `src/merenda/nimkit/views.nim`:
  `View`, frame/bounds state, subviews, lifecycle hooks, hit testing,
  appearance/style identity, layout/display invalidation, hover/active state,
  and event dispatch into selector methods.
- `src/merenda/nimkit/cells.nim`:
  `Cell` and `ActionCell`, control-view back references, enabled/highlighted
  state, button state cycling, and target/action storage used by controls.
- `src/merenda/nimkit/controls.nim`:
  `Control`, cell ownership, cell selector forwarding, enabled state,
  target/action, and closure-backed action targets.
- `src/merenda/nimkit/buttons.nim`:
  `Button`, title, state cycling, mixed-state support, checkbox/radio variants,
  highlight/tracking behavior, and keyboard activation.
- `src/merenda/nimkit/textfields.nim`:
  `TextField`, string value, alignment, text color, editable/selectable flags,
  selected range/insertion state, delegate storage, explicit text-field delegate
  selector hooks, and default text editing command handlers.
- `src/merenda/nimkit/comboboxes.nim`:
  `ComboBox`, local item storage through `ComboBoxCell`, selector-backed data
  source/delegate hooks, popup open/highlight/selection state, mouse tracking,
  keyboard navigation, and text selector compatibility.
- `src/merenda/nimkit/theme.nim`:
  `Theme`, `Appearance`, `StyleContext`, resolved button/text-field/combo-box
  style objects, typed style tokens, style overrides, `EdgeInsets`,
  control-state colors, borders, corner radius, focus-ring metrics, and control
  text insets.
- `src/merenda/nimkit/rendering.nim`:
  figdraw node creation, text layout helpers, theme-backed built-in control
  drawing, combo-box popup rendering, and render-tree construction.
- `src/merenda/nimkit/backend.nim`:
  Internal host backend for siwin native windows, FigDraw renderer setup,
  native event translation, input coordinate conversion, native stepping, and
  presentation.
- `src/merenda/nimkit/windows.nim`:
  `Window` title/frame/content/first-responder state, visibility lifecycle,
  effective appearance propagation, render flushing, hover/mouse tracking, and
  NimKit event dispatch.
- `src/merenda/nimkit/application.nim`:
  App singleton/lifetime, window list, app-level appearance, run loop helpers,
  and frame-limited test execution.

## Next Work

### Intrinsic Sizing And Layout

Use the existing control/cell/theme split as the implementation basis, while
exposing a modern intrinsic measurement model where it fits NimKit:

- Keep controls thin and cell-driven. `Control.sizeToFit` should ask the
  installed cell for its measured size.
- Put content measurement in cells, not views. Button cells should measure
  title/image/check/radio content; text-field cells should measure text and
  editor affordances; combo-box cells should measure selected text plus arrow
  and popup/list requirements.
- Put chrome metrics in `Appearance`/theme, not hardcoded controls. Borders,
  focus rings, control insets, image-title gaps, minimum heights, and
  state/style-specific margins should be resolved through style tokens and
  concrete style objects before drawing or measuring.
- Add modern measurement procs on NimKit objects: `intrinsicContentSize`,
  `invalidateIntrinsicContentSize`, `sizeThatFits`, and `sizeToFit`. Plain
  `View` should default to no intrinsic metric; labels/buttons/checks/radios/
  text fields/combo boxes should return useful content sizes.
- Keep `sizeThatFits(proposedSize)` distinct from `intrinsicContentSize`.
  Intrinsic size is the view's natural content size independent of parent
  layout where possible; fitting size may account for a proposed width/height,
  wrapping, popup constraints, or future layout-managed children.
- Invalidate intrinsic size when content or metrics change: title/text, image or
  indicator state, font, control size, style classes/id, appearance, cell
  replacement, editable/selectable decorations, and combo-box item sources.
- Feed intrinsic sizes into `needsLayout` rather than resizing immediately.
  `sizeToFit` is an explicit frame mutation convenience; ordinary property
  changes should invalidate size and layout, then the layout pass decides
  frames.
- Add content hugging and compression resistance as value-style layout
  priorities once intrinsic sizes exist. Start with practical desktop-control
  defaults: controls prefer stretching over clipping, labels/checks/radios hug
  more strongly than text fields, and required priorities are avoided by
  default.
- Add autoresizing/layout containers before a constraint solver. A first useful
  layer can support manual `layoutSubviews`, `sizeToFit`, stack-like examples,
  and intrinsic-size-aware helper layout. Defer full Auto Layout constraints
  until controls and examples prove the simpler path insufficient.

How the current theme engine fits:

- Treat the existing theme engine as the single metrics resolver for both
  drawing and measurement. Do not add separate `ButtonTheme`,
  `TextFieldTheme`, or layout-only theme objects.
- The current shape already has the right resolver boundary: `Theme` owns
  tokens/rules, `Appearance` is the inherited resolver context, `StyleContext`
  carries role/state/id/classes, and concrete style values such as
  `ButtonStyle`, `ChoiceButtonStyle`, `TextFieldStyle`, and `ComboBoxStyle` are
  what render code consumes.
- Measurement should consume those same resolved style values. For example,
  button sizing should use `ButtonStyle.text.insets`,
  `ControlBoxStyle.borderWidth`, focus-ring metrics, and future button minimum
  metrics; choice controls should use `ChoiceButtonStyle.indicatorSize` and
  `indicatorSpacing`; combo boxes should use `ComboBoxStyle.arrowWidth` and text
  insets.
- Add missing metric tokens only when measurement needs them:
  minimum control width/height, image-title gap, content baseline offsets,
  popup row height, and any control-size-specific insets. Keep them as generic
  `StyleKey[T]` values so future query/CSS-style matching can override them by
  role, state, id, or class.
- Resolve style from the same `StyleContext` for layout and rendering. That
  keeps hover/active/focused/disabled/selected state changes from producing
  different measured and drawn geometry.
- Appearance, style id/class, token, and rule changes should invalidate display,
  intrinsic size, and parent layout for the affected subtree. The current
  `effectiveAppearance` inheritance already gives the right propagation point;
  sizing should hook into it rather than adding a second inheritance system.
- Shadows are primarily drawing overflow and should not change intrinsic size by
  default. Focus rings, borders, and intentional chrome overhangs can affect
  fitting size only through explicit metrics.
- Future CSS/query styling should be able to replace or extend the rule matcher
  without changing control measurement. Controls should ask for resolved styles,
  not inspect token names or hardcode class-specific layout constants.

Concrete task order:

1. Add sizing value types: an intrinsic no-metric sentinel, layout priorities,
   optional fitting constraints, and tests for default `View` sizing.
2. Add cell measurement APIs: `cellSize`, `cellSizeForBounds` or Nim-style
   equivalents, plus theme-backed content/chrome metric helpers that consume
   resolved `ButtonStyle`, `ChoiceButtonStyle`, `TextFieldStyle`, and
   `ComboBoxStyle` values.
3. Implement button/checkbox/radio intrinsic sizing from title, indicator,
   image-title gap, control insets, focus-ring allowance, and minimum control
   heights.
4. Implement text-field and combo-box intrinsic sizing from text metrics,
   text/editor insets, arrow/indicator metrics, and minimum control heights.
5. Add `Control.sizeThatFits`, `Control.intrinsicContentSize`, `sizeToFit`, and
   intrinsic-size invalidation from cell/style changes.
6. Wire intrinsic invalidation into `setNeedsLayout` on parents and add tests
   that property changes update layout lazily rather than mutating frames
   unexpectedly.
7. Add tests that theme token/rule changes affecting metrics invalidate
   intrinsic size and cause measurement/rendering to agree on text and chrome
   rectangles.
8. Add examples showing `sizeToFit` and intrinsic-size-driven layout for common
   controls, then broaden to simple stack/container layout if the API holds.

### Controls

- Add the next controls after intrinsic sizing is in place, so their default
  frame behavior, cell metrics, keyboard focus, and examples use the same
  measurement path from the start.
- Extend combo-box/list infrastructure with scrollable popup content and shared
  list-row behavior rather than adding one-off popup logic per control.
- Keep delegate/custom policy hooks selector-based and explicit where they
  affect behavior. Use generic forwarding for control-to-cell delegation, not
  for arbitrary view or delegate dispatch.
- For future complex widgets, keep the same split: cells for reusable control
  display/interaction state, delegates for policy decisions, data sources for
  externally owned data, and containment for scroll/window structure.

### Rendering And Events

- Keep whole-window FigDraw rebuilds until they become measurable; preserve
  dirty rect metadata and the explicit display traversal so a later backend can
  narrow rendering without changing view APIs.
- Add clipped dirty-rect rendering when the FigDraw/backend boundary has a
  concrete partial-present path.
- Grow the default key binding table only as new text editing commands, menu
  shortcuts, and richer key equivalents need it.

### Native Integration

- Continue testing scaled input against rendering on macOS, X11, and Wayland.
- Keep render construction unit-testable without a live native window.
- Keep native handles private behind `nativeWindowOrNil`/`rendererOrNil` style
  escape hatches for tests and diagnostics.

## Core Architecture Notes

### Improvements To Consider

- Add a formal backend boundary. Window creation, event polling, native window
  lookup, renderer ownership, and backend operations should sit behind a small
  NimKit backend interface so siwin-specific details stay out of `Application`
  and `Window`.
- Add coordinate caching only after profiling shows the current uncached
  conversion helpers are a measurable cost. Keep frame/bounds/superview/clipping
  invalidation explicit if caching lands.
- Keep growing the theme/metrics drawing boundary. `Theme` and `Appearance`
  should centralize borders, focus rings, control metrics, menu/window chrome,
  and state-specific colors as those features are added.
- Keep strengthening the control/cell split. Centralize cell invalidation,
  value conversion, target/action storage, highlight/tracking behavior, and
  default cell construction so controls stay thin.
- Stage layout work conservatively. Finish intrinsic content sizes,
  size-to-fit, layout invalidation, and simple intrinsic-aware containers first;
  defer a full constraint solver until there are enough controls and examples
  to justify it.
- Add modal/tracking loop infrastructure before menus, popovers, or drag
  sessions depend on edge-case event ordering.

### Priority Order

- Short term: intrinsic sizing, cleaner cell invalidation/default-cell
  construction, and more controls using theme metrics.
- Medium term: simple intrinsic-aware layout containers and broader control
  coverage.
- Later: constraint layout, richer popup/list infrastructure, loadable themes,
  and broader resource organization.

## Test Plan

- Run focused tests during development with:
  `nim c -r --nimcache:.nimcache/<name> tests/<file>.nim`.
- Keep separate `--nimcache` directories when running Nim compiles in parallel;
  the shared cache can corrupt generated C during concurrent builds.
- Existing focused tests:
  `tests/tnimkit_types.nim`,
  `tests/tnimkit_views.nim`,
  `tests/tnimkit_rendering.nim`,
  `tests/tnimkit_theme.nim`,
  `tests/tnimkit_keybindings.nim`,
  `tests/tnimkit_textfields.nim`,
  `tests/tnimkit_comboboxes.nim`,
  `tests/tnimkit_controls.nim`,
  `tests/tnimkit_responder.nim`,
  `tests/tnimkit_application.nim`,
  `tests/tnimkit_screenshot.nim`.
- Compile NimKit examples when changing public API or widget behavior:
  `examples/nimkit_hello.nim`,
  `examples/nimkit_button_demo.nim`,
  `examples/nimkit_button_counter.nim`,
  `examples/nimkit_checkbox_demo.nim`,
  `examples/nimkit_radio_demo.nim`,
  `examples/nimkit_textfield_demo.nim`,
  `examples/nimkit_combobox_demo.nim`,
  `examples/nimkit_controls_showcase.nim`.
- Run the full suite with `nim test` before considering a larger stage complete.

## Risks

- Overusing reactive storage can make simple state hard to reason about. Use
  plain backing fields unless observation/binding is part of the contract.
- Exposing direct fields for behavioral properties can remove future hook points.
  Keep proc boundaries where swizzling, validation, layout, instrumentation, or
  native synchronization may matter.
- Dynamic responder chains depend on explicit parent/child and window/content
  ownership; avoid hidden globals as ownership shortcuts.
- figdraw text layout and native window flushing are easy to couple. Keep render
  tree construction pure enough to test without siwin.
- NimKit can drift from expected desktop UI behavior. Cover user-visible event,
  layout, and drawing semantics with tests as each area becomes more complete.

## Non-Goals For Now

- Full Auto Layout compatibility or a constraint solver.
- Menus.
- Scroll views.
- Full text editing.
- Source compatibility with another UI toolkit.
- Foreign runtime interop from NimKit's public API.
