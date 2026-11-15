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
      this[vpDraggable] = true
      this.spacing = 10
      this.edgeInsets = insets(10)
      this.backgroundColor = color(0.16, 0.24, 0.32, 0.16)
      Label:
        when defined(merendaIntrinsicCache):
          this[vpCacheIntrinsicSize] = true
        this.stringValue = "#" & $task.id
      TextField:
        when defined(merendaIntrinsicCache):
          this[vpCacheIntrinsicSize] = true
        this.identifier = "title-" & $task.id
        arrangedSizing(svspFillAvailableWidth)
        if owner.isNil:
          this.stringValue = task.title
        else:
          bindingScope.bindTextField(
            "title",
            owner.tasks.item(task.id),
            owner,
            task.id,
            titleFor,
            this,
            editTitle,
          )
      Button("Remove", identifier = "remove-" & $task.id, acceptsFirstResponder = false):
        when defined(merendaIntrinsicCache):
          this[vpCacheIntrinsicSize] = true
        onAction(owner, task.id) do(
          receiver: TaskController, id: int, sender: DynamicAgent
        ):
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
          when defined(merendaIntrinsicCache):
            this[vpCacheIntrinsicSize] = true
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
      bindingScope.bindPreview(controller)
      Label:
        when defined(merendaIntrinsicCache):
          this[vpCacheIntrinsicSize] = true
        this.stringValue = "Direct views + MVC bindings"
        this.labelStyle = lsHeading
      Label:
        when defined(merendaIntrinsicCache):
          this[vpCacheIntrinsicSize] = true
        this.stringValue =
          "Edit a title, then insert, reverse, undo or change the counter."
      HStack:
        this.distribution = svdNatural
        this.spacing = 8
        Button("Insert at top", identifier = "insert", acceptsFirstResponder = false):
          when defined(merendaIntrinsicCache):
            this[vpCacheIntrinsicSize] = true
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            receiver.insertTask()
        Button("Reverse", identifier = "reverse", acceptsFirstResponder = false):
          when defined(merendaIntrinsicCache):
            this[vpCacheIntrinsicSize] = true
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            receiver.reverseTasks()
        Button("Counter +1", identifier = "counter", acceptsFirstResponder = false):
          when defined(merendaIntrinsicCache):
            this[vpCacheIntrinsicSize] = true
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            receiver.counter <- receiver.counter{} + 1
        Button("Undo", identifier = "undo", acceptsFirstResponder = false):
          when defined(merendaIntrinsicCache):
            this[vpCacheIntrinsicSize] = true
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            discard receiver.history.performUndo()
        Button("Redo", identifier = "redo", acceptsFirstResponder = false):
          when defined(merendaIntrinsicCache):
            this[vpCacheIntrinsicSize] = true
          onAction(controller) do(receiver: TaskController, sender: DynamicAgent):
            discard receiver.history.performRedo()
      Label:
        when defined(merendaIntrinsicCache):
          this[vpCacheIntrinsicSize] = true
        this.identifier = "counter-value"
        bindingScope.bindValue("counter", controller.counter, this) do(
          label: Label, value: int
        ):
          label.stringValue = "Unrelated counter: " & $value
      component(observedTaskRows, controller)
      Label:
        when defined(merendaIntrinsicCache):
          this[vpCacheIntrinsicSize] = true
        this.identifier = "status"
        this.labelStyle = lsStatus
        bindingScope.bindValue("status", controller.status, this) do(
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
