import std/unittest

import sigils/selectors

import knutella/nimkit

method overrideTitle(self: Button): string {.selector.} =
  "Swizzled"

suite "nimkit controls":
  test "button core methods are selector-backed and protocol visible":
    let button = newButton(0, 0, 120, 36, "Original")

    check button.conformsTo(ButtonProtocol)
    discard button.replaceMethod(title(), overrideTitle)
    check button.title == "Swizzled"

  test "button click sends selector action to closure target":
    let
      root = newView(0, 0, 240, 180)
      label = newTextField(16, 16, 180, 32, "Ready")
      button = newButton(16, 64, 120, 36, "Click")
      action = actionSelector("clickedAction")

    proc onClicked(sender: DynamicAgent) =
      check sender == DynamicAgent(button)
      label.setStringValue("Clicked")

    let target = newActionTarget(action, onClicked)

    button.setTarget(target)
    button.setAction(action)
    root.addSubview(label)
    root.addSubview(button)

    check root.hitTest(initPoint(24, 72)) == button
    check root.clickAt(initPoint(24, 72))
    check label.stringValue == "Clicked"

  test "button mouse tracking cancels click when released outside":
    let
      window = newWindow(0, 0, 240, 180, "Button tracking")
      root = newView(0, 0, 240, 180)
      button = newButton(16, 64, 120, 36, "Click")
      action = actionSelector("trackedClick")

    var actionCount = 0

    proc onClicked(sender: DynamicAgent) =
      check sender == DynamicAgent(button)
      inc actionCount

    let target = newActionTarget(action, onClicked)

    button.setTarget(target)
    button.setAction(action)
    root.addSubview(button)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(24, 72))
    check button.isHighlighted
    check window.mouseDraggedAt(initPoint(200, 150))
    check not button.isHighlighted
    check window.mouseUpAt(initPoint(200, 150))
    check actionCount == 0

    check window.mouseDownAt(initPoint(24, 72))
    check window.mouseDraggedAt(initPoint(200, 150))
    check window.mouseDraggedAt(initPoint(24, 72))
    check button.isHighlighted
    check window.mouseUpAt(initPoint(24, 72))
    check actionCount == 1

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

    discard button.send(performClick(), ActionArgs(sender: button))
    check button.state == bsOn
    discard button.send(performClick(), ActionArgs(sender: button))
    check button.state == bsOff
    check actionCount == 2

  test "toggle button supports mixed state cycling":
    let button = newButton(0, 0, 120, 36, "Mixed")
    button.setButtonType(btToggle)
    button.setAllowsMixedState(true)

    discard button.send(performClick(), ActionArgs(sender: button))
    check button.state == bsOn
    discard button.send(performClick(), ActionArgs(sender: button))
    check button.state == bsMixed
    discard button.send(performClick(), ActionArgs(sender: button))
    check button.state == bsOff

  test "checkbox toggles state and supports mixed state":
    var actionCount = 0
    let
      checkbox = newCheckBox(0, 0, 140, 24, "Enabled")
      action = actionSelector("checkboxAction")

    proc onToggle(sender: DynamicAgent) =
      check sender == DynamicAgent(checkbox)
      inc actionCount

    checkbox.setTarget(newActionTarget(action, onToggle))
    checkbox.setAction(action)
    checkbox.setAllowsMixedState(true)

    discard checkbox.send(performClick(), ActionArgs(sender: checkbox))
    check checkbox.state == bsOn
    discard checkbox.send(performClick(), ActionArgs(sender: checkbox))
    check checkbox.state == bsMixed
    discard checkbox.send(performClick(), ActionArgs(sender: checkbox))
    check checkbox.state == bsOff
    check actionCount == 3

  test "radio buttons select one sibling without toggling off":
    var actionCount = 0
    let
      root = newView(0, 0, 220, 100)
      first = newRadioButton(10, 10, 160, 24, "First")
      second = newRadioButton(10, 42, 160, 24, "Second")
      action = actionSelector("radioAction")

    proc onSelect(sender: DynamicAgent) =
      check sender == DynamicAgent(first) or sender == DynamicAgent(second)
      inc actionCount

    let target = newActionTarget(action, onSelect)
    first.setTarget(target)
    first.setAction(action)
    second.setTarget(target)
    second.setAction(action)
    root.addSubview(first)
    root.addSubview(second)

    discard first.send(performClick(), ActionArgs(sender: first))
    check first.state == bsOn
    check second.state == bsOff

    discard second.send(performClick(), ActionArgs(sender: second))
    check first.state == bsOff
    check second.state == bsOn

    discard second.send(performClick(), ActionArgs(sender: second))
    check second.state == bsOn
    check actionCount == 3
