## Domain and controller policy for the direct-view task demo.
import std/[algorithm, strutils]
import sigils/[core, reactive]
import merenda/foundation/backrefs
import merenda/nimkit

type
  TaskItem* = object
    id*: int
    title*: string

  TaskRows* = seq[TaskItem]
  TaskController* = ref object of ViewController
    tasks*: CollectionSigil[int, TaskItem]
    nextId*: int
    counter*: Sigil[int]
    status*: Sigil[string]
    history*: UndoManager
    preview*: DeclarativeDragView[TaskRows]

proc taskId*(task: TaskItem): int =
  task.id

proc replaceTasks*(controller: TaskController, next: TaskRows, action: string) =
  let previous = controller.tasks{}
  if previous == next:
    return
  # Collection validation happens before publication; a rejected snapshot must
  # not enter undo history. View observations schedule their work for later.
  controller.tasks <- next
  var owner: BackRef[TaskController]
  owner.target = controller
  controller.history.registerValueChange(
    proc(previous: TaskRows) =
      let receiver = owner{}
      if not receiver.isNil:
        receiver.replaceTasks(previous, action)
    ,
    previous,
    action,
  )
  controller.status <- action

proc titleFor*(controller: TaskController, id: int): string =
  if id in controller.tasks:
    result = controller.tasks[id].title

proc editTitle*(controller: TaskController, id: int, text: string) =
  if text.strip.len == 0:
    controller.status <- "A task title cannot be blank. Undo or keep typing."
    return
  var next = controller.tasks{}
  for task in next.mitems:
    if task.id == id:
      task.title = text
      controller.replaceTasks(next, "Edit task " & $id)
      return

proc insertTask*(controller: TaskController) =
  let id = controller.nextId
  inc controller.nextId
  var next = controller.tasks{}
  next.insert(TaskItem(id: id, title: "New task " & $id), 0)
  controller.replaceTasks(next, "Inserted task " & $id)

proc reverseTasks*(controller: TaskController) =
  var next = controller.tasks{}
  next.reverse()
  controller.replaceTasks(next, "Reversed the task order")

proc removeTask*(controller: TaskController, id: int) =
  var next = controller.tasks{}
  for i, task in next:
    if task.id == id:
      next.delete(i)
      controller.replaceTasks(next, "Removed task " & $id)
      return

proc successors*(tasks: TaskRows, id: string): seq[TaskRows] =
  let taskId = parseInt(id[5 .. ^1])
  var remaining = tasks
  var dragged: TaskItem
  for i, task in remaining:
    if task.id == taskId:
      dragged = task
      remaining.delete(i)
      break
  for i in 0 .. remaining.len:
    var next = remaining
    next.insert(dragged, i)
    result.add next

proc acceptTasksProposal*(controller: TaskController, previous, next: TaskRows): bool =
  ## Drag proposals cannot overwrite edits made since their snapshot.
  if controller.tasks{} == previous:
    controller.replaceTasks(next, "Dragged a task")
    result = true

proc newTaskModelController*(): TaskController =
  result = TaskController(
    tasks: newCollectionSigil(
      @[
        TaskItem(id: 1, title: "Keep my editing session"),
        TaskItem(id: 2, title: "Insert and reorder around me"),
        TaskItem(id: 3, title: "Commands follow task identity"),
      ],
      taskId,
    ),
    nextId: 4,
    counter: newSigil(0),
    status: newSigil("Select text in a row to start."),
    history: newUndoManager(),
  )
  initViewController(result)

proc createPreview*(
    controller: TaskController,
    build: proc(tasks: TaskRows, env: DragEnvironment): View {.closure.},
) =
  var owner: BackRef[TaskController]
  owner.target = controller
  controller.preview = newDeclarativeDragView(
    controller.tasks{},
    build = build,
    successors = successors,
    commit = proc(previous, next: TaskRows): bool =
      let receiver = owner{}
      if not receiver.isNil:
        result = receiver.acceptTasksProposal(previous, next)
    ,
    frame = rect(0, 0, 470, 330),
  )

proc bindPreview*[B: BindingScope | View](owner: B, controller: TaskController) =
  mixin bindValue
  if not controller.preview.isNil:
    owner.bindValue("preview", controller.tasks, controller.preview) do(
      preview: DeclarativeDragView[TaskRows], value: TaskRows
    ):
      if preview.model != value:
        preview.model = value

proc setTaskDemoView*(controller: TaskController, live: View) =
  controller.preview.autoresizingMaskConstraints = false
  let right = newStackView()
  right.spacing = 14
  right.distribution = svdNatural
  right.edgeInsets = insets(16)
  right.addArrangedSubview(newHeadingLabel("Dragology preview"))
  right.addArrangedSubview(newLabel("Drag a card here to reorder the live list."))
  right.addArrangedSubview(
    newLabel("Same row builder; fresh widgets, no live bindings.")
  )
  right.addArrangedSubview(controller.preview)
  let root = newStackView(laHorizontal)
  root.alignment = svaFill
  root.distribution = svdFillEqually
  root.addArrangedSubview(live, right)
  controller.setView(root)
