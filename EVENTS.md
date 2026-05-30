# Event Handling Plan (Cocotron Model, FigDraw + Siwin Backend)

This document is a detailed implementation guide for bringing Merenda event behavior in line with Cocotron-style AppKit semantics while still using:

- Siwin as the native input source
- FigDraw as the renderer

It is based on Cocotron’s event flow in:

- `vendor/darling-cocotron/AppKit/NSDisplay.m`
- `vendor/darling-cocotron/AppKit/NSApplication.m`
- `vendor/darling-cocotron/AppKit/NSWindow.m`
- `vendor/darling-cocotron/AppKit/NSResponder.m`
- `vendor/darling-cocotron/AppKit/NSView.m`
- `vendor/darling-cocotron/AppKit/NSControl.m`
- `vendor/darling-cocotron/AppKit/NSCell.m`
- `vendor/darling-cocotron/AppKit/NSEvent.subproj/*`

## 1. Cocotron Event Pipeline (Reference Behavior)

## 1.1 Backend -> Display Queue

Cocotron backends translate OS events into `NSEvent` and enqueue them via `postEvent:atStart:` on `NSDisplay`.  
`NSDisplay.nextEventMatchingMask` drains this queue, running the run loop first, and returns a sentinel `NSAppKitSystem` event if no event is available.

Key points:

- event queue is centralized
- filtering is mask-based
- events can be requeued (`atStart:YES`)

## 1.2 Application Run Loop

`NSApplication.run` repeatedly:

1. fetches an event with `nextEventMatchingMask:untilDate:inMode:dequeue:`
2. calls `sendEvent:`
3. updates windows/termination state

`NSApplication.sendEvent:` pre-checks key equivalents on key-down when command/alt modifiers are present.  
Order is:

1. key window `performKeyEquivalent:`
2. main window `performKeyEquivalent:`
3. main menu `performKeyEquivalent:`

If not consumed, event is sent to `[event window]`.

## 1.3 Window Dispatch

`NSWindow.sendEvent:` semantics:

- mouse down: hit-test at current mouse location, send to hit view, store down location
- mouse up/dragged: dispatch to view hit at stored down location
- mouse moved/entered/exited/scroll: hit-test current location
- key/flags: send to first responder

This is a major behavior detail: mouse events are routed by hit-tested view, not by first responder.

## 1.4 Responder + Key Interpretation

`NSResponder`:

- forwards unhandled event methods to `nextResponder`
- `interpretKeyEvents:` maps key bindings to selectors via keyboard binding manager
- if no binding, falls back to `insertText:`
- `noResponderFor:` beeps on unhandled keyDown

## 1.5 Control/Cell Tracking

`NSControl.mouseDown:` and `NSCell.trackMouse:` run nested event loops using `nextEventMatchingMask`:

- highlight on down
- continue tracking through drag/up
- optional continuous action dispatch
- finalize on mouse-up in/outside cell rules

This depends on queue-driven `nextEventMatchingMask`.

## 1.6 Tracking Areas / Cursor

`NSWindow` maintains tracking area state, rebuilds invalidated tracking areas, and synthesizes:

- `mouseEntered:`
- `mouseExited:`
- `mouseMoved:`
- `cursorUpdate:`

based on mouse location transitions and tracking options.

## 2. Current Merenda State (Important Gaps)

Current implementation pieces:

- Siwin -> `NSEvent` conversion exists in `src/merenda/appkit/events.nim`
- direct callback dispatch exists in `src/merenda/appkit/rendering.nim`
- responder chain forwarding exists in `src/merenda/appkit/responders.nim`
- basic window dispatch exists in `src/merenda/appkit/windows.nim`

Main behavior gaps vs Cocotron:

- no central queued `nextEventMatchingMask` pipeline (`NSDisplay`-style)
- `NSApplication.sendEvent` sends to top visible window, not `event.window`
- `NSWindow.sendEvent` routes mouse events to first responder/content fallback, not hit-tested view semantics
- no `interpretKeyEvents`, `performKeyEquivalent`, or key-binding command path
- `NSControl.mouseDown` tracking loop is missing
- `NSCell.trackMouse` is simplified (single-step, no event loop)
- tracking area / cursor update logic in window is stubbed
- Siwin `onTextInput` is not integrated into AppKit keyboard text flow
- rendering currently includes manual button/combo mouse handling in backend callbacks

