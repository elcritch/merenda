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
    method frame(): Rect
    method bounds(): Rect
    method isHidden(): bool
    method needsDisplay(): bool
    method backgroundColor(): Color
    method superview(): View
    method subviews(): seq[View]
    method setNeedsDisplay(value: bool)
    method setFrame(frame: Rect)
    method setBounds(bounds: Rect)
    method setHidden(hidden: bool)
    method setBackgroundColor(color: Color)
    method removeFromSuperview()
    method addSubview(child: View)
    method pointInside(point: Point): bool
    method hitTest(point: Point): View

method viewFrame(self: View): Rect {.selector.} =
  self.xFrame

method viewBounds(self: View): Rect {.selector.} =
  self.xBounds

method viewIsHidden(self: View): bool {.selector.} =
  self.xHidden

method viewNeedsDisplay(self: View): bool {.selector.} =
  self.xNeedsDisplay

method viewBackgroundColor(self: View): Color {.selector.} =
  self.xBackgroundColor

method viewSuperview(self: View): View {.selector.} =
  self.xSuperview

method viewSubviews(self: View): seq[View] {.selector.} =
  self.xSubviews

method viewSetNeedsDisplay(self: View, value: bool): EmptyArgs {.selector.} =
  self.xNeedsDisplay = value
  if value and not self.xSuperview.isNil:
    self.xSuperview.setNeedsDisplay(true)

method viewSetFrame(self: View, frame: Rect): EmptyArgs {.selector.} =
  if self.xFrame == frame:
    return
  self.xFrame = frame
  self.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
  self.setNeedsDisplay(true)

method viewSetBounds(self: View, bounds: Rect): EmptyArgs {.selector.} =
  if self.xBounds == bounds:
    return
  self.xBounds = initRect(bounds.origin, bounds.size)
  self.setNeedsDisplay(true)

method viewSetHidden(self: View, hidden: bool): EmptyArgs {.selector.} =
  if self.xHidden == hidden:
    return
  self.xHidden = hidden
  self.setNeedsDisplay(true)

method viewSetBackgroundColor(self: View, color: Color): EmptyArgs {.selector.} =
  if self.xBackgroundColor == color:
    return
  self.xBackgroundColor = color
  self.setNeedsDisplay(true)

method viewRemoveFromSuperview(self: View): EmptyArgs {.selector.} =
  let parent = self.xSuperview
  if parent.isNil:
    return
  let idx = parent.xSubviews.find(self)
  if idx >= 0:
    parent.xSubviews.delete(idx)
    parent.setNeedsDisplay(true)
  self.xSuperview = nil
  self.clearNextResponder()

method viewAddSubview(self: View, child: View): EmptyArgs {.selector.} =
  if child.isNil:
    return
  if not child.xSuperview.isNil:
    child.removeFromSuperview()
  child.xSuperview = self
  self.xSubviews.add child
  child.setNextResponder(self)
  self.setNeedsDisplay(true)

method viewPointInside(self: View, point: Point): bool {.selector.} =
  self.xBounds.contains(point)

method viewHitTest(self: View, point: Point): View {.selector.} =
  if self.xHidden or not self.pointInside(point):
    return nil

  for idx in countdown(self.xSubviews.high, 0):
    let child = self.xSubviews[idx]
    let local = point.localPoint(child.frame)
    let hit = child.hitTest(local)
    if not hit.isNil:
      return hit

  self

proc installViewMethods(view: View) =
  discard view.replaceMethod(frame, viewFrame)
  discard view.replaceMethod(bounds, viewBounds)
  discard view.replaceMethod(isHidden, viewIsHidden)
  discard view.replaceMethod(needsDisplay, viewNeedsDisplay)
  discard view.replaceMethod(backgroundColor, viewBackgroundColor)
  discard view.replaceMethod(superview, viewSuperview)
  discard view.replaceMethod(subviews, viewSubviews)
  discard view.replaceMethod(setNeedsDisplay, viewSetNeedsDisplay)
  discard view.replaceMethod(setFrame, viewSetFrame)
  discard view.replaceMethod(setBounds, viewSetBounds)
  discard view.replaceMethod(setHidden, viewSetHidden)
  discard view.replaceMethod(setBackgroundColor, viewSetBackgroundColor)
  discard view.replaceMethod(removeFromSuperview, viewRemoveFromSuperview)
  discard view.replaceMethod(addSubview, viewAddSubview)
  discard view.replaceMethod(pointInside, viewPointInside)
  discard view.replaceMethod(hitTest, viewHitTest)

proc initViewFields*(view: View, frame: Rect) =
  initResponder(view)
  view.xFrame = frame
  view.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
  view.xNeedsDisplay = true
  view.xBackgroundColor = initColor(0.94, 0.95, 0.97, 1.0)
  view.installViewMethods()

proc newView*(frame: Rect): View =
  result = View()
  initViewFields(result, frame)

proc newView*(x, y, width, height: float32): View =
  newView(initRect(x, y, width, height))

proc frame*(view: View): Rect =
  view.send(frame, ())

proc bounds*(view: View): Rect =
  view.send(bounds, ())

proc isHidden*(view: View): bool =
  view.send(isHidden, ())

proc needsDisplay*(view: View): bool =
  view.send(needsDisplay, ())

proc backgroundColor*(view: View): Color =
  view.send(backgroundColor, ())

proc superview*(view: View): View =
  view.xSuperview

proc subviews*(view: View): seq[View] =
  view.xSubviews

proc setNeedsDisplay*(view: View, value: bool) =
  discard view.send(setNeedsDisplay, value)

proc setFrame*(view: View, frame: Rect) =
  discard view.send(setFrame, frame)

proc setBounds*(view: View, bounds: Rect) =
  discard view.send(setBounds, bounds)

proc setHidden*(view: View, hidden: bool) =
  discard view.send(setHidden, hidden)

proc setBackgroundColor*(view: View, color: Color) =
  discard view.send(setBackgroundColor, color)

proc removeFromSuperview*(view: View) =
  discard view.send(removeFromSuperview, ())

proc addSubview*(view, child: View) =
  discard view.send(addSubview, child)

proc pointInside*(view: View, point: Point): bool =
  view.send(pointInside, point)

proc hitTest*(view: View, point: Point): View =
  view.send(hitTest, point)

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
