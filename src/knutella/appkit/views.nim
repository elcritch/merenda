import std/algorithm
import std/sequtils

import ./runtime
import ./responders
import ./graphics
import ./colors
import ./trackingareas

export responders

proc isViewDescendantOf*(viewId: IDPtr, ancestorId: IDPtr): bool
proc detachSubviews*(view: NSObject)

objcImpl:
  type WindowsWrapper* {.structural.} =
    concept self
        method invalidateCursorRectsForView*(self: WindowsWrapper, view: NSView)
        method xInvalidateTrackingAreas*(self: WindowsWrapper)

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
    xBounds {.get: bounds, set: setBounds.}: NSRect
    xWindow {.get: window, set: setWindow.}: NSWindow
    xMenu {.get: menu, set: setMenu.}: NSMenu
    xSuperview {.get: superview, set: xSetSuperview.}: NSView
    xSubviews {.get: subviews, set: setSubviews.}: seq[NSView]
    xNextKeyView: NSView
    xPreviousKeyView: NSView

    xHidden: bool
    xBackgroundColor: NSColor

    xPostsNotificationOnFrameChange {.
      set: setPostsFrameChangedNotifications, get: postsFrameChangedNotifications
    .}: bool
    xPostsNotificationOnBoundsChange {.
      set: setPostsBoundsChangedNotifications, get: postsBoundsChangedNotifications
    .}: bool

    xAutoresizesSubviews {.set: setAutoresizesSubviews, get: autoresizesSubviews.}: bool
    xAutoresizingMask {.set: setAutoresizingMask, get: autoresizingMask.}: int

    xTag: int
    xDraggedTypes: seq[ID]
    xTrackingAreas: seq[NSTrackingArea]
    xNeedsDisplay {.set: setNeedsDisplay, get: needsDisplay.}: bool
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
    result.xHidden = false
    result.xPostsNotificationOnFrameChange = true
    result.xPostsNotificationOnBoundsChange = true
    result.xAutoresizesSubviews = true
    result.xAutoresizingMask = 0
    result.xAlpha = 1.0
    result.xSuperview = NSView(value: nil)
    result.xTag = -1
    result.xSubviews = @[]
    result.xNeedsDisplay = true
    result.xInvalidRects = @[]
    result.xRectsBeingRedrawn = @[]

  method init*(self: var NSView): NSView =
    self.initWithFrame(nsRect(0, 0, 1, 1))

  method setFrame*(self: NSView, frame: NSRect) =
    if self.xFrame == frame:
      return

    let priorSize = self.xBounds.size

    if self.xBounds.size.width == 0 or self.xBounds.size.height == 0:
      #// No valid current bounds value - just update it to use the frame size
      self.xBounds.size = frame.size
    else:
      #// Get the bounds->frame transform
      # CGAffineTransform transform=concatViewTransform(CGAffineTransformIdentity,self,nil,YES,NO);
      #// ... and invert it so we can get the new bounds size from the new frame size
      # self.xTransform = CGAffineTransformInvert(transform);
      # self.xBounds.size = CGSizeApplyAffineTransform(frame.size, transform);

      self.xBounds.size = frame.size # TODO: implement the affine transforms...

    self.xFrame = frame
    self.xWindow.asWrapper(WindowsWrapper).invalidateCursorRectsForView(self)
      #this also invalidates tracking areas

  method setBounds*(
      self: NSView,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ) =
    self.xBounds =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))
    self.xNeedsDisplay = true
    self.xInvalidRects.setLen(0)
    self.xRectsBeingRedrawn.setLen(0)

  method setBoundsOrigin*(self: NSView, point: NSPoint) =
    let oldBounds = self.xBounds
    self.xBounds = nsRect(
      point.x, point.y, max(oldBounds.size.width, 0.0), max(oldBounds.size.height, 0.0)
    )
    self.xNeedsDisplay = true
    self.xInvalidRects.setLen(0)
    self.xRectsBeingRedrawn.setLen(0)

  method setBoundsSize*(self: NSView, size: NSSize) =
    let oldBounds = self.xBounds
    self.xBounds = nsRect(
      oldBounds.origin.x,
      oldBounds.origin.y,
      max(size.width, 0.0),
      max(size.height, 0.0),
    )
    self.xNeedsDisplay = true
    self.xInvalidRects.setLen(0)
    self.xRectsBeingRedrawn.setLen(0)

  method isFlipped*(self: NSView): bool =
    false

  method isOpaque*(self: NSView): bool =
    false

  method adjustScroll*(self: NSView, toRect: NSRect): NSRect =
    return nsRect(0, 0, 0, 0)

  method visibleRect*(self: NSView): NSRect =
    if self.isNil or self.xHidden:
      return nsRect(0.0, 0.0, 0.0, 0.0)
    self.xBounds

  method canDraw*(self: NSView): bool =
    (not self.isNil) and (not self.xHidden)

  method viewWillDraw*(self: NSView) =
    for child in self.xSubviews:
      if child.isNil:
        continue
      child.viewWillDraw()

  method xTrackingAreasChanged*(self: NSView) =
    self.window().asWrapper(WindowsWrapper).xInvalidateTrackingAreas()

  method addTrackingArea*(self: NSView, trackingArea: NSTrackingArea) =
    self.xTrackingAreas.add(trackingArea)
    self.xTrackingAreasChanged()

  method updateTrackingAreas*(self: NSView) =
    self.xTrackingAreasChanged()

  method discardCursorRects*(self: NSView) =
    var areas = self.xTrackingAreas
    areas.keepItIf(
      not (it.isLegacy() and it.options().contains(NSTrackingCursorUpdate))
    )

    nsArray(self.subviews()).makeObjectsPerformSelector(@ns"discardCursorRects")
    self.xTrackingAreasChanged()

  method opaqueAncestor*(self: NSView): NSView =
    if self.isNil:
      return NSView(value: nil)
    if self.isOpaque():
      return retain(self)
    let parent = self.xSuperview
    if parent.isNil:
      return retain(self)
    parent.opaqueAncestor()

  method setNeedsDisplayInRect*(self: NSView, rect: NSRect) =
    let visible = self.visibleRect()
    let clipped = nsIntersectionRect(visible, rect)
    if isEmpty(clipped):
      return
    if nsContainsRect(clipped, visible):
      self.xInvalidRects.setLen(0)
    else:
      self.xInvalidRects.add(clipped)
    self.xRectsBeingRedrawn.setLen(0)
    self.xNeedsDisplay = true

  method display*(self: NSView) =
    self.displayRect(self.visibleRect())

  method xDisplayIfNeededWithoutViewWillDraw*(self: NSView) =
    if self.xNeedsDisplay:
      self.displayRect(unionOfInvalidRects(self))
      self.xInvalidRects.setLen(0)
      #if self.xInvalidRects.len == 0:
      #  self.displayRect(self.visibleRect())
      #else:
      #  var dirty = self.xInvalidRects[0]
      #  for i in 1 ..< self.xInvalidRects.len:
      #    dirty = nsUnionRect(dirty, self.xInvalidRects[i])
      #  self.displayRect(dirty)

    for child in self.xSubviews:
      if child.isNil:
        continue
      child.xDisplayIfNeededWithoutViewWillDraw()

  method displayIfNeeded*(self: NSView) =
    self.viewWillDraw()

  method displayIfNeededInRect*(self: NSView, rect: NSRect) =
    let clipped = nsIntersectionRect(rect, self.visibleRect())
    if isEmpty(clipped):
      return
    if self.xNeedsDisplay:
      self.displayRect(clipped)
    for child in self.xSubviews:
      if child.isNil:
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
      child.displayIfNeededInRect(childDirty)

  method displayIfNeededIgnoringOpacity*(self: NSView) =
    if self.xNeedsDisplay:
      self.displayRectIgnoringOpacity(unionOfInvalidRects(self))

    for child in self.xSubviews:
      if child.isNil:
        continue
      child.displayIfNeededIgnoringOpacity()

  method displayIfNeededInRectIgnoringOpacity*(self: NSView, rect: NSRect) =
    let clipped = nsIntersectionRect(rect, self.visibleRect())
    if isEmpty(clipped):
      return
    if self.xNeedsDisplay:
      self.displayRectIgnoringOpacity(clipped)
    for child in self.xSubviews:
      if child.isNil:
        continue
      let childFrame = child.xFrame
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
      child.displayIfNeededInRectIgnoringOpacity(childDirty)

  method displayRect*(self: NSView, rect: NSRect) =
    let opaque = self.opaqueAncestor()
    if opaque.isNil or opaque.value == self.value:
      self.displayRectIgnoringOpacity(rect)
      return
    opaque.displayRectIgnoringOpacity(opaque.visibleRect())

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
      if child.isNil or child.xHidden:
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
    if self.isNil:
      return
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

  method setBackgroundColor(
      self: NSView,
      r: float32,
      g {.kw("green").}: float32,
      b {.kw("blue").}: float32,
      a {.kw("alpha").}: float32,
  ) =
    self.xBackgroundColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setHidden(self: NSView, hidden: bool) =
    self.xHidden = hidden

  method dealloc(self: NSView) {.used.} =
    detachSubviews(self)
    self.xInvalidRects.setLen(0)
    self.xRectsBeingRedrawn.setLen(0)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSView, self, getSelector("dealloc"))

