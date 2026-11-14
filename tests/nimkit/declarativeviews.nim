import std/unittest
import merenda/nimkit

type
  Todo = object
    id, title: string

  TestController = ref object of Responder
    called, value: string
    actions, changes: int
    host: DeclarativeView

proc newTestController(): TestController =
  result = TestController()
  initResponder(result)

proc namedAction(self: DynamicAgent, invocation: var Invocation) =
  let controller = TestController(self)
  inc controller.actions
  controller.called = View(invocation.argsAs(ActionArgs).sender).identifier
  invocation.setResult(())

proc rowSpec(todo: Todo, onRemove = ViewAction(), onChange = ViewAction()): ViewSpec =
  viewBody:
    HStack(identifier = "row-" & todo.id, draggable = true):
      TextField(
        todo.title,
        identifier = "edit-" & todo.id,
        onChange = onChange,
        sizing = svspFillAvailableWidth,
      )
      Button("Remove", identifier = "remove-" & todo.id, onAction = onRemove)

proc listSpec(todos: seq[Todo], counter = 0): ViewSpec =
  viewBody:
    VStack(identifier = "list"):
      Label("Count: " & $counter, identifier = "counter")
      for todo in todos:
        keyed(todo.id):
          rowSpec(todo)

proc click(button: Button) =
  discard button.send(performClick(), ActionArgs(sender: button))

proc controlledBody(controller: TestController): ViewSpec =
  viewBody:
    TextField(controller.value, identifier = "field"):
      onChange(controller) do(receiver: TestController, sender: DynamicAgent):
        inc receiver.changes
        receiver.value = TextField(sender).stringValue
        receiver.host.update(receiver.controlledBody())

static:
  doAssert not compiles(
    block:
      let body = viewBody:
        vstack:
          Label("Lowercase container")
      discard body
  )
  doAssert not compiles(
    block:
      let body = viewBody:
        VStack:
          button("Lowercase control")
      discard body
  )
  doAssert not compiles(
    block:
      proc capturedHandler(controller: TestController, captured: int): ViewSpec =
        viewBody:
          Button("Invalid"):
            onAction(controller) do(receiver: TestController, sender: DynamicAgent) {.
              closure
            .}:
              receiver.actions += captured

      discard capturedHandler(newTestController(), 1)
  )

