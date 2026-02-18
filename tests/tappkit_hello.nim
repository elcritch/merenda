import std/unittest

import nutella/appkit

suite "nutella appkit hello world":
  test "basic appkit api compiles":
    check compiles(
      block:
        let app = NSApp()
        let window = newWindow(100, 120, 640, 420, "Nutella Hello World")
        let root = newView(0, 0, 640, 420)
        root.setBackgroundColor(0.96, 0.96, 0.98, 1.0)

        let field = newTextField(32, 32, 360, 44, "Hello world from Nutella")
        root.addSubview(field)

        let button = newButton(32, 96, 180, 44, "Click me")
        button.setOnClick(
          proc(sender: NSButton) {.gcsafe.} =
            discard sender
        )
        button.click()
        root.addSubview(button)

        window.setContentView(root)
        app.addWindow(window)
        window.makeKeyAndOrderFront(app)
        discard app.runForFrames(1)
        window.close()
        app.stop()
    )

  test "application keeps added window alive across frame loop":
    var app = NSApp()

    block:
      var window = newWindow(100, 120, 320, 240, "Owned Window")
      app.addWindow(window)
      # Mark closed to avoid backend setup; run loop should still traverse safely.
      window.close()
      # Drop the local owner; app should still own the window entry safely.
      window.value = nil

    discard app.runForFrames(1)
    app.value = nil
