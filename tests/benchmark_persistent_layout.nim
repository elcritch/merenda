## Compare opt-in persistent solves with fresh solves for fixed live trees and
## the unmodified DirectView task demo. Run the two builds sequentially.
import std/[hashes, monotimes, os, times]
include "../examples/direct_views_demo.nim"
import merenda/nimkit/foundation/[mainthreadwork, viewprofiling]
import merenda/nimkit/view/viewbase
from merenda/nimkit/view/viewconstraints import solveBlocked

proc flushWork() =
  var passes = 0
  while hasPendingMainThreadWork():
    discard drainMainThreadWork()
    inc passes
    doAssert passes < 100

proc blocked(view: View): bool =
  if view.layoutFeedbackBlocked() or view.solveBlocked(lsmLayout) or
      view.solveBlocked(lsmFitting):
    return true
  for child in view.subviews:
    if child.blocked():
      return true

type Snapshot = object
  frames, priorities, diagnostics: Hash

proc snapshot(view: View, state: var Snapshot) =
  state.frames = state.frames !& hash(view.identifier)
  let frame = view.frame
  for value in [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]:
    state.frames = state.frames !& hash(value)
  for axis in LayoutAxis:
    state.priorities =
      state.priorities !& hash(view.huggingPriority(axis).priorityValue)
    state.priorities =
      state.priorities !& hash(view.compressionPriority(axis).priorityValue)
  for diagnostic in view.cssLayoutDiagnostics():
    state.diagnostics = state.diagnostics !& hash(diagnostic.viewId)
    state.diagnostics = state.diagnostics !& hash(diagnostic.property)
    state.diagnostics = state.diagnostics !& hash(diagnostic.message)
  state.diagnostics = state.diagnostics !& hash(view.xLastLayoutSolveDiagnostic.failed)
  state.diagnostics =
    state.diagnostics !& hash(ord(view.xLastLayoutSolveDiagnostic.limit))
  for child in view.subviews:
    child.snapshot(state)

proc writeSample(
    file: File,
    scenario: string,
    preview: bool,
    operation: string,
    sample: int,
    elapsed: int64,
    root: View,
    profile: ViewProfile,
    fixtureInvalid: bool,
) =
  var state: Snapshot
  root.snapshot(state)
  let invalid = fixtureInvalid or root.blocked() or profile.solverFailures > 0
  file.writeLine(
    scenario & "," & $preview & ",100," & operation & "," & $sample & "," & $elapsed &
      "," & $invalid & "," & $profile.solverViews & "," & $profile.solverConstraints &
      "," & $profile.solverPasses & "," & $profile.solverFailures & "," &
      $profile.persistentBuilds & "," & $profile.persistentReuses & "," &
      $profile.persistentFallbacks & "," & $profile.phases[vppIntrinsicMeasurement].calls &
      "," & $profile.phases[vppConstraintInsertion].calls & "," &
      $profile.phases[vppConstraintInsertion].nanoseconds & "," &
      $profile.phases[vppSolve].nanoseconds & "," & $(!$state.frames) & "," &
      $(!$state.priorities) & "," & $(!$state.diagnostics)
  )
  file.flushFile()

type FixedFixture = object
  root: View
  counter: Label
  rows: seq[DirectView]
  fields: seq[TextField]

proc fixedFixture(): FixedFixture =
  result.root = newView(frame = rect(0, 0, 1240, 540))
  result.root{vpPersistentLayout} = true
  result.counter = newLabel("Counter: 0")
  result.counter.frame = rect(0, 0, 150, 20)
  result.counter.autoresizingMaskConstraints = true
  result.root.addSubview(result.counter)
  for index in 0 ..< 100:
    let row = newDirectView(frame = rect(0, float32(index * 30), 220, 30))
    row.identifier = "row-" & $index
    row.autoresizingMask = {cxWidthSizable}
    let label = newLabel("#" & $index)
    label.frame = rect(0, 0, 40, 24)
    label.autoresizingMaskConstraints = true
    let field = newTextField(frame = rect(40, 0, 130, 24))
    field.stringValue = "Task " & $index
    field.autoresizingMaskConstraints = true
    let button = newButton("Remove", frame = rect(170, 0, 50, 24))
    button.autoresizingMaskConstraints = true
    row.addSubview(label)
    row.addSubview(field)
    row.addSubview(button)
    result.root.addSubview(row)
    result.rows.add row
    result.fields.add field
  discard buildRenders(result.root)
  discard buildRenders(result.root)