proc new*(t: typedesc[NSView]): NSView =
  var allocated = NSView.alloc()
  result = initOwned(move(allocated))

proc clearSuperviewRef*(viewId: IDPtr) =
  if viewId.isNil:
    return
  let child = ownFromId[NSView](viewId)
  if child.isNil:
    return
  child.xSuperview = NSView(value: nil)
  child.setNextResponder(NSResponder(value: nil))

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
        return retain(lhs)
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
      clearSuperviewRef(childId)
      children.del(i)
      parent.setSubviews(children)
      return true
  false

proc removeFromSuperview*(view: NSView) =
  if view.isNil:
    return
  let parent = view.superview()
  if parent.isNil:
    return
  view.xSuperview = NSView(value: nil)
  discard removeSubviewById(parent, view.value)

proc addSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil or self.value == view.value:
    return
  let parent = view.superview()
  if not parent.isNil and parent.value == self.value:
    var children = self.xSubviews
    if view notin children:
      children.add(view)
      self.xSubviews = children
    view.setNextResponder(self.NSResponder)
    return
  if not parent.isNil:
    view.removeFromSuperview()
  var children = self.xSubviews
  if view notin children:
    children.add(view)
    self.xSubviews = children
  view.xSetSuperview(retain(self))
  view.setNextResponder(self.NSResponder)

proc removeSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil:
    return
  discard removeSubviewById(self, view.value)

proc viewWithTag*(view: NSView, wantedTag: int): NSView =
  if view.isNil:
    return NSView(value: nil)
  if view.xTag == wantedTag:
    return retain(view)
  for child in view.subviews():
    if child.isNil:
      continue
    let hit = child.viewWithTag(wantedTag)
    if not hit.isNil:
      return hit
  NSView(value: nil)
