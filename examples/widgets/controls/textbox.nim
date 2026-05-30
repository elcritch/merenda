import std/[os, strutils]

import merenda/appkit
import merenda/objc

proc maxFramesFromEnv(defaultValue = -1): int =
  let raw = getEnv("MERENDA_EXAMPLE_FRAMES").strip()
  if raw.len == 0:
    return defaultValue
  try:
    parseInt(raw)
  except ValueError:
    defaultValue

proc debugRenderDumpEnabled(): bool =
  getEnv("MERENDA_APPKIT_DEBUG_RENDER").strip().toLowerAscii() in
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

proc dumpTextBoxLayout(
    stage: string, window: NSWindow, textBox1: NSTextField, textBox2: NSTextField
) =
  if window.isNil:
    return
  let windowFrame = window.frame()
  let contentRect = window.contentRectForFrameRect(windowFrame)
  let contentView = window.contentView()
  let firstResponder = window.firstResponder()
  echo "[Window ",
    stage, "] frame=", formatRect(windowFrame), " contentRect=", formatRect(contentRect)
  dumpViewLine(contentView, "contentView")
  dumpViewLine(textBox1.NSView, "textBox1")
  dumpViewLine(textBox2.NSView, "textBox2")
  echo "[textBox1] string='",
    textBox1.stringValue(),
    "' editable=",
    intBool(textBox1.isEditable()),
    " selectable=",
    intBool(textBox1.isSelectable()),
    " bezeled=",
    intBool(textBox1.isBezeled()),
    " drawsBackground=",
    intBool(textBox1.drawsBackground())
  echo "[textBox2] string='",
    textBox2.stringValue(),
    "' editable=",
    intBool(textBox2.isEditable()),
    " selectable=",
    intBool(textBox2.isSelectable()),
    " bezeled=",
    intBool(textBox2.isBezeled()),
    " drawsBackground=",
    intBool(textBox2.drawsBackground()),
    " firstResponder=",
    intBool((not firstResponder.isNil) and firstResponder.value == textBox2.value)
  if debugRenderDumpEnabled():
    debugDumpWindowRenderTree(window)

objcImpl:
  type TextBoxWindow = object of NSWindow
    xTextBox1: NSTextField
    xTextBox2: NSTextField

  method init*(self: var TextBoxWindow): TextBoxWindow =
    var base = self.initWithContentRect(
      100.0,
      100.0,
      300.0,
      328.0,
      {NSTitledWindow, NSClosableWindow, NSMiniaturizableWindow, NSResizableWindow},
      NSBackingStoreBuffered,
      false,
    )
    result = asTypeRaw[TextBoxWindow](base.value)
    base.value = nil
    if result.isNil:
      return

    var contentAlloc = NSView.alloc()
    var contentView = contentAlloc.initWithFrame(nsRect(0.0, 0.0, 300.0, 300.0))
    contentAlloc.value = nil
    result.setContentView(contentView)

    var textBox1Alloc = NSTextField.alloc()
    result.xTextBox1 = textBox1Alloc.init()
    result.xTextBox1.setFrame(nsRect(10.0, 270.0, 100.0, 20.0))
    result.xTextBox1.setStringValue(@ns"textBox1")
    result.xTextBox1.setAlignment(NSLeftTextAlignment)

    var textBox2Alloc = NSTextField.alloc()
    result.xTextBox2 = textBox2Alloc.init()
    result.xTextBox2.setFrame(nsRect(10.0, 230.0, 100.0, 20.0))
    result.xTextBox2.setStringValue(@ns"textBox2")
    result.xTextBox2.setAlignment(NSLeftTextAlignment)

    contentView.addSubview(result.xTextBox1)
    contentView.addSubview(result.xTextBox2)
    discard result.makeFirstResponder(result.xTextBox2.NSResponder)
    result.setTitle(@ns"TextBox Example")
    result.setIsVisible(true)
    dumpTextBoxLayout("init", result as NSWindow, result.xTextBox1, result.xTextBox2)
    contentView.value = nil

  method windowShouldClose*(self: TextBoxWindow, sender: NSObject): bool =
    if sender.isNil:
      NSApp().stop()
      return true
    NSApp().stop()
    true

  method dealloc(self: TextBoxWindow) {.used.} =
    self.xTextBox1 = NSTextField(value: nil)
    self.xTextBox2 = NSTextField(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(TextBoxWindow, self, getSelector("dealloc"))

when isMainModule:
  var app = NSApp()
  var windowAlloc = TextBoxWindow.alloc()
  var window = initOwned(move(windowAlloc))

  app.addWindow(window.NSWindow)
  window.makeKeyAndOrderFront(app.NSObject)

  try:
    let maxFrames = maxFramesFromEnv()
    if maxFrames < 0:
      app.run()
    else:
      discard app.runForFrames(maxFrames)
  except CatchableError as exc:
    echo "Unable to run textbox example: ", exc.msg

  window.value = nil
  app.value = nil