suite "NimKit declarative views":
  test "viewBody accepts SwiftUI-style capitalized control names":
    let controller = newTestController()
    let body = viewBody:
      VStack:
        HStack:
          Label("Title")
          TextField("Value", identifier = "value"):
            onChange(controller) do(receiver: TestController, sender: DynamicAgent):
              receiver.value = TextField(sender).stringValue
          Button("Count", identifier = "count"):
            onAction(controller) do(receiver: TestController, sender: DynamicAgent):
              inc receiver.actions
    let host = newDeclarativeView(body)
    defer:
      host.clear()
    Button(host.viewWithIdentifier("count")).click()
    TextField(host.viewWithIdentifier("value")).stringValue = "Edited"
    check controller.actions == 1
    check controller.value == "Edited"

  test "viewBody composes typed helpers, branches and keyed loops":
    let todos = @[Todo(id: "a", title: "Alpha"), Todo(id: "b", title: "Beta")]
    let spec = listSpec(todos)
    let detached = buildDetachedView(spec)
    check StackView(detached).arrangedSubviews.len == 3
    check TextField(detached.viewWithIdentifier("edit-b")).stringValue == "Beta"
    check detached.viewWithIdentifier("row-a")[vpDraggable]
    check detached.window.isNil
    check detached.superview.isNil

  test "editing survives insertion, reorder, unrelated updates and unchanged titles":
    var todos = @[
      Todo(id: "a", title: "Alpha"),
      Todo(id: "b", title: "Beta"),
      Todo(id: "c", title: "Gamma"),
    ]
    let host = newDeclarativeView(listSpec(todos), frame = rect(0, 0, 600, 320))
    let window = newWindow("Declarative editing", frame = rect(0, 0, 600, 320))
    window.setContentView(host)
    defer:
      host.clear()
      window.close()
    host.layoutSubtreeIfNeeded()
    let field = TextField(host.viewWithIdentifier("edit-b"))
    let row = field.superview
    require window.makeFirstResponder(field)
    let editor = field.currentEditor
    field.selectedRange = initTextRange(1, 2)
    # A local edit not yet reflected in the model must also survive reevaluation.
    TextView(editor).insertTextValue("EDIT")
    field.selectedRange = initTextRange(1, 3)
    let edited = field.stringValue
    todos = @[todos[2], Todo(id: "new", title: "New"), todos[1], todos[0]]
    host.update(listSpec(todos, counter = 7))
    host.layoutSubtreeIfNeeded()
    check host.viewWithIdentifier("edit-b") == field
    check field.superview == row
    check field.currentEditor == editor
    check window.firstResponder == editor
    check window.fieldEditorClient() == field
    check field.stringValue == edited
    check field.selectedRange == initTextRange(1, 3)
    check host.updateStats.created == 3
    check host.updateStats.removed == 0
    let arranged = StackView(host.viewWithIdentifier("list")).arrangedSubviews
    check arranged[1].identifier == "row-c"
    check arranged[3] == row
    host.update(listSpec(todos, counter = 8))
    check host.updateStats.created == 0
    check host.updateStats.moved == 0
    check field.currentEditor == editor
    check field.selectedRange == initTextRange(1, 3)

  test "marked text survives an unrelated description update":
    let todos = @[Todo(id: "a", title: "Alpha")]
    let host = newDeclarativeView(listSpec(todos), frame = rect(0, 0, 500, 200))
    let window = newWindow("Declarative composition", frame = rect(0, 0, 500, 200))
    window.setContentView(host)
    defer:
      host.clear()
      window.close()
    let field = TextField(host.viewWithIdentifier("edit-a"))
    require window.makeFirstResponder(field)
    let editor = TextView(field.currentEditor)
    editor.selectedRange = initTextRange(1, 2)
    editor.setMarkedTextValue("xy", initTextRange(1, 0), initTextRange(-1, 0))
    require editor.hasMarkedText
    let marked = editor.markedRange
    let selection = editor.selectedRange
    let text = editor.stringValue
    host.update(listSpec(todos, counter = 1))
    check field.currentEditor == editor
    check editor.hasMarkedText
    check editor.markedRange == marked
    check editor.selectedRange == selection
    check editor.stringValue == text

  test "callbacks are refreshed and still target the keyed item after reordering":
    let controller = newTestController()
    proc item(id: string, revision: int): ViewSpec =
      let callback = viewAction(controller, (id: id, revision: revision)) do(
        receiver: TestController,
        context: tuple[id: string, revision: int],
        sender: DynamicAgent
      ):
        receiver.called = context.id & ":" & $context.revision
      let changed = viewAction(controller, (id: id, revision: revision)) do(
        receiver: TestController,
        context: tuple[id: string, revision: int],
        sender: DynamicAgent
      ):
        receiver.called =
          context.id & ":" & $context.revision & ":" & TextField(sender).stringValue
      keyedSpec(id, rowSpec(Todo(id: id, title: id), callback, changed))

    let host = newDeclarativeView(vstackSpec(@[item("a", 1), item("b", 1)]))
    defer:
      host.clear()
    let button = Button(host.viewWithIdentifier("remove-a"))
    let field = TextField(host.viewWithIdentifier("edit-a"))
    host.update(vstackSpec(@[item("b", 2), item("a", 2)]))
    check host.viewWithIdentifier("remove-a") == button
    button.click()
    check controller.called == "a:2"
    field.stringValue = "Edited"
    check controller.called == "a:2:Edited"
    host.update(vstackSpec(@[item("b", 3)]))
    button.click()
    field.stringValue = "Detached"
    check controller.called == "a:2:Edited"

  test "controlled text echoes preserve editing and programmatic patches do not notify":
    let controller = newTestController()
    controller.value = "Alpha"
    let host =
      newDeclarativeView(controller.controlledBody(), frame = rect(0, 0, 300, 60))
    controller.host = host
    let window = newWindow("Declarative binding", frame = rect(0, 0, 300, 60))
    window.setContentView(host)
    defer:
      host.clear()
      window.close()
    let field = TextField(host.viewWithIdentifier("field"))
    require window.makeFirstResponder(field)
    let editor = field.currentEditor
    field.selectedRange = initTextRange(5, 0)
    discard editor.send(insertText(), "!")
    check controller.changes == 1
    check controller.value == "Alpha!"
    check field.currentEditor == editor
    check field.selectedRange == initTextRange(6, 0)
    controller.value = "External update"
    host.update(controller.controlledBody())
    check field.stringValue == controller.value
    check controller.changes == 1
    host.clear()
    field.stringValue = "Detached"
    check controller.changes == 1

  test "inline actions retain adapters without retaining their owning controller":
    var observed: BackRef[TestController]
    var host: DeclarativeView
    block:
      let controller = newTestController()
      observed.target = controller
      let body = viewBody:
        Button("Count", identifier = "count"):
          onAction(controller, 3) do(
            receiver: TestController, amount: int, sender: DynamicAgent
          ):
            receiver.actions += amount
      host = newDeclarativeView(body)
      controller.host = host
      Button(host.viewWithIdentifier("count")).click()
      check controller.actions == 3
    check observed.isNil
    Button(host.viewWithIdentifier("count")).click()
    host.clear()

  test "existing named selectors keep ordinary responder targets weak":
    var observed: BackRef[TestController]
    var host: DeclarativeView
    block:
      let controller = newTestController()
      observed.target = controller
      let action = actionSelector("test.declarativeNamedAction")
      discard controller.replaceMethod(action, DynamicMethod(namedAction))
      host = newDeclarativeView(
        buttonSpec(
          "Run", onAction = initViewAction(action, controller), identifier = "named"
        )
      )
      Button(host.viewWithIdentifier("named")).click()
      check controller.actions == 1
      check controller.called == "named"
    check observed.isNil
    Button(host.viewWithIdentifier("named")).click()
    host.clear()

  test "an inline action can clear its own mount":
    let controller = newTestController()
    let body = viewBody:
      Button("Clear", identifier = "clear"):
        onAction(controller) do(receiver: TestController, sender: DynamicAgent):
          inc receiver.actions
          receiver.host.clear()
    controller.host = newDeclarativeView(body)
    let button = Button(controller.host.viewWithIdentifier("clear"))
    button.click()
    check controller.actions == 1
    check controller.host.arrangedSubviews.len == 0
    button.click()
    check controller.actions == 1

  test "conditional siblings do not shift structural identity":
    proc body(show: bool): ViewSpec =
      viewBody:
        VStack:
          if show:
            Label("Optional")
          TextField("Stable", identifier = "stable")

    let host = newDeclarativeView(body(false))
    defer:
      host.clear()
    let field = host.viewWithIdentifier("stable")
    host.update(body(true))
    check host.viewWithIdentifier("stable") == field
    host.update(body(false))
    check host.viewWithIdentifier("stable") == field

  test "invalid sibling keys fail before modifying the installed hierarchy":
    let host = newDeclarativeView(listSpec(@[Todo(id: "a", title: "Alpha")]))
    defer:
      host.clear()
    let field = host.viewWithIdentifier("edit-a")
    expect ValueError:
      host.update(listSpec(@[Todo(id: "a", title: "One"), Todo(id: "a", title: "Two")]))
    check host.viewWithIdentifier("edit-a") == field
    check TextField(field).stringValue == "Alpha"

  test "unkeyed repetitions are diagnosed and keys are scoped to their parent":
    let invalid = viewBody:
      VStack:
        for i in 0 .. 1:
          Label($i)
    expect ValueError:
      discard newDeclarativeView(invalid)
    let host = newDeclarativeView(
      vstackSpec(
        @[
          vstackSpec(@[labelSpec("A", key = "same")], key = "left"),
          vstackSpec(@[labelSpec("B", key = "same")], key = "right"),
        ]
      )
    )
    host.clear()

  test "changed keys or widget kinds replace the old instance":
    let host = newDeclarativeView(textFieldSpec("A", key = "a", identifier = "field"))
    defer:
      host.clear()
    let first = host.viewWithIdentifier("field")
    host.update(textFieldSpec("B", key = "b", identifier = "field"))
    let second = host.viewWithIdentifier("field")
    check second != first
    check first.superview.isNil
    host.update(labelSpec("Label", key = "b", identifier = "field"))
    check host.viewWithIdentifier("field") != second
    check host.updateStats.created == 1
    check host.updateStats.removed == 1

  test "detached previews install no event handlers and match live layout":
    let controller = newTestController()
    let action = viewAction(controller) do(
      receiver: TestController, sender: DynamicAgent
    ):
      inc receiver.actions
    let changed = viewAction(controller) do(
      receiver: TestController, sender: DynamicAgent
    ):
      inc receiver.changes
    let spec = vstackSpec(
      @[keyedSpec("a", rowSpec(Todo(id: "a", title: "Alpha"), action, changed))]
    )
    let host = newDeclarativeView(spec, frame = rect(0, 0, 500, 200))
    defer:
      host.clear()
    host.layoutSubtreeIfNeeded()
    let detached = buildDetachedView(spec)
    let env =
      DragEnvironment(bounds: rect(0, 0, 500, 200), appearance: initAppearance())
    let preview = captureDragPreview(detached, env)
    Button(detached.viewWithIdentifier("remove-a")).click()
    TextField(detached.viewWithIdentifier("edit-a")).stringValue = "Preview only"
    check controller.actions == 0
    check controller.changes == 0
    check preview.find("row-a") >= 0
    let live = host.viewWithIdentifier("row-a")
    check preview.elements[preview.find("row-a")].frame ==
      host.rectFromView(live.bounds, live)
    check TextField(host.viewWithIdentifier("edit-a")).stringValue == "Alpha"
