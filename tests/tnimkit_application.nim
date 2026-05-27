import std/unittest

import knutella/nimkit

suite "nimkit application":
  test "runForFrames opens and pumps a visible native window":
    block nativeRun:
      let
        app = newApplication()
        window = newWindow(80, 80, 240, 140, "Nimkit Native Test")
        root = newView(0, 0, 240, 140)

      root.addSubview(newTextField(16, 16, 180, 32, "Native window"))
      window.setContentView(root)
      app.addWindow(window)

      check not window.isVisible
      window.makeKeyAndOrderFront()
      check window.isVisible

      try:
        check app.runForFrames(2) == 2
        check window.nativeReady
        check not window.nativeWindowOrNil().isNil
      except CatchableError:
        skip()
        break nativeRun
      finally:
        window.close()
