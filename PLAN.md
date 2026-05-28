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
- `src/knutella/nimkit/windows.nim`:
  `Window`, native siwin window ownership, event translation, render flushing,
  and input coordinate conversion.
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

- Add explicit coordinate conversion helpers between view, window, and screen
  spaces.
- Add clipping/visible-rect behavior and tests.
- Decide whether rendering should call selector-backed custom draw handlers or
  stay with type-specific render traversal for now.
- Add dirty-region tracking only after whole-window redraw becomes a measurable
  problem.

### Responder/Event Coverage

- Add mouse move, drag, scroll, entered/exited, and click-count handling.
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
