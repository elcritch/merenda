## NimKit viewport adaptation for Terminex's optional threaded sessions.

import std/math
import terminex/threaded

export threaded

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
): TerminalViewportSnapshot =
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
  for row in 0 ..< info.rows:
    result.lines.add session.lineAtAbsolute(result.start + row)
