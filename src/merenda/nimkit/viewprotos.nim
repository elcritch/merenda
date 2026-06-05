import ./selectors
import ./theme
import ./types
import ./viewgeometry
import ./viewbase

protocol ViewProtocolInternal from View:
  property frame -> Rect
  property bounds -> Rect
  property needsDisplay -> bool
  property backgroundColor -> Color
  property clipsToBounds -> bool
  property nextKeyView -> View
  property previousKeyView -> View

  method frame(self: View): Rect =
    if self.isNil:
      return
    self.xFrame

  method setFrame(self: View, frame: Rect) =
    let nextFrame = self.resolvedFrame(frame)
    if frame.hasAutoMetric:
      self.autoresizingMaskConstraints = false
    if self.xFrame == nextFrame:
      return
    self.xFrame = nextFrame
    self.xBounds = initRect(self.xBounds.origin, nextFrame.size)
    self.invalidateLayoutItemGeometry(lirFrame)
    self.refreshAutoresizingReference()
    self.notifyAutoresizingDependentsChanged()
    self.setNeedsDisplay(true)

  method bounds(self: View): Rect =
    if self.isNil:
      return
    self.xBounds

  method setBounds(self: View, bounds: Rect) =
    if self.xBounds == bounds:
      return
    self.xBounds = initRect(bounds.origin, bounds.size)
    self.notifyLayoutInputChanged(lirBounds)
    self.notifyAutoresizingDependentsChanged()
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

  method clipsToBounds(self: View): bool =
    self.xClipsToBounds

  method setClipsToBounds(self: View, clipsToBounds: bool) =
    if self.xClipsToBounds == clipsToBounds:
      return
    self.xClipsToBounds = clipsToBounds
    self.setNeedsDisplaySubtree()

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
    self.invalidateLayoutItemGeometry(lirHidden)
    self.setNeedsDisplay(true)

  method isHiddenOrHasHiddenAncestor*(self: View): bool =
    var current = self
    while not current.isNil:
      if current.xHidden:
        return true
      current = current.xSuperview
    false

  method visibleRect*(self: View): Rect =
    if self.isNil or self.isHiddenOrHasHiddenAncestor():
      return
    result = self.xBounds
    var ancestor = self.xSuperview
    while not ancestor.isNil:
      if ancestor.xClipsToBounds:
        result = result.intersection(self.rectFromView(ancestor.xBounds, ancestor))
        if result.isEmpty:
          return
      ancestor = ancestor.xSuperview

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
      self.notifyLayoutInputChanged(lirSuperview)
      parent.notifyLayoutInputChanged(lirHierarchy)
      parent.setNeedsDisplayInRect(self.rectToView(self.bounds, parent))
    self.xSuperview = nil
    self.resetAutoresizingState()
    self.clearNextResponder()
    self.setNextKeyView(nil)
    self.setPreviousKeyView(nil)
    self.setWindowOwner(nil)
    self.clearInheritedAppearance()
    self.notifyDidMoveToSuperview()
    if oldWindow != nil:
      self.notifyDidMoveToWindow()
    self.notifyLayoutInputChanged(lirSuperview)

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
    child.refreshAutoresizingReference()
    self.xSubviews.add child
    child.setNextResponder(self)
    child.setWindowOwner(self.xWindow)
    child.setInheritedAppearance(self.effectiveAppearance())
    self.notifyDidAddSubview(child)
    child.notifyDidMoveToSuperview()
    if oldWindow != self.xWindow:
      child.notifyDidMoveToWindow()
    child.notifyLayoutInputChanged(lirSuperview)
    self.notifyLayoutInputChanged(lirHierarchy)
    self.setNeedsDisplayInRect(child.rectToView(child.bounds, self))

  method pointInside*(self: View, point: Point): bool =
    self.xBounds.contains(point)

  method hitTestLevel*(self: View, point: Point): int =
    DefaultDrawLevel.int

  method hitTest*(self: View, point: Point): View =
    if self.xHidden:
      return nil

    let inside = self.pointInside(point)
    if inside or not self.xClipsToBounds:
      var
        bestHit: View
        bestLevel = low(int)
      for idx in countdown(self.xSubviews.high, 0):
        let child = self.xSubviews[idx]
        let local = child.pointFromView(point, self)
        let hit = child.hitTest(local)
        if not hit.isNil:
          let
            hitLocal = hit.pointFromView(point, self)
            level = max(child.hitTestLevel(local), hit.hitTestLevel(hitLocal))
          if bestHit.isNil or level > bestLevel:
            bestHit = hit
            bestLevel = level
      if not bestHit.isNil:
        return bestHit

    if inside: self else: nil

