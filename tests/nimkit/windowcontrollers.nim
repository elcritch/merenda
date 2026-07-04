import std/unittest

import sigils/core

import merenda/nimkit

type
  LoadingController = ref object of WindowController
  ControllerDelegateSpy = ref object of Responder
  LegacyWindowDelegateSpy = ref object of Responder

var
  loadingEvents: seq[string]
  controllerEvents: seq[string]
  legacyEvents: seq[string]
  allowControllerClose: bool
  allowLegacyClose: bool

protocol LoadingControllerProtocol of WindowControllerLoading:
  method makeWindow(controller: LoadingController): Window =
    loadingEvents.add "makeWindow"
    newWindow("Loaded", frame = rect(0, 0, 240, 160))

  method titleForDisplayName(
      controller: LoadingController, displayName: string
  ): string =
    loadingEvents.add "title:" & displayName
    "Document - " & displayName

protocol ControllerDelegateSpyProtocol of WindowControllerDelegate:
  method controllerWillLoad(
      delegate: ControllerDelegateSpy, controller: WindowController
  ) =
    controllerEvents.add "willLoad"

  method controllerDidLoad(
      delegate: ControllerDelegateSpy, controller: WindowController
  ) =
    controllerEvents.add "didLoad"

  method controllerWillShow(
      delegate: ControllerDelegateSpy, controller: WindowController
  ) =
    controllerEvents.add "willShow"

  method controllerDidShow(
      delegate: ControllerDelegateSpy, controller: WindowController
  ) =
    controllerEvents.add "didShow"

  method controllerShouldClose(
      delegate: ControllerDelegateSpy, controller: WindowController
  ): bool =
    controllerEvents.add "shouldClose"
    allowControllerClose

  method controllerWillClose(
      delegate: ControllerDelegateSpy, controller: WindowController
  ) =
    controllerEvents.add "willClose"

  method controllerDidClose(
      delegate: ControllerDelegateSpy, controller: WindowController
  ) =
    controllerEvents.add "didClose"

  method controllerDidSyncTitle(
      delegate: ControllerDelegateSpy, controller: WindowController
  ) =
    controllerEvents.add "title"

protocol LegacyWindowDelegateSpyProtocol of WindowDelegateProtocol:
  method windowShouldClose(delegate: LegacyWindowDelegateSpy, window: Window): bool =
    legacyEvents.add "shouldClose"
    allowLegacyClose

  method windowWillClose(delegate: LegacyWindowDelegateSpy, window: Window) =
    legacyEvents.add "willClose"

  method windowDidClose(delegate: LegacyWindowDelegateSpy, window: Window) =
    legacyEvents.add "didClose"

suite "nimkit window controllers":
  test "window controller loads lazily and synchronizes document titles through protocol":
    let
      controller = LoadingController()
      delegate = ControllerDelegateSpy()

    loadingEvents = @[]
    controllerEvents = @[]
    allowControllerClose = true
    controller.initWindowController()
    discard controller.withProtocol(LoadingControllerProtocol)
    discard delegate.withProtocol(ControllerDelegateSpyProtocol)
    controller.delegate = delegate

    controller.documentDisplayName = "Spec.nim"
    check not controller.isWindowLoaded

    let window = controller.controlledWindow()
    check controller.isWindowLoaded
    check window.title == "Document - Spec.nim"
    check loadingEvents[0] == "makeWindow"
    check "title:Spec.nim" in loadingEvents
    check "willLoad" in controllerEvents
    check "didLoad" in controllerEvents
    check "title" in controllerEvents

    controller.documentDisplayName = "Renamed.nim"
    check window.title == "Document - Renamed.nim"

    controller.windowTitle = "Explicit Title"
    check window.title == "Explicit Title"

    controller.documentDisplayName = "Ignored.nim"
    check window.title == "Explicit Title"

    controller.clearWindowTitle()
    check window.title == "Document - Ignored.nim"

  test "showWindow integrates owned windows with application ordering":
    let
      app = newApplication()
      other = newWindow("Other", frame = rect(20, 20, 240, 160))
      controller =
        newWindowController(newWindow("Document", frame = rect(0, 0, 240, 160)))

    app.addWindow(other)
    let window = controller.showWindow(app)

    check window.isVisible
    check window.nextResponder() == Responder(controller)
    check controller.nextResponder() == Responder(app)
    check app.keyWindow == window
    check app.mainWindow == window
    check app.orderedWindows[0] == window

    window.orderBack()
    check app.orderedWindows[^1] == window

    window.orderFront()
    check app.orderedWindows[0] == window

    controller.window = nil
    check window.nextResponder() == Responder(app)

  test "window controller bridges close delegates and vetoes":
    let
      window = newWindow("Closable", frame = rect(0, 0, 240, 160))
      legacyDelegate = LegacyWindowDelegateSpy()
      controllerDelegate = ControllerDelegateSpy()

    legacyEvents = @[]
    controllerEvents = @[]
    allowLegacyClose = true
    allowControllerClose = false
    discard legacyDelegate.withProtocol(LegacyWindowDelegateSpyProtocol)
    discard controllerDelegate.withProtocol(ControllerDelegateSpyProtocol)
    window.delegate = legacyDelegate

    let controller = newWindowController(window)
    controller.delegate = controllerDelegate

    check not controller.close()
    check not window.isClosed
    check legacyEvents == @["shouldClose"]
    check controllerEvents == @["shouldClose"]

    allowControllerClose = true
    check controller.close()
    check window.isClosed
    check legacyEvents == @["shouldClose", "shouldClose", "willClose", "didClose"]
    check controllerEvents == @["shouldClose", "shouldClose", "willClose", "didClose"]

    controller.window = nil
    check window.delegate() == DynamicAgent(legacyDelegate)
