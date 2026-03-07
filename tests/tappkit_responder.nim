import std/unittest

import knutella/appkit
import knutella/objc
import siwin/window as siwin

var spyKeyDownCount = 0
var spyMouseDownCount = 0
var spyMouseDragCount = 0
var spyScrollCount = 0
var spyLastEventType = NSApplicationDefined
var spyLastMouseButton = siwin.MouseButton.left
var routeWindowOneId: IDPtr = nil
var routeWindowTwoId: IDPtr = nil
var routeWindowOneMouseDown = 0
var routeWindowTwoMouseDown = 0
var pinnedLeftId: IDPtr = nil
var pinnedRightId: IDPtr = nil
var pinnedLeftDown = 0
var pinnedRightDown = 0
var pinnedLeftDrag = 0
var pinnedRightDrag = 0
var pinnedLeftUp = 0
var pinnedRightUp = 0
var buttonClickCount = 0

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

  method mouseDragged*(self: EventSpyView, event: NSEvent) =
    inc spyMouseDragCount
    spyLastEventType = event.`type`()

  method scrollWheel*(self: EventSpyView, event: NSEvent) =
    inc spyScrollCount
    spyLastEventType = event.`type`()

objcImpl:
  type RouteSpyView = object of NSView

  method mouseDown*(self: RouteSpyView, event: NSEvent) =
    if self.value == routeWindowOneId:
      inc routeWindowOneMouseDown
    elif self.value == routeWindowTwoId:
      inc routeWindowTwoMouseDown

