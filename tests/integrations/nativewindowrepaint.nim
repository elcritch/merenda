## Native window repaint regressions.
import std/[monotimes, os, times, unittest]

import figdraw/windowing/siwinshim
from siwin/platforms/any/window import eventLoopWaker, wake

import merenda/nimkit/app/application
from merenda/nimkit/app/backend import remMainThread
import merenda/nimkit/app/windows as nimkitWindows
import merenda/nimkit/foundation/[mainthreadwork, types]
import merenda/nimkit/view/views

when defined(linux) or defined(bsd):
  import x11/x except Window
  import x11/xlib
  import siwin/platforms/x11/window as x11Window
elif defined(windows):
  import std/importutils
  import siwin/platforms/winapi/window as winapiWindow
  import siwin/platforms/winapi/winapi as nativeWinapi

  privateAccess winapiWindow.WindowWinapi

proc pumpUntilClean(app: Application, windows: openArray[nimkitWindows.Window]): bool =
  let deadline = getMonoTime() + initDuration(seconds = 5)
  while getMonoTime() < deadline:
    discard app.runForFrames(1)
    var ready = true
    for window in windows:
      if not window.nativeReady or window.nativeRenderCount() == 0 or
          window.needsDisplayUpdate() or window.nativeRenderRequested():
        ready = false
    if ready and not siwinshim.sharedSiwinGlobals().pollEvents():
      return true
    sleep(1)

proc addRepaintWindow(
    app: Application, title: string, x: float32
): nimkitWindows.Window =
  result = newWindow(title, frame = rect(x, 80, 240, 140))
  result.setContentView(newView(frame = rect(0, 0, 240, 140)))
  app.addWindow(result)
  result.makeKeyAndOrderFront()

suite "NimKit native window repaint":
  setup:
    let app = newApplication("Native Repaint Test")
    app.renderExecutionMode = remMainThread
    let
      window = app.addRepaintWindow("Repaint Target", 80)
      otherWindow = app.addRepaintWindow("Unchanged Window", 360)
    defer:
      otherWindow.close()
      window.close()
    require app.pumpUntilClean([window, otherWindow])
    let
      before = window.nativeRenderCount()
      otherBefore = otherWindow.nativeRenderCount()
      nativeWindow = window.nativeWindowOrNil()
      waker = siwinshim.sharedSiwinGlobals().eventLoopWaker()
    require not nativeWindow.isNil

  test "event-loop wakes drain work without repainting clean windows":
    var workDrained = false
    scheduleMainThreadWork(
      proc(): bool =
        workDrained = true
    )
    waker.wake()
    waker.wake()
    check app.runForFrames(1) == 1
    check workDrained
    check window.nativeRenderCount() == before
    check otherWindow.nativeRenderCount() == otherBefore

  test "queued visual changes repaint only the invalidated window":
    var workDrained = false
    scheduleMainThreadWork(
      proc(): bool =
        window.contentView.needsDisplay = true
        workDrained = true
    )
    waker.wake()
    require app.pumpUntilClean([window, otherWindow])
    check workDrained
    check window.nativeRenderCount() > before
    check otherWindow.nativeRenderCount() == otherBefore

  test "onRender repaints a clean view tree without invalidating other windows":
    nativeWindow.redraw()
    require app.pumpUntilClean([window, otherWindow])
    check window.nativeRenderCount() > before
    check otherWindow.nativeRenderCount() == otherBefore

  when defined(linux) or defined(bsd) or defined(windows):
    test "unhandled native activity does not request a repaint":
      block nativeActivity:
        when defined(linux) or defined(bsd):
          if nativeWindow.siwinDisplayServerName() != "x11":
            skip()
            break nativeActivity
          let
            x11NativeWindow = x11Window.WindowX11(nativeWindow)
            display = cast[ptr Display](x11NativeWindow.nativeDisplayHandle())
            handle = x11NativeWindow.nativeWindowHandle().culong
          var event: XEvent
          event.xclient = XClientMessageEvent(
            theType: ClientMessage, display: display, window: handle, format: 32
          )
          require display.XSendEvent(handle, 0, NoEventMask, event.addr) != 0
          discard display.XSync(0)
        else:
          let handle = winapiWindow.WindowWinapi(nativeWindow).handle
          require nativeWinapi.PostMessage(handle, nativeWinapi.WmNull, 0, 0) != 0

        check app.runForFrames(1) == 1
        check window.nativeRenderCount() == before
        check otherWindow.nativeRenderCount() == otherBefore

    test "native damage with a wake repaints only the damaged window":
      block nativeDamage:
        when defined(linux) or defined(bsd):
          if nativeWindow.siwinDisplayServerName() != "x11":
            skip()
            break nativeDamage
          let
            x11NativeWindow = x11Window.WindowX11(nativeWindow)
            display = cast[ptr Display](x11NativeWindow.nativeDisplayHandle())
            handle = x11NativeWindow.nativeWindowHandle().culong
        else:
          let handle = winapiWindow.WindowWinapi(nativeWindow).handle

        let originalSize = nativeWindow.size()
        for wakeFirst in [true, false]:
          let rendered = window.nativeRenderCount()
          check not window.needsDisplayUpdate()
          if wakeFirst:
            waker.wake()
          when defined(linux) or defined(bsd):
            discard display.XClearArea(handle, 0, 0, 0, 0, 1)
            discard display.XSync(0)
          else:
            require nativeWinapi.InvalidateRect(handle, nil, 0) != 0
          if not wakeFirst:
            waker.wake()

          let deadline = getMonoTime() + initDuration(seconds = 5)
          while getMonoTime() < deadline and window.nativeRenderCount() <= rendered:
            discard app.runForFrames(1)
            sleep(1)
          check window.nativeRenderCount() > rendered
          check nativeWindow.size() == originalSize
          check otherWindow.nativeRenderCount() == otherBefore
