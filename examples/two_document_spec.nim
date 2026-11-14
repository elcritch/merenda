## The same two independent task editors using ViewSpec.
import std/options
import sigils/[core, reactive]
import merenda/nimkit
import merenda/nimkit/responder/guardedcommands
import ./two_document_tasks

proc taskRow(task: EditorTask, owner: EditorController): ViewSpec =
  var field = textFieldSpec(
    task.title, identifier = "title-" & $task.id, sizing = svspFillAvailableWidth
  )
  field.binding = viewBinding(
    owner,
    (owner.generation, task.id),
    proc(
        scope: BindingScope,
        owner: EditorController,
        context: EditorContext,
        field: TextField,
    ) =
      scope.bindTextField(
        "title",
        owner.tasks.item(context.id),
        owner,
        context,
        taskTitle,
        field,
        editTask,
      ),
    ownsText = true,
  )
  var accepted = labelSpec("", identifier = "accepted-" & $task.id)
  accepted.binding = viewBinding(
    owner,
    task.id,
    proc(scope: BindingScope, owner: EditorController, id: int, label: Label) =
      scope.bindValue("accepted", owner.tasks.item(id), label) do(
        label: Label, value: Option[EditorTask]
      ):
        label.stringValue = "Accepted: " & (if value.isSome: value.get.title else: ""),
  )
  result = viewBody:
    HStack(spacing = 8, identifier = "row-" & $task.id):
      field
      accepted
      Button("Validate", focusable = false, identifier = "validate-" & $task.id):
        onAction(owner, owner.taskCommand(task.id)) do(
          receiver: EditorController, command: EditorTaskCommand, sender: DynamicAgent
        ):
          command.perform(validateTaskCommand)
      Button("Remove", focusable = false, identifier = "remove-" & $task.id):
        onAction(owner, owner.taskCommand(task.id)) do(
          receiver: EditorController, command: EditorTaskCommand, sender: DynamicAgent
        ):
          command.perform(removeTaskCommand)

proc statusLabel(owner: EditorController): ViewSpec =
  result = labelSpec("", identifier = "status")
  result.binding = viewBinding(
    owner,
    0,
    proc(scope: BindingScope, owner: EditorController, context: int, label: Label) =
      scope.bindValue("status", owner.status, label) do(label: Label, value: string):
        label.stringValue = value,
  )

proc documentLabel(owner: EditorController): ViewSpec =
  result = labelSpec("", identifier = "document")
  result.binding = viewBinding(
    owner,
    0,
    proc(scope: BindingScope, owner: EditorController, context: int, label: Label) =
      scope.bindValue("document", owner.documentLabel, label) do(
        label: Label, value: string
      ):
        label.stringValue = value,
  )

proc editorBody(owner: EditorController, state: EditorStructure): ViewSpec =
  result = viewBody:
    VStack(spacing = 8, padding = insets(12)):
      documentLabel(owner)
      HStack:
        Button("Reverse", focusable = false):
          onAction(owner) do(receiver: EditorController, sender: DynamicAgent):
            receiver.reverseTasks()
        Button("Restore #1", focusable = false):
          onAction(owner) do(receiver: EditorController, sender: DynamicAgent):
            receiver.restoreTask(1)
        Button("Undo", focusable = false):
          onAction(owner) do(receiver: EditorController, sender: DynamicAgent):
            receiver.undo()
      HStack:
        Button("Complete queued", focusable = false, identifier = "complete"):
          onAction(owner) do(receiver: EditorController, sender: DynamicAgent):
            receiver.queue.flushValidation()
        Button("Switch document", focusable = false):
          onAction(owner) do(receiver: EditorController, sender: DynamicAgent):
            receiver.switchDocument()
        Button("Close", focusable = false):
          onAction(owner) do(receiver: EditorController, sender: DynamicAgent):
            receiver.closeDocument()
      VStack(identifier = "rows"):
        for task in (if owner.closed: @[] else: owner.tasks{}):
          keyed($state.generation & ":" & $task.id):
            taskRow(task, owner)
      statusLabel(owner)

proc newSpecEditor*(owner: EditorController, queue: ValidationQueue): DeclarativeView =
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
  result = newDeclarativeView(vstackSpec())
  result.bindBody(owner.structure, owner, editorBody)

proc runTwoDocumentSpec*() =
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
  root.addArrangedSubview(newSpecEditor(first, queue), newSpecEditor(second, queue))
  sharedApplication().runWindow(
    newWindow("Two documents: ViewSpec", frame = rect(80, 80, 1300, 600)), root
  )

when isMainModule and not defined(merendaTests):
  runTwoDocumentSpec()
