import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as figrender
import figdraw/windowing/siwinshim as siwinshim

import ./runtime
import ./responders
import ./views

objcImpl:

  type NSWindow* = object of NSResponder
    frame: NSRect
    windowTitleId: ID
    wContentView: ID
    windowFirstResponder: ID
    windowNativeWindow: siwinshim.Window
    windowRenderer: figrender.FigRenderer[siwinshim.SiwinRenderBackend]
    windowAutoScale: bool
    windowNativeReady: bool
    windowVisibleRequested: bool
    windowClosed: bool

  method init*(self: var NSWindow): NSWindow =
    result = asType[NSWindow](callSuperIdFrom(NSWindow, self, getSelector("init")))
    if result.isNil:
      return
    result.frame = nsRect(100, 100, 640, 420)
    result.windowTitleId = retainId(@ns"Nutella Window".value)
    result.wContentView = nil
    result.windowFirstResponder = nil
    result.windowNativeWindow = nil
    result.windowRenderer = nil
    result.windowAutoScale = true
    result.windowNativeReady = false
    result.windowVisibleRequested = false
    result.windowClosed = false

  method initWithContentRect*(
      self: var NSWindow,
      x: cfloat,
      y {.kw("y").}: cfloat,
      width {.kw("width").}: cfloat,
      height {.kw("height").}: cfloat,
  ): NSWindow =
    result = self.init()
    if result.isNil:
      return
    result.frame =
      nsRect(x.float32, y.float32, max(width.float32, 1.0), max(height.float32, 1.0))

  method setContentView(self: NSWindow, view: NSView) =
    if self.isNil:
      return
    if not self.wContentView.isNil and self.wContentView != view.value:
      if self.windowFirstResponder == self.wContentView or
          isViewDescendantOf(self.windowFirstResponder, self.wContentView):
        self.windowFirstResponder = replacedOwnedId(self.windowFirstResponder, nil)
      clearSuperviewRef(self.wContentView)
    if not view.isNil:
      let parentId = view.viewSuperview()
      if not parentId.isNil:
        var parent = ownFromId[NSView](parentId)
        if not parent.isNil:
          var subviews = parent.viewSubviews()
          for i, candidate in subviews:
            if candidate == view.value:
              subviews.del(i)
              parent.viewSubviews = subviews
              releaseId(view.value)
              break
      view.viewSuperview = nil
      view.setNextResponder(asType[NSResponder](self))
    self.wContentView = replacedOwnedId(self.wContentView(), view.value)

  method contentView(self: NSWindow): NSView =
    if self.wContentView.isNil:
      return NSView(value: nil)
    result = ownFromId[NSView](self.wContentView)

  method windowTitle*(self: NSWindow): NSString =
    if self.windowTitleId.isNil:
      return @ns""
    ownFromId[NSString](self.windowTitleId)

  method firstResponder*(self: NSWindow): NSResponder =
    if self.windowFirstResponder.isNil:
      return NSResponder(value: nil)
    ownFromId[NSResponder](self.windowFirstResponder)

  method makeFirstResponder*(self: NSWindow, responder: NSResponder): bool =
    if self.isNil:
      return false
    var requested = responder
    if requested.isNil:
      requested = asType[NSResponder](self)
    if self.windowFirstResponder == requested.value:
      return true

    let currentId = self.windowFirstResponder()
    var current = ownFromId[NSResponder](currentId)
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

  method acceptsFirstResponder*(self: NSWindow): bool =
    true

  method setTitle*(self: NSWindow, value: NSString) =
    self.windowTitleId = replacedOwnedId(self.windowTitleId, value.value)
    if self.windowNativeReady and not self.windowNativeWindow.isNil:
      self.windowNativeWindow.title = $value

  method setContentSize*(
      self: NSWindow, width: cfloat, height {.kw("height").}: cfloat
  ) =
    var frame = self.frame()
    frame.size = nsSize(max(width.float32, 1.0), max(height.float32, 1.0))
    self.frame = frame
    if self.windowNativeReady and not self.windowNativeWindow.isNil:
      self.windowNativeWindow.size =
        ivec2(clampWindowSize(frame.size.width), clampWindowSize(frame.size.height))

  method setFrameOrigin*(self: NSWindow, x: cfloat, y {.kw("y").}: cfloat) =
    var frame = self.frame()
    frame.origin = nsPoint(x.float32, y.float32)
    self.frame = frame

  method makeKeyAndOrderFront(self: NSWindow, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    self.windowVisibleRequested = true

  method orderFront*(self: NSWindow, sender: NSObject) =
    self.makeKeyAndOrderFront(sender)

  method orderOut*(self: NSWindow, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    self.windowVisibleRequested = false

  method isVisible*(self: NSWindow): bool =
    (not self.isNil) and self.windowVisibleRequested() and (not self.windowClosed())

  method isKeyWindow*(self: NSWindow): bool =
    self.isVisible()

  method isMiniaturized*(self: NSWindow): bool =
    false

  method close(self: NSWindow) =
    self.windowClosed = true
    if self.windowNativeReady and not self.windowNativeWindow.isNil:
      siwinshim.close(self.windowNativeWindow)

  method dealloc(self: NSWindow) {.used.} =
    if self.windowNativeReady and (not self.windowNativeWindow.isNil):
      siwinshim.close(self.windowNativeWindow)
    self.windowFirstResponder = replacedOwnedId(self.windowFirstResponder(), nil)
    if not self.wContentView.isNil:
      clearSuperviewRef(self.wContentView)
    self.windowTitleId = replacedOwnedId(self.windowTitleId, nil)
    self.wContentView = replacedOwnedId(self.wContentView(), nil)
    clearIvarRefs(self)
    discard callSuperIdFrom(NSWindow, self, getSelector("dealloc"))

objcImpl:
  type NSPanel* = object of NSWindow
    worksWhenModal {.set: setWorksWhenModal, get: worksWhenModal.}: bool
    becomesKeyOnlyIfNeeded {.
      set: setBecomesKeyOnlyIfNeeded, get: becomesKeyOnlyIfNeeded
    .}: bool
    floatingPanel {.set: setFloatingPanel, get: isFloatingPanel.}: bool

  method init*(self: var NSPanel): NSPanel =
    result = asType[NSPanel](callSuperIdFrom(NSPanel, self, getSelector("init")))
    if result.isNil:
      return
    result.worksWhenModal = false
    result.becomesKeyOnlyIfNeeded = false
    result.floatingPanel = false

  method canBecomeMainWindow*(self: NSPanel): bool =
    discard self
    false

proc new*(t: typedesc[NSWindow]): NSWindow =
  var allocated = NSWindow.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc new*(t: typedesc[NSPanel]): NSPanel =
  var allocated = NSPanel.alloc()
  result = allocated.init()
  allocated.value = nil
  if result.isNil:
    return

proc setFrame*(window: NSWindow, frame: NSRect) =
  var nextFrame = nsRect(
    frame.origin.x,
    frame.origin.y,
    max(frame.size.width, 1.0),
    max(frame.size.height, 1.0),
  )
  window.frame = nextFrame
  if window.windowNativeReady() and not window.windowNativeWindow().isNil:
    window.windowNativeWindow.size = ivec2(
      clampWindowSize(nextFrame.size.width), clampWindowSize(nextFrame.size.height)
    )

proc frameOrigin*(window: NSWindow): NSPoint =
  window.frame().origin

proc frameSize*(window: NSWindow): NSSize =
  window.frame().size

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

proc title*(window: NSWindow): NSString =
  window.windowTitle()

proc setTitle*(window: NSWindow, value: string) =
  window.setTitle(ns(value))