proc runFixed(file: File, name: string) =
  resetViewProfile()
  let data = fixedFixture()
  var fixtureInvalid = data.root.blocked() or currentViewProfile().solverFailures > 0
  var sequence = 0
  proc operation() =
    inc sequence
    case name
    of "edit":
      data.fields[0].stringValue = "Edited " & $sequence
    of "counter":
      data.counter.stringValue = "Counter: " & $sequence
    of "reorder":
      let reverse = sequence mod 2 == 1
      data.root.sortSubviews(
        proc(a, b: View): int =
          if reverse:
            cmp(b.identifier, a.identifier)
          else:
            cmp(a.identifier, b.identifier)
      )
      for index, row in data.rows:
        let position =
          if reverse:
            99 - index
          else:
            index
        row.frame = rect(0, float32(position * 30), 220, 30)
    of "resize":
      let width = if sequence mod 2 == 0: 1240.0'f32 else: 1200.0'f32
      data.root.frame = rect(0, 0, width, 540)
    else:
      raise newException(ValueError, "unknown operation")
    discard buildRenders(data.root)

  for _ in 0 ..< 2:
    operation()
  fixtureInvalid =
    fixtureInvalid or data.root.blocked() or currentViewProfile().solverFailures > 0
  for sample in 1 .. 5:
    resetViewProfile()
    let start = getMonoTime()
    operation()
    let elapsed = (getMonoTime() - start).inNanoseconds
    file.writeSample(
      "fixed",
      false,
      name,
      sample,
      elapsed,
      data.root,
      currentViewProfile(),
      fixtureInvalid,
    )

proc demoFixture(preview: bool): TaskController =
  if preview:
    result = newTaskController()
  else:
    result = newTaskModelController()
    result.setView(result.buildChrome())
  result.view{vpPersistentLayout} = true
  var tasks: TaskRows
  for id in 1 .. 100:
    tasks.add TaskItem(id: id, title: "Task " & $id)
  result.replaceTasks(tasks, "Populate")
  flushWork()
  result.history.clearAll()
  result.view.frame = rect(0, 0, 1240, 540)
  discard buildRenders(result.view)
  flushWork()
  discard buildRenders(result.view)

proc runDemo(file: File, preview: bool, name: string) =
  resetViewProfile()
  let controller = demoFixture(preview)
  var fixtureInvalid =
    controller.view.blocked() or currentViewProfile().solverFailures > 0
  defer:
    controller.setView(nil)
    flushWork()
  var sequence = 0
  proc operation() =
    inc sequence
    case name
    of "edit":
      controller.editTitle(1, "Edited " & $sequence)
    of "counter":
      controller.counter <- sequence
    of "reorder":
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
  fixtureInvalid =
    fixtureInvalid or controller.view.blocked() or
    currentViewProfile().solverFailures > 0
  for sample in 1 .. 5:
    resetViewProfile()
    let start = getMonoTime()
    operation()
    let elapsed = (getMonoTime() - start).inNanoseconds
    file.writeSample(
      "demo",
      preview,
      name,
      sample,
      elapsed,
      controller.view,
      currentViewProfile(),
      fixtureInvalid,
    )
    controller.history.clearAll()

proc main() =
  let file = open(paramStr(1), fmWrite)
  defer:
    file.close()
  file.writeLine(
    "scenario,preview,rows,operation,sample,wall_ns,blocked,solver_views,solver_constraints,solver_passes,solver_failures,persistent_builds,persistent_reuses,persistent_fallbacks,intrinsic_calls,insertion_scopes,insertion_inclusive_ns,solve_inclusive_ns,frame_hash,priority_hash,diagnostic_hash"
  )
  for name in ["edit", "counter", "reorder", "resize"]:
    file.runFixed(name)
  for preview in [false, true]:
    for name in ["edit", "counter", "reorder", "resize"]:
      file.runDemo(preview, name)

when isMainModule:
  main()
