import ./responders
import ./selectors
import ./theme
import ./types

export responders

type View* = ref object of Responder
  xFrame: Rect
  xBounds: Rect
  xHidden: bool
  xNeedsDisplay: bool
  xInvalidRects: seq[Rect]
  xBackgroundColor: Color
  xAppearance: Appearance
  xHasAppearance: bool
  xInheritedAppearance: Appearance
  xHasInheritedAppearance: bool
  xStyleId: string
  xStyleClasses: seq[string]
  xHovered: bool
  xActive: bool
  xNeedsLayout: bool
  xNextKeyView: View
  xPreviousKeyView: View
  xSuperview: View
  xWindow: Responder
  xSubviews: seq[View]

proc pointFromView*(view: View, point: Point, fromView: View): Point
proc pointToView*(view: View, point: Point, toView: View): Point
proc rectFromView*(view: View, rect: Rect, fromView: View): Rect
proc rectToView*(view: View, rect: Rect, toView: View): Rect
proc pointFromWindow*(view: View, point: Point): Point
proc pointToWindow*(view: View, point: Point): Point
proc rectFromWindow*(view: View, rect: Rect): Rect
proc rectToWindow*(view: View, rect: Rect): Rect
proc notifyWillMoveToSuperview(view, superview: View)
proc notifyDidMoveToSuperview(view: View)
proc notifyWillMoveToWindow(view: View, window: Responder)
proc notifyDidMoveToWindow(view: View)
proc notifyDidAddSubview(view, subview: View)
proc notifyWillRemoveSubview(view, subview: View)
proc setWindowOwner(view: View, window: Responder)
proc setNeedsLayout*(view: View, value: bool)
proc setNeedsDisplaySubtree(view: View)
proc viewCanBecomeKeyView*(view: View): bool
proc effectiveAppearance*(view: View): Appearance
proc setInheritedAppearance*(view: View, appearance: Appearance)
proc clearInheritedAppearance*(view: View)

