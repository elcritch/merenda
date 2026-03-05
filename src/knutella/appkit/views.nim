import std/sequtils

import ./runtime
import ./responders
import ./graphics
import ./colors
import ./trackingareas

export responders

proc isViewDescendantOf*(viewId: IDPtr, ancestorId: IDPtr): bool
proc detachSubviews*(view: NSObject)
proc isHiddenOrHasHiddenAncestor*(view: NSView): bool
proc convertPoint*(self: NSView, point: NSPoint, fromView: NSView): NSPoint
proc convertPointToView*(self: NSView, point: NSPoint, toView: NSView): NSPoint
proc convertRect*(self: NSView, rect: NSRect, fromView: NSView): NSRect
proc convertRectToView*(self: NSView, rect: NSRect, toView: NSView): NSRect
proc addSubview*(self: NSView, view: NSView)
proc removeFromSuperviewWithoutNeedingDisplay*(view: NSView)
proc removeFromSuperview*(view: NSView)
method xInvalidateTrackingAreas*(self: NSWindow) {.base.} =
  discard

method invalidateCursorRectsForView*(self: NSWindow, view: NSView) {.base.} =
  discard

proc markTransformsDirty(view: NSView)

objcImpl:
  type ClipViewWrapper* {.structural.} =
    concept self
        method documentView*(self: ClipViewWrapper): NSView
        method documentVisibleRect*(self: ClipViewWrapper): NSRect
        method scrollToPoint*(self: ClipViewWrapper, point: NSPoint)

template unionOfInvalidRects*(self: NSView): NSRect =
  ##
  ##   If _needsDisplay is YES and there are no _invalidRects, invalid rect is bounds
  ##   If _needsDisplay is YES and there are _invalidRects, invalid rect is union
  ##   You can't just keep a running invalid rect because setting YES then changing the
  ##   bounds should redraw the new bounds, but changing the bounds should not alter the
  ##   invalidated rects.
  ##

  block:
    var result: NSRect
    if self.xInvalidRects.len == 0:
      result = self.visibleRect()
    else:
      result = self.xInvalidRects[0]
      for i in 1 ..< self.xInvalidRects.len:
        result = nsUnionRect(result, self.xInvalidRects[i])
    result

