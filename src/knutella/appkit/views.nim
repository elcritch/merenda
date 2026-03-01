import ./runtime
import ./responders
import ./graphics
import ./colors

export responders

proc isViewDescendantOf*(viewId: IDPtr, ancestorId: IDPtr): bool
proc detachSubviews*(view: NSObject)


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
    viewFrame: NSRect
    viewBounds {.set: setBounds, get: bounds.}: NSRect
    viewBackgroundColor: NSColor
    viewHidden: bool
    postsFrameChanged {.
      set: setPostsFrameChangedNotifications, get: postsFrameChangedNotifications
    .}: bool
    postsBoundsChanged {.
      set: setPostsBoundsChangedNotifications, get: postsBoundsChangedNotifications
    .}: bool
    autoResizeSubs {.set: setAutoresizesSubviews, get: autoresizesSubviews.}: bool
    autoResizeMask {.set: setAutoresizingMask, get: autoresizingMask.}: int
    alpha {.set: setAlphaValue, get: alphaValue.}: float32
    viewSuperview: NSView
    viewTag: int
    viewSubviews: seq[NSView]
    viewNeedsDisplay {.set: setNeedsDisplay, get: needsDisplay.}: bool
    xInvalidRects: seq[NSRect]
    xRectsBeingRedrawn: seq[NSRect]

  method init*(self: var NSView): NSView =
    result = asTypeRaw[NSView](
      cast[proc(
        self: IDPtr, op: SEL, x: float32, y: float32, width: float32, height: float32
      ): IDPtr {.cdecl, varargs.}](objc_msgSend)(
        self.value, getSelector("initWithFrame:y:width:height:"), 0.0, 0.0, 1.0, 1.0
      )
    )

  method initWithFrame*(
      self: var NSView,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ): NSView =
    result = asTypeRaw[NSView](callSuperIdFrom(NSView, self, getSelector("init")))
    if result.isNil:
      return
    result.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))
    result.viewBounds =
      nsRect(0.0, 0.0, max(width.float32, 0.0), max(height.float32, 0.0))
    result.viewBackgroundColor = nsColor(0.86, 0.90, 0.96, 1.0)
    result.viewHidden = false
    result.postsFrameChanged = true
    result.postsBoundsChanged = true
    result.autoResizeSubs = true
    result.autoResizeMask = 0
    result.alpha = 1.0
    result.viewSuperview = NSView(value: nil)
    result.viewTag = -1
    result.viewSubviews = @[]
    result.viewNeedsDisplay = true
    result.xInvalidRects = @[]
    result.xRectsBeingRedrawn = @[]

  method setFrame*(
      self: NSView,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ) =
    let priorBounds = self.viewBounds()
    self.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))
    self.viewBounds = nsRect(
      priorBounds.origin.x,
      priorBounds.origin.y,
      max(width.float32, 0.0),
      max(height.float32, 0.0),
    )
    self.viewNeedsDisplay = true
    self.xInvalidRects.setLen(0)
    self.xRectsBeingRedrawn.setLen(0)

  method setBounds*(
      self: NSView,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ) =
    self.viewBounds =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))
    self.viewNeedsDisplay = true
    self.xInvalidRects.setLen(0)
    self.xRectsBeingRedrawn.setLen(0)

  method setBoundsOrigin*(self: NSView, point: NSPoint) =
    let oldBounds = self.viewBounds()
    self.viewBounds = nsRect(
      point.x, point.y, max(oldBounds.size.width, 0.0), max(oldBounds.size.height, 0.0)
    )
    self.viewNeedsDisplay = true
    self.xInvalidRects.setLen(0)
    self.xRectsBeingRedrawn.setLen(0)

  method setBoundsSize*(self: NSView, size: NSSize) =
    let oldBounds = self.viewBounds()
    self.viewBounds = nsRect(
      oldBounds.origin.x,
      oldBounds.origin.y,
      max(size.width, 0.0),
      max(size.height, 0.0),
    )
    self.viewNeedsDisplay = true
    self.xInvalidRects.setLen(0)
    self.xRectsBeingRedrawn.setLen(0)

  method isFlipped*(self: NSView): bool =
    false

  method isOpaque*(self: NSView): bool =
    false

  method visibleRect*(self: NSView): NSRect =
    if self.isNil or self.viewHidden():
      return nsRect(0.0, 0.0, 0.0, 0.0)
    self.viewBounds()

  method canDraw*(self: NSView): bool =
    (not self.isNil) and (not self.viewHidden())

  method viewWillDraw*(self: NSView) =
    for child in self.viewSubviews():
      if child.isNil:
        continue
      child.viewWillDraw()

  method opaqueAncestor*(self: NSView): NSView =
    if self.isNil:
      return NSView(value: nil)
    if self.isOpaque():
      return retain(self)
    let parent = self.viewSuperview()
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
    self.viewNeedsDisplay = true

  method display*(self: NSView) =
    self.displayRect(self.visibleRect())

  method xDisplayIfNeededWithoutViewWillDraw*(self: NSView) =
    if self.viewNeedsDisplay():
      self.displayRect(unionOfInvalidRects(self))
      self.xInvalidRects.setLen(0)
      #if self.xInvalidRects.len == 0:
      #  self.displayRect(self.visibleRect())
      #else:
      #  var dirty = self.xInvalidRects[0]
      #  for i in 1 ..< self.xInvalidRects.len:
      #    dirty = nsUnionRect(dirty, self.xInvalidRects[i])
      #  self.displayRect(dirty)

    for child in self.viewSubviews():
      if child.isNil: continue
      child.xDisplayIfNeededWithoutViewWillDraw()

  method displayIfNeeded*(self: NSView) =
    self.viewWillDraw()


  method displayIfNeededInRect*(self: NSView, rect: NSRect) =

    let clipped = nsIntersectionRect(rect, self.visibleRect())
    if isEmpty(clipped):
      return
    if self.viewNeedsDisplay():
      self.displayRect(clipped)
    for child in self.viewSubviews():
      if child.isNil:
        continue
      let childFrame = child.viewFrame()
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
    if self.viewNeedsDisplay():
      self.displayRectIgnoringOpacity(unionOfInvalidRects(self))

    for child in self.viewSubviews():
      if child.isNil:
        continue
      child.displayIfNeededIgnoringOpacity()

  method displayIfNeededInRectIgnoringOpacity*(self: NSView, rect: NSRect) =
    let clipped = nsIntersectionRect(rect, self.visibleRect())
    if isEmpty(clipped):
      return
    if self.viewNeedsDisplay():
      self.displayRectIgnoringOpacity(clipped)
    for child in self.viewSubviews():
      if child.isNil:
        continue
      let childFrame = child.viewFrame()
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

    for child in self.viewSubviews():
      if child.isNil or child.viewHidden():
        continue
      let childFrame = child.viewFrame()
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
      self.viewNeedsDisplay = false
    else:
      var i = self.xInvalidRects.high
      while i >= 0:
        if nsContainsRect(clipped, self.xInvalidRects[i]):
          self.xInvalidRects.del(i)
        dec i
      self.viewNeedsDisplay = self.xInvalidRects.len > 0
    self.xRectsBeingRedrawn.setLen(0)

  method displayRectIgnoringOpacity*(
      self: NSView, rect: NSRect, context {.kw("inContext").}: NSGraphicsContext
  ) =
    discard context
    self.displayRectIgnoringOpacity(rect)

  method getRectsBeingDrawn*(
      self: NSView, rects: ptr ptr NSRect, count {.kw("count").}: ptr int
  ) =
    if rects.isNil or count.isNil:
      return
    if self.xRectsBeingRedrawn.len == 0:
      if self.xInvalidRects.len == 0:
        if self.viewNeedsDisplay():
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
    let color = self.viewBackgroundColor()
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
    discard self
    discard size
    discard

  method drawPageBorderWithSize*(self: NSView, size: NSSize) =
    discard self
    discard size
    discard

  method setBackgroundColor(
      self: NSView,
      r: float32,
      g {.kw("green").}: float32,
      b {.kw("blue").}: float32,
      a {.kw("alpha").}: float32,
  ) =
    self.viewBackgroundColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setHidden(self: NSView, hidden: bool) =
    self.viewHidden = hidden

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
  child.viewSuperview = NSView(value: nil)
  child.setNextResponder(NSResponder(value: nil))