## 3. Target Architecture for Merenda

Goal: keep Siwin + FigDraw, but move to Cocotron-like event semantics.

### 3.1 Event Queue Layer

Implement a queue layer in AppKit runtime (either:
- new `src/merenda/appkit/display.nim` mirroring `NSDisplay`, or
- queue fields on `NSApplication`).

Required APIs:

- `postEvent(event, atStart)`
- `nextEventMatchingMask(mask, untilDate, inMode, dequeue)`
- `discardEventsMatchingMask(mask, beforeEvent)`
- `currentEvent`

Implementation notes:

- use FIFO queue with optional push-front
- add lock if callbacks and consumers can run on different threads
- store `currentEvent` thread-safely

### 3.2 Siwin -> NSEvent Ingestion

In `rendering.nim` event callbacks:

- convert Siwin event to `NSEvent`
- set `windowNumber` to the concrete window number/id
- `postEvent` to queue instead of direct `window.sendEvent`

Keep coordinate conversion (`rawInputToLogical`) as-is.

Event mapping requirements:

- `MouseButtonEvent`:
  - left/right down/up -> corresponding AppKit types
  - non-left/right -> add `NSOtherMouseDown` / `NSOtherMouseUp` support
- `MouseMoveEvent`:
  - moved/dragged based on pressed button set
- `ScrollEvent`:
  - map `deltaX` and `delta` to `deltaX/deltaY`
- `KeyEvent`:
  - modifiers-only keys -> `NSFlagsChanged`
  - others -> `NSKeyDown`/`NSKeyUp`
- `TextInputEvent`:
  - integrate for actual text insertion path

### 3.3 App Pump

Replace direct callback-dispatch model with pump-style dispatch:

1. collect events from queue
2. dispatch via `NSApplication.sendEvent`
3. render invalidated windows

Pseudo-flow:

```nim
while appRunning:
  pollNativeWindows()   # nativeWindow.step / platform pump
  while true:
    let e = app.nextEventMatchingMask(NSAnyEventMask, now, NSDefaultRunLoopMode, true)
    if e.isNil: break
    app.sendEvent(e)
  renderNeededWindows()
```

`NSWindow.nextEventMatchingMask` must delegate to app queue filtering and be usable inside tracking loops.

## 4. Dispatch Semantics To Implement

### 4.1 `NSApplication.sendEvent`

Behavior:

- for keyDown with command/alt, run key-equivalent path first
- if consumed, stop
- otherwise send to `event.window` (resolve by window number), not “last visible window”

Add `_performKeyEquivalent` order:

1. key window
2. main window
3. main menu (when implemented)

### 4.2 `NSWindow.sendEvent`

Implement Cocotron-like routing rules:

- on left/right down:
  - hit-test at current location
  - optionally update first responder
  - send down to hit view
  - store mouse-down location
- on up/drag:
  - route to view hit at stored down location
- on moved/entered/exited/scroll:
  - route to current hit view (fallback to window if nil)
- on key/keyUp/flags:
  - route to first responder

Do not route all events through first responder by default.

### 4.3 `NSResponder`

Add missing behaviors:

- `interpretKeyEvents(events)`
- `performKeyEquivalent(event)` default false
- `cursorUpdate(event)` forwarding
- `noResponderFor(keyDown:)` beep behavior (or equivalent)
- make `doCommandBySelector` check `self` first, then chain

### 4.4 `NSView`

Add/align defaults:

- `performKeyEquivalent` recursion through subviews
- `scrollWheel` default to enclosing scroll view behavior, else super
- `rightMouseDown` context menu popup (`menuForEvent`)

## 5. Keyboard/Text Strategy With Siwin

Siwin provides both:

