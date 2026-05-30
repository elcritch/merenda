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

proc dumpCheckBoxLayout(
    stage: string,
    window: NSWindow,
    checkBox1: NSButton,
    checkBox2: NSButton,
    checkBox3: NSButton,
    checkBox4: NSButton,
    checkBox5: NSButton,
) =
  if window.isNil:
    return
  let windowFrame = window.frame()
  let contentRect = window.contentRectForFrameRect(windowFrame)
  let contentView = window.contentView()
  echo "[Window ",
    stage, "] frame=", formatRect(windowFrame), " contentRect=", formatRect(contentRect)
  dumpViewLine(contentView, "contentView")
  dumpViewLine(checkBox1.NSView, "checkBox1")
  dumpViewLine(checkBox2.NSView, "checkBox2")
  dumpViewLine(checkBox3.NSView, "checkBox3")
  dumpViewLine(checkBox4.NSView, "checkBox4")
  dumpViewLine(checkBox5.NSView, "checkBox5")
  echo "[checkBox1] state=",
    checkBox1.state(),
    " mixed=",
    intBool(checkBox1.allowsMixedState()),
    " alignment=",
    checkBox1.alignment(),
    " title='",
    checkBox1.title(),
    "'"
  echo "[checkBox2] state=",
    checkBox2.state(),
    " mixed=",
    intBool(checkBox2.allowsMixedState()),
    " alignment=",
    checkBox2.alignment(),
    " title='",
    checkBox2.title(),
    "'"
  echo "[checkBox3] state=",
    checkBox3.state(),
    " mixed=",
    intBool(checkBox3.allowsMixedState()),
    " alignment=",
    checkBox3.alignment(),
    " title='",
    checkBox3.title(),
    "'"
  echo "[checkBox4] state=",
    checkBox4.state(),
    " mixed=",
    intBool(checkBox4.allowsMixedState()),
    " alignment=",
    checkBox4.alignment(),
    " title='",
    checkBox4.title(),
    "'"
  echo "[checkBox5] state=",
    checkBox5.state(),
    " mixed=",
    intBool(checkBox5.allowsMixedState()),
    " alignment=",
    checkBox5.alignment(),
    " title='",
    checkBox5.title(),
    "'"
  if debugRenderDumpEnabled():
    debugDumpWindowRenderTree(window)

