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

const WindowTitlebarHeight = 28.0'f32

proc titlebarHeightForStyleMask(styleMask: int): float32 =
  if (styleMask and NSTitledWindowMask) != 0:
    return WindowTitlebarHeight
  0.0

proc frameRectForContentRectWithStyle(contentRect: NSRect, styleMask: int): NSRect =
  let titlebarHeight = titlebarHeightForStyleMask(styleMask)
  nsRect(
    contentRect.origin.x,
    contentRect.origin.y,
    max(contentRect.size.width, 1.0),
    max(contentRect.size.height + titlebarHeight, 1.0),
  )

proc contentRectForFrameRectWithStyle(frameRect: NSRect, styleMask: int): NSRect =
  let titlebarHeight = titlebarHeightForStyleMask(styleMask)
  nsRect(
    frameRect.origin.x,
    frameRect.origin.y,
    max(frameRect.size.width, 1.0),
    max(frameRect.size.height - titlebarHeight, 1.0),
  )

objcImpl:
  type NSWindow* = object of NSResponder
    xFrame {.set: windowFrame, get: windowFrame.}: NSRect
    xTitle {.set: windowTitle, get: windowTitle.}: NSString
    xStyleMask {.set: windowStyleMask, get: windowStyleMask.}: int
    xBackingType {.set: setBackingType, get: backingType.}: NSBackingStoreType
    xDeferred {.set: windowDeferred, get: windowDeferred.}: bool
    xReleasedWhenClosed {.set: setReleasedWhenClosed, get: isReleasedWhenClosed.}: bool
    xContentView {.set: windowContentView, get: windowContentView.}: NSView
    xDelegate {.set: setDelegate, get: delegate.}: ID
    xFirstResponder {.set: windowFirstResponder, get: windowFirstResponder.}:
      NSResponder
    xNativeWindow {.set: windowNativeWindow, get: windowNativeWindow.}: siwinshim.Window
    xRenderer {.set: windowRenderer, get: windowRenderer.}:
      figrender.FigRenderer[siwinshim.SiwinRenderBackend]
    xAutoScale {.set: windowAutoScale, get: windowAutoScale.}: bool
    xNativeReady {.set: windowNativeReady, get: windowNativeReady.}: bool
    xVisibleRequested {.set: windowVisibleRequested, get: windowVisibleRequested.}: bool
    xClosed {.set: windowClosed, get: windowClosed.}: bool

  method init*(self: var NSWindow): NSWindow =
    result = asTypeRaw[NSWindow](callSuperIdFrom(NSWindow, self, getSelector("init")))
    if result.isNil:
      return
    result.xFrame = nsRect(100, 100, 640, 420)
    result.xTitle = @ns"KNutella Window"
    result.xStyleMask =
      NSTitledWindowMask or NSClosableWindowMask or NSResizableWindowMask
    result.xBackingType = NSBackingStoreBuffered
    result.xDeferred = false
    result.xReleasedWhenClosed = true
    result.xContentView = NSView(value: nil)
    result.xDelegate.value = nil
    result.xFirstResponder = NSResponder(value: nil)
    result.xNativeWindow = nil
    result.xRenderer = nil
    result.xAutoScale = true
    result.xNativeReady = false
    result.xVisibleRequested = false
    result.xClosed = false

  method initWithContentRect*(
      self: var NSWindow,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
  ): NSWindow =
    result = self.init()
    if result.isNil:
      return
    result.xFrame =
      nsRect(x.float32, y.float32, max(width.float32, 1.0), max(height.float32, 1.0))

  method initWithContentRect*(
      self: var NSWindow,
      x: float32,
      y {.kw("y").}: float32,
      width {.kw("width").}: float32,
      height {.kw("height").}: float32,
      styleMask {.kw("styleMask").}: int,
      backing {.kw("backing").}: NSBackingStoreType,
      deferFlag {.kw("defer").}: bool,
  ): NSWindow =
    result = self.initWithContentRect(x, y, width, height)
    if result.isNil:
      return
    result.xStyleMask = styleMask
    result.xBackingType = backing
    result.xDeferred = deferFlag

  method setContentView*(self: NSWindow, view: NSView) =
    if self.isNil:
      return
    if not self.xContentView.isNil and self.xContentView.value != view.value:
      if self.xFirstResponder.value == self.xContentView.value or
          isViewDescendantOf(self.xFirstResponder.value, self.xContentView.value):
        self.xFirstResponder = NSResponder(value: nil)
      clearSuperviewRef(self.xContentView.value)
    if not view.isNil:
      let parent = view.viewSuperview()
      if not parent.isNil:
        var subviews = parent.viewSubviews()
        for i, candidate in subviews:
          if candidate.value == view.value:
            subviews.del(i)
            parent.viewSubviews = subviews
            break
      view.viewSuperview = NSView(value: nil)
      view.setNextResponder(self as NSResponder)
    self.xContentView = retain(view)

  method contentView*(self: NSWindow): NSView =
    if self.xContentView.isNil:
      return NSView(value: nil)
    result = retain(self.xContentView)

  method frameRectForContentRect*(self: NSWindow, rect: NSRect): NSRect =
    frameRectForContentRectWithStyle(rect, self.windowStyleMask())

  method contentRectForFrameRect*(self: NSWindow, rect: NSRect): NSRect =
    contentRectForFrameRectWithStyle(rect, self.windowStyleMask())

  method firstResponder*(self: NSWindow): NSResponder =
    if self.xFirstResponder.isNil:
      return NSResponder(value: nil)
    retain(self.xFirstResponder)

  method makeFirstResponder*(self: NSWindow, responder: NSResponder): bool =
    if self.isNil:
      return false
    var requested = responder
    if requested.isNil:
      requested = self as NSResponder
    if self.xFirstResponder.value == requested.value:
      return true

    var current = self.xFirstResponder
    if not current.isNil and not current.resignFirstResponder():
      return false

    if not requested.acceptsFirstResponder() or not requested.becomeFirstResponder():
      if not current.isNil and current.acceptsFirstResponder() and
          current.becomeFirstResponder():
        self.xFirstResponder = retain(current)
      return false

    self.xFirstResponder = retain(requested)
    true

  method acceptsFirstResponder*(self: NSWindow): bool =
    true

  method keyDown*(self: NSWindow, event: NSEvent) =
    if (not event.isNil) and siwinPressed(event) and siwinKey(event) == siwin.Key.escape:
      self.performClose(self as NSObject)
      return
    let next = self.nextResponder()
    if not next.isNil:
      next.keyDown(event)
      return
    self.noResponderFor(getSelector("keyDown:"))

  method windowShouldClose*(self: NSWindow, sender: NSObject): bool =
    true

  method performClose*(self: NSWindow, sender: NSObject) =
    if self.isNil:
      return
    if not self.windowShouldClose(sender):
      return
    self.close()

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
    self.xTitle = value
    if self.xNativeReady and not self.xNativeWindow.isNil:
      self.xNativeWindow.title = $value

  method setContentSize*(
      self: NSWindow, width: float32, height {.kw("height").}: float32
  ) =
    var frame = self.xFrame
    frame.size = nsSize(max(width.float32, 1.0), max(height.float32, 1.0))
    self.xFrame = frame
    if self.xNativeReady and not self.xNativeWindow.isNil:
      self.xNativeWindow.size =
        ivec2(clampWindowSize(frame.size.width), clampWindowSize(frame.size.height))

  method setFrameOrigin*(self: NSWindow, x: float32, y {.kw("y").}: float32) =
    var frame = self.xFrame
    frame.origin = nsPoint(x.float32, y.float32)
    self.xFrame = frame

  method makeKeyAndOrderFront*(self: NSWindow, sender: NSObject) =
    if self.isNil:
      return
    self.xVisibleRequested = true

  method orderFront*(self: NSWindow, sender: NSObject) =
    self.makeKeyAndOrderFront(sender)

  method orderOut*(self: NSWindow, sender: NSObject) =
    if self.isNil:
      return
    self.xVisibleRequested = false

  method isVisible*(self: NSWindow): bool =
    (not self.isNil) and self.xVisibleRequested and (not self.xClosed)

  method setIsVisible*(self: NSWindow, value: bool) =
    if self.isNil:
      return
    if value:
      self.makeKeyAndOrderFront(self as NSObject)
    else:
      self.orderOut(self as NSObject)

  method isKeyWindow*(self: NSWindow): bool =
    self.isVisible()

  method isMiniaturized*(self: NSWindow): bool =
    false

  method close*(self: NSWindow) =
    self.xClosed = true
    if self.xNativeReady and not self.xNativeWindow.isNil:
      siwinshim.close(self.xNativeWindow)

  method dealloc(self: NSWindow) {.used.} =
    if self.xNativeReady and (not self.xNativeWindow.isNil):
      siwinshim.close(self.xNativeWindow)
    self.xFirstResponder = NSResponder(value: nil)
    if not self.xContentView.isNil:
      clearSuperviewRef(self.xContentView.value)
    self.xContentView = NSView(value: nil)
    self.xDelegate.value = nil
    destroyIvarFields(self)
    discard callSuperIdFrom(NSWindow, self, getSelector("dealloc"))

