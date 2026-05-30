# NimKit Current Plan

## Goal

Build and evolve Merenda's pure Nim UI layer at `src/merenda/nimkit` as the
project's primary UI toolkit.

The public API should stay Nim-native: plain value types for data, ref objects
for identity-bearing UI objects, selector-backed hooks where dynamic dispatch is
useful, and backend/runtime details kept behind NimKit boundaries.

## Current State

NimKit currently includes the core desktop-control slice:

- Core objects: `Application`, `Window`, `Responder`, `View`, `Control`,
  `Cell`/`ActionCell`, `Button`, checkbox/radio variants, `TextField`, and
  `ComboBox`.
- Plain Nim value types for geometry, events, key identifiers, modifiers,
  popup options, and control state. `chroma.Color` is used directly for color
  state.
- Selector-backed responder/action dispatch through `sigils/selectors`, with
  explicit selector hooks for event handling, drawing, layout, control actions,
  text editing commands, delegates, and data sources.
- A view system with frame/bounds geometry, hierarchy/lifecycle hooks,
  optional clipping, coordinate conversion, hit testing, dirty-rect
  invalidation, `needsLayout`, Cocoa-like constraint-update lifecycle hooks,
  display preparation/cleanup, style identity, and inherited appearance.
- A window event path with first responder tracking, automatic and manual
  key-view loops, tab/backtab traversal, mouse capture during drag/up tracking,
  hover/active/focus-visible state, repeated click counts, scroll bubbling, and
  view-local coordinate conversion for responder fallback.
- Runtime-switchable key binding profiles for macOS, Windows, Linux, and BSD.
  Bindings map text, typed keys, key codes, and shortcut modifiers to command
  selectors before raw `keyDown` dispatch.
- A theme system built around `Theme`, inherited `Appearance`, `StyleContext`,
  typed style keys, token stores, selector-like style rules, shadows, focus
  metrics, stdlib-style token and style assignment through
  `theme[tokenName] = value` and `theme[role, styleKey] = value`, and concrete
  resolved styles for the built-in controls.
- FigDraw rendering via `DrawContext`, per-widget `draw` selector methods,
  default and popup draw levels, text layout helpers, focus-ring helpers,
  style-resolved control drawing, and `buildRenders` entry points that do not
  require a native window.
- siwin-backed native windows, popup windows, configurable popup presentation
  (`ppAutomatic`, `ppWindow`, `ppInline`), native scale-aware input conversion,
  frame pumping, rendering, and test/diagnostic escape hatches for native
  handles.
- Controls with useful behavior: cell-backed buttons, release-outside
  cancellation, keyboard activation, toggle/mixed/check/radio state cycling,
  editable/selectable single-line text fields, and combo boxes with local items,
  data source/delegate hooks, inline or window-backed popups, keyboard
  navigation, and action dispatch on selection.
- Intrinsic sizing for the built-in control set: sizing value types,
  `intrinsicContentSize`, `sizeThatFits`, `sizeToFit`, cell measurement hooks,
  theme-backed minimum/chrome metrics, lazy parent layout invalidation, and
  content hugging/compression priority storage.
- Runnable NimKit examples:
  `examples/nimkit_hello.nim`,
  `examples/nimkit_button_demo.nim`,
  `examples/nimkit_button_counter.nim`,
  `examples/nimkit_checkbox_demo.nim`,
  `examples/nimkit_radio_demo.nim`,
  `examples/nimkit_textfield_demo.nim`,
  `examples/nimkit_combobox_demo.nim`,
  `examples/nimkit_controls_showcase.nim`.
- Focused tests cover value types, views, controls, text fields, combo boxes,
  responders, key bindings, rendering, screenshots, and native application
  pumping.

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
- Keep built-in widget drawing on the widget/cell side through `draw`
  selectors and `DrawContext`. Rendering traversal should stay generic rather
  than growing control-specific branches.
- Resolve visual metrics through `Appearance`/`StyleContext` and concrete style
  objects. Controls should not inspect token names or carry hardcoded style
  special cases when a generic style key can express the same thing.

## Module Layout

- `src/merenda/nimkit.nim`:
  Aggregating import for the public API.
