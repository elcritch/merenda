## P7 diagnostic timings; compare on the same machine with benchmark_declarative_views.
## nim ic -d:release -o:deps/benchmark_direct_views tests/benchmark_direct_views.nim
import std/[algorithm, math, monotimes, os, strformat, strutils, times]
import sigils/[core, reactive]
import merenda/nimkit
import merenda/nimkit/directviews except bindingScope
from merenda/nimkit/view/viewconstraints import solveBlocked

type
  Task = ref object of Responder
    id: int
    title: string
    edits: int

  BenchReceiver = ref object of Responder
    calls: int
    counter: Sigil[int]

  InvalidLayoutError = object of CatchableError

var
  checksum: int
  setupOnly: bool
  sampleCount = 5
  csv: File

proc titleChanged(task: Task, value: int) {.signal.}
proc readTitle(task: Task, context: int): string =
  task.title

proc acceptTitle(task: Task, context: int, value: string) =
  task.title = value
  inc task.edits

proc readCounter(receiver: BenchReceiver, context: int): int =
  receiver.counter{}

proc writeCounter(label: Label, value: int) =
  label.stringValue = "Count: " & $value

proc body(
    session: DirectView | DirectViewSession, tasks: seq[Task], receiver: BenchReceiver
) =
  session.viewBody:
    VStack:
      this.distribution = svdNatural
      this.identifier = "list"
      Label:
        this.identifier = "counter"
        bindingScope.onSchedule(
          proc() =
            discard
        )
        bindingScope.bindSigilValue(
          "counter", receiver.counter, receiver, 0, readCounter, this, writeCounter
        )
      for task in tasks:
        keyed($task.id):
          HStack:
            this.distribution = svdNatural
            this.identifier = "row-" & $task.id
            this{vpDraggable} = true
            this.edgeInsets = insets(4)
            Label:
              this.stringValue = "#" & $task.id
            TextField:
              this.identifier = "edit-" & $task.id
              arrangedSizing(svspFillAvailableWidth)
              bindingScope.onSchedule(
                proc() =
                  discard
              )
              bindingScope.bindTextField(
                "title", task, titleChanged, task, task.id, readTitle, this, acceptTitle
              )
            Button:
              this.title = "Remove"
              this.acceptsFirstResponder = false
              onAction(receiver, task.id) do(
                this: Button, owner: BenchReceiver, id: int
              ):
                owner.calls += id + 1

proc elapsedUs(start: MonoTime): float64 =
  (getMonoTime() - start).inNanoseconds.float64 / 1000.0

proc checkLayout(view: View) =
  if view.layoutFeedbackBlocked():
    raise
      newException(InvalidLayoutError, "layout feedback blocked: " & view.identifier)
  for mode in [lsmLayout, lsmFitting]:
    if view.solveBlocked(mode):
      raise newException(
        InvalidLayoutError,
        "view=" & view.identifier & " mode=" & $mode & " diagnostic=" &
          $view.xLastLayoutSolveDiagnostic,
      )
  for child in view.subviews:
    child.checkLayout()

proc measureSamples(name: string, count: int, operation: proc() {.closure.}) =
  # Two warmups, then one calibration operation. Calibrate to roughly 20 ms
  # per batch, capped at 2000 operations. Heavy cases use one operation per batch.
  operation()
  operation()
  let start = getMonoTime()
  operation()
  let iterations = max(1, min(2000, int(ceil(20_000.0 / max(elapsedUs(start), 1.0)))))
  var samples: seq[float64]
  for sample in 1 .. sampleCount:
    let started = getMonoTime()
    for _ in 0 ..< iterations:
      operation()
    let perOperation = elapsedUs(started) / iterations.float64
    samples.add perOperation
  # Publish samples only after every operation completed valid work. A late
  # budget failure must not leave apparently successful timing rows in the CSV.
  if not csv.isNil:
    for i, sample in samples:
      csv.writeLine(&"{count},{name},{i + 1},{iterations},{sample:.6f},ok")
    csv.flushFile()
  samples.sort()
  echo &"rows={count:>3} {name:<27} median_us={samples[samples.len div 2]:>12.3f} " &
    &"min_us={samples[0]:.3f} max_us={samples[^1]:.3f} batch={iterations}"

proc measure(name: string, count: int, operation: proc() {.closure.}) =
  try:
    measureSamples(name, count, operation)
  except InvalidLayoutError as error:
    echo &"rows={count:>3} {name:<27} BLOCKED: {error.msg}"
    if not csv.isNil:
      let reason = ("blocked: " & error.msg).replace("\"", "\"\"")
      csv.writeLine(&"{count},{name},0,0,,\"{reason}\"")
      csv.flushFile()

