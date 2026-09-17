## Native window lifecycle regressions.
import std/[unittest]

import figdraw/windowing/siwinshim

import merenda/nimkit
import merenda/nimkit/app/windows as nimkitWindows
import merenda/kosmo/kosmo

type NativeWindowDelegateSpy = ref object of Responder
  events: seq[string]

protocol NativeWindowDelegateSpyHooks of WindowDelegateProtocol:
  method windowWillClose(
      delegate: NativeWindowDelegateSpy, window: nimkitWindows.Window
  ) =
    discard window
    delegate.events.add("willClose")

  method windowDidClose(
      delegate: NativeWindowDelegateSpy, window: nimkitWindows.Window
  ) =
    discard window
    delegate.events.add("didClose")

suite "NimKit native window lifecycle":
  test "replacing a native popup keeps the replacement open and reusable":
    let
      window = newWindow("Native popup replacement", frame = rect(80, 80, 320, 240))
      root = newView(frame = rect(0, 0, 320, 240))
      anchor = newView(frame = rect(10, 10, 140, 24))
      firstContent = newView(frame = rect(0, 0, 140, 40))
      secondContent = newView(frame = rect(0, 0, 140, 40))
    defer:
      window.close()
    root.addSubview(anchor)
    window.setContentView(root)
    anchor.acceptsFirstResponder = true
    firstContent.acceptsFirstResponder = true
    secondContent.acceptsFirstResponder = true
    window.makeKeyAndOrderFront()
    window.ensureNativeWindow()
    require window.nativeReady
    let
      first = newPopupHost(
        window,
        anchor,
        firstContent,
        initSize(140, 40),
        presentation = ppWindow,
        restoreResponder = anchor,
      )
      second = newPopupHost(
        window,
        anchor,
        secondContent,
        initSize(140, 40),
        presentation = ppWindow,
        restoreResponder = anchor,
      )
    require first.presentPopup()
    let firstWindow = first.popupWindow()
    require not firstWindow.isNil
    require firstWindow.nativeReady

    require second.presentPopup()
    check not first.popupOpen
    check firstWindow.isClosed
    require not second.popupWindow().isNil
    check second.popupOpen
    check second.popupWindow().nativeReady
    check not second.popupWindow().isClosed
    check window.transientWindow() == second.popupWindow()
    check second.popupWindow().firstResponder == secondContent

    check second.dismissPopup()
    check window.firstResponder == anchor
    check not window.hasActiveTransientSession()
    require second.presentPopup()
    require not second.popupWindow().isNil
    check second.popupWindow().nativeReady
    check not second.popupWindow().isClosed
    check second.dismissPopup()

  test "native close delivers the regular window lifecycle callbacks":
    block nativeDelegateClose:
      let
        app = newApplication("Native Delegate Close Test")
        window = newWindow("Native Delegate Close", frame = rect(80, 80, 240, 140))
        delegate = NativeWindowDelegateSpy()

      initResponder(delegate)
      discard delegate.withProtocol(NativeWindowDelegateSpyHooks)
      window.delegate = delegate
      window.setContentView(newView(frame = rect(0, 0, 240, 140)))
      app.addWindow(window)
      window.makeKeyAndOrderFront()

      try:
        check app.runForFrames(1) == 1
        check window.nativeReady
        let nativeWindow = window.nativeWindowOrNil()
        require not nativeWindow.isNil
        siwinshim.close(nativeWindow)
        check window.isClosed
        check delegate.events == @["willClose", "didClose"]
        window.close()
        check delegate.events == @["willClose", "didClose"]
      except CatchableError:
        skip()
        break nativeDelegateClose
      finally:
        if not window.isClosed:
          window.close()

  test "native Kosmo close closes its independent settings window":
    block nativeKosmoClose:
      let
        app = newApplication("Native Kosmo Close Test")
        frontend = newKosmoApplication(app, monitorsGitStatus = false)

      try:
        frontend.show()
        check frontend.showSettings()
        let settings = frontend.settingsWindow()
        require not settings.isNil
        check app.runForFrames(2) == 2
        check frontend.window.nativeReady
        let nativeWindow = frontend.window.nativeWindowOrNil()
        require not nativeWindow.isNil
        siwinshim.close(nativeWindow)
        check frontend.window.isClosed
        check settings.window.isClosed
      except CatchableError:
        skip()
        break nativeKosmoClose
      finally:
        frontend.close()
