## Direct views: ordinary components and view-owned, keyed collection bindings.
import sigils/[core, reactive]
import merenda/nimkit
import merenda/nimkit/directviews
import ./declarative_tasks

proc taskRow(context: DirectNode, task: TaskItem, owner: TaskController) =
  context.viewBody:
    HStack:
      this.distribution = svdNatural
      this.identifier = "task-" & $task.id
      this{vpDraggable} = true
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
          bindTextField(
            "title", owner.tasks.item(task.id), owner, task.id, titleFor, editTitle
          )
      Button("Remove", identifier = "remove-" & $task.id, acceptsFirstResponder = false):
        onAction(owner, task.id) do(this: Button, receiver: TaskController, id: int):
          receiver.removeTask(id)

proc taskRows(context: DirectNode, tasks: TaskRows, owner: TaskController = nil) =
  context.viewBody:
    VStack:
      this.identifier = "tasks"
      this.distribution = svdNatural
      this.spacing = 10
      this.alignment = svaFill
      for task in tasks:
        keyed(task.id):
          component(taskRow, task, owner)
      if tasks.len == 0:
        Label:
          this.stringValue = "No tasks. Add one to continue."

proc showTaskRows(context: DirectNode, owner: TaskController, ids: seq[int]) =
  context.taskRows(owner.tasks{}, owner)

proc observedTaskRows(context: DirectNode, owner: TaskController) =
  context.bindBody(owner.tasks.order, owner, showTaskRows)

proc buildChrome(controller: TaskController): DirectView =
  result = newDirectView()
  result.viewBody:
    VStack:
      this.spacing = 14
      this.distribution = svdNatural
      this.edgeInsets = insets(16)
      this.bindPreview(controller)
      Label:
        this.stringValue = "Direct views + MVC bindings"
        this.labelStyle = lsHeading
      Label:
        this.stringValue =
          "Edit a title, then insert, reverse, undo or change the counter."
      HStack:
        this.distribution = svdNatural
        this.spacing = 8
        Button("Insert at top", identifier = "insert", acceptsFirstResponder = false):
          onAction(controller) do(this: Button, receiver: TaskController):
            receiver.insertTask()
        Button("Reverse", identifier = "reverse", acceptsFirstResponder = false):
          onAction(controller) do(this: Button, receiver: TaskController):
            receiver.reverseTasks()
        Button("Counter +1", identifier = "counter", acceptsFirstResponder = false):
          onAction(controller) do(this: Button, receiver: TaskController):
            receiver.counter <- receiver.counter{} + 1
        Button("Undo", identifier = "undo", acceptsFirstResponder = false):
          onAction(controller) do(this: Button, receiver: TaskController):
            discard receiver.history.performUndo()
        Button("Redo", identifier = "redo", acceptsFirstResponder = false):
          onAction(controller) do(this: Button, receiver: TaskController):
            discard receiver.history.performRedo()
      Label:
        this.identifier = "counter-value"
        bindValue(id = "counter", input = controller.counter) do(
          label: Label, value: int
        ):
          label.stringValue = "Unrelated counter: " & $value
      component(observedTaskRows, controller)
      Label:
        this.identifier = "status"
        this.labelStyle = lsStatus
        bindValue(id = "status", input = controller.status) do(
          label: Label, value: string
        ):
          label.stringValue = value

proc newTaskController(): TaskController =
  result = newTaskModelController()
  result.createPreview(
    proc(tasks: TaskRows, env: DragEnvironment): View =
      let host = newDirectView(detached = true)
      host.viewBody:
        component(taskRows, tasks)
      host.takeDetachedRoot()
  )
  result.setTaskDemoView(result.buildChrome())

proc runDirectViewsDemo*() =
  let controller = newTaskController()
  sharedApplication().runWindow(
    newWindow("Direct views: MVC and bindings", frame = rect(80, 80, 1240, 540)),
    controller.view,
  )

when isMainModule and not defined(merendaTests):
  runDirectViewsDemo()
