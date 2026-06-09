import std/unittest

import sigils/selectors

import merenda/nimkit

type TrackingSpyView = ref object of View
  xName: string

var
  trackingEvents: seq[string]
  trackingPoints: seq[Point]
  trackingClickCounts: seq[int]
  trackingModifiers: seq[set[KeyModifier]]
  trackingTimestamps: seq[float]
  trackingScrollDeltas: seq[Point]
  trackingScrollPhases: seq[ScrollEventPhase]
  trackingScrollMomentumPhases: seq[ScrollEventPhase]
  trackingCommandSenders: seq[DynamicAgent]

proc recordTrackingEvent(spy: TrackingSpyView, name: string, event: MouseEvent) =
  let
    location = event.location
    clickCount = event.clickCount
    modifiers = event.modifiers
    timestamp = event.timestamp
  trackingEvents.add(spy.xName & "." & name)
  trackingPoints.add(location)
  trackingClickCounts.add(clickCount)
  trackingModifiers.add(modifiers)
  trackingTimestamps.add(timestamp)

proc recordScrollEvent(spy: TrackingSpyView, event: ScrollEvent) =
  let
    location = event.location
    delta = initPoint(event.deltaX, event.deltaY)
    modifiers = event.modifiers
    timestamp = event.timestamp
    phase = event.phase
    momentumPhase = event.momentumPhase
  trackingEvents.add(spy.xName & ".scroll")
  trackingPoints.add(location)
  trackingModifiers.add(modifiers)
  trackingTimestamps.add(timestamp)
  trackingScrollDeltas.add(delta)
  trackingScrollPhases.add(phase)
  trackingScrollMomentumPhases.add(momentumPhase)

proc resetTracking() =
  trackingEvents.setLen(0)
  trackingPoints.setLen(0)
  trackingClickCounts.setLen(0)
  trackingModifiers.setLen(0)
  trackingTimestamps.setLen(0)
  trackingScrollDeltas.setLen(0)
  trackingScrollPhases.setLen(0)
  trackingScrollMomentumPhases.setLen(0)
  trackingCommandSenders.setLen(0)

protocol TrackingSpyEvents of ResponderEventProtocol:
  method mouseDown(spy: TrackingSpyView, event: MouseEvent): bool =
    spy.recordTrackingEvent("down", event)
    true

  method mouseUp(spy: TrackingSpyView, event: MouseEvent): bool =
    spy.recordTrackingEvent("up", event)
    true

  method mouseEntered(spy: TrackingSpyView, event: MouseEvent): bool =
    spy.recordTrackingEvent("entered", event)
    true

  method mouseExited(spy: TrackingSpyView, event: MouseEvent): bool =
    spy.recordTrackingEvent("exited", event)
    true

  method mouseMoved(spy: TrackingSpyView, event: MouseEvent): bool =
    spy.recordTrackingEvent("moved", event)
    true

  method mouseDragged(spy: TrackingSpyView, event: MouseEvent): bool =
    spy.recordTrackingEvent("dragged", event)
    true

  method scrollWheel(spy: TrackingSpyView, event: ScrollEvent) =
    spy.recordScrollEvent(event)

  method keyDown(spy: TrackingSpyView, event: KeyEvent) =
    trackingEvents.add(spy.xName & ".key:" & event.text)
    trackingModifiers.add(event.modifiers)

protocol TrackingSpyCommandProtocol:
  method trackingCommand*(args: ActionArgs) {.optional.}

protocol TrackingSpyCommands of TrackingSpyCommandProtocol:
  method trackingCommand(spy: TrackingSpyView, args: ActionArgs) =
    trackingEvents.add(spy.xName & ".command")
    trackingCommandSenders.add(args.sender)

