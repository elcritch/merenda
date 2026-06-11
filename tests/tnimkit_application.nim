import std/[tables, unittest]

from figdraw/windowing/siwinshim import nil
import sigils/core

import merenda/nimkit

type WindowHookObserver = ref object of Agent

var
  windowHookEvents: seq[string]
  windowHookAllowContentView: bool
  windowHookAllowFirstResponder: bool
  windowHookAllowDismiss: bool

protocol WindowLifecycleSpyHooks of WindowLifecycleProtocol:
  method shouldSetContentView(window: Window, view: View): bool =
    windowHookEvents.add "shouldContentView"
    windowHookAllowContentView

protocol WindowFocusSpyHooks of WindowFocusProtocol:
  method shouldMakeFirstResponder(window: Window, responder: Responder): bool =
    windowHookEvents.add "shouldFirstResponder"
    windowHookAllowFirstResponder

protocol WindowPopupSpyHooks of WindowPopupProtocol:
  method shouldDismiss(window: Window, reason: DismissReason): bool =
    windowHookEvents.add "shouldDismiss"
    windowHookAllowDismiss

protocol WindowLifecycleObserverEvents of WindowLifecycleEvents:
  proc willSetContentView(observer: WindowHookObserver, view: View) {.slot.} =
    windowHookEvents.add "willContentView"

  proc didSetContentView(observer: WindowHookObserver, oldView: View) {.slot.} =
    windowHookEvents.add "didContentView"

protocol WindowFocusObserverEvents of WindowFocusEvents:
  proc didChangeFirstResponder(
      observer: WindowHookObserver, previous: Responder
  ) {.slot.} =
    windowHookEvents.add "didFirstResponder"

protocol WindowAppearanceObserverEvents of WindowAppearanceEvents:
  proc didChangeEffectiveAppearance(
      observer: WindowHookObserver, appearance: Appearance
  ) {.slot.} =
    windowHookEvents.add "didAppearance"

protocol WindowPopupObserverEvents of WindowPopupEvents:
  proc didDismissTransientSession(
      observer: WindowHookObserver, reason: DismissReason
  ) {.slot.} =
    windowHookEvents.add "didDismiss"

  proc didChangePopupPresentation(
      observer: WindowHookObserver, presentation: PopupPresentation
  ) {.slot.} =
    windowHookEvents.add "didPopupPresentation"