proc detachSubviews*(view: NSObject) =
  if view.isNil:
    return
  let v = view.NSView
  if v.isNil:
    return
  var children = v.viewSubviews()
  for child in children:
    clearSuperviewRef(child.value)
  children.setLen(0)
  v.viewSubviews = children

proc frame*(view: NSView): NSRect =
  view.viewFrame()

proc frameOrigin*(view: NSView): NSPoint =
  view.frame().origin

proc frameSize*(view: NSView): NSSize =
  view.frame().size

proc boundsOrigin*(view: NSView): NSPoint =
  view.bounds().origin

proc boundsSize*(view: NSView): NSSize =
  view.bounds().size

proc isHidden*(view: NSView): bool =
  view.viewHidden()

proc isHiddenOrHasHiddenAncestor*(view: NSView): bool =
  var current = view
  while not current.isNil:
    if current.viewHidden():
      return true
    let parent = current.viewSuperview()
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
    let parent = current.viewSuperview()
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
    currentId = current.viewSuperview().value
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
      let rhsParent = rhs.viewSuperview()
      if rhsParent.isNil:
        break
      rhs = rhsParent
    let lhsParent = lhs.viewSuperview()
    if lhsParent.isNil:
      break
    lhs = lhsParent
  NSView(value: nil)

proc tag*(view: NSView): int =
  view.viewTag()

