var sharedApplicationRef {.threadvar.}: NSApplication

proc sharedApplication*(t: typedesc[NSApplication]): NSApplication =
  when false:
    discard t
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
  window.windowVisibleRequested = true

proc windows*(app: NSApplication): seq[NSWindow] =
  let appWindows = app.appWindows()
  result = newSeq[NSWindow](appWindows.len)
  for i, id in appWindows:
    result[i] = ownFromId[NSWindow](id)

proc setContentView*(window: NSWindow, view: NSView) =
  let currentContentView = window.windowContentView()
  if not currentContentView.isNil and currentContentView != view.value:
    if window.windowFirstResponder() == currentContentView or
        isViewDescendantOf(window.windowFirstResponder(), currentContentView):
      window.windowFirstResponder = replacedOwnedId(window.windowFirstResponder(), nil)
    clearSuperviewRef(currentContentView)
  if not view.isNil:
    let parentId = view.viewSuperview()
    if not parentId.isNil:
      view.removeFromSuperview()
    view.viewSuperview = nil
    view.setNextResponder(asType[NSResponder](window))
  window.windowContentView = replacedOwnedId(window.windowContentView(), view.value)

proc contentView*(window: NSWindow): NSView =
  let cv = window.windowContentView()
  if cv.isNil:
    return NSView(value: nil)
  ownFromId[NSView](cv)

proc makeKeyAndOrderFront*(window: NSWindow, sender: NSObject) =
  discard sender
  window.windowVisibleRequested = true

proc close*(window: NSWindow) =
  window.windowClosed = true
  if window.windowNativeReady() and not window.windowNativeWindow().isNil:
    siwinshim.close(window.windowNativeWindow())

proc run*(app: NSApplication) =
  discard runApplicationFrames(app, -1)

proc stop*(app: NSApplication) =
  app.appRunning = false

proc isRunning*(app: NSApplication): bool =
  app.appRunning()

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
      if not nativeWindow.isNil and nativeWindow.opened:
        nativeWindow.redraw()
        nativeWindow.step()
      if (not nativeWindow.isNil) and nativeWindow.closed:
        window.windowClosed = true
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