objcImpl:
  type NSView* = object of NSResponder
    xFrame {.get: frame.}: NSRect
    xBounds {.get: bounds.}: NSRect
    xWindow {.get: window.}: NSWindow
    xMenu {.get: menu, set: setMenu.}: NSMenu
    xSuperview {.get: superview.}: NSView
    xSubviews {.get: subviews.}: seq[NSView]
    xNextKeyView {.get: nextKeyView.}: NSView
    xPreviousKeyView {.get: previousKeyView.}: NSView

    xHidden {.get: isHidden.}: bool
    xBackgroundColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor

    xPostsNotificationOnFrameChange {.
      set: setPostsFrameChangedNotifications, get: postsFrameChangedNotifications
    .}: bool
    xPostsNotificationOnBoundsChange {.
      set: setPostsBoundsChangedNotifications, get: postsBoundsChangedNotifications
    .}: bool

    xAutoresizesSubviews {.set: setAutoresizesSubviews, get: autoresizesSubviews.}: bool
    xAutoresizingMask {.set: setAutoresizingMask, get: autoresizingMask.}: int

    xTag {.set: setTag, get: tag.}: int
    xDraggedTypes: seq[ID]
    xTrackingAreas: seq[NSTrackingArea]
    xNeedsDisplay {.get: needsDisplay.}: bool
    xInvalidRects: seq[NSRect]
    xRectsBeingRedrawn: seq[NSRect]

    xFrameRotation: float32
    xBoundsRotation: float32

    xValidTrackingAreas: bool
    xValidTransforms: bool

    xTransformFromWindow: AffineTransformation
    xTransformToWindow: AffineTransformation
    xTransformToLayer: AffineTransformation

    xVisibleRect: NSRect
    xFocusRingType: NSFocusRingType

    xWantsLayer: bool
    # xLayer: CALayer
    # xCompositingFilter: CIFilter 
    # xContentFilters: NSArray
    xShadow: NSShadow
    # xAnimations: NSDictionary[NSString, NSAnimation]
    xAlpha {.set: setAlphaValue, get: alphaValue.}: float32

    #xLayerContext: CALayerContext 

  method initWithFrame*(self: var NSView, rect: NSRect): NSView =
    result = asTypeRaw[NSView](callSuperIdFrom(NSView, self, getSelector("init")))
    if result.isNil:
      return
    result.xFrame = rect
    result.xBounds =
      nsRect(0.0, 0.0, max(rect.size.width, 0.0), max(rect.size.height, 0.0))
    result.xBackgroundColor = nsColor(0.86, 0.90, 0.96, 1.0)
    result.xPostsNotificationOnFrameChange = true
    result.xPostsNotificationOnBoundsChange = true
    result.xAutoresizesSubviews = true
    result.xAlpha = 1.0
    result.xTag = -1
    result.xNeedsDisplay = true

  method init*(self: var NSView): NSView =
    self.initWithFrame(nsRect(0, 0, 1, 1))

  method setFrame*(self: NSView, frame: NSRect) =
    if self.xFrame == frame:
      return

    let oldSize = self.xBounds.size

    if self.xBounds.size.width == 0 or self.xBounds.size.height == 0:
      self.xBounds.size = frame.size
    else:
      self.xBounds.size = frame.size

    self.xFrame = frame
    if self.xAutoresizesSubviews:
      self.resizeSubviewsWithOldSize(oldSize)
    markTransformsDirty(self)
    self.window().invalidateCursorRectsForView(self)

  method frameOrigin*(self: NSView): NSPoint =
    self.xFrame.origin

  method frameSize*(self: NSView): NSSize =
    self.xFrame.size

  method setFrameSize*(self: NSView, size: NSSize) =
    var frame = self.xFrame
    frame.size = nsSize(max(size.width, 0.0), max(size.height, 0.0))
    self.setFrame(frame)

  method setFrameOrigin*(self: NSView, origin: NSPoint) =
    var frame = self.xFrame
    frame.origin = origin
    self.setFrame(frame)

  method setBounds*(self: NSView, bounds: NSRect) =
    let nextBounds = nsRect(
      bounds.origin.x,
      bounds.origin.y,
      max(bounds.size.width, 0.0),
      max(bounds.size.height, 0.0),
    )
    if self.xBounds == nextBounds:
      return
    self.xBounds = nextBounds
    markTransformsDirty(self)
    self.window().invalidateCursorRectsForView(self)
    if self.xPostsNotificationOnBoundsChange:
      self.xNeedsDisplay = true

  method setBounds*(
      self: NSView,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ) =
    self.setBounds(
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))
    )

  method boundsOrigin*(self: NSView): NSPoint =
    self.xBounds.origin

  method boundsSize*(self: NSView): NSSize =
    self.xBounds.size

  method setBoundsOrigin*(self: NSView, point: NSPoint) =
    var bounds = self.xBounds
    bounds.origin = point
    self.setBounds(bounds)

  method setBoundsSize*(self: NSView, size: NSSize) =
    var bounds = self.xBounds
    bounds.size = nsSize(max(size.width, 0.0), max(size.height, 0.0))
    self.setBounds(bounds)

  method isFlipped*(self: NSView): bool =
    false

  method isOpaque*(self: NSView): bool =
    false

  method adjustScroll*(self: NSView, toRect: NSRect): NSRect =
    nsRect(0, 0, 0, 0)

  method visibleRect*(self: NSView): NSRect =
    if self.isHiddenOrHasHiddenAncestor():
      return nsRect(0.0, 0.0, 0.0, 0.0)
    let parent = self.xSuperview
    if parent.isNil:
      return self.xBounds
    let parentVisible = parent.visibleRect()
    let converted = self.convertRect(parentVisible, parent)
    nsIntersectionRect(converted, self.xBounds)

  method canDraw*(self: NSView): bool =
    (not self.xWindow.isNil) and (not self.isHiddenOrHasHiddenAncestor())

  method viewWillDraw*(self: NSView) =
    for child in self.xSubviews:
      child.viewWillDraw()

  method xTrackingAreasChanged*(self: NSView) =
    self.window().xInvalidateTrackingAreas()

  method addTrackingArea*(self: NSView, trackingArea: NSTrackingArea) =
    self.xTrackingAreas.add(trackingArea)
    self.xTrackingAreasChanged()

  method removeTrackingArea*(self: NSView, trackingArea: NSTrackingArea) =
    var i = self.xTrackingAreas.high
    while i >= 0:
      if self.xTrackingAreas[i].value == trackingArea.value:
        self.xTrackingAreas.del(i)
      dec i
    self.xTrackingAreasChanged()

  method trackingAreas*(self: NSView): seq[NSTrackingArea] =
    self.xTrackingAreas

  method updateTrackingAreas*(self: NSView) =
    self.xValidTrackingAreas = false
    self.xTrackingAreasChanged()

  method registerForDraggedTypes*(self: NSView, types: seq[ID]) =
    self.xDraggedTypes = types

  method unregisterDraggedTypes*(self: NSView) =
    self.xDraggedTypes.setLen(0)

  method registeredDraggedTypes*(self: NSView): seq[ID] =
    self.xDraggedTypes

  method discardCursorRects*(self: NSView) =
    var areas = self.xTrackingAreas
    areas.keepItIf(
      not (it.isLegacy() and it.options().contains(NSTrackingCursorUpdate))
    )

    nsArray(self.subviews()).makeObjectsPerformSelector(@ns"discardCursorRects")
    self.xTrackingAreasChanged()

  method opaqueAncestor*(self: NSView): NSView =
    if self.isOpaque():
      return self
    let parent = self.xSuperview
    if parent.isNil:
      return self
    parent.opaqueAncestor()

  method setNeedsDisplayInRect*(self: NSView, rect: NSRect) =
    if not self.xNeedsDisplay or self.xInvalidRects.len > 0:
      let visible = self.visibleRect()
      let clipped = nsIntersectionRect(visible, rect)
      if isEmpty(clipped):
        return
      if nsContainsRect(clipped, visible):
        self.xInvalidRects.setLen(0)
      else:
        self.xInvalidRects.add(clipped)
      self.xRectsBeingRedrawn.setLen(0)

      let opaque = self.opaqueAncestor()
      if not opaque.isNil and opaque.value != self.value:
        let dirtyRect = self.convertRectToView(clipped, opaque)
        opaque.setNeedsDisplayInRect(dirtyRect)

    self.xNeedsDisplay = true

  method setNeedsDisplay*(self: NSView, flag: bool) =
    self.xNeedsDisplay = flag
    self.xInvalidRects.setLen(0)
    self.xRectsBeingRedrawn.setLen(0)

  method display*(self: NSView) =
    self.displayRect(self.visibleRect())

  method xDisplayIfNeededWithoutViewWillDraw*(self: NSView) =
    if self.xNeedsDisplay:
      self.displayRect(unionOfInvalidRects(self))
      self.setNeedsDisplay(false)

    for child in self.xSubviews:
      child.xDisplayIfNeededWithoutViewWillDraw()

  method displayIfNeeded*(self: NSView) =
    self.viewWillDraw()
    self.xDisplayIfNeededWithoutViewWillDraw()

  method displayIfNeededInRect*(self: NSView, rect: NSRect) =
    let dirty = nsIntersectionRect(unionOfInvalidRects(self), rect)
    if isEmpty(dirty):
      return
    if self.xNeedsDisplay:
      self.displayRect(dirty)
    for child in self.xSubviews:
      let childDirty = self.convertRectToView(dirty, child)
      let childDirtyInParent = nsIntersectionRect(childDirty, child.bounds())
      if isEmpty(childDirtyInParent):
        continue
      child.displayIfNeededInRect(childDirtyInParent)

  method displayIfNeededIgnoringOpacity*(self: NSView) =
    if self.xNeedsDisplay:
      self.displayRectIgnoringOpacity(unionOfInvalidRects(self))

    for child in self.xSubviews:
      child.displayIfNeededIgnoringOpacity()

  method displayIfNeededInRectIgnoringOpacity*(self: NSView, rect: NSRect) =
    let dirty = nsIntersectionRect(unionOfInvalidRects(self), rect)
    if isEmpty(dirty):
      return
    if self.xNeedsDisplay:
      self.displayRectIgnoringOpacity(dirty)
    for child in self.xSubviews:
      let childDirty = self.convertRectToView(dirty, child)
      let childDirtyInParent = nsIntersectionRect(childDirty, child.bounds())
      if isEmpty(childDirtyInParent):
        continue
      child.displayIfNeededInRectIgnoringOpacity(childDirtyInParent)

  method displayRect*(self: NSView, rect: NSRect) =
    let opaque = self.opaqueAncestor()
    if opaque.isNil or opaque.value == self.value:
      self.displayRectIgnoringOpacity(rect)
      return
    let converted = self.convertRectToView(rect, opaque)
    opaque.displayRectIgnoringOpacity(converted)

  method displayRectIgnoringOpacity*(self: NSView, rect: NSRect) =
    let visibleRect = self.visibleRect()
    let clipped = nsIntersectionRect(rect, visibleRect)

    if isEmpty(clipped) or not self.canDraw():
      return

    self.xRectsBeingRedrawn.setLen(0)
    if self.xInvalidRects.len == 0:
      self.xRectsBeingRedrawn.add(clipped)
    else:
      for r in self.xInvalidRects:
        let drawRect = nsIntersectionRect(r, visibleRect)
        if isEmpty(drawRect):
          continue
        self.xRectsBeingRedrawn.add(drawRect)
      if self.xRectsBeingRedrawn.len == 0:
        self.xRectsBeingRedrawn.add(clipped)

    self.drawRect(clipped)

    for child in self.xSubviews:
      if child.xHidden:
        continue
      let childFrame = child.frame()
      let childDirtyInParent = nsIntersectionRect(clipped, childFrame)
      if isEmpty(childDirtyInParent):
        continue
      let childBounds = child.bounds()
      let childDirty = nsRect(
        childBounds.origin.x + (childDirtyInParent.origin.x - childFrame.origin.x),
        childBounds.origin.y + (childDirtyInParent.origin.y - childFrame.origin.y),
        childDirtyInParent.size.width,
        childDirtyInParent.size.height,
      )
      child.displayRectIgnoringOpacity(childDirty)

    if self.xInvalidRects.len == 0:
      self.xNeedsDisplay = false
    else:
      var i = self.xInvalidRects.high
      while i >= 0:
        if nsContainsRect(clipped, self.xInvalidRects[i]):
          self.xInvalidRects.del(i)
        dec i
      self.xNeedsDisplay = self.xInvalidRects.len > 0
    self.xRectsBeingRedrawn.setLen(0)

  method displayRectIgnoringOpacity*(
      self: NSView, rect: NSRect, context {.kw("inContext").}: NSGraphicsContext
  ) =
    self.displayRectIgnoringOpacity(rect)

  method getRectsBeingDrawn*(
      self: NSView, rects: ptr ptr NSRect, count {.kw("count").}: ptr int
  ) =
    if rects.isNil or count.isNil:
      return
    if self.xRectsBeingRedrawn.len == 0:
      if self.xInvalidRects.len == 0:
        if self.xNeedsDisplay:
          self.xRectsBeingRedrawn = @[self.visibleRect()]
      else:
        self.xRectsBeingRedrawn = self.xInvalidRects
    if self.xRectsBeingRedrawn.len == 0:
      rects[] = nil
      count[] = 0
      return
    rects[] = cast[ptr NSRect](unsafeAddr self.xRectsBeingRedrawn[0])
    count[] = self.xRectsBeingRedrawn.len

  method needsToDrawRect*(self: NSView, rect: NSRect): bool =
    if not nsIntersectsRect(rect, self.visibleRect()):
      return false
    var rectsPtr: ptr NSRect = nil
    var rectCount = 0
    self.getRectsBeingDrawn(addr rectsPtr, addr rectCount)
    if rectCount <= 0 or rectsPtr.isNil:
      return false
    let rects = cast[ptr UncheckedArray[NSRect]](rectsPtr)
    for i in 0 ..< rectCount:
      if nsIntersectsRect(rect, rects[i]):
        return true
    false

  method drawRect*(self: NSView, rect: NSRect) =
    let color = self.xBackgroundColor
    if color.a <= 0.0:
      return
    color.setFill()
    if rect.size.width > 0.0 and rect.size.height > 0.0:
      NSRectFill(rect)
    else:
      NSRectFill(self.bounds())

  method wantsClipToBounds*(self: NSView): bool =
    false

  method drawSheetBorderWithSize*(self: NSView, size: NSSize) =
    discard

  method drawPageBorderWithSize*(self: NSView, size: NSSize) =
    discard

  method didAddSubview*(self: NSView, subview: NSView) =
    discard

  method willRemoveSubview*(self: NSView, subview: NSView) =
    discard

  method viewWillMoveToSuperview*(self: NSView, view: NSView) =
    discard

  method viewDidMoveToSuperview*(self: NSView) =
    discard

  method viewWillMoveToWindow*(self: NSView, window: NSWindow) =
    discard

  method viewDidMoveToWindow*(self: NSView) =
    discard

  method setWindow*(self: NSView, window: NSWindow) =
    if self.xWindow.value == window.value:
      return
    self.viewWillMoveToWindow(window)
    self.xWindow = window
    for child in self.xSubviews:
      child.setWindow(window)
    self.xValidTrackingAreas = false
    self.window().invalidateCursorRectsForView(self)
    self.viewDidMoveToWindow()

  method xSetSuperview*(self: NSView, superview: NSView) =
    self.xSuperview = superview
    if superview.isNil:
      self.setNextResponder(NSResponder(value: nil))
    else:
      self.setNextResponder(superview.NSResponder)
    self.window().invalidateCursorRectsForView(self)

  method setSubviews*(self: NSView, array: seq[NSView]) =
    while self.xSubviews.len > 0:
      let child = self.xSubviews[self.xSubviews.high]
      child.removeFromSuperview()
    for view in array:
      self.addSubview(view)
      if not view.isNil:
        view.setNeedsDisplay(true)

  method setHidden*(self: NSView, hidden: bool) =
    if self.xHidden == hidden:
      return
    self.xHidden = hidden
    if hidden:
      self.viewDidHide()
    else:
      self.viewDidUnhide()
      self.setNeedsDisplay(true)
    self.window().invalidateCursorRectsForView(self)

  method viewDidHide*(self: NSView) =
    discard

  method viewDidUnhide*(self: NSView) =
    discard

  method setNextKeyView*(self: NSView, next: NSView) =
    if not next.isNil:
      next.xPreviousKeyView = self
    elif not self.xNextKeyView.isNil:
      self.xNextKeyView.xPreviousKeyView = NSView(value: nil)
    self.xNextKeyView = next

  method canBecomeKeyView*(self: NSView): bool =
    not self.isHiddenOrHasHiddenAncestor()

  method needsPanelToBecomeKey*(self: NSView): bool =
    false

  method acceptsFirstMouse*(self: NSView, event: NSEvent): bool =
    false

  method mouse*(self: NSView, point: NSPoint, inRect: NSRect): bool =
    if self.isFlipped():
      point.x >= inRect.origin.x and point.x < inRect.origin.x + inRect.size.width and
        point.y >= inRect.origin.y and point.y < inRect.origin.y + inRect.size.height
    else:
      point.x >= inRect.origin.x and point.x < inRect.origin.x + inRect.size.width and
        point.y >= inRect.origin.y and point.y < inRect.origin.y + inRect.size.height

  method hitTest*(self: NSView, point: NSPoint): NSView =
    if self.isHiddenOrHasHiddenAncestor():
      return NSView(value: nil)
    if not self.mouse(point, inRect = self.bounds()):
      return NSView(value: nil)
    var i = self.xSubviews.high
    while i >= 0:
      let child = self.xSubviews[i]
      if not child.isHidden():
        let childPoint = self.convertPointToView(point, child)
        let hit = child.hitTest(childPoint)
        if hit.notNil:
          return hit
      dec i
    self

  method xEnclosingClipView*(self: NSView): NSView =
    var current = self.superview()
    while not current.isNil:
      if current.isKindOfClass(NSClipView):
        return current
      current = current.superview()
    NSView(value: nil)

  method scrollPoint*(self: NSView, point: NSPoint) =
    let clipView = self.xEnclosingClipView()
    if clipView.isNil:
      return
    let origin = self.convertPointToView(point, clipView)
    ID(value: clipView.value).asWrapper(ClipViewWrapper).scrollToPoint(origin)

  method scrollRectToVisible*(self: NSView, rect: NSRect): bool =
    let clipView = self.xEnclosingClipView()
    if clipView.isNil:
      return false
    let clipWrapper = ID(value: clipView.value).asWrapper(ClipViewWrapper)
    let documentView = clipWrapper.documentView()
    if documentView.isNil:
      return false

    let visible = clipWrapper.documentVisibleRect()
    let target = documentView.convertRect(rect, self)

    let missingLeft = visible.origin.x - target.origin.x
    let missingRight = maxX(target) - maxX(visible)
    let missingTop = visible.origin.y - target.origin.y
    let missingBottom = maxY(target) - maxY(visible)

    var dx = 0.0'f32
    var dy = 0.0'f32
    if missingLeft * missingRight < 0.0:
      if abs(missingLeft) < abs(missingRight):
        dx = -missingLeft
      else:
        dx = missingRight
    if missingTop * missingBottom < 0.0:
      if abs(missingTop) < abs(missingBottom):
        dy = -missingTop
      else:
        dy = missingBottom

    if dx == 0.0 and dy == 0.0:
      return false

    var point = visible.origin
    point.x += dx
    point.y += dy
    let clipPoint = documentView.convertPointToView(point, clipView)
    clipWrapper.scrollToPoint(clipPoint)
    true

  method resizeSubviewsWithOldSize*(self: NSView, oldSize: NSSize) =
    for child in self.xSubviews:
      child.resizeWithOldSuperviewSize(oldSize)

  method resizeWithOldSuperviewSize*(self: NSView, oldSize: NSSize) =
    discard

  method dealloc(self: NSView) {.used.} =
    detachSubviews(self)
    self.xInvalidRects.setLen(0)
    self.xRectsBeingRedrawn.setLen(0)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSView, self, getSelector("dealloc"))

