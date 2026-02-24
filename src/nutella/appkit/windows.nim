import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as figrender
import figdraw/windowing/siwinshim as siwinshim
import siwin/window as siwin

import ./runtime
import ./responders
import ./views
import ./events

export responders, views

objcImpl:
  type NSWindow* = object of NSResponder
    xxFrame {.set: windowFrame, get: windowFrame.}: NSRect
    xxTitle {.set: windowTitle, get: windowTitle.}: NSString
    xxContentView {.set: windowContentView, get: windowContentView.}: ID
    xxFirstResponder {.set: windowFirstResponder, get: windowFirstResponder.}: ID
    xxNativeWindow {.set: windowNativeWindow, get: windowNativeWindow.}:
      siwinshim.Window
    xxRenderer {.set: windowRenderer, get: windowRenderer.}:
      figrender.FigRenderer[siwinshim.SiwinRenderBackend]
    xxAutoScale {.set: windowAutoScale, get: windowAutoScale.}: bool
    xxNativeReady {.set: windowNativeReady, get: windowNativeReady.}: bool
    xxVisibleRequested {.set: windowVisibleRequested, get: windowVisibleRequested.}:
      bool
    xxClosed {.set: windowClosed, get: windowClosed.}: bool

  method init*(self: var NSWindow): NSWindow =
    result = asType[NSWindow](callSuperIdFrom(NSWindow, self, getSelector("init")))
    if result.isNil:
      return
    result.xxFrame = nsRect(100, 100, 640, 420)
    result.xxTitle = @ns"Nutella Window"
    result.xxContentView = nil
    result.xxFirstResponder = nil
    result.xxNativeWindow = nil
    result.xxRenderer = nil
    result.xxAutoScale = true
    result.xxNativeReady = false
    result.xxVisibleRequested = false
    result.xxClosed = false

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
    result.xxFrame =
      nsRect(x.float32, y.float32, max(width.float32, 1.0), max(height.float32, 1.0))

  method setContentView*(self: NSWindow, view: NSView) =
    if self.isNil:
      return
    if not self.xxContentView.isNil and self.xxContentView != view.value:
      if self.xxFirstResponder == self.xxContentView or
          isViewDescendantOf(self.xxFirstResponder, self.xxContentView):
        self.xxFirstResponder = replacedOwnedId(self.xxFirstResponder, nil)
      clearSuperviewRef(self.xxContentView)
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
    self.xxContentView = replacedOwnedId(self.xxContentView, view.value)

  method contentView*(self: NSWindow): NSView =
    if self.xxContentView.isNil:
      return NSView(value: nil)
    result = ownFromId[NSView](self.xxContentView)

  method firstResponder*(self: NSWindow): NSResponder =
    if self.xxFirstResponder.isNil:
      return NSResponder(value: nil)
    ownFromId[NSResponder](self.xxFirstResponder)

  method makeFirstResponder*(self: NSWindow, responder: NSResponder): bool =
    if self.isNil:
      return false
    var requested = responder
    if requested.isNil:
      requested = asType[NSResponder](self)
    if self.xxFirstResponder == requested.value:
      return true

    let currentId = self.xxFirstResponder
    var current = ownFromId[NSResponder](currentId)
    if not current.isNil and not current.resignFirstResponder():
      return false

    if not requested.acceptsFirstResponder() or not requested.becomeFirstResponder():
      if not current.isNil and current.acceptsFirstResponder() and
          current.becomeFirstResponder():
        self.xxFirstResponder = replacedOwnedId(self.xxFirstResponder, current.value)
      return false

    self.xxFirstResponder = replacedOwnedId(self.xxFirstResponder, requested.value)
    true

  method acceptsFirstResponder*(self: NSWindow): bool =
    true

  method keyDown*(self: NSWindow, event: NSEvent) =
    if (not event.isNil) and siwinPressed(event) and siwinKey(event) == siwin.Key.escape:
      self.close()
      return
    let next = self.nextResponder()
    if not next.isNil:
      next.keyDown(event)
      return
    self.noResponderFor(getSelector("keyDown:"))

  method eventDispatchTarget(self: NSWindow): NSResponder =
    if self.isNil:
      return NSResponder(value: nil)
    let first = self.firstResponder()
    if not first.isNil:
      return first
    let content = self.contentView()
    if not content.isNil:
      return ownFromId[NSResponder](content.value)
    ownFromId[NSResponder](self.value)

  method sendEvent*(self: NSWindow, event: NSEvent) =
    if self.isNil or event.isNil:
      return
    let target = self.eventDispatchTarget()
    if target.isNil:
      return
    case event.`type`()
    of NSLeftMouseDown:
      target.mouseDown(event)
    of NSLeftMouseUp:
      target.mouseUp(event)
    of NSRightMouseDown:
      target.rightMouseDown(event)
    of NSRightMouseUp:
      target.rightMouseUp(event)
    of NSMouseMoved:
      target.mouseMoved(event)
    of NSLeftMouseDragged:
      target.mouseDragged(event)
    of NSRightMouseDragged:
      target.rightMouseDragged(event)
    of NSMouseEntered:
      target.mouseEntered(event)
    of NSMouseExited:
      target.mouseExited(event)
    of NSKeyDown:
      target.keyDown(event)
    of NSKeyUp:
      target.keyUp(event)
    of NSFlagsChanged:
      target.flagsChanged(event)
    of NSScrollWheel:
      target.scrollWheel(event)
    else:
      discard

  method setTitle*(self: NSWindow, value: NSString) =
    self.xxTitle = value
    if self.xxNativeReady and not self.xxNativeWindow.isNil:
      self.xxNativeWindow.title = $value

  method setContentSize*(
      self: NSWindow, width: cfloat, height {.kw("height").}: cfloat
  ) =
    var frame = self.xxFrame
    frame.size = nsSize(max(width.float32, 1.0), max(height.float32, 1.0))
    self.xxFrame = frame
    if self.xxNativeReady and not self.xxNativeWindow.isNil:
      self.xxNativeWindow.size =
        ivec2(clampWindowSize(frame.size.width), clampWindowSize(frame.size.height))

  method setFrameOrigin*(self: NSWindow, x: cfloat, y {.kw("y").}: cfloat) =
    var frame = self.xxFrame
    frame.origin = nsPoint(x.float32, y.float32)
    self.xxFrame = frame

  method makeKeyAndOrderFront*(self: NSWindow, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    self.xxVisibleRequested = true

  method orderFront*(self: NSWindow, sender: NSObject) =
    self.makeKeyAndOrderFront(sender)

  method orderOut*(self: NSWindow, sender: NSObject) =
    discard sender
    if self.isNil:
      return
    self.xxVisibleRequested = false

  method isVisible*(self: NSWindow): bool =
    (not self.isNil) and self.xxVisibleRequested and (not self.xxClosed)

  method isKeyWindow*(self: NSWindow): bool =
    self.isVisible()

  method isMiniaturized*(self: NSWindow): bool =
    false

  method close*(self: NSWindow) =
    self.xxClosed = true
    if self.xxNativeReady and not self.xxNativeWindow.isNil:
      siwinshim.close(self.xxNativeWindow)

  method dealloc(self: NSWindow) {.used.} =
    if self.xxNativeReady and (not self.xxNativeWindow.isNil):
      siwinshim.close(self.xxNativeWindow)
    self.xxFirstResponder = replacedOwnedId(self.xxFirstResponder, nil)
    if not self.xxContentView.isNil:
      clearSuperviewRef(self.xxContentView)
    self.xxContentView = replacedOwnedId(self.xxContentView, nil)
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
  result = initOwned(move(allocated))

proc new*(t: typedesc[NSPanel]): NSPanel =
  var allocated = NSPanel.alloc()
  result = initOwned(move(allocated))

proc setFrame*(window: NSWindow, frame: NSRect) =
  var nextFrame = nsRect(
    frame.origin.x,
    frame.origin.y,
    max(frame.size.width, 1.0),
    max(frame.size.height, 1.0),
  )
  window.xxFrame = nextFrame
  if window.xxNativeReady and not window.xxNativeWindow.isNil:
    window.xxNativeWindow.size = ivec2(
      clampWindowSize(nextFrame.size.width), clampWindowSize(nextFrame.size.height)
    )

proc frame*(window: NSWindow): NSRect =
  window.xxFrame

proc frameOrigin*(window: NSWindow): NSPoint =
  window.xxFrame.origin

proc frameSize*(window: NSWindow): NSSize =
  window.xxFrame.size

proc setFrameOrigin*(window: NSWindow, origin: NSPoint) =
  let f = window.xxFrame
  window.setFrame(nsRect(origin.x, origin.y, f.size.width, f.size.height))

proc setFrameSize*(window: NSWindow, size: NSSize) =
  let f = window.xxFrame
  window.setFrame(nsRect(f.origin.x, f.origin.y, size.width, size.height))

proc setContentSize*(window: NSWindow, size: NSSize) =
  window.setFrameSize(size)

proc setContentSize*(window: NSWindow, width, height: float32) =
  window.setContentSize(nsSize(width, height))

proc title*(window: NSWindow): NSString =
  window.xxTitle

proc setTitle*(window: NSWindow, value: string) =
  window.setTitle(ns(value))
