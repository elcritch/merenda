## ARC back-reference behavior shared by the NimKit test runner.
import std/unittest

import merenda/nimkit
import merenda/nimkit/responder/responders as nimkitResponders

static:
  doAssert compileOption("mm", "arc")

suite "NimKit ARC back references":
  test "view back links do not retain a destroyed superview":
    let child = newView(frame = rect(20, 30, 80, 40))

    block:
      let parent = newView(frame = rect(0, 0, 200, 160))
      parent.addSubview(child)

      check child.superview == parent
      check nimkitResponders.nextResponder(Responder(child)) == Responder(parent)

    check child.superview.isNil
    check nimkitResponders.nextResponder(Responder(child)).isNil

  test "view back links do not retain a destroyed window":
    let content = newView(frame = rect(0, 0, 240, 160))

    block:
      let window = newWindow("Back link", frame = rect(0, 0, 240, 160))
      window.setAutorecalculatesKeyViewLoop(false)
      window.setContentView(content)

      check content.window == Responder(window)
      check nimkitResponders.nextResponder(Responder(content)) == Responder(window)

    check content.window.isNil
    check nimkitResponders.nextResponder(Responder(content)).isNil