objcImpl:
  type NSPanel* = object of NSWindow
    worksWhenModal {.set: setWorksWhenModal, get: worksWhenModal.}: bool
    becomesKeyOnlyIfNeeded {.
      set: setBecomesKeyOnlyIfNeeded, get: becomesKeyOnlyIfNeeded
    .}: bool
    floatingPanel {.set: setFloatingPanel, get: isFloatingPanel.}: bool

  method init*(self: var NSPanel): NSPanel =
    result = asTypeRaw[NSPanel](callSuperIdFrom(NSPanel, self, getSelector("init")))
    if result.isNil:
      return
    result.worksWhenModal = false
    result.becomesKeyOnlyIfNeeded = false
    result.floatingPanel = false

  method canBecomeMainWindow*(self: NSPanel): bool =
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
  window.xFrame = nextFrame
  if window.xNativeReady and not window.xNativeWindow.isNil:
    window.xNativeWindow.size = ivec2(
      clampWindowSize(nextFrame.size.width), clampWindowSize(nextFrame.size.height)
    )

proc frame*(window: NSWindow): NSRect =
  window.xFrame

proc frameOrigin*(window: NSWindow): NSPoint =
  window.xFrame.origin

proc frameSize*(window: NSWindow): NSSize =
  window.xFrame.size

proc setFrameOrigin*(window: NSWindow, origin: NSPoint) =
  let f = window.xFrame
  window.setFrame(nsRect(origin.x, origin.y, f.size.width, f.size.height))

proc setFrameSize*(window: NSWindow, size: NSSize) =
  let f = window.xFrame
  window.setFrame(nsRect(f.origin.x, f.origin.y, size.width, size.height))

proc setContentSize*(window: NSWindow, size: NSSize) =
  window.setFrameSize(size)

proc setContentSize*(window: NSWindow, width, height: float32) =
  window.setContentSize(nsSize(width, height))

proc title*(window: NSWindow): NSString =
  window.xTitle

proc setTitle*(window: NSWindow, value: string) =
  window.setTitle(ns(value))
