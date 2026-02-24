import ./runtime
import ./responders
import ./views

objcImpl:
  type NSBox* = object of NSView
    boxType {.set: setBoxType, get: boxType.}: int
    borderType {.set: setBorderType, get: borderType.}: int
    titlePosition {.set: setTitlePosition, get: titlePosition.}: int
    transparent {.set: setTransparent, get: isTransparent.}: bool
    contentMargins {.set: setContentViewMargins, get: contentViewMargins.}: NSSize
    title {.set: setTitle, get: title.}: NSString
    boxContentView: ID

  method init*(self: var NSBox): NSBox =
    result = asType[NSBox](callSuperIdFrom(NSBox, self, getSelector("init")))
    if result.isNil:
      return
    result.boxType = 0
    result.borderType = 1
    result.titlePosition = 1
    result.transparent = true
    result.contentMargins = nsSize(0, 0)
    result.title = @ns""
    result.boxContentView = nil

    var contentAlloc = NSView.alloc()
    var content = contentAlloc.initWithFrame(
      0.cfloat,
      0.cfloat,
      result.viewFrame().size.width.cfloat,
      result.viewFrame().size.height.cfloat,
    )
    contentAlloc.value = nil
    if not content.isNil:
      var children = result.viewSubviews()
      children.add(retainId(content.value))
      result.viewSubviews = children
      content.viewSuperview = result.value
      content.setNextResponder(asType[NSResponder](result))
      result.boxContentView = replacedOwnedId(result.boxContentView, content.value)
    content.value = nil

  method setTitleWithMnemonic*(self: NSBox, value: NSString) =
    self.setTitle(stripMnemonicMarkers(value))

  method contentView*(self: NSBox): NSView =
    if self.boxContentView.isNil:
      return NSView(value: nil)
    ownFromId[NSView](self.boxContentView)

  method setContentView*(self: NSBox, view: NSView) =
    if self.isNil:
      return
    if self.boxContentView == view.value:
      return

    if not self.boxContentView.isNil:
      clearSuperviewRef(self.boxContentView)
      var children = self.viewSubviews()
      for i, candidate in children:
        if candidate == self.boxContentView:
          children.del(i)
          self.viewSubviews = children
          releaseId(candidate)
          break

    if view.isNil:
      self.boxContentView = replacedOwnedId(self.boxContentView, nil)
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
    self.boxContentView = replacedOwnedId(self.boxContentView, view.value)

  method setFrame*(
      self: NSBox,
      x: cfloat,
      y {.kw("y").}: cfloat,
      width {.kw("width").}: cfloat,
      height {.kw("height").}: cfloat,
  ) =
    self.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))
    let content = self.contentView()
    if not content.isNil:
      content.setFrame(
        0.cfloat,
        0.cfloat,
        self.viewFrame().size.width.cfloat,
        self.viewFrame().size.height.cfloat,
      )

  method dealloc(self: NSBox) {.used.} =
    self.boxContentView = replacedOwnedId(self.boxContentView, nil)
    discard callSuperIdFrom(NSBox, self, getSelector("dealloc"))

proc new*(t: typedesc[NSBox]): NSBox =
  var allocated = NSBox.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return
