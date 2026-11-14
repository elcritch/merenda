## P7 evaluation: retained actual views, controller commands and owned bindings.
## Compare with declarative_views_demo.nim, which builds ViewSpec values.
import std/[algorithm, strutils]
import sigils/[core, reactive]
import merenda/nimkit

type
  TaskItem = object
    id: int
    title: string

  TaskRows = seq[TaskItem]

  TaskController = ref object of ViewController
    tasks: TaskRows
    nextId: int
    counter: Sigil[int]
    status: Sigil[string]
    history: UndoManager
    bindings: BindingScope
    chrome, rows: DirectViewSession
    preview: DeclarativeDragView[TaskRows]

proc rowsChanged(controller: TaskController) {.signal.}
proc titlesChanged(controller: TaskController) {.signal.}
proc snapshotChanged(controller: TaskController) {.signal.}

proc replaceTasks(controller: TaskController, next: TaskRows, action: string)
proc editTitle(controller: TaskController, id: int, text: string)

proc recordTasks(controller: TaskController, action: string) =
  var owner: BackRef[TaskController]
  owner.target = controller
  controller.history.registerValueChange(
    proc(previous: TaskRows) =
      let receiver = owner.target
      if not receiver.isNil:
        receiver.replaceTasks(previous, action)
    ,
    controller.tasks,
    action,
  )

proc replaceTasks(controller: TaskController, next: TaskRows, action: string) =
  if controller.tasks == next:
    return
  controller.recordTasks(action)
  controller.tasks = next
  controller.status <- action
  emit controller.rowsChanged()
  emit controller.titlesChanged()
  emit controller.snapshotChanged()

proc titleFor(controller: TaskController, id: int): string =
  for task in controller.tasks:
    if task.id == id:
      return task.title

proc editTitle(controller: TaskController, id: int, text: string) =
  # Validation is controller policy. Invalid text remains provisional in the
  # editor; other bindings must not erase it on an unrelated notification.
  if text.strip.len == 0:
    controller.status <- "A task title cannot be blank. Undo or keep typing."
    return
  for task in controller.tasks.mitems:
    if task.id == id and task.title != text:
      controller.recordTasks("Edit task " & $id)
      task.title = text
      controller.status <- "Edited task " & $id
      emit controller.titlesChanged()
      emit controller.snapshotChanged()
      return

proc insertTask(controller: TaskController) =
  let id = controller.nextId
  inc controller.nextId
  var next = controller.tasks
  next.insert(TaskItem(id: id, title: "New task " & $id), 0)
  controller.replaceTasks(next, "Inserted task " & $id)

proc reverseTasks(controller: TaskController) =
  var next = controller.tasks
  next.reverse()
  controller.replaceTasks(next, "Reversed the task order")

proc removeTask(controller: TaskController, id: int) =
  var next = controller.tasks
  for i, task in next:
    if task.id == id:
      next.delete(i)
      controller.replaceTasks(next, "Removed task " & $id)
      return

proc taskRows(
    session: DirectViewSession, tasks: TaskRows, owner: TaskController = nil
) =
  session.viewBody:
    VStack:
      this.identifier = "tasks"
      this.spacing = 10
      this.alignment = svaFill
      for task in tasks:
        keyed(task.id):
          HStack:
            this.identifier = "task-" & $task.id
            this[vpDraggable] = true
            this.spacing = 10
            this.edgeInsets = insets(10)
            this.backgroundColor = color(0.16, 0.24, 0.32, 0.16)
            Label:
              this.stringValue = "#" & $task.id
            TextField:
              this.identifier = "title-" & $task.id
              arrangedSizing(svspFillAvailableWidth)
              if owner.isNil:
                this.stringValue = task.title
              else:
                bindingScope.bindTextField(
                  "title", owner, titlesChanged, owner, task.id, titleFor, this,
                  editTitle,
                )
            Button:
              this.title = "Remove"
              this.identifier = "remove-" & $task.id
              this.acceptsFirstResponder = false
              onAction(owner, task.id) do(
                receiver: TaskController, id: int, sender: DynamicAgent
              ):
                receiver.removeTask(id)
      if tasks.len == 0:
        Label:
          this.stringValue = "No tasks. Add one to continue."

proc currentTasks(controller: TaskController, context: int): TaskRows =
  controller.tasks

proc renderRows(controller: TaskController, tasks: TaskRows) =
  controller.rows.taskRows(tasks, controller)

proc updatePreview(preview: DeclarativeDragView[TaskRows], tasks: TaskRows) =
  preview.model = tasks

