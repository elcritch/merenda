## Measures Kosmo's Moe wheel handling, grid update, and CPU-side rendering.
## Run with `nim ic -r tests/benchmark_moe_scroll.nim`.

import std/[algorithm, monotimes, strformat, times]

import merenda/kosmo/kosmo
import merenda/nimkit

proc milliseconds(started: MonoTime): float =
  (getMonoTime() - started).inNanoseconds.float / 1_000_000.0

proc report(label: string, samples: var seq[float]) =
  samples.sort()
  echo &"{label}: median {samples[samples.len div 2]:.3f} ms, " &
    &"p95 {samples[samples.len * 95 div 100]:.3f} ms"

proc benchmark() =
  const Frames = 1_200
  var source: string
  for line in 0 ..< 5_000:
    source.add &"let value{line:04} = calculate(column, {line}) # a sample editor row\n"

  let
    editor = newKosmoEditor(text = source)
    view = newKosmoEditorView(editor)
  defer:
    editor.close()
  view.frame = rect(0, 0, 1_000, 640)
  view.refresh()
  discard view.buildRenders()

  var
    eventSamples = newSeqOfCap[float](Frames)
    frameSamples = newSeqOfCap[float](Frames)
  for frame in 0 ..< Frames + 20:
    let
      started = getMonoTime()
      direction = if frame < Frames div 2 + 20: -1.0'f32 else: 1.0'f32
      outcome = view.scrollBy(direction, row = 2, column = 2)
    let eventMs = milliseconds(started)
    doAssert outcome.handled and outcome.appliedRows == -int(direction)
    discard view.buildRenders()
    if frame >= 20:
      eventSamples.add eventMs
      frameSamples.add milliseconds(started)

  report("wheel + grid", eventSamples)
  report("wheel + grid + frame", frameSamples)

benchmark()
