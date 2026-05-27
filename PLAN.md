# Pure Nim `nimkit` Staged Port

## Goal

Build a side-by-side pure Nim UI layer at `src/knutella/nimkit` while keeping the
current ObjC/AppKit implementation intact as the behavioral reference.

The first useful milestone is a runnable demo:

- one `Application`
- one `Window`
- one root `View`
- one `TextField`
- one `Button`
- a click path that hit-tests the button, sends a selector action, mutates
  sigil-backed label state, invalidates rendering, and redraws the updated text

This is not an ObjC compatibility layer. The first API should be Nim-native and
AppKit-shaped, with compatibility adapters deferred until the native layer works.

## Constraints

- Do not change the existing `knutella/appkit` modules during the first demo.
- Do not expose `NSObject`, `ID`, `IDPtr`, `SEL`, `objc_msgSend`, retain/release
  helpers, or ObjC ivar/accessor macros from `nimkit`.
- Use Atlas-managed dependencies and paths. Do not use Nimble for dependency
  installation or path discovery.
- Use `figdraw` for render construction and `siwin` for native window/input
  integration.
- Use `sigils/selectors` for responder/action dispatch:
  `DynamicAgent`, typed selectors, `perform`, `send`, `respondsTo`,
  `setNextResponder`, protocols, and reversible method wrapping.
- Use `Sigil[T]` only for state that must trigger rendering or behavior updates.
  Plain value fields are fine for stable configuration.

## Public API Shape

Use AppKit-like concepts without `NS*` names in the initial public surface.

- `Application`, `Window`, `Responder`, `View`, `Control`, `Button`, and
  `TextField` are `ref object` types because identity, parent/child graphs, and
  shared mutation are part of the UI contract.
- Geometry, color, and event payloads are plain value objects:
  `Point`, `Size`, `Rect`, `Color`, `MouseEvent`, `KeyEvent`.
- Constructors follow Nim conventions:
  `newApplication`, `newWindow`, `newView`, `newButton`, `newTextField`.
- Value helpers follow `initX` naming:
  `initPoint`, `initSize`, `initRect`, `initColor`.
- Keep one primary accessor style. Prefer ordinary procs such as `frame`,
  `setFrame`, `bounds`, `setNeedsDisplay`, `addSubview`, `removeFromSuperview`,
  `hitTest`, `sendAction`, and `performClick`.
- Selector-backed behavior should still have Nim-callable wrappers, so callers can
  use direct proc syntax for normal cases and dynamic dispatch for responder/action
  paths.

## Proposed Module Layout

- `src/knutella/nimkit.nim`
  Aggregating import for the public API.
- `src/knutella/nimkit/types.nim`
  Geometry, colors, button/control enums, and event value objects.
- `src/knutella/nimkit/selectors.nim`
  Public selector declarations and protocols for responder, drawing, control, and
  command behavior.
- `src/knutella/nimkit/responders.nim`
  `Responder`, next-responder links, selector forwarding, first-responder hooks,
  and command fallback behavior.
- `src/knutella/nimkit/views.nim`
  `View`, frame/bounds conversion, subviews, hit testing, invalidation, clipping,
  and recursive render traversal.
- `src/knutella/nimkit/windows.nim`
  `Window`, content view ownership, native siwin window, event translation, and
  render flushing.
- `src/knutella/nimkit/application.nim`
  App singleton/lifetime, window list, run loop helpers, and frame-limited test
  execution.
- `src/knutella/nimkit/controls.nim`
  `Control`, target/action, enabled state, value plumbing, and validation hooks.
- `src/knutella/nimkit/buttons.nim`
  `Button`, title, state cycling, highlight behavior, key equivalent later.
- `src/knutella/nimkit/textfields.nim`
  `TextField`, string value, alignment, enabled/editable/selectable flags.
- `src/knutella/nimkit/rendering.nim`
  figdraw node creation, text layout helpers, render-tree debug/test helpers.

## Stage 0: Foundations

Deliver enough static structure that later work does not invent APIs in tests.

- Add the module skeleton above and export it through `knutella/nimkit`.
- Define value types and constructors for geometry/color.
- Define core selectors and protocols:
  `draw`, `mouseDown`, `mouseUp`, `keyDown`, `performClick`, `sendAction`,
  `validateUserInterfaceItem`, `tryToPerform`, `doCommandBySelector`,
  `noResponderFor`.
- Add compile-only tests for imports, constructors, and selector declarations.

Acceptance:

- `import knutella/nimkit` compiles.
- Public constructors and selectors compile without pulling in ObjC runtime types.

## Stage 1: Basic Demo

Deliver the smallest visible and clickable UI.

- Implement `Application`, `Window`, `Responder`, `View`, `TextField`, and
  `Button`.
- Render view backgrounds, button rectangles, and single-line text through figdraw.
- Wire siwin mouse events to window coordinates, recursive `hitTest`, `mouseDown`,
  `mouseUp`, and `performClick`.
- Implement target/action using typed sigils selectors. Support at least a
  controller target and a closure-backed target object.
- Store label text, button title, highlighted state, enabled state, and
  `needsDisplay` as sigils.
