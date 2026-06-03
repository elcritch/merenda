# NimKit Current Plan

## Goal

Build and evolve Merenda's pure Nim UI layer at `src/merenda/nimkit` as the
project's primary UI toolkit.

The public API should stay Nim-native: plain value types for data, ref objects
for identity-bearing UI objects, selector-backed hooks where dynamic dispatch is
useful, and backend/runtime details kept behind NimKit boundaries.

## Current State

NimKit currently includes the core desktop-control slice:

- Core objects: `Application`, `Window`, `Responder`, `View`, `StackView`,
  `FormView`, `GridView`, `Control`, `Cell`/`ActionCell`, `Button`,
  checkbox/radio variants, `TextField`, and `ComboBox`.
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
  navigation, scrollable popup viewport behavior, and action dispatch on
  selection.
- Intrinsic sizing for the built-in control set: sizing value types,
  `intrinsicContentSize`, `sizeThatFits`, `sizeToFit`, cell measurement hooks,
  theme-backed minimum/chrome metrics, lazy parent layout invalidation, and
  content hugging/compression priority storage.
- A Cocoa-like constraint convenience layer over the core constraint model:
  typed x/y/dimension anchors, inset-backed content layout guides, and
  active-by-default edge-pinning helpers, inactive edge-constraint builders,
  property-style mutation for constants/priorities/activation, and short batch
  activation helpers.
- A Kiwiberry/Cassowary-backed constraint application pass that solves active
  constraints per view subtree, keeps the subtree root geometry fixed,
  preserves descendant geometry with edit-variable stays, keeps solver variables
  scoped to the collected subtree, applies intrinsic size for opted-in or
  constraint-participating views through hugging/compression priorities, and
  supports sibling constraints and soft-priority conflicts.
- Runnable NimKit examples:
  `examples/nimkit_hello.nim`,
  `examples/nimkit_button_demo.nim`,
  `examples/nimkit_button_counter.nim`,
  `examples/nimkit_checkbox_demo.nim`,
  `examples/nimkit_radio_demo.nim`,
  `examples/nimkit_textfield_demo.nim`,
  `examples/nimkit_combobox_demo.nim`,
  `examples/nimkit_combo_scroll_demo.nim`,
  `examples/nimkit_controls_showcase.nim`,
  `examples/nimkit_layout_showcase.nim`,
  `examples/nimkit_grid_preferences.nim`.
- Focused tests cover value types, views, layout containers, controls, text
  fields, combo boxes, responders, key bindings, rendering, screenshots, and
  native application pumping.

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
- `src/merenda/nimkit/viewconstraints.nim`:
  `LayoutConstraint` construction/storage/activation, Kiwiberry-backed
  constraint solving, typed layout anchors, content layout guides, and
  edge-pinning helper APIs.
- `src/merenda/nimkit/stackviews.nim`:
  `StackView`, arranged subviews, orientation, spacing, edge insets,
  cross-axis alignment, fill/fill-equally distribution, intrinsic stack
  measurement, and layout through the same view lifecycle hooks as other
  containers.
- `src/merenda/nimkit/formviews.nim`:
  `FormView`, label/field rows, max label-column measurement, field-column
  stretching, row/column spacing, edge insets, label and row alignment,
  minimum field width, intrinsic form measurement, and lifecycle-driven layout.
- `src/merenda/nimkit/gridviews.nim`:
  `GridView`, explicit row/column placement, row/column spacing, edge insets,
  directional cell alignment, spanning items, intrinsic grid measurement, and
  lifecycle-driven layout.
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
  source/delegate hooks, popup presentation preference, popup open policy,
  selected string/index syncing, and text selector compatibility.
- `src/merenda/nimkit/listviews.nim`:
  `ListViewport`, shared list/popup row helpers for visible-count clamping,
  first-row scrolling, popup bounds, row bounds, and row hit testing, plus a
  narrow callback-backed `PopupListView` for transient single-column popup
  drawing, row tracking, scrolling, highlighting, and activation.
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
- Add layout containers on the same core shapes. Stack/form/grid containers,
  intrinsic sizing, and Kiwiberry-backed solving now share the view lifecycle;
  generated autoresizing-mask constraints and fuller compatibility conveniences
  can be added as examples require them.

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
6. Done for the current core: Wire intrinsic invalidation into
   `setNeedsLayout` on parents and add tests that property changes update
   layout lazily rather than mutating frames unexpectedly. Continue broadening
   this once container layout exists.
7. Done for the current control set: Add tests that theme token/rule changes
   affecting metrics invalidate intrinsic size and cause measurement/rendering
   to agree on text and chrome rectangles. Coverage now checks style metric
   changes against intrinsic sizing, parent/container layout invalidation, and
   rendered FigDraw text/indicator rectangles for representative controls.
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
11. Done: Add layout item geometry hooks needed by constraints and containers:
   baseline offsets, alignment rects, frame/alignment conversion, layout
   attribute values, and invalidation when intrinsic size, hugging, compression
   resistance, frame, or hierarchy changes. Baseline/alignment behavior remains
   conservative by default until controls need richer text alignment.
   This completes the conservative layout-core stage: intrinsic content sizes,
   size-to-fit, layout invalidation, and a Cocoa-like constraint
   lifecycle/model are now in place before autoresizing masks, containers, or
   any solver work.