protocol ViewLifecycleProtocolInternal:
  method viewWillMoveToSuperview*(superview: View) {.optional.}
  method viewDidMoveToSuperview*() {.optional.}
  method viewWillMoveToWindow*(window: Responder) {.optional.}
  method viewDidMoveToWindow*() {.optional.}
  method didAddSubview*(subview: View) {.optional.}
  method willRemoveSubview*(subview: View) {.optional.}

proc `frame=`*(view: View, frame: Rect) =
  view.setFrame(frame)

proc `bounds=`*(view: View, bounds: Rect) =
  view.setBounds(bounds)

proc `needsDisplay=`*(view: View, value: bool) =
  view.setNeedsDisplay(value)

proc background*(view: View): Color =
  view.backgroundColor()

proc `background=`*(view: View, color: Color) =
  view.setBackgroundColor(color)

proc `backgroundColor=`*(view: View, color: Color) =
  view.setBackgroundColor(color)

proc `clipsToBounds=`*(view: View, clipsToBounds: bool) =
  view.setClipsToBounds(clipsToBounds)

proc `nextKeyView=`*(view: View, next: View) =
  view.setNextKeyView(next)

proc `previousKeyView=`*(view: View, previous: View) =
  view.setPreviousKeyView(previous)

proc hidden*(view: View): bool =
  view.isHidden()

proc `hidden=`*(view: View, hidden: bool) =
  view.setHidden(hidden)

proc setNeedsDisplaySubtree*(view: View) =
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
  view.invalidateIntrinsicContentSizeSubtree()
  view.setNeedsDisplaySubtree()

proc `appearance=`*(view: View, appearance: Appearance) =
  view.setAppearance(appearance)

proc clearAppearance*(view: View) =
  if view.isNil or not view.xHasAppearance:
    return
  view.xAppearance = Appearance()
  view.xHasAppearance = false
  view.invalidateIntrinsicContentSizeSubtree()
  view.setNeedsDisplaySubtree()

proc assignInheritedAppearance(view: View, appearance: Appearance) =
  view.xInheritedAppearance = appearance
  view.xHasInheritedAppearance = true
  view.invalidateIntrinsicContentSize()
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
  view.invalidateIntrinsicContentSize()
  for child in view.xSubviews:
    child.clearInheritedAppearance()
  view.setNeedsDisplay(true)

proc notifyWillMoveToSuperview*(view, superview: View) =
  discard view.sendIfHandled(viewWillMoveToSuperview(), superview)

proc notifyDidMoveToSuperview*(view: View) =
  discard view.sendIfHandled(viewDidMoveToSuperview())

proc notifyWillMoveToWindow*(view: View, window: Responder) =
  discard view.sendIfHandled(viewWillMoveToWindow(), window)
  for child in view.xSubviews:
    child.notifyWillMoveToWindow(window)

proc notifyDidMoveToWindow*(view: View) =
  discard view.sendIfHandled(viewDidMoveToWindow())
  for child in view.xSubviews:
    child.notifyDidMoveToWindow()

proc notifyDidAddSubview*(view, subview: View) =
  discard view.sendIfHandled(didAddSubview(), subview)

proc notifyWillRemoveSubview*(view, subview: View) =
  discard view.sendIfHandled(willRemoveSubview(), subview)

proc setWindowOwner*(view: View, window: Responder) =
  view.xWindow = window
  for child in view.xSubviews:
    child.setWindowOwner(window)

proc addSubview*(view: View, first, second: View, rest: varargs[View]) =
  view.addSubview(first)
  view.addSubview(second)
  for child in rest:
    view.addSubview(child)

let
  ViewProtocol* = ViewProtocolInternal
  ViewLifecycleProtocol* = ViewLifecycleProtocolInternal
