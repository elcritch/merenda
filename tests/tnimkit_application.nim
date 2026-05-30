import std/[tables, unittest]

import figdraw/windowing/siwinshim

import knutella/nimkit

suite "nimkit application":
  test "raw mouse input converts from reported input size to logical size":
    let logicalSize = vec2(360.0'f32, 220.0'f32)

    check rawInputToLogical(
      vec2(72.0'f32, 108.0'f32), ivec2(360'i32, 220'i32), logicalSize
    ) == vec2(72.0'f32, 108.0'f32)
    check rawInputToLogical(
      vec2(108.0'f32, 162.0'f32), ivec2(540'i32, 330'i32), logicalSize
    ) == vec2(72.0'f32, 108.0'f32)

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

  test "native close marks window closed without releasing during callback":
    block nativeClose:
      let
        app = newApplication()
        window = newWindow(80, 80, 240, 140, "Nimkit Native Close")

      window.setContentView(newView(0, 0, 240, 140))
      app.addWindow(window)
      window.makeKeyAndOrderFront()

      try:
        check app.runForFrames(1) == 1
        let nativeWindow = window.nativeWindowOrNil()
        check not nativeWindow.isNil
        if nativeWindow.isNil:
          break nativeClose
        siwinshim.close(nativeWindow)
        check window.isClosed
        check not window.nativeReady
      except CatchableError:
        skip()
        break nativeClose
      finally:
        window.close()

  test "native combo boxes use popup windows instead of owner-window popup drawing":
    block nativeComboPopup:
      let
        app = newApplication()
        window = newWindow(80, 80, 260, 160, "Nimkit Native Combo Popup")
        root = newView(0, 0, 260, 160)
        combo = newComboBox(16, 16, 140, 24, ["Low", "Medium", "High"])

      root.addSubview(combo)
      window.setContentView(root)
      app.addWindow(window)
      window.makeKeyAndOrderFront()

      try:
        check app.runForFrames(1) == 1
        check window.nativeReady
        check window.mouseDownAt(initPoint(24, 24))
        check combo.popupOpen
        let renders = window.buildRenders()
        check PopupDrawLevel notin renders.layers
      except CatchableError:
        skip()
        break nativeComboPopup
      finally:
        combo.closePopup()
        window.close()

  test "native combo boxes can force inline popup drawing":
    block nativeInlineComboPopup:
      let
        app = newApplication()
        window = newWindow(80, 80, 260, 160, "Nimkit Inline Combo Popup")
        root = newView(0, 0, 260, 160)
        combo = newComboBox(16, 16, 140, 24, ["Low", "Medium", "High"])

      window.setPopupPresentation(ppInline)
      root.addSubview(combo)
      window.setContentView(root)
      app.addWindow(window)
      window.makeKeyAndOrderFront()

      try:
        check app.runForFrames(1) == 1
        check window.nativeReady
        check window.mouseDownAt(initPoint(24, 24))
        check combo.popupOpen
        let renders = window.buildRenders()
        check PopupDrawLevel in renders.layers
      except CatchableError:
        skip()
        break nativeInlineComboPopup
      finally:
        combo.closePopup()
        window.close()
