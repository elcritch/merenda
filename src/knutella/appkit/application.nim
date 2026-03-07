import std/[os, times]

import figdraw/windowing/siwinshim as siwinshim

import ./runtime
import ./responders
import ./windows
import ./views
import ./buttons
import ./textfields
import ./rendering
import ./events

proc runApplicationFrames(app: NSObject, maxFrames: int): int

proc referenceTimestampNow(): float =
  epochTime() - 978_307_200.0

proc windowMatchesEventMask(eventId: IDPtr, mask: NSEventMask): bool =
  if eventId.isNil:
    return false
  let event = ownFromId[NSEvent](eventId)
  if event.isNil:
    return false
  event.`type`() in mask

proc eventQueueIndexForMask(queue: seq[IDPtr], mask: NSEventMask): int =
  for i, id in queue:
    if windowMatchesEventMask(id, mask):
      return i
  -1

objcImpl:
  type NSApplication* = object of NSResponder
    appWindows: seq[IDPtr]
    appEventQueue: seq[IDPtr]
    appCurrentEvent: NSEvent
    appRunning: bool

  method init*(self: var NSApplication): NSApplication =
    result = asTypeRaw[NSApplication](
      callSuperIdFrom(NSApplication, self, getSelector("init"))
    )
    if result.isNil:
      return
    result.appWindows = @[]
    result.appEventQueue = @[]
    result.appCurrentEvent = NSEvent(value: nil)
    result.appRunning = false

  method addWindow(self: NSApplication, window: NSWindow) =
    if self.isNil or window.isNil:
      return
    var windows = self.appWindows()
    if window.value notin windows:
      windows.add(retainId(window.value))
      self.appWindows = windows
    window.setNextResponder(self.NSResponder)
    window.windowVisibleRequested true

  method run(self: NSApplication) =
    discard runApplicationFrames(self, -1)

  method keyWindow*(self: NSApplication): NSWindow =
    if self.isNil:
      return NSWindow(value: nil)
    let windows = self.appWindows()
    var i = windows.high
    while i >= 0:
      let window = ownFromId[NSWindow](windows[i])
      if (not window.isNil) and (not window.windowClosed()) and
          window.windowVisibleRequested():
        return window
      dec i
    NSWindow(value: nil)

  method mainWindow*(self: NSApplication): NSWindow =
    if self.isNil:
      return NSWindow(value: nil)
    let key = self.keyWindow()
    if not key.isNil:
      return key
    let windows = self.appWindows()
    for id in windows:
      let window = ownFromId[NSWindow](id)
      if (not window.isNil) and (not window.windowClosed()) and
          window.windowVisibleRequested():
        return window
    NSWindow(value: nil)

  method currentEvent*(self: NSApplication): NSEvent =
    if self.isNil or self.appCurrentEvent.isNil:
      return NSEvent(value: nil)
    retain(self.appCurrentEvent)

  method postEvent*(
      self: NSApplication, event: NSEvent, atStart {.kw("atStart").}: bool
  ) =
    if self.isNil or event.isNil:
      return
    var queue = self.appEventQueue()
    let retained = retainId(event.value)
    if atStart:
      queue.insert(retained, 0)
    else:
      queue.add(retained)
    self.appEventQueue = queue

  method discardEventsMatchingMask*(
      self: NSApplication, mask: NSEventMask, beforeEvent {.kw("beforeEvent").}: NSEvent
  ) =
    if self.isNil or mask.len == 0:
      return
    var queue = self.appEventQueue()
    let beforeId = if beforeEvent.isNil: nil else: beforeEvent.value
    var i = 0
    while i < queue.len:
      if beforeId == queue[i]:
        break
      if windowMatchesEventMask(queue[i], mask):
        removeOwnedIdAt(queue, i)
        continue
      inc i
    self.appEventQueue = queue

  method xStepNativeWindows(self: NSApplication): bool =
    if self.isNil:
      return false
    var windows = self.appWindows()
    var i = 0
    while i < windows.len:
      let window = ownFromId[NSWindow](windows[i])
      if window.isNil:
        removeOwnedIdAt(windows, i)
        continue
      if window.windowClosed():
        removeOwnedIdAt(windows, i)
        continue
      if not window.windowVisibleRequested():
        inc i
        continue
      try:
        ensureNativeWindow(window)
      except CatchableError:
        removeOwnedIdAt(windows, i)
        self.appWindows = windows
        raise
      let nativeWindow = window.windowNativeWindow()
      if (not nativeWindow.isNil) and nativeWindow.opened():
        nativeWindow.step()
        result = true
      if (not nativeWindow.isNil) and nativeWindow.closed():
        window.windowClosed true
        removeOwnedIdAt(windows, i)
        continue
      inc i
    self.appWindows = windows

  method nextEventMatchingMask*(
      self: NSApplication,
      mask: NSEventMask,
      untilDate {.kw("untilDate").}: float,
      inMode {.kw("inMode").}: NSString,
      dequeue {.kw("dequeue").}: bool,
  ): NSEvent =
    discard inMode
    if self.isNil or mask.len == 0:
      return NSEvent(value: nil)

    while true:
      var queue = self.appEventQueue()
      let idx = eventQueueIndexForMask(queue, mask)
      if idx >= 0:
        let eventId = queue[idx]
        if dequeue:
          queue.del(idx)
          self.appEventQueue = queue
        result = ownFromId[NSEvent](eventId)
        self.appCurrentEvent = retain(result)
        if dequeue:
          releaseId(eventId)
        return

      if (not dequeue) or untilDate <= 0.0 or referenceTimestampNow() >= untilDate:
        return NSEvent(value: nil)

      if not self.xStepNativeWindows():
        if referenceTimestampNow() >= untilDate:
          return NSEvent(value: nil)
        sleep(1)
      if referenceTimestampNow() >= untilDate:
        return NSEvent(value: nil)

  method sendEvent*(self: NSApplication, event: NSEvent) =
    if self.isNil or event.isNil:
      return
    self.appCurrentEvent = retain(event)

    if event.`type`() == NSKeyDown:
      let flags = event.modifierFlags()
      if NSCommandKeyMask in flags or NSAlternateKeyMask in flags:
        let keyWindow = self.keyWindow()
        if not keyWindow.isNil and keyWindow.performKeyEquivalent(event):
          return
        let mainWindow = self.mainWindow()
        if (not mainWindow.isNil) and mainWindow.value != keyWindow.value and
            mainWindow.performKeyEquivalent(event):
          return

    let eventWindowNumber = event.windowNumber()
    if eventWindowNumber != 0:
      let windows = self.appWindows()
      for id in windows:
        let window = ownFromId[NSWindow](id)
        if window.isNil or window.windowClosed():
          continue
        if window.windowNumber() == eventWindowNumber:
          window.sendEvent(event)
          return

    let keyWindow = self.keyWindow()
    if not keyWindow.isNil:
      keyWindow.sendEvent(event)

  method sendAction*(
      self: NSApplication,
      action: SEL,
      target {.kw("to").}: ID,
      sender {.kw("from").}: ID,
  ): bool =
    let senderObj = self.NSObject
    if not target.isNil:
      let targetObj = target.value.NSObject
      return performResponderSelector(targetObj, action, senderObj)
    let responder = self.NSResponder
    responder.tryToPerform(action, senderObj)

  method stop(self: NSApplication) =
    self.appRunning = false

  method dealloc(self: NSApplication) {.used.} =
    var windows = self.appWindows()
    var queue = self.appEventQueue()
    clearOwnedIds(windows)
    clearOwnedIds(queue)
    self.appWindows = windows
    self.appEventQueue = queue
    self.appCurrentEvent = NSEvent(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(NSApplication, self, getSelector("dealloc"))

var sharedApplicationRef {.threadvar.}: NSApplication

proc runApplicationFrames(app: NSObject, maxFrames: int): int =
  let app = NSApplication(app)
  app.appRunning = true
  var windows = app.appWindows()
  while app.appRunning():
    var activeWindows = 0
    var i = 0
    while i < windows.len:
      let window = ownFromId[NSWindow](windows[i])
      if window.isNil:
        removeOwnedIdAt(windows, i)
        continue

      if window.windowClosed():
        removeOwnedIdAt(windows, i)
        continue

      try:
        ensureNativeWindow(window)
      except CatchableError:
        removeOwnedIdAt(windows, i)
        app.appWindows = windows
        raise

      if not window.windowVisibleRequested():
        inc i
        continue

      let nativeWindow = window.windowNativeWindow()
      if not nativeWindow.isNil and nativeWindow.opened():
        nativeWindow.redraw()
        nativeWindow.step()
      if (not nativeWindow.isNil) and nativeWindow.closed():
        window.windowClosed true
        removeOwnedIdAt(windows, i)
        continue

      inc activeWindows
      inc i

    app.appWindows = windows

    while true:
      let event = app.nextEventMatchingMask(
        NSAnyEventMask,
        referenceTimestampNow(),
        @ns"NSDefaultRunLoopMode",
        dequeue = true,
      )
      if event.isNil:
        break
      app.sendEvent(event)

    inc result
    if maxFrames >= 0 and result >= maxFrames:
      break
    if activeWindows == 0:
      break
    sleep(8)
    windows = app.appWindows()

  app.appRunning = false
  app.appWindows = windows

proc new*(t: typedesc[NSApplication]): NSApplication =
  var allocated = NSApplication.alloc()
  result = initOwned(move(allocated))

proc sharedApplication*(t: typedesc[NSApplication]): NSApplication =
  if sharedApplicationRef.isNil:
    sharedApplicationRef = NSApplication.new()
  sharedApplicationRef

proc NSApp*(): NSApplication =
  NSApplication.sharedApplication()

proc addWindow*(app: NSApplication, window: NSWindow) =
  var windows = app.appWindows()
  if window.value notin windows:
    windows.add(retainId(window.value))
    app.appWindows = windows
  window.setNextResponder(app as NSResponder)
  window.windowVisibleRequested true

proc windows*(app: NSApplication): seq[NSWindow] =
  let appWindows = app.appWindows()
  result = newSeq[NSWindow](appWindows.len)
  for i, id in appWindows:
    result[i] = ownFromId[NSWindow](id)

proc run*(app: NSApplication) =
  discard runApplicationFrames(app, -1)

proc stop*(app: NSApplication) =
  app.appRunning = false

proc isRunning*(app: NSApplication): bool =
  app.appRunning()

proc runForFrames*(app: NSApplication, maxFrames: int): int =
  runApplicationFrames(app, maxFrames)

proc newWindow*(
    x, y, width, height: float32, title: NSString = @ns"KNutella Window"
): NSWindow =
  var wAlloc = NSWindow.alloc()
  result =
    wAlloc.initWithContentRect(x.float32, y.float32, width.float32, height.float32)
  wAlloc.value = nil
  result.setTitle(title)

proc newWindow*(x, y, width, height: float32, title: string): NSWindow =
  newWindow(x, y, width, height, ns(title))

proc newView*(x, y, width, height: float32): NSView =
  var vAlloc = NSView.alloc()
  result =
    vAlloc.initWithFrame(nsRect(x.float32, y.float32, width.float32, height.float32))
  vAlloc.value = nil

proc newTextField*(x, y, width, height: float32, value: NSString = @ns""): NSTextField =
  result = NSTextField.new()
  result.setFrame(nsRect(x.float32, y.float32, width.float32, height.float32))
  result.setStringValue(value)

proc newTextField*(x, y, width, height: float32, value: string): NSTextField =
  newTextField(x, y, width, height, ns(value))

proc newButton*(x, y, width, height: float32, title: NSString = @ns"Button"): NSButton =
  result = NSButton.new()
  result.setFrame(nsRect(x.float32, y.float32, width.float32, height.float32))
  result.setTitle(title)

proc newButton*(x, y, width, height: float32, title: string): NSButton =
  newButton(x, y, width, height, ns(title))
