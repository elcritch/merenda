## Two independent task editors using direct views and the shared document policy.
import std/options
import sigils/[core, reactive]
import merenda/nimkit
import merenda/nimkit/responder/guardedcommands
import ./two_document_tasks

proc taskRow(context: DirectNode, task: EditorTask, owner: EditorController) =
  context.viewBody:
    HStack:
      this.distribution = svdNatural
      this.identifier = "row-" & $task.id
      this.spacing = 8
      TextField:
        this.identifier = "title-" & $task.id
        arrangedSizing(svspFillAvailableWidth)
        bindingScope.bindTextField(
          "title",
          owner.tasks.item(task.id),
          owner,
          (owner.generation, task.id),
          taskTitle,
          this,
          editTask,
        )
      Label:
        this.identifier = "accepted-" & $task.id
        bindingScope.bindValue("accepted", owner.tasks.item(task.id), this) do(
          label: Label, value: Option[EditorTask]
        ):
          label.stringValue = "Accepted: " & (if value.isSome: value.get.title else: "")
      Button(
        "Validate", identifier = "validate-" & $task.id, acceptsFirstResponder = false
      ):
        onAction(owner, owner.taskCommand(task.id)) do(
          receiver: EditorController, command: EditorTaskCommand, sender: DynamicAgent
        ):
          command.perform(validateTaskCommand)
      Button("Remove", identifier = "remove-" & $task.id, acceptsFirstResponder = false):
        onAction(owner, owner.taskCommand(task.id)) do(
          receiver: EditorController, command: EditorTaskCommand, sender: DynamicAgent
        ):
          command.perform(removeTaskCommand)

proc rows(context: DirectNode, owner: EditorController, state: EditorStructure) =
  context.viewBody:
    VStack:
      this.identifier = "rows"
      this.distribution = svdNatural
      for task in (if owner.closed: @[] else: owner.tasks{}):
        keyed($state.generation & ":" & $task.id):
          component(taskRow, task, owner)

proc observedRows(context: DirectNode, owner: EditorController) =
  context.bindBody(owner.structure, owner, rows)

proc newDirectEditor*(owner: EditorController, queue: ValidationQueue): DirectView =
  owner.queue = queue
  if owner.alternate.isNil:
    owner.alternate = newEditorDocument(
      owner.documentId + 10,
      @[
        EditorTask(id: 1, title: "Another document"),
        EditorTask(id: 2, title: "Reorder this task"),
        EditorTask(id: 3, title: "Independent drafts"),
      ],
    )
  result = newDirectView()
  result.viewBody:
    VStack:
      this.spacing = 8
      this.distribution = svdNatural
      this.edgeInsets = insets(12)
      Label:
        this.identifier = "document"
        bindingScope.bindValue("document", owner.documentLabel, this) do(
          label: Label, value: string
        ):
          label.stringValue = value
      HStack:
        this.distribution = svdNatural
        Button("Reverse", acceptsFirstResponder = false):
          onAction(owner) do(receiver: EditorController, sender: DynamicAgent):
            receiver.reverseTasks()
        Button("Restore #1", acceptsFirstResponder = false):
          onAction(owner) do(receiver: EditorController, sender: DynamicAgent):
            receiver.restoreTask(1)
        Button("Undo", acceptsFirstResponder = false):
          onAction(owner) do(receiver: EditorController, sender: DynamicAgent):
            receiver.undo()
      HStack:
        this.distribution = svdNatural
        Button(
          "Complete queued", identifier = "complete", acceptsFirstResponder = false
        ):
          onAction(owner) do(receiver: EditorController, sender: DynamicAgent):
            receiver.queue.flushValidation()
        Button("Switch document", acceptsFirstResponder = false):
          onAction(owner) do(receiver: EditorController, sender: DynamicAgent):
            receiver.switchDocument()
        Button("Close", acceptsFirstResponder = false):
          onAction(owner) do(receiver: EditorController, sender: DynamicAgent):
            receiver.closeDocument()
      component(observedRows, owner)
      Label:
        this.identifier = "status"
        bindingScope.bindValue("status", owner.status, this) do(
          label: Label, value: string
        ):
          label.stringValue = value

proc runTwoDocumentDirect*() =
  let queue = newValidationQueue()
  let first = newEditorController(
    1,
    @[
      EditorTask(id: 1, title: "First document"),
      EditorTask(id: 2, title: "Move me"),
      EditorTask(id: 3, title: "Another task"),
    ],
  )
  let second = newEditorController(
    2,
    @[
      EditorTask(id: 1, title: "Second document"),
      EditorTask(id: 2, title: "Move me too"),
      EditorTask(id: 3, title: "Another task"),
    ],
  )
  let root = newStackView(laHorizontal)
  root.distribution = svdFillEqually
  root.addArrangedSubview(newDirectEditor(first, queue), newDirectEditor(second, queue))
  sharedApplication().runWindow(
    newWindow("Two documents: direct views", frame = rect(80, 80, 1300, 600)), root
  )

when isMainModule and not defined(merendaTests):
  runTwoDocumentDirect()
