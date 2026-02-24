import ./runtime
import ./responders

export responders

proc isViewDescendantOf*(viewId: ID, ancestorId: ID): bool
proc detachSubviews*(view: NSObject)

objcImpl:
  type NSView* = object of NSResponder
    viewFrame: NSRect
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
    alpha {.set: setAlphaValue, get: alphaValue.}: cfloat
    viewSuperview: ID
    viewTag: int
    viewSubviews: seq[ID]

  method init*(self: var NSView): NSView =
    result = asType[NSView](callSuperIdFrom(NSView, self, getSelector("init")))
    if result.isNil:
      return
    result.viewFrame = nsRect(0, 0, 100, 100)
    result.viewBackgroundColor = nsColor(0.86, 0.90, 0.96, 1.0)
    result.viewHidden = false
    result.postsFrameChanged = false
    result.postsBoundsChanged = false
    result.autoResizeSubs = true
    result.autoResizeMask = 0
    result.alpha = 1.0
    result.viewSuperview = nil
    result.viewTag = 0
    result.viewSubviews = @[]

  method initWithFrame*(
      self: var NSView,
      x: cfloat,
      y {.kw("y").}: cfloat,
      width {.kw("width").}: cfloat,
      height {.kw("height").}: cfloat,
  ): NSView =
    result = self.init()
    if result.isNil:
      return
    result.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))

  method setFrame*(
      self: NSView,
      x: cfloat,
      y {.kw("y").}: cfloat,
      width {.kw("width").}: cfloat,
      height {.kw("height").}: cfloat,
  ) =
    self.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))

  method setBackgroundColor(
      self: NSView,
      r: cfloat,
      g {.kw("green").}: cfloat,
      b {.kw("blue").}: cfloat,
      a {.kw("alpha").}: cfloat,
  ) =
    self.viewBackgroundColor = nsColor(r.float32, g.float32, b.float32, a.float32)

  method setHidden(self: NSView, hidden: bool) =
    self.viewHidden = hidden

  method dealloc(self: NSView) {.used.} =
    detachSubviews(self)
    clearIvarRefs(self)
    discard callSuperIdFrom(NSView, self, getSelector("dealloc"))

proc new*(t: typedesc[NSView]): NSView =
  var allocated = NSView.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc clearSuperviewRef*(viewId: ID) =
  if viewId.isNil:
    return
  let child = ownFromId[NSView](viewId)
  if child.isNil:
    return
  child.viewSuperview = nil
  child.setNextResponder(NSResponder(value: nil))

proc detachSubviews*(view: NSObject) =
  if view.isNil:
    return
  var v = asType[NSView](view.value)
  if v.isNil:
    return
  var children = v.viewSubviews()
  for child in children:
    clearSuperviewRef(child)
    releaseId(child)
  children.setLen(0)
  v.viewSubviews = children
  v.value = nil

proc frame*(view: NSView): NSRect =
  view.viewFrame()

proc frameOrigin*(view: NSView): NSPoint =
  view.frame().origin

proc frameSize*(view: NSView): NSSize =
  view.frame().size

proc isHidden*(view: NSView): bool =
  view.viewHidden()

proc isHiddenOrHasHiddenAncestor*(view: NSView): bool =
  var current = view
  while not current.isNil:
    if current.viewHidden():
      return true
    let parentId = current.viewSuperview()
    if parentId.isNil:
      break
    current = ownFromId[NSView](parentId)
  false

proc isDescendantOf*(view: NSView, other: NSView): bool =
  if view.isNil or other.isNil:
    return false
  var current = view
  while not current.isNil:
    if current.value == other.value:
      return true
    let parentId = current.viewSuperview()
    if parentId.isNil:
      break
    current = ownFromId[NSView](parentId)
  false

proc isViewDescendantOf*(viewId: ID, ancestorId: ID): bool =
  if viewId.isNil or ancestorId.isNil:
    return false
  var currentId = viewId
  while not currentId.isNil:
    if currentId == ancestorId:
      return true
    let current = ownFromId[NSView](currentId)
    if current.isNil:
      break
    currentId = current.viewSuperview()
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
      let rhsParentId = rhs.viewSuperview()
      if rhsParentId.isNil:
        break
      rhs = ownFromId[NSView](rhsParentId)
    let lhsParentId = lhs.viewSuperview()
    if lhsParentId.isNil:
      break
    lhs = ownFromId[NSView](lhsParentId)
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
    frame.origin.x.cfloat, frame.origin.y.cfloat, frame.size.width.cfloat,
    frame.size.height.cfloat,
  )

proc setFrameOrigin*(view: NSView, origin: NSPoint) =
  let f = view.frame()
  view.setFrame(nsRect(origin.x, origin.y, f.size.width, f.size.height))

proc setFrameSize*(view: NSView, size: NSSize) =
  let f = view.frame()
  view.setFrame(
    nsRect(f.origin.x, f.origin.y, max(size.width, 0.0), max(size.height, 0.0))
  )

proc subviews*(view: NSView): seq[NSView] =
  let childIds = view.viewSubviews()
  result = newSeq[NSView](childIds.len)
  for i, child in childIds:
    result[i] = ownFromId[NSView](child)

proc superview*(view: NSView): NSView =
  let parentId = view.viewSuperview()
  if parentId.isNil:
    return NSView(value: nil)
  ownFromId[NSView](parentId)

proc removeSubviewById(parent: NSView, childId: ID): bool =
  if parent.isNil or childId.isNil:
    return false
  var children = parent.viewSubviews()
  for i, candidate in children:
    if candidate == childId:
      clearSuperviewRef(childId)
      children.del(i)
      parent.viewSubviews = children
      releaseId(childId)
      return true
  false

proc removeFromSuperview*(view: NSView) =
  if view.isNil:
    return
  let parentId = view.viewSuperview()
  if parentId.isNil:
    return
  view.viewSuperview = nil
  let parent = ownFromId[NSView](parentId)
  if parent.isNil:
    return
  discard removeSubviewById(parent, view.value)

proc addSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil or self.value == view.value:
    return
  let parentId = view.viewSuperview()
  if parentId == self.value:
    var children = self.viewSubviews()
    if view.value notin children:
      children.add(retainId(view.value))
      self.viewSubviews = children
    view.setNextResponder(asType[NSResponder](self))
    return
  if not parentId.isNil:
    view.removeFromSuperview()
  var children = self.viewSubviews()
  if view.value notin children:
    children.add(retainId(view.value))
    self.viewSubviews = children
  view.viewSuperview = self.value
  view.setNextResponder(asType[NSResponder](self))

proc removeSubview*(self: NSView, view: NSView) =
  if self.isNil or view.isNil:
    return
  discard removeSubviewById(self, view.value)

proc viewWithTag*(view: NSView, wantedTag: int): NSView =
  if view.isNil:
    return NSView(value: nil)
  if view.viewTag() == wantedTag:
    return retain(view)
  for childId in view.viewSubviews():
    let child = ownFromId[NSView](childId)
    if child.isNil:
      continue
    let hit = child.viewWithTag(wantedTag)
    if not hit.isNil:
      return hit
  NSView(value: nil)

