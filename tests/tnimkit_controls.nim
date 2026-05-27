import std/unittest

import sigils/selectors

import knutella/nimkit

suite "nimkit controls":
  test "button click sends selector action to closure target":
    let
      root = newView(0, 0, 240, 180)
      label = newTextField(16, 16, 180, 32, "Ready")
      button = newButton(16, 64, 120, 36, "Click")
      action = actionSelector("buttonClicked")

    proc onClicked(sender: DynamicAgent) =
      check sender == DynamicAgent(button)
      label.setStringValue("Clicked")

    let target = newActionTarget(action, onClicked)

    button.setTarget(target)
    button.setAction(action)
    root.addSubview(label)
    root.addSubview(button)

    check root.clickAt(initPoint(24, 72))
    check label.stringValue == "Clicked"

  test "toggle button cycles state during performClick":
    var actionCount = 0
    let
      button = newButton(0, 0, 120, 36, "Toggle")
      action = actionSelector("toggleAction")

    proc onToggle(sender: DynamicAgent) =
      check sender == DynamicAgent(button)
      inc actionCount

    let target = newActionTarget(action, onToggle)

    button.setButtonType(btToggle)
    button.setTarget(target)
    button.setAction(action)

    discard button.send(performClickSelector(), ActionArgs(sender: button))
    check button.state == bsOn
    discard button.send(performClickSelector(), ActionArgs(sender: button))
    check button.state == bsOff
    check actionCount == 2

  test "toggle button supports mixed state cycling":
    let button = newButton(0, 0, 120, 36, "Mixed")
    button.setButtonType(btToggle)
    button.setAllowsMixedState(true)

    discard button.send(performClickSelector(), ActionArgs(sender: button))
    check button.state == bsOn
    discard button.send(performClickSelector(), ActionArgs(sender: button))
    check button.state == bsMixed
    discard button.send(performClickSelector(), ActionArgs(sender: button))
    check button.state == bsOff
