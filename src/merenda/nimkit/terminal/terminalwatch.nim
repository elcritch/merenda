## UI subscriptions to worker snapshots. PTY readiness belongs to the worker.

import sigils/core
import ../foundation/terminaltrace
import ./terminalsessions

type TerminalOutputWatch* = ref object of Agent
  token*: uint64
  session: TerminalViewSession
  started, stopped: bool

proc terminalOutputReady*(watch: TerminalOutputWatch, token: uint64) {.signal.}
proc terminalOutputWatchStarted*(watch: TerminalOutputWatch, token: uint64) {.signal.}
proc terminalOutputWatchStopped*(watch: TerminalOutputWatch, token: uint64) {.signal.}

proc outputReady(watch: TerminalOutputWatch) {.slot.} =
  if watch.started and not watch.stopped:
    recordTerminalTrace("ui-ready", watch.session.workerIdentity())
    emit watch.terminalOutputReady(watch.token)

var nextWatchIdentity {.threadvar.}: uint64

proc newTerminalOutputWatch*(session: TerminalViewSession): TerminalOutputWatch =
  if not session.isNil:
    inc nextWatchIdentity
    result = TerminalOutputWatch(token: nextWatchIdentity, session: session)

proc start*(watch: TerminalOutputWatch) =
  if watch.isNil or watch.started or watch.stopped:
    return
  watch.started = true
  watch.session.connect(sessionOutputAvailable, watch, outputReady)
  emit watch.terminalOutputWatchStarted(watch.token)
  # Consume anything that arrived before this subscription was attached.
  watch.outputReady()

proc stop*(watch: TerminalOutputWatch) =
  if watch.isNil or watch.stopped:
    return
  watch.stopped = true
  if watch.started:
    watch.session.disconnect(sessionOutputAvailable, watch, outputReady)
  watch.session = nil
  emit watch.terminalOutputWatchStopped(watch.token)
