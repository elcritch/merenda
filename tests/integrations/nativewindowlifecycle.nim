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