proc setTag*(view: NSView, value: int) =
  view.viewTag = value

proc setBackgroundColor*(view: NSView, r, g, b: float32, a: float32 = 1.0'f32) =
  view.viewBackgroundColor = nsColor(r, g, b, a)

proc setHidden*(view: NSView, hidden: bool) =
  view.viewHidden = hidden

proc setFrame*(view: NSView, frame: NSRect) =
  view.setFrame(
    frame.origin.x.float32, frame.origin.y.float32, frame.size.width.float32,
    frame.size.height.float32,
  )

proc setFrameOrigin*(view: NSView, origin: NSPoint) =
  let f = view.frame()
  view.setFrame(nsRect(origin.x, origin.y, f.size.width, f.size.height))

proc setFrameSize*(view: NSView, size: NSSize) =
  let f = view.frame()
  view.setFrame(
    nsRect(f.origin.x, f.origin.y, max(size.width, 0.0), max(size.height, 0.0))
  )

proc setBounds*(view: NSView, bounds: NSRect) =
  view.setBounds(
    bounds.origin.x.float32, bounds.origin.y.float32, bounds.size.width.float32,
    bounds.size.height.float32,
  )

proc enclosingScrollView*(view: NSView): NSScrollView =
  if view.isNil:
    return NSScrollView(value: nil)
  var current = view.viewSuperview()
  while not current.isNil:
    if current.isKindOfClass(NSScrollView):
      return ownFromId[NSScrollView](current.value)
    current = current.viewSuperview()
  NSScrollView(value: nil)

proc subviews*(view: NSView): seq[NSView] =
  result = view.viewSubviews()

proc superview*(view: NSView): NSView =
  let parent = view.viewSuperview()
  if parent.isNil:
    return NSView(value: nil)
  retain(parent)

proc removeSubviewById(parent: NSView, childId: IDPtr): bool =
  if parent.isNil or childId.isNil:
    return false
  var children = parent.viewSubviews()
  for i, candidate in children:
    if candidate.value == childId:
      clearSuperviewRef(childId)
      children.del(i)
      parent.viewSubviews = children
      return true
  false

proc removeFromSuperview*(view: NSView) =
  if view.isNil:
    return
  let parent = view.viewSuperview()
  if parent.isNil:
    return
  view.viewSuperview = NSView(value: nil)
  discard removeSubviewById(parent, view.value)

proc addSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil or self.value == view.value:
    return
  let parent = view.viewSuperview()
  if not parent.isNil and parent.value == self.value:
    var children = self.viewSubviews()
    if view notin children:
      children.add(view)
      self.viewSubviews = children
    view.setNextResponder(self.NSResponder)
    return
  if not parent.isNil:
    view.removeFromSuperview()
  var children = self.viewSubviews()
  if view notin children:
    children.add(view)
    self.viewSubviews = children
  view.viewSuperview = retain(self)
  view.setNextResponder(self.NSResponder)

proc removeSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil:
    return
  discard removeSubviewById(self, view.value)

proc viewWithTag*(view: NSView, wantedTag: int): NSView =
  if view.isNil:
    return NSView(value: nil)
  if view.viewTag() == wantedTag:
    return retain(view)
  for child in view.viewSubviews():
    if child.isNil:
      continue
    let hit = child.viewWithTag(wantedTag)
    if not hit.isNil:
      return hit
  NSView(value: nil)
