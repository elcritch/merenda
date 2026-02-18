import std/unittest

import nutella/appkit
import nutella/objc

suite "nutella appkit hello world":
  test "appkit controls report runtime class hierarchy":
    var button = newButton(0, 0, 120, 32, "Press")
    check(button.isKindOfClass(NSButton))
    check(button.isKindOfClass(NSControl))
    check(button.isKindOfClass(NSView))
    check(button.isKindOfClass(NSResponder))
    check(button.isKindOfClass(NSObject))
    check(not button.isKindOfClass(NSTextField))

    var field = newTextField(0, 0, 200, 32, "Hello")
    check(field.isKindOfClass(NSTextField))
    check(field.isKindOfClass(NSControl))
    check(field.isKindOfClass(NSView))
    check(field.isKindOfClass(NSResponder))
    check(field.isKindOfClass(NSObject))
    check(not field.isKindOfClass(NSButton))

    button.value = nil
    field.value = nil

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