proc counterText(controller: TaskController, context: int): string =
  "Unrelated counter: " & $controller.counter{}

proc statusText(controller: TaskController, context: int): string =
  controller.status{}

proc setLabel(label: Label, value: string) =
  if label.stringValue != value:
    label.stringValue = value

proc buildChrome(controller: TaskController) =
  controller.chrome.viewBody:
    VStack:
      this.spacing = 14
      this.edgeInsets = insets(16)
      Label:
        this.stringValue = "Direct views + MVC bindings"
        this.labelStyle = lsHeading
      Label:
        this.stringValue =
          "Edit a title, then insert, reverse, undo or change the counter."
      HStack:
        this.spacing = 8
        Button:
          this.title = "Insert at top"
          this.identifier = "insert"
          this.acceptsFirstResponder = false
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            receiver.insertTask()
        Button:
          this.title = "Reverse"
          this.identifier = "reverse"
          this.acceptsFirstResponder = false
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            receiver.reverseTasks()
        Button:
          this.title = "Counter +1"
          this.identifier = "counter"
          this.acceptsFirstResponder = false
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            receiver.counter <- receiver.counter{} + 1
        Button:
          this.title = "Undo"
          this.identifier = "undo"
          this.acceptsFirstResponder = false
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            discard receiver.history.performUndo()
        Button:
          this.title = "Redo"
          this.identifier = "redo"
          this.acceptsFirstResponder = false
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            discard receiver.history.performRedo()
      Label:
        this.identifier = "counter-value"
        bindingScope.bindSigilValue(
          "counter", controller.counter, controller, 0, counterText, this, setLabel
        )
      VStack:
        # A separately owned structural region: its body only reruns when rows
        # are inserted, removed or moved. The outer chrome is built once.
        controller.rows = newDirectViewSession(this)
      Label:
        this.identifier = "status"
        this.labelStyle = lsStatus
        bindingScope.bindSigilValue(
          "status", controller.status, controller, 0, statusText, this, setLabel
        )

proc successors(tasks: TaskRows, id: string): seq[TaskRows] =
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

proc runDirectViewsDemo*() =
  let controller = TaskController(
    tasks: @[
      TaskItem(id: 1, title: "Keep my editing session"),
      TaskItem(id: 2, title: "Insert and reorder around me"),
      TaskItem(id: 3, title: "Commands follow task identity"),
    ],
    nextId: 4,
    counter: newSigil(0),
    status: newSigil("Select text in a row to start."),
    history: newUndoManager(),
    bindings: newBindingScope(),
    chrome: newDirectViewSession(newStackView()),
  )
  initViewController(controller)
  controller.buildChrome()
  controller.bindings.bindValue(
    "rows", controller, rowsChanged, controller, 0, currentTasks, controller, renderRows
  )
  var owner: BackRef[TaskController]
  owner.target = controller
  controller.preview = newDeclarativeDragView(
    controller.tasks,
    build = proc(tasks: TaskRows, env: DragEnvironment): View =
      let session = newDirectViewSession(newStackView(), detached = true)
      session.taskRows(tasks)
      session.takeDetachedRoot(),
    successors = successors,
    commit = proc(previous, next: TaskRows): bool =
      let receiver = owner.target
      # A drag proposal cannot overwrite edits made since its snapshot.
      if not receiver.isNil and receiver.tasks == previous:
        receiver.replaceTasks(next, "Dragged a task")
        result = true
    ,
    frame = rect(0, 0, 470, 330),
  )
  controller.bindings.bindValue(
    "preview", controller, snapshotChanged, controller, 0, currentTasks,
    controller.preview, updatePreview,
  )
  controller.preview.autoresizingMaskConstraints = false
  let right = newStackView()
  right.spacing = 14
  right.edgeInsets = insets(16)
  right.addArrangedSubview(newHeadingLabel("Dragology preview"))
  right.addArrangedSubview(newLabel("Drag a card here to reorder the live list."))
  right.addArrangedSubview(newLabel("Same builder; fresh widgets, no live bindings."))
  right.addArrangedSubview(controller.preview)
  let root = newStackView(laHorizontal)
  root.alignment = svaFill
  root.distribution = svdFillEqually
  root.addArrangedSubview(controller.chrome.host, right)
  controller.setView(root)
  defer:
    controller.bindings.dispose()
    controller.rows.close()
    controller.chrome.close()
  sharedApplication().runWindow(
    newWindow("Direct views: MVC and bindings", frame = rect(80, 80, 1240, 540)), root
  )

when isMainModule:
  runDirectViewsDemo()
