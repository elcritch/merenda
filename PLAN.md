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

- `Application`, `Window`, `Responder`, `View`, `Control`, `Button`, and
  `TextField`.
- Plain Nim value types for geometry, colors, events, and control options.
- Responder/action dispatch through `sigils/selectors`.
- View hierarchy, invalidation, hit testing, and basic first-responder dispatch.
- figdraw rendering for view backgrounds, button rectangles, and single-line
  text.
- siwin native windows, mouse button dispatch, key/text input dispatch, and
  framebuffer/UI-scale-aware mouse coordinate conversion.
- Runnable examples:
  `examples/nimkit_hello.nim`,
  `examples/nimkit_button_demo.nim`,
  `examples/nimkit_button_counter.nim`.
- Focused tests for values, views, controls, responders, rendering,
  screenshots, and native application pumping.

## Coding Style

- Keep geometry, color, event, and option data as plain Nim value types:
  `object`, enums, sets. Do not wrap NSRect-like data or scalar widget state in
  `ref object`, Objective-C wrappers, or `Sigil`.
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
  Geometry, colors, button/control enums, and event value objects.
- `src/knutella/nimkit/selectors.nim`:
  Typed selector declarations and action/event argument objects.
- `src/knutella/nimkit/responders.nim`:
  `Responder`, next-responder links, selector forwarding, first-responder hooks,
  and command fallback behavior.
- `src/knutella/nimkit/views.nim`:
  `View`, frame/bounds state, subviews, hit testing, invalidation, and event
  dispatch into selector methods.
- `src/knutella/nimkit/controls.nim`:
  `Control`, enabled state, target/action, and closure-backed action targets.
- `src/knutella/nimkit/buttons.nim`:
  `Button`, title, state cycling, mixed-state support, highlight behavior, and
  keyboard activation.
- `src/knutella/nimkit/textfields.nim`:
  `TextField`, string value, alignment, text color, editable/selectable flags.
- `src/knutella/nimkit/rendering.nim`:
  figdraw node creation, text layout helpers, and render-tree construction.
- `src/knutella/nimkit/backend.nim`:
  Internal host backend for siwin native windows, FigDraw renderer setup,
  native event translation, input coordinate conversion, native stepping, and
  presentation.
- `src/knutella/nimkit/windows.nim`:
  `Window` title/frame/content/first-responder state, visibility lifecycle,
  render flushing, and NimKit event dispatch.
- `src/knutella/nimkit/application.nim`:
  App singleton/lifetime, window list, run loop helpers, and frame-limited test
  execution.

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
- Views, text fields, and buttons render through figdraw.
- Button clicks hit-test through the view hierarchy, dispatch mouse events
  through selectors, perform target/action, mutate state, invalidate, and redraw.
- Screenshot coverage captures the button demo before and after a synthetic
  click.

### Responder And Event Core

- Responder chains forward selector dispatch through `sigils/selectors`.
- `Window` tracks first responder and dispatches key events to it before falling
  back to the content view.
- Space key activation of buttons is covered by tests.
- siwin mouse positions are converted from the native input coordinate extent to
  NimKit logical coordinates, including scaled-display cases.

### Controls

- `Control` supports enabled state and target/action.
- `Button` supports momentary and toggle modes, mixed-state cycling, highlight,
  disabled rendering, mouse activation, and key activation.
- `TextField` supports displayed string value, alignment, text color, editable,
  and selectable state.

## Next Work

### View Geometry And Rendering

- Decide whether rendering should call selector-backed custom draw handlers or
  stay with type-specific render traversal for now.
- Keep whole-window redraw until it becomes a measurable problem; preserve dirty
  metadata so a later renderer can narrow the work without changing view APIs.

### Responder/Event Coverage

- Add scroll, entered/exited, and click-count handling.
- Add richer key command dispatch and unhandled-selector tests.
- Decide how much of AppKit's responder fallback model NimKit should mirror.

### Controls

- Add controls only after the current `Control`/`Button`/`TextField` contracts
  stay stable under more examples.
- Prioritize checkbox/radio/toggle variants, combo box, and basic text editing
  because existing AppKit examples can act as references.
- Keep delegate/custom policy hooks selector-based where they affect behavior.

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
- Fill in view lifecycle hooks where Cocoa behavior depends on them:
  `viewWillMoveToSuperview`, `viewWillMoveToWindow`, `viewDidMoveToSuperview`,
  `viewDidMoveToWindow`, `didAddSubview`, and removal hooks. These should remain
  methods, not direct field writes, because subclasses and future swizzles need
  stable interception points.
