## PTY readability notifications for terminal views. Parsing stays on the UI thread.

import sigils/core
import terminex/[compactscrollback, termscreen, termsessions]

when defined(posix):
  import std/[posix, tables]
  import chronos
  import sigils/[threadChronos, threadProxies, threads]
  import ../foundation/backgroundworkers

type WatchedTerminalSession = CompactTerminalSession[TerminexCell]

when defined(posix):
  type TerminalReadRegistration = object # Zero means unowned, including after a move.
    descriptorPlusOne: cint
    token: uint64
    registered: bool
    armed: bool

  proc `=destroy`(registration: TerminalReadRegistration)
  proc `=copy`(
    target: var TerminalReadRegistration, source: TerminalReadRegistration
  ) {.error.}

  proc `=dup`(source: TerminalReadRegistration): TerminalReadRegistration {.error.}

  type TerminalOutputReader = ref object of AgentActor
    registration: TerminalReadRegistration

  var activeReaders {.threadvar.}: Table[uint64, WeakRef[TerminalOutputReader]]

  proc `=destroy`(registration: TerminalReadRegistration) =
    if registration.descriptorPlusOne > 0:
      let descriptor = registration.descriptorPlusOne - 1
      activeReaders.del(registration.token)
      if registration.armed:
        discard removeReader2(AsyncFD(descriptor))
      if registration.registered:
        discard unregister2(AsyncFD(descriptor))
      discard posix.close(descriptor)

type TerminalOutputWatch* = ref object of Agent
  token*: uint64
  starting: bool
  started: bool
  stopping: bool
  when defined(posix):
    reader: AgentProxy[TerminalOutputReader]

proc terminalOutputReady*(watch: TerminalOutputWatch, token: uint64) {.signal.}
proc terminalOutputWatchStarted*(watch: TerminalOutputWatch, token: uint64) {.signal.}
proc terminalOutputWatchStopped*(watch: TerminalOutputWatch, token: uint64) {.signal.}
proc terminalOutputWatchFailed*(watch: TerminalOutputWatch, token: uint64) {.signal.}

