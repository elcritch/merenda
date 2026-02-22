import std/unittest

import nutella/appkit
import nutella/objc

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
