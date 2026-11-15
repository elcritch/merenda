## Compare intrinsic reuse in the editable virtualized collection demo.
import std/[monotimes, times]
import merenda/nimkit
import merenda/nimkit/directviews
import merenda/nimkit/foundation/viewprofiling
import ./intrinsic_collection_fixture

for cache in [false, true]:
  let demo = newIntrinsicCollectionFixture(5000, cache)
  let controller = ArrayController(demo.view.dataSource())
  discard buildRenders(demo.view)
  for operation in ["edit", "scroll", "insert", "reorder", "resize"]:
    for sample in 0 ..< 7:
      resetViewProfile()
      let start = getMonoTime()
      case operation
      of "edit":
        controller.setValue("0", "title", toObj("Edited " & $sample))
      of "scroll":
        demo.view.scrollView.contentOffset = initPoint(0, (sample mod 2).float32 * 1200)
      of "insert":
        controller.insertItem(
          modelItem("new-" & $sample, fields = [modelField("title", toObj("New"))]), 0
        )
      of "reorder":
        discard controller.moveItem("0", sample mod 2)
      of "resize":
        demo.view.frame = rect(0, 0, 640 - (sample mod 2).float32 * 40, 480)
      else:
        discard
      demo.rows.flushBindings()
      discard buildRenders(demo.view)
      if sample >= 2:
        let profile = currentViewProfile()
        echo cache,
          ",",
          operation,
          ",",
          sample,
          ",",
          (getMonoTime() - start).inMicroseconds,
          ",",
          demo.view.visibleItemViews.len,
          ",",
          profile.solverViews,
          ",",
          profile.solverPasses
  demo.rows.close()
