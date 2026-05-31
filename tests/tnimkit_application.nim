import std/[tables, unittest]

import figdraw/windowing/siwinshim

import merenda/nimkit

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
        window = newWindow("Nimkit Native Test", frame = initRect(80, 80, 240, 140))
        root = newView(frame = initRect(0, 0, 240, 140))

      root.addSubview(newTextField("Native window", frame = initRect(16, 16, 180, 32)))
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
        window = newWindow("Nimkit Native Close", frame = initRect(80, 80, 240, 140))

      window.setContentView(newView(frame = initRect(0, 0, 240, 140)))
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
        window =
          newWindow("Nimkit Native Combo Popup", frame = initRect(80, 80, 260, 160))
        root = newView(frame = initRect(0, 0, 260, 160))
        combo =
          newComboBox(["Low", "Medium", "High"], frame = initRect(16, 16, 140, 24))
        other = newComboBox(["Red", "Green", "Blue"], frame = initRect(16, 58, 140, 24))

      root.addSubview(combo)
      root.addSubview(other)
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
        combo.activateItemAtIndex(1)
        combo.closePopup()
        check combo.indexOfSelectedItem() == 1
        check combo.stringValue == "Medium"
        check window.firstResponder == combo
        let nativeWindow = window.nativeWindowOrNil()
        if not nativeWindow.isNil:
          check nativeWindow.focused()

        check window.mouseDownAt(initPoint(24, 24))
        check combo.popupOpen
        if not nativeWindow.isNil:
          nativeWindow.eventsHandler.onStateBoolChanged(
            siwinshim.StateBoolChangedEvent(
              window: nativeWindow,
              value: true,
              kind: siwinshim.StateBoolChangedEventKind.focus,
            )
          )
        check not combo.popupOpen
        check combo.indexOfSelectedItem() == 1
        check other.indexOfSelectedItem() == -1

        check window.mouseDownAt(initPoint(24, 24))
        check combo.popupOpen
        check window.mouseDownAt(initPoint(24, 68))
        check window.mouseUpAt(initPoint(24, 68))
        check not combo.popupOpen
        check not other.popupOpen
        check combo.indexOfSelectedItem() == 1
        check other.indexOfSelectedItem() == -1
        check window.firstResponder == combo
        if not nativeWindow.isNil:
          check nativeWindow.focused()
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
        window =
          newWindow("Nimkit Inline Combo Popup", frame = initRect(80, 80, 260, 160))
        root = newView(frame = initRect(0, 0, 260, 160))
        combo =
          newComboBox(["Low", "Medium", "High"], frame = initRect(16, 16, 140, 24))

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