- Add `examples/nimkit_button_demo.nim`.

Acceptance:

- The demo opens a window.
- Clicking the button changes the visible label text.
- The click path exercises selector dispatch rather than a direct callback only.
- `nim c examples/nimkit_button_demo.nim` succeeds.

## Stage 2: Responder And Event Core

Port the responder model before broadening controls.

- Implement next-responder routing equivalent to current `NSResponder`:
  `nextResponder`, `tryToPerform`, `doCommandBySelector`, and `noResponderFor`.
- Add first responder storage on `Window`.
- Add keyboard event translation for ordinary text and basic command selectors.
- Add key dispatch order:
  first responder, key window/content view, then no-responder fallback.
- Add tests for forwarding, unhandled selectors, first-responder changes, and
  action dispatch through a responder chain.

Acceptance:

- Required selector sends raise a clear unhandled-selector error when no responder
  handles them.
- Optional selector performs return an explicit handled/not-handled result.
- Keyboard command dispatch is testable without opening a native window.

## Stage 3: View, Geometry, And Rendering Parity

Port the stable view behavior from the ObjC AppKit implementation.

- Implement frame/bounds conversion, subview ordering, removal, hidden state,
  visible rect clipping, and invalidation propagation.
- Keep layout explicit. Do not add auto layout in this phase.
- Add recursive render traversal that calls selector-based draw handlers and
  returns figdraw `Renders`.
- Add render-tree tests modeled after the existing AppKit graphics tests:
  root exists, expected text nodes exist, button nodes exist, hidden views are not
  rendered, clipping behaves predictably.

Acceptance:

- Render construction can be tested without a live native window.
- Updating sigil-backed render state invalidates only the affected path or a
  clearly documented coarser region.

## Stage 4: Controls

Add the first reusable controls after responder and rendering behavior are stable.

- Implement `Control` with enabled state, target/action, value, alignment, and
  validation hooks.
- Implement `Button` state behavior comparable to the current port:
  momentary, toggle, mixed-state where practical, highlighted, and disabled.
- Implement `TextField` display behavior:
  string value, placeholder later if needed, alignment, enabled/editable flags.
- Use selector protocols for delegate/custom policy hooks. Do not require subclass
  inheritance for every customization path.

Acceptance:

- Button and text field behavior is covered by unit tests.
- A second example can reuse the controls without demo-specific shortcuts.

## Stage 5: Migration Layer

Add compatibility only after the Nim-native API has proved itself.

- Decide whether selected `NS*` aliases are useful or whether adapters are safer.
- Migrate one existing `knutella/appkit` example to `knutella/nimkit`.
- Keep adapters thin: translate construction, event/action routing, and common
  geometry types without exposing ObjC object ownership rules.

Acceptance:

- At least one existing example has a clean `nimkit` equivalent.
- The ObjC/AppKit implementation remains buildable and behaviorally useful as a
  reference.

## Test Plan

- Add `tests/tnimkit_types.nim` for value constructors and invariants.
- Add `tests/tnimkit_selectors.nim` for typed selector dispatch and protocol
  conformance.
- Add `tests/tnimkit_responder.nim` for forwarding, first responder behavior, and
  unhandled selectors.
- Add `tests/tnimkit_views.nim` for subview ordering, hit testing, hidden state,
  frame/bounds conversion, and invalidation.
- Add `tests/tnimkit_rendering.nim` for figdraw render-tree inspection.
- Add `tests/tnimkit_controls.nim` for button and text field behavior.
- Compile examples through the existing `nim test` task.
- Run focused tests during development with `nim c -r tests/<file>.nim`.
- Run the full suite with `nim test` before considering a stage complete.

## Decisions To Make Early

- Whether `nimkit` should reuse existing `NSPoint`/`NSRect` value types internally
  or introduce public `Point`/`Rect` and only convert at boundaries. Default:
  introduce public `Point`/`Rect` to avoid leaking AppKit naming into the native
  API.
- Whether render invalidation tracks exact dirty rects in stage 1 or starts with
  whole-window redraw. Default: whole-window redraw for the demo, then dirty rects
  in stage 3.
- Whether target/action accepts closures directly or wraps them in a target object.
  Default: expose target/action as the primary model and provide a closure-backed
  target helper for convenience.
- How much `sigils` state to expose. Default: keep sigils as an implementation
  detail unless callers need observation; expose ordinary accessors first.

## Risks

- `DynamicAgent` responder chains use weak next-responder links. Parent/child and
  window/content ownership must be explicit so views do not disappear during event
  dispatch.
- figdraw text layout and native window flushing are easy to couple. Keep render
  construction pure enough to unit test without siwin.
- A pure Nim API can accidentally drift from AppKit behavior. For each ported area,
  name the current AppKit module used as the reference in the implementation notes
  or test file.
- Overusing sigils can make simple state hard to reason about. Use them only where
  observation/invalidation is part of the contract.

## Non-Goals For The First Demo

- Auto layout.
- Menus.
- Scroll views.
- Text editing.
- Full AppKit `NS*` source compatibility.
- ObjC runtime interop from `nimkit`.
