## Diagnostic timings, not CI thresholds. No native window or GPU is created.
## nim ic -d:release -o:deps/benchmark_declarative_views tests/benchmark_declarative_views.nim
## ./deps/benchmark_declarative_views --csv:/tmp/declarative.csv
## Optional: --rows:10,100,300 --samples:5
import std/[algorithm, math, monotimes, os, strformat, strutils, times]
import merenda/nimkit
from merenda/nimkit/view/viewconstraints import solveBlocked

type
  Task = object
    id: int
    title: string

  BenchReceiver = ref object of Responder
    calls: int

var
  checksum: int
  sampleCount = 5
  csv: File

proc row(task: Task, receiver: BenchReceiver, actions: bool): ViewSpec =
  var changed, removed: ViewAction
  if actions:
    changed = viewAction(receiver, task.id) do(
      owner: BenchReceiver, id: int, sender: DynamicAgent
    ):
      owner.calls += id + 1
    removed = viewAction(receiver, task.id) do(
      owner: BenchReceiver, id: int, sender: DynamicAgent
    ):
      owner.calls += id + 1
  viewBody:
    HStack(identifier = "row-" & $task.id, draggable = true, padding = insets(4)):
      Label("#" & $task.id)
      TextField(
        task.title,
        onChange = changed,
        identifier = "edit-" & $task.id,
        sizing = svspFillAvailableWidth,
      )
      Button("Remove", onAction = removed, focusable = false)

proc body(
    tasks: seq[Task], counter: int, receiver: BenchReceiver, actions = true
): ViewSpec =
  viewBody:
    VStack(identifier = "list"):
      Label("Count: " & $counter, identifier = "counter")
      for task in tasks:
        keyed($task.id):
          row(task, receiver, actions)

proc elapsedUs(start: MonoTime): float64 =
  (getMonoTime() - start).inNanoseconds.float64 / 1000.0

proc checkLayout(view: View) =
  doAssert not view.layoutFeedbackBlocked()
  doAssert not view.solveBlocked(lsmLayout)
  doAssert not view.solveBlocked(lsmFitting)
  for child in view.subviews:
    child.checkLayout()

proc measure(name: string, count: int, operation: proc() {.closure.}) =
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
    if not csv.isNil:
      csv.writeLine(&"{count},{name},{sample},{iterations},{perOperation:.6f}")
      csv.flushFile()
  samples.sort()
  echo &"rows={count:>3} {name:<27} median_us={samples[samples.len div 2]:>12.3f} " &
    &"min_us={samples[0]:.3f} max_us={samples[^1]:.3f} batch={iterations}"

proc run(count: int) =
  var tasks: seq[Task]
  for id in 0 ..< count:
    tasks.add Task(id: id, title: "Task " & $id)
  let receiver = BenchReceiver()
  initResponder(receiver)
  measure(
    "describe_no_actions",
    count,
    proc() =
      let spec = body(tasks, 0, receiver, actions = false)
      checksum += spec.children.len,
  )
  measure(
    "describe_inline_actions",
    count,
    proc() =
      let spec = body(tasks, 0, receiver)
      checksum += spec.children.len,
  )

  let
    spec = body(tasks, 0, receiver)
    frame = rect(0, 0, 600, count.float32 * 54 + 50)
    host = newDeclarativeView(spec, frame)
    field = host.viewWithIdentifier("edit-0")
    counterLabel = Label(host.viewWithIdentifier("counter"))
  defer:
    host.clear()
  host.layoutSubtreeIfNeeded()
  host.checkLayout()
  measure(
    "cached_noop_update",
    count,
    proc() =
      host.update(spec)
      checksum += host.updateStats.reused,
  )
  doAssert host.updateStats == ViewUpdateStats(reused: count * 4 + 2)
  measure(
    "rebuilt_noop_update",
    count,
    proc() =
      host.update(body(tasks, 0, receiver))
      checksum += host.updateStats.reused,
  )
  doAssert host.updateStats == ViewUpdateStats(reused: count * 4 + 2)
  var counter = 0
  measure(
    "counter_update",
    count,
    proc() =
      inc counter
      host.update(body(tasks, counter, receiver))
      checksum += host.updateStats.reused,
  )
  doAssert host.updateStats.created == 0
  measure(
    "text_update",
    count,
    proc() =
      inc counter
      tasks[count div 2].title = "Edited " & $counter
      host.update(body(tasks, 0, receiver))
      checksum += host.updateStats.reused,
  )
  doAssert receiver.calls == 0
  measure(
    "reverse_update",
    count,
    proc() =
      tasks.reverse()
      host.update(body(tasks, 0, receiver))
      checksum += host.updateStats.moved,
  )
  doAssert host.viewWithIdentifier("edit-0") == field
  doAssert host.updateStats.created == 0
  doAssert host.updateStats.removed == 0
  doAssert host.updateStats.moved == count - 1

  var inserted, removed: ViewUpdateStats
  measure(
    "insert_remove_pair",
    count,
    proc() =
      tasks.insert(Task(id: count, title: "Inserted"), 0)
      host.update(body(tasks, 0, receiver))
      inserted = host.updateStats
      tasks.delete(0)
      host.update(body(tasks, 0, receiver))
      removed = host.updateStats
      checksum += removed.removed,
  )
  doAssert inserted.created == 4 and inserted.removed == 0
  doAssert removed.created == 0 and removed.removed == 4
  doAssert host.viewWithIdentifier("edit-0") == field

  measure(
    "counter_update_with_layout",
    count,
    proc() =
      inc counter
      host.update(body(tasks, counter, receiver))
      host.layoutSubtreeIfNeeded()
      checksum += host.updateStats.reused,
  )
  host.checkLayout()
  measure(
    "direct_counter_set",
    count,
    proc() =
      inc counter
      counterLabel.stringValue = "Count: " & $counter
      checksum += counterLabel.stringValue.len,
  )

  # Prebuilt descriptions are outside the timings below. Each timed operation
  # includes widget/snapshot destruction; a mounted tree is explicitly cleared.
  measure(
    "mount_clear",
    count,
    proc() =
      let mounted = newDeclarativeView(spec, frame)
      checksum += mounted.updateStats.created
      mounted.clear(),
  )
  measure(
    "detached_build_drop",
    count,
    proc() =
      let detached = buildDetachedView(spec)
      checksum += StackView(detached).arrangedSubviews.len,
  )
  let environment = DragEnvironment(bounds: frame, appearance: initAppearance())
  block:
    let detached = buildDetachedView(spec)
    let preview = captureDragPreview(detached, environment)
    doAssert preview.elements.len == count
    detached.checkLayout()
  measure(
    "drag_preview_capture",
    count,
    proc() =
      let detached = buildDetachedView(spec)
      let preview = captureDragPreview(detached, environment)
      doAssert preview.elements.len == count
      doAssert not detached.layoutFeedbackBlocked()
      checksum += preview.elements.len,
  )
  doAssert receiver.calls == 0

proc main() =
  var counts = @[10, 100, 300]
  for argument in commandLineParams():
    if argument.startsWith("--csv:"):
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
    csv.writeLine("rows,case,sample,iterations,us_per_op")
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
    " / sizeof(ViewSpec)=",
    sizeof(ViewSpec),
    " / samples=",
    sampleCount
  for count in counts:
    doAssert count > 1
    run(count)
  echo "checksum=", checksum

main()