- Introduce a theme/metrics drawing boundary. GNUstep's `GSTheme` centralizes
  borders, focus rings, control metrics, tile/nine-patch drawing, menu/window
  chrome, and state-specific colors. Our drawing is still spread across controls
  and rendering helpers. Start with a small theme object for colors, borders,
  focus rings, control margins, and cell metrics; defer loadable themes.
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
- Add a command/key-binding layer before text editing grows. GNUstep has key
  binding tables and command actions; our text fields currently handle command
  selectors directly. A small command table would keep text editing, menu key
  equivalents, and responder fallback from diverging.

### Priority Order

- Short term: dirty-rect invariants, visible rects, and view lifecycle hooks.
- Medium term: theme/metrics object, cleaner cell invalidation/default-cell
  construction, and richer key command dispatch.
- Later: constraint layout, panels/services integration, loadable themes, and
  broader GNUstep-style resource organization.

### NimKit Follow-Up Against GNUstep

Current comparison source:
`deps/libs-gui/Source/NSApplication.m`, `NSWindow.m`, `NSView.m`,
`NSControl.m`, `NSCell.m`, `GSDisplayServer.m`, and `GSTheme.m`.

NimKit is intentionally much smaller than AppKit, but the GNUstep architecture
still points to the next correctness boundaries:

- Add selector-backed view lifecycle hooks. GNUstep calls will/did move hooks,
  resets cursor rects, marks subviews dirty, updates responder/window ownership,
  and calls `didAddSubview` when views are inserted. NimKit currently mutates
  `xSuperview`, `xSubviews`, and next responder directly. Add hook methods for
  `viewWillMoveToSuperview`, `viewDidMoveToSuperview`, `viewWillMoveToWindow`,
  `viewDidMoveToWindow`, and `didAddSubview`, then route add/remove/content-view
  changes through them.
- Keep the control model simple, but introduce a theme/metrics boundary before
  adding more widgets. GNUstep pushes borders, focus rings, control state colors,
  tile drawing, and cell metrics through `GSTheme`. NimKit should not copy the
  full theme system yet, but button/text-field rendering should ask a small
  theme object for colors, border widths, padding, focus-ring metrics, and text
  insets instead of baking them into render helpers.
- Add a command/key-binding layer before text editing grows. GNUstep routes key
  equivalents through the application/window path and text commands through key
  binding tables and responder selectors. NimKit currently has only `keyDown`
  dispatch plus space activation. Add a small command table mapping key/modifier
  combinations to command selectors so text editing, buttons, and future menus
  share one responder path.

Recommended NimKit order:

- First: invalid rects/visible rects and lifecycle hooks, with tests around
  reparenting, hidden views, and child invalidation.
- Second: theme/metrics and command/key-binding layers, then expand controls.

Concrete task list:

1. Add visible-rect and clipping behavior. Hidden ancestors should produce an
   empty visible rect; parent bounds should clip child visible rects; future
   scroll views should be able to narrow visible rects without special render
   hacks.
2. Add selector-backed view lifecycle hooks. Provide
   `viewWillMoveToSuperview`, `viewDidMoveToSuperview`,
   `viewWillMoveToWindow`, `viewDidMoveToWindow`, `didAddSubview`, and a remove
   hook. Route `addSubview`, `removeFromSuperview`, and `setContentView`
   through those hooks while keeping direct field mutation private.
3. Introduce a small theme/metrics object. Do not build a loadable theme system
   yet; start with colors, border widths, corner radius, focus-ring metrics,
   control padding, and text insets used by buttons and text fields. Rendering
   should ask the theme for these values instead of hard-coding them in
   widget/render helpers.
4. Add a command/key-binding layer before real text editing expands. Map
   key/modifier combinations to command selectors, then dispatch through the
   responder chain. This should share the same path for text editing commands,
   button key equivalents, and future menu shortcuts.
5. Expand controls after the above contracts stabilize. Prioritize checkbox,
    radio, toggle variants, combo box, and basic text editing. Keep policy
    hooks selector-based where behavior is overridable.

## Test Plan

- Run focused tests during development with:
  `nim c -r --nimcache:.nimcache/<name> tests/<file>.nim`.
- Keep separate `--nimcache` directories when running Nim compiles in parallel;
  the shared cache can corrupt generated C during concurrent builds.
- Existing focused tests:
  `tests/tnimkit_types.nim`,
  `tests/tnimkit_views.nim`,
  `tests/tnimkit_rendering.nim`,
  `tests/tnimkit_controls.nim`,
  `tests/tnimkit_responder.nim`,
  `tests/tnimkit_application.nim`,
  `tests/tnimkit_screenshot.nim`.
- Compile NimKit examples when changing public API or widget behavior:
  `examples/nimkit_hello.nim`,
  `examples/nimkit_button_demo.nim`,
  `examples/nimkit_button_counter.nim`.
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
