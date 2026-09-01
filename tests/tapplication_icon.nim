import std/[base64, unittest]

import merenda/nimkit

const TinyPng =
  "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAaElEQVR42mNgGGjA" &
  "CGOIyGn8vxRFvEapjhuMDAwMDEwwgUtRDAx6y0h3ARMyhxxDmNAFSDWECZsgKYYw" &
  "4ZIg1hAmfJLEGMJEyAZChjAR4098hjARG9q4DGEiJc6xGcJEasojN8XSDgAA/Fca" &
  "GFwb71YAAAAASUVORK5CYII="

proc testIcon(): ImageResource =
  newImageResourceFromData(decode(TinyPng), name = "application-icon-test")

suite "NimKit application icon":
  test "application icon propagates to existing and future windows":
    let
      app = newApplication("Icon Test")
      existingWindow = newWindow("Existing")
      futureWindow = newWindow("Future")
      icon = testIcon()

    app.addWindow(existingWindow)
    app.icon = icon
    app.addWindow(futureWindow)

    check app.icon == icon
    check existingWindow.icon == icon
    check futureWindow.icon == icon

  test "clearing the application icon clears registered windows":
    let
      app = newApplication("Icon Clear Test")
      window = newWindow("Window")

    app.icon = testIcon()
    app.addWindow(window)
    app.icon = nil

    check app.icon.isNil
    check window.icon.isNil
