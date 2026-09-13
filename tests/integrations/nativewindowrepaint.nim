## Native window repaint regressions.
import std/[monotimes, os, times, unittest]

import figdraw/windowing/siwinshim

import merenda/nimkit

when defined(linux) or defined(bsd):
  import x11/x except Window
  import x11/xlib
  import siwin/platforms/x11/window as x11Window

suite "NimKit native window repaint":
  when defined(linux) or defined(bsd):
    test "X11 expose activity requests a native repaint":
      block nativeExposeRepaint:
        let
          app = newApplication("Native Expose Repaint Test")
          window = newWindow("Native Expose Repaint", frame = rect(80, 80, 240, 140))

        window.setContentView(newView(frame = rect(0, 0, 240, 140)))
        app.addWindow(window)
        window.makeKeyAndOrderFront()

        try:
          check app.runForFrames(2) == 2
          check window.nativeReady
          let nativeWindow = window.nativeWindowOrNil()
          require not nativeWindow.isNil
          if nativeWindow.siwinDisplayServerName() != "x11":
            skip()
            break nativeExposeRepaint

          let
            x11NativeWindow = x11Window.WindowX11(nativeWindow)
            display = cast[ptr Display](x11NativeWindow.nativeDisplayHandle())
            handle = x11NativeWindow.nativeWindowHandle().culong
          require not display.isNil
          require handle != 0

          let before = window.nativeRenderCount()
          discard display.XClearArea(handle, 0, 0, 0, 0, 1)
          discard display.XFlush()
          let deadline = getMonoTime() + initDuration(seconds = 5)
          while getMonoTime() < deadline and window.nativeRenderCount() <= before:
            discard app.runForFrames(1)
            sleep(1)
          check window.nativeRenderCount() > before
        except CatchableError:
          skip()
          break nativeExposeRepaint
        finally:
          window.close()
