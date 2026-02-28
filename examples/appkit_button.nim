import std/[os, strutils]

import nutella/appkit/[application, buttons, textfields, types, views, windows]
import nutella/objc

proc maxFramesFromEnv(defaultValue = -1): int =
  let raw = getEnv("NUTELLA_EXAMPLE_FRAMES").strip()
  if raw.len == 0:
    return defaultValue
  try:
    parseInt(raw)
  except ValueError:
    defaultValue

when isMainModule:
  var button1Clicked = 0
  var button2Clicked = 0

  var app = NSApp()
  var window = newWindow(100, 100, 300, 300, "Button example")
  var root = newView(0, 0, 300, 300)

  var button1 = newButton(50, 225, 90, 25, @ns"button1")
  button1.setBezelStyle(NSRoundedBezelStyle)
  button1.setAutoresizingMask(NSViewMaxXMargin or NSViewMinYMargin)

  var button2 = newButton(50, 125, 200, 75, @ns"button2")
  button2.setBezelStyle(NSRegularSquareBezelStyle)
  button2.setAutoresizingMask(NSViewMaxXMargin or NSViewMinYMargin)

  var label1 = newTextField(50, 80, 200, 20, @ns"button1 clicked 0 times")
  label1.setBezeled(false)
  label1.setDrawsBackground(false)
  label1.setEditable(false)

  var label2 = newTextField(50, 50, 200, 20, @ns"button2 clicked 0 times")
  label2.setBezeled(false)
  label2.setDrawsBackground(false)
  label2.setEditable(false)

  button1.setOnClick(
    proc(sender: NSButton) =
      inc button1Clicked
      label1.setStringValue(
        @ns($sender.title() & " clicked " & $button1Clicked & " times")
      )
  )

  button2.setOnClick(
    proc(sender: NSButton) =
      inc button2Clicked
      label2.setStringValue(
        @ns($sender.title() & " clicked " & $button2Clicked & " times")
      )
  )

  root.addSubview(button1)
  root.addSubview(button2)
  root.addSubview(label1)
  root.addSubview(label2)

  window.setContentView(root)
  app.addWindow(window)
  window.makeKeyAndOrderFront(app)

  try:
    let maxFrames = maxFramesFromEnv()
    if maxFrames < 0:
      app.run()
    else:
      discard app.runForFrames(maxFrames)
  except CatchableError as exc:
    echo "Unable to run button example: ", exc.msg

  label2.value = nil
  label1.value = nil
  button2.value = nil
  button1.value = nil
  root.value = nil
  window.value = nil
  app.value = nil
