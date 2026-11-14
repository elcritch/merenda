## Identical acceptance checks for the two demo representations.
import std/[sequtils, unittest]
import sigils/[core, reactive]
import merenda/nimkit
import merenda/nimkit/foundation/mainthreadwork
import ../../examples/declarative_tasks

proc findDemoView(controller: TaskController, id: string): View =
  # Keep receiver temporaries inside this call, so teardown checks below do not
  # accidentally retain the complete root until the test's scope exits.
  controller.view.viewWithIdentifier(id)

template taskDemoChecks*(suiteName: string, factory: untyped) =
  suite suiteName:
    test "one commit path validates edits and restores structural and title changes":
      let controller = factory()
      controller.tasks <- @[
        TaskItem(id: 1, title: "One"), TaskItem(id: 2, title: "Two")
      ]
      controller.nextId = 3
      discard drainMainThreadWork()
      controller.history.clearAll()
      let field = TextField(controller.findDemoView("title-1"))
      let before = controller.tasks{}
      controller.editTitle(1, " ")
      check controller.tasks{} == before
      check not controller.history.canUndo
      controller.editTitle(1, "Edited")
      discard drainMainThreadWork()
      check field.stringValue == "Edited"
      controller.reverseTasks()
      discard drainMainThreadWork()
      check controller.findDemoView("title-1") == field
      check controller.tasks{}[1].id == 1
      check controller.history.performUndo()
      discard drainMainThreadWork()
      check controller.tasks{}[0].id == 1
      check controller.history.performUndo()
      discard drainMainThreadWork()
      check controller.tasks{} == before
      check field.stringValue == "One"
      check controller.history.performRedo()
      discard drainMainThreadWork()
      check field.stringValue == "Edited"
      controller.counter <- 2
      discard drainMainThreadWork()
      check Label(controller.findDemoView("counter-value")).stringValue ==
        "Unrelated counter: 2"
      check controller.findDemoView("title-1") == field
      check field.stringValue == "Edited"
      controller.insertTask()
      discard drainMainThreadWork()
      check controller.tasks{}[0].id == 3
      controller.removeTask(3)
      discard drainMainThreadWork()
      check controller.tasks{}.mapIt(it.id) == @[1, 2]

    test "Sigil snapshots coalesce previews and title edits leave row structure alone":
      let controller = factory()
      let original = controller.tasks{}
      let row = controller.findDemoView("task-1")
      let field = TextField(controller.findDemoView("title-1"))
      let localColor = color(0.9, 0.1, 0.2, 1)
      row.backgroundColor = localColor
      controller.editTitle(1, "First edit")
      controller.editTitle(1, "Second edit")
      check controller.preview.model == original
      discard drainMainThreadWork()
      check controller.preview.model == controller.tasks{}
      check field.stringValue == "Second edit"
      # The row body would restore its declared background if it had rerun.
      check row.backgroundColor == localColor
      controller.counter <- 42
      discard drainMainThreadWork()
      check controller.preview.model == controller.tasks{}
      check row.backgroundColor == localColor
      controller.setView(nil)
      check controller.tasks.subcriptions.len == 0
      check controller.counter.subcriptions.len == 0