protocol ViewProtocolInternal from View:
  property frame -> Rect
  property bounds -> Rect
  property needsDisplay -> bool
  property backgroundColor -> Color
  property nextKeyView -> View
  property previousKeyView -> View

  method frame(self: View): Rect =
    self.xFrame

  method setFrame(self: View, frame: Rect) =
    if self.xFrame == frame:
      return
    self.xFrame = frame
    self.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
    self.setNeedsLayout(true)
    self.setNeedsDisplay(true)

  method bounds(self: View): Rect =
    self.xBounds

  method setBounds(self: View, bounds: Rect) =
    if self.xBounds == bounds:
      return
    self.xBounds = initRect(bounds.origin, bounds.size)
    self.setNeedsLayout(true)
    self.setNeedsDisplay(true)

  method needsDisplay(self: View): bool =
    self.xNeedsDisplay

  method setNeedsDisplay(self: View, value: bool) =
    if not value:
      self.xNeedsDisplay = false
      self.xInvalidRects.setLen(0)
      return

    self.xNeedsDisplay = true
    self.xInvalidRects.setLen(0)
    let parent = self.xSuperview
    if not parent.isNil:
      parent.setNeedsDisplayInRect(self.rectToView(self.bounds, parent))

  method setNeedsDisplayInRect*(self: View, rect: Rect) =
    let clipped = rect.intersection(self.visibleRect())
    if clipped.isEmpty:
      return

    if not self.xNeedsDisplay:
      self.xNeedsDisplay = true
      self.xInvalidRects = @[clipped]
    elif self.xInvalidRects.len > 0:
      self.xInvalidRects[0] = self.xInvalidRects[0].union(clipped)
      self.xInvalidRects.setLen(1)

    let parent = self.xSuperview
    if not parent.isNil:
      parent.setNeedsDisplayInRect(self.rectToView(clipped, parent))

  method invalidRect*(self: View): Rect =
    if not self.xNeedsDisplay:
      return initRect(0.0, 0.0, 0.0, 0.0)
    if self.xInvalidRects.len == 0:
      return self.visibleRect()
    result = self.xInvalidRects[0]
    for idx in 1 ..< self.xInvalidRects.len:
      result = result.union(self.xInvalidRects[idx])

  method invalidRects*(self: View): seq[Rect] =
    if not self.xNeedsDisplay:
      return @[]
    if self.xInvalidRects.len == 0:
      return @[self.visibleRect()]
    self.xInvalidRects

  method backgroundColor(self: View): Color =
    self.xBackgroundColor

  method setBackgroundColor(self: View, color: Color) =
    if self.xBackgroundColor == color:
      return
    self.xBackgroundColor = color
    self.setNeedsDisplay(true)

  method nextKeyView(self: View): View =
    self.xNextKeyView

  method setNextKeyView(self: View, next: View) =
    if self.isNil or self.xNextKeyView == next:
      return

    let oldNext = self.xNextKeyView
    if not oldNext.isNil and oldNext.xPreviousKeyView == self:
      oldNext.xPreviousKeyView = nil

    self.xNextKeyView = next
    if not next.isNil:
      let oldPrevious = next.xPreviousKeyView
      if not oldPrevious.isNil and oldPrevious != self and
          oldPrevious.xNextKeyView == next:
        oldPrevious.xNextKeyView = nil
      next.xPreviousKeyView = self

  method previousKeyView(self: View): View =
    self.xPreviousKeyView

  method setPreviousKeyView(self: View, previous: View) =
    if self.isNil or self.xPreviousKeyView == previous:
      return
    if previous.isNil:
      let oldPrevious = self.xPreviousKeyView
      if not oldPrevious.isNil and oldPrevious.xNextKeyView == self:
        oldPrevious.xNextKeyView = nil
      self.xPreviousKeyView = nil
      return
    previous.setNextKeyView(self)

  method canBecomeKeyView*(self: View): bool =
    self.viewCanBecomeKeyView()

  method nextValidKeyView*(self: View): View =
    var candidate = self.nextKeyView()
    var hopCount = 0
    while not candidate.isNil and hopCount < 4096:
      if candidate == self:
        if candidate.canBecomeKeyView():
          return candidate
        return nil
      if candidate.canBecomeKeyView():
        return candidate
      candidate = candidate.nextKeyView()
      inc hopCount

  method previousValidKeyView*(self: View): View =
    var candidate = self.previousKeyView()
    var hopCount = 0
    while not candidate.isNil and hopCount < 4096:
      if candidate == self:
        if candidate.canBecomeKeyView():
          return candidate
        return nil
      if candidate.canBecomeKeyView():
        return candidate
      candidate = candidate.previousKeyView()
      inc hopCount

  method isHidden*(self: View): bool =
    self.xHidden

  method setHidden*(self: View, hidden: bool) =
    if self.xHidden == hidden:
      return
    self.xHidden = hidden
    self.setNeedsLayout(true)
    self.setNeedsDisplay(true)

  method isHiddenOrHasHiddenAncestor*(self: View): bool =
    var current = self
    while not current.isNil:
      if current.xHidden:
        return true
      current = current.xSuperview
    false

  method visibleRect*(self: View): Rect =
    if self.isHiddenOrHasHiddenAncestor():
      return initRect(0.0, 0.0, 0.0, 0.0)
    let parent = self.xSuperview
    if parent.isNil:
      return self.xBounds
    let parentVisible = parent.visibleRect()
    let converted = self.rectFromView(parentVisible, parent)
    converted.intersection(self.xBounds)

  method superview*(self: View): View =
    self.xSuperview

  method window*(self: View): Responder =
    self.xWindow

  method subviews*(self: View): seq[View] =
    self.xSubviews

  method removeFromSuperview*(self: View) =
    let parent = self.xSuperview
    if parent.isNil:
      return
    let oldWindow = self.xWindow
    parent.notifyWillRemoveSubview(self)
    self.notifyWillMoveToSuperview(nil)
    if oldWindow != nil:
      self.notifyWillMoveToWindow(nil)
    let idx = parent.xSubviews.find(self)
    if idx >= 0:
      parent.xSubviews.delete(idx)
      parent.setNeedsLayout(true)
      parent.setNeedsDisplayInRect(self.rectToView(self.bounds, parent))
    self.xSuperview = nil
    self.clearNextResponder()
    self.setNextKeyView(nil)
    self.setPreviousKeyView(nil)
    self.setWindowOwner(nil)
    self.clearInheritedAppearance()
    self.notifyDidMoveToSuperview()
    if oldWindow != nil:
      self.notifyDidMoveToWindow()

  method addSubview*(self: View, child: View) =
    if child.isNil:
      return
    if not child.xSuperview.isNil:
      child.removeFromSuperview()
    let oldWindow = child.xWindow
    child.notifyWillMoveToSuperview(self)
    if oldWindow != self.xWindow:
      child.notifyWillMoveToWindow(self.xWindow)
    child.xSuperview = self
    self.xSubviews.add child
    child.setNextResponder(self)
    child.setWindowOwner(self.xWindow)
    child.setInheritedAppearance(self.effectiveAppearance())
    self.notifyDidAddSubview(child)
    child.notifyDidMoveToSuperview()
    if oldWindow != self.xWindow:
      child.notifyDidMoveToWindow()
    self.setNeedsLayout(true)
    child.setNeedsLayout(true)
    self.setNeedsDisplayInRect(child.rectToView(child.bounds, self))

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

