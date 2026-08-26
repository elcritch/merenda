## Pseudo-terminal process transport and terminal parser integration.

import std/os

when defined(posix):
  import std/posix

import ./[terminalparser, terminalscreen]

const
  DefaultTerminalReadLimit* = 1024 * 1024
  DefaultTerminalWriteLimit* = 1024 * 1024
  TerminalReadChunkSize = 16 * 1024

type
  TerminalEnvironmentVariable* = object
    name*, value*: string

  TerminalSpawnOptions* = object
    command*: string
    shell*: string
    workingDirectory*: string
    environment*: seq[TerminalEnvironmentVariable]
    terminalName*: string
    colorTerminal*: string

  TerminalSessionState* = enum
    tssIdle
    tssRunning
    tssExited
    tssClosed
    tssFailed

  TerminalPollResult* = object
    bytesRead*: int
    screenChanged*: bool
    processExited*: bool

  TerminalSessionError* = object of CatchableError

  TerminalSessionObj = object
    xScreen: TerminalScreen
    xParser: TerminalParser
    xState: TerminalSessionState
    xExitCode: int
    xError: string
    xPendingWrite: string
    xReadLimit, xWriteLimit: int
    when defined(posix):
      xMasterFd: cint
      xChildPid: Pid

  TerminalSession* = ref TerminalSessionObj

when defined(posix):
  when defined(macosx):
    proc forkpty(
      master: var cint, name: cstring, termios: pointer, size: pointer
    ): Pid {.importc, header: "<util.h>".}

  elif defined(freebsd):
    {.passL: "-lutil".}
    proc forkpty(
      master: var cint, name: cstring, termios: pointer, size: pointer
    ): Pid {.importc, header: "<libutil.h>".}

  else:
    proc forkpty(
      master: var cint, name: cstring, termios: pointer, size: pointer
    ): Pid {.importc, header: "<pty.h>".}

  type TerminalWindowSize {.importc: "struct winsize", header: "<sys/ioctl.h>".} = object
    ws_row: cushort
    ws_col: cushort
    ws_xpixel: cushort
    ws_ypixel: cushort

  when defined(macosx) or defined(freebsd):
    const TerminalSetWindowSize = 0x80087467.culong
  else:
    const TerminalSetWindowSize = 0x5414.culong

  proc ioctl(
    descriptor: cint, request: culong
  ): cint {.importc, header: "<sys/ioctl.h>", varargs.}

template releaseTerminalProcess(session: TerminalSessionObj) =
  when defined(posix):
    if session.xMasterFd >= 0:
      discard posix.close(session.xMasterFd)
    if session.xChildPid > 0 and session.xState == tssRunning:
      discard killpg(session.xChildPid, SIGHUP)
      discard killpg(session.xChildPid, SIGKILL)
      discard kill(session.xChildPid, SIGKILL)
      var status: cint
      discard waitpid(session.xChildPid, status, 0)

proc `=destroy`(session: TerminalSessionObj) =
  releaseTerminalProcess(session)

proc `=wasMoved`(session: var TerminalSessionObj) =
  when defined(posix):
    session.xMasterFd = -1
    session.xChildPid = 0

proc `=copy`(destination: var TerminalSessionObj, source: TerminalSessionObj) {.error.}
proc `=dup`(source: TerminalSessionObj): TerminalSessionObj {.error.}

func initTerminalEnvironmentVariable*(
    name, value: string
): TerminalEnvironmentVariable =
  TerminalEnvironmentVariable(name: name, value: value)

func initTerminalSpawnOptions*(
    command = "",
    shell = "",
    workingDirectory = "",
    environment: openArray[TerminalEnvironmentVariable] = [],
    terminalName = "xterm-256color",
    colorTerminal = "truecolor",
): TerminalSpawnOptions =
  TerminalSpawnOptions(
    command: command,
    shell: shell,
    workingDirectory: workingDirectory,
    environment: @environment,
    terminalName: terminalName,
    colorTerminal: colorTerminal,
  )

func terminalSessionsSupported*(): bool =
  defined(posix)

proc newTerminalSession*(
    columns = DefaultTerminalColumns,
    rows = DefaultTerminalRows,
    maxScrollback = DefaultTerminalScrollback,
): TerminalSession =
  new(result)
  result.xScreen = initTerminalScreen(columns, rows, maxScrollback)
  result.xParser = initTerminalParser()
  result.xState = tssIdle
  result.xExitCode = -1
  result.xReadLimit = DefaultTerminalReadLimit
  result.xWriteLimit = DefaultTerminalWriteLimit
  when defined(posix):
    result.xMasterFd = -1

