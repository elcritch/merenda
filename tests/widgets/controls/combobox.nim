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

proc dumpComboBoxLine(comboBox: NSComboBox, name: string) =
  if comboBox.isNil:
    return
  dumpViewLine(comboBox.NSView, name)
  echo "[",
    name,
    "] editable=",
    intBool(comboBox.isEditable()),
    " selected=",
    comboBox.indexOfSelectedItem(),
    " numberOfItems=",
    comboBox.numberOfItems(),
    " string='",
    comboBox.stringValue(),
    "'"

proc dumpComboBoxLayout(
    stage: string, window: NSWindow, comboBox1: NSComboBox, comboBox2: NSComboBox
) =
  if window.isNil:
    return
  let windowFrame = window.frame()
  let contentRect = window.contentRectForFrameRect(windowFrame)
  let contentView = window.contentView()
  echo "[Window ",
    stage, "] frame=", formatRect(windowFrame), " contentRect=", formatRect(contentRect)
  dumpViewLine(contentView, "contentView")
  dumpComboBoxLine(comboBox1, "comboBox1")
  dumpComboBoxLine(comboBox2, "comboBox2")
  if debugRenderDumpEnabled():
    debugDumpWindowRenderTree(window)

objcImpl:
  type ComboBoxWindow = object of NSWindow
    xComboBox1: NSComboBox
    xComboBox2: NSComboBox

  method init*(self: var ComboBoxWindow): ComboBoxWindow =
    var base = self.initWithContentRect(
      100.0,
      100.0,
      300.0,
      328.0,
      {NSTitledWindow, NSClosableWindow, NSMiniaturizableWindow, NSResizableWindow},
      NSBackingStoreBuffered,
      false,
    )
    result = asTypeRaw[ComboBoxWindow](base.value)
    base.value = nil
    if result.isNil:
      return

    var contentAlloc = NSView.alloc()
    var contentView = contentAlloc.initWithFrame(nsRect(0.0, 0.0, 300.0, 300.0))
    contentAlloc.value = nil
    result.setContentView(contentView)

    var comboBox1Alloc = NSComboBox.alloc()
    result.xComboBox1 = comboBox1Alloc.init()
    comboBox1Alloc.value = nil
    result.xComboBox1.setFrame(nsRect(10.0, 260.0, 121.0, 26.0))
    result.xComboBox1.addItemWithObjectValue(@ns"item1")
    result.xComboBox1.addItemWithObjectValue(@ns"item2")
    result.xComboBox1.addItemWithObjectValue(@ns"item3")
    result.xComboBox1.setTarget(ID(value: result.value))
    result.xComboBox1.setAction(getSelector("OnComboBox1SelectedItemChange:"))
    result.xComboBox1.selectItemAtIndex(1)

    var comboBox2Alloc = NSComboBox.alloc()
    result.xComboBox2 = comboBox2Alloc.init()
    comboBox2Alloc.value = nil
    result.xComboBox2.setFrame(nsRect(10.0, 220.0, 121.0, 26.0))
    result.xComboBox2.setEditable(false)
    result.xComboBox2.addItemWithObjectValue(@ns"item1")
    result.xComboBox2.addItemWithObjectValue(@ns"item2")
    result.xComboBox2.addItemWithObjectValue(@ns"item3")
    result.xComboBox2.setTarget(ID(value: result.value))
    result.xComboBox2.selectItemAtIndex(1)

    contentView.addSubview(result.xComboBox1)
    contentView.addSubview(result.xComboBox2)
    result.setTitle(@ns"ComboBox Example")
    result.setIsVisible(true)
    dumpComboBoxLayout("init", result as NSWindow, result.xComboBox1, result.xComboBox2)
    contentView.value = nil

  method windowShouldClose*(self: ComboBoxWindow, sender: NSObject): bool =
    if sender.isNil:
      NSApp().stop()
      return true
    NSApp().stop()
    true

  method OnComboBox1SelectedItemChange*(self: ComboBoxWindow, sender: NSObject) =
    if sender.isNil:
      return
    self.xComboBox2.selectItemAtIndex(self.xComboBox1.indexOfSelectedItem())
    dumpComboBoxLayout(
      "comboBox1-change", self as NSWindow, self.xComboBox1, self.xComboBox2
    )

  method OnComboBox2SelectedItemChange*(self: ComboBoxWindow, sender: NSObject) =
    if sender.isNil:
      return
    self.xComboBox1.selectItemAtIndex(self.xComboBox2.indexOfSelectedItem())
    dumpComboBoxLayout(
      "comboBox2-change", self as NSWindow, self.xComboBox1, self.xComboBox2
    )

  method dealloc(self: ComboBoxWindow) {.used.} =
    self.xComboBox1 = NSComboBox(value: nil)
    self.xComboBox2 = NSComboBox(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(ComboBoxWindow, self, getSelector("dealloc"))

when isMainModule:
  var app = NSApp()
  var windowAlloc = ComboBoxWindow.alloc()
  var window = initOwned(move(windowAlloc))

  app.addWindow(window.NSWindow)
  window.makeKeyAndOrderFront(app.NSObject)

  if getEnv("KNUTELLA_COMBOBOX_OPEN_POPUP").strip().len > 0:
    window.xComboBox1.openPopup()
    dumpComboBoxLayout(
      "popup-open", window.NSWindow, window.xComboBox1, window.xComboBox2
    )

  if getEnv("KNUTELLA_COMBOBOX_TRIGGER_CALLBACK").strip().len > 0:
    dumpComboBoxLayout(
      "post-front", window.NSWindow, window.xComboBox1, window.xComboBox2
    )
    window.OnComboBox1SelectedItemChange(window.NSObject)

  try:
    let maxFrames = maxFramesFromEnv()
    if maxFrames < 0:
      app.run()
    else:
      discard app.runForFrames(maxFrames)
  except CatchableError as exc:
    echo "Unable to run combobox example: ", exc.msg

  window.value = nil
  app.value = nil
