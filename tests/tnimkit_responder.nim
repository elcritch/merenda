import std/unittest

import sigils/selectors

import knutella/nimkit

type TrackingSpyView = ref object of View
  xName: string

var
  trackingEvents: seq[string]
  trackingPoints: seq[Point]
  trackingClickCounts: seq[int]
  trackingModifiers: seq[set[KeyModifier]]
  trackingTimestamps: seq[float]
  trackingScrollDeltas: seq[Point]

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
  trackingEvents.add(spy.xName & ".scroll")
  trackingPoints.add(location)
  trackingModifiers.add(modifiers)
  trackingTimestamps.add(timestamp)
  trackingScrollDeltas.add(delta)

proc resetTracking() =
  trackingEvents.setLen(0)
  trackingPoints.setLen(0)
  trackingClickCounts.setLen(0)
  trackingModifiers.setLen(0)
  trackingTimestamps.setLen(0)
  trackingScrollDeltas.setLen(0)

protocol TrackingSpyEvents of ResponderEventProtocol:
  method mouseDown(spy: TrackingSpyView, event: MouseEvent) =
    spy.recordTrackingEvent("down", event)

  method mouseUp(spy: TrackingSpyView, event: MouseEvent) =
    spy.recordTrackingEvent("up", event)

  method mouseEntered(spy: TrackingSpyView, event: MouseEvent) =
    spy.recordTrackingEvent("entered", event)

  method mouseExited(spy: TrackingSpyView, event: MouseEvent) =
    spy.recordTrackingEvent("exited", event)

  method mouseMoved(spy: TrackingSpyView, event: MouseEvent) =
    spy.recordTrackingEvent("moved", event)

  method mouseDragged(spy: TrackingSpyView, event: MouseEvent) =
    spy.recordTrackingEvent("dragged", event)

  method scrollWheel(spy: TrackingSpyView, event: ScrollEvent) =
    spy.recordScrollEvent(event)

proc newTrackingSpyView(name: string, frame: Rect): TrackingSpyView =
  result = TrackingSpyView(xName: name)
  initViewFields(result, frame)
  discard result.withProtocol(TrackingSpyEvents)

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

  test "window mouse tracking sends drag and up to mouse-down view":
    let
      window = newWindow(0, 0, 240, 160, "Mouse tracking")
      root = newView(0, 0, 240, 160)
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
      window = newWindow(0, 0, 240, 160, "Mouse move")
      root = newView(0, 0, 240, 160)
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
      window = newWindow(0, 0, 240, 160, "Mouse hover")
      root = newView(0, 0, 240, 160)
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
      window = newWindow(0, 0, 240, 160, "Mouse clicks")
      root = newView(0, 0, 240, 160)
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
      window = newWindow(0, 0, 240, 160, "Mouse click targets")
      root = newView(0, 0, 240, 160)
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
      window = newWindow(0, 0, 240, 160, "Mouse bubbling")
      root = newView(0, 0, 240, 160)
      parent = newTrackingSpyView("parent", initRect(10, 10, 100, 80))
      child = newView(20, 15, 30, 20)

    parent.addSubview(child)
    root.addSubview(parent)
    window.setContentView(root)

    resetTracking()

    check window.mouseDownAt(
      initPoint(35, 30), modifiers = {kmShift, kmCommand}, timestamp = 20.0
    )
    check window.mouseUpAt(
      initPoint(35, 30), modifiers = {kmShift, kmCommand}, timestamp = 20.1
    )

    check trackingEvents == @["parent.down", "parent.up"]
    check trackingPoints == @[initPoint(25, 20), initPoint(25, 20)]
    check trackingModifiers == @[{kmShift, kmCommand}, {kmShift, kmCommand}]
    check trackingTimestamps == @[20.0, 20.1]

  test "window scroll dispatch hit-tests and converts local coordinates":
    let
      window = newWindow(0, 0, 240, 160, "Mouse scroll")
      root = newView(0, 0, 240, 160)
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
    check trackingModifiers == @[{kmOption}]
    check trackingTimestamps == @[42.0]

  test "window scroll dispatch bubbles unhandled child scrolls":
    let
      window = newWindow(0, 0, 240, 160, "Scroll bubbling")
      root = newView(0, 0, 240, 160)
      parent = newTrackingSpyView("parent", initRect(10, 10, 100, 80))
      child = newView(20, 15, 30, 20)

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
