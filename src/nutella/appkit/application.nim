import std/os

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

objcImpl:
  type NSApplication* = object of NSResponder
    appWindows: seq[ID]
    appRunning: bool

  method init*(self: var NSApplication): NSApplication =
    result =
      asType[NSApplication](callSuperIdFrom(NSApplication, self, getSelector("init")))
    if result.isNil:
      return
    result.appWindows = @[]
    result.appRunning = false

  method addWindow(self: NSApplication, window: NSWindow) =
    if self.isNil or window.isNil:
      return
    var windows = self.appWindows()
    if window.value notin windows:
      windows.add(retainId(window.value))
      self.appWindows = windows
    window.setNextResponder(asType[NSResponder](self))
    window.windowVisibleRequested true

  method run(self: NSApplication) =
    discard runApplicationFrames(self, -1)

  method sendEvent*(self: NSApplication, event: NSEvent) =
    if self.isNil or event.isNil:
      return
    let windows = self.appWindows()
    var i = windows.len - 1
    while i >= 0:
      let window = ownFromId[NSWindow](windows[i])
      if (not window.isNil) and (not window.windowClosed()) and
          window.windowVisibleRequested():
        window.sendEvent(event)
        return
      dec i

  method stop(self: NSApplication) =
    self.appRunning = false

  method dealloc(self: NSApplication) {.used.} =
    var windows = self.appWindows()
    clearOwnedIds(windows)
    self.appWindows = windows
    clearIvarRefs(self)
    discard callSuperIdFrom(NSApplication, self, getSelector("dealloc"))

var sharedApplicationRef {.threadvar.}: NSApplication

proc runApplicationFrames(app: NSObject, maxFrames: int): int =
  let app = ownFromId[NSApplication](app.value)
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
  result = allocated.init()
  allocated.value = nil

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
  window.setNextResponder(asType[NSResponder](app))
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

proc sendEvent*(app: NSApplication, event: NSEvent) =
  if app.isNil or event.isNil:
    return
  let windows = app.appWindows()
  var i = windows.len - 1
  while i >= 0:
    let window = ownFromId[NSWindow](windows[i])
    if (not window.isNil) and (not window.windowClosed()) and
        window.windowVisibleRequested():
      window.sendEvent(event)
      return
    dec i

proc isRunning*(app: NSApplication): bool =
  app.appRunning()

proc runForFrames*(app: NSApplication, maxFrames: int): int =
  runApplicationFrames(app, maxFrames)

proc newWindow*(
    x, y, width, height: float32, title: NSString = @ns"Nutella Window"
): NSWindow =
  var wAlloc = NSWindow.alloc()
  result = wAlloc.initWithContentRect(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  wAlloc.value = nil
  result.setTitle(title)

proc newWindow*(x, y, width, height: float32, title: string): NSWindow =
  newWindow(x, y, width, height, ns(title))

proc newView*(x, y, width, height: float32): NSView =
  var vAlloc = NSView.alloc()
  result = vAlloc.initWithFrame(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  vAlloc.value = nil

proc newTextField*(x, y, width, height: float32, value: NSString = @ns""): NSTextField =
  result = NSTextField.new()
  result.setFrame(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  result.setStringValue(value)

proc newTextField*(x, y, width, height: float32, value: string): NSTextField =
  newTextField(x, y, width, height, ns(value))

proc newButton*(x, y, width, height: float32, title: NSString = @ns"Button"): NSButton =
  result = NSButton.new()
  result.setFrame(x.cfloat, y.cfloat, width.cfloat, height.cfloat)
  result.setTitle(title)

proc newButton*(x, y, width, height: float32, title: string): NSButton =
  newButton(x, y, width, height, ns(title))