proc newTrackingSpyView(name: string, frame: Rect): TrackingSpyView =
  result = TrackingSpyView(xName: name)
  initViewFields(result, frame)
  discard result.withProtocol(TrackingSpyEvents)
  discard result.withProtocol(TrackingSpyCommands)

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

    check child.nextResponder == parent
    check child.sendIfHandled(action, ActionArgs(sender: child))
    check callCount == 1

  test "window first responder requires acceptance":
    let
      window = newWindow("Responder", frame = initRect(0, 0, 240, 160))
      plain = newView(frame = initRect(0, 0, 240, 160))
      button = newButton("Default", frame = initRect(20, 20, 120, 36))

    check not window.makeFirstResponder(plain)
    check window.firstResponder.isNil
    check window.makeFirstResponder(button)
    check window.firstResponder == button
    check button.isFocused
    check button.isFocusVisible

  test "mouse focus does not force visible focus rings":
    let
      window = newWindow("Mouse focus", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      button = newButton("Default", frame = initRect(20, 20, 120, 36))

    root.addSubview(button)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(30, 30))
    check window.firstResponder == button
    check button.isFocused
    check not button.isFocusVisible

  test "space key activates button through default command binding":
    let
      window = newWindow("Keys", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      button = newButton("Default", frame = initRect(20, 20, 120, 36))
      action = actionSelector("keyAction")

    var actionCount = 0

    proc onKeyAction(sender: DynamicAgent) =
      check sender == DynamicAgent(button)
      inc actionCount

    let target = newActionTarget(action, onKeyAction)
    button.target = target
    button.action = action
    root.addSubview(button)
    window.setContentView(root)

    check window.makeFirstResponder(button)
    check window.dispatchKeyDown(
      KeyEvent(text: " ", key: keySpace, keyCode: keySpace.ord)
    )
    check actionCount == 1

  test "space and enter activate tab-selected checkbox":
    let
      window = newWindow("Checkbox keys", frame = initRect(0, 0, 260, 120))
      root = newView(frame = initRect(0, 0, 260, 120))
      field = newTextField("value", frame = initRect(10, 10, 90, 28))
      checkbox = newCheckBox("Enabled", frame = initRect(110, 10, 120, 28))
      action = actionSelector("checkboxKeyAction")

    var actionCount = 0

    proc onCheckboxKeyAction(sender: DynamicAgent) =
      check sender == DynamicAgent(checkbox)
      inc actionCount

    let target = newActionTarget(action, onCheckboxKeyAction)
    checkbox.target = target
    checkbox.action = action
    root.addSubview(field, checkbox)
    window.setContentView(root)

    check window.makeFirstResponder(field)
    check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check window.firstResponder == checkbox
    check checkbox.isFocused
    check checkbox.isFocusVisible

    check window.dispatchKeyDown(KeyEvent(key: keySpace, keyCode: keySpace.ord))
    check checkbox.state == bsOn
    check actionCount == 1

    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check checkbox.state == bsOff
    check actionCount == 2

  test "window key bindings dispatch commands through responder chain":
    let
      window = newWindow("Key commands", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      parent = newTrackingSpyView("parent", initRect(10, 10, 100, 80))
      child = newView(frame = initRect(20, 15, 30, 20))

    child.setAcceptsFirstResponder(true)
    parent.addSubview(child)
    root.addSubview(parent)
    window.setContentView(root)
    window.bindKey("k", {kmCommand}, trackingCommand())

    resetTracking()

    check window.makeFirstResponder(child)
    check window.dispatchKeyDown(
      KeyEvent(key: keyK, keyCode: keyK.ord, modifiers: {kmCommand})
    )

    check trackingEvents == @["parent.command"]
    check trackingCommandSenders == @[DynamicAgent(child)]

  test "window shortcut bindings resolve primary platform modifier":
    let
      window = newWindow("Shortcuts", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      parent = newTrackingSpyView("parent", initRect(10, 10, 100, 80))
      child = newView(frame = initRect(20, 15, 30, 20))

    child.setAcceptsFirstResponder(true)
    parent.addSubview(child)
    root.addSubview(parent)
    window.setContentView(root)
    window.bindShortcuts(keyK, {smShortcut}, trackingCommand())

    resetTracking()

    check window.makeFirstResponder(child)
    check window.dispatchKeyDown(
      KeyEvent(key: keyK, keyCode: keyK.ord, modifiers: shortcutModifiers())
    )

    check trackingEvents == @["parent.command"]
    check trackingCommandSenders == @[DynamicAgent(child)]

  test "unhandled key bindings fall through to raw key dispatch":
    let
      window = newWindow("Key fallback", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      parent = newTrackingSpyView("parent", initRect(10, 10, 100, 80))
      child = newView(frame = initRect(20, 15, 30, 20))

    child.setAcceptsFirstResponder(true)
    parent.addSubview(child)
    root.addSubview(parent)
    window.setContentView(root)
    window.bindKey("x", {kmCommand}, actionSelector("missingCommand"))

    resetTracking()

    check window.makeFirstResponder(child)
    check window.dispatchKeyDown(
      KeyEvent(text: "x", key: keyX, keyCode: keyX.ord, modifiers: {kmCommand})
    )

    check trackingEvents == @["parent.key:x"]
    check trackingModifiers == @[{kmCommand}]

  test "tab moves first responder through automatic key view loop":
    let
      window = newWindow("Key views", frame = initRect(0, 0, 320, 160))
      root = newView(frame = initRect(0, 0, 320, 160))
      first = newButton("First", frame = initRect(10, 10, 80, 28))
      field = newTextField("value", frame = initRect(100, 10, 100, 28))
      last = newButton("Last", frame = initRect(210, 10, 80, 28))

    root.addSubview(first)
    root.addSubview(field)
    root.addSubview(last)
    window.setContentView(root)

    check window.initialFirstResponder == first
    check window.makeFirstResponder(first)

    check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check window.firstResponder == field
    check field.isFocused
    check field.isFocusVisible
    check not first.isFocused
    check field.selectedRange == initTextRange(0, 5)

    check window.dispatchKeyDown(
      KeyEvent(key: keyTab, keyCode: keyTab.ord, modifiers: {kmShift})
    )
    check window.firstResponder == first
    check first.isFocused
    check first.isFocusVisible
    check not field.isFocused

    check window.dispatchKeyDown(
      KeyEvent(key: keyTab, keyCode: keyTab.ord, modifiers: {kmShift})
    )
    check window.firstResponder == last
    check last.isFocused
    check not first.isFocused

  test "tab skips views that cannot become key views":
    let
      window = newWindow("Key view skips", frame = initRect(0, 0, 320, 160))
      root = newView(frame = initRect(0, 0, 320, 160))
      plain = newView(frame = initRect(10, 10, 60, 28))
      disabled = newButton("Disabled", frame = initRect(80, 10, 80, 28))
      hidden = newButton("Hidden", frame = initRect(170, 10, 60, 28))
      enabled = newButton("OK", frame = initRect(240, 10, 60, 28))

    disabled.setEnabled(false)
    hidden.setHidden(true)
    root.addSubview(plain)
    root.addSubview(disabled)
    root.addSubview(hidden)
    root.addSubview(enabled)
    window.setContentView(root)

    check not window.makeFirstResponder(disabled)
    check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check window.firstResponder == enabled

  test "manual key view links are used when automatic loop is disabled":
    let
      window = newWindow("Manual key views", frame = initRect(0, 0, 320, 160))
      root = newView(frame = initRect(0, 0, 320, 160))
      first = newButton("First", frame = initRect(10, 10, 80, 28))
      skipped = newButton("Skipped", frame = initRect(100, 10, 80, 28))
      last = newButton("Last", frame = initRect(190, 10, 80, 28))

    root.addSubview(first)
    root.addSubview(skipped)
    root.addSubview(last)
    first.setNextKeyView(last)
    last.setNextKeyView(first)
    window.setAutorecalculatesKeyViewLoop(false)
    window.setContentView(root)

    check window.makeFirstResponder(first)
    check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check window.firstResponder == last

  test "doCommandBySelector raises for unhandled commands":
    let responder = newResponder()

    expect(UnhandledSelectorError):
      responder.doCommandBySelector(actionSelector("missingCommand"))

  test "window mouse tracking sends drag and up to mouse-down view":
    let
      window = newWindow("Mouse tracking", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      left = newTrackingSpyView("left", initRect(10, 10, 60, 40))
      right = newTrackingSpyView("right", initRect(120, 10, 60, 40))

    root.addSubview(left)
    root.addSubview(right)
    window.setContentView(root)

    resetTracking()

    check window.mouseDownAt(initPoint(20, 20))
    check window.mouseDraggedAt(initPoint(130, 20))
    check left.isActive
    check window.mouseUpAt(initPoint(130, 20))
    check not left.isActive

    check trackingEvents == @["left.down", "left.dragged", "left.up"]
    check trackingPoints == @[initPoint(10, 10), initPoint(120, 10), initPoint(120, 10)]

  test "window mouse move hit-tests normally after tracking clears":
    let
      window = newWindow("Mouse move", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      left = newTrackingSpyView("left", initRect(10, 10, 60, 40))
      right = newTrackingSpyView("right", initRect(120, 10, 60, 40))

    root.addSubview(left)
    root.addSubview(right)
    window.setContentView(root)

    resetTracking()

    check window.mouseDownAt(initPoint(20, 20))
    check window.mouseUpAt(initPoint(130, 20))
    check window.mouseMovedAt(initPoint(130, 20))

    check trackingEvents == @["left.down", "left.up", "right.entered", "right.moved"]
    check trackingPoints ==
      @[initPoint(10, 10), initPoint(120, 10), initPoint(10, 10), initPoint(10, 10)]

  test "window mouse move drives hover entered and exited state":
    let
      window = newWindow("Mouse hover", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      left = newTrackingSpyView("left", initRect(10, 10, 60, 40))
      right = newTrackingSpyView("right", initRect(120, 10, 60, 40))

    root.addSubview(left)
    root.addSubview(right)
    window.setContentView(root)

    resetTracking()

    check window.mouseMovedAt(initPoint(20, 20))
    check left.isHovered
    check not right.isHovered

    check window.mouseMovedAt(initPoint(130, 20))
    check not left.isHovered
    check right.isHovered

    check window.mouseMovedAt(initPoint(5, 5))
    check not left.isHovered
    check not right.isHovered

    check trackingEvents ==
      @[
        "left.entered", "left.moved", "left.exited", "right.entered", "right.moved",
        "right.exited",
      ]
    check trackingPoints ==
      @[
        initPoint(10, 10),
        initPoint(10, 10),
        initPoint(120, 10),
        initPoint(10, 10),
        initPoint(10, 10),
        initPoint(-115, -5),
      ]

  test "window mouse dispatch computes repeated click counts":
    let
      window = newWindow("Mouse clicks", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      left = newTrackingSpyView("left", initRect(10, 10, 80, 40))

    root.addSubview(left)
    window.setContentView(root)

    resetTracking()

    check window.mouseDownAt(initPoint(20, 20))
    check window.mouseUpAt(initPoint(20, 20))
    check window.mouseDownAt(initPoint(22, 21))
    check window.mouseUpAt(initPoint(22, 21))
    check window.mouseDownAt(initPoint(60, 20))
    check window.mouseUpAt(initPoint(60, 20))

    check trackingEvents ==
      @["left.down", "left.up", "left.down", "left.up", "left.down", "left.up"]
    check trackingClickCounts == @[1, 1, 2, 2, 1, 1]

  test "window mouse dispatch keeps click counts target-local":
    let
      window = newWindow("Mouse click targets", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      left = newTrackingSpyView("left", initRect(10, 10, 80, 40))
      right = newTrackingSpyView("right", initRect(10, 10, 80, 40))

    root.addSubview(left)
    window.setContentView(root)

    resetTracking()

    check window.mouseDownAt(initPoint(20, 20), timestamp = 100.0)
    check window.mouseUpAt(initPoint(20, 20), timestamp = 100.1)

    left.removeFromSuperview()
    root.addSubview(right)

    check window.mouseDownAt(initPoint(20, 20), timestamp = 100.2)
    check window.mouseUpAt(initPoint(20, 20), timestamp = 100.3)

    check trackingEvents == @["left.down", "left.up", "right.down", "right.up"]
    check trackingClickCounts == @[1, 1, 1, 1]

  test "window mouse dispatch bubbles unhandled child events in parent coordinates":
    let
      window = newWindow("Mouse bubbling", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      parent = newTrackingSpyView("parent", initRect(10, 10, 100, 80))
      child = newView(frame = initRect(20, 15, 30, 20))

    parent.addSubview(child)
    root.addSubview(parent)
    window.setContentView(root)

    resetTracking()

    check window.mouseDownAt(
      initPoint(35, 30), modifiers = {kmShift, kmCommand}, timestamp = 20.0
    )
    check not child.isActive
    check parent.isActive
    check window.mouseUpAt(
      initPoint(35, 30), modifiers = {kmShift, kmCommand}, timestamp = 20.1
    )
    check not parent.isActive

    check trackingEvents == @["parent.down", "parent.up"]
    check trackingPoints == @[initPoint(25, 20), initPoint(25, 20)]
    check trackingModifiers == @[{kmShift, kmCommand}, {kmShift, kmCommand}]
    check trackingTimestamps == @[20.0, 20.1]

  test "window key dispatch bubbles first responder key events":
    let
      window = newWindow("Key bubbling", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      parent = newTrackingSpyView("parent", initRect(10, 10, 100, 80))
      child = newView(frame = initRect(20, 15, 30, 20))

    child.setAcceptsFirstResponder(true)
    parent.addSubview(child)
    root.addSubview(parent)
    window.setContentView(root)

    resetTracking()

    check window.makeFirstResponder(child)
    check window.dispatchKeyDown(
      KeyEvent(text: "x", key: keyX, keyCode: keyX.ord, modifiers: {kmControl})
    )

    check trackingEvents == @["parent.key:x"]
    check trackingModifiers == @[{kmControl}]

  test "window scroll dispatch hit-tests and converts local coordinates":
    let
      window = newWindow("Mouse scroll", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      left = newTrackingSpyView("left", initRect(10, 10, 80, 40))

    root.addSubview(left)
    window.setContentView(root)

    resetTracking()

    check window.scrollWheelAt(
      initPoint(20, 20),
      deltaX = 1.5'f32,
      deltaY = -2.0'f32,
      modifiers = {kmOption},
      timestamp = 42.0,
    )

    check trackingEvents == @["left.scroll"]
    check trackingPoints == @[initPoint(10, 10)]
    check trackingScrollDeltas == @[initPoint(1.5, -2.0)]
    check trackingScrollPhases == @[sepChanged]
    check trackingScrollMomentumPhases == @[sepNone]
    check trackingModifiers == @[{kmOption}]
    check trackingTimestamps == @[42.0]

  test "window scroll dispatch preserves event phase and momentum target":
    let
      window = newWindow("Momentum scroll", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      left = newTrackingSpyView("left", initRect(10, 10, 80, 40))
      right = newTrackingSpyView("right", initRect(120, 10, 80, 40))

    root.addSubview(left)
    root.addSubview(right)
    window.setContentView(root)

    resetTracking()

    check window.dispatchScrollWheel(
      ScrollEvent(
        location: initPoint(20, 20),
        deltaY: -1.0'f32,
        phase: sepEnded,
        momentumPhase: sepBegan,
      )
    )
    check window.dispatchScrollWheel(
      ScrollEvent(
        location: initPoint(130, 20), deltaY: -1.0'f32, momentumPhase: sepChanged
      )
    )

    check trackingEvents == @["left.scroll", "left.scroll"]
    check trackingPoints == @[initPoint(10, 10), initPoint(10, 10)]
    check trackingScrollPhases == @[sepEnded, sepNone]
    check trackingScrollMomentumPhases == @[sepBegan, sepChanged]

  test "window mouse and scroll dispatch stop at content bounds":
    let
      window = newWindow("Content bounds", frame = initRect(0, 0, 100, 80))
      root = newView(frame = initRect(0, 0, 100, 80))
      child = newTrackingSpyView("child", initRect(120, 10, 40, 30))

    root.addSubview(child)
    window.setContentView(root)

    resetTracking()

    check root.hitTest(initPoint(125, 20)) == child
    check not window.mouseDownAt(initPoint(125, 20))
    check not window.scrollWheelAt(initPoint(125, 20), deltaY = 1.0)
    check trackingEvents.len == 0

  test "window scroll dispatch bubbles unhandled child scrolls":
    let
      window = newWindow("Scroll bubbling", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      parent = newTrackingSpyView("parent", initRect(10, 10, 100, 80))
      child = newView(frame = initRect(20, 15, 30, 20))

    parent.addSubview(child)
    root.addSubview(parent)
    window.setContentView(root)

    resetTracking()

    check window.scrollWheelAt(
      initPoint(35, 30),
      deltaX = -0.5'f32,
      deltaY = 3.0'f32,
      modifiers = {kmControl},
      timestamp = 43.0,
    )

    check trackingEvents == @["parent.scroll"]
    check trackingPoints == @[initPoint(25, 20)]
    check trackingScrollDeltas == @[initPoint(-0.5, 3.0)]
    check trackingModifiers == @[{kmControl}]
    check trackingTimestamps == @[43.0]