suite "nimkit application":
  test "window protocols observe and veto core window behavior":
    let
      window = newWindow("Window hooks", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      replacement = newView(frame = initRect(0, 0, 240, 160))
      button = newButton("Focus", frame = initRect(16, 16, 90, 32))
      observer = WindowHookObserver()

    windowHookEvents = @[]
    windowHookAllowContentView = false
    windowHookAllowFirstResponder = false
    windowHookAllowDismiss = false
    discard window.withProtocol(WindowLifecycleSpyHooks)
    discard window.withProtocol(WindowFocusSpyHooks)
    discard window.withProtocol(WindowPopupSpyHooks)
    observer.observeProtocol(window, WindowLifecycleEvents)
    observer.observeProtocol(window, WindowFocusEvents)
    observer.observeProtocol(window, WindowAppearanceEvents)
    observer.observeProtocol(window, WindowPopupEvents)

    window.setContentView(root)
    check window.contentView.isNil
    check windowHookEvents == @["shouldContentView"]

    windowHookEvents = @[]
    windowHookAllowContentView = true
    window.setContentView(root)
    check window.contentView == root
    check windowHookEvents == @[
      "shouldContentView", "willContentView", "didContentView"
    ]

    root.addSubview(button)
    windowHookEvents = @[]
    check not window.makeFirstResponder(button)
    check window.firstResponder.isNil
    check windowHookEvents == @["shouldFirstResponder"]

    windowHookEvents = @[]
    windowHookAllowFirstResponder = true
    check window.makeFirstResponder(button)
    check window.firstResponder == button
    check windowHookEvents == @["shouldFirstResponder", "didFirstResponder"]

    windowHookEvents = @[]
    window.setContentView(replacement)
    check window.contentView == replacement
    check window.firstResponder.isNil
    check windowHookEvents ==
      @[
        "shouldContentView", "willContentView", "shouldFirstResponder",
        "didFirstResponder", "didContentView",
      ]

    windowHookEvents = @[]
    window.setAppearance(initAppearance())
    check windowHookEvents == @["didAppearance"]

    windowHookEvents = @[]
    window.setPopupPresentation(ppInline)
    check window.popupPresentation == ppInline
    check windowHookEvents == @["didPopupPresentation"]

    window.beginTransientSession(owner = window)
    windowHookEvents = @[]
    check not window.dismissTransientSession(tdrProgrammatic)
    check window.hasActiveTransientSession()
    check windowHookEvents == @["shouldDismiss"]

    windowHookEvents = @[]
    windowHookAllowDismiss = true
    check window.dismissTransientSession(tdrProgrammatic)
    check not window.hasActiveTransientSession()
    check windowHookEvents == @["shouldDismiss", "didDismiss"]

  test "nil-target actions dispatch through window app and app delegate":
    let
      app = newApplication()
      window = newWindow("Action chain", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      button = newButton("Run", frame = initRect(20, 20, 90, 32))
      action = actionSelector("appDelegateAction")

    var
      actionCount = 0
      actionSender: DynamicAgent

    proc onAction(sender: DynamicAgent) =
      inc actionCount
      actionSender = sender

    let delegate = newActionTarget(action, onAction)
    app.delegate = delegate
    button.action = action
    root.addSubview(button)
    window.setContentView(root)
    app.addWindow(window)

    check button.sendAction()
    check actionCount == 1
    check actionSender == DynamicAgent(button)

  test "window key commands continue through application delegate":
    let
      app = newApplication()
      window = newWindow("Command chain", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      child = newView(frame = initRect(20, 20, 80, 32))
      action = actionSelector("appDelegateCommand")

    var
      actionCount = 0
      actionSender: DynamicAgent

    proc onAction(sender: DynamicAgent) =
      inc actionCount
      actionSender = sender

    child.setAcceptsFirstResponder(true)
    root.addSubview(child)
    window.setContentView(root)
    window.bindKey("k", {kmCommand}, action)
    app.delegate = newActionTarget(action, onAction)
    app.addWindow(window)

    check window.makeFirstResponder(child)
    check window.dispatchKeyDown(
      KeyEvent(key: keyK, keyCode: keyK.ord, modifiers: {kmCommand})
    )
    check actionCount == 1
    check actionSender == DynamicAgent(child)

  test "raw mouse input converts from reported input size to logical size":
    let logicalSize = siwinshim.vec2(360.0'f32, 220.0'f32)

    check rawInputToLogical(
      siwinshim.vec2(72.0'f32, 108.0'f32),
      siwinshim.ivec2(360'i32, 220'i32),
      logicalSize,
    ) == siwinshim.vec2(72.0'f32, 108.0'f32)
    check rawInputToLogical(
      siwinshim.vec2(108.0'f32, 162.0'f32),
      siwinshim.ivec2(540'i32, 330'i32),
      logicalSize,
    ) == siwinshim.vec2(72.0'f32, 108.0'f32)

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

  test "native render request follows display dirty state":
    block nativeRenderRequest:
      let
        app = newApplication()
        window =
          newWindow("Nimkit Native Render Request", frame = initRect(80, 80, 240, 140))
        root = newView(frame = initRect(0, 0, 240, 140))
        child = newView(frame = initRect(16, 16, 80, 40))

      root.addSubview(child)
      window.setContentView(root)
      app.addWindow(window)
      window.makeKeyAndOrderFront()

      try:
        check app.runForFrames(1) == 1
        check window.nativeReady
        check not root.needsDisplayUpdateInSubtree()
        check not window.nativeRenderRequested()
        check not window.requestNativeDisplayUpdateIfNeeded()

        let before = window.nativeRenderCount()
        child.background = initColor(1, 0, 0)
        check root.needsDisplayUpdateInSubtree()
        check window.requestNativeDisplayUpdateIfNeeded()
        check window.nativeRenderRequested()
        check app.runForFrames(1) == 1
        check window.nativeRenderCount() > before
        check not root.needsDisplayUpdateInSubtree()
        check not window.nativeRenderRequested()
      except CatchableError:
        skip()
        break nativeRenderRequest
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
        check window.hasActiveTransientSession()
        let renders = window.buildRenders()
        check PopupDrawLevel notin renders.layers
        combo.activateItemAtIndex(1)
        combo.closePopup()
        check not window.hasActiveTransientSession()
        check combo.indexOfSelectedItem() == 1
        check combo.stringValue == "Medium"
        check window.firstResponder == combo
        let nativeWindow = window.nativeWindowOrNil()
        if not nativeWindow.isNil:
          check siwinshim.focused(nativeWindow)

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
        check not window.hasActiveTransientSession()
        check window.transientDismissReason() == tdrFocusChange
        check combo.indexOfSelectedItem() == 1
        check other.indexOfSelectedItem() == -1

        check window.mouseDownAt(initPoint(24, 24))
        check combo.popupOpen
        check window.hasActiveTransientSession()
        check window.mouseDownAt(initPoint(24, 68))
        check window.mouseUpAt(initPoint(24, 68))
        check not combo.popupOpen
        check not window.hasActiveTransientSession()
        check window.transientDismissReason() == tdrOutsideClick
        check not other.popupOpen
        check combo.indexOfSelectedItem() == 1
        check other.indexOfSelectedItem() == -1
        check window.firstResponder == combo
        if not nativeWindow.isNil:
          check siwinshim.focused(nativeWindow)
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
        check window.hasActiveTransientSession()
        let renders = window.buildRenders()
        check PopupDrawLevel in renders.layers
      except CatchableError:
        skip()
        break nativeInlineComboPopup
      finally:
        combo.closePopup()
        window.close()
