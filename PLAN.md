# NimKit Current Plan

## Goal

Build and evolve a side-by-side pure Nim UI layer at `src/knutella/nimkit`
while keeping the existing ObjC/AppKit implementation intact as the behavioral
reference.

NimKit is not an ObjC compatibility layer. The public API should stay Nim-native
and AppKit-shaped, with ObjC/AppKit adapters deferred until the native layer has
proved the core model.

## Current State

NimKit already has the first useful vertical slice:

- `Application`, `Window`, `Responder`, `View`, `Control`, `Button`,
  checkbox/radio button variants, and `TextField`.
- Plain Nim value types for geometry, events, and control options, with
  `chroma.Color` used directly for color state.
- Responder/action and key-command dispatch through `sigils/selectors`.
- Cocoa/AppKit-shaped object boundaries: views own hierarchy, geometry,
  drawing, tracking, layout, and appearance directly; controls are the
  cell-backed branch; delegates/data sources are explicit selector hooks rather
  than generic forwarding targets.
- View hierarchy, lifecycle hooks, invalidation, hit testing, and basic
  first-responder dispatch.
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
- figdraw rendering for view backgrounds, selector-backed custom drawing, button
  rectangles, single-line text, and style-resolved button/text-field metrics.
- siwin native windows, modifier-aware mouse/scroll dispatch, key/text input
  dispatch, and framebuffer/UI-scale-aware mouse coordinate conversion.
- Runnable examples:
  `examples/nimkit_hello.nim`,
  `examples/nimkit_button_demo.nim`,
  `examples/nimkit_button_counter.nim`,
  `examples/nimkit_checkbox_demo.nim`,
  `examples/nimkit_radio_demo.nim`.
- Focused tests for values, views, controls, responders, rendering,
  screenshots, and native application pumping.

## Coding Style

- Keep geometry, event, and option data as plain Nim value types: `object`,
  enums, sets. Use established library value types where they are already the
  rendering/data interchange type, such as `chroma.Color` for color. Do not wrap
  NSRect-like data or scalar widget state in `ref object`, Objective-C wrappers,
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
- Keep ObjC runtime types out of NimKit's public surface: no `NSObject`, `ID`,
  `IDPtr`, `SEL`, `objc_msgSend`, retain/release helpers, or ObjC ivar/accessor
  macros.

## Module Layout

- `src/knutella/nimkit.nim`:
  Aggregating import for the public API.
- `src/knutella/nimkit/types.nim`:
  Geometry, colors, button/control enums, and mouse/scroll/key event value
  objects.
- `src/knutella/nimkit/selectors.nim`:
  Typed selector declarations, action/event argument objects, drawing hooks,
  mouse enter/exit hooks, scroll hooks, and layout hooks.
- `src/knutella/nimkit/responders.nim`:
  `Responder`, next-responder links, selector forwarding, first-responder hooks,
  and command fallback behavior.
- `src/knutella/nimkit/drawing.nim`:
  `DrawContext`, FigDraw node insertion, and local-to-window drawing geometry
  helpers used by selector-backed custom drawing.
- `src/knutella/nimkit/keybindings.nim`:
  Plain `KeyStroke`, `KeyBinding`, and `KeyBindingTable` values for mapping
  key/modifier combinations to command selectors, including platform-primary
  shortcut modifiers.
- `src/knutella/nimkit/views.nim`:
  `View`, frame/bounds state, subviews, lifecycle hooks, hit testing,
  appearance/style identity, layout/display invalidation, hover/active state,
  and event dispatch into selector methods.
- `src/knutella/nimkit/cells.nim`:
  `Cell` and `ActionCell`, control-view back references, enabled/highlighted
  state, button state cycling, and target/action storage used by controls.
- `src/knutella/nimkit/controls.nim`:
  `Control`, cell ownership, cell selector forwarding, enabled state,
  target/action, and closure-backed action targets.
- `src/knutella/nimkit/buttons.nim`:
  `Button`, title, state cycling, mixed-state support, checkbox/radio variants,
  highlight/tracking behavior, and keyboard activation.
- `src/knutella/nimkit/textfields.nim`:
  `TextField`, string value, alignment, text color, editable/selectable flags,
  delegate storage, and explicit text-field delegate selector hooks.
- `src/knutella/nimkit/theme.nim`:
  `Theme`, `Appearance`, `StyleContext`, resolved button/text-field style
  objects, typed style tokens, style overrides, `EdgeInsets`, control-state
  colors, borders, corner radius, focus-ring metrics, and button/text-field text
  insets.
