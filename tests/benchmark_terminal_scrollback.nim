## Measures terminal scrollback navigation separately from frame construction.
##
## Run with:
##   nim r -d:release tests/benchmark_terminal_scrollback.nim
##
## This is a diagnostic benchmark. It intentionally has no timing threshold so
## machine load and CI hardware cannot turn performance noise into test failures.

import std/[monotimes, strformat, times]

import merenda/nimkit

const
  Columns = 120
  Rows = 40
  HistoryLines = 10_000
  InputLines = HistoryLines * 2 + Rows
  EventIterations = 2_000
  FrameIterations = 250

proc terminalOutput(lineCount: Natural): string =
  result = newStringOfCap(lineCount * (Columns + 2))
  for line in 0 ..< lineCount:
    result.add &"scrollback row {line:05}"
    result.add " abcdefghijklmnopqrstuvwxyz 0123456789"
    result.add "\r\n"

proc elapsedMicroseconds(startedAt: MonoTime, iterations: int): float =
  let nanoseconds = (getMonoTime() - startedAt).inNanoseconds.float
  nanoseconds / 1_000.0 / iterations.float

let
  session = newTerminalSession(Columns, Rows, HistoryLines)
  view = newTerminalView(session, frame = rect(0, 0, 1_200, 640))
  window = newWindow("Terminal scrollback benchmark", frame = rect(0, 0, 1_200, 640))
var startedAt = getMonoTime()
session.processOutput(terminalOutput(InputLines))
let ingestionMean = elapsedMicroseconds(startedAt, InputLines)
discard view.poll()
window.setContentView(view)
discard window.buildRenders()
let point = view.pointToWindow(initPoint(12, 12))

startedAt = getMonoTime()
for _ in 0 ..< EventIterations:
  doAssert window.dispatchScrollWheel(
    ScrollEvent(location: point, deltaY: 1.0'f32, phase: sepChanged)
  )
let eventMean = elapsedMicroseconds(startedAt, EventIterations)

startedAt = getMonoTime()
for _ in 0 ..< FrameIterations:
  doAssert window.dispatchScrollWheel(
    ScrollEvent(location: point, deltaY: 1.0'f32, phase: sepChanged)
  )
  discard window.buildRenders()
let frameMean = elapsedMicroseconds(startedAt, FrameIterations)

echo "Terminal scrollback (", Columns, "x", Rows, ", ", HistoryLines, " history rows)"
echo &"history ingestion  {ingestionMean:>9.2f} us/row"
echo &"event/grid update  {eventMean:>9.2f} us/event"
echo &"event + frame      {frameMean:>9.2f} us/frame"
