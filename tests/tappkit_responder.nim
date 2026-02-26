import std/unittest

import nutella/appkit
import nutella/objc
import siwin/window as siwin

var spyKeyDownCount = 0
var spyMouseDownCount = 0
var spyScrollCount = 0
var spyLastEventType = NSApplicationDefined
var spyLastMouseButton = siwin.MouseButton.left

objcImpl:
  type EventSpyView = object of NSView

  method acceptsFirstResponder*(self: EventSpyView): bool =
    true

  method keyDown*(self: EventSpyView, event: NSEvent) =
    inc spyKeyDownCount
    spyLastEventType = event.`type`()

  method mouseDown*(self: EventSpyView, event: NSEvent) =
    inc spyMouseDownCount
    spyLastEventType = event.`type`()
    spyLastMouseButton = siwinMouseButton(event)

  method scrollWheel*(self: EventSpyView, event: NSEvent) =
    inc spyScrollCount
    spyLastEventType = event.`type`()

suite "appkit responder chain":
  test "nextResponder wiring follows view-window-application chain":
    var app = NSApp()
    var window = newWindow(10, 20, 240, 180, "Responder Tree")
    var root = newView(0, 0, 240, 180)
    var child = newView(10, 10, 80, 30)
    root.addSubview(child)
    window.setContentView(root)
    app.addWindow(window)

    check(child.nextResponder().value == root.value)
    check(root.nextResponder().value == window.value)
    check(window.nextResponder().value == app.value)

    child.removeFromSuperview()
    check(child.nextResponder().isNil)

    var replacement = newView(0, 0, 240, 180)
    window.setContentView(replacement)
    check(root.nextResponder().isNil)
    check(replacement.nextResponder().value == window.value)

    replacement.value = nil
    child.value = nil
    root.value = nil
    window.value = nil
    app.value = nil

  test "tryToPerform walks chain and dispatches one or zero arg selectors":
    var head = NSResponder.new()
    var middle = NSResponder.new()
    var window = newWindow(0, 0, 120, 80, "Dispatch")
    head.setNextResponder(middle)
    middle.setNextResponder(window)

    check(not window.isVisible())
    var sender = NSResponder.new()
    check(head.tryToPerform(selector("orderFront:"), sender))
    check(window.isVisible())
    check(head.tryToPerform(selector("isVisible"), sender))
    check(not head.tryToPerform(selector("selectorDoesNotExist:"), sender))

    head.doCommandBySelector(selector("orderOut:"))
    check(not window.isVisible())

    sender.value = nil
    window.value = nil
    middle.value = nil
    head.value = nil

  test "window makeFirstResponder honors acceptsFirstResponder rules":
    var window = newWindow(20, 30, 200, 120, "First Responder")
    var field = newTextField(0, 0, 100, 30, "Field")
    var button = newButton(0, 32, 100, 30, "Button")
    var plain = NSResponder.new()

    check(not window.makeFirstResponder(plain))
    check(window.firstResponder().isNil)

    check(window.makeFirstResponder(field))
    check(window.firstResponder().value == field.value)

    button.setEnabled(false)
    check(not window.makeFirstResponder(button))
    check(window.firstResponder().value == field.value)

    button.setEnabled(true)
    button.setRefusesFirstResponder(true)
    check(not window.makeFirstResponder(button))
    check(window.firstResponder().value == field.value)

    button.setRefusesFirstResponder(false)
    check(window.makeFirstResponder(button))
    check(window.firstResponder().value == button.value)

    plain.value = nil
    button.value = nil
    field.value = nil
    window.value = nil

  test "window sendEvent dispatches NSEvent through responder chain":
    spyKeyDownCount = 0
    spyMouseDownCount = 0
    spyScrollCount = 0
    spyLastEventType = NSApplicationDefined
    spyLastMouseButton = siwin.MouseButton.left

    var window = newWindow(0, 0, 240, 160, "Event Dispatch")
    var root = newView(0, 0, 240, 160)
    var spy = EventSpyView.new()
    spy.setFrame(0.cfloat, 0.cfloat, 240.cfloat, 160.cfloat)
    root.addSubview(spy)
    window.setContentView(root)
    check(window.makeFirstResponder(spy))

    let keyEvent = keyEventFromSiwin(
      0,
      nsPoint(10, 12),
      siwin.KeyEvent(key: siwin.Key.a, pressed: true, repeated: false, generated: false),
    )
    window.sendEvent(keyEvent)
    check(spyKeyDownCount == 1)
    check(spyLastEventType == NSKeyDown)

    let mouseEvent = mouseButtonEventFromSiwin(
      0,
      nsPoint(10, 12),
      siwin.MouseButtonEvent(
        button: siwin.MouseButton.left, pressed: true, generated: false
      ),
    )
    window.sendEvent(mouseEvent)
    check(spyMouseDownCount == 1)
    check(spyLastEventType == NSLeftMouseDown)
    check(spyLastMouseButton == siwin.MouseButton.left)

    let scrollEvent = scrollEventFromSiwin(
      0, nsPoint(10, 12), siwin.ScrollEvent(delta: -1.0, deltaX: 0.25)
    )
    window.sendEvent(scrollEvent)
    check(spyScrollCount == 1)
    check(spyLastEventType == NSScrollWheel)

    check(window.makeFirstResponder(NSResponder(value: nil)))
    let escapeEvent = keyEventFromSiwin(
      0,
      nsPoint(0, 0),
      siwin.KeyEvent(
        key: siwin.Key.escape, pressed: true, repeated: false, generated: false
      ),
    )
    window.sendEvent(escapeEvent)
    check(window.windowClosed())

    spy.value = nil
    root.value = nil
    window.value = nil
