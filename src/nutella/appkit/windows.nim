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
    wTitleId: ID
    wContentView: ID
    wFirstResponder: ID
    wNativeWindow: siwinshim.Window
    wRenderer: figrender.FigRenderer[siwinshim.SiwinRenderBackend]
    wAutoScale: bool
    wNativeReady: bool
    wVisibleRequested: bool
    wClosed: bool

  method init*(self: var NSWindow): NSWindow =
    result = asType[NSWindow](callSuperIdFrom(NSWindow, self, getSelector("init")))
    if result.isNil:
      return
    result.frame = nsRect(100, 100, 640, 420)
    result.wTitleId = retainId(@ns"Nutella Window".value)
    result.wContentView = nil
    result.wFirstResponder = nil
    result.wNativeWindow = nil
    result.wRenderer = nil
    result.wAutoScale = true
    result.wNativeReady = false
    result.wVisibleRequested = false
    result.wClosed = false

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

  method setContentView*(self: NSWindow, view: NSView) =
    if self.isNil:
      return
    if not self.wContentView.isNil and self.wContentView != view.value:
      if self.wFirstResponder == self.wContentView or
          isViewDescendantOf(self.wFirstResponder, self.wContentView):
        self.wFirstResponder = replacedOwnedId(self.wFirstResponder, nil)
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

  method contentView*(self: NSWindow): NSView =
    if self.wContentView.isNil:
      return NSView(value: nil)
    result = ownFromId[NSView](self.wContentView)

  method wTitle*(self: NSWindow): NSString =
    if self.wTitleId.isNil:
      return @ns""
    ownFromId[NSString](self.wTitleId)

  method firstResponder*(self: NSWindow): NSResponder =
    if self.wFirstResponder.isNil:
      return NSResponder(value: nil)
    ownFromId[NSResponder](self.wFirstResponder)

  method makeFirstResponder*(self: NSWindow, responder: NSResponder): bool =
    if self.isNil:
      return false
    var requested = responder
    if requested.isNil:
      requested = asType[NSResponder](self)
    if self.wFirstResponder == requested.value:
      return true

    let currentId = self.wFirstResponder()
    var current = ownFromId[NSResponder](currentId)
    if not current.isNil and not current.resignFirstResponder():
      return false

    if not requested.acceptsFirstResponder() or not requested.becomeFirstResponder():
      if not current.isNil and current.acceptsFirstResponder() and
          current.becomeFirstResponder():
        self.wFirstResponder =
          replacedOwnedId(self.wFirstResponder(), current.value)
      return false

    self.wFirstResponder =
      replacedOwnedId(self.wFirstResponder(), requested.value)
    true

  method acceptsFirstResponder*(self: NSWindow): bool =
    true

  method setTitle*(self: NSWindow, value: NSString) =
    self.wTitleId = replacedOwnedId(self.wTitleId, value.value)
    if self.wNativeReady and not self.wNativeWindow.isNil:
      self.wNativeWindow.title = $value

  method setContentSize*(
      self: NSWindow, width: cfloat, height {.kw("height").}: cfloat
  ) =
    var frame = self.frame()
    frame.size = nsSize(max(width.float32, 1.0), max(height.float32, 1.0))
    self.frame = frame
    if self.wNativeReady and not self.wNativeWindow.isNil:
      self.wNativeWindow.size =
        ivec2(clampWindowSize(frame.size.width), clampWindowSize(frame.size.height))

  method setFrameOrigin*(self: NSWindow, x: cfloat, y {.kw("y").}: cfloat) =
    var frame = self.frame()
    frame.origin = nsPoint(x.float32, y.float32)
    self.frame = frame

  method makeKeyAndOrderFront(self: NSWindow, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    self.wVisibleRequested = true

  method orderFront*(self: NSWindow, sender: NSObject) =
    self.makeKeyAndOrderFront(sender)

  method orderOut*(self: NSWindow, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    self.wVisibleRequested = false

  method isVisible*(self: NSWindow): bool =
    (not self.isNil) and self.wVisibleRequested() and (not self.wClosed())

  method isKeyWindow*(self: NSWindow): bool =
    self.isVisible()

  method isMiniaturized*(self: NSWindow): bool =
    false

  method close(self: NSWindow) =
    self.wClosed = true
    if self.wNativeReady and not self.wNativeWindow.isNil:
      siwinshim.close(self.wNativeWindow)

  method dealloc(self: NSWindow) {.used.} =
    if self.wNativeReady and (not self.wNativeWindow.isNil):
      siwinshim.close(self.wNativeWindow)
    self.wFirstResponder = replacedOwnedId(self.wFirstResponder(), nil)
    if not self.wContentView.isNil:
      clearSuperviewRef(self.wContentView)
    self.wTitleId = replacedOwnedId(self.wTitleId, nil)
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
  if window.wNativeReady() and not window.wNativeWindow().isNil:
    window.wNativeWindow.size = ivec2(
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

proc title*(window: NSWindow): NSString =
  window.wTitle()

proc setTitle*(window: NSWindow, value: string) =
  window.setTitle(ns(value))

