import ./runtime
import ./views
import ./graphics
import ./colors

objcImpl:
  type NSClipView* = object of NSView
    clipBackgroundColor {.set: setBackgroundColor, get: backgroundColor.}: NSColor
    xDocumentCursor {.set: setDocumentCursor, get: documentCursor.}: NSCursor
    clipDocumentViewId: NSView
    clipDocumentRect: NSRect
    clipDrawsBackground {.set: setDrawsBackground, get: drawsBackground.}: bool
    clipCopiesOnScroll {.set: setCopiesOnScroll, get: copiesOnScroll.}: bool
    clipScrollOrigin: NSPoint

  method init*(self: var NSClipView): NSClipView =
    result =
      asTypeRaw[NSClipView](callSuperIdFrom(NSClipView, self, getSelector("init")))
    if result.isNil:
      return
    result.clipBackgroundColor = nsColor(1.0, 1.0, 1.0, 1.0)
    result.xDocumentCursor = NSCursor(value: nil)
    result.clipDocumentViewId = NSView(value: nil)
    result.clipDocumentRect = nsRect(0, 0, 0, 0)
    result.clipDrawsBackground = true
    result.clipCopiesOnScroll = false
    result.clipScrollOrigin = nsPoint(0, 0)
    result.setBoundsOrigin(result.clipScrollOrigin)

  method documentView*(self: NSClipView): NSView =
    if self.clipDocumentViewId.isNil:
      return NSView(value: nil)
    retain(self.clipDocumentViewId)

  method setDocumentView*(self: NSClipView, view: NSView) =
    if self.isNil:
      return
    if self.clipDocumentViewId.value == view.value:
      return

    if not self.clipDocumentViewId.isNil:
      clearSuperviewRef(self.clipDocumentViewId.value)
      var children = self.viewSubviews()
      for i, candidate in children:
        if candidate.value == self.clipDocumentViewId.value:
          children.del(i)
          self.viewSubviews = children
          break

    if view.isNil:
      self.clipDocumentViewId = NSView(value: nil)
      self.clipDocumentRect = nsRect(0, 0, 0, 0)
      self.clipScrollOrigin = nsPoint(0, 0)
      self.setBoundsOrigin(self.clipScrollOrigin)
      return

    let parent = view.viewSuperview()
    if not parent.isNil:
      var siblings = parent.viewSubviews()
      for i, candidate in siblings:
        if candidate.value == view.value:
          siblings.del(i)
          parent.viewSubviews = siblings
          break
      view.viewSuperview = NSView(value: nil)

    var children = self.viewSubviews()
    if view notin children:
      children.add(view)
      self.viewSubviews = children
    view.viewSuperview = retain(asType[NSView](self))
    view.setNextResponder(asType[NSResponder](self))
    self.clipDocumentViewId = retain(view)
    self.clipScrollOrigin = self.constrainScrollPoint(self.clipScrollOrigin)
    self.setBoundsOrigin(self.clipScrollOrigin)
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
    let clipSize = self.bounds().size
    let docRect = self.documentRect()
    nsRect(
      constrained.x,
      constrained.y,
      min(clipSize.width, docRect.size.width),
      min(clipSize.height, docRect.size.height),
    )

  method constrainScrollPoint*(self: NSClipView, point: NSPoint): NSPoint =
    let docRect = self.documentRect()
    let clipSize = self.bounds().size
    let maxX = max(docRect.size.width - clipSize.width, 0.0)
    let maxY = max(docRect.size.height - clipSize.height, 0.0)
    result = nsPoint(clamp(point.x, 0.0, maxX), clamp(point.y, 0.0, maxY))

  method viewBoundsChanged*(self: NSClipView, note: NSObject) =
    discard

  method viewFrameChanged*(self: NSClipView, note: NSObject) =
    discard

  method autoscroll*(self: NSClipView, event: NSObject): bool =
    false

  method scrollToPoint*(self: NSClipView, point: NSPoint) =
    self.clipScrollOrigin = self.constrainScrollPoint(point)
    self.setBoundsOrigin(self.clipScrollOrigin)
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
    var superObj =
      ObjcSuper(receiver: self.value, superClass: getClass(NSClipView).getSuperclass())
    cast[proc(
      superObj: var ObjcSuper,
      op: SEL,
      x: float32,
      y: float32,
      width: float32,
      height: float32,
    ) {.cdecl, varargs.}](objc_msgSendSuper)(
      superObj,
      getSelector("setFrame:y:width:height:"),
      x.float32,
      y.float32,
      max(width.float32, 0.0),
      max(height.float32, 0.0),
    )
    self.clipScrollOrigin = self.constrainScrollPoint(self.clipScrollOrigin)
    self.setBoundsOrigin(self.clipScrollOrigin)
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
    self.xDocumentCursor = NSCursor(value: nil)
    self.clipDocumentViewId = NSView(value: nil)
    discard callSuperIdFrom(NSClipView, self, getSelector("dealloc"))

  method drawRect*(self: NSClipView, rect: NSRect) =
    if self.isNil or (not self.drawsBackground()):
      return
    let bg = self.backgroundColor()
    bg.setFill()
    if rect.size.width > 0.0 and rect.size.height > 0.0:
      NSRectFill(rect)
    else:
      NSRectFill(self.bounds())

  method wantsClipToBounds*(self: NSClipView): bool =
    true

proc new*(t: typedesc[NSClipView]): NSClipView =
  var allocated = NSClipView.alloc()
  result = initOwned(move(allocated))
