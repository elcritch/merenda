## Readiness delivery, backpressure, and PTY descriptor ownership.
when defined(posix):
  import std/[monotimes, os, strutils, times, unittest]
  import sigils/[core, threads]
  import terminex
  import merenda/nimkit/app/[animations, diagnostics, windows]
  import merenda/nimkit/foundation/[backgroundworkers, types]
  import merenda/nimkit/terminal/[terminalviews, terminalwatch]
  import merenda/nimkit/text/monotextviews

  type WatchSpy = ref object of Agent
    started, ready, failed, stopped: int
    token: uint64

  proc didStart(spy: WatchSpy, token: uint64) {.slot.} =
    inc spy.started
    spy.token = token

  proc didRead(spy: WatchSpy, token: uint64) {.slot.} =
    inc spy.ready
    spy.token = token

  proc didFail(spy: WatchSpy, token: uint64) {.slot.} =
    inc spy.failed
    spy.token = token

  proc didStop(spy: WatchSpy, token: uint64) {.slot.} =
    inc spy.stopped
    spy.token = token

  proc observe(watch: TerminalOutputWatch, spy: WatchSpy) =
    watch.connect(terminalOutputWatchStarted, spy, didStart)
    watch.connect(terminalOutputReady, spy, didRead)
    watch.connect(terminalOutputWatchFailed, spy, didFail)
    watch.connect(terminalOutputWatchStopped, spy, didStop)

  template waitFor(condition: untyped) =
    block:
      let deadline = getMonoTime() + initDuration(seconds = 5)
      while not (condition) and getMonoTime() < deadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(1)
      require condition

  proc waitForText(session: CompactTerminalSession[TerminexCell], text: string): bool =
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      discard session.poll()
      if text in session.screen().plainText():
        return true
      sleep(1)

  proc spawnEchoSession(): CompactTerminalSession[TerminexCell] =
    spawnCompactTerminalSession(
      initTerminalSpawnOptions(
        command =
          "stty -echo; printf 'watch-ready\\n'; while IFS= read -r line; do printf 'received:%s\\n' \"$line\"; done"
      ),
      columns = 60,
      rows = 8,
    )

  suite "Terminal output watches":
    test "readability is one-shot and parsing stays on the caller thread":
      discard nimkitTimerThread()
      let session = spawnEchoSession()
      defer:
        session.close()
      require session.waitForText("watch-ready")
      let watch = newTerminalOutputWatch(session)
      require not watch.isNil
      defer:
        watch.stop()
      let spy = WatchSpy()
      watch.observe(spy)
      watch.start()
      watch.start()
      waitFor(spy.started == 1)
      check spy.failed == 0
      session.write("first\n")
      waitFor(spy.ready == 1)
      check "received:first" notin session.screen().plainText()
      require session.waitForText("received:first")
      session.write("second\n")
      require session.waitForText("received:second")
      check spy.ready == 1
      watch.rearm()
      session.write("third\n")
      waitFor(spy.ready == 2)
      require session.waitForText("received:third")
      watch.stop()
      watch.stop()
      watch.rearm()
      waitFor(spy.stopped == 1)
      check spy.token == watch.token
      check spy.failed == 0
      check session.running()
      session.write("after-stop\n")
      require session.waitForText("received:after-stop")
      check spy.ready == 2

    when defined(macosx) or defined(linux):
      test "stop and abandoned watches release their duplicated descriptors":
        discard nimkitTimerThread()
        let session = spawnEchoSession()
        defer:
          session.close()
        require session.waitForText("watch-ready")
        let baseline = processResourceUsage().fileDescriptors
        require baseline >= 0
        for index in 0 ..< 12:
          var watch = newTerminalOutputWatch(session)
          require not watch.isNil
          let spy = WatchSpy()
          watch.observe(spy)
          if index mod 3 != 0:
            watch.start()
            waitFor(spy.started == 1)
          if index mod 3 == 1:
            # Drop a registered watch without an explicit stop.
            watch = nil
          else:
            watch.stop()
            waitFor(spy.stopped == 1)
            watch = nil
          waitFor(processResourceUsage().fileDescriptors <= baseline)
        check session.running()

    test "views receive output without animation ticks and replace old watches":
      let
        first = spawnEchoSession()
        second = spawnEchoSession()
        view = newTerminalView(first, frame = rect(0, 0, 640, 180))
        window = newWindow("Terminal readiness", frame = rect(0, 0, 640, 180))
        other = newWindow("Terminal moved", frame = rect(0, 0, 640, 180))
      defer:
        view.close()
        first.close()
        second.close()
      require first.waitForText("watch-ready")
      require second.waitForText("watch-ready")
      first.readLimit = 8
      second.readLimit = 8
      window.setContentView(view)
      let heartbeat = window.animationScheduler().scheduledAnimations()[0]
      waitFor(heartbeat.cadence.kind == ackInterval)
      check heartbeat.cadence.interval == initDuration(milliseconds = 500)
      first.write("first-view\n")
      waitFor("received:first-view" in view.stringValue())
      # Queue output for the old session before replacing it.
      first.write("stale-view\n")
      view.session = second
      second.write("second-view\n")
      waitFor("received:second-view" in view.stringValue())
      check "first-view" notin view.stringValue()
      check "stale-view" notin view.stringValue()
      window.setContentView(nil)
      check window.animationScheduler().animationCount() == 0
      other.setContentView(view)
      second.write("moved-view\n")
      waitFor("received:moved-view" in view.stringValue())
      view.close()
      check other.animationScheduler().animationCount() == 0
      check not second.running()
