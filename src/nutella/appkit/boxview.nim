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
    boxContentView: NSView

  method init*(self: var NSBox): NSBox =
    result = asTypeRaw[NSBox](callSuperIdFrom(NSBox, self, getSelector("init")))
    if result.isNil:
      return
    result.boxType = 0
    result.borderType = 1
    result.titlePosition = 1
    result.transparent = true
    result.contentMargins = nsSize(0, 0)
    result.title = @ns""
    result.boxContentView = NSView(value: nil)

    var contentAlloc = NSView.alloc()
    var content = contentAlloc.initWithFrame(
      0'f32,
      0'f32,
      result.viewFrame().size.width.float32,
      result.viewFrame().size.height.float32,
    )
    contentAlloc.value = nil
    if not content.isNil:
      var children = result.viewSubviews()
      children.add(content)
      result.viewSubviews = children
      content.viewSuperview = retain(asRetainedType[NSView](result))
      content.setNextResponder(asRetainedType[NSResponder](result))
      result.boxContentView = retain(content)
    content.value = nil

  method setTitleWithMnemonic*(self: NSBox, value: NSString) =
    self.setTitle(stripMnemonicMarkers(value))

  method contentView*(self: NSBox): NSView =
    if self.boxContentView.isNil:
      return NSView(value: nil)
    retain(self.boxContentView)

  method setContentView*(self: NSBox, view: NSView) =
    if self.isNil:
      return
    if self.boxContentView.value == view.value:
      return

    if not self.boxContentView.isNil:
      clearSuperviewRef(self.boxContentView.value)
      var children = self.viewSubviews()
      for i, candidate in children:
        if candidate.value == self.boxContentView.value:
          children.del(i)
          self.viewSubviews = children
          break

    if view.isNil:
      self.boxContentView = NSView(value: nil)
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
    view.viewSuperview = retain(asRetainedType[NSView](self))
    view.setNextResponder(asRetainedType[NSResponder](self))
    self.boxContentView = retain(view)

  method setFrame*(
      self: NSBox,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ) =
    self.viewFrame =
      nsRect(x.float32, y.float32, max(width.float32, 0.0), max(height.float32, 0.0))
    let content = self.contentView()
    if not content.isNil:
      content.setFrame(
        0'f32,
        0'f32,
        self.viewFrame().size.width.float32,
        self.viewFrame().size.height.float32,
      )

  method dealloc(self: NSBox) {.used.} =
    self.boxContentView = NSView(value: nil)
    discard callSuperIdFrom(NSBox, self, getSelector("dealloc"))

proc new*(t: typedesc[NSBox]): NSBox =
  var allocated = NSBox.alloc()
  result = initOwned(move(allocated))