protocol ViewLifecycleProtocolInternal:
  method viewWillMoveToSuperview*(superview: View) {.optional.}
  method viewDidMoveToSuperview*() {.optional.}
  method viewWillMoveToWindow*(window: Responder) {.optional.}
  method viewDidMoveToWindow*() {.optional.}
  method didAddSubview*(subview: View) {.optional.}
  method willRemoveSubview*(subview: View) {.optional.}

proc setNeedsDisplaySubtree(view: View) =
  if view.isNil:
    return
  view.setNeedsDisplay(true)
  for child in view.xSubviews:
    child.setNeedsDisplaySubtree()

proc viewCanBecomeKeyView*(view: View): bool =
  (not view.isNil) and view.acceptsFirstResponder() and
    not view.isHiddenOrHasHiddenAncestor()

proc hasAppearance*(view: View): bool =
  (not view.isNil) and view.xHasAppearance

proc appearance*(view: View): Appearance =
  if view.isNil or not view.xHasAppearance:
    return initAppearance()
  view.xAppearance

proc effectiveAppearance*(view: View): Appearance =
  if view.isNil:
    return initAppearance()
  if view.xHasAppearance:
    return view.xAppearance
  if not view.xSuperview.isNil:
    return view.xSuperview.effectiveAppearance()
  if view.xHasInheritedAppearance:
    return view.xInheritedAppearance
  initAppearance()

proc resolvedAppearance*(view: View, inherited: Appearance): Appearance =
  if view.isNil:
    return inherited
  if view.xHasAppearance:
    return view.xAppearance
  if view.xHasInheritedAppearance and view.xSuperview.isNil:
    return view.xInheritedAppearance
  inherited

proc setAppearance*(view: View, appearance: Appearance) =
  if view.isNil:
    return
  view.xAppearance = appearance
  view.xHasAppearance = true
  view.setNeedsDisplaySubtree()

proc clearAppearance*(view: View) =
  if view.isNil or not view.xHasAppearance:
    return
  view.xAppearance = Appearance()
  view.xHasAppearance = false
  view.setNeedsDisplaySubtree()

proc assignInheritedAppearance(view: View, appearance: Appearance) =
  view.xInheritedAppearance = appearance
  view.xHasInheritedAppearance = true
  for child in view.xSubviews:
    child.assignInheritedAppearance(appearance)

proc setInheritedAppearance*(view: View, appearance: Appearance) =
  if view.isNil:
    return
  view.assignInheritedAppearance(appearance)
  view.setNeedsDisplaySubtree()

proc clearInheritedAppearance*(view: View) =
  if view.isNil:
    return
  view.xInheritedAppearance = Appearance()
  view.xHasInheritedAppearance = false
  for child in view.xSubviews:
    child.clearInheritedAppearance()
  view.setNeedsDisplay(true)

proc styleId*(view: View): string =
  if view.isNil: "" else: view.xStyleId

proc setStyleId*(view: View, id: string) =
  if view.isNil or view.xStyleId == id:
    return
  view.xStyleId = id
  view.setNeedsDisplay(true)

proc styleClasses*(view: View): seq[string] =
  if view.isNil:
    @[]
  else:
    view.xStyleClasses

proc setStyleClasses*(view: View, classes: openArray[string]) =
  if view.isNil:
    return
  let nextClasses = @classes
  if view.xStyleClasses == nextClasses:
    return
  view.xStyleClasses = nextClasses
  view.setNeedsDisplay(true)

proc hasStyleClass*(view: View, className: string): bool =
  (not view.isNil) and view.xStyleClasses.find(className) >= 0

proc addStyleClass*(view: View, className: string) =
  if view.isNil or view.hasStyleClass(className):
    return
  view.xStyleClasses.add className
  view.setNeedsDisplay(true)

proc removeStyleClass*(view: View, className: string) =
  if view.isNil:
    return
  let idx = view.xStyleClasses.find(className)
  if idx < 0:
    return
  view.xStyleClasses.delete(idx)
  view.setNeedsDisplay(true)

proc isHovered*(view: View): bool =
  (not view.isNil) and view.xHovered

proc setHovered*(view: View, hovered: bool) =
  if view.isNil or view.xHovered == hovered:
    return
  view.xHovered = hovered
  view.setNeedsDisplay(true)

proc isActive*(view: View): bool =
  (not view.isNil) and view.xActive

proc setActive*(view: View, active: bool) =
  if view.isNil or view.xActive == active:
    return
  view.xActive = active
  view.setNeedsDisplay(true)

proc needsLayout*(view: View): bool =
  (not view.isNil) and view.xNeedsLayout

proc setNeedsLayout*(view: View, value: bool) =
  if view.isNil:
    return
  view.xNeedsLayout = value