- `src/knutella/nimkit/rendering.nim`:
  figdraw node creation, text layout helpers, theme-backed built-in control
  drawing, and render-tree construction.
- `src/knutella/nimkit/backend.nim`:
  Internal host backend for siwin native windows, FigDraw renderer setup,
  native event translation, input coordinate conversion, native stepping, and
  presentation.
- `src/knutella/nimkit/windows.nim`:
  `Window` title/frame/content/first-responder state, visibility lifecycle,
  effective appearance propagation, render flushing, hover/mouse tracking, and
  NimKit event dispatch.
- `src/knutella/nimkit/application.nim`:
  App singleton/lifetime, window list, app-level appearance, run loop helpers,
  and frame-limited test execution.

## Completed Milestones

### Foundations

- `import knutella/nimkit` compiles without exposing ObjC runtime types.
- Constructors exist for the core object and value types:
  `newApplication`, `newWindow`, `newView`, `newButton`, `newTextField`,
  `initPoint`, `initSize`, `initRect`, `initColor`.
- Core event/action selectors exist:
  `mouseDown`, `mouseUp`, `keyDown`, `performClick`, `sendAction`,
  `tryToPerform`, `doCommandBySelector`, `noResponderFor`,
  `validateUserInterfaceItem`.

### Basic Visible UI

- Native windows can be opened and pumped through `Application.run` and
  `runForFrames`.
- Views, selector-backed custom drawing, text fields, and buttons render through
  figdraw.
- Button clicks hit-test through the view hierarchy, dispatch mouse events
  through selectors, perform target/action, mutate state, invalidate, and redraw.
- Screenshot coverage captures the button demo before and after a synthetic
  click.

### View Geometry And Lifecycle

- Visible rects account for hidden ancestors, parent clipping, bounds origins,
  and child invalidation propagation.
- `addSubview`, `removeFromSuperview`, and `setContentView` route through
  selector-backed view lifecycle hooks:
  `viewWillMoveToSuperview`, `viewDidMoveToSuperview`,
  `viewWillMoveToWindow`, `viewDidMoveToWindow`, `didAddSubview`, and
  `willRemoveSubview`.
- Content views track window ownership through descendants, content roots use
  the window as next responder, and replacing content clears a first responder
  from the removed subtree.

### Responder And Event Core

- Responder chains forward selector dispatch through `sigils/selectors`.
- `Window` tracks first responder and dispatches key events to it before falling
  back to the content view.
- `KeyBindingTable` maps text/typed-key/key-code plus modifier combinations to
  command selectors. `Window` resolves key commands before raw `keyDown`,
  dispatches them through the same responder command path as
  `doCommandBySelector`, and falls through to raw key dispatch when the command
  is unhandled.
- Space key activation of buttons is now the default key binding for
  `performClick`, covered by responder tests.
- siwin mouse positions are converted from the native input coordinate extent to
  NimKit logical coordinates, including scaled-display cases.

### Controls

- `Control` supports enabled state and target/action.
- `Control` owns a `Cell`; target/action state is mirrored through
  `ActionCell`, and control property selectors can forward to the installed
  cell.
- `Button` supports momentary and toggle modes, mixed-state cycling, highlight,
  disabled rendering, mouse activation, key activation, Cocoa-style
  release-outside cancellation, and checkbox/radio variants.
- Checkbox buttons reuse button target/action and mixed-state cycling while
  rendering through choice-control theme metrics.
- Radio buttons reuse button target/action, select without toggling off, and
  clear sibling radio buttons in the same superview.
- `TextField` supports displayed string value, alignment, text color, editable,
  selectable state, delegate storage, and an explicit `textDidChange` delegate
  hook without treating the delegate as a generic forwarding target.

### Theme And Metrics

- `Theme` is a plain Nim value object with button/text-field colors, borders,
  corner radius, focus-ring metrics, checkbox/radio indicator metrics, and
  text/control insets.
- `Appearance` is the resolver boundary between theme tokens, control state,
  and concrete draw styles.
- `StyleContext` carries role and control-state facts that an appearance or
  future query-like style resolver can match without changing render code.
- `StyleTokenStore` provides named color/length/inset token lookup, parent
  fallback, nested token references, and typed accessors without adding CSS
  parsing.
- Generic `StyleKey[T]` and role-scoped `StylePatch` values let callers layer
  targeted appearance overrides onto the default theme before FigDraw sees
  concrete styles.
