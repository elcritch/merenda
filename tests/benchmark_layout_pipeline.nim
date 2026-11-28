## Profile actual DirectView demo updates and live rendering without a native window.
## Build once with -d:merendaProfile and once without it to estimate instrumentation cost.
import std/[hashes, monotimes, os, strutils, times]
include "../examples/direct_views_demo.nim"
import merenda/foundation/mainthreadwork
import merenda/nimkit/debug/viewprofiling
from merenda/nimkit/view/viewconstraints import solveBlocked
import merenda/nimkit/view/viewbase

type LayoutSnapshot = object
  frames, priorities, diagnostics: Hash

proc addSnapshot(view: View, snapshot: var LayoutSnapshot) =
  snapshot.frames = snapshot.frames !& hash(view.identifier)
  let frame = view.frame
  for value in [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]:
    snapshot.frames = snapshot.frames !& hash(value)
  for axis in LayoutAxis:
    snapshot.priorities =
      snapshot.priorities !& hash(view.huggingPriority(axis).priorityValue)
    snapshot.priorities =
      snapshot.priorities !& hash(view.compressionPriority(axis).priorityValue)
  for diagnostic in view.cssLayoutDiagnostics():
    snapshot.diagnostics = snapshot.diagnostics !& hash(diagnostic.viewId)
    snapshot.diagnostics = snapshot.diagnostics !& hash(diagnostic.property)
    snapshot.diagnostics = snapshot.diagnostics !& hash(diagnostic.message)
  snapshot.diagnostics =
    snapshot.diagnostics !& hash(view.xLastLayoutSolveDiagnostic.failed)
  snapshot.diagnostics =
    snapshot.diagnostics !& hash(ord(view.xLastLayoutSolveDiagnostic.limit))
  for child in view.subviews:
    child.addSnapshot(snapshot)

proc layoutSnapshot(view: View): LayoutSnapshot =
  view.addSnapshot(result)
  result.frames = !$result.frames
  result.priorities = !$result.priorities
  result.diagnostics = !$result.diagnostics

proc flushWork() =
  var passes = 0
  while hasPendingMainThreadWork():
    discard drainMainThreadWork()
    inc passes
    doAssert passes < 100, "binding work did not settle"

proc blocked(view: View): bool =
  if view.layoutFeedbackBlocked() or view.solveBlocked(lsmLayout) or
      view.solveBlocked(lsmFitting):
    return true
  for child in view.subviews:
    if child.blocked():
      return true

proc newFixture(count: int, preview: bool, invalid: var bool): TaskController =
  resetViewProfile()
  if preview:
    result = newTaskController()
  else:
    result = newTaskModelController()
    result.setView(result.buildChrome())
  var tasks: TaskRows
  for id in 1 .. count:
    tasks.add TaskItem(id: id, title: "Task " & $id)
  result.replaceTasks(tasks, "Populate")
  flushWork()
  result.history.clearAll()
  result.view.frame = rect(0, 0, 1240, 540)
  discard buildRenders(result.view)
  flushWork()
  discard buildRenders(result.view)
  invalid = result.view.blocked() or currentViewProfile().solverFailures > 0

proc writeHeader(file: File) =
  file.write(
    "preview,rows,operation,sample,wall_ns,blocked,solver_views,solver_constraints,solver_passes,solver_failures,frame_hash,priority_hash,diagnostic_hash"
  )
  for phase in ViewProfilePhase:
    file.write(
      "," & $phase & "_calls," & $phase & "_inclusive_ns," & $phase & "_exclusive_ns"
    )
  file.writeLine("")

proc writeSample(
    file: File,
    preview: bool,
    count: int,
    name: string,
    sample: int,
    elapsed: int64,
    invalid: bool,
    profile: ViewProfile,
    snapshot: LayoutSnapshot,
) =
  file.write(
    $preview & "," & $count & "," & name & "," & $sample & "," & $elapsed & "," &
      $invalid & "," & $profile.solverViews & "," & $profile.solverConstraints & "," &
      $profile.solverPasses & "," & $profile.solverFailures & "," & $snapshot.frames &
      "," & $snapshot.priorities & "," & $snapshot.diagnostics
  )
  for phase in ViewProfilePhase:
    let timing = profile.phases[phase]
    file.write(
      "," & $timing.calls & "," & $timing.nanoseconds & "," &
        $timing.exclusiveNanoseconds
    )
  file.writeLine("")
  file.flushFile()

proc runCase(
    file: File,
    controller: TaskController,
    preview: bool,
    count: int,
    name: string,
    invalidFixture: bool,
) =
  var sequence = 0
  proc operation() =
    inc sequence
    case name
    of "clean":
      discard
    of "counter":
      controller.counter <- sequence
    of "edit":
      controller.editTitle(1, "Edited " & $sequence)
    of "reverse":
      controller.reverseTasks()
    of "resize":
      let width = if sequence mod 2 == 0: 1240.0'f32 else: 1200.0'f32
      controller.view.frame = rect(0, 0, width, 540)
    else:
      raise newException(ValueError, "unknown operation")
    flushWork()
    discard buildRenders(controller.view)

  for _ in 0 ..< 2:
    operation()
  for sample in 1 .. 5:
    resetViewProfile()
    let started = getMonoTime()
    operation()
    let elapsed = (getMonoTime() - started).inNanoseconds
    let profile = currentViewProfile()
    let invalid =
      invalidFixture or controller.view.blocked() or profile.solverFailures > 0
    file.writeSample(
      preview,
      count,
      name,
      sample,
      elapsed,
      invalid,
      profile,
      controller.view.layoutSnapshot(),
    )
    controller.history.clearAll()

proc main() =
  let path =
    if paramCount() > 0:
      paramStr(1)
    else:
      "/tmp/layout-pipeline.csv"
  let file = open(path, fmWrite)
  defer:
    file.close()
  file.writeHeader()
  for count in [10, 50, 100]:
    for preview in [false, true]:
      var invalidFixture: bool
      let controller = newFixture(count, preview, invalidFixture)
      for operation in ["clean", "counter", "edit", "reverse", "resize"]:
        file.runCase(controller, preview, count, operation, invalidFixture)
      controller.setView(nil)
      flushWork()

when isMainModule:
  main()
