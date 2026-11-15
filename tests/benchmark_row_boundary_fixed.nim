## Controlled fixed-size DirectView row-host comparison. Build with and without
## -d:merendaRowLayoutBoundaries; both builds use the same marked tree.
import std/[hashes, monotimes, os, times]
import merenda/nimkit
import merenda/nimkit/directviews
import merenda/nimkit/foundation/viewprofiling
import merenda/nimkit/view/viewbase
from merenda/nimkit/view/viewconstraints import solveBlocked

type Fixture = object
  root: View
  counter: Label
  rows: seq[DirectView]
  fields: seq[TextField]

proc fixture(count: int): Fixture =
  result.root = newView(frame = rect(0, 0, 1240, 540))
  result.counter = newLabel("Counter: 0")
  result.root.addSubview(result.counter)
  for index in 0 ..< count:
    let row = newDirectView(frame = rect(0, float32(index * 30), 220, 30))
    row.identifier = "row-" & $index
    row.xPrivProps.incl vipExperimentalRowLayoutBoundary
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

proc blocked(view: View): bool =
  if view.layoutFeedbackBlocked() or view.solveBlocked(lsmLayout):
    return true
  for child in view.subviews:
    if child.blocked():
      return true

type Snapshot = object
  frames, priorities, diagnostics: Hash
  partitioned: int

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
  if view.xLayoutInputCache.partitioned:
    inc state.partitioned
  for child in view.subviews:
    child.snapshot(state)

proc run(file: File, count: int, name: string) =
  let data = fixture(count)
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
            count - index - 1
          else:
            index
        row.frame = rect(0, float32(position * 30), 220, 30)
    of "resize":
      let width = if sequence mod 2 == 0: 1240.0'f32 else: 1200.0'f32
      data.root.frame = rect(0, 0, width, 540)
    else:
      raise newException(ValueError, "unknown workload")
    discard buildRenders(data.root)

  for _ in 0 ..< 2:
    operation()
  for sample in 1 .. 5:
    resetViewProfile()
    let start = getMonoTime()
    operation()
    let elapsed = (getMonoTime() - start).inNanoseconds
    let profile = currentViewProfile()
    var state: Snapshot
    data.root.snapshot(state)
    let invalid = data.root.blocked() or profile.solverFailures > 0
    file.writeLine(
      $count & "," & name & "," & $sample & "," & $elapsed & "," & $invalid & "," &
        $profile.solverViews & "," & $profile.solverConstraints & "," &
        $profile.solverPasses & "," & $profile.solverFailures & "," &
        $profile.phases[vppIntrinsicMeasurement].calls & "," &
        $profile.phases[vppIntrinsicMeasurement].exclusiveNanoseconds & "," &
        $profile.phases[vppConstraintInsertion].exclusiveNanoseconds & "," &
        $(!$state.frames) & "," & $(!$state.priorities) & "," & $(!$state.diagnostics) &
        "," & $state.partitioned
    )
    file.flushFile()

proc main() =
  let file = open(paramStr(1), fmWrite)
  defer:
    file.close()
  file.writeLine(
    "rows,operation,sample,wall_ns,blocked,solver_views,solver_constraints,solver_passes,solver_failures,intrinsic_calls,intrinsic_exclusive_ns,insertion_exclusive_ns,frame_hash,priority_hash,diagnostic_hash,partitioned_roots"
  )
  for count in [10, 50, 100]:
    for name in ["edit", "counter", "reorder", "resize"]:
      file.run(count, name)

when isMainModule:
  main()