12. Done for the current core: Add autoresizing mask and
   `autoresizingMaskConstraints` semantics, matching Cocoa's translate flag
   without carrying the long API name into NimKit. The first pass stores the
   Cocoa bridge state and invalidates child/container constraints when the
   mask, translate flag, frame, bounds, or hierarchy changes. Generated
   autoresizing-mask constraints remain a future compatibility layer.
13. Done for the current solver core: Replace the deterministic constraint
   subset with Kiwiberry/Cassowary-backed solving after constraint updates and
   before layout hooks. The pass rebuilds a solver for the view subtree,
   keeps the subtree root geometry fixed, preserves descendant geometry with
   edit-variable stays, ignores constraints whose referenced items are outside
   that subtree, applies active `LayoutConstraint` values as required or soft
   solver constraints, maps intrinsic content size for opted-in or
   constraint-participating views into compression/hugging inequalities,
   supports sibling constraints, and honors stronger soft priorities.
14. Done for the first container layers: Add intrinsic-aware `StackView`,
   `FormView`, and `GridView` on top of the core. `StackView` supports
   arranged subviews, orientation, spacing, edge insets, cross-axis alignment,
   fill/fill-equally distribution, intrinsic measurement, priority-guided fill
   growth/shrink, hidden-view omission, and lazy invalidation. `FormView`
   supports label/field rows, max label-column measurement, stretching fields,
   row/column spacing, insets, label and row alignment, minimum field width,
   hidden row omission, and the same update/layout lifecycle. `GridView`
   supports explicit row/column placement, row/column spacing, insets,
   directional alignment, spanning items, hidden-view omission, intrinsic
   measurement, and solver-backed layout through the same view lifecycle.
15. Done for the current examples: Add `examples/nimkit_layout_showcase.nim`
   and `examples/nimkit_grid_preferences.nim` showing intrinsic-size-driven
   stack/form/grid layout and the current constraint APIs for common controls.
16. Done for the current API: Add modern constraint conveniences on top of the
   existing model: typed x/y/dimension anchors, inset-backed content layout
   guides, and `pinEdges` helpers. NimKit examples now use those helpers
   instead of spelling common root-edge constraints manually.
17. Done for Nim-style constraint API polish: Add `constraint.constant =`,
   `constraint.priority =`, `constraint.active =`, `constraint.active`,
   `activate`/`deactivate` aliases, and varargs batch helpers for
   `addConstraints`, `removeConstraints`, activation, and deactivation.
   `pinEdges` now activates the common edge-pin case directly, while
   `edgeConstraints` builds inactive constraints for callers that need delayed
   activation. Examples now use direct edge pins without a separate activation
   wrapper.
18. Done for scrollable combo/list popup infrastructure: Add shared
   `ListViewport` row-window state and list geometry helpers, wire combo boxes
   to scroll highlighted rows into view, support mouse-wheel popup scrolling
   for inline and window-backed popup paths, ignore popup border hit tests,
   draw only visible rows, add combo-box scroll tests, and add
   `examples/nimkit_combo_scroll_demo.nim` plus a long combo in the regular
   combo-box demo.
19. Done for popup/list ergonomics without inventing a full list widget:
   Add page/home/end key commands, keep hover and keyboard highlight behavior
   on the same row-window geometry while ignoring popup-border hover misses,
   draw a lightweight scroll indicator for popups with hidden rows, and keep
   tests at the combo-box/window level so inline and native popup presentations
   stay aligned.
20. Done for smaller popup-list extraction: Move transient single-column row
   drawing, native popup row event handling, inline row tracking helpers, scroll
   direction mapping, and activation/close callbacks into `PopupListView`.
   `ComboBox` now supplies item text, selected/highlighted indices, and popup
   policy through callbacks instead of owning a private popup view.
21. Done for minimal transient popup/session infrastructure: Add a narrow
   `Window`-owned transient session with owner responder, optional transient
   window, dismissal reason, callback, and focus restoration target. Combo-box
   popups now use that shared path for inline and window-backed outside-click,
   Escape, focus-change, native-done, and programmatic dismissal.
   It gives us a narrow base for full modal/tracking-loop behavior later
   without committing to a full AppKit-style modal system now.
22. Done for the current autoresizing-mask compatibility layer: Generate
   solver constraints for framed subviews with `autoresizingMaskConstraints`
   enabled and no explicit layout constraints. The pass stores reference
   geometry in `AutoresizingState`, translates flexible min margins and sizable
   dimensions into proportional parent-size equations, preserves the default fixed
   origin/size behavior, and lets explicit constraints take precedence.
   Richer source-compat behavior, especially unusual multi-flex combinations
   and bounds-origin edge cases, remains deferred until examples need it.
