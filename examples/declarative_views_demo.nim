## Value descriptions with the same controller and keyed observations as direct_views_demo.
import sigils/[core, reactive]
import merenda/nimkit
import ./declarative_tasks

proc taskTitle(task: TaskItem, owner: TaskController): ViewSpec =
  result = textFieldSpec(
    task.title, identifier = "title-" & $task.id, sizing = svspFillAvailableWidth
  )
  if not owner.isNil:
    result.binding = viewBinding(
      owner,
      task.id,
      proc(scope: BindingScope, owner: TaskController, id: int, field: TextField) =
        scope.bindTextField(
          "title", owner.tasks.item(id), owner, id, titleFor, field, editTitle
        ),
      ownsText = true,
    )

proc taskRow(task: TaskItem, owner: TaskController): ViewSpec =
  viewBody:
    HStack(
      spacing = 10,
      padding = insets(10),
      identifier = "task-" & $task.id,
      draggable = true,
      background = color(0.16, 0.24, 0.32, 0.16),
    ):
      Label("#" & $task.id)
      taskTitle(task, owner)
      Button("Remove", focusable = false, identifier = "remove-" & $task.id):
        onAction(owner, task.id) do(
          receiver: TaskController, id: int, sender: DynamicAgent
        ):
          receiver.removeTask(id)

proc taskRows(tasks: TaskRows, owner: TaskController = nil): ViewSpec =
  viewBody:
    VStack(spacing = 10, alignment = svaFill, identifier = "tasks"):
      for task in tasks:
        keyed($task.id):
          taskRow(task, owner)
      if tasks.len == 0:
        Label("No tasks. Add one to continue.")

proc counterLabel(owner: TaskController): ViewSpec =
  result = labelSpec("", identifier = "counter-value")
  result.binding = viewBinding(
    owner,
    0,
    proc(scope: BindingScope, owner: TaskController, context: int, label: Label) =
      scope.bindValue("counter", owner.counter, label) do(label: Label, value: int):
        label.stringValue = "Unrelated counter: " & $value,
  )

proc statusLabel(owner: TaskController): ViewSpec =
  result = labelSpec("", style = lsStatus, identifier = "status")
  result.binding = viewBinding(
    owner,
    0,
    proc(scope: BindingScope, owner: TaskController, context: int, label: Label) =
      scope.bindValue("status", owner.status, label) do(label: Label, value: string):
        label.stringValue = value,
  )

proc liveBody(controller: TaskController, ids: seq[int]): ViewSpec =
  result = viewBody:
    VStack(spacing = 14, padding = insets(16)):
      Label("ViewSpec + MVC bindings", style = lsHeading)
      Label("Edit a title, then insert, reverse, undo or change the counter.")
      HStack:
        Button("Insert at top", focusable = false, identifier = "insert"):
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            receiver.insertTask()
        Button("Reverse", focusable = false, identifier = "reverse"):
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            receiver.reverseTasks()
        Button("Counter +1", focusable = false, identifier = "counter"):
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            receiver.counter <- receiver.counter{} + 1
        Button("Undo", focusable = false, identifier = "undo"):
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            discard receiver.history.performUndo()
        Button("Redo", focusable = false, identifier = "redo"):
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            discard receiver.history.performRedo()
      counterLabel(controller)
      taskRows(controller.tasks{}, controller)
      statusLabel(controller)
  result.binding = viewBinding(
    controller,
    0,
    proc(scope: BindingScope, owner: TaskController, context: int, view: StackView) =
      scope.bindPreview(owner),
  )

proc newTaskController(): TaskController =
  result = newTaskModelController()
  result.createPreview(
    proc(tasks: TaskRows, env: DragEnvironment): View =
      buildDetachedView(taskRows(tasks))
  )
  let live = newDeclarativeView(vstackSpec())
  live.bindBody(result.tasks.order, result, liveBody)
  result.setTaskDemoView(live)

proc runDeclarativeViewsDemo*() =
  let controller = newTaskController()
  sharedApplication().runWindow(
    newWindow("Declarative views: MVC and bindings", frame = rect(80, 80, 1240, 540)),
    controller.view,
  )

when isMainModule and not defined(merendaTests):
  runDeclarativeViewsDemo()
