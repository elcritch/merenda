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

type WindowFlushHook* = proc(windowId: IDPtr)

var nextWindowNumberCounter {.threadvar.}: NSInteger
var windowFlushHook {.threadvar.}: WindowFlushHook

proc nextWindowNumber(): NSInteger =
  if nextWindowNumberCounter <= 0:
    nextWindowNumberCounter = 1
  result = nextWindowNumberCounter
  inc nextWindowNumberCounter

proc setWindowFlushHook*(hook: WindowFlushHook) =
  windowFlushHook = hook

proc flushWindowImpl(window: NSWindow)

proc titlebarHeightForStyleMask(styleMask: set[NSWindowDecorations]): float32 =
  if NSTitledWindow in styleMask:
    return WindowTitlebarHeight
  0.0

proc frameRectForContentRectWithStyle(
    contentRect: NSRect, styleMask: set[NSWindowDecorations]
): NSRect =
  let titlebarHeight = titlebarHeightForStyleMask(styleMask)
  nsRect(
    contentRect.origin.x,
    contentRect.origin.y,
    max(contentRect.size.width, 1.0),
    max(contentRect.size.height + titlebarHeight, 1.0),
  )

proc contentRectForFrameRectWithStyle(
    frameRect: NSRect, styleMask: set[NSWindowDecorations]
): NSRect =
  let titlebarHeight = titlebarHeightForStyleMask(styleMask)
  nsRect(
    frameRect.origin.x,
    frameRect.origin.y,
    max(frameRect.size.width, 1.0),
    max(frameRect.size.height - titlebarHeight, 1.0),
  )

proc eventQueueResponder(window: NSWindow): NSResponder =
  if window.isNil:
    return NSResponder(value: nil)
  var current = window.nextResponder()
  while not current.isNil:
    if current.respondsToSelector("postEvent:atStart:") and
        current.respondsToSelector("nextEventMatchingMask:untilDate:inMode:dequeue:"):
      return current
    current = current.nextResponder()
  NSResponder(value: nil)

proc viewForWindowPoint(window: NSWindow, locationInWindow: NSPoint): NSView
proc mousePinnedDispatchTarget(window: NSWindow): NSResponder