- `src/merenda/nimkit/types.nim`:
  `Point`, `Size`, `Rect`, chroma-backed `Color`, key/modifier enums,
  button/control enums, popup presentation options, and mouse/scroll/key event
  value objects.
- `src/merenda/nimkit/selectors.nim`:
  Typed selector declarations, action/event argument objects, drawing hooks,
  mouse/scroll hooks, text input/editing command hooks, key-view commands,
  combo-box hooks, and layout hooks.
- `src/merenda/nimkit/responders.nim`:
  `Responder`, next-responder links, selector forwarding, first-responder hooks,
  and command fallback behavior.
- `src/merenda/nimkit/drawing.nim`:
  `DrawContext`, default/popup draw levels, FigDraw node insertion, text layout,
  local-to-window drawing geometry helpers, focus rings, shadows, and small
  control drawing helpers used by selector-backed custom drawing.
- `src/merenda/nimkit/keybindings.nim`:
  Plain `KeyStroke`, `KeyBinding`, and `KeyBindingTable` values for mapping
  key/modifier combinations to command selectors, platform-primary shortcut
  modifiers, and macOS/Windows/Linux/BSD default text-editing profiles.
- `src/merenda/nimkit/views.nim`:
  `View`, frame/bounds state, subviews, lifecycle hooks, hit testing,
  coordinate conversion, optional clipping, appearance/style identity,
  layout/display invalidation, key-view links, hover/active/focus state, and
  event dispatch into selector methods.
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
  selector hooks, first-responder editing state, and default text editing
  command handlers.
- `src/merenda/nimkit/comboboxes.nim`:
  `ComboBox`, local item storage through `ComboBoxCell`, selector-backed data
  source/delegate hooks, popup presentation preference, inline popup drawing,
  window-backed popup views, popup open/highlight/selection state, mouse
  tracking, keyboard navigation, and text selector compatibility.
- `src/merenda/nimkit/theme.nim`:
  `Theme`, `Appearance`, `StyleContext`, resolved button/text-field/combo-box
  style objects, typed style tokens, style overrides, `EdgeInsets`,
  `BoxShadow`, control-state colors, borders, corner radius, focus-ring
  metrics, indicator metrics, arrow metrics, and control text insets.
- `src/merenda/nimkit/rendering.nim`:
  Generic view traversal, display preparation/cleanup, per-widget draw selector
  dispatch, appearance propagation, and render-tree construction.
- `src/merenda/nimkit/backend.nim`:
  Internal host backend for siwin native windows, FigDraw renderer setup,
  native event translation, input coordinate conversion, native stepping, and
  presentation.
- `src/merenda/nimkit/windows.nim`:
  `Window` title/frame/content/first-responder state, visibility lifecycle,
  effective appearance propagation, key bindings, key-view loops, popup
  presentation, popup window creation, render flushing, hover/mouse tracking,
  scale-aware coordinate conversion, and NimKit event dispatch.
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
  title/check/radio content; text-field cells should measure text and editor
  affordances; combo-box cells should measure selected text plus arrow and
  popup/list requirements.
- Put chrome metrics in `Appearance`/theme, not hardcoded controls. Borders,
  focus rings, shadows, control insets, minimum sizes, indicator metrics,
  arrow metrics, and state/style-specific margins should be resolved through
  style tokens and concrete style objects before drawing or measuring.
- Add modern measurement procs on NimKit objects: `intrinsicContentSize`,
  `invalidateIntrinsicContentSize`, `sizeThatFits`, and `sizeToFit`. Plain
  `View` should default to no intrinsic metric; buttons/checks/radios/text
  fields/combo boxes should return useful content sizes.
- Keep `sizeThatFits(proposedSize)` distinct from `intrinsicContentSize`.
  Intrinsic size is the view's natural content size independent of parent
  layout where possible; fitting size may account for a proposed width/height,
  wrapping, popup constraints, or future layout-managed children.
- Invalidate intrinsic size when content or metrics change: title/text,
  indicator state, font, control size, style classes/id, appearance, cell
  replacement, editable/selectable decorations, and combo-box item sources.
