## Readiness delivery, backpressure, and PTY descriptor ownership.
when defined(posix):
  import ../support/terminalhelpers
  import std/[atomics, monotimes, options, os, strutils, tempfiles, times, unittest]
  import sigils/[core, threads]
  import threading/smartptrs
  import terminex
  import merenda/nimkit/app/[animations, diagnostics, windows]
  import merenda/nimkit/foundation/[backgroundworkers, mainthreadwork, types]
  import merenda/nimkit/terminal/[terminalviews, terminalwatch]
  import merenda/nimkit/text/monotextviews

  type WatchSpy = ref object of Agent
    started, ready, stopped: int
    token: uint64

  type RestartSpy = ref object of Agent
    view: TerminalView
    replacement: TerminalViewSession
    exits: int

  type
    WorkerGateState = object
      entered, released, timedOut: Atomic[bool]

    WorkerGate = ref object of AgentActor
      state: SharedPtr[WorkerGateState]

  proc enterGate(gate: AgentProxy[WorkerGate]) {.signal.}
  proc enterGate(gate: WorkerGate) {.slot.} =
    gate.state[].entered.store(true, moRelease)
    let deadline = getMonoTime() + initDuration(seconds = 5)
    # Deliberately stop dispatch on the terminal thread. UI access must complete
    # while this gate is closed, rather than synchronously asking its worker.
    while not gate.state[].released.load(moAcquire) and getMonoTime() < deadline:
      sleep(1)
    if not gate.state[].released.load(moAcquire):
      gate.state[].timedOut.store(true, moRelease)

  proc replaceOnExit(spy: RestartSpy, code: int) {.slot.} =
    discard code
    inc spy.exits
    spy.view.session = spy.replacement

  proc didStart(spy: WatchSpy, token: uint64) {.slot.} =
    inc spy.started
    spy.token = token

  proc didRead(spy: WatchSpy, token: uint64) {.slot.} =
    inc spy.ready
    spy.token = token

  proc didStop(spy: WatchSpy, token: uint64) {.slot.} =
    inc spy.stopped
    spy.token = token

  proc observe(watch: TerminalOutputWatch, spy: WatchSpy) =
    watch.connect(terminalOutputWatchStarted, spy, didStart)
    watch.connect(terminalOutputReady, spy, didRead)
    watch.connect(terminalOutputWatchStopped, spy, didStop)

  template waitFor(condition: untyped, owner: Window = nil) =
    block:
      let deadline = getMonoTime() + initDuration(seconds = 5)
      while not (condition) and getMonoTime() < deadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        if not owner.isNil:
          discard drainMainThreadWork()
          discard owner.drainAnimations()
        sleep(1)
      require condition

  proc waitForText(session: TerminalViewSession, text: string): bool =
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      discard session.poll()
      if text in session.screen().plainText():
        return true
      sleep(1)

  proc spawnEchoSession(): TerminalViewSession =
    spawnTerminalViewSession(
      initTerminalSpawnOptions(
        command =
          "stty -echo; printf 'watch-ready\\n'; while IFS= read -r line; do printf 'received:%s\\n' \"$line\"; done"
      ),
      columns = 60,
      rows = 8,
    )

  suite "Terminal output watches":
    test "worker drains a flood without UI read jobs and coalesces notifications":
      const LineCount = 10_000
      let session = newTerminalViewSession(columns = 60, rows = 8)
      session.start(
        initTerminalSpawnOptions(
          shell = "/bin/sh",
          command =
            "stty -echo; printf 'worker-ready\\n'; IFS= read -r start; " &
            "i=0; while [ $i -lt " & $LineCount & " ]; do " &
            "printf 'worker-line\\n'; i=$((i+1)); done; printf 'worker-final\\n'; exit 9",
        )
      )
      defer:
        session.closeAndWait()
      let readyDeadline = getMonoTime() + initDuration(seconds = 5)
      while "worker-ready" notin session.screen().plainText() and
          getMonoTime() < readyDeadline:
        discard session.poll()
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(1)
      require "worker-ready" in session.screen().plainText()
      let
        watch = newTerminalOutputWatch(session)
        spy = WatchSpy()
        original = session.screen()
      require not watch.isNil
      defer:
        watch.stop()
      watch.observe(spy)
      watch.start()
      waitFor(spy.started == 1)
      discard session.poll()
      spy.ready = 0
      session.write("start\n")
      # Pump delivery, but never poll the session or drain UI read jobs. Parsing
      # and all read continuations must complete on the readiness worker itself.
      waitFor(session.screenInfo().scrollbackLinesAdded == uint64(LineCount + 3 - 8))
      waitFor(spy.ready == 1)
      check "worker-final" in session.screen().plainText()
      check "worker-final" notin original.plainText()
      check session.screenInfo().scrollbackLinesAdded == uint64(LineCount + 3 - 8)
      let update = session.poll()
      check update.bytesRead > 100_000
      let exitDeadline = getMonoTime() + initDuration(seconds = 5)
      while session.running() and getMonoTime() < exitDeadline:
        discard session.poll()
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(1)
      require not session.running()
      check session.exitCode() == 9
      check not update.readPaused
      check session.poll().bytesRead == 0
      watch.stop()
      waitFor(spy.stopped == 1)

    test "a stalled UI cannot stop PTY draining or lose the final snapshot":
      let root = createTempDir("merenda-terminal-backpressure-", "")
      let marker = root / "drained"
      let session = spawnTerminalViewSession(
        initTerminalSpawnOptions(
          shell = "/bin/sh",
          command =
            "i=0; while [ $i -lt 2048 ]; do " &
            "printf 'payload-abcdefghijklmnopqrstuvwxyz-0123456789\\n'; " &
            "i=$((i+1)); done; printf 'last-output\\n'; touch " & quoteShell(marker) &
            "; exit 11",
        ),
        columns = 80,
        rows = 3,
        maxScrollback = 10,
      )
      defer:
        session.closeAndWait()
        removeDir(root)
      # Intentionally withhold UI dispatch/ACKs. The child can reach its marker
      # only if the worker keeps draining a burst larger than the PTY buffer.
      let deadline = getMonoTime() + initDuration(seconds = 10)
      while not fileExists(marker) and getMonoTime() < deadline:
        sleep(1)
      require fileExists(marker)
      check session.screen().plainText() == ""
      waitFor(session.state() == tssExited)
      check session.exitCode() == 11
      check session.screenInfo().scrollbackCount == 10
      check "last-output" in session.screen().plainText()
      check session.poll().bytesRead > 90_000

    when defined(macosx) or defined(linux):
      test "closing worker sessions releases PTYs and readiness descriptors":
        discard terminalWorkerThread()
        let baseline = processResourceUsage().fileDescriptors
        require baseline >= 0
        for index in 0 ..< 3:
          let session = spawnEchoSession()
          defer:
            session.closeAndWait()
          require session.waitForText("watch-ready")
          session.closeAndWait()
          waitFor(processResourceUsage().fileDescriptors <= baseline)

    test "cancelling output observation leaves snapshot polling usable":
      let session = newTerminalViewSession(columns = 60, rows = 8)
      session.start(
        initTerminalSpawnOptions(
          shell = "/bin/sh",
          command =
            "stty -echo; printf 'worker-ready\\n'; while IFS= read -r line; do printf 'received:%s\\n' \"$line\"; done",
        )
      )
      defer:
        session.closeAndWait()
      let
        watch = newTerminalOutputWatch(session)
        spy = WatchSpy()
      require not watch.isNil
      watch.observe(spy)
      watch.start()
      watch.stop() # Cancel before pumping the queued startup acknowledgement.
      waitFor(spy.stopped == 1)
      session.write("after-cancel\n")
      let deadline = getMonoTime() + initDuration(seconds = 5)
      while "received:after-cancel" notin session.screen().plainText() and
          getMonoTime() < deadline:
        discard session.poll()
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(1)
      require "received:after-cancel" in session.screen().plainText()

    test "worker snapshots remain available across detach and reattach":
      let session = newTerminalViewSession(columns = 60, rows = 8)
      session.start(
        initTerminalSpawnOptions(
          shell = "/bin/sh",
          command =
            "stty -echo; printf 'worker-ready\\n'; while IFS= read -r line; do printf 'received:%s\\n' \"$line\"; done",
        )
      )
      defer:
        session.closeAndWait()
      let
        view = newTerminalView(session, frame = rect(0, 0, 640, 180))
        window = newWindow("Worker terminal", frame = rect(0, 0, 640, 180))
      defer:
        view.close()
      window.setContentView(view)
      waitFor("worker-ready" in view.stringValue(), window)
      session.write("first\n")
      waitFor("received:first" in view.stringValue(), window)
      let before = session.screenInfo().generation
      window.setContentView(nil)
      check window.animationScheduler().animationCount() == 0

      session.write("detached\n")
      let deadline = getMonoTime() + initDuration(seconds = 5)
      while "received:detached" notin session.screen().plainText() and
          getMonoTime() < deadline:
        discard session.poll()
        discard getCurrentSigilThread().pollAll(NonBlocking)
        sleep(1)
      require "received:detached" in session.screen().plainText()
      check session.screenInfo().generation > before
      window.setContentView(view)
      check "received:detached" in view.stringValue()
      session.write("reattached\n")
      waitFor("received:reattached" in view.stringValue(), window)
      session.closeAndWait()
      discard window.animationScheduler().tick(initDuration(milliseconds = 500))
      discard drainMainThreadWork()
      check window.animationScheduler().animationCount() == 0

    test "UI queries and commands do not wait for the terminal dispatcher":
      let session = newTerminalViewSession(columns = 60, rows = 8)
      session.start(
        initTerminalSpawnOptions(
          shell = "/bin/sh",
          command =
            "stty -echo; printf 'gate-ready\\n'; while IFS= read -r line; do stty size; printf 'received:%s\\n' \"$line\"; done",
        )
      )
      defer:
        session.closeAndWait()
      let watch = newTerminalOutputWatch(session)
      let spy = WatchSpy()
      watch.observe(spy)
      watch.start()
      defer:
        watch.stop()
      waitFor(spy.started == 1 and "gate-ready" in session.screen().plainText())
      session.writeLimit = 8
      waitFor(session.pendingCommands() == 0)
      let state = newSharedPtr(WorkerGateState())
      var actor = WorkerGate(state: state)
      let gate = actor.moveToThread(terminalWorkerThread())
      connectThreaded(gate, enterGate, gate, WorkerGate.enterGate())
      defer:
        state[].released.store(true, moRelease)
      emit gate.enterGate()
      check not state[].timedOut.load(moAcquire)
      waitFor(state[].entered.load(moAcquire))
      check not state[].timedOut.load(moAcquire)
      let original = session.screen()
      let info = session.screenInfo()
      check session.lineAtAbsolute(info.scrollbackCount) == original.lineAt(0)
      session.resize(41, 7)
      session.write("ordered\n")
      check session.pendingWriteBytes() == 8
      expect TerminexSessionError:
        session.write("overflow")
      check session.pendingCommands() == 2
      check session.screenInfo().columns == 60
      check not state[].timedOut.load(moAcquire)
      state[].released.store(true, moRelease)
      # Keep the proxy alive until its deliberately blocked task is released.
      check not gate.isNil
      waitFor(
        session.pendingCommands() == 0 and
          "received:ordered" in session.screen().plainText()
      )
      check "7 41" in session.screen().plainText()
      check session.screenInfo().columns == 41
      check session.screenInfo().rows == 7
      check session.pendingWriteBytes() == 0
      check original.columns == 60
      session.close()
      check not session.running()
      waitFor(session.pendingCommands() == 0)

    test "queued close and restart reject stale snapshots and preserve final output":
      let session = newTerminalViewSession(columns = 60, rows = 3, maxScrollback = 4)
      session.start(
        initTerminalSpawnOptions(
          shell = "/bin/sh", command = "stty -echo; printf 'first-ready\\n'; read line"
        )
      )
      defer:
        session.closeAndWait()
      let watch = newTerminalOutputWatch(session)
      watch.start()
      defer:
        watch.stop()
      waitFor("first-ready" in session.screen().plainText())
      session.processOutput(
        "one\r\ntwo\r\nthree\r\nfour\r\nfive\r\nsix\r\nseven\r\neight"
      )
      waitFor(session.pendingCommands() == 0)
      check session.screenInfo().scrollbackCount == 4
      let beforeClear = session.screenInfo().scrollbackResetCount
      session.clearScrollback()
      waitFor(session.pendingCommands() == 0)
      check session.screenInfo().scrollbackCount == 0
      check session.screenInfo().scrollbackResetCount > beforeClear
      session.close()
      session.start(
        initTerminalSpawnOptions(
          shell = "/bin/sh", command = "printf '\\r\\nsecond-final\\n'; exit 7"
        )
      )
      waitFor(not session.running() and session.pendingCommands() == 0)
      check session.state() == tssExited
      check session.exitCode() == 7
      check "second-final" in session.screen().plainText()
      let final = session.poll()
      check final.processExited
      check final.bytesRead > 0
      let repeated = session.poll()
      check repeated.processExited
      check repeated.bytesRead == 0

    test "views receive scheduled output and replace old watches":
      let
        first = spawnEchoSession()
        second = spawnEchoSession()
        view = newTerminalView(first, frame = rect(0, 0, 640, 180))
        window = newWindow("Terminal readiness", frame = rect(0, 0, 640, 180))
        other = newWindow("Terminal moved", frame = rect(0, 0, 640, 180))
      defer:
        view.close()
        first.closeAndWait()
        second.closeAndWait()
      require first.waitForText("watch-ready")
      require second.waitForText("watch-ready")
      first.readLimit = 8
      second.readLimit = 8
      window.setContentView(view)
      let heartbeat = window.animationScheduler().scheduledAnimations()[0]
      waitFor(heartbeat.cadence.kind == ackInterval)
      check heartbeat.cadence.interval == initDuration(milliseconds = 500)
      first.write("first-view\n")
      waitFor("received:first-view" in view.stringValue(), window)
      # Queue output for the old session before replacing it.
      first.write("stale-view\n")
      waitFor(
        "received:stale-view" in first.screen().plainText() and
          hasPendingMainThreadWork()
      )
      view.session = second
      second.write("second-view\n")
      waitFor("received:second-view" in view.stringValue(), window)
      check "first-view" notin view.stringValue()
      check "stale-view" notin view.stringValue()
      window.setContentView(nil)
      check window.animationScheduler().animationCount() == 0
      other.setContentView(view)
      second.write("moved-view\n")
      waitFor("received:moved-view" in view.stringValue(), other)
      view.close()
      check other.animationScheduler().animationCount() == 0
      check not second.running()

    test "an exit callback can start output for a replacement session":
      let
        first = spawnEchoSession()
        second = spawnEchoSession()
        view = newTerminalView(first, frame = rect(0, 0, 640, 180))
        window = newWindow("Terminal restart", frame = rect(0, 0, 640, 180))
        spy = RestartSpy(view: view, replacement: second)
      defer:
        view.close()
        first.closeAndWait()
        second.closeAndWait()
      require first.waitForText("watch-ready")
      require second.waitForText("watch-ready")
      view.connect(terminalProcessDidExit, spy, replaceOnExit)
      window.setContentView(view)
      require first.terminate()
      waitFor(spy.exits == 1, window)
      require view.session == second
      second.write("restarted\n")
      waitFor("received:restarted" in view.stringValue(), window)
      check spy.exits == 1

    test "snapshot delivery yields before rendering and close cancels the pending frame":
      let session = spawnEchoSession()
      defer:
        session.closeAndWait()
      require session.waitForText("watch-ready")
      let
        view = newTerminalView(session, frame = rect(0, 0, 640, 180))
        window = newWindow("Terminal batching", frame = rect(0, 0, 640, 180))
      defer:
        view.close()
      window.setContentView(view)
      let heartbeat = window.animationScheduler().scheduledAnimations()[0]
      waitFor(heartbeat.cadence.kind == ackInterval)
      session.write("batched\n")
      waitFor(
        "received:batched" in session.screen().plainText() and hasPendingMainThreadWork()
      )
      check "received:batched" notin view.stringValue()
      waitFor("received:batched" in view.stringValue(), window)
      check window.animationScheduler().animationCount() == 1
      check heartbeat.cadence.interval == initDuration(milliseconds = 500)
      discard window.animationScheduler().tick(initDuration(milliseconds = 500))
      check not hasPendingMainThreadWork()
      check window.animationScheduler().animationCount() == 1

      session.write("cancelled\n")
      waitFor(
        "received:cancelled" in session.screen().plainText() and
          hasPendingMainThreadWork()
      )
      view.close()
      check window.animationScheduler().animationCount() == 0
      discard window.drainAnimations()
      discard drainMainThreadWork()
      check "received:cancelled" notin view.stringValue()

    test "queued UI work is harmless after close and ORC view collection":
      let session = spawnEchoSession()
      defer:
        session.closeAndWait()
      require session.waitForText("watch-ready")
      var reference: BackRef[TerminalView]
      block:
        let view = newTerminalView(session, frame = rect(0, 0, 640, 180))
        let window = newWindow("Abandoned terminal", frame = rect(0, 0, 640, 180))
        reference.target = view
        window.setContentView(view)
        require hasPendingMainThreadWork()
        window.setContentView(nil)
        view.close()
        window.close()
      when defined(gcOrc):
        # ORC can collect the view graph's cycles after its lexical owners leave.
        GC_runOrc()
        check reference.isNil
      discard drainMainThreadWork()
      check not hasPendingMainThreadWork()

    test "closing a session directly stops its attached readiness work":
      let session = spawnEchoSession()
      defer:
        session.closeAndWait()
      require session.waitForText("watch-ready")
      let
        view = newTerminalView(session, frame = rect(0, 0, 640, 180))
        window = newWindow("Terminal closed session", frame = rect(0, 0, 640, 180))
      defer:
        view.close()
      window.setContentView(view)
      let heartbeat = window.animationScheduler().scheduledAnimations()[0]
      waitFor(heartbeat.cadence.kind == ackInterval)
      session.write("closing\n")
      waitFor(
        "received:closing" in session.screen().plainText() and hasPendingMainThreadWork()
      )
      session.closeAndWait()
      discard drainMainThreadWork()
      check not hasPendingMainThreadWork()
      check window.animationScheduler().animationCount() == 0

    test "more output keeps the pending presentation deadline":
      let session = spawnEchoSession()
      defer:
        session.closeAndWait()
      require session.waitForText("watch-ready")
      let
        view = newTerminalView(session, frame = rect(0, 0, 640, 180))
        window = newWindow("Terminal deadline", frame = rect(0, 0, 640, 180))
      defer:
        view.close()
      window.setContentView(view)
      let scheduler = window.animationScheduler()
      let heartbeat = scheduler.scheduledAnimations()[0]
      waitFor(heartbeat.cadence.kind == ackInterval)
      session.write("first\n")
      waitFor(
        "received:first" in session.screen().plainText() and hasPendingMainThreadWork()
      )
      discard drainMainThreadWork()
      require scheduler.animationCount() == 2
      let firstDeadline = scheduler.nextDeadline()
      require firstDeadline.isSome
      check "received:first" notin view.stringValue()

      session.write("second\n")
      let deadline = getMonoTime() + initDuration(seconds = 5)
      while "received:second" notin session.screen().plainText() and
          getMonoTime() < deadline:
        discard getCurrentSigilThread().pollAll(NonBlocking)
        discard drainMainThreadWork()
        sleep(1)
      require "received:second" in session.screen().plainText()
      check scheduler.nextDeadline() == firstDeadline
      check "received:second" notin view.stringValue()
      waitFor("received:second" in view.stringValue(), window)
      check "received:first" in view.stringValue()

    test "a busy terminal yields between batches and retains its final output":
      const LineCount = 10_000
      let session = spawnTerminalViewSession(
        initTerminalSpawnOptions(
          shell = "/bin/sh",
          command =
            "stty -echo; printf 'watch-ready\\n'; IFS= read -r start; " &
            "i=0; while [ $i -lt " & $LineCount & " ]; do " &
            "printf 'payload-line\\n'; i=$((i+1)); done; printf 'final-output\\n'; exit 7",
        ),
        columns = 60,
        rows = 8,
      )
      defer:
        session.closeAndWait()
      require session.waitForText("watch-ready")
      session.readLimit = 16 * 1024
      let
        view = newTerminalView(session, frame = rect(0, 0, 640, 180))
        window = newWindow("Terminal flood", frame = rect(0, 0, 640, 180))
      defer:
        view.close()
      window.setContentView(view)
      let heartbeat = window.animationScheduler().scheduledAnimations()[0]
      waitFor(heartbeat.cadence.kind == ackInterval)
      session.write("start\n")
      var progressFrames = 0
      let deadline = getMonoTime() + initDuration(seconds = 60)
      while session.running() and getMonoTime() < deadline:
        let before = session.screenInfo().generation
        discard getCurrentSigilThread().pollAll(NonBlocking)
        discard drainMainThreadWork()
        discard window.drainAnimations()
        if session.screenInfo().generation != before:
          inc progressFrames
        sleep(1)
      require not session.running()
      check session.exitCode() == 7
      check progressFrames > 0
      check "final-output" in view.stringValue()
      check session.screenInfo().scrollbackLinesAdded ==
        uint64(LineCount + 3 - session.screenInfo().rows)
      check window.animationScheduler().animationCount() == 0
