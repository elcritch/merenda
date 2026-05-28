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

protocol ViewProtocolInternal:
  required:
    method frame*(): Rect
    method bounds*(): Rect
    method isHidden*(): bool
    method needsDisplay*(): bool
    method backgroundColor*(): Color
    method superview*(): View
    method subviews*(): seq[View]
    method setNeedsDisplay*(value: bool)
    method setFrame*(frame: Rect)
    method setBounds*(bounds: Rect)
    method setHidden*(hidden: bool)
    method setBackgroundColor*(color: Color)
    method removeFromSuperview*()
    method addSubview*(child: View)
    method pointInside*(point: Point): bool
    method hitTest*(point: Point): View

protocol DefaultView of ViewProtocolInternal:
  method frame(self: View): Rect =
    self.xFrame

  method bounds(self: View): Rect =
    self.xBounds

  method isHidden(self: View): bool =
    self.xHidden

  method needsDisplay(self: View): bool =
    self.xNeedsDisplay

  method backgroundColor(self: View): Color =
    self.xBackgroundColor

  method superview(self: View): View =
    self.xSuperview

  method subviews(self: View): seq[View] =
    self.xSubviews

  method setNeedsDisplay(self: View, value: bool) =
    self.xNeedsDisplay = value
    if value and not self.xSuperview.isNil:
      self.xSuperview.setNeedsDisplay(true)

  method setFrame(self: View, frame: Rect) =
    if self.xFrame == frame:
      return
    self.xFrame = frame
    self.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
    self.setNeedsDisplay(true)

  method setBounds(self: View, bounds: Rect) =
    if self.xBounds == bounds:
      return
    self.xBounds = initRect(bounds.origin, bounds.size)
    self.setNeedsDisplay(true)

  method setHidden(self: View, hidden: bool) =
    if self.xHidden == hidden:
      return
    self.xHidden = hidden
    self.setNeedsDisplay(true)

  method setBackgroundColor(self: View, color: Color) =
    if self.xBackgroundColor == color:
      return
    self.xBackgroundColor = color
    self.setNeedsDisplay(true)

  method removeFromSuperview(self: View) =
    let parent = self.xSuperview
    if parent.isNil:
      return
    let idx = parent.xSubviews.find(self)
    if idx >= 0:
      parent.xSubviews.delete(idx)
      parent.setNeedsDisplay(true)
    self.xSuperview = nil
    self.clearNextResponder()

  method addSubview(self: View, child: View) =
    if child.isNil:
      return
    if not child.xSuperview.isNil:
      child.removeFromSuperview()
    child.xSuperview = self
    self.xSubviews.add child
    child.setNextResponder(self)
    self.setNeedsDisplay(true)

  method pointInside(self: View, point: Point): bool =
    self.xBounds.contains(point)

  method hitTest(self: View, point: Point): View =
    if self.xHidden or not self.pointInside(point):
      return nil

    for idx in countdown(self.xSubviews.high, 0):
      let child = self.xSubviews[idx]
      let local = point.localPoint(child.frame)
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
  discard view.replaceMethods(DefaultView.init())

proc newView*(frame: Rect): View =
  result = View()
  initViewFields(result, frame)

proc newView*(x, y, width, height: float32): View =
  newView(initRect(x, y, width, height))

proc dispatchMouseDown*(view: View, event: MouseEvent): bool =
  var value: EmptyArgs
  view.perform(mouseDownSelector(), event, value)

proc dispatchMouseUp*(view: View, event: MouseEvent): bool =
  var value: EmptyArgs
  view.perform(mouseUpSelector(), event, value)

proc dispatchKeyDown*(view: View, event: KeyEvent): bool =
  var value: EmptyArgs
  view.perform(keyDownSelector(), event, value)

proc clickAt*(view: View, point: Point): bool =
  let hit = view.hitTest(point)
  if hit.isNil:
    return false

  let event = MouseEvent(location: point, button: mbPrimary, clickCount: 1)
  discard hit.dispatchMouseDown(event)
  result = hit.dispatchMouseUp(event)

let ViewProtocol* = ViewProtocolInternal