- Feed intrinsic sizes into `needsLayout` rather than resizing immediately.
  `sizeToFit` is an explicit frame mutation convenience; ordinary property
  changes should invalidate size and layout, then the layout pass decides
  frames.
- Add content hugging and compression resistance as value-style layout
  priorities once intrinsic sizes exist. Start with practical desktop-control
  defaults: controls prefer stretching over clipping, checks/radios hug more
  strongly than text fields, and required priorities are avoided by default.
- Build the Cocoa-like layout core before adding higher-level containers.
  `deps/libs-gui`/GNUstep is a useful architecture reference here, but do not
  port its code. Use its layering as guidance: view lifecycle and constraint
  storage live on `View`; intrinsic size contributes priority-like constraints;
  autoresizing masks can translate into layout inputs; stack/grid containers sit
  above the same lifecycle.
- Add layout containers only after the core shapes exist. A first useful
  container layer can support manual `layoutSubviews`, `sizeToFit`, stack-like
  examples, and intrinsic-size-aware helper layout. Defer a full Auto Layout
  solver until the Cocoa-like public model and container examples prove the
  simpler path insufficient.

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
  minimum control sizes, content baseline offsets, popup row height,
  and any control-size-specific insets. Keep them as generic `StyleKey[T]`
  values so future query/CSS-style matching can override them by role, state,
  id, or class.
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

Concrete task order and status:

1. Done: Add sizing value types: an intrinsic no-metric sentinel, layout
   priorities, optional fitting constraints, and tests for default `View`
   sizing.
2. Done: Add cell measurement APIs: `cellSize`, `cellSizeForBounds` or
   Nim-style equivalents, plus theme-backed content/chrome metric helpers that
   consume resolved `ButtonStyle`, `ChoiceButtonStyle`, `TextFieldStyle`, and
   `ComboBoxStyle` values.
3. Done: Implement button/checkbox/radio intrinsic sizing from title,
   indicator, control insets, focus-ring allowance, and minimum control sizes.
4. Done: Implement text-field and combo-box intrinsic sizing from text metrics,
   text/editor insets, arrow/indicator metrics, and minimum control sizes.
5. Done: Add `Control.sizeThatFits`, `Control.intrinsicContentSize`,
   `sizeToFit`, and intrinsic-size invalidation from cell/style changes.
6. Mostly done: Wire intrinsic invalidation into `setNeedsLayout` on parents and
   add tests that property changes update layout lazily rather than mutating
   frames unexpectedly. Continue broadening this once container layout exists.
7. Partly done: Add tests that theme token/rule changes affecting metrics
   invalidate intrinsic size and cause measurement/rendering to agree on text
   and chrome rectangles. Current coverage checks style metric changes against
   text rects; broader render-tree agreement can be added with container tests.
8. Done: Compare the first NimKit sizing pass with local GNUstep
   `deps/libs-gui`. GNUstep's `NSControl.sizeToFit` delegates directly to cell
   natural size, plain `NSView` has no intrinsic metric, orientation-specific
   hugging/compression priorities are stored on the view, and
   `NSCell.cellSizeForBounds:` currently returns natural `cellSize`. NimKit now
   follows that default for built-in control cells instead of clamping to an
   undersized proposal before wrapping-specific measurement exists.
9. Done: Add the Cocoa-like constraint update lifecycle on `View`:
   `needsUpdateConstraints`, `setNeedsUpdateConstraints`, `updateConstraints`,
   and `updateConstraintsForSubtreeIfNeeded`. `layoutSubtreeIfNeeded` should run
   constraint updates before layout, matching the modern AppKit ordering without
   porting GNUstep code.
10. Done: Add constraint data shapes before solving: `LayoutAttribute`,
   `LayoutRelation`, `LayoutConstraint`, activation/deactivation, and per-view
   constraint storage. These are Nim-native shapes aligned with modern Cocoa,
   with activation only managing storage and invalidation for now. No solver or
   frame mutation is included yet.
11. Not started: Add layout item geometry hooks needed by constraints and
   containers: baseline offsets, alignment rects, and invalidation when
   intrinsic size, hugging, compression resistance, frame, or hierarchy changes.
   Stub baseline/alignment behavior conservatively until controls need richer
   text alignment.