proc convertPoint*(self: NSView, point: NSPoint, fromView: NSView): NSPoint =
  if fromView.isNil:
    var current = self
    var resultPoint = point
    while not current.isNil:
      let frame = current.frame()
      let bounds = current.bounds()
      resultPoint.x += bounds.origin.x - frame.origin.x
      resultPoint.y += bounds.origin.y - frame.origin.y
      current = current.superview()
    return resultPoint
  if fromView.value == self.value:
    return point
  let windowPoint = fromView.convertPointToView(point, NSView(value: nil))
  self.convertPoint(windowPoint, NSView(value: nil))

proc convertPointToView*(self: NSView, point: NSPoint, toView: NSView): NSPoint =
  if toView.isNil:
    var current = self
    var resultPoint = point
    while not current.isNil:
      let frame = current.frame()
      let bounds = current.bounds()
      resultPoint.x += frame.origin.x - bounds.origin.x
      resultPoint.y += frame.origin.y - bounds.origin.y
      current = current.superview()
    return resultPoint
  if toView.value == self.value:
    return point
  let windowPoint = self.convertPointToView(point, NSView(value: nil))
  toView.convertPoint(windowPoint, NSView(value: nil))

proc convertRect*(self: NSView, rect: NSRect, fromView: NSView): NSRect =
  let origin = self.convertPoint(rect.origin, fromView)
  nsRect(origin.x, origin.y, rect.size.width, rect.size.height)

