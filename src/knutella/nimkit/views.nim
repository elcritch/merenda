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

proc pointFromView*(view: View, point: Point, fromView: View): Point
proc pointToView*(view: View, point: Point, toView: View): Point
proc rectFromView*(view: View, rect: Rect, fromView: View): Rect
proc rectToView*(view: View, rect: Rect, toView: View): Rect
proc pointFromWindow*(view: View, point: Point): Point
proc pointToWindow*(view: View, point: Point): Point
proc rectFromWindow*(view: View, rect: Rect): Rect
proc rectToWindow*(view: View, rect: Rect): Rect

protocol ViewProtocolInternal from View:
  property frame -> Rect
  property bounds -> Rect
  property needsDisplay -> bool
  property backgroundColor -> Color

  method frame(self: View): Rect =
    self.xFrame

  method setFrame(self: View, frame: Rect) =
    if self.xFrame == frame:
      return
    self.xFrame = frame
    self.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
    self.setNeedsDisplay(true)

  method bounds(self: View): Rect =
    self.xBounds

  method setBounds(self: View, bounds: Rect) =
    if self.xBounds == bounds:
      return
    self.xBounds = initRect(bounds.origin, bounds.size)
    self.setNeedsDisplay(true)

  method needsDisplay(self: View): bool =
    self.xNeedsDisplay

  method setNeedsDisplay(self: View, value: bool) =
    self.xNeedsDisplay = value
    if value and not self.xSuperview.isNil:
      self.xSuperview.setNeedsDisplay(true)

  method backgroundColor(self: View): Color =
    self.xBackgroundColor

  method setBackgroundColor(self: View, color: Color) =
    if self.xBackgroundColor == color:
      return
    self.xBackgroundColor = color
    self.setNeedsDisplay(true)

  method isHidden*(self: View): bool =
    self.xHidden

  method setHidden*(self: View, hidden: bool) =
    if self.xHidden == hidden:
      return
    self.xHidden = hidden
    self.setNeedsDisplay(true)

  method superview*(self: View): View =
    self.xSuperview

  method subviews*(self: View): seq[View] =
    self.xSubviews

  method removeFromSuperview*(self: View) =
    let parent = self.xSuperview
    if parent.isNil:
      return
    let idx = parent.xSubviews.find(self)
    if idx >= 0:
      parent.xSubviews.delete(idx)
      parent.setNeedsDisplay(true)
    self.xSuperview = nil
    self.clearNextResponder()

  method addSubview*(self: View, child: View) =
    if child.isNil:
      return
    if not child.xSuperview.isNil:
      child.removeFromSuperview()
    child.xSuperview = self
    self.xSubviews.add child
    child.setNextResponder(self)
    self.setNeedsDisplay(true)

  method pointInside*(self: View, point: Point): bool =
    self.xBounds.contains(point)

  method hitTest*(self: View, point: Point): View =
    if self.xHidden or not self.pointInside(point):
      return nil

    for idx in countdown(self.xSubviews.high, 0):
      let child = self.xSubviews[idx]
      let local = child.pointFromView(point, self)
      let hit = child.hitTest(local)
      if not hit.isNil:
        return hit

    self

proc initViewFields*(view: View, frame: Rect) =
  initResponder(view)
  view.xFrame = frame
  view.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
  view.xNeedsDisplay = true
  view.xBackgroundColor = initColor(0.94, 0.95, 0.97, 1.0)
  discard view.withProto()

proc newView*(frame: Rect): View =
  result = View()
  initViewFields(result, frame)

proc newView*(x, y, width, height: float32): View =
  newView(initRect(x, y, width, height))

proc pointToSuperview(view: View, point: Point): Point =
  let
    frame = view.frame
    bounds = view.bounds
  initPoint(
    frame.origin.x + point.x - bounds.origin.x,
    frame.origin.y + point.y - bounds.origin.y,
  )

