import std/unittest

import siwin/window as siwin

import knutella/appkit
import knutella/objc

suite "appkit NSEvent":
  test "event masks and constants match header values":
    check(NSKeyDown.ord == 10)
    check(NSAppKitDefined.ord == 20)
    check(NSEventMaskFromType(NSKeyDown) == NSKeyDownMask)
    check(NSEventMaskFromType(NSScrollWheel) == NSScrollWheelMask)
    check(NSLeftMouseDown in NSAnyEventMask)
    check(NSAppKitDefined in NSAnyEventMask)
    check(NSOtherMouseDown in NSAnyEventMask)
    check(NSOtherMouseUp in NSAnyEventMask)
    check(NSOtherMouseDragged in NSAnyEventMask)
    check(
      NSDeviceIndependentModifierFlagsMask == {NSAlphaShiftKeyMask .. NSFunctionKeyMask}
    )
    check(NSF1FunctionKey.ord == 0xF704)
    check(NSModeSwitchFunctionKey.ord == 0xF747)

  test "key and other event factories round-trip payload values":
    let keyFlags = {NSShiftKeyMask, NSCommandKeyMask}
    var keyEvent = newKeyEvent(
      NSKeyDown, nsPoint(12, 18), keyFlags, 42.5, 77, @ns"a", @ns"A", false, 12'u16
    )
    check(keyEvent.`type`() == NSKeyDown)
    check(keyEvent.locationInWindow() == nsPoint(12, 18))
    check(keyEvent.modifierFlags() == keyFlags)
    check(keyEvent.windowNumber() == 77)
    check(keyEvent.characters() == @ns"a")
    check(keyEvent.charactersIgnoringModifiers() == @ns"A")
    check(keyEvent.keyCode() == 12'u16)
    check(keyEvent.isKindOfClass(NSEvent_keyboard))

    var otherEvent = newOtherEvent(
      NSApplicationDefined,
      nsPoint(1, 2),
      {NSControlKeyMask},
      21.0,
      5,
      9.cshort,
      100,
      200,
    )
    check(otherEvent.subtype() == 9)
    check(otherEvent.data1() == 100)
    check(otherEvent.data2() == 200)
    check(otherEvent.isKindOfClass(NSEvent_other))

    keyEvent.value = nil
    otherEvent.value = nil

  test "subclass interfaces are wired for mouse, periodic, and coregraphics":
    var mouseEvent =
      newMouseEvent(NSLeftMouseDown, nsPoint(7, 11), {NSShiftKeyMask}, 11.0, 2, 3)
    check(mouseEvent.isKindOfClass(NSEvent_mouse))
    let mouseEventTyped = mouseEvent as NSEvent_mouse
    check(mouseEventTyped.serialNumber() == 0)
    mouseEventTyped.setSerialNumber(99)
    check(mouseEventTyped.serialNumber() == 99)

    var periodic = newPeriodicEvent()
    check(periodic.isKindOfClass(NSEvent_periodic))
    check(periodic.`type`() == NSPeriodic)

    var display = newDisplayEvent(cast[pointer](0x1234'u))
    check(display.isKindOfClass(NSEvent_CoreGraphics))
    check(display.`type`() == NSPlatformSpecificDisplayEvent)
    check(display.coreGraphicsEvent() == cast[pointer](0x1234'u))

    mouseEvent.value = nil
    periodic.value = nil
    display.value = nil

  test "subtype and tracking methods raise when event lacks payload":
    var e = NSEvent.new()
    expect(ValueError):
      discard e.subtype()
    expect(ValueError):
      discard e.data1()
    expect(ValueError):
      discard e.trackingNumber()
    expect(ValueError):
      discard e.userData()
    e.value = nil

  test "periodic state toggles and rejects duplicate start":
    NSEvent.stopPeriodicEvents()
    check(not periodicEventsEnabled())
    NSEvent.startPeriodicEventsAfterDelay(0.25, 0.5)
    check(periodicEventsEnabled())
    check(periodicEventsDelay() == 0.25)
    check(periodicEventsPeriod() == 0.5)

    expect(ValueError):
      NSEvent.startPeriodicEventsAfterDelay(0.1, 0.2)

    NSEvent.stopPeriodicEvents()
    check(not periodicEventsEnabled())

  test "siwin core types map into NSEvent data":
    let keyInput = siwin.KeyEvent(
      key: siwin.Key.a,
      pressed: true,
      repeated: true,
      generated: false,
      modifiers: {siwin.ModifierKey.shift, siwin.ModifierKey.control},
    )
    var fromKey = keyEventFromSiwin(4, nsPoint(3, 4), keyInput, @ns"A", @ns"a")
    check(fromKey.`type`() == NSKeyDown)
    check(fromKey.modifierFlags() == {NSShiftKeyMask, NSControlKeyMask})
    check(fromKey.siwinKey() == siwin.Key.a)
    check(
      fromKey.siwinModifiers() == {siwin.ModifierKey.shift, siwin.ModifierKey.control}
    )
    check(fromKey.siwinRepeated())
    check(fromKey.siwinPressed())

    let mouseInput = siwin.MouseButtonEvent(
      button: siwin.MouseButton.left, pressed: true, generated: false
    )
    var fromMouse =
      mouseButtonEventFromSiwin(6, nsPoint(9, 10), mouseInput, {siwin.ModifierKey.alt})
    check(fromMouse.`type`() == NSLeftMouseDown)
    check(fromMouse.clickCount() == 1)
    check(fromMouse.isKindOfClass(NSEvent_mouse))
    check(fromMouse.siwinMouseButton() == siwin.MouseButton.left)
    check(fromMouse.modifierFlags() == {NSAlternateKeyMask})

    let otherMouseInput = siwin.MouseButtonEvent(
      button: siwin.MouseButton.middle, pressed: true, generated: false
    )
    var fromOtherMouse = mouseButtonEventFromSiwin(
      6, nsPoint(9, 10), otherMouseInput, {siwin.ModifierKey.alt}
    )
    check(fromOtherMouse.`type`() == NSOtherMouseDown)
    check(fromOtherMouse.siwinMouseButton() == siwin.MouseButton.middle)

    let scrollInput = siwin.ScrollEvent(delta: -2.0, deltaX: 1.5)
    var fromScroll =
      scrollEventFromSiwin(8, nsPoint(2, 7), scrollInput, {siwin.ModifierKey.system})
    check(fromScroll.`type`() == NSScrollWheel)
    check(fromScroll.deltaX() == 1.5)
    check(fromScroll.deltaY() == -2.0)
    check(fromScroll.modifierFlags() == {NSCommandKeyMask})

    let textInput = siwin.TextInputEvent(text: "Hello", repeated: false)
    var fromText =
      textInputEventFromSiwin(12, nsPoint(3, 2), textInput, {siwin.ModifierKey.shift})
    check(fromText.`type`() == NSApplicationDefined)
    check(isTextInputEvent(fromText))
    check(fromText.characters() == @ns"Hello")
    check(fromText.modifierFlags() == {NSShiftKeyMask})

    fromKey.value = nil
    fromMouse.value = nil
    fromOtherMouse.value = nil
    fromScroll.value = nil
    fromText.value = nil
