## Fixed-viewport materialized and virtualized DirectView rows.
## Build with -d:release -d:merendaProfile; phase timings overlap.
import std/[monotimes, times]
import sigils/selectors
import merenda/nimkit
import merenda/nimkit/directviews
import merenda/nimkit/debug/viewprofiling
from merenda/nimkit/view/viewconstraints import solveBlocked

proc readTitle(controller: ArrayController, id: string): string =
  controller.itemWithIdentifier(id).title

proc applyTitle(field: TextField, title: string) =
  field.stringValue = title

proc buildRow(row: DirectView, controller: ArrayController, id: string) =
  row.viewBody:
    HStack:
      Label:
        this.stringValue = id
      TextField:
        this.bindValue(
          "title", controller, arrayControllerDidChange, controller, id, readTitle,
          applyTitle,
        )
      Button:
        this.title = "Remove"

proc blocked(view: View): bool =
  if view.layoutFeedbackBlocked() or view.solveBlocked(lsmLayout) or
      view.solveBlocked(lsmFitting):
    return true
  for child in view.subviews:
    if child.blocked():
      return true

proc report(
    kind, operation: string,
    count, height, mounted, subscriptions: int,
    started: MonoTime,
    root: View,
) =
  let profile = currentViewProfile()
  echo "variant=",
    kind,
    " operation=",
    operation,
    " items=",
    count,
    " viewport_height=",
    height,
    " mounted=",
    mounted,
    " subscriptions=",
    subscriptions,
    " elapsed_us=",
    (getMonoTime() - started).inMicroseconds,
    " solver_views_max=",
    profile.solverViews,
    " solver_constraints_max=",
    profile.solverConstraints,
    " solver_passes=",
    profile.solverPasses,
    " layout_blocked=",
    root.blocked()
  for phase in ViewProfilePhase:
    let sample = profile.phases[phase]
    echo "  ",
      phase, " calls=", sample.calls, " inclusive_us=", sample.nanoseconds div 1000

proc run(count, height: int) =
  var items: seq[ModelItem]
  for index in 0 ..< count:
    items.add modelItem($index, title = "Row " & $index, objectValue = toObj($index))
  let controller = newArrayController(items)
  block materialized:
    resetViewProfile()
    let start = getMonoTime()
    let stack = newStackView(frame = rect(0, 0, 240, count.float32 * 30))
    var rows: seq[DirectView]
    for index in 0 ..< count:
      let row = newDirectView(frame = rect(0, 0, 240, 30))
      row.buildRow(controller, $index)
      stack.addArrangedSubview(row)
      rows.add row
    let scroll =
      newScrollView(frame = rect(0, 0, 240, height.float32), documentView = stack)
    discard buildRenders(scroll)
    report("materialized", "mount", count, height, rows.len, rows.len, start, scroll)
    resetViewProfile()
    let scrollStart = getMonoTime()
    scroll.contentOffset = initPoint(0, count.float32 * 15)
    discard buildRenders(scroll)
    report(
      "materialized", "scroll", count, height, rows.len, rows.len, scrollStart, scroll
    )
    for row in rows:
      row.clear()
  block virtualized:
    resetViewProfile()
    let start = getMonoTime()
    let collection = newCollectionView(frame = rect(0, 0, 240, height.float32))
    collection.collectionLayout = newCollectionViewLayout(
      clkList,
      itemSize = initSize(240, 30),
      minimumLineSpacing = 0,
      edgeInsets = insets(0),
    )
    let rows = newCollectionRows(collection, controller, buildRow)
    discard buildRenders(collection)
    let mounted = collection.visibleItemViews.len
    report(
      "virtualized", "mount", count, height, mounted, mounted + 3, start, collection
    )
    resetViewProfile()
    let scrollStart = getMonoTime()
    collection.scrollView.contentOffset = initPoint(0, count.float32 * 15)
    discard buildRenders(collection)
    doAssert collection.scrollView.contentOffset.y > 0
    doAssert not collection.itemViewAtIndex(count div 2).isNil
    let scrolled = collection.visibleItemViews.len
    report(
      "virtualized",
      "scroll",
      count,
      height,
      scrolled,
      scrolled + 3,
      scrollStart,
      collection,
    )
    rows.close()

when isMainModule:
  when not defined(merendaProfile):
    {.error: "compile this benchmark with -d:merendaProfile".}
  for height in [90, 180]:
    run(100, height)
    run(1000, height)