proc pointFromSuperview(view: View, point: Point): Point =
  let
    frame = view.frame
    bounds = view.bounds
  initPoint(
    bounds.origin.x + point.x - frame.origin.x,
    bounds.origin.y + point.y - frame.origin.y,
  )

proc pointToWindow*(view: View, point: Point): Point =
  if view.isNil:
    return point
  var resultPoint = point
  var current = view
  while not current.isNil:
    resultPoint = current.pointToSuperview(resultPoint)
    current = current.superview
  resultPoint

proc pointFromWindow*(view: View, point: Point): Point =
  if view.isNil:
    return point
  var chain: seq[View] = @[]
  var current = view
  while not current.isNil:
    chain.add(current)
    current = current.superview
  var resultPoint = point
  for idx in countdown(chain.high, 0):
    resultPoint = chain[idx].pointFromSuperview(resultPoint)
  resultPoint

proc pointToView*(view: View, point: Point, toView: View): Point =
  if view.isNil:
    if toView.isNil:
      return point
    return toView.pointFromWindow(point)
  if view == toView:
    return point
  let windowPoint = view.pointToWindow(point)
  if toView.isNil:
    windowPoint
  else:
    toView.pointFromWindow(windowPoint)

proc pointFromView*(view: View, point: Point, fromView: View): Point =
  if view.isNil:
    if fromView.isNil:
      return point
    return fromView.pointToWindow(point)
  if view == fromView:
    return point
  if fromView.isNil:
    return view.pointFromWindow(point)
  view.pointFromWindow(fromView.pointToWindow(point))

proc rectFromCorners(p0, p1: Point): Rect =
  initRect(min(p0.x, p1.x), min(p0.y, p1.y), abs(p1.x - p0.x), abs(p1.y - p0.y))

proc rectToWindow*(view: View, rect: Rect): Rect =
  let
    p0 = view.pointToWindow(rect.origin)
    p1 = view.pointToWindow(initPoint(rect.maxX, rect.maxY))
  rectFromCorners(p0, p1)

proc rectFromWindow*(view: View, rect: Rect): Rect =
  let
    p0 = view.pointFromWindow(rect.origin)
    p1 = view.pointFromWindow(initPoint(rect.maxX, rect.maxY))
  rectFromCorners(p0, p1)

proc rectToView*(view: View, rect: Rect, toView: View): Rect =
  let
    p0 = view.pointToView(rect.origin, toView)
    p1 = view.pointToView(initPoint(rect.maxX, rect.maxY), toView)
  rectFromCorners(p0, p1)

proc rectFromView*(view: View, rect: Rect, fromView: View): Rect =
  let
    p0 = view.pointFromView(rect.origin, fromView)
    p1 = view.pointFromView(initPoint(rect.maxX, rect.maxY), fromView)
  rectFromCorners(p0, p1)

proc dispatchMouseDown*(view: View, event: MouseEvent): bool =
  view.sendIfHandled(mouseDown(), event)

proc dispatchMouseUp*(view: View, event: MouseEvent): bool =
  view.sendIfHandled(mouseUp(), event)

proc dispatchMouseMoved*(view: View, event: MouseEvent): bool =
  view.sendIfHandled(mouseMoved(), event)

proc dispatchMouseDragged*(view: View, event: MouseEvent): bool =
  view.sendIfHandled(mouseDragged(), event)

proc dispatchKeyDown*(view: View, event: KeyEvent): bool =
  view.sendIfHandled(keyDown(), event)

proc clickAt*(view: View, point: Point): bool =
  let hit = view.hitTest(point)
  if hit.isNil:
    return false

  let event = MouseEvent(
    location: hit.pointFromView(point, view), button: mbPrimary, clickCount: 1
  )
  discard hit.dispatchMouseDown(event)
  result = hit.dispatchMouseUp(event)

let ViewProtocol* = ViewProtocolInternal