12. Not started: Add autoresizing mask and
   `translatesAutoresizingMaskIntoConstraints` semantics. The first pass may
   apply masks directly or generate simple internal layout inputs; preserve the
   Cocoa shape while keeping the implementation small.
13. Not started: Add a small deterministic constraint application subset:
   width/height constants, edge pins to superview, centers, and intrinsic
   min/max behavior from hugging and compression resistance. Avoid a full
   Cassowary-style solver until real examples require it.
14. Not started: Add intrinsic-aware containers on top of that core, starting
   with `StackView` and then a simple grid/form layout. Containers should
   participate in the same update/layout/invalidation lifecycle instead of
   growing a parallel layout system.
15. Not started: Add examples showing `sizeToFit`, intrinsic-size-driven
   layout, stack layout, and the minimal constraint subset for common controls.

### Controls

- Add the next controls after intrinsic sizing is in place, so their default
  frame behavior, cell metrics, keyboard focus, and examples use the same
  measurement path from the start.
- Extend combo-box/list infrastructure with scrollable popup content and shared
  list-row behavior rather than adding one-off popup logic per control.
- Keep text editing scoped to single-line control behavior for now. Grow command
  selectors and key bindings before adding multiline editor features.
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

- Continue testing scaled input against rendering on macOS, X11, Wayland, and
  inline-windowless targets.
- Keep render construction unit-testable without a live native window.
- Keep native handles private behind `nativeWindowOrNil`/`rendererOrNil` style
  escape hatches for tests and diagnostics.

## Core Architecture Notes

### Improvements To Consider

- Add a formal backend boundary. Window creation, event polling, native window
  lookup, renderer ownership, and backend operations should sit behind a small
  NimKit backend interface so siwin-specific details stay out of `Application`
  and `Window`.
- Keep popup presentation policy on `Window`/control instances. Do not add
  global popup state; platforms without native popup windows should keep using
  the same inline FigDraw path.
- Add coordinate caching only after profiling shows the current uncached
  conversion helpers are a measurable cost. Keep frame/bounds/superview/clipping
  invalidation explicit if caching lands.
- Keep growing the theme/metrics drawing boundary. `Theme` and `Appearance`
  should centralize borders, shadows, focus rings, control metrics,
  popup/list metrics, and state-specific colors as those features are added.
- Keep strengthening the control/cell split. Centralize cell invalidation,
  value conversion, target/action storage, highlight/tracking behavior, and
  default cell construction so controls stay thin.
- Stage layout work conservatively. Finish intrinsic content sizes, size-to-fit,
  layout invalidation, and a Cocoa-like constraint lifecycle/model first; then
  build intrinsic-aware containers on that core. Defer a full constraint solver
  until the public layout shapes, controls, and examples justify it.
- Add modal/tracking loop infrastructure before menus, popovers, or drag
  sessions depend on edge-case event ordering.
- Keep expanding command/key-binding behavior through the responder command path
  rather than adding raw key special cases in individual controls.

### Priority Order

- Short term: Cocoa-like layout lifecycle, constraint data shapes, autoresizing
  mask semantics, cleaner cell invalidation/default-cell construction, and
  measurement tests that prove theme/rendering/layout agreement.
- Medium term: simple intrinsic-aware `StackView`/grid containers built on the
  layout core, scrollable list/popup infrastructure, and broader control
  coverage.
- Later: fuller constraint solving, loadable/query-like themes, menus/popovers,
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
  `tests/tnimkit_sizing.nim`,
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
- Inline and window-backed popup paths can diverge. Keep behavior tests at the
  combo-box/window level so both presentation modes follow the same selection,
  cancellation, and focus semantics.
- NimKit can drift from expected desktop UI behavior. Cover user-visible event,
  layout, and drawing semantics with tests as each area becomes more complete.

## Non-Goals For Now

- Full Auto Layout compatibility or a complete constraint solver. The near-term
  goal is the Cocoa-like lifecycle and public model, not source compatibility
  with AppKit or a port of GNUstep internals.
- Menus.
- Scroll views.
- Multiline or rich text editing.
- Drop-in source compatibility with another UI toolkit.
- Foreign runtime interop from NimKit's public API.