- Built-in button and text-field rendering resolves `ButtonStyle` and
  `TextFieldStyle` values before drawing, and checkbox/radio rendering resolves
  `ChoiceButtonStyle` before drawing. Render helpers consume concrete fills,
  strokes, corner radii, text colors, indicator metrics, and text rectangles
  instead of reaching through raw theme slots.
- `buildRenders(root, theme)` and `buildRenders(window, theme)` allow focused
  render-tree tests and callers to supply a theme without native-window setup.

### Appearance, State, Layout, And Display

- `Application`, `Window`, and `View` can carry local `Appearance` values.
  `effectiveAppearance` inherits from view parent, window, then app, with local
  view appearances overriding inherited values for the subtree.
- Appearance changes on app/window/view invalidate the affected content subtree.
- Views store stable `styleId` and `styleClasses`, and built-in rendering passes
  those through `StyleContext` for future query-like theme resolvers.
- Window mouse dispatch now drives `mouseEntered`/`mouseExited`, `isHovered`,
  and `isActive`; built-in control rendering feeds hover/active state into
  style resolution.
- Window dispatch computes repeated click counts for close successive mouse
  presses on the same target, preserves the count through mouse-up, and routes
  mouse/scroll events through a Cocoa-style responder fallback while converting
  event locations into each responder view's local coordinates.
- Views expose `needsLayout`, `setNeedsLayout`, `layoutSubtreeIfNeeded`,
  `prepareDisplaySubtree`, and `finishDisplaySubtree`. Rendering explicitly
  runs layout/display preparation before building FigDraw nodes and clears dirty
  state only after render construction succeeds.

## Next Work

### View Geometry And Rendering

- Keep whole-window FigDraw rebuilds until they become measurable; preserve
  dirty rect metadata and the explicit display traversal so a later backend can
  narrow rendering without changing view APIs.
- Add clipped dirty-rect rendering when the FigDraw/backend boundary has a
  concrete partial-present path.

### Responder/Event Coverage

- Grow the default key binding table as text editing commands, menu shortcuts,
  and richer key equivalents are added.

### Controls

- Add controls only after the current `Control`/`Button`/`TextField` contracts
  stay stable under more examples.
- Prioritize combo box and basic text editing next because existing AppKit
  examples can act as references. Checkbox/radio/toggle variants now have the
  first NimKit implementation.
- Keep delegate/custom policy hooks selector-based and explicit where they
  affect behavior. Use generic forwarding for control-to-cell delegation, not
  for arbitrary view or delegate dispatch.
- For future complex widgets, follow the AppKit split: cells for reusable
  control display/interaction state, delegates for policy decisions, data
  sources for externally owned data, and containment for scroll/window
  structure.

### Native Integration

- Continue testing scaled input against rendering on macOS, X11, and Wayland.
- Keep render construction unit-testable without a live native window.
- Keep native handles private behind `nativeWindowOrNil`/`rendererOrNil` style
  escape hatches for tests and diagnostics.

### Migration Layer

- Defer `NS*` aliases and compatibility adapters until the Nim-native API is
  stable.
- When migration starts, keep adapters thin: construction, event/action routing,
  and geometry conversion only.
- Keep the ObjC/AppKit implementation buildable and useful as the behavioral
  reference.

## Cocoa Core Architecture Notes

Architecture review source: `deps/libs-gui/Headers/AppKit` and
`deps/libs-gui/Source`, especially `NSApplication`, `NSWindow`, `NSView`,
`NSControl`, `NSCell`, `GSDisplayServer`, `GSTheme`, key bindings, and the auto
layout engine. Use GNUstep/libs-gui as architectural reference only. Do not copy
its implementation.

### Already Aligned

- Our ObjC/AppKit core already follows the main Cocoa split better than NimKit:
  `NSApplication` owns the event queue, `NSWindow` dispatches to hit-tested or
  first-responder views, `NSView` owns frame/bounds/hierarchy/invalidation, and
  `NSControl` delegates most persistent control state to `NSCell`.
- Our `NSView` has the right broad shape: frame, bounds, superview/subviews,
  window ownership, tracking areas, invalid rects, visible rects, transform
  state, and proc/method boundaries where behavior may need to be swizzled.
- NimKit should keep its simpler Nim-native model, but it should treat the
  ObjC/AppKit core as the behavioral reference for event order, coordinate
  conversion, invalidation, and control semantics.

### Improvements To Consider