objcImpl:
  type NSWindow* = object of NSResponder
    xWindowNumber {.get: windowNumber.}: NSInteger
    xFrame {.set: windowFrame, get: windowFrame.}: NSRect
    xTitle {.set: windowTitle, get: windowTitle.}: NSString
    xStyleMask {.set: setStyleMask, get: styleMask.}: set[NSWindowDecorations]
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
    xMouseDownLocationInWindow: NSPoint
    xMouseDownView: NSView
    xHasMouseDownLocation: bool

  method init*(self: var NSWindow): NSWindow =
    result = asTypeRaw[NSWindow](callSuperIdFrom(NSWindow, self, getSelector("init")))
    if result.isNil:
      return
    result.xWindowNumber = nextWindowNumber()
    result.xFrame = nsRect(100, 100, 640, 420)
    result.xTitle = @ns"KNutella Window"
    result.xStyleMask = {NSTitledWindow, NSClosableWindow, NSResizableWindow}
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
    result.xMouseDownLocationInWindow = nsPoint(0.0, 0.0)
    result.xMouseDownView = NSView(value: nil)
    result.xHasMouseDownLocation = false

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
      styleMask {.kw("styleMask").}: set[NSWindowDecorations],
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
      self.xContentView.setWindow(NSWindow(value: nil))
      clearSuperviewRef(self.xContentView.value)
    if not view.isNil:
      let parent = view.superview()
      if not parent.isNil:
        var subviews = parent.subviews()
        for i, candidate in subviews:
          if candidate.value == view.value:
            subviews.del(i)
            parent.xSubviews = subviews
            break
      view.xSetSuperView(NSView(value: nil))
      view.setNextResponder(self as NSResponder)
    self.xContentView = retain(view)
    if not self.xContentView.isNil:
      self.xContentView.setWindow(self)

  method contentView*(self: NSWindow): NSView =
    if self.xContentView.isNil:
      return NSView(value: nil)
    result = retain(self.xContentView)

  method frameRectForContentRect*(self: NSWindow, rect: NSRect): NSRect =
    frameRectForContentRectWithStyle(rect, self.styleMask())

  method contentRectForFrameRect*(self: NSWindow, rect: NSRect): NSRect =
    contentRectForFrameRectWithStyle(rect, self.styleMask())

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

  method performKeyEquivalent*(self: NSWindow, event: NSEvent): bool =
    if self.isNil or event.isNil:
      return false
    let first = self.firstResponder()
    if not first.isNil and first.performKeyEquivalent(event):
      return true
    let content = self.contentView()
    if not content.isNil and content.performKeyEquivalent(event):
      return true
    false

  method postEvent*(self: NSWindow, event: NSEvent, atStart {.kw("atStart").}: bool) =
    if self.isNil or event.isNil:
      return
    let responder = eventQueueResponder(self)
    if responder.isNil:
      self.sendEvent(event)
      return
    cast[proc(self: IDPtr, op: SEL, event: IDPtr, atStart: bool) {.cdecl, varargs.}](objc_msgSend)(
      responder.value, getSelector("postEvent:atStart:"), event.value, atStart
    )

  method nextEventMatchingMask*(
      self: NSWindow,
      mask: NSEventMask,
      untilDate {.kw("untilDate").}: float,
      inMode {.kw("inMode").}: NSString,
      dequeue {.kw("dequeue").}: bool,
  ): NSEvent =
    if self.isNil:
      return NSEvent(value: nil)
    let responder = eventQueueResponder(self)
    if responder.isNil:
      return NSEvent(value: nil)
    let eventId = cast[proc(
      self: IDPtr,
      op: SEL,
      mask: NSEventMask,
      untilDate: float,
      inMode: IDPtr,
      dequeue: bool,
    ): IDPtr {.cdecl, varargs.}](objc_msgSend)(
      responder.value,
      getSelector("nextEventMatchingMask:untilDate:inMode:dequeue:"),
      mask,
      untilDate,
      inMode.value,
      dequeue,
    )
    ownFromId[NSEvent](eventId)

  method keyDispatchTarget(self: NSWindow): NSResponder =
    if self.isNil:
      return NSResponder(value: nil)
    let first = self.firstResponder()
    if not first.isNil:
      return first
    NSResponder(self)

  method sendEvent*(self: NSWindow, event: NSEvent) =
    if self.isNil or event.isNil:
      return
    case event.`type`()
    of NSLeftMouseDown:
      let hit = viewForWindowPoint(self, event.locationInWindow())
      if not hit.isNil:
        discard self.makeFirstResponder(NSResponder(hit))
        self.xMouseDownView = retain(hit)
        self.xMouseDownLocationInWindow = event.locationInWindow()
        self.xHasMouseDownLocation = true
        hit.mouseDown(event)
      else:
        self.xHasMouseDownLocation = false
        self.mouseDown(event)
    of NSLeftMouseUp:
      let target = mousePinnedDispatchTarget(self)
      target.mouseUp(event)
      self.xMouseDownView = NSView(value: nil)
      self.xHasMouseDownLocation = false
    of NSRightMouseDown:
      let hit = viewForWindowPoint(self, event.locationInWindow())
      if not hit.isNil:
        self.xMouseDownView = retain(hit)
        self.xMouseDownLocationInWindow = event.locationInWindow()
        self.xHasMouseDownLocation = true
        hit.rightMouseDown(event)
      else:
        self.xHasMouseDownLocation = false
        self.rightMouseDown(event)
    of NSRightMouseUp:
      let target = mousePinnedDispatchTarget(self)
      target.rightMouseUp(event)
      self.xMouseDownView = NSView(value: nil)
      self.xHasMouseDownLocation = false
    of NSOtherMouseDown:
      let hit = viewForWindowPoint(self, event.locationInWindow())
      if not hit.isNil:
        self.xMouseDownView = retain(hit)
        self.xMouseDownLocationInWindow = event.locationInWindow()
        self.xHasMouseDownLocation = true
        hit.otherMouseDown(event)
      else:
        self.xHasMouseDownLocation = false
        self.otherMouseDown(event)
    of NSOtherMouseUp:
      let target = mousePinnedDispatchTarget(self)
      target.otherMouseUp(event)
      self.xMouseDownView = NSView(value: nil)
      self.xHasMouseDownLocation = false
    of NSMouseMoved:
      let hit = viewForWindowPoint(self, event.locationInWindow())
      if not hit.isNil:
        hit.mouseMoved(event)
      else:
        self.mouseMoved(event)
    of NSScrollWheel:
      let hit = viewForWindowPoint(self, event.locationInWindow())
      if not hit.isNil:
        hit.scrollWheel(event)
      else:
        self.scrollWheel(event)
    of NSMouseEntered:
      let hit = viewForWindowPoint(self, event.locationInWindow())
      if not hit.isNil:
        hit.mouseEntered(event)
      else:
        self.mouseEntered(event)
    of NSMouseExited:
      let hit = viewForWindowPoint(self, event.locationInWindow())
      if not hit.isNil:
        hit.mouseExited(event)
      else:
        self.mouseExited(event)
    of NSLeftMouseDragged:
      let target = mousePinnedDispatchTarget(self)
      target.mouseDragged(event)
    of NSRightMouseDragged:
      let target = mousePinnedDispatchTarget(self)
      target.rightMouseDragged(event)
    of NSOtherMouseDragged:
      let target = mousePinnedDispatchTarget(self)
      target.otherMouseDragged(event)
    of NSKeyDown:
      let target = self.keyDispatchTarget()
      target.keyDown(event)
    of NSKeyUp:
      let target = self.keyDispatchTarget()
      target.keyUp(event)
    of NSFlagsChanged:
      let target = self.keyDispatchTarget()
      target.flagsChanged(event)
    of NSApplicationDefined:
      if isTextInputEvent(event):
        let target = self.keyDispatchTarget()
        let text = event.characters()
        if not text.isNil:
          target.insertText(text.NSObject)
      else:
        discard
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

  method xInvalidateTrackingAreas*(self: NSWindow) =
    discard

  method xResetCursorRectsInView*(self: NSWindow, view: NSView) =
    discard

  method invalidateCursorRectsForView*(self: NSWindow, view: NSView) =
    view.discardCursorRects()
    self.xResetCursorRectsInView(view)
    self.xInvalidateTrackingAreas()

  method flushWindow*(self: NSWindow) =
    flushWindowImpl(self)

  method close*(self: NSWindow) =
    self.xClosed = true
    if self.xNativeReady and not self.xNativeWindow.isNil:
      siwinshim.close(self.xNativeWindow)

  method dealloc(self: NSWindow) {.used.} =
    if self.xNativeReady and (not self.xNativeWindow.isNil):
      siwinshim.close(self.xNativeWindow)
    self.xFirstResponder = NSResponder(value: nil)
    self.xMouseDownView = NSView(value: nil)
    self.xHasMouseDownLocation = false
    if not self.xContentView.isNil:
      clearSuperviewRef(self.xContentView.value)
    self.xContentView = NSView(value: nil)
    self.xDelegate.value = nil
    destroyIvarFields(self)
    discard callSuperIdFrom(NSWindow, self, getSelector("dealloc"))

