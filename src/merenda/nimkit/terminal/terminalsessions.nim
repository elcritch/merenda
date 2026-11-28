## NimKit viewport adaptation for Terminex's optional threaded sessions.

import std/math
import terminex/threaded
from ../../foundation/backgroundworkers import registerBackgroundWorkerShutdownHook

export threaded except newThreadedTerminalSession, spawnThreadedTerminalSession,
  terminalWorkerThread

proc registerTerminalWorkerShutdown*() =
  ## Include Terminex in Foundation shutdown on the calling thread.
  registerBackgroundWorkerShutdownHook(shutdownTerminalWorkers)

proc terminalWorkerThread*(): typeof(threaded.terminalWorkerThread()) =
  registerTerminalWorkerShutdown()
  threaded.terminalWorkerThread()

proc newThreadedTerminalSession*(
    columns = 80, rows = 24, maxScrollback = 10_000
): ThreadedTerminalSession =
  registerTerminalWorkerShutdown()
  threaded.newThreadedTerminalSession(columns, rows, maxScrollback)

proc spawnThreadedTerminalSession*(
    options = initTerminalSpawnOptions(),
    columns = 80,
    rows = 24,
    maxScrollback = 10_000,
): ThreadedTerminalSession =
  registerTerminalWorkerShutdown()
  threaded.spawnThreadedTerminalSession(options, columns, rows, maxScrollback)

type
  TerminalViewSession* = ThreadedTerminalSession
  TerminalViewportSnapshot* = object
    info*: TerminexScreenInfo
    start*: int
    scrollPosition*: float32
    lines*: seq[TerminexLine]
    workerToken*, readSerial*: uint64

proc newTerminalViewSession*(
    columns = 80, rows = 24, maxScrollback = 10_000
): TerminalViewSession =
  newThreadedTerminalSession(columns, rows, maxScrollback)

proc spawnTerminalViewSession*(
    options = initTerminalSpawnOptions(),
    columns = 80,
    rows = 24,
    maxScrollback = 10_000,
): TerminalViewSession =
  spawnThreadedTerminalSession(options, columns, rows, maxScrollback)

proc viewportSnapshot*(
    session: TerminalViewSession,
    scrollPosition: float32,
    previousLinesAdded, previousResetCount: uint64,
    includeLines: bool,
): TerminalViewportSnapshot =
  ## Resolve the viewport. Callers reusing retained rows can fetch lines as needed.
  result.info = session.screenInfo()
  result.workerToken = session.workerIdentity()
  result.readSerial = session.readSequence()
  let info = result.info
  if info.scrollbackResetCount == previousResetCount:
    result.scrollPosition = scrollPosition
    if scrollPosition > 0:
      result.scrollPosition += (info.scrollbackLinesAdded - previousLinesAdded).float32
    result.scrollPosition =
      clamp(result.scrollPosition, 0.0'f32, info.scrollbackCount.float32)
  result.start =
    max(info.totalLineCount - info.rows - int(ceil(result.scrollPosition)), 0)
  if includeLines:
    for row in 0 ..< info.rows:
      result.lines.add session.lineAtAbsolute(result.start + row)

proc viewportSnapshot*(
    session: TerminalViewSession,
    scrollPosition: float32,
    previousLinesAdded, previousResetCount: uint64,
): TerminalViewportSnapshot =
  session.viewportSnapshot(scrollPosition, previousLinesAdded, previousResetCount, true)
