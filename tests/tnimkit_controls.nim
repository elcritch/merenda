import std/unittest

import sigils/core
import sigils/selectors

import merenda/nimkit

type TextChangeSpy = ref object of Agent
  changeCount: int
  lastSender: DynamicAgent

type ControlActionSpy = ref object of Agent
  events: seq[string]
  lastSender: DynamicAgent

proc rememberTextDidChange(spy: TextChangeSpy, sender: DynamicAgent) {.slot.} =
  inc spy.changeCount
  spy.lastSender = sender

proc rememberActionDidSend(spy: ControlActionSpy, sender: DynamicAgent) {.slot.} =
  spy.events.add "signal"
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

    field.connect(textDidChange, spy, rememberTextDidChange)

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

  test "slider clamps, steps, and sends actions while tracking":
    let slider = newSlider(0.0, 100.0, 25.0, frame = initRect(10, 10, 200, 24))
    slider.stepValue = 10.0

    check slider.value == 30.0
    slider.value = 104.0
    check slider.value == 100.0
    slider.value = -4.0
    check slider.value == 0.0

    let
      window = newWindow("Slider tracking", frame = initRect(0, 0, 240, 80))
      root = newView(frame = initRect(0, 0, 240, 80))
      action = actionSelector("sliderAction")
      spy = ControlActionSpy()

    var actionCount = 0
    proc onSlide(sender: DynamicAgent) =
      check sender == DynamicAgent(slider)
      spy.events.add "target"
      inc actionCount

    slider.connect(actionDidSend, spy, rememberActionDidSend)
    slider.target = newActionTarget(action, onSlide)
    slider.action = action
    root.addSubview(slider)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(120, 22))
    check slider.cell().isHighlighted()
    check actionCount > 0
    check spy.events == @["target", "signal"]
    check spy.lastSender == DynamicAgent(slider)

    let previousCount = actionCount
    check window.mouseDraggedAt(initPoint(200, 22))
    check slider.value >= 90.0
    check actionCount > previousCount
    check spy.events[spy.events.len - 2] == "target"
    check spy.events[spy.events.len - 1] == "signal"

    check window.mouseUpAt(initPoint(200, 22))
    check not slider.cell().isHighlighted()

  test "stepper clamps, wraps, formats values, and dispatches actions":
    let
      stepper = newStepper(0.0, 10.0, 4.0, increment = 2.0)
      action = actionSelector("stepperAction")
      spy = ControlActionSpy()

    var actionCount = 0
    proc onStep(sender: DynamicAgent) =
      check sender == DynamicAgent(stepper)
      spy.events.add "target"
      inc actionCount

    stepper.connect(actionDidSend, spy, rememberActionDidSend)
    stepper.target = newActionTarget(action, onStep)
    stepper.action = action

    check stepper.value == 4.0
    check stepper.intrinsicContentSize().width == 52.0
    check stepper.intrinsicContentSize().height == 23.0
    check stepper.incrementValue()
    check stepper.value == 6.0
    check actionCount == 1
    check spy.events == @["target", "signal"]
    check spy.lastSender == DynamicAgent(stepper)

    check stepper.decrementValue()
    check stepper.value == 4.0
    stepper.value = 99.0
    check stepper.value == 10.0
    check not stepper.incrementValue()
    check actionCount == 2

    stepper.wraps = true
    check stepper.incrementValue()
    check stepper.value == 0.0
    check stepper.decrementValue()
    check stepper.value == 10.0

    stepper.valueFormatter = proc(value: float32): string =
      $int(value) & " units"
    check stepper.formattedValue == "10 units"
    check stepper.accessibilityValue() == "10 units"

    stepper.increment = -1.0
    check stepper.increment == 0.0
    check not stepper.incrementValue()

  test "stepper mouse and keyboard tracking maintains repeat state":
    let
      window = newWindow("Stepper tracking", frame = initRect(0, 0, 120, 80))
      root = newView(frame = initRect(0, 0, 120, 80))
      stepper =
        newStepper(0.0, 10.0, 4.0, increment = 2.0, frame = initRect(10, 10, 52, 23))
      action = actionSelector("stepperTrackingAction")

    var actionCount = 0
    proc onStep(sender: DynamicAgent) =
      check sender == DynamicAgent(stepper)
      inc actionCount

    stepper.target = newActionTarget(action, onStep)
    stepper.action = action
    root.addSubview(stepper)
    window.setContentView(root)

    check stepper.partAtPoint(initPoint(13.0, 11.0)) == spDecrement
    check stepper.partAtPoint(initPoint(39.0, 11.0)) == spIncrement

    check window.mouseDownAt(initPoint(49, 21), timestamp = 10.0)
    check stepper.value == 6.0
    check stepper.pressedPart == spIncrement
    check stepper.repeatPart == spIncrement
    check stepper.repeatActive()
    check stepper.repeatCount == 1
    check stepper.repeatStartedAt == 10.0
    check actionCount == 1

    check window.mouseTrackingTickAt(initPoint(49, 21), timestamp = 10.2)
    check stepper.value == 6.0
    check stepper.repeatCount == 1
    check actionCount == 1

    check window.mouseTrackingTickAt(initPoint(49, 21), timestamp = 10.36)
    check stepper.value == 8.0
    check stepper.repeatCount == 2
    check stepper.lastRepeatAt == 10.36
    check actionCount == 2

    check window.mouseDraggedAt(initPoint(80, 70), timestamp = 10.4)
    check stepper.pressedPart == spNone
    check window.mouseTrackingTickAt(initPoint(80, 70), timestamp = 10.5)
    check stepper.value == 8.0
    check stepper.repeatCount == 2
    check actionCount == 2

    check window.mouseDraggedAt(initPoint(49, 21), timestamp = 10.6)
    check stepper.pressedPart == spIncrement
    check window.mouseTrackingTickAt(initPoint(49, 21), timestamp = 10.6)
    check stepper.value == 10.0
    check stepper.repeatCount == 3
    check stepper.lastRepeatAt == 10.6
    check actionCount == 3

    check window.mouseUpAt(initPoint(49, 21), timestamp = 11.0)
    check stepper.pressedPart == spNone
    check stepper.repeatPart == spNone
    check not stepper.repeatActive()
    check stepper.repeatCount == 3

    check window.makeFirstResponder(stepper)
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown))
    check stepper.value == 8.0
    check window.dispatchKeyDown(KeyEvent(key: keyArrowUp))
    check stepper.value == 10.0

  test "progress indicator clamps values and exposes display state":
    let indicator = newProgressIndicator(0.0, 100.0, 25.0)

    check indicator.conformsTo(ProgressProtocol)
    check indicator.progressIndicatorCell() == ProgressIndicatorCell(indicator.cell())
    check indicator.value == 25.0

    let swizzledValue: DynamicMethod = proc(
        self: DynamicAgent, invocation: var Invocation
    ) =
      check ProgressIndicator(self).conformsTo(ProgressProtocol)
      invocation.setResult(42.0'f32)

    let protocolProbe = newProgressIndicator(0.0, 100.0, 25.0)
    protocolProbe.replaceMethod(value(), swizzledValue)
    check protocolProbe.value == 42.0

    indicator.value = 140.0
    check indicator.value == 100.0
    indicator.value = -20.0
    check indicator.value == 0.0

    indicator.incrementBy(12.5)
    check indicator.value == 12.5
    indicator.minValue = 20.0
    check indicator.value == 20.0

    check not indicator.indeterminate
    indicator.indeterminate = true
    check indicator.indeterminate
    check indicator.accessibilityRole() == arProgressIndicator
    check indicator.accessibilityValue() == "indeterminate"

    check not indicator.animating
    indicator.startAnimation()
    check indicator.animating
    check ssActive in indicator.widgetStateSet()
    indicator.stepAnimation(0.25)
    check indicator.animationPhase == 0.25
    indicator.stopAnimation()
    check not indicator.animating
    check ssActive notin indicator.widgetStateSet()

    indicator.progressIndicatorStyle = pisSpinning
    check indicator.intrinsicContentSize().width ==
      indicator.intrinsicContentSize().height

  test "control action signal can be used without a target":
    let
      slider = newSlider(0.0, 1.0, 0.0)
      spy = ControlActionSpy()

    slider.connect(actionDidSend, spy, rememberActionDidSend)

    check not slider.sendAction()
    check spy.events == @["signal"]
    check spy.lastSender == DynamicAgent(slider)

  test "switch button toggles state and sends action signal after target":
    let
      switchButton = newSwitchButton(false, frame = initRect(0, 0, 54, 30))
      action = actionSelector("switchAction")
      spy = ControlActionSpy()

    var actionCount = 0
    proc onSwitch(sender: DynamicAgent) =
      check sender == DynamicAgent(switchButton)
      spy.events.add "target"
      inc actionCount

    check switchButton.conformsTo(SwitchButtonProtocol)
    check switchButton.state == bsOff
    check not switchButton.on

    switchButton.connect(actionDidSend, spy, rememberActionDidSend)
    switchButton.target = newActionTarget(action, onSwitch)
    switchButton.action = action

    discard switchButton.send(performClick(), ActionArgs(sender: switchButton))
    check switchButton.state == bsOn
    check switchButton.on
    check actionCount == 1
    check spy.events == @["target", "signal"]
    check spy.lastSender == DynamicAgent(switchButton)

    switchButton.state = bsMixed
    check switchButton.state == bsOff
    check not switchButton.on

  test "switch button mouse tracking cancels click when released outside":
    let
      window = newWindow("Switch tracking", frame = initRect(0, 0, 180, 90))
      root = newView(frame = initRect(0, 0, 180, 90))
      switchButton = newSwitchButton(false, frame = initRect(16, 24, 54, 30))
      action = actionSelector("trackedSwitch")

    var actionCount = 0
    proc onSwitch(sender: DynamicAgent) =
      check sender == DynamicAgent(switchButton)
      inc actionCount

    switchButton.target = newActionTarget(action, onSwitch)
    switchButton.action = action
    root.addSubview(switchButton)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(24, 32))
    check switchButton.highlighted
    check window.mouseDraggedAt(initPoint(150, 70))
    check not switchButton.highlighted
    check window.mouseUpAt(initPoint(150, 70))
    check not switchButton.on
    check actionCount == 0

    check window.mouseDownAt(initPoint(24, 32))
    check window.mouseUpAt(initPoint(24, 32))
    check switchButton.on
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