23. Done for the first layout input/invalidation bus pass: Add
   `docs/layout.md`, source-tagged `LayoutInput`/`LayoutEquation` shapes, a
   Sigils-backed `layoutInputChanged` signal bus for constraint/layout
   invalidation reasons, and generated input inspection for the current solve
   root. Autoresizing-mask and intrinsic-size solver inputs now flow through
   the common internal equation path, while authored constraints remain
   Cocoa-shaped `LayoutConstraint` values.
24. Done for the first autoresizing state cleanup: Split
   `AutoresizingState` dirty tracking into local reference refresh and generated
   input rebuild flags. Local frame/autoresizing changes refresh the stored
   reference geometry, while superview geometry changes dirty generated inputs
   without replacing the existing reference before solving. Solver and
   container frame application now share the same internal layout-frame helper.
25. Done for the first layout/API cleanup: Narrow the `merenda/nimkit` umbrella
   export so raw `LayoutInput`, `LayoutEquation`, `LayoutInputCache`, and
   `AutoresizingState` type names stay out of the normal public import while
   internal modules can still import focused implementation modules directly.
   Fully hiding `View.x*` fields remains a deeper refactor because those fields
   are exported on the public `View` object for cross-module internals today.
26. Done for internal frame-application cleanup: Replace boolean options on the
   internal layout-frame helper with `LayoutFrameOrigin`, naming authored frame
   edits, container layout, and solver application directly. Preserve the
   current rule that solver-applied geometry does not immediately regenerate
   layout inputs from half-applied output.
27. Done for the first debug API cleanup: Add stable generated-layout summary
   APIs, `generatedLayoutSummary` and `constraintsAffectingLayout`, before
   encouraging callers to inspect raw `LayoutInput` values. Keep `constraints()`
   authored only, and group generated autoresizing, intrinsic, and future
   container inputs by source for Cocoa-style debugging.
28. Done for the first signal-bus/cache step: Treat the Sigils-backed
   `layoutInputChanged` path as the core invalidation bus and make dirty
   sources drive per-source generated-input cache refresh where practical.
   The solver still rebuilds the full subtree for correctness, but generated
   autoresizing, intrinsic, and future container inputs are now cached in
   source buckets with per-source generations. First solve, user-constraint
   changes, and structural changes conservatively rebuild all generated
   buckets.
29. Done for optional Cocoa naming compatibility: Keep
   `autoresizingMaskConstraints` as the short Nim-facing API and add
   `translatesAutoresizingMaskIntoConstraints` as an AppKit comparison alias.
30. Next layout-cache refinement: Split broad `lirSubviews` usage into more
   precise descendant-geometry and hierarchy-structure reasons so ordinary
   child frame edits do not have to look like subtree structure changes. Keep
   the current conservative full generated-bucket rebuild for actual
   add/remove/visibility changes.

### Controls

- Add the next controls after intrinsic sizing is in place, so their default
  frame behavior, cell metrics, keyboard focus, and examples use the same
  measurement path from the start.
- Done for combo boxes and future list-like controls: add `ListViewport`,
  shared list-row geometry, and `PopupListView` for scrollable transient popup
  content rather than adding one-off popup logic per control.
- Keep future list-like controls on this base: start with shared viewport,
  row geometry, selection, and keyboard command behavior before adding a
  full `ListView` or table-style API.
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
- Done for the current popup/event pass: use an explicit transient popup session
  on `Window`, not extra combo-box-only state, for outside-click dismissal,
  Escape cancellation, auxiliary window closure, and focus restoration. Future
  menus, popovers, and drag sessions should reuse the same ordering.
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
- Stage layout work conservatively. Keep expanding constraints through the
  Cocoa-like lifecycle/model and Kiwiberry-backed solver, then add compatibility
  conveniences only when controls and examples prove the need.
- Build full modal/tracking loop behavior on top of the new transient session
  base before menus, popovers, or drag sessions depend on edge-case event
  ordering.
- Keep expanding command/key-binding behavior through the responder command path
  rather than adding raw key special cases in individual controls.

### Priority Order

- Short term: richer container behavior where examples need it, remaining
  autoresizing-mask compatibility details when examples justify them, and
  broader control coverage.
- Medium term: loadable/query-like themes, menu/popover implementations on top
  of the transient popup infrastructure, and broader resource organization.
- Later: full source-compatibility conveniences only when examples prove the
  need.

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
  `tests/tnimkit_stackviews.nim`,
  `tests/tnimkit_formviews.nim`,
  `tests/tnimkit_gridviews.nim`,
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
  `examples/nimkit_combo_scroll_demo.nim`,
  `examples/nimkit_controls_showcase.nim`,
  `examples/nimkit_layout_showcase.nim`,
  `examples/nimkit_grid_preferences.nim`.
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

- Full Auto Layout source compatibility. The near-term goal is the Cocoa-like
  lifecycle and public model, not source compatibility with AppKit or a port of
  GNUstep internals.
- Menus.
- Scroll views.
- Multiline or rich text editing.
- Drop-in source compatibility with another UI toolkit.
- Foreign runtime interop from NimKit's public API.
