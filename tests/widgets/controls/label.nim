import std/[os, strutils]

import knutella/appkit
import knutella/objc

proc maxFramesFromEnv(defaultValue = -1): int =
  let raw = getEnv("KNUTELLA_EXAMPLE_FRAMES").strip()
  if raw.len == 0:
    return defaultValue
  try:
    parseInt(raw)
  except ValueError:
    defaultValue

proc debugRenderDumpEnabled(): bool =
  getEnv("KNUTELLA_APPKIT_DEBUG_RENDER").strip().toLowerAscii() in
    ["1", "true", "yes", "on"]

proc format1(value: float32): string =
  formatFloat(value.float, ffDecimal, 1)

proc formatRect(rect: NSRect): string =
  "(" & format1(rect.origin.x) & "," & format1(rect.origin.y) & " " &
    format1(rect.size.width) & "x" & format1(rect.size.height) & ")"

proc intBool(flag: bool): int =
  if flag: 1 else: 0

proc dumpViewLine(view: NSView, name: string) =
  if view.isNil:
    return
  echo "[",
    name,
    "] frame=",
    formatRect(view.frame()),
    " bounds=",
    formatRect(view.bounds()),
    " autoresizeMask=0x",
    toHex(view.autoresizingMask(), 2)

proc dumpLabelLayout(stage: string, window: NSWindow, label1: NSTextField) =
  if window.isNil:
    return
  let windowFrame = window.frame()
  let contentRect = window.contentRectForFrameRect(windowFrame)
  let contentView = window.contentView()
  echo "[Window ",
    stage, "] frame=", formatRect(windowFrame), " contentRect=", formatRect(contentRect)
  dumpViewLine(contentView, "contentView")
  dumpViewLine(label1), "label1" as NSView
  echo "[label1] string='",
    label1.stringValue(),
    "' bezeled=",
    intBool(label1.isBezeled()),
    " drawsBackground=",
    intBool(label1.drawsBackground()),
    " editable=",
    intBool(label1.isEditable()),
    " selectable=",
    intBool(label1.isSelectable()),
    " alignment=",
    label1.alignment()
  if debugRenderDumpEnabled():
    debugDumpWindowRenderTree(window)

objcImpl:
  type LabelWindow = object of NSWindow
    xLabel1: NSTextField

  method init*(self: var LabelWindow): LabelWindow =
    var base = self.initWithContentRect(
      100.0,
      100.0,
      300.0,
      328.0,
      NSTitledWindowMask or NSClosableWindowMask or NSMiniaturizableWindowMask or
        NSResizableWindowMask,
      NSBackingStoreBuffered,
      false,
    )
    result = asTypeRaw[LabelWindow](base.value)
    base.value = nil
    if result.isNil:
      return

    var contentAlloc = NSView.alloc()
    var contentView = contentAlloc.initWithFrame(0.0, 0.0, 300.0, 300.0)
    contentAlloc.value = nil
    result.setContentView(contentView)

    var label1Alloc = NSTextField.alloc()
    result.xLabel1 = label1Alloc.initWithFrame(10.0, 270.0, 100.0, 20.0)
    label1Alloc.value = nil
    result.xLabel1.setStringValue(@ns"label1")
    result.xLabel1.setBezeled(false)
    result.xLabel1.setDrawsBackground(false)
    result.xLabel1.setEditable(false)
    result.xLabel1.setSelectable(false)
    result.xLabel1.setAlignment(NSLeftTextAlignment)
    result.xLabel1.setTextColor(nsColor(0.0, 0.0, 0.0, 1.0))

    contentView.addSubview(result.xLabel1)
    result.setTitle(@ns"Label Example")
    result.setIsVisible(true)
    dumpLabelLayout("init", result), result.xLabel1 as NSWindow
    contentView.value = nil

  method windowShouldClose*(self: LabelWindow, sender: NSObject): bool =
    if sender.isNil:
      NSApp().stop()
      return true
    NSApp().stop()
    true

  method dealloc(self: LabelWindow) {.used.} =
    self.xLabel1 = NSTextField(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(LabelWindow, self, getSelector("dealloc"))

when isMainModule:
  var app = NSApp()
  var windowAlloc = LabelWindow.alloc()
  var window = initOwned(move(windowAlloc))

  app.addWindow(window) as NSWindow
  window.makeKeyAndOrderFront(app) as NSObject

  try:
    let maxFrames = maxFramesFromEnv()
    if maxFrames < 0:
      app.run()
    else:
      discard app.runForFrames(maxFrames)
  except CatchableError as exc:
    echo "Unable to run label example: ", exc.msg

  window.value = nil
  app.value = nil