proc setNeedsLayout*(view: View) =
  view.setNeedsLayout(true)

proc layoutSubtreeIfNeeded*(view: View) =
  if view.isNil:
    return
  if view.xNeedsLayout:
    view.xNeedsLayout = false
    discard view.sendIfHandled(layoutSubviews())
    discard view.sendIfHandled(layout())
  for child in view.xSubviews:
    child.layoutSubtreeIfNeeded()

proc dirtyRects*(view: View): seq[Rect] =
  if view.isNil:
    @[]
  else:
    view.invalidRects()

proc needsDisplayInSubtree*(view: View): bool =
  if view.isNil:
    return false
  if view.needsDisplay:
    return true
  for child in view.xSubviews:
    if child.needsDisplayInSubtree():
      return true
  false

proc prepareDisplaySubtree*(view: View): bool =
  if view.isNil:
    return false
  view.layoutSubtreeIfNeeded()
  view.needsDisplayInSubtree()

proc finishDisplaySubtree*(view: View) =
  if view.isNil:
    return
  view.setNeedsDisplay(false)
  for child in view.xSubviews:
    child.finishDisplaySubtree()

proc notifyWillMoveToSuperview(view, superview: View) =
  discard view.sendIfHandled(viewWillMoveToSuperview(), superview)

proc notifyDidMoveToSuperview(view: View) =
  discard view.sendIfHandled(viewDidMoveToSuperview())

proc notifyWillMoveToWindow(view: View, window: Responder) =
  discard view.sendIfHandled(viewWillMoveToWindow(), window)
  for child in view.xSubviews:
    child.notifyWillMoveToWindow(window)

proc notifyDidMoveToWindow(view: View) =
  discard view.sendIfHandled(viewDidMoveToWindow())
  for child in view.xSubviews:
    child.notifyDidMoveToWindow()

proc notifyDidAddSubview(view, subview: View) =
  discard view.sendIfHandled(didAddSubview(), subview)

proc notifyWillRemoveSubview(view, subview: View) =
  discard view.sendIfHandled(willRemoveSubview(), subview)

proc setWindowOwner(view: View, window: Responder) =
  view.xWindow = window
  for child in view.xSubviews:
    child.setWindowOwner(window)

proc moveToWindowOwner*(view: View, window: Responder) =
  if view.isNil or view.xWindow == window:
    return
  view.notifyWillMoveToWindow(window)
  view.setWindowOwner(window)
  view.notifyDidMoveToWindow()

proc clearSuperviewForWindowOwner*(view: View) =
  if view.isNil:
    return
  view.xSuperview = nil
  view.clearNextResponder()

proc containsView*(view, candidate: View): bool =
  if view.isNil or candidate.isNil:
    return false
  if view == candidate:
    return true
  for child in view.xSubviews:
    if child.containsView(candidate):
      return true
  false

proc initViewFields*(view: View, frame: Rect) =
  initResponder(view)
  view.xFrame = frame
  view.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
  view.xNeedsDisplay = true
  view.xNeedsLayout = true
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

proc handleMouseDown*(view: View, event: MouseEvent): bool =
  view.sendLocalIfHandled(mouseDown(), event)

proc handleMouseUp*(view: View, event: MouseEvent): bool =
  view.sendLocalIfHandled(mouseUp(), event)

proc handleMouseEntered*(view: View, event: MouseEvent): bool =
  view.sendLocalIfHandled(mouseEntered(), event)

proc handleMouseExited*(view: View, event: MouseEvent): bool =
  view.sendLocalIfHandled(mouseExited(), event)

proc handleMouseMoved*(view: View, event: MouseEvent): bool =
  view.sendLocalIfHandled(mouseMoved(), event)

proc handleMouseDragged*(view: View, event: MouseEvent): bool =
  view.sendLocalIfHandled(mouseDragged(), event)

proc handleScrollWheel*(view: View, event: ScrollEvent): bool =
  view.sendLocalIfHandled(scrollWheel(), event)

proc handleKeyDown*(view: View, event: KeyEvent): bool =
  view.sendLocalIfHandled(keyDown(), event)

proc clearNeedsDisplayTree*(view: View) =
  view.finishDisplaySubtree()

proc clickAt*(view: View, point: Point): bool =
  let hit = view.hitTest(point)
  if hit.isNil:
    return false

  let event = MouseEvent(
    location: hit.pointFromView(point, view), button: mbPrimary, clickCount: 1
  )
  discard hit.handleMouseDown(event)
  result = hit.handleMouseUp(event)

let
  ViewProtocol* = ViewProtocolInternal
  ViewLifecycleProtocol* = ViewLifecycleProtocolInternal
