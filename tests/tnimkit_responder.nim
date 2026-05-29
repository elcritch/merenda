import std/unittest

import sigils/selectors

import knutella/nimkit

type TrackingSpyView = ref object of View
  xName: string

var
  trackingEvents: seq[string]
  trackingPoints: seq[Point]

proc recordTrackingEvent(spy: TrackingSpyView, name: string, event: MouseEvent) =
  trackingEvents.add(spy.xName & "." & name)
  trackingPoints.add(event.location)

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

    trackingEvents.setLen(0)
    trackingPoints.setLen(0)

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

    trackingEvents.setLen(0)
    trackingPoints.setLen(0)

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

    trackingEvents.setLen(0)
    trackingPoints.setLen(0)

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