proc viewForWindowPoint(window: NSWindow, locationInWindow: NSPoint): NSView =
  if window.isNil:
    return NSView(value: nil)
  let content = window.contentView()
  if content.isNil:
    return NSView(value: nil)
  let localPoint = content.convertPoint(locationInWindow, NSView(value: nil))
  let hit = content.hitTest(localPoint)
  if not hit.isNil:
    return hit
  content

proc mousePinnedDispatchTarget(window: NSWindow): NSResponder =
  if window.isNil:
    return NSResponder(value: nil)
  if window.xHasMouseDownLocation:
    let hit = viewForWindowPoint(window, window.xMouseDownLocationInWindow)
    if not hit.isNil:
      return NSResponder(hit)
    if not window.xMouseDownView.isNil:
      return NSResponder(window.xMouseDownView)
  let first = window.firstResponder()
  if not first.isNil:
    return first
  NSResponder(window)

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

proc pumpNativeWindowFrame*(window: NSWindow) =
  if window.isNil:
    return
  let nativeWindow = window.windowNativeWindow()
  if nativeWindow.isNil or not nativeWindow.opened():
    return
  nativeWindow.redraw()
  nativeWindow.step()

proc flushWindowImpl(window: NSWindow) =
  if window.isNil:
    return
  let hook = windowFlushHook
  if not hook.isNil:
    hook(window.value)
    return
  pumpNativeWindowFrame(window)

proc title*(window: NSWindow): NSString =
  window.xTitle

proc setTitle*(window: NSWindow, value: string) =
  window.setTitle(ns(value))