- `onKey` (physical key state)
- `onTextInput` (composed text, IME-safe)

Recommended model:

- keep `onKey` for control/navigation/shortcuts and modifier state
- use `onTextInput` for text insertion semantics

Implementation approach:

1. For key down/up, create `NSEvent` with keyCode/modifiers and best-effort characters.
2. For text input, dispatch insertion path to first responder (`insertText:` or equivalent command path).
3. Ensure shortcuts (cmd/ctrl/alt combos) are handled before text insertion.

This avoids layout/IME breakage and mirrors Cocotron’s split between key interpretation and text insertion.

## 6. Control and Cell Tracking Work

### 6.1 `NSControl.mouseDown`

Implement loop like Cocotron:

- highlight cell
- call `cell.trackMouse(...)`
- toggle/set state
- send action on success
- clear highlight and redraw

### 6.2 `NSCell.trackMouse`

Replace simplified implementation with queue-driven loop:

- `startTrackingAt`
- loop on `nextEventMatchingMask(NSLeftMouseUpMask + NSLeftMouseDraggedMask)`
- `continueTracking`
- optional continuous action send
- `stopTracking` with proper `mouseIsUp`

This is required for correct drag-out/drag-in and press/hold behaviors.

## 7. Tracking Areas and Cursor Rects

Implement window-side tracking maintenance:

- invalidate + lazy rebuild of collected tracking areas
- evaluate area activation options (active app/key window/first responder/inVisibleRect)
- synthesize enter/exit/moved/cursor-update events
- call owner methods when supported

Use existing `NSTrackingArea` and `NSView` hooks as source of truth.

## 8. Event Constants and API Compatibility

Decide and execute one compatibility direction:

- Preferred: align event type numeric values and mask semantics with Cocotron/AppKit headers.

Current Merenda diverges in event enum values and uses `set[NSEventType]` masks.  
For Cocotron parity and future API compatibility, migrate to bitmask-style `NSEventMask` (integer flags), while keeping helper constructors to minimize breakage.

## 9. Migration Plan (Phased)

1. Queue foundation
- add queue APIs (`postEvent`, `nextEventMatchingMask`, `currentEvent`)
- wire from Siwin callbacks

2. Dispatch correctness
- fix `NSApplication.sendEvent` targeting
- implement Cocotron-like `NSWindow.sendEvent` routing

3. Keyboard command layer
- add `performKeyEquivalent`, `interpretKeyEvents`, command selectors
- integrate `onTextInput`

4. Control/cell tracking
- implement `NSControl.mouseDown` loop
- implement full `NSCell.trackMouse`

5. Tracking areas + cursor updates
- implement invalidate/reset/collect/evaluate flow

6. Cleanup backend hacks
- remove manual button/combobox event hacks from `rendering.nim` as controls become event-correct

7. Modal and requeue support
- add minimal modal session loop semantics and unprocessed event requeue

## 10. Testing Plan

Add/update tests in `tests/`:

- queue behavior:
  - ordering
  - mask filtering
  - `atStart` requeue
- app/window dispatch:
  - mouse down target vs first responder
  - mouse up/drag target pinned to down location
  - key to first responder
- key equivalents:
  - key window/main window/menu order
  - consumed vs unconsumed behavior
- responder:
  - `interpretKeyEvents` -> selector dispatch
  - insert-text fallback
- control/cell:
  - drag in/out tracking behavior
  - continuous action emission
- tracking areas:
  - entered/exited/moved/cursorUpdate synthesis
- text input:
  - Siwin `onTextInput` produces inserted text correctly

## 11. Practical Notes For This Repo

- Keep FigDraw rendering path unchanged initially; only move event ownership to queue/pump.
- Keep Siwin coordinate conversion logic (`rawInputToLogical`) as the canonical location transform.
- Preserve existing `events.nim` conversion helpers, but extend them with:
  - other-mouse support
  - text-input handling
  - window-number assignment from native windows
- Expect current responder/event tests (`tests/tappkit_responder.nim`, `tests/tevents.nim`) to require updates as semantics become Cocotron-compatible.
