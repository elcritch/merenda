## Paired intrinsic-cache comparison for the buffered editable collection.
## Build with -d:release; add -d:merendaProfile for counters.
import std/[hashes, monotimes, os, tables, times]
import merenda/nimkit
import merenda/nimkit/directviews
import merenda/nimkit/debug/viewprofiling
import merenda/nimkit/intrinsicprofiling
import ./intrinsic_collection_fixture
from merenda/nimkit/view/viewconstraints import solveBlocked

type Key = tuple[operation: string, sample: int]

proc addFrames(view: View, value: var Hash) =
  value = value !& hash(view.frame)
  value = value !& hash(view.hidden)
  if view of TextField:
    value = value !& hash(TextField(view).stringValue)
  for child in view.subviews:
    child.addFrames(value)

proc fingerprint(collection: CollectionView, controller: ArrayController): Hash =
  var value: Hash
  collection.addFrames(value)
  let active = controller.indexOfIdentifier("0")
  var indexes = collection.materializationItemIndexes()
  if active >= 0 and active notin indexes:
    indexes.add active
  for index in indexes:
    let row = collection.itemViewAtIndex(index)
    doAssert not row.isNil
    value = value !& hash(controller.itemAt(index).identifier)
    row.addFrames(value)
  !$value

proc isBlocked(view: View): bool =
  if view.layoutFeedbackBlocked() or view.solveBlocked(lsmLayout) or
      view.solveBlocked(lsmFitting):
    return true
  for child in view.subviews:
    if child.isBlocked():
      return true

let reverse = paramCount() > 0 and paramStr(1) == "reverse"
let policies =
  if reverse:
    [true, false]
  else:
    [false, true]
var baseline: Table[Key, Hash]
when defined(merendaProfile):
  useDefaultIntrinsicProfileCategories()
echo "cache,operation,sample,elapsed_us,mounted,buffered,visible,subscriptions,solver_views,solver_passes,intrinsic_calls,intrinsic_us,hits,misses,disabled,fingerprint"
for cache in policies:
  for operation in ["edit", "scroll", "insert", "reorder", "resize"]:
    let demo = newIntrinsicCollectionFixture(5000, cache)
    let controller = ArrayController(demo.view.dataSource())
    let window = newWindow("Buffered cache comparison", frame = rect(0, 0, 640, 480))
    window.setContentView(demo.view)
    discard window.buildRenders()
    let row = DirectView(demo.view.itemViewAtIndex(0))
    doAssert not row.isNil
    let field = TextField(StackView(row.arrangedSubviews[0]).arrangedSubviews[1])
    doAssert window.makeFirstResponder(field)
    for sample in 0 ..< 9:
      resetViewProfile()
      let start = getMonoTime()
      case operation
      of "edit":
        doAssert window.dispatchTextInput($sample)
      of "scroll":
        demo.view.scrollView.contentOffset = initPoint(0, (sample mod 2).float32 * 1200)
      of "insert":
        controller.insertItem(
          modelItem("new-" & $sample, fields = [modelField("title", toObj("New"))]), 0
        )
      of "reorder":
        doAssert controller.moveItem("0", if sample mod 2 == 0: 3 else: 0)
      of "resize":
        window.frame = rect(0, 0, 640 - (sample mod 2).float32 * 40, 480)
      else:
        raise newException(ValueError, "unknown operation")
      demo.rows.flushBindings()
      discard window.buildRenders()
      if operation == "resize":
        doAssert demo.view.frame.size.width == 640 - (sample mod 2).float32 * 40
      let elapsed = (getMonoTime() - start).inMicroseconds
      doAssert not demo.view.isBlocked(), "layout is blocked"
      doAssert field.currentEditor != nil, "editor must remain mounted"
      let signature = fingerprint(demo.view, controller)
      let key = (operation: operation, sample: sample)
      if key in baseline:
        doAssert baseline[key] == signature, "cached and uncached frames differ"
      else:
        baseline[key] = signature
      if sample >= 2:
        let profile = currentViewProfile()
        let measured = profile.phases[vppIntrinsicMeasurement]
        var hits, misses, disabled = 0
        for entry in currentIntrinsicProfile():
          case entry.event
          of ipeCacheHit:
            hits += entry.count
          of ipeColdMiss, ipeInvalidatedMiss, ipeRevisionMismatch:
            misses += entry.count
          of ipeCacheDisabled:
            disabled += entry.count
          else:
            discard
        echo cache,
          ",",
          operation,
          ",",
          sample - 1,
          ",",
          elapsed,
          ",",
          demo.view.visibleItemViews.len,
          ",",
          demo.view.materializationItemIndexes.len,
          ",",
          demo.view.visibleItemIndexes.len,
          ",",
          controller.subcriptions.len + controller.selectionController.subcriptions.len,
          ",",
          profile.solverViews,
          ",",
          profile.solverPasses,
          ",",
          measured.calls,
          ",",
          measured.exclusiveNanoseconds div 1000,
          ",",
          hits,
          ",",
          misses,
          ",",
          disabled,
          ",",
          signature
    demo.rows.close()
    window.close()
