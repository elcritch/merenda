import ./runtime

objcImpl:

  type NXWindow* = object of NXResponder
    windowFrame: NSRect
    windowTitleId: ID
    windowContentView: ID
    windowFirstResponder: ID
    windowNativeWindow: siwinshim.Window
    windowRenderer: figrender.FigRenderer[siwinshim.SiwinRenderBackend]
    windowAutoScale: bool
    windowNativeReady: bool
    windowVisibleRequested: bool
    windowClosed: bool

  method init*(self: var NXWindow): NXWindow =
    result = asType[NXWindow](callSuperIdFrom(NXWindow, self, getSelector("init")))
    if result.isNil:
      return
    result.windowFrame = nsRect(100, 100, 640, 420)
    result.windowTitleId = retainId(@ns"Nutella Window".value)
    result.windowContentView = nil
    result.windowFirstResponder = nil
    result.windowNativeWindow = nil
    result.windowRenderer = nil
    result.windowAutoScale = true
    result.windowNativeReady = false
    result.windowVisibleRequested = false
    result.windowClosed = false

  method initWithContentRect*(
      self: var NXWindow,
      x: cfloat,
      y {.kw("y").}: cfloat,
      width {.kw("width").}: cfloat,
      height {.kw("height").}: cfloat,
  ): NXWindow =
    result = self.init()
    if result.isNil:
      return
    result.windowFrame =
      nsRect(x.float32, y.float32, max(width.float32, 1.0), max(height.float32, 1.0))

  method setContentView(self: NXWindow, view: NXView) =
    if self.isNil:
      return
    if not self.windowContentView.isNil and self.windowContentView != view.value:
      if self.windowFirstResponder == self.windowContentView or
          isViewDescendantOf(self.windowFirstResponder, self.windowContentView):
        self.windowFirstResponder = replacedOwnedId(self.windowFirstResponder, nil)
      clearSuperviewRef(self.windowContentView)
    if not view.isNil:
      let parentId = view.viewSuperview()
      if not parentId.isNil:
        var parent = ownFromId[NXView](parentId)
        if not parent.isNil:
          var subviews = parent.viewSubviews()
          for i, candidate in subviews:
            if candidate == view.value:
              subviews.del(i)
              parent.viewSubviews = subviews
              releaseId(view.value)
              break
      view.viewSuperview = nil
      view.setNextResponder(asType[NXResponder](self))
    self.windowContentView = replacedOwnedId(self.windowContentView(), view.value)

  method contentView(self: NXWindow): NXView =
    if self.windowContentView.isNil:
      return NXView(value: nil)
    result = ownFromId[NXView](self.windowContentView)

  method windowTitle*(self: NXWindow): NSString =
    if self.windowTitleId.isNil:
      return @ns""
    ownFromId[NSString](self.windowTitleId)

  method firstResponder*(self: NXWindow): NXResponder =
    if self.windowFirstResponder.isNil:
      return NXResponder(value: nil)
    ownFromId[NXResponder](self.windowFirstResponder)

  method makeFirstResponder*(self: NXWindow, responder: NXResponder): bool =
    if self.isNil:
      return false
    var requested = responder
    if requested.isNil:
      requested = asType[NXResponder](self)
    if self.windowFirstResponder == requested.value:
      return true

    let currentId = self.windowFirstResponder()
    var current = ownFromId[NXResponder](currentId)
    if not current.isNil and not current.resignFirstResponder():
      return false

    if not requested.acceptsFirstResponder() or not requested.becomeFirstResponder():
      if not current.isNil and current.acceptsFirstResponder() and
          current.becomeFirstResponder():
        self.windowFirstResponder =
          replacedOwnedId(self.windowFirstResponder(), current.value)
      return false

    self.windowFirstResponder =
      replacedOwnedId(self.windowFirstResponder(), requested.value)
    true

  method acceptsFirstResponder*(self: NXWindow): bool =
    true

  method setTitle*(self: NXWindow, value: NSString) =
    self.windowTitleId = replacedOwnedId(self.windowTitleId, value.value)
    if self.windowNativeReady and not self.windowNativeWindow.isNil:
      self.windowNativeWindow.title = $value

  method setContentSize*(
      self: NXWindow, width: cfloat, height {.kw("height").}: cfloat
  ) =
    var frame = self.windowFrame()
    frame.size = nsSize(max(width.float32, 1.0), max(height.float32, 1.0))
    self.windowFrame = frame
    if self.windowNativeReady and not self.windowNativeWindow.isNil:
      self.windowNativeWindow.size =
        ivec2(clampWindowSize(frame.size.width), clampWindowSize(frame.size.height))

  method setFrameOrigin*(self: NXWindow, x: cfloat, y {.kw("y").}: cfloat) =
    var frame = self.windowFrame()
    frame.origin = nsPoint(x.float32, y.float32)
    self.windowFrame = frame

  method makeKeyAndOrderFront(self: NXWindow, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    self.windowVisibleRequested = true

  method orderFront*(self: NXWindow, sender: NSObject) =
    self.makeKeyAndOrderFront(sender)

  method orderOut*(self: NXWindow, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    self.windowVisibleRequested = false

  method isVisible*(self: NXWindow): bool =
    (not self.isNil) and self.windowVisibleRequested() and (not self.windowClosed())

  method isKeyWindow*(self: NXWindow): bool =
    self.isVisible()

  method isMiniaturized*(self: NXWindow): bool =
    false

  method close(self: NXWindow) =
    self.windowClosed = true
    if self.windowNativeReady and not self.windowNativeWindow.isNil:
      siwinshim.close(self.windowNativeWindow)

  method dealloc(self: NXWindow) {.used.} =
    if self.windowNativeReady and (not self.windowNativeWindow.isNil):
      siwinshim.close(self.windowNativeWindow)
    self.windowFirstResponder = replacedOwnedId(self.windowFirstResponder(), nil)
    if not self.windowContentView.isNil:
      clearSuperviewRef(self.windowContentView)
    self.windowTitleId = replacedOwnedId(self.windowTitleId, nil)
    self.windowContentView = replacedOwnedId(self.windowContentView(), nil)
    clearIvarRefs(self)
    discard callSuperIdFrom(NXWindow, self, getSelector("dealloc"))

objcImpl:
  type NXPanel* = object of NXWindow
    worksWhenModal {.set: setWorksWhenModal, get: worksWhenModal.}: bool
    becomesKeyOnlyIfNeeded {.
      set: setBecomesKeyOnlyIfNeeded, get: becomesKeyOnlyIfNeeded
    .}: bool
    floatingPanel {.set: setFloatingPanel, get: isFloatingPanel.}: bool

  method init*(self: var NXPanel): NXPanel =
    result = asType[NXPanel](callSuperIdFrom(NXPanel, self, getSelector("init")))
    if result.isNil:
      return
    result.worksWhenModal = false
    result.becomesKeyOnlyIfNeeded = false
    result.floatingPanel = false

  method canBecomeMainWindow*(self: NXPanel): bool =
    discard self
    false

proc new*(t: typedesc[NSWindow]): NSWindow =
  when false:
    discard t
  var allocated = NSWindow.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSPanel]): NSPanel =
  when false:
    discard t
  var allocated = NSPanel.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

