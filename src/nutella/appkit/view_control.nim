proc clearSuperviewRef(viewId: ID) =
  if viewId.isNil:
    return
  let child = ownFromId[NSView](viewId)
  if child.isNil:
    return
  child.viewSuperview = nil

proc detachSubviews(view: NSObject) =
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

proc frame*(window: NSWindow): NSRect =
  window.windowFrame()

proc frameOrigin*(view: NSView): NSPoint =
  view.frame().origin

proc frameOrigin*(window: NSWindow): NSPoint =
  window.frame().origin

proc frameSize*(view: NSView): NSSize =
  view.frame().size

proc frameSize*(window: NSWindow): NSSize =
  window.frame().size

proc title*(window: NSWindow): string =
  window.windowTitle()

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

proc setFrame*(window: NSWindow, frame: NSRect) =
  var nextFrame = nsRect(
    frame.origin.x,
    frame.origin.y,
    max(frame.size.width, 1.0),
    max(frame.size.height, 1.0),
  )
  window.windowFrame = nextFrame
  if window.windowNativeReady() and not window.windowNativeWindow().isNil:
    window.windowNativeWindow.size = ivec2(
      clampWindowSize(nextFrame.size.width), clampWindowSize(nextFrame.size.height)
    )

proc setFrameOrigin*(window: NSWindow, origin: NSPoint) =
  let f = window.frame()
  window.setFrame(nsRect(origin.x, origin.y, f.size.width, f.size.height))

proc setFrameSize*(window: NSWindow, size: NSSize) =
  let f = window.frame()
  window.setFrame(nsRect(f.origin.x, f.origin.y, size.width, size.height))

proc setContentSize*(window: NSWindow, size: NSSize) =
  window.setFrameSize(size)

proc setContentSize*(window: NSWindow, width, height: float32) =
  window.setContentSize(nsSize(width, height))

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
    return
  if not parentId.isNil:
    view.removeFromSuperview()
  var children = self.viewSubviews()
  if view.value notin children:
    children.add(retainId(view.value))
    self.viewSubviews = children
  view.viewSuperview = self.value

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

proc setOnClick*(button: NSButton, cb: proc(sender: NSButton)) =
  if cb.isNil:
    button.onClick = nil
  else:
    button.onClick = proc(sender: ID) =
      cb(ownFromId[NSButton](sender))

proc click*(button: NSButton) =
  if not button.enabled():
    return
  if button.mixedAllowed():
    case button.stateValue()
    of NSOffState:
      button.stateValue = NSOnState
    of NSOnState:
      button.stateValue = NSMixedState
    else:
      button.stateValue = NSOffState
  else:
    if button.stateValue() == NSOnState:
      button.stateValue = NSOffState
    else:
      button.stateValue = NSOnState
  let cb = button.onClick()
  if not cb.isNil:
    cb(button.value)

proc getPeriodicDelay*(button: NSButton, delay: var cfloat, interval: var cfloat) =
  if button.isNil:
    delay = 0.0
    interval = 0.0
    return
  delay = button.periodicDelay()
  interval = button.periodicInterval()
