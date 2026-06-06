import std/unittest

import sigils/core
import sigils/selectors

import merenda/nimkit

type TextChangeSpy = ref object of Agent
  changeCount: int
  lastSender: DynamicAgent

proc rememberTextDidChange(spy: TextChangeSpy, sender: DynamicAgent) {.slot.} =
  inc spy.changeCount
  spy.lastSender = sender

suite "nimkit controls":
  test "button core methods are selector-backed and protocol visible":
    let button = newButton("Original", frame = initRect(0, 0, 120, 36))

    check button.conformsTo(ButtonProtocol)
    let swizzledTitle: DynamicMethod = proc(
        self: DynamicAgent, invocation: var Invocation
    ) =
      check Button(self) == button
      invocation.setResult("Swizzled")
    button.replaceMethod(title(), swizzledTitle)
    check button.title == "Swizzled"

  test "button click sends selector action to closure target":
    let
      root = newView(frame = initRect(0, 0, 240, 180))
      label = newTextField("Ready", frame = initRect(16, 16, 180, 32))
      button = newButton("Click", frame = initRect(16, 64, 120, 36))
      action = actionSelector("clickedAction")

    proc onClicked(sender: DynamicAgent) =
      check sender == DynamicAgent(button)
      label.text = "Clicked"

    let target = newActionTarget(action, onClicked)

    button.target = target
    button.action = action
    root.addSubview(label)
    root.addSubview(button)

    check root.hitTest(initPoint(24, 72)) == button
    check root.clickAt(initPoint(24, 72))
    check label.stringValue == "Clicked"

  test "button properties are forwarded through its button cell":
    let button = newButton("Original", frame = initRect(0, 0, 120, 36))
    let cell = button.buttonCell()

    check not cell.isNil
    check button.cell() == Cell(cell)
    check cell.title == "Original"
    check button.enabled

    button.enabled = false
    check not button.enabled
    button.enabled = true

    button.title = "Forwarded"
    check cell.title == "Forwarded"

    cell.setState(bsOn)
    check button.state == bsOn

    button.buttonType = btCheckBox
    check cell.buttonType == btCheckBox

  test "text fields emit explicit change signals":
    let
      field = newTextField("Value", frame = initRect(0, 0, 120, 24))
      spy = TextChangeSpy()

    connect(field, textDidChange, spy, rememberTextDidChange)

    field.text = "Changed"
    check spy.changeCount == 1
    check spy.lastSender == DynamicAgent(field)

    field.text = "Changed"
    check spy.changeCount == 1

  test "button mouse tracking cancels click when released outside":
    let
      window = newWindow("Button tracking", frame = initRect(0, 0, 240, 180))
      root = newView(frame = initRect(0, 0, 240, 180))
      button = newButton("Click", frame = initRect(16, 64, 120, 36))
      action = actionSelector("trackedClick")

    var actionCount = 0

    proc onClicked(sender: DynamicAgent) =
      check sender == DynamicAgent(button)
      inc actionCount

    let target = newActionTarget(action, onClicked)

    button.target = target
    button.action = action
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
      button = newButton("Toggle", frame = initRect(0, 0, 120, 36))
      action = actionSelector("toggleAction")

    proc onToggle(sender: DynamicAgent) =
      check sender == DynamicAgent(button)
      inc actionCount

    let target = newActionTarget(action, onToggle)

    button.buttonType = btToggle
    button.target = target
    button.action = action

    discard button.send(performClick(), ActionArgs(sender: button))
    check button.state == bsOn
    discard button.send(performClick(), ActionArgs(sender: button))
    check button.state == bsOff
    check actionCount == 2

  test "toggle button supports mixed state cycling":
    let button = newButton("Mixed", frame = initRect(0, 0, 120, 36))
    button.buttonType = btToggle
    button.allowsMixedState = true

    discard button.send(performClick(), ActionArgs(sender: button))
    check button.state == bsOn
    discard button.send(performClick(), ActionArgs(sender: button))
    check button.state == bsMixed
    discard button.send(performClick(), ActionArgs(sender: button))
    check button.state == bsOff

  test "checkbox toggles state and supports mixed state":
    var actionCount = 0
    let
      checkbox = newCheckBox("Enabled", frame = initRect(0, 0, 140, 24))
      action = actionSelector("checkboxAction")

    proc onToggle(sender: DynamicAgent) =
      check sender == DynamicAgent(checkbox)
      inc actionCount

    checkbox.target = newActionTarget(action, onToggle)
    checkbox.action = action
    checkbox.allowsMixedState = true

    discard checkbox.send(performClick(), ActionArgs(sender: checkbox))
    check checkbox.state == bsOn
    discard checkbox.send(performClick(), ActionArgs(sender: checkbox))
    check checkbox.state == bsMixed
    discard checkbox.send(performClick(), ActionArgs(sender: checkbox))
    check checkbox.state == bsOff
    check actionCount == 3

  test "radio buttons select one sibling without toggling off":
    var actionCount = 0
    var observedSelection = ""
    let
      root = newView(frame = initRect(0, 0, 220, 100))
      first = newRadioButton("First", frame = initRect(10, 10, 160, 24))
      second = newRadioButton("Second", frame = initRect(10, 42, 160, 24))
      other = newRadioButton("Other", frame = initRect(10, 74, 160, 24))
      action = actionSelector("radioAction")
      otherAction = actionSelector("otherRadioAction")

    proc onSelect(sender: DynamicAgent) =
      check sender == DynamicAgent(first) or sender == DynamicAgent(second) or
        sender == DynamicAgent(other)
      if first.state == bsOn:
        observedSelection = "first"
      elif second.state == bsOn:
        observedSelection = "second"
      elif other.state == bsOn:
        observedSelection = "other"
      else:
        observedSelection = "none"
      inc actionCount

    let target = newActionTarget(action, onSelect)
    first.target = target
    first.action = action
    second.target = target
    second.action = action
    other.target = target
    other.action = otherAction
    other.state = bsOn
    root.addSubview(first)
    root.addSubview(second)
    root.addSubview(other)

    discard first.send(performClick(), ActionArgs(sender: first))
    check first.state == bsOn
    check second.state == bsOff
    check other.state == bsOn
    check observedSelection == "first"

    discard second.send(performClick(), ActionArgs(sender: second))
    check first.state == bsOff
    check second.state == bsOn
    check other.state == bsOn
    check observedSelection == "second"

    discard second.send(performClick(), ActionArgs(sender: second))
    check second.state == bsOn
    check observedSelection == "second"
    check actionCount == 3
