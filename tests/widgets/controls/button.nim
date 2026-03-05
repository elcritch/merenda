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

objcImpl:
  type ButtonWindow = object of NSWindow
    xButton1: NSButton
    xButton2: NSButton
    xLabel1: NSTextField
    xLabel2: NSTextField
    xButton1Clicked: int
    xButton2Clicked: int

  method init*(self: var ButtonWindow): ButtonWindow =
    var base = self.initWithContentRect(
      100.0,
      100.0,
      300.0,
      300.0,
      {NSTitledWindow, NSClosableWindow, NSResizableWindow},
      NSBackingStoreBuffered,
      false,
    )
    result = asTypeRaw[ButtonWindow](base.value)
    base.value = nil
    if result.isNil:
      return

    result.xButton1Clicked = 0
    result.xButton2Clicked = 0

    var contentAlloc = NSView.alloc()
    var contentView = contentAlloc.initWithFrame(nsRect(0.0, 0.0, 300.0, 300.0))
    contentAlloc.value = nil
    result.setContentView(contentView)

    var button1Alloc = NSButton.alloc()
    result.xButton1 = button1Alloc.init()
    button1Alloc.value = nil
    result.xButton1.setFrame(nsRect(50.0, 225.0, 90.0, 25.0))
    result.xButton1.setTitle(@ns"button1")
    result.xButton1.setBezelStyle(NSRoundedBezelStyle)
    result.xButton1.setTarget(ID(value: result.value))
    result.xButton1.setAction(getSelector("OnButton1Click:"))
    result.xButton1.setAutoresizingMask(NSViewMaxXMargin.int or NSViewMinYMargin.int)

    var button2Alloc = NSButton.alloc()
    result.xButton2 = button2Alloc.init()
    button2Alloc.value = nil
    result.xButton2.setFrame(nsRect(50.0, 125.0, 200.0, 75.0))
    result.xButton2.setTitle(@ns"button2")
    result.xButton2.setBezelStyle(NSRegularSquareBezelStyle)
    result.xButton2.setTarget(ID(value: result.value))
    result.xButton2.setAction(getSelector("OnButton2Click:"))
    result.xButton2.setAutoresizingMask(NSViewMaxXMargin.int or NSViewMinYMargin.int)

    var label1Alloc = NSTextField.alloc()
    result.xLabel1 = label1Alloc.init()
    label1Alloc.value = nil
    result.xLabel1.setFrame(nsRect(50.0, 80.0, 200.0, 20.0))
    result.xLabel1.setStringValue(@ns"button1 clicked 0 times")
    result.xLabel1.setBezeled(false)
    result.xLabel1.setDrawsBackground(false)
    result.xLabel1.setEditable(false)

    var label2Alloc = NSTextField.alloc()
    result.xLabel2 = label2Alloc.init()
    label2Alloc.value = nil
    result.xLabel2.setFrame(nsRect(50.0, 50.0, 200.0, 20.0))
    result.xLabel2.setStringValue(@ns"button2 clicked 0 times")
    result.xLabel2.setBezeled(false)
    result.xLabel2.setDrawsBackground(false)
    result.xLabel2.setEditable(false)

    contentView.addSubview(result.xButton1)
    contentView.addSubview(result.xButton2)
    contentView.addSubview(result.xLabel1)
    contentView.addSubview(result.xLabel2)
    result.setTitle(@ns"Button example")
    result.setIsVisible(true)
    contentView.value = nil

  method windowShouldClose*(self: ButtonWindow, sender: NSObject): bool =
    if sender.isNil:
      NSApp().stop()
      return true
    NSApp().stop()
    true

  method OnButton1Click*(self: ButtonWindow, sender: NSObject) =
    if sender.isNil:
      return
    inc self.xButton1Clicked
    self.xLabel1.setStringValue(
      @ns("button1 clicked " & $self.xButton1Clicked & " times")
    )

  method OnButton2Click*(self: ButtonWindow, sender: NSObject) =
    if sender.isNil:
      return
    inc self.xButton2Clicked
    self.xLabel2.setStringValue(
      @ns("button2 clicked " & $self.xButton2Clicked & " times")
    )

  method dealloc(self: ButtonWindow) {.used.} =
    self.xButton1 = NSButton(value: nil)
    self.xButton2 = NSButton(value: nil)
    self.xLabel1 = NSTextField(value: nil)
    self.xLabel2 = NSTextField(value: nil)
    destroyIvarFields(self)
    discard callSuperIdFrom(ButtonWindow, self, getSelector("dealloc"))

when isMainModule:
  var app = NSApp()
  var windowAlloc = ButtonWindow.alloc()
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
    echo "Unable to run button example: ", exc.msg

  window.value = nil
  app.value = nil