proc convertRectToView*(self: NSView, rect: NSRect, toView: NSView): NSRect =
  let origin = self.convertPointToView(rect.origin, toView)
  nsRect(origin.x, origin.y, rect.size.width, rect.size.height)

proc markTransformsDirty(view: NSView) =
  view.xValidTransforms = false
  view.xValidTrackingAreas = false
  for child in view.xSubviews:
    markTransformsDirty(child)

proc new*(t: typedesc[NSView]): NSView =
  var allocated = NSView.alloc()
  result = initOwned(move(allocated))

proc clearSuperviewRef*(viewId: IDPtr) =
  if viewId.isNil:
    return
  let child = ownFromId[NSView](viewId)
  if child.isNil:
    return
  child.xSetSuperview(NSView(value: nil))

proc detachSubviews*(view: NSObject) =
  if view.isNil:
    return
  let v = view.NSView
  if v.isNil:
    return
  var children = v.subviews()
  for child in children:
    clearSuperviewRef(child.value)
  children.setLen(0)
  v.setSubviews(children)

proc isHiddenOrHasHiddenAncestor*(view: NSView): bool =
  var current = view
  while not current.isNil:
    if current.xHidden:
      return true
    let parent = current.xSuperview()
    if parent.isNil:
      break
    current = parent
  false

