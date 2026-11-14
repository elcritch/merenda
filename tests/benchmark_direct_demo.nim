## Measure the actual demo command path, including undo and queued preview work.
## -d:directDemoBaseline loads the committed pre-simplification demo, with the
## same natural StackView distribution as the current example.
import std/[macros, monotimes, times, os, strformat]

when defined(directDemoBaseline):
  macro previousDemo(): untyped =
    let source = staticExec("git show 1cfc3247:examples/direct_views_demo.nim")
    result = parseStmt(source)
    proc naturalStacks(node: NimNode) =
      if node.kind in {nnkCall, nnkCommand} and node.len > 1 and node[0].kind == nnkIdent and
          node[^1].kind == nnkStmtList and
          (node[0].eqIdent("VStack") or node[0].eqIdent("HStack")):
        node[^1].insert(0, parseStmt("this.distribution = svdNatural"))
      for child in node:
        naturalStacks(child)

    for node in result:
      if node.kind == nnkProcDef and node.name.eqIdent("runDirectViewsDemo"):
        node[0] = ident("newTaskController")
        node.params[0] = ident("TaskController")
        var body = newStmtList()
        for statement in node.body:
          if statement.kind == nnkDefer:
            break
          body.add statement
        body.add parseStmt("result = controller")
        node.body = body
      naturalStacks(node)
    # Drop only the executable entry point; preserve all application logic.
    result.del(result.len - 1)

  previousDemo()
else:
  include "../examples/direct_views_demo.nim"

import merenda/nimkit/foundation/mainthreadwork

proc flushWork() =
  var passes = 0
  while hasPendingMainThreadWork():
    discard drainMainThreadWork()
    inc passes
    doAssert passes < 100, "binding work did not settle"

proc measure(
    csv: File,
    count: int,
    name: string,
    iterations: int,
    controller: TaskController,
    operation: proc() {.closure.},
) =
  for _ in 0 ..< 2:
    operation()
    flushWork()
  for sample in 1 .. 5:
    let start = getMonoTime()
    for _ in 0 ..< iterations:
      operation()
    let us = (getMonoTime() - start).inNanoseconds.float64 / 1000 / iterations.float64
    csv.writeLine(&"{count},{name},{sample},{iterations},{us:.6f},ok")
    # Queue-only cases settle outside the measured interval.
    flushWork()
    controller.history.clearAll()
  csv.flushFile()

proc run(csv: File, count: int) =
  let controller = newTaskController()
  defer:
    when compiles(controller.bindings):
      controller.bindings.dispose()
    controller.rows.close()
    controller.chrome.close()
    flushWork()
  var tasks: TaskRows
  for id in 1 .. count:
    tasks.add TaskItem(id: id, title: "Task " & $id)
  controller.replaceTasks(tasks, "Populate")
  flushWork()
  controller.history.clearAll()
  var value = 0
  measure(
    csv,
    count,
    "counter_and_flush",
    1000,
    controller,
    proc() =
      inc value
      controller.counter <- value
      flushWork(),
  )
  measure(
    csv,
    count,
    "edit_command_only",
    100,
    controller,
    proc() =
      inc value
      controller.editTitle(1, "Edited " & $value),
  )
  measure(
    csv,
    count,
    "edit_and_preview_flush",
    2,
    controller,
    proc() =
      inc value
      controller.editTitle(1, "Edited " & $value)
      flushWork(),
  )
  measure(
    csv,
    count,
    "reverse_and_preview_flush",
    2,
    controller,
    proc() =
      controller.reverseTasks()
      flushWork(),
  )

proc main() =
  let path =
    if paramCount() == 0:
      "/tmp/direct-demo.csv"
    else:
      paramStr(1)
  let csv = open(path, fmWrite)
  defer:
    csv.close()
  csv.writeLine("rows,case,sample,iterations,us_per_op,status")
  for count in [3, 10, 100]:
    run(csv, count)

main()