objcImpl:
  type CheckBoxWindow = object of NSWindow
    xCheckBox1: NSButton
    xCheckBox2: NSButton
    xCheckBox3: NSButton
    xCheckBox4: NSButton
    xCheckBox5: NSButton

  method init*(self: var CheckBoxWindow): CheckBoxWindow =
    var base = self.initWithContentRect(
      100.0,
      100.0,
      300.0,
      328.0,
      {NSTitledWindow, NSClosableWindow, NSMiniaturizableWindow, NSResizableWindow},
      NSBackingStoreBuffered,
      false,
    )
    result = asTypeRaw[CheckBoxWindow](base.value)
    base.value = nil
    if result.isNil:
      return

    var contentAlloc = NSView.alloc()
    var contentView = contentAlloc.initWithFrame(nsRect(0.0, 0.0, 300.0, 300.0))
    contentAlloc.value = nil
    result.setContentView(contentView)

    var checkBox1Alloc = NSButton.alloc()
    result.xCheckBox1 = checkBox1Alloc.init()
    checkBox1Alloc.value = nil
    result.xCheckBox1.setFrame(nsRect(30.0, 250.0, 105.0, 20.0))
    result.xCheckBox1.setTitle(@ns"Unchecked")
    result.xCheckBox1.setButtonType(NSSwitchButton)
    result.xCheckBox1.setTarget(ID(value: result.value))
    result.xCheckBox1.setAction(getSelector("OnCheckBox1Click:"))
    result.xCheckBox1.setAlignment(NSNaturalTextAlignment)
    result.xCheckBox1.setAutoresizingMask(NSViewMaxXMargin.int or NSViewMinYMargin.int)
    result.xCheckBox1.setState(NSOffState.cint)

    var checkBox2Alloc = NSButton.alloc()
    result.xCheckBox2 = checkBox2Alloc.init()
    checkBox2Alloc.value = nil
    result.xCheckBox2.setFrame(nsRect(30.0, 220.0, 105.0, 20.0))
    result.xCheckBox2.setTitle(@ns"Checked")
    result.xCheckBox2.setButtonType(NSSwitchButton)
    result.xCheckBox2.setTarget(ID(value: result.value))
    result.xCheckBox2.setAction(getSelector("OnCheckBox2Click:"))
    result.xCheckBox2.setAlignment(NSNaturalTextAlignment)
    result.xCheckBox2.setAutoresizingMask(NSViewMaxXMargin.int or NSViewMinYMargin.int)
    result.xCheckBox2.setState(NSOnState.cint)

    var checkBox3Alloc = NSButton.alloc()
    result.xCheckBox3 = checkBox3Alloc.init()
    checkBox3Alloc.value = nil
    result.xCheckBox3.setFrame(nsRect(30.0, 190.0, 105.0, 20.0))
    result.xCheckBox3.setTitle(@ns"Mixed")
    result.xCheckBox3.setAllowsMixedState(true)
    result.xCheckBox3.setButtonType(NSSwitchButton)
    result.xCheckBox3.setTarget(ID(value: result.value))
    result.xCheckBox3.setAction(getSelector("OnCheckBox3Click:"))
    result.xCheckBox3.setAlignment(NSNaturalTextAlignment)
    result.xCheckBox3.setAutoresizingMask(NSViewMaxXMargin.int or NSViewMinYMargin.int)
    result.xCheckBox3.setState(NSMixedState.cint)

    var checkBox4Alloc = NSButton.alloc()
    result.xCheckBox4 = checkBox4Alloc.init()
    checkBox4Alloc.value = nil
    result.xCheckBox4.setFrame(nsRect(30.0, 160.0, 105.0, 25.0))
    result.xCheckBox4.setTitle(@ns"Checked")
    result.xCheckBox4.setButtonType(NSOnOffButton)
    result.xCheckBox4.setBezelStyle(NSRoundedBezelStyle)
    result.xCheckBox4.setTarget(ID(value: result.value))
    result.xCheckBox4.setAction(getSelector("OnCheckBox4Click:"))
    result.xCheckBox4.setAlignment(NSCenterTextAlignment)
    result.xCheckBox4.setAutoresizingMask(NSViewMaxXMargin.int or NSViewMinYMargin.int)
    result.xCheckBox4.setState(NSOnState.cint)

    var checkBox5Alloc = NSButton.alloc()
    result.xCheckBox5 = checkBox5Alloc.init()
    checkBox5Alloc.value = nil
    result.xCheckBox5.setFrame(nsRect(30.0, 130.0, 105.0, 25.0))
    result.xCheckBox5.setTitle(@ns"Unchecked")
    result.xCheckBox5.setButtonType(NSOnOffButton)
    result.xCheckBox5.setBezelStyle(NSRoundedBezelStyle)
    result.xCheckBox5.setTarget(ID(value: result.value))
    result.xCheckBox5.setAction(getSelector("OnCheckBox5Click:"))
    result.xCheckBox5.setAlignment(NSCenterTextAlignment)
    result.xCheckBox5.setAutoresizingMask(NSViewMaxXMargin.int or NSViewMinYMargin.int)
    result.xCheckBox5.setState(NSOffState.cint)

    contentView.addSubview(result.xCheckBox1)
    contentView.addSubview(result.xCheckBox2)
    contentView.addSubview(result.xCheckBox3)
    contentView.addSubview(result.xCheckBox4)
    contentView.addSubview(result.xCheckBox5)

    result.setTitle(@ns"CheckBox example")
    result.setIsVisible(true)
    dumpCheckBoxLayout(
      "init",
      result as NSWindow,
      result.xCheckBox1,
      result.xCheckBox2,
      result.xCheckBox3,
      result.xCheckBox4,
      result.xCheckBox5,
    )
    contentView.value = nil

  method windowShouldClose*(self: CheckBoxWindow, sender: NSObject): bool =
    if sender.isNil:
      NSApp().stop()
      return true
    NSApp().stop()
    true

  method stateToString*(self: CheckBoxWindow, state: NSCellState): NSString =
    if self.isNil:
      return @ns"Unchecked"
    case state
    of NSOffState:
      @ns"Unchecked"
    of NSOnState:
      @ns"Checked"
    else:
      @ns"Mixed"

  method OnCheckBox1Click*(self: CheckBoxWindow, sender: NSObject) =
    if sender.isNil:
      return
    self.xCheckBox1.setState(NSOffState.cint)
    self.xCheckBox1.setTitle(self.stateToString(self.xCheckBox1.state()))
    dumpCheckBoxLayout(
      "checkBox1-click",
      self as NSWindow,
      self.xCheckBox1,
      self.xCheckBox2,
      self.xCheckBox3,
      self.xCheckBox4,
      self.xCheckBox5,
    )

  method OnCheckBox2Click*(self: CheckBoxWindow, sender: NSObject) =
    if sender.isNil:
      return
    self.xCheckBox2.setTitle(self.stateToString(self.xCheckBox2.state()))
    dumpCheckBoxLayout(
      "checkBox2-click",
      self as NSWindow,
      self.xCheckBox1,
      self.xCheckBox2,
      self.xCheckBox3,
      self.xCheckBox4,
      self.xCheckBox5,
    )

  method OnCheckBox3Click*(self: CheckBoxWindow, sender: NSObject) =
    if sender.isNil:
      return
    self.xCheckBox3.setTitle(self.stateToString(self.xCheckBox3.state()))
    dumpCheckBoxLayout(
      "checkBox3-click",
      self as NSWindow,
      self.xCheckBox1,
      self.xCheckBox2,
      self.xCheckBox3,
      self.xCheckBox4,
      self.xCheckBox5,
    )

  method OnCheckBox4Click*(self: CheckBoxWindow, sender: NSObject) =
    if sender.isNil:
      return
    self.xCheckBox4.setTitle(self.stateToString(self.xCheckBox4.state()))
    dumpCheckBoxLayout(
      "checkBox4-click",
      self as NSWindow,
      self.xCheckBox1,
      self.xCheckBox2,
      self.xCheckBox3,
      self.xCheckBox4,
      self.xCheckBox5,
    )

  method OnCheckBox5Click*(self: CheckBoxWindow, sender: NSObject) =
    if sender.isNil:
      return
    self.xCheckBox5.setState(NSOffState.cint)
    self.xCheckBox5.setTitle(self.stateToString(self.xCheckBox5.state()))
    dumpCheckBoxLayout(
      "checkBox5-click",
      self as NSWindow,
      self.xCheckBox1,
      self.xCheckBox2,
      self.xCheckBox3,
      self.xCheckBox4,
      self.xCheckBox5,
    )

  method dealloc(self: CheckBoxWindow) {.used.} =
    self.xCheckBox1 = NSButton(value: nil)
    self.xCheckBox2 = NSButton(value: nil)
    self.xCheckBox3 = NSButton(value: nil)
    self.xCheckBox4 = NSButton(value: nil)
    self.xCheckBox5 = NSButton(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(CheckBoxWindow, self, getSelector("dealloc"))

when isMainModule:
  var app = NSApp()
  var windowAlloc = CheckBoxWindow.alloc()
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
    echo "Unable to run checkbox example: ", exc.msg

  window.value = nil
  app.value = nil
