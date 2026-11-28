import std/[monotimes, os, times, unittest]
import sigils/[core, reactive]
import merenda/foundation/backrefs
import merenda/nimkit
import merenda/nimkit/directviews
import merenda/foundation/mainthreadwork
import ../../examples/[two_document_tasks, two_document_direct]

template waitUntil(condition: untyped) =
  block:
    let deadline = getMonoTime() + initDuration(seconds = 5)
    while not (condition) and getMonoTime() < deadline:
      discard drainMainThreadWork()
      sleep(1)
    check condition

template editorChecks(name: string, factory: untyped) =
  suite name:
    test "independent editors preserve keyed editing and controller drafts":
      let queue = newValidationQueue()
      let first = newEditorController(
        1, @[EditorTask(id: 1, title: "First"), EditorTask(id: 2, title: "Second")]
      )
      let second = newEditorController(
        2, @[EditorTask(id: 1, title: "Other"), EditorTask(id: 2, title: "Task")]
      )
      let left = factory(first, queue)
      let right = factory(second, queue)
      let root = newStackView(laHorizontal)
      root.addArrangedSubview(left, right)
      let window = newWindow("Two editors", frame = rect(0, 0, 800, 400))
      window.setContentView(root)
      defer:
        left.clear()
        right.clear()
        window.close()
      require first.tasks.order.subcriptions.len > 0
      require second.tasks.order.subcriptions.len > 0
      require first.tasks.item(1).subcriptions.len > 0
      require second.tasks.item(1).subcriptions.len > 0
      let field = TextField(left.viewWithIdentifier("title-1"))
      let other = TextField(right.viewWithIdentifier("title-1"))
      let otherRow = right.viewWithIdentifier("row-1")
      let color = color(0.8, 0.2, 0.1, 1)
      otherRow.backgroundColor = color
      first.editTask(1, "Draft")
      waitUntil(field.stringValue == "Draft")
      check other.stringValue == "Other"
      check otherRow.backgroundColor == color
      check not second.history.canUndo
      check first.tasks[1].title == "First"
      let validate = Button(left.viewWithIdentifier("validate-1"))
      let complete = Button(left.viewWithIdentifier("complete"))
      discard validate.send(performClick(), ActionArgs(sender: validate))
      check queue.pendingCount == 1
      discard complete.send(performClick(), ActionArgs(sender: complete))
      check first.tasks[1].title == "Draft"
      waitUntil(
        Label(left.viewWithIdentifier("accepted-1")).stringValue == "Accepted: Draft"
      )
      check first.history.canUndo
      check first.history.performUndo()
      check first.tasks[1].title == "First"
      check first.taskTitle(1) == "Draft"
      waitUntil(
        Label(left.viewWithIdentifier("accepted-1")).stringValue == "Accepted: First"
      )
      require window.makeFirstResponder(field)
      let editor = TextView(field.currentEditor)
      editor.selectedRange = initTextRange(1, 2)
      editor.setMarkedTextValue("xy", initTextRange(1, 0), initTextRange(-1, 0))
      require editor.hasMarkedText
      let marked = editor.markedRange
      let selection = editor.selectedRange
      first.reverseTasks()
      waitUntil(
        StackView(left.viewWithIdentifier("rows")).arrangedSubviews[1].identifier ==
          "row-1"
      )
      check left.viewWithIdentifier("title-1") == field
      check field.currentEditor == editor
      check editor.markedRange == marked
      check editor.selectedRange == selection
      check otherRow.backgroundColor == color
      let draftBeforeRemoval = first.taskTitle(1)
      first.removeTask(1)
      waitUntil(left.viewWithIdentifier("title-1").isNil)
      first.restoreTask(1)
      waitUntil(not left.viewWithIdentifier("title-1").isNil)
      check TextField(left.viewWithIdentifier("title-1")).stringValue ==
        draftBeforeRemoval
      check left.viewWithIdentifier("title-1") != field
      check first.history.performUndo()
      check second.taskTitle(1) == "Other"

    test "queued delivery rejects edits, switches, close and same-id reopen":
      let queue = newValidationQueue()
      let first = newEditorController(1, @[EditorTask(id: 1, title: "One")])
      let second = newEditorController(2, @[EditorTask(id: 1, title: "Two")])
      let left = factory(first, queue)
      let right = factory(second, queue)
      defer:
        left.clear()
        right.clear()
      require first.status.subcriptions.len > 0
      require second.status.subcriptions.len > 0
      queue.queueValidation(first, 1)
      first.editTask(1, "New")
      queue.queueValidation(first, 1)
      queue.queueValidation(second, 1)
      check queue.pendingCount == 3
      let original = first.document
      let switched = newEditorDocument(3, @[EditorTask(id: 1, title: "Switched")])
      let oldField = TextField(left.viewWithIdentifier("title-1"))
      let oldButton = Button(left.viewWithIdentifier("remove-1"))
      let oldValidate = Button(left.viewWithIdentifier("validate-1"))
      first.bindDocument(switched)
      oldField.stringValue = "Stale edit"
      emit oldField.textDidChange(DynamicAgent(oldField))
      discard oldButton.send(performClick(), ActionArgs(sender: oldButton))
      discard oldValidate.send(performClick(), ActionArgs(sender: oldValidate))
      check queue.pendingCount == 3
      check first.taskTitle(1) == "Switched"
      check first.tasks[1].title == "Switched"
      queue.flushValidation()
      check queue.completed == 3
      check queue.applied == 1
      waitUntil(
        Label(right.viewWithIdentifier("status")).stringValue == "Title is valid"
      )
      check first.status{} == "Ready"
      first.bindDocument(original)
      check first.taskTitle(1) == "New"
      first.bindDocument(switched)
      queue.queueValidation(first, 1)
      first.closeDocument()
      check switched.isClosed
      let closedTasks = switched.tasks{}
      switched.replaceTasks(@[], "Ignored after close")
      check switched.tasks{} == closedTasks
      let reopened = newEditorDocument(3, @[EditorTask(id: 1, title: "Reopened")])
      first.bindDocument(reopened)
      queue.flushValidation()
      check queue.completed == 4
      check queue.applied == 1
      check first.status{} == "Ready"
      waitUntil(TextField(left.viewWithIdentifier("title-1")).stringValue == "Reopened")
      oldField.stringValue = "Another stale edit"
      emit oldField.textDidChange(DynamicAgent(oldField))
      discard oldButton.send(performClick(), ActionArgs(sender: oldButton))
      check first.taskTitle(1) == "Reopened"
      queue.queueValidation(first, 1)
      first.editTask(1, " ")
      queue.flushValidation()
      check queue.applied == 1
      queue.queueValidation(first, 1)
      queue.flushValidation()
      check queue.applied == 2
      check first.tasks[1].title == "Reopened"
      waitUntil(
        Label(left.viewWithIdentifier("status")).stringValue == "Title is blank"
      )
      let retained = Button(left.viewWithIdentifier("remove-1"))
      queue.queueValidation(first, 1)
      first.detachEditor()
      discard retained.send(performClick(), ActionArgs(sender: retained))
      check 1 in first.tasks
      left.clear()
      discard retained.send(performClick(), ActionArgs(sender: retained))
      check 1 in first.tasks
      first.detachEditor()
      queue.flushValidation()
      check queue.applied == 2

    test "removed row actions are ignored before redraw":
      let queue = newValidationQueue()
      let owner = newEditorController(1, @[EditorTask(id: 1, title: "One")])
      let host = factory(owner, queue)
      defer:
        host.clear()
      let remove = Button(host.viewWithIdentifier("remove-1"))
      let validate = Button(host.viewWithIdentifier("validate-1"))
      owner.removeTask(1)
      let revision = owner.document.revision
      discard remove.send(performClick(), ActionArgs(sender: remove))
      discard validate.send(performClick(), ActionArgs(sender: validate))
      check owner.document.revision == revision
      check queue.pendingCount == 0
      check 1 notin owner.tasks

    test "switching to a closed document leaves the current editor active":
      let queue = newValidationQueue()
      let owner = newEditorController(1, @[EditorTask(id: 1, title: "First")])
      let host = factory(owner, queue)
      defer:
        host.clear()
      let closed = owner.document
      owner.switchDocument()
      waitUntil(
        TextField(host.viewWithIdentifier("title-1")).stringValue == "Another document"
      )
      discard closed.close()
      let generation = owner.generation
      owner.switchDocument()
      check owner.generation == generation
      check owner.alternate == closed
      let field = TextField(host.viewWithIdentifier("title-1"))
      field.stringValue = "Still active"
      emit field.textDidChange(DynamicAgent(field))
      check owner.taskTitle(1) == "Still active"

    test "document undo survives replacement of its editor controller":
      let queue = newValidationQueue()
      let doc = newEditorDocument(7, @[EditorTask(id: 1, title: "Original")])
      var owner = newEditorController(doc)
      owner.editTask(1, "Accepted")
      queue.queueValidation(owner, 1)
      queue.flushValidation()
      check doc.tasks[1].title == "Accepted"
      owner = nil
      let replacement = newEditorController(doc)
      replacement.undo()
      check doc.tasks[1].title == "Original"
      check replacement.taskTitle(1) == "Accepted"

    test "pending validation does not retain a retired controller":
      let queue = newValidationQueue()
      var owner = newEditorController(9, @[EditorTask(id: 1, title: "Temporary")])
      var weak: BackRef[EditorController]
      weak.target = owner
      let host = factory(owner, queue)
      let retained = Button(host.viewWithIdentifier("validate-1"))
      queue.queueValidation(owner, 1)
      host.clear()
      owner = nil
      check weak.isNil
      discard retained.send(performClick(), ActionArgs(sender: retained))
      check queue.pendingCount == 1
      queue.flushValidation()
      check queue.completed == 1
      check queue.applied == 0

editorChecks("two document editors: direct", newDirectEditor)