proc countViews(view: View): int =
  result = 1
  for child in view.subviews:
    result += child.countViews()

proc run(count: int) =
  var tasks: seq[Task]
  for id in 0 ..< count:
    let task = Task(id: id, title: "Task " & $id)
    initResponder(task)
    tasks.add task
  let receiver = BenchReceiver(counter: newSigil(0))
  initResponder(receiver)
  let frame = rect(0, 0, 600, count.float32 * 54 + 50)
  if setupOnly:
    var samples: seq[float64]
    for i in 0 ..< sampleCount + 2:
      let start = getMonoTime()
      let direct = newDirectView(frame)
      direct.body(tasks, receiver)
      let us = elapsedUs(start)
      doAssert direct.arrangedSubviews[0].countViews() == 4 * count + 2
      direct.clear()
      if i >= 2:
        samples.add us
        if not csv.isNil:
          csv.writeLine(&"{count},setup,{i - 1},1,{us:.6f},ok")
    samples.sort()
    echo &"rows={count} setup median_us={samples[samples.len div 2]:.3f}"
    return
  let host = newStackView(frame = frame)
  let session = newDirectViewSession(host)
  session.body(tasks, receiver)
  doAssert host.arrangedSubviews[0].countViews() == 4 * count + 2
  defer:
    session.close()
  let field = host.viewWithIdentifier("edit-0")
  measure(
    "compose_noop",
    count,
    proc() =
      session.body(tasks, receiver)
      checksum += host.arrangedSubviews.len,
  )
  measure(
    "reverse_compose",
    count,
    proc() =
      tasks.reverse()
      session.body(tasks, receiver)
      checksum += host.arrangedSubviews.len,
  )
  doAssert host.viewWithIdentifier("edit-0") == field
  var value = 0
  measure(
    "title_signal_flush",
    count,
    proc() =
      inc value
      let task = tasks[count div 2]
      task.title = "Edited " & $value
      emit task.titleChanged(0)
      session.flushBindings()
      checksum += value,
  )
  measure(
    "counter_sigil_flush",
    count,
    proc() =
      inc value
      receiver.counter <- value
      session.flushBindings()
      checksum += value,
  )
  measure(
    "counter_sigil_flush_layout",
    count,
    proc() =
      inc value
      receiver.counter <- value
      session.flushBindings()
      host.layoutSubtreeIfNeeded()
      host.checkLayout()
      checksum += value,
  )
  measure(
    "mount_close",
    count,
    proc() =
      let mounted = newDirectViewSession(newStackView(frame = frame))
      mounted.body(tasks, receiver)
      checksum += mounted.host.arrangedSubviews.len
      mounted.close(),
  )
  measure(
    "detached_build_drop",
    count,
    proc() =
      let preview = newDirectViewSession(newStackView(frame = frame), detached = true)
      preview.body(tasks, receiver)
      let detached = preview.takeDetachedRoot()
      checksum += StackView(detached).arrangedSubviews.len,
  )
  let environment = DragEnvironment(bounds: frame, appearance: initAppearance())
  measure(
    "drag_preview_capture",
    count,
    proc() =
      let preview = newDirectViewSession(newStackView(frame = frame), detached = true)
      preview.body(tasks, receiver)
      let detached = preview.takeDetachedRoot()
      let capture = captureDragPreview(detached, environment)
      doAssert capture.elements.len == count
      detached.checkLayout()
      checksum += capture.elements.len,
  )
  doAssert receiver.calls == 0
  for task in tasks:
    doAssert task.edits == 0

proc main() =
  var counts = @[10, 100, 300]
  for argument in commandLineParams():
    if argument == "--setup-only":
      setupOnly = true
    elif argument.startsWith("--csv:"):
      csv = open(argument[6 .. ^1], fmWrite)
    elif argument.startsWith("--rows:"):
      counts.setLen(0)
      for count in argument[7 .. ^1].split(','):
        counts.add parseInt(count)
    elif argument.startsWith("--samples:"):
      sampleCount = parseInt(argument[10 .. ^1])
    else:
      raise newException(ValueError, "unknown benchmark argument: " & argument)
  doAssert sampleCount > 0 and sampleCount mod 2 == 1
  doAssert counts.len > 0
  defer:
    if not csv.isNil:
      csv.close()
  if not csv.isNil:
    csv.writeLine("rows,case,sample,iterations,us_per_op,status")
  echo "Nim ",
    NimVersion,
    " / ",
    hostOS,
    " / ",
    hostCPU,
    " / release=",
    defined(release),
    " / ARC=",
    compileOption("mm", "arc"),
    " / samples=",
    sampleCount
  for count in counts:
    doAssert count > 1
    run(count)
  echo "checksum=", checksum

main()
