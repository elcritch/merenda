import ./runtime
import ./responders

export responders

proc isViewDescendantOf*(viewId: IDPtr, ancestorId: IDPtr): bool
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
    alpha {.set: setAlphaValue, get: alphaValue.}: float32
    viewSuperview: NSView
    viewTag: int
    viewSubviews: seq[NSView]

  method init*(self: var NSView): NSView =
    result = asType[NSView](
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
    result = asType[NSView](callSuperIdFrom(NSView, self, getSelector("init")))
    if result.isNil:
      return
    result.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))
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

  method setFrame*(
      self: NSView,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ) =
    self.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))

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
    clearIvarRefs(self)
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
  let v = asRetainedType[NSView](view)
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
    view.setNextResponder(asType[NSResponder](self))
    return
  if not parent.isNil:
    view.removeFromSuperview()
  var children = self.viewSubviews()
  if view notin children:
    children.add(view)
    self.viewSubviews = children
  view.viewSuperview = retain(self)
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
  for child in view.viewSubviews():
    if child.isNil:
      continue
    let hit = child.viewWithTag(wantedTag)
    if not hit.isNil:
      return hit
  NSView(value: nil)
