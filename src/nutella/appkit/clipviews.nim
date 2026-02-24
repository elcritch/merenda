import ./runtime
import ./views

objcImpl:
  type NSClipView* = object of NSView
    clipBackgroundColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    clipDocumentCursorId: ID
    clipDocumentViewId: ID
    clipDocumentRect: NSRect
    clipDrawsBackground {.set: setDrawsBackground, get: drawsBackground.}: bool
    clipCopiesOnScroll {.set: setCopiesOnScroll, get: copiesOnScroll.}: bool
    clipScrollOrigin: NSPoint

  method init*(self: var NSClipView): NSClipView =
    result = asType[NSClipView](callSuperIdFrom(NSClipView, self, getSelector("init")))
    if result.isNil:
      return
    result.clipBackgroundColor = nsColor(1.0, 1.0, 1.0, 1.0)
    result.clipDocumentCursorId = nil
    result.clipDocumentViewId = nil
    result.clipDocumentRect = nsRect(0, 0, 0, 0)
    result.clipDrawsBackground = true
    result.clipCopiesOnScroll = false
    result.clipScrollOrigin = nsPoint(0, 0)

  method documentCursor*(self: NSClipView): NSObject =
    if self.clipDocumentCursorId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.clipDocumentCursorId)

  method setDocumentCursor*(self: NSClipView, value: NSObject) =
    self.clipDocumentCursorId = replacedOwnedId(self.clipDocumentCursorId, value.value)

  method documentView*(self: NSClipView): NSView =
    if self.clipDocumentViewId.isNil:
      return NSView(value: nil)
    ownFromId[NSView](self.clipDocumentViewId)

  method setDocumentView*(self: NSClipView, view: NSView) =
    if self.isNil:
      return
    if self.clipDocumentViewId == view.value:
      return

    if not self.clipDocumentViewId.isNil:
      clearSuperviewRef(self.clipDocumentViewId)
      var children = self.viewSubviews()
      for i, candidate in children:
        if candidate == self.clipDocumentViewId:
          children.del(i)
          self.viewSubviews = children
          releaseId(candidate)
          break

    if view.isNil:
      self.clipDocumentViewId = replacedOwnedId(self.clipDocumentViewId, nil)
      self.clipDocumentRect = nsRect(0, 0, 0, 0)
      self.clipScrollOrigin = nsPoint(0, 0)
      return

    let parentId = view.viewSuperview()
    if not parentId.isNil:
      var parent = ownFromId[NSView](parentId)
      if not parent.isNil:
        var siblings = parent.viewSubviews()
        for i, candidate in siblings:
          if candidate == view.value:
            siblings.del(i)
            parent.viewSubviews = siblings
            releaseId(candidate)
            break
      view.viewSuperview = nil

    var children = self.viewSubviews()
    if view.value notin children:
      children.add(retainId(view.value))
      self.viewSubviews = children
    view.viewSuperview = self.value
    view.setNextResponder(asType[NSResponder](self))
    self.clipDocumentViewId = replacedOwnedId(self.clipDocumentViewId, view.value)
    self.clipScrollOrigin = self.constrainScrollPoint(self.clipScrollOrigin)
    let frame = view.viewFrame()
    self.clipDocumentRect =
      nsRect(0, 0, max(frame.size.width, 0.0), max(frame.size.height, 0.0))
    view.setFrame(
      (-self.clipScrollOrigin.x).float32,
      (-self.clipScrollOrigin.y).float32,
      frame.size.width.float32,
      frame.size.height.float32,
    )

  method documentRect*(self: NSClipView): NSRect =
    if self.clipDocumentViewId.isNil:
      return nsRect(0, 0, 0, 0)
    let doc = self.documentView()
    if doc.isNil:
      return nsRect(0, 0, 0, 0)
    let frame = doc.viewFrame()
    self.clipDocumentRect =
      nsRect(0, 0, max(frame.size.width, 0.0), max(frame.size.height, 0.0))
    self.clipDocumentRect

  method documentVisibleRect*(self: NSClipView): NSRect =
    let constrained = self.constrainScrollPoint(self.clipScrollOrigin)
    let clipSize = self.viewFrame().size
    let docRect = self.documentRect()
    nsRect(
      constrained.x,
      constrained.y,
      min(clipSize.width, docRect.size.width),
      min(clipSize.height, docRect.size.height),
    )

  method constrainScrollPoint*(self: NSClipView, point: NSPoint): NSPoint =
    let docRect = self.documentRect()
    let clipSize = self.viewFrame().size
    let maxX = max(docRect.size.width - clipSize.width, 0.0)
    let maxY = max(docRect.size.height - clipSize.height, 0.0)
    result = nsPoint(clamp(point.x, 0.0, maxX), clamp(point.y, 0.0, maxY))

  method viewBoundsChanged*(self: NSClipView, note: NSObject) =
    discard self
    discard note

  method viewFrameChanged*(self: NSClipView, note: NSObject) =
    discard self
    discard note

  method autoscroll*(self: NSClipView, event: NSObject): bool =
    discard self
    discard event
    false

  method scrollToPoint*(self: NSClipView, point: NSPoint) =
    self.clipScrollOrigin = self.constrainScrollPoint(point)
    let doc = self.documentView()
    if doc.isNil:
      return
    let frame = doc.viewFrame()
    doc.setFrame(
      (-self.clipScrollOrigin.x).float32,
      (-self.clipScrollOrigin.y).float32,
      frame.size.width.float32,
      frame.size.height.float32,
    )

  method setFrame*(
      self: NSClipView,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ) =
    self.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))
    self.clipScrollOrigin = self.constrainScrollPoint(self.clipScrollOrigin)
    let doc = self.documentView()
    if doc.isNil:
      return
    let frame = doc.viewFrame()
    doc.setFrame(
      (-self.clipScrollOrigin.x).float32,
      (-self.clipScrollOrigin.y).float32,
      frame.size.width.float32,
      frame.size.height.float32,
    )

  method dealloc(self: NSClipView) {.used.} =
    self.clipDocumentCursorId = replacedOwnedId(self.clipDocumentCursorId, nil)
    self.clipDocumentViewId = replacedOwnedId(self.clipDocumentViewId, nil)
    discard callSuperIdFrom(NSClipView, self, getSelector("dealloc"))

proc new*(t: typedesc[NSClipView]): NSClipView =
  var allocated = NSClipView.alloc()
  result = initOwned(move(allocated))