func screen*(session: TerminalSession): lent TerminalScreen =
  session.xScreen

func state*(session: TerminalSession): TerminalSessionState =
  session.xState

func running*(session: TerminalSession): bool =
  session.xState == tssRunning

func exitCode*(session: TerminalSession): int =
  session.xExitCode

func lastError*(session: TerminalSession): string =
  session.xError

func pendingWriteBytes*(session: TerminalSession): int =
  session.xPendingWrite.len

func readLimit*(session: TerminalSession): int =
  session.xReadLimit

proc `readLimit=`*(session: TerminalSession, value: int) =
  session.xReadLimit = max(value, TerminalReadChunkSize)

func writeLimit*(session: TerminalSession): int =
  session.xWriteLimit

proc `writeLimit=`*(session: TerminalSession, value: int) =
  session.xWriteLimit = max(value, 1)

proc processOutput*(session: TerminalSession, data: string) =
  session.xParser.feed(session.xScreen, data)

when defined(posix):
  proc ioError(operation: string): ref TerminalSessionError =
    newException(TerminalSessionError, operation & ": " & $strerror(errno))

  proc resolvedShell(options: TerminalSpawnOptions): string =
    if options.shell.len > 0:
      options.shell
    else:
      getEnv("SHELL", "/bin/sh")

  proc configureChild(options: TerminalSpawnOptions) =
    if options.workingDirectory.len > 0 and chdir(options.workingDirectory.cstring) != 0:
      exitnow(126)
    putEnv("TERM", options.terminalName)
    putEnv("COLORTERM", options.colorTerminal)
    putEnv("TERM_PROGRAM", "NimKit")
    for variable in options.environment:
      if variable.name.len > 0 and '=' notin variable.name:
        putEnv(variable.name, variable.value)

  proc executeChild(options: TerminalSpawnOptions) {.noreturn.} =
    options.configureChild()
    let shell = options.resolvedShell()
    if options.command.len > 0:
      discard
        execl(shell.cstring, shell.cstring, "-lc".cstring, options.command.cstring, nil)
    else:
      discard execl(shell.cstring, shell.cstring, nil)
    exitnow(127)

  proc setNonBlocking(descriptor: cint) =
    let flags = fcntl(descriptor, F_GETFL)
    if flags < 0 or fcntl(descriptor, F_SETFL, flags or O_NONBLOCK) < 0:
      raise ioError("configure PTY")

proc start*(session: TerminalSession, options = initTerminalSpawnOptions()) =
  if session.isNil:
    raise newException(TerminalSessionError, "cannot start a nil terminal session")
  if session.xState == tssRunning:
    raise newException(TerminalSessionError, "terminal session is already running")
  when defined(posix):
    var
      descriptor: cint
      windowSize = TerminalWindowSize(
        ws_row: session.xScreen.rows.cushort, ws_col: session.xScreen.columns.cushort
      )
    let child = forkpty(descriptor, nil, nil, addr windowSize)
    if child < 0:
      session.xState = tssFailed
      session.xError = "start PTY: " & $strerror(errno)
      raise newException(TerminalSessionError, session.xError)
    if child == 0:
      options.executeChild()

    try:
      descriptor.setNonBlocking()
    except TerminalSessionError as error:
      discard posix.close(descriptor)
      discard killpg(child, SIGKILL)
      discard kill(child, SIGKILL)
      var status: cint
      discard waitpid(child, status, 0)
      session.xState = tssFailed
      session.xError = error.msg
      raise
    session.xMasterFd = descriptor
    session.xChildPid = child
    session.xState = tssRunning
    session.xExitCode = -1
    session.xError.setLen(0)
    session.xPendingWrite.setLen(0)
  else:
    session.xState = tssFailed
    session.xError = "pseudo-terminals are not supported on this platform"
    raise newException(TerminalSessionError, session.xError)

proc spawnTerminalSession*(
    options = initTerminalSpawnOptions(),
    columns = DefaultTerminalColumns,
    rows = DefaultTerminalRows,
    maxScrollback = DefaultTerminalScrollback,
): TerminalSession =
  result = newTerminalSession(columns, rows, maxScrollback)
  result.start(options)