proc isDescendantOf*(view: NSView, other: NSView): bool =
  if view.isNil or other.isNil:
    return false
  var current = view
  while not current.isNil:
    if current.value == other.value:
      return true
    let parent = current.superview()
    if parent.isNil:
      break
    current = parent
  false

proc isViewDescendantOf*(viewId: IDPtr, ancestorId: IDPtr): bool =
  if viewId.isNil or ancestorId.isNil:
    return false
  var currentId = viewId
  while not currentId.isNil:
    if currentId == ancestorId:
      return true
    let current = ownFromId[NSView](currentId)
    if current.isNil:
      break
    currentId = current.superview().value
  false

proc ancestorSharedWithView*(view: NSView, other: NSView): NSView =
  if view.isNil or other.isNil:
    return NSView(value: nil)
  var lhs = view
  while not lhs.isNil:
    var rhs = other
    while not rhs.isNil:
      if lhs.value == rhs.value:
        return lhs
      let rhsParent = rhs.superview()
      if rhsParent.isNil:
        break
      rhs = rhsParent
    let lhsParent = lhs.superview()
    if lhsParent.isNil:
      break
    lhs = lhsParent
  NSView(value: nil)

proc enclosingScrollView*(view: NSView): NSScrollView =
  if view.isNil:
    return NSScrollView(value: nil)
  var current = view.superview()
  while not current.isNil:
    if current.isKindOfClass(NSScrollView):
      return ownFromId[NSScrollView](current.value)
    current = current.superview()
  NSScrollView(value: nil)

