## Measure synthetic input through a live native renderer, not display scanout.
## Build with -d:release.
import std/[monotimes, os, strutils, times]
import merenda/nimkit
import merenda/nimkit/directviews
import merenda/nimkit/app/backend
import ./intrinsic_collection_fixture

proc waitForRender(app: Application, window: Window, previous: Natural): bool =
  let deadline = getMonoTime() + initDuration(seconds = 10)
  while getMonoTime() < deadline:
    discard app.runForFrames(1)
    if window.nativeRenderCount() > previous and not window.needsDisplayUpdate() and
        not window.nativeRenderRequested():
      return true
    sleep(1)

let reverse = paramCount() > 0 and paramStr(1) == "reverse"
let policies =
  if reverse:
    [true, false]
  else:
    [false, true]
echo "cache,operation,sample,render_us,mounted"
for cache in policies:
  for operation in ["edit", "scroll"]:
    let app = newApplication("Intrinsic cache native benchmark")
    app.renderExecutionMode = remMainThread
    let demo = newIntrinsicCollectionFixture(5000, cache)
    let window = newWindow("Intrinsic cache benchmark", frame = rect(80, 80, 640, 480))
    window.setContentView(demo.view)
    app.addWindow(window)
    window.makeKeyAndOrderFront()
    doAssert app.waitForRender(window, 0), "initial render did not complete"
    let row = DirectView(demo.view.itemViewAtIndex(0))
    doAssert not row.isNil
    let field = TextField(StackView(row.arrangedSubviews[0]).arrangedSubviews[1])
    doAssert window.makeFirstResponder(field)
    for sample in 0 ..< 9:
      let before = window.nativeRenderCount()
      let started = getMonoTime()
      case operation
      of "edit":
        doAssert window.dispatchTextInput($sample)
      of "scroll":
        demo.view.scrollView.contentOffset =
          initPoint(0, if sample mod 2 == 0: 1200.0'f32 else: 0.0'f32)
      else:
        raise newException(ValueError, "unknown operation")
      doAssert app.waitForRender(window, before), "updated render did not complete"
      let elapsed = (getMonoTime() - started).inMicroseconds
      doAssert field.currentEditor != nil
      doAssert demo.view.itemViewAtIndex(0) == row
      if operation == "edit":
        doAssert field.stringValue.endsWith($sample)
      else:
        doAssert demo.view.scrollView.contentOffset.y ==
          (if sample mod 2 == 0: 1200.0'f32 else: 0.0'f32)
      if sample >= 2:
        echo cache,
          ",",
          operation,
          ",",
          sample - 1,
          ",",
          elapsed,
          ",",
          demo.view.visibleItemViews.len
    demo.rows.close()
    window.close()
