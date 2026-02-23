objcImpl:
  type NXClipView* = object of NXView
    clipBackgroundColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    clipDocumentCursorId: ID
    clipDocumentViewId: ID
    clipDocumentRect: NSRect
    clipDrawsBackground {.set: setDrawsBackground, get: drawsBackground.}: bool
    clipCopiesOnScroll {.set: setCopiesOnScroll, get: copiesOnScroll.}: bool
    clipScrollOrigin: NSPoint

  method init*(self: var NXClipView): NXClipView =
    result = asType[NXClipView](callSuperIdFrom(NXClipView, self, getSelector("init")))
    if result.isNil:
      return
    result.clipBackgroundColor = nsColor(1.0, 1.0, 1.0, 1.0)
    result.clipDocumentCursorId = nil
    result.clipDocumentViewId = nil
    result.clipDocumentRect = nsRect(0, 0, 0, 0)
    result.clipDrawsBackground = true
    result.clipCopiesOnScroll = false
    result.clipScrollOrigin = nsPoint(0, 0)

  method documentCursor*(self: NXClipView): NSObject =
    if self.clipDocumentCursorId.isNil:
      return NSObject(value: nil)
    ownFromId[NSObject](self.clipDocumentCursorId)

  method setDocumentCursor*(self: NXClipView, value: NSObject) =
    self.clipDocumentCursorId = replacedOwnedId(self.clipDocumentCursorId, value.value)

  method documentView*(self: NXClipView): NXView =
    if self.clipDocumentViewId.isNil:
      return NXView(value: nil)
    ownFromId[NXView](self.clipDocumentViewId)

  method setDocumentView*(self: NXClipView, view: NXView) =
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
      var parent = ownFromId[NXView](parentId)
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
    view.setNextResponder(asType[NXResponder](self))
    self.clipDocumentViewId = replacedOwnedId(self.clipDocumentViewId, view.value)
    self.clipScrollOrigin = self.constrainScrollPoint(self.clipScrollOrigin)
    let frame = view.viewFrame()
    self.clipDocumentRect =
      nsRect(0, 0, max(frame.size.width, 0.0), max(frame.size.height, 0.0))
    view.setFrame(
      (-self.clipScrollOrigin.x).cfloat,
      (-self.clipScrollOrigin.y).cfloat,
      frame.size.width.cfloat,
      frame.size.height.cfloat,
    )

  method documentRect*(self: NXClipView): NSRect =
    if self.clipDocumentViewId.isNil:
      return nsRect(0, 0, 0, 0)
    let doc = self.documentView()
    if doc.isNil:
      return nsRect(0, 0, 0, 0)
    let frame = doc.viewFrame()
    self.clipDocumentRect =
      nsRect(0, 0, max(frame.size.width, 0.0), max(frame.size.height, 0.0))
    self.clipDocumentRect

  method documentVisibleRect*(self: NXClipView): NSRect =
    let constrained = self.constrainScrollPoint(self.clipScrollOrigin)
    let clipSize = self.viewFrame().size
    let docRect = self.documentRect()
    nsRect(
      constrained.x,
      constrained.y,
      min(clipSize.width, docRect.size.width),
      min(clipSize.height, docRect.size.height),
    )

  method constrainScrollPoint*(self: NXClipView, point: NSPoint): NSPoint =
    let docRect = self.documentRect()
    let clipSize = self.viewFrame().size
    let maxX = max(docRect.size.width - clipSize.width, 0.0)
    let maxY = max(docRect.size.height - clipSize.height, 0.0)
    result = nsPoint(clamp(point.x, 0.0, maxX), clamp(point.y, 0.0, maxY))

  method viewBoundsChanged*(self: NXClipView, note: NSObject) =
    discard self
    discard note

  method viewFrameChanged*(self: NXClipView, note: NSObject) =
    discard self
    discard note

  method autoscroll*(self: NXClipView, event: NSObject): bool =
    discard self
    discard event
    false

  method scrollToPoint*(self: NXClipView, point: NSPoint) =
    self.clipScrollOrigin = self.constrainScrollPoint(point)
    let doc = self.documentView()
    if doc.isNil:
      return
    let frame = doc.viewFrame()
    doc.setFrame(
      (-self.clipScrollOrigin.x).cfloat,
      (-self.clipScrollOrigin.y).cfloat,
      frame.size.width.cfloat,
      frame.size.height.cfloat,
    )

  method setFrame*(
      self: NXClipView,
      x: cfloat,
      y {.kw("y").}: cfloat,
      width {.kw("width").}: cfloat,
      height {.kw("height").}: cfloat,
  ) =
    self.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))
    self.clipScrollOrigin = self.constrainScrollPoint(self.clipScrollOrigin)
    let doc = self.documentView()
    if doc.isNil:
      return
    let frame = doc.viewFrame()
    doc.setFrame(
      (-self.clipScrollOrigin.x).cfloat,
      (-self.clipScrollOrigin.y).cfloat,
      frame.size.width.cfloat,
      frame.size.height.cfloat,
    )

  method dealloc(self: NXClipView) {.used.} =
    self.clipDocumentCursorId = replacedOwnedId(self.clipDocumentCursorId, nil)
    self.clipDocumentViewId = replacedOwnedId(self.clipDocumentViewId, nil)
    discard callSuperIdFrom(NXClipView, self, getSelector("dealloc"))
