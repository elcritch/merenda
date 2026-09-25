## Repeatable editor workloads; timings are diagnostic rather than CI thresholds.
## Run: nim r tests/benchmark_tekton.nim
import std/[monotimes, strformat, times]
import merenda/nimkit
import merenda/tekton

proc measure(count: int) =
  var bundle = initResourceBundle("bench.tekton")
  var children: seq[ViewNodeResource]
  for index in 0 ..< count:
    children.add initViewNodeResource(
      resourceId("button." & $index),
      "button",
      [
        resourceProperty("title", resourceValue("Button " & $index)),
        resourceProperty("frame", resourceValue(rect(10, index.float32 * 35, 140, 30))),
      ],
    )
  bundle.views =
    @[
      initViewNodeResource(
        resourceId("root"),
        properties = [resourceProperty("frame", resourceValue(rect(0, 0, 600, 600)))],
        children = children,
      )
    ]
  let start = getMonoTime()
  let document = newResourceEditorDocument(bundle)
  let editor = newResourceEditor(document)
  let opened = getMonoTime()
  for index in 0 ..< 40:
    doAssert editor.selectResource(resourceId("button." & $(index mod count)))
  let selected = getMonoTime()
  for index in 0 ..< 10:
    doAssert editor.commitSelectedPropertyText("title", "Edited " & $index).edit.applied
  let edited = getMonoTime()
  for index in 0 ..< 40:
    editor.synchronize()
  let synchronized = getMonoTime()
  echo &"{count} widgets: open {(opened-start).inMicroseconds.float/1000:.2f} ms; " &
    &"select {(selected-opened).inMicroseconds.float/40000:.3f} ms/op; " &
    &"edit {(edited-selected).inMicroseconds.float/10000:.3f} ms/op; " &
    &"unchanged sync {(synchronized-edited).inMicroseconds.float/40000:.3f} ms/op"

measure(100)
measure(300)