- Add a formal display-server/backend boundary to the ObjC/AppKit core. GNUstep
  routes window creation, event polling, server/window lookup, and backend
  operations through `GSDisplayServer`; ours still mixes siwin stepping,
  renderer ownership, and AppKit object logic inside `NSApplication`/`NSWindow`.
  A small Nim `DisplayServer`/`AppKitBackend` layer would make siwin replaceable,
  improve headless tests, and keep native-window quirks out of Cocoa objects.
- Tighten the view display pipeline around dirty rects. GNUstep keeps the
  invariant that dirty children mark ancestors dirty, clips invalidation to
  visible rects, redirects drawing to an opaque ancestor, and clears dirty state
  only after display. Our core has the pieces, but the traversal should be made
  explicit and covered by tests before adding more complex views.
- Make coordinate caching and invalidation a first-class view subsystem.
  GNUstep recursively invalidates cached window/view transforms and visible
  rects on frame, bounds, superview, hidden-state, and flip changes. Our
  `markTransformsDirty` path should grow into the same clear lifecycle, with
  tests for nested conversion, flipped views, bounds origins, and reparenting.
- Keep growing the theme/metrics drawing boundary. GNUstep's `GSTheme`
  centralizes borders, focus rings, control metrics, tile/nine-patch drawing,
  menu/window chrome, and state-specific colors. NimKit now has a small value
  theme for button/text-field colors and metrics; defer loadable themes and
  richer chrome until more controls exist.
- Keep strengthening the `NSControl`/`NSCell` split. GNUstep uses default cell
  classes and cell-owned state heavily. Our core already has cells; next cleanup
  should centralize cell invalidation, value conversion, target/action storage,
  highlight/tracking behavior, and default cell construction so controls stay
  thin.
- Stage layout work conservatively. GNUstep has autoresizing masks plus an auto
  layout engine. For us, finish autoresizing masks, intrinsic content sizes, and
  layout invalidation first; defer a constraint solver until there are enough
  controls to justify it.
- Centralize the application/window event path. GNUstep separates event queue
  lookup, `NSApplication.sendEvent`, window dispatch, tracking loops, modal
  loops, and key equivalent handling. Our path works, but modal sessions,
  tracking loops, key equivalents, mouse capture, and closed/invisible-window
  filtering should be made explicit before more widgets depend on edge-case
  event ordering.
- Extend the command/key-binding layer as text editing grows. GNUstep has key
  binding tables and command actions; NimKit now has the command-table core, but
  text editing, menu key equivalents, and responder fallback will need more
  default bindings.

### Priority Order

- Short term: cleaner cell invalidation/default-cell construction, and more
  controls using the theme metrics.
- Medium term: constraint layout groundwork and broader control coverage.
- Later: constraint layout, panels/services integration, loadable themes, and
  broader GNUstep-style resource organization.

### NimKit Follow-Up Against GNUstep

Current comparison source:
`deps/libs-gui/Source/NSApplication.m`, `NSWindow.m`, `NSView.m`,
`NSControl.m`, `NSCell.m`, `GSDisplayServer.m`, and `GSTheme.m`.

NimKit is intentionally much smaller than AppKit, but the GNUstep architecture
still points to the next correctness boundaries:

- The first command/key-binding layer is in place. GNUstep routes key
  equivalents through the application/window path and text commands through key
  binding tables and responder selectors; NimKit now has the same core shape
  with a small table that maps text/typed-key/key-code plus modifier
  combinations to command selectors.

Recommended NimKit order:

- Next: continue expanding controls while keeping rendering routed through theme
  metrics, with combo box and basic text editing as the next candidates.

Concrete task list:

1. Continue expanding controls after the above contracts stabilize. Prioritize
   combo box and basic text editing. Keep policy hooks selector-based where
   behavior is overridable.

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
  `tests/tnimkit_controls.nim`,
  `tests/tnimkit_responder.nim`,
  `tests/tnimkit_application.nim`,
  `tests/tnimkit_screenshot.nim`.
- Compile NimKit examples when changing public API or widget behavior:
  `examples/nimkit_hello.nim`,
  `examples/nimkit_button_demo.nim`,
  `examples/nimkit_button_counter.nim`,
  `examples/nimkit_checkbox_demo.nim`,
  `examples/nimkit_radio_demo.nim`.
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
- NimKit can drift from AppKit behavior. For each ported area, name the current
  AppKit module used as the reference in implementation notes or tests.

## Non-Goals For Now

- Auto layout.
- Menus.
- Scroll views.
- Full text editing.
- Full AppKit `NS*` source compatibility.
- ObjC runtime interop from NimKit.
