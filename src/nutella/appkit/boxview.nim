import ./runtime

objcImpl:

  type NXBox* = object of NXView
    boxType {.set: setBoxType, get: boxType.}: int
    borderType {.set: setBorderType, get: borderType.}: int
    titlePosition {.set: setTitlePosition, get: titlePosition.}: int
    transparent {.set: setTransparent, get: isTransparent.}: bool
    contentMargins {.set: setContentViewMargins, get: contentViewMargins.}: NSSize
    titleId: ID
    boxContentView: ID

  method init*(self: var NXBox): NXBox =
    result = asType[NXBox](callSuperIdFrom(NXBox, self, getSelector("init")))
    if result.isNil:
      return
    result.boxType = 0
    result.borderType = 1
    result.titlePosition = 1
    result.transparent = true
    result.contentMargins = nsSize(0, 0)
    result.titleId = retainId(@ns"".value)
    result.boxContentView = nil

    var contentAlloc = NXView.alloc()
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
      content.setNextResponder(asType[NXResponder](result))
      result.boxContentView = replacedOwnedId(result.boxContentView, content.value)
    content.value = nil

  method title*(self: NXBox): NSString =
    if self.titleId.isNil:
      return @ns""
    ownFromId[NSString](self.titleId)

  method setTitle*(self: NXBox, value: NSString) =
    self.titleId = replacedOwnedId(self.titleId, value.value)

  method setTitleWithMnemonic*(self: NXBox, value: NSString) =
    self.setTitle(stripMnemonicMarkers(value))

  method contentView*(self: NXBox): NXView =
    if self.boxContentView.isNil:
      return NXView(value: nil)
    ownFromId[NXView](self.boxContentView)

  method setContentView*(self: NXBox, view: NXView) =
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
    self.boxContentView = replacedOwnedId(self.boxContentView, view.value)

  method setFrame*(
      self: NXBox,
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

  method dealloc(self: NXBox) {.used.} =
    self.titleId = replacedOwnedId(self.titleId, nil)
    self.boxContentView = replacedOwnedId(self.boxContentView, nil)
    discard callSuperIdFrom(NXBox, self, getSelector("dealloc"))
proc new*(t: typedesc[NSBox]): NSBox =
  when false:
    discard t
  var allocated = NSBox.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

