## Compare explicit intrinsic-cache opt-in for the demo's built-in leaf controls.
## Run the profiled and unprofiled builds separately; detailed counts require
## -d:merendaProfile. No native window or GPU is involved.
import std/[hashes, monotimes, os, tables, times]
include "../examples/direct_views_demo.nim"
import merenda/nimkit/foundation/[mainthreadwork, viewprofiling]
import merenda/nimkit/intrinsicprofiling
import merenda/nimkit/view/viewgeometry
from merenda/nimkit/view/viewconstraints import solveBlocked

type CachePolicy = enum
  cpOff
  cpLeafControls

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

proc applyPolicy(view: View, policy: CachePolicy) =
  if view of TextField or view of Button:
    view[vpCacheIntrinsicSize] = policy == cpLeafControls
  for child in view.subviews:
    child.applyPolicy(policy)

proc frameHash(view: View, state: var Hash) =
  state = state !& hash(view.identifier)
  let frame = view.frame
  state = state !& hash(frame.origin.x)
  state = state !& hash(frame.origin.y)
  state = state !& hash(frame.size.width)
  state = state !& hash(frame.size.height)
  for child in view.subviews:
    child.frameHash(state)

proc geometryHash(view: View): Hash =
  var state: Hash
  view.frameHash(state)
  !$state

proc newFixture(count: int, policy: CachePolicy, invalid: var bool): TaskController =
  resetViewProfile()
  result = newTaskModelController()
  result.setView(result.buildChrome())
  var tasks: TaskRows
  for id in 1 .. count:
    tasks.add TaskItem(id: id, title: "Task " & $id)
  result.replaceTasks(tasks, "Populate")
  flushWork()
  result.history.clearAll()
  result.view.frame = rect(0, 0, 1240, 540)
  result.view.applyPolicy(policy)
  result.view.invalidateIntrinsicContentSizeSubtree()
  discard buildRenders(result.view)
  flushWork()
  discard buildRenders(result.view)
  invalid = result.view.blocked() or currentViewProfile().solverFailures > 0

proc runCase(
    file, counts: File,
    controller: TaskController,
    policy: CachePolicy,
    name: string,
    invalidFixture: bool,
    baselineFrames: var Table[tuple[operation: string, sample: int], Hash],
) =
  var sequence = 0
  proc operation() =
    inc sequence
    case name
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
    let signature = controller.view.geometryHash()
    let key = (operation: name, sample: sample)
    if policy == cpOff:
      baselineFrames[key] = signature
    elif not invalid:
      doAssert baselineFrames[key] == signature, "cached layout geometry differs"
    file.writeLine(
      $policy & "," & name & "," & $sample & "," & $elapsed & "," & $invalid & "," &
        $signature & "," & $profile.solverViews & "," & $profile.solverConstraints & "," &
        $profile.solverPasses & "," & $profile.phases[vppIntrinsicMeasurement].calls &
        "," & $profile.phases[vppIntrinsicMeasurement].exclusiveNanoseconds
    )
    for entry in currentIntrinsicProfile():
      counts.writeLine(
        $policy & "," & name & "," & $sample & "," & entry.widgetType & "," &
          $entry.event & "," & entry.reason & "," & $entry.count
      )
    file.flushFile()
    counts.flushFile()
    controller.history.clearAll()

proc main() =
  let prefix =
    if paramCount() > 0:
      paramStr(1)
    else:
      "/tmp/intrinsic-reuse"
  let file = open(prefix & "-summary.csv", fmWrite)
  let counts = open(prefix & "-counts.csv", fmWrite)
  defer:
    file.close()
    counts.close()
    setIntrinsicProfileClassifier(nil)
  file.writeLine(
    "policy,operation,sample,wall_ns,blocked,geometry_hash,solver_views,solver_constraints,solver_passes,intrinsic_calls,intrinsic_exclusive_ns"
  )
  counts.writeLine("policy,operation,sample,widget_type,event,reason,count")
  useDefaultIntrinsicProfileCategories()
  var baselineFrames: Table[tuple[operation: string, sample: int], Hash]
  for policy in CachePolicy:
    var invalid: bool
    let controller = newFixture(100, policy, invalid)
    for operation in ["counter", "edit", "reverse", "resize"]:
      file.runCase(counts, controller, policy, operation, invalid, baselineFrames)
    controller.setView(nil)
    flushWork()

when isMainModule:
  main()
