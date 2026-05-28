import sigils/selectors

import ./responders
import ./selectors
import ./types

export responders

type View* = ref object of Responder
  xFrame: Rect
  xBounds: Rect
  xHidden: bool
  xNeedsDisplay: bool
  xBackgroundColor: Color
  xSuperview: View
  xSubviews: seq[View]

proc initViewFields*(view: View, frame: Rect) =
  initResponder(view)
  view.xFrame = frame
  view.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
  view.xNeedsDisplay = true
  view.xBackgroundColor = initColor(0.94, 0.95, 0.97, 1.0)

proc newView*(frame: Rect): View =
  result = View()
  initViewFields(result, frame)

proc newView*(x, y, width, height: float32): View =
  newView(initRect(x, y, width, height))

proc frame*(view: View): Rect =
  view.xFrame

proc bounds*(view: View): Rect =
  view.xBounds

proc isHidden*(view: View): bool =
  view.xHidden

proc needsDisplay*(view: View): bool =
  view.xNeedsDisplay

proc backgroundColor*(view: View): Color =
  view.xBackgroundColor

proc superview*(view: View): View =
  view.xSuperview

proc subviews*(view: View): lent seq[View] =
  view.xSubviews

proc setNeedsDisplay*(view: View, value: bool) =
  view.xNeedsDisplay = value
  if value and not view.xSuperview.isNil:
    view.xSuperview.setNeedsDisplay(true)

proc setFrame*(view: View, frame: Rect) =
  if view.frame == frame:
    return
  view.xFrame = frame
  view.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
  view.setNeedsDisplay(true)

proc setBounds*(view: View, bounds: Rect) =
  if view.bounds == bounds:
    return
  view.xBounds = initRect(bounds.origin, bounds.size)
  view.setNeedsDisplay(true)

proc setHidden*(view: View, hidden: bool) =
  if view.isHidden == hidden:
    return
  view.xHidden = hidden
  view.setNeedsDisplay(true)

proc setBackgroundColor*(view: View, color: Color) =
  if view.backgroundColor == color:
    return
  view.xBackgroundColor = color
  view.setNeedsDisplay(true)

proc removeFromSuperview*(view: View) =
  let parent = view.xSuperview
  if parent.isNil:
    return
  let idx = parent.xSubviews.find(view)
  if idx >= 0:
    parent.xSubviews.delete(idx)
    parent.setNeedsDisplay(true)
  view.xSuperview = nil
  view.clearNextResponder()

proc addSubview*(view, child: View) =
  if child.isNil:
    return
  if not child.xSuperview.isNil:
    child.removeFromSuperview()
  child.xSuperview = view
  view.xSubviews.add child
  child.setNextResponder(view)
  view.setNeedsDisplay(true)

proc pointInside*(view: View, point: Point): bool =
  view.bounds.contains(point)

proc hitTest*(view: View, point: Point): View =
  if view.isHidden or not view.pointInside(point):
    return nil

  for idx in countdown(view.xSubviews.high, 0):
    let child = view.xSubviews[idx]
    let local = point.localPoint(child.frame)
    let hit = child.hitTest(local)
    if not hit.isNil:
      return hit

  view

proc dispatchMouseDown*(view: View, event: MouseEvent): bool =
  var value: EmptyArgs
  view.perform(mouseDownSelector(), MouseEventArgs(event: event), value)

proc dispatchMouseUp*(view: View, event: MouseEvent): bool =
  var value: EmptyArgs
  view.perform(mouseUpSelector(), MouseEventArgs(event: event), value)

proc dispatchKeyDown*(view: View, event: KeyEvent): bool =
  var value: EmptyArgs
  view.perform(keyDownSelector(), KeyEventArgs(event: event), value)

proc clickAt*(view: View, point: Point): bool =
  let hit = view.hitTest(point)
  if hit.isNil:
    return false

  let event = MouseEvent(location: point, button: mbPrimary, clickCount: 1)
  discard hit.dispatchMouseDown(event)
  result = hit.dispatchMouseUp(event)
