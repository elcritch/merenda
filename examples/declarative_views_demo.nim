## Evaluation: edit a task while inserting/reordering rows and changing a counter.
## The same row descriptions also produce effect-free Dragology previews.
import std/[algorithm, strutils]
import merenda/nimkit

type
  TaskItem = object
    id: int
    title: string

  TaskModel = object
    tasks: seq[TaskItem]
    counter, nextId: int
    lastAction: string

  TaskController = ref object of ViewController
    model: TaskModel
    live: DeclarativeView
    preview: DeclarativeDragView[TaskModel]

proc refresh(controller: TaskController, updatePreview = true)

proc taskRow(task: TaskItem, owner: TaskController): ViewSpec =
  let id = task.id
  viewBody:
    HStack(
      spacing = 10,
      padding = insets(10),
      identifier = "task-" & $id,
      draggable = true,
      background = color(0.16, 0.24, 0.32, 0.16),
    ):
      Label("#" & $id)
      TextField(
        task.title, identifier = "title-" & $id, sizing = svspFillAvailableWidth
      ):
        onChange(owner, id) do(
          controller: TaskController, id: int, sender: DynamicAgent
        ):
          for item in controller.model.tasks.mitems:
            if item.id == id:
              item.title = TextField(sender).stringValue
              break
          controller.refresh()
      Button("Remove", focusable = false, identifier = "remove-" & $id):
        onAction(owner, id) do(
          controller: TaskController, id: int, sender: DynamicAgent
        ):
          for i, item in controller.model.tasks:
            if item.id == id:
              controller.model.tasks.delete(i)
              break
          controller.model.lastAction = "Removed task " & $id
          controller.refresh()

proc taskRows(model: TaskModel, owner: TaskController = nil): ViewSpec =
  viewBody:
    VStack(spacing = 10, alignment = svaFill, identifier = "tasks"):
      for task in model.tasks:
        keyed($task.id):
          taskRow(task, owner)
      if model.tasks.len == 0:
        Label("No tasks. Add one to continue.")

proc liveBody(controller: TaskController): ViewSpec =
  viewBody:
    VStack(spacing = 14, padding = insets(16)):
      Label("Live editable list", style = lsHeading)
      Label("Edit a title, select text, then use these buttons.")
      HStack:
        Button("Insert at top", focusable = false, identifier = "insert"):
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            let id = receiver.model.nextId
            inc receiver.model.nextId
            receiver.model.tasks.insert(TaskItem(id: id, title: "New task " & $id), 0)
            receiver.model.lastAction = "Inserted task " & $id & " at the top"
            receiver.refresh()
        Button("Reverse", focusable = false, identifier = "reverse"):
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            receiver.model.tasks.reverse()
            receiver.model.lastAction = "Reversed the task order"
            receiver.refresh()
        Button("Counter +1", focusable = false, identifier = "counter"):
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            inc receiver.model.counter
            receiver.refresh()
      Label("Unrelated counter: " & $controller.model.counter)
      taskRows(controller.model, controller)
      Label(controller.model.lastAction, style = lsStatus)

proc refresh(controller: TaskController, updatePreview = true) =
  controller.live.update(controller.liveBody())
  if updatePreview and not controller.preview.isNil:
    controller.preview.model = controller.model

proc nextModels(model: TaskModel, id: string): seq[TaskModel] =
  let taskId = parseInt(id[5 .. ^1])
  var remaining = model
  var task: TaskItem
  for i, item in remaining.tasks:
    if item.id == taskId:
      task = item
      remaining.tasks.delete(i)
      break
  for i in 0 .. remaining.tasks.len:
    var next = remaining
    next.tasks.insert(task, i)
    next.lastAction = "Dragged task " & $taskId
    result.add next

proc runDeclarativeViewsDemo*() =
  let controller = TaskController(
    model: TaskModel(
      tasks: @[
        TaskItem(id: 1, title: "Keep my editing session"),
        TaskItem(id: 2, title: "Insert and reorder around me"),
        TaskItem(id: 3, title: "Callbacks follow task identity"),
      ],
      nextId: 4,
      lastAction: "Select text in a row to start.",
    )
  )
  initViewController(controller)
  controller.live = newDeclarativeView(controller.liveBody())
  var owner: BackRef[TaskController]
  owner.target = controller
  controller.preview = newDeclarativeDragView(
    controller.model,
    build = proc(model: TaskModel, env: DragEnvironment): View =
      buildDetachedView(taskRows(model)),
    successors = nextModels,
    commit = proc(previous, next: TaskModel): bool =
      let receiver = owner.target
      if not receiver.isNil:
        receiver.model = next
        receiver.refresh(updatePreview = false)
        result = true
    ,
    frame = rect(0, 0, 470, 330),
  )
  controller.preview.autoresizingMaskConstraints = false
  let right = newStackView(laVertical)
  right.spacing = 14
  right.distribution = svdNatural
  right.edgeInsets = insets(16)
  right.addArrangedSubview(newHeadingLabel("Dragology preview"))
  right.addArrangedSubview(newLabel("Drag a card here to reorder the live list."))
  right.addArrangedSubview(
    newLabel("Same description; event callbacks are not installed.")
  )
  right.addArrangedSubview(controller.preview)
  let root = newStackView(laHorizontal)
  root.alignment = svaFill
  root.distribution = svdFillEqually
  root.addArrangedSubview(controller.live, right)
  controller.setView(root)
  defer:
    controller.live.clear()
  sharedApplication().runWindow(
    newWindow(
      "Declarative views: identity and previews", frame = rect(80, 80, 1100, 540)
    ),
    root,
  )

when isMainModule:
  runDeclarativeViewsDemo()
