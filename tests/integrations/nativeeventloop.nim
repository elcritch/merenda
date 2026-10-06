## AppKit tracking loops must service worker results and preserve later wakeups.
when defined(macosx):
  import std/[monotimes, os, strutils, times, unittest]
  import darwin/app_kit/[nsapplication, nsevent, nseventmask, nswindow]
  import darwin/foundation/[nsarray, nsdate, nsgeometry, nsrunloop, nsstring, nstimer]
  import darwin/objc/runtime
  import figdraw/windowing as siwin
  import sigils/threadBase
  import merenda/nimkit/app/[application, backend, windows]
  import merenda/nimkit/app/nativeeventloop
  import merenda/nimkit/controls/nativemenus
  import merenda/nimkit/foundation/[mainthreadwork, types]
  import merenda/nimkit/terminal/terminalviews
  import merenda/nimkit/text/monotextviews
  import ../support/terminalhelpers

  proc addTimer(
    loop: NSRunLoop, timer: NSTimer, mode: NSRunLoopMode
  ) {.objc: "addTimer:forMode:".}

  proc nativeWindows(app: NSApplication): NSArray[NSWindow] {.objc: "windows".}

  {.push cdecl, header: "<CoreFoundation/CoreFoundation.h>".}
  proc CFRunLoopGetCurrent(): pointer {.importc.}
  proc CFRunLoopStop(loop: pointer) {.importc.}
  proc CFRunLoopRunInMode(
    mode: pointer, seconds: cdouble, returnAfterSourceHandled: bool
  ): cint {.importc.}

  {.pop.}

  var nativeLoopTick: proc() {.closure.}

  proc tick(self: ID, command: SEL, timer: ID) {.cdecl, raises: [].} =
    try:
      if not nativeLoopTick.isNil:
        nativeLoopTick()
    except Exception as error:
      echo "native loop regression callback failed: ", error.msg

  proc timerTarget(): NSObject =
    var cls = getClass("NimKitNativeLoopTest")
    if cls.isNil:
      cls = allocateClassPair(getClass("NSObject"), "NimKitNativeLoopTest", 0)
      discard cls.addMethod(sel_registerName("tick:"), tick)
      cls.registerClassPair()
    cast[NSObject](cls.new())

  proc takeWake(): NSEvent =
    NSApplication.sharedApplication().nextEventMatchingMask(
      cast[NSEventMask](1'u64 shl NSApplicationDefined.ord),
      NSDate.distantPast,
      NSDefaultRunLoopMode,
      true,
    )

  suite "NimKit native event loop":
    test "nested native loops honor frame deadlines without a polling timer":
      var deadlines = 0
      var due = getMonoTime() + initDuration(milliseconds = 20)
      let timeout = getMonoTime() + initDuration(seconds = 2)
      withNativeEventLoop(
        proc(): Duration =
          let now = getMonoTime()
          if now >= due:
            inc deadlines
            due = now + initDuration(milliseconds = 20)
            if deadlines == 3:
              CFRunLoopStop(CFRunLoopGetCurrent())
          due - now
      ):
        # CoreFoundation owns this wait. Only the bridge can schedule frames;
        # the two-second timeout is a failure deadline, not a polling interval.
        while deadlines < 3 and getMonoTime() < timeout:
          discard CFRunLoopRunInMode(
            cast[pointer](@"NSModalPanelRunLoopMode"),
            max((timeout - getMonoTime()).inNanoseconds.float64 / 1.0e9, 0.0),
            false,
          )
      check deadlines == 3

    test "a frame rearms a wake consumed by AppKit":
      let app = newApplication("Native wake regression")
      let globals = siwin.sharedSiwinGlobals()
      discard app.runForFrames(1)
      installNativeEventLoopWaker(getCurrentSigilThread())
      discard pollNativeEvents()
      globals.wakeEventLoop()
      # AppKit's tracking loop consumes application-defined events without
      # passing through Siwin's acknowledgement hook.
      require not takeWake().isNil
      discard app.runForFrames(1)
      globals.wakeEventLoop()
      check not takeWake().isNil
      globals.consumeEventLoopWake()

    test "terminal frames continue during and after native tracking and About":
      let
        app = newApplication("Native terminal tracking regression")
        view = newTerminalView(
          initTerminalSpawnOptions(
            shell = "/bin/sh",
            command =
              "stty -echo; printf 'ready\\n'; while IFS= read -r line; do printf '%s\\n' \"$line\"; done",
          ),
          frame = rect(0, 0, 400, 240),
        )
        window = newWindow(
          "Native terminal tracking regression", frame = rect(80, 80, 400, 240)
        )
        target = timerTarget()
      defer:
        nativeLoopTick = nil
        target.release()
        view.close()
        view.session().waitForCommands()
        window.close()
      discard app.showWindow(window, view)
      let readyDeadline = getMonoTime() + initDuration(seconds = 5)
      while "ready" notin view.stringValue() and getMonoTime() < readyDeadline:
        discard app.runForFrames(1)
        sleep(1)
      require "ready" in view.stringValue()

      var sent, received: int
      let deadline = getMonoTime() + initDuration(seconds = 3)
      nativeLoopTick = proc() =
        if sent > received and ("tracking-" & $sent) in view.stringValue():
          received = sent
        if received == 3 or getMonoTime() >= deadline:
          CFRunLoopStop(CFRunLoopGetCurrent())
        elif sent == received:
          inc sent
          view.session().write("tracking-" & $sent & "\n")
      let timer = NSTimer.timerWithTimeInterval(
        0.01, target, sel_registerName("tick:"), nil, true
      )
      NSRunLoop.current().addTimer(timer, @"NSEventTrackingRunLoopMode")
      defer:
        timer.invalidate()
      scheduleMainThreadWork(
        proc(): bool =
          # Use AppKit's tracking mode directly so other GUI suites cannot
          # cancel the test by taking focus away from an interactive menu.
          # AppKit's event source can stop a run-loop invocation as soon as a
          # native event arrives. Tracking resumes it until the menu closes.
          while received < 3 and getMonoTime() < deadline:
            discard CFRunLoopRunInMode(
              cast[pointer](@"NSEventTrackingRunLoopMode"),
              max((deadline - getMonoTime()).inNanoseconds.float64 / 1.0e9, 0.0),
              false,
            )
            # Native tracking dispatches the event that ended its wait. Consume
            # it through AppKit (not Siwin), including coalesced worker wakeups.
            while getMonoTime() < deadline:
              let event = NSApplication.sharedApplication().nextEventMatchingMask(
                  NSEventMaskAny,
                  NSDate.distantPast,
                  @"NSEventTrackingRunLoopMode",
                  true,
                )
              if event.isNil:
                break
              NSApplication.sharedApplication().sendEvent(event)
      )
      discard app.runForFrames(1)
      check sent > 0
      check received == 3

      # Exercise the actual About panel after tracking, then check both this
      # terminal and a newly created worker while the panel is visible.
      let nativeApp = NSApplication.sharedApplication()
      var previousWindows: seq[NSWindow]
      for native in nativeApp.nativeWindows():
        previousWindows.add native
      showStandardAboutPanel("Kosmo regression")
      var about: NSWindow
      for native in nativeApp.nativeWindows():
        if native notin previousWindows:
          about = native
      require not about.isNil
      defer:
        about.orderOut(nil)
      let second = newTerminalView(
        initTerminalSpawnOptions(
          shell = "/bin/sh",
          command = "printf 'new-terminal-ready\\n'; IFS= read -r finish",
        ),
        frame = rect(0, 0, 400, 240),
      )
      let secondWindow =
        newWindow("Terminal after About", frame = rect(500, 80, 400, 240))
      defer:
        second.close()
        second.session().waitForCommands()
        secondWindow.close()
      discard app.showWindow(secondWindow, second)
      view.session().write("after-about\n")
      let afterDeadline = getMonoTime() + initDuration(seconds = 5)
      while (
        "after-about" notin view.stringValue() or
        "new-terminal-ready" notin second.stringValue()
      ) and getMonoTime() < afterDeadline
      :
        discard app.runForFrames(1)
        sleep(1)
      check "after-about" in view.stringValue()
      check "new-terminal-ready" in second.stringValue()