objcImpl:
  type PinnedSpyView = object of NSView

  method mouseDown*(self: PinnedSpyView, event: NSEvent) =
    if self.value == pinnedLeftId:
      inc pinnedLeftDown
    elif self.value == pinnedRightId:
      inc pinnedRightDown

  method mouseDragged*(self: PinnedSpyView, event: NSEvent) =
    if self.value == pinnedLeftId:
      inc pinnedLeftDrag
    elif self.value == pinnedRightId:
      inc pinnedRightDrag

  method mouseUp*(self: PinnedSpyView, event: NSEvent) =
    if self.value == pinnedLeftId:
      inc pinnedLeftUp
    elif self.value == pinnedRightId:
      inc pinnedRightUp

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

  test "application queue supports ordering filtering and requeue":
    var app = NSApplication.new()
    let keyEvent = keyEventFromSiwin(
      1,
      nsPoint(1, 1),
      siwin.KeyEvent(key: siwin.Key.a, pressed: true, repeated: false, generated: false),
    )
    let mouseEvent = mouseButtonEventFromSiwin(
      1,
      nsPoint(2, 2),
      siwin.MouseButtonEvent(
        button: siwin.MouseButton.left, pressed: true, generated: false
      ),
    )

    app.postEvent(keyEvent, false)
    app.postEvent(mouseEvent, true)

    let first =
      app.nextEventMatchingMask(NSAnyEventMask, 0.0, @ns"NSDefaultRunLoopMode", true)
    check(not first.isNil)
    check(first.`type`() == NSLeftMouseDown)

    let second =
      app.nextEventMatchingMask(NSKeyDownMask, 0.0, @ns"NSDefaultRunLoopMode", true)
    check(not second.isNil)
    check(second.`type`() == NSKeyDown)

    let none =
      app.nextEventMatchingMask(NSAnyEventMask, 0.0, @ns"NSDefaultRunLoopMode", true)
    check(none.isNil)

    app.value = nil

  test "application sendEvent targets event window number":
    routeWindowOneMouseDown = 0
    routeWindowTwoMouseDown = 0
    routeWindowOneId = nil
    routeWindowTwoId = nil

    var app = NSApplication.new()
    var windowOne = newWindow(0, 0, 100, 100, "One")
    var windowTwo = newWindow(0, 0, 100, 100, "Two")
    var rootOne = newView(0, 0, 100, 100)
    var rootTwo = newView(0, 0, 100, 100)
    var spyOne = RouteSpyView.new()
    var spyTwo = RouteSpyView.new()
    routeWindowOneId = spyOne.value
    routeWindowTwoId = spyTwo.value
    spyOne.setFrame(nsRect(0, 0, 100, 100))
    spyTwo.setFrame(nsRect(0, 0, 100, 100))
    rootOne.addSubview(spyOne)
    rootTwo.addSubview(spyTwo)
    windowOne.setContentView(rootOne)
    windowTwo.setContentView(rootTwo)
    app.addWindow(windowOne)
    app.addWindow(windowTwo)

    let event = mouseButtonEventFromSiwin(
      windowOne.windowNumber(),
      nsPoint(10, 10),
      siwin.MouseButtonEvent(
        button: siwin.MouseButton.left, pressed: true, generated: false
      ),
    )
    app.sendEvent(event)

    check(routeWindowOneMouseDown == 1)
    check(routeWindowTwoMouseDown == 0)

    spyTwo.value = nil
    spyOne.value = nil
    rootTwo.value = nil
    rootOne.value = nil
    windowTwo.value = nil
    windowOne.value = nil
    app.value = nil

  test "window sendEvent uses hit testing and pins drag/up to mouse-down target":
    spyKeyDownCount = 0
    spyMouseDownCount = 0
    spyMouseDragCount = 0
    spyScrollCount = 0
    spyLastEventType = NSApplicationDefined
    spyLastMouseButton = siwin.MouseButton.left

    var window = newWindow(0, 0, 240, 160, "Event Dispatch")
    var root = newView(0, 0, 240, 160)
    var spy = EventSpyView.new()
    spy.setFrame(nsRect(200, 120, 30, 30))
    pinnedLeftId = nil
    pinnedRightId = nil
    pinnedLeftDown = 0
    pinnedRightDown = 0
    pinnedLeftDrag = 0
    pinnedRightDrag = 0
    pinnedLeftUp = 0
    pinnedRightUp = 0

    var leftView = PinnedSpyView.new()
    var rightView = PinnedSpyView.new()
    leftView.setFrame(nsRect(0, 0, 120, 160))
    rightView.setFrame(nsRect(120, 0, 120, 160))
    pinnedLeftId = leftView.value
    pinnedRightId = rightView.value
    root.addSubview(leftView)
    root.addSubview(rightView)
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
    check(spyMouseDownCount == 0)
    check(pinnedLeftDown == 1)
    check(pinnedRightDown == 0)

    let dragEvent = mouseMoveEventFromSiwin(
      0,
      nsPoint(200, 12),
      siwin.MouseMoveEvent(kind: siwin.MouseMoveKind.moveWhileDragging),
      {},
      {siwin.MouseButton.left},
    )
    window.sendEvent(dragEvent)
    check(pinnedLeftDrag == 1)
    check(pinnedRightDrag == 0)

    let mouseUpEvent = mouseButtonEventFromSiwin(
      0,
      nsPoint(200, 12),
      siwin.MouseButtonEvent(
        button: siwin.MouseButton.left, pressed: false, generated: false
      ),
    )
    window.sendEvent(mouseUpEvent)
    check(pinnedLeftUp == 1)
    check(pinnedRightUp == 0)

    let scrollEvent = scrollEventFromSiwin(
      0, nsPoint(10, 12), siwin.ScrollEvent(delta: -1.0, deltaX: 0.25)
    )
    window.sendEvent(scrollEvent)
    check(spyScrollCount == 0)

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

    leftView.value = nil
    rightView.value = nil
    spy.value = nil
    root.value = nil
    window.value = nil

  test "control mouseDown tracking consumes queued mouse-up and triggers action":
    buttonClickCount = 0
    var app = NSApplication.new()
    var window = newWindow(0, 0, 220, 140, "Tracking")
    var root = newView(0, 0, 220, 140)
    var button = newButton(20, 20, 100, 32, "Queue Click")
    button.setOnClick(
      proc(sender: NSButton) =
        discard sender
        inc buttonClickCount
    )
    root.addSubview(button)
    window.setContentView(root)
    app.addWindow(window)

    let down = mouseButtonEventFromSiwin(
      window.windowNumber(),
      nsPoint(30, 30),
      siwin.MouseButtonEvent(
        button: siwin.MouseButton.left, pressed: true, generated: false
      ),
    )
    let up = mouseButtonEventFromSiwin(
      window.windowNumber(),
      nsPoint(30, 30),
      siwin.MouseButtonEvent(
        button: siwin.MouseButton.left, pressed: false, generated: false
      ),
    )

    app.postEvent(down, false)
    app.postEvent(up, false)
    let first =
      app.nextEventMatchingMask(NSAnyEventMask, 0.0, @ns"NSDefaultRunLoopMode", true)
    check(not first.isNil)
    app.sendEvent(first)

    check(buttonClickCount == 1)

    button.value = nil
    root.value = nil
    window.value = nil
    app.value = nil

  test "text input event inserts text into first responder":
    var window = newWindow(0, 0, 200, 80, "Text Input")
    var root = newView(0, 0, 200, 80)
    var field = newTextField(10, 10, 160, 24, "")
    root.addSubview(field)
    window.setContentView(root)
    check(window.makeFirstResponder(field))

    let textEvent = textInputEventFromSiwin(
      window.windowNumber(),
      nsPoint(12, 12),
      siwin.TextInputEvent(text: "abc", repeated: false),
    )
    window.sendEvent(textEvent)
    check(field.stringValue() == @ns"abc")

    field.value = nil
    root.value = nil
    window.value = nil

  test "application key equivalents trigger control action before normal dispatch":
    buttonClickCount = 0
    var app = NSApplication.new()
    var window = newWindow(0, 0, 240, 120, "Key Eq")
    var root = newView(0, 0, 240, 120)
    var button = newButton(20, 20, 140, 32, "Shortcut")
    button.setKeyEquivalent(@ns"k")
    button.setKeyEquivalentModifierMask(nsModifierFlagsMask({NSCommandKeyMask}).int)
    button.setOnClick(
      proc(sender: NSButton) =
        discard sender
        inc buttonClickCount
    )
    root.addSubview(button)
    window.setContentView(root)
    app.addWindow(window)

    let shortcut = newKeyEvent(
      NSKeyDown,
      nsPoint(30, 30),
      {NSCommandKeyMask},
      0.0,
      window.windowNumber().int,
      @ns"k",
      @ns"k",
      false,
      0'u16,
    )
    app.sendEvent(shortcut)
    check(buttonClickCount == 1)

    button.value = nil
    root.value = nil
    window.value = nil
    app.value = nil
