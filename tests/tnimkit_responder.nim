import std/unittest

import sigils/selectors

import knutella/nimkit

suite "nimkit responder":
  test "next responder is observable and forwards selector dispatch":
    let
      action = actionSelector("forwardedAction")
      child = newResponder()

    var callCount = 0

    proc onForwarded(sender: DynamicAgent) =
      check sender == DynamicAgent(child)
      inc callCount

    let parent = newActionTarget(action, onForwarded)
    child.setNextResponder(parent)

    var value: EmptyArgs
    check child.nextResponder == parent
    check child.perform(action, ActionArgs(sender: child), value)
    check callCount == 1

  test "window first responder requires acceptance":
    let
      window = newWindow(0, 0, 240, 160, "Responder")
      plain = newView(0, 0, 240, 160)
      button = newButton(20, 20, 120, 36, "Default")

    check not window.makeFirstResponder(plain)
    check window.firstResponder.isNil
    check window.makeFirstResponder(button)
    check window.firstResponder == button

  test "space key activates button through first responder dispatch":
    let
      window = newWindow(0, 0, 240, 160, "Keys")
      root = newView(0, 0, 240, 160)
      button = newButton(20, 20, 120, 36, "Default")
      action = actionSelector("keyAction")

    var actionCount = 0

    proc onKeyAction(sender: DynamicAgent) =
      check sender == DynamicAgent(button)
      inc actionCount

    let target = newActionTarget(action, onKeyAction)
    button.setTarget(target)
    button.setAction(action)
    root.addSubview(button)
    window.setContentView(root)

    check window.makeFirstResponder(button)
    check window.dispatchKeyDown(KeyEvent(text: " ", keyCode: 32))
    check actionCount == 1