when defined(posix):
  proc beginRequested(reader: AgentProxy[TerminalOutputReader]) {.signal.}
  proc armRequested(reader: AgentProxy[TerminalOutputReader]) {.signal.}
  proc stopRequested(reader: AgentProxy[TerminalOutputReader]) {.signal.}
  proc readerReady(reader: TerminalOutputReader, token: uint64) {.signal.}
  proc readerStarted(reader: TerminalOutputReader, token: uint64) {.signal.}
  proc readerFailed(reader: TerminalOutputReader, token: uint64) {.signal.}
  proc readerStopped(reader: TerminalOutputReader, token: uint64) {.signal.}

  var
    nextWatchToken {.threadvar.}: uint64
    stoppingWatches {.threadvar.}: seq[TerminalOutputWatch]

  proc masterDescriptor(session: WatchedTerminalSession): cint =
    ## Terminex 0.3.2 has no public descriptor accessor. Field reflection is
    ## type checked; if the dependency changes, this watcher falls back to polling.
    result = -1
    if session.isNil or not session.running():
      return
    for name, value in fieldPairs(session[]):
      when name == "xMasterFd":
        result = value

  proc disarm(reader: TerminalOutputReader) =
    if reader.registration.armed:
      discard removeReader2(AsyncFD(reader.registration.descriptorPlusOne - 1))
      reader.registration.armed = false

  proc closeDescriptor(reader: TerminalOutputReader) =
    let token = reader.registration.token
    reader.registration = TerminalReadRegistration(token: token)

  proc descriptorReady(data: pointer) {.gcsafe, raises: [].} =
    # A queued OS callback may outlive unregistration. Tokens avoid retaining
    # readers or dereferencing a pointer to an actor that has already gone away.
    let token = cast[uint64](data)
    let reference = activeReaders.getOrDefault(token)
    if reference.isNil:
      return
    let reader = reference[]
    if not reader.registration.armed:
      return
    reader.disarm()
    try:
      emit reader.readerReady(token)
    except Exception:
      # Sigils declares Exception; nothing may escape the native callback.
      discard

  proc arm(reader: TerminalOutputReader): bool =
    if reader.registration.descriptorPlusOne == 0 or not reader.registration.registered:
      return
    if reader.registration.armed:
      return true
    if addReader2(
      AsyncFD(reader.registration.descriptorPlusOne - 1),
      descriptorReady,
      cast[pointer](reader.registration.token),
    ).isErr:
      return
    reader.registration.armed = true
    true

  proc beginReading(reader: TerminalOutputReader) {.slot.} =
    let token = reader.registration.token
    if reader.registration.registered:
      return
    if reader.registration.descriptorPlusOne == 0:
      emit reader.readerFailed(token)
      return
    if register2(AsyncFD(reader.registration.descriptorPlusOne - 1)).isErr:
      reader.closeDescriptor()
      emit reader.readerFailed(token)
      return
    reader.registration.registered = true
    activeReaders[token] = reader.unsafeWeakRef()
    if not reader.arm():
      reader.closeDescriptor()
      emit reader.readerFailed(token)
      return
    emit reader.readerStarted(token)

  proc rearm(reader: TerminalOutputReader) {.slot.} =
    let token = reader.registration.token
    if not reader.arm():
      reader.closeDescriptor()
      emit reader.readerFailed(token)

  proc stopReading(reader: TerminalOutputReader) {.slot.} =
    let token = reader.registration.token
    reader.closeDescriptor()
    emit reader.readerStopped(token)

  proc outputReady(watch: TerminalOutputWatch, token: uint64) {.slot.} =
    if not watch.stopping and token == watch.token:
      emit watch.terminalOutputReady(token)

  proc outputStarted(watch: TerminalOutputWatch, token: uint64) {.slot.} =
    if not watch.stopping and token == watch.token:
      watch.started = true
      emit watch.terminalOutputWatchStarted(token)

  proc outputFailed(watch: TerminalOutputWatch, token: uint64) {.slot.} =
    if not watch.stopping and token == watch.token:
      watch.started = false
      emit watch.terminalOutputWatchFailed(token)

  proc outputStopped(watch: TerminalOutputWatch, token: uint64) {.slot.} =
    if token != watch.token:
      return
    watch.reader = nil
    emit watch.terminalOutputWatchStopped(token)
    for index, pending in stoppingWatches:
      if pending == watch:
        stoppingWatches.delete(index)
        break

  proc newTerminalOutputWatch*(session: WatchedTerminalSession): TerminalOutputWatch =
    let descriptor = session.masterDescriptor()
    if descriptor < 0:
      return
    let duplicate = posix.dup(descriptor)
    if duplicate < 0:
      return
    let flags = fcntl(duplicate, F_GETFD)
    if flags < 0 or fcntl(duplicate, F_SETFD, flags or FD_CLOEXEC) < 0:
      discard posix.close(duplicate)
      return
    inc nextWatchToken
    var reader = TerminalOutputReader(
      registration: TerminalReadRegistration(
        descriptorPlusOne: duplicate + 1, token: nextWatchToken
      )
    )
    try:
      result = TerminalOutputWatch(token: nextWatchToken)
      result.reader = reader.moveToThread(nimkitTimerThread())
      connectThreaded(result.reader, beginRequested, result.reader, beginReading)
      connectThreaded(result.reader, armRequested, result.reader, rearm)
      connectThreaded(result.reader, stopRequested, result.reader, stopReading)
      connectThreaded(
        result.reader, readerReady, result, TerminalOutputWatch.outputReady()
      )
      connectThreaded(
        result.reader, readerStarted, result, TerminalOutputWatch.outputStarted()
      )
      connectThreaded(
        result.reader, readerFailed, result, TerminalOutputWatch.outputFailed()
      )
      connectThreaded(
        result.reader, readerStopped, result, TerminalOutputWatch.outputStopped()
      )
    except CatchableError:
      # The reader owns the duplicate, including failed construction.
      result = nil

  proc start*(watch: TerminalOutputWatch) =
    if not watch.isNil and not watch.reader.isNil and not watch.stopping and
        not watch.starting:
      watch.starting = true
      emit watch.reader.beginRequested()

  proc rearm*(watch: TerminalOutputWatch) =
    if not watch.isNil and watch.started and not watch.stopping:
      emit watch.reader.armRequested()

  proc stop*(watch: TerminalOutputWatch) =
    if watch.isNil or watch.stopping or watch.reader.isNil:
      return
    watch.stopping = true
    stoppingWatches.add watch
    emit watch.reader.stopRequested()

else:
  proc newTerminalOutputWatch*(session: WatchedTerminalSession): TerminalOutputWatch =
    discard session

  proc start*(watch: TerminalOutputWatch) =
    discard watch

  proc rearm*(watch: TerminalOutputWatch) =
    discard watch

  proc stop*(watch: TerminalOutputWatch) =
    discard watch

when defined(posix):
  var terminalWatchWorkerLifetime {.used.}: NimkitBackgroundWorkerLifetime
