import std/[os, strutils]

import nutella/appkit

proc maxFramesFromEnv(defaultValue = -1): int =
  let raw = getEnv("NUTELLA_EXAMPLE_FRAMES").strip()
  if raw.len == 0:
    return defaultValue
  try:
    parseInt(raw)
  except ValueError:
    defaultValue

when isMainModule:
  var app = NSApp()
  var window = newWindow(120, 120, 720, 460, "Nutella AppKit Hello")
  var root = newView(0, 0, 720, 460)
  root.setBackgroundColor(0.95, 0.96, 0.98, 1.0)

  var title = newTextField(28, 28, 520, 48, "Hello from Nutella/AppKit")
  root.addSubview(title)

  var subtitle = newTextField(
    28, 86, 620, 36,
    "NSApplication + NSWindow + NSView + NSControl wired to siwin/figdraw",
  )
  subtitle.setBackgroundColor(0.98, 0.98, 0.99, 1.0)
  root.addSubview(subtitle)

  var button = newButton(28, 150, 200, 44, "Click Me")
  button.setOnClick(
    proc(sender: NSButton) {.gcsafe.} =
      discard sender
      echo "button clicked"
  )
  root.addSubview(button)

  window.setContentView(root)
  app.addWindow(window)
  window.makeKeyAndOrderFront(app)

  try:
    let maxFrames = maxFramesFromEnv()
    if maxFrames < 0:
      app.run()
    else:
      discard app.runForFrames(maxFrames)
  except Exception as exc:
    echo "Unable to run AppKit example: ", exc.msg
  finally:
    button.value = nil
    subtitle.value = nil
    title.value = nil
    root.value = nil
    window.value = nil
    app.value = nil
