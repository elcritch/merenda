import std/unittest

import siwin/window as siwin

import nutella/appkit
import nutella/objc

suite "appkit NSEvent":
  test "event masks and constants match header values":
    check(NSEventMaskFromType(NSKeyDown) == NSKeyDownMask.cuint)
    check(NSEventMaskFromType(NSScrollWheel) == NSScrollWheelMask.cuint)
    check(NSDeviceIndependentModifierFlagsMask == 0xffff_0000'u)
    check(NSF1FunctionKey == 0xF704'u16)
    check(NSModeSwitchFunctionKey == 0xF747'u16)

  test "key and other event factories round-trip payload values":
    let keyFlags = (NSShiftKeyMask or NSCommandKeyMask).cuint
    var keyEvent = newKeyEvent(
      NSKeyDown, nsPoint(12, 18), keyFlags, 42.5, 77, @ns"a", @ns"A", false, 12'u16
    )
    check(keyEvent.`type`() == NSKeyDown)
    check(keyEvent.locationInWindow() == nsPoint(12, 18))
    check(keyEvent.modifierFlags() == (NSShiftKeyMask or NSCommandKeyMask))
    check(keyEvent.windowNumber() == 77)
    check(keyEvent.characters() == @ns"a")
    check(keyEvent.charactersIgnoringModifiers() == @ns"A")
    check(keyEvent.keyCode() == 12'u16)

    var otherEvent = newOtherEvent(
      NSApplicationDefined, nsPoint(1, 2), NSControlKeyMask, 21.0, 5, 9.cshort, 100, 200
    )
    check(otherEvent.subtype() == 9)
    check(otherEvent.data1() == 100)
    check(otherEvent.data2() == 200)

    keyEvent.value = nil
    otherEvent.value = nil

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
    check(fromKey.modifierFlags() == (NSShiftKeyMask or NSControlKeyMask))
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
    check(fromMouse.siwinMouseButton() == siwin.MouseButton.left)
    check(fromMouse.modifierFlags() == NSAlternateKeyMask)

    let scrollInput = siwin.ScrollEvent(delta: -2.0, deltaX: 1.5)
    var fromScroll =
      scrollEventFromSiwin(8, nsPoint(2, 7), scrollInput, {siwin.ModifierKey.system})
    check(fromScroll.`type`() == NSScrollWheel)
    check(fromScroll.deltaX() == 1.5)
    check(fromScroll.deltaY() == -2.0)
    check(fromScroll.modifierFlags() == NSCommandKeyMask)

    fromKey.value = nil
    fromMouse.value = nil
    fromScroll.value = nil