proc removeSubviewById(parent: NSView, childId: IDPtr): bool =
  if parent.isNil or childId.isNil:
    return false
  var children = parent.subviews()
  for i, candidate in children:
    if candidate.value == childId:
      parent.willRemoveSubview(candidate)
      clearSuperviewRef(childId)
      children.del(i)
      parent.xSubviews = children
      return true
  false

proc removeFromSuperviewWithoutNeedingDisplay*(view: NSView) =
  if view.isNil:
    return
  let parent = view.superview()
  if parent.isNil:
    return
  view.viewWillMoveToSuperview(NSView(value: nil))
  view.viewWillMoveToWindow(NSWindow(value: nil))
  discard removeSubviewById(parent, view.value)
  view.setWindow(NSWindow(value: nil))
  view.viewDidMoveToSuperview()
  view.viewDidMoveToWindow()

proc removeFromSuperview*(view: NSView) =
  if view.isNil:
    return
  let parent = view.superview()
  if parent.isNil:
    return
  parent.setNeedsDisplayInRect(view.frame())
  view.removeFromSuperviewWithoutNeedingDisplay()

proc addSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil or self.value == view.value:
    return

  view.viewWillMoveToSuperview(self)
  let parent = view.superview()
  if not parent.isNil and parent.value != self.value:
    view.removeFromSuperviewWithoutNeedingDisplay()

  var children = self.xSubviews
  for i, existing in children:
    if existing.value == view.value:
      children.del(i)
      break
  children.add(view)
  self.xSubviews = children

  view.xSetSuperview(self)
  view.setWindow(self.window())
  markTransformsDirty(view)
  self.setNeedsDisplayInRect(view.frame())

  self.didAddSubview(view)
  view.viewDidMoveToSuperview()

proc removeSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil:
    return
  view.removeFromSuperview()

proc viewWithTag*(view: NSView, wantedTag: int): NSView =
  if view.isNil:
    return NSView(value: nil)
  if view.xTag == wantedTag:
    return view
  for child in view.subviews():
    if child.isNil:
      continue
    let hit = child.viewWithTag(wantedTag)
    if not hit.isNil:
      return hit
  NSView(value: nil)