when defined(posix):
  proc tryWrite(session: TerminalSession): int =
    while session.xPendingWrite.len > 0:
      let written = posix.write(
        session.xMasterFd,
        unsafeAddr session.xPendingWrite[0],
        session.xPendingWrite.len,
      )
      if written > 0:
        result += written.int
        if written.int >= session.xPendingWrite.len:
          session.xPendingWrite.setLen(0)
        else:
          session.xPendingWrite =
            session.xPendingWrite[written.int ..< session.xPendingWrite.len]
      elif written < 0 and errno == EINTR:
        discard
      elif written < 0 and (errno == EAGAIN or errno == EWOULDBLOCK):
        return
      else:
        raise ioError("write PTY")

proc flushInput*(session: TerminalSession): int {.discardable.} =
  if not session.running() or session.xPendingWrite.len == 0:
    return
  when defined(posix):
    result = session.tryWrite()

proc write*(session: TerminalSession, data: string) =
  if not session.running():
    raise newException(TerminalSessionError, "terminal session is not running")
  if data.len == 0:
    return
  discard session.flushInput()
  if session.xPendingWrite.len + data.len > session.xWriteLimit:
    raise newException(TerminalSessionError, "terminal input buffer is full")
  session.xPendingWrite.add data
  discard session.flushInput()

when defined(posix):
  proc recordExit(session: TerminalSession, status: cint) =
    if WIFEXITED(status):
      session.xExitCode = WEXITSTATUS(status).int
    elif WIFSIGNALED(status):
      session.xExitCode = 128 + WTERMSIG(status).int
    else:
      session.xExitCode = -1
    session.xState = tssExited
    session.xChildPid = 0
    if session.xMasterFd >= 0:
      discard posix.close(session.xMasterFd)
      session.xMasterFd = -1

  proc checkExit(session: TerminalSession): bool =
    if session.xChildPid <= 0:
      return session.xState == tssExited
    var status: cint
    let child = waitpid(session.xChildPid, status, WNOHANG)
    if child > 0:
      session.recordExit(status)
      true
    else:
      false

proc poll*(session: TerminalSession): TerminalPollResult =
  if not session.running():
    result.processExited = session.xState == tssExited
    return
  let generation = session.xScreen.generation
  try:
    discard session.flushInput()
    when defined(posix):
      var consumed = 0
      while consumed < session.xReadLimit:
        var buffer =
          newString(min(TerminalReadChunkSize, session.xReadLimit - consumed))
        let count = posix.read(session.xMasterFd, addr buffer[0], buffer.len)
        if count > 0:
          buffer.setLen(count.int)
          consumed += count.int
          session.processOutput(buffer)
        elif count < 0 and errno == EINTR:
          discard
        elif count < 0 and (errno == EAGAIN or errno == EWOULDBLOCK or errno == EIO):
          break
        else:
          break
      result.bytesRead = consumed
      let replies = session.xScreen.takePendingReplies()
      for reply in replies:
        session.write(reply)
      result.processExited = session.checkExit()
  except TerminalSessionError as error:
    session.xError = error.msg
  result.screenChanged = generation != session.xScreen.generation

proc resize*(session: TerminalSession, columns, rows: int) =
  session.xScreen.resize(columns, rows)
  if session.running():
    when defined(posix):
      var size = TerminalWindowSize(
        ws_row: session.xScreen.rows.cushort, ws_col: session.xScreen.columns.cushort
      )
      if ioctl(session.xMasterFd, TerminalSetWindowSize, addr size) < 0:
        session.xError = "resize PTY: " & $strerror(errno)

proc sendSignal*(session: TerminalSession, signal: int): bool {.discardable.} =
  if not session.running():
    return false
  when defined(posix):
    result = killpg(session.xChildPid, signal.cint) == 0

proc interrupt*(session: TerminalSession): bool {.discardable.} =
  when defined(posix):
    session.sendSignal(SIGINT)
  else:
    false

proc terminate*(session: TerminalSession): bool {.discardable.} =
  when defined(posix):
    session.sendSignal(SIGTERM)
  else:
    false

proc close*(session: TerminalSession) =
  if session.isNil or session.xState == tssClosed:
    return
  when defined(posix):
    if session.xMasterFd >= 0:
      discard posix.close(session.xMasterFd)
      session.xMasterFd = -1
    if session.xChildPid > 0:
      if session.xState == tssRunning:
        discard killpg(session.xChildPid, SIGHUP)
        discard killpg(session.xChildPid, SIGKILL)
        discard kill(session.xChildPid, SIGKILL)
      var status: cint
      discard waitpid(session.xChildPid, status, 0)
      session.xChildPid = 0
  session.xPendingWrite.setLen(0)
  session.xState = tssClosed
