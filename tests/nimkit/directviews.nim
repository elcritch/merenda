import std/unittest
import sigils/core
import sigils/reactive
import merenda/nimkit/foundation/mainthreadwork
import merenda/nimkit
import merenda/nimkit/directviews
import merenda/nimkit/directviews/dsl
import merenda/nimkit/containers/stackviews
import merenda/nimkit/text/textfields
import merenda/nimkit/view/views
import merenda/nimkit/controls/buttons
import merenda/nimkit/responder/responders
import merenda/nimkit/foundation/selectors

type
  DirectController = ref object of Responder
    calls: int
    host: DirectView

  DirectBindingModel = ref object of Responder
    value: int

  TextOwner = ref object of Responder
    text: Sigil[string]
    edits: int

  CustomDirectView = ref object of View

  PropertyDirectView = ref object of View
    seed: int
    xCaption: string
    writes: int

protocol DirectSelectorActions from DirectController:
  method recordDirectWidget(controller: DirectController, args: ActionArgs) =
    if args.sender of Button:
      Button(args.sender).title = "Clicked"
      inc controller.calls
    elif args.sender of TextField:
      controller.calls += TextField(args.sender).stringValue.len

proc readOwnedText(owner: TextOwner): string =
  owner.text{}

proc readOwnedText(owner: TextOwner, context: int): string =
  owner.readOwnedText()

proc editOwnedText(owner: TextOwner, value: string) =
  inc owner.edits
  owner.text <- value

proc editOwnedText(owner: TextOwner, context: int, value: string) =
  owner.editOwnedText(value)

proc directChanged(model: DirectBindingModel, value: int) {.signal.}
proc readDirect(model: DirectBindingModel, context: int): int =
  model.value

proc writeDirect(field: TextField, value: int) =
  field.stringValue = $value

proc newCustomDirectView(): CustomDirectView =
  result = CustomDirectView()
  initViewFields(result)

proc newPropertyDirectView(seed: int): PropertyDirectView =
  result = PropertyDirectView(seed: seed)
  initViewFields(result)

proc `caption=`(view: PropertyDirectView, value: string) =
  view.xCaption = value
  inc view.writes

proc caption(view: PropertyDirectView): string =
  view.xCaption

proc counterComponent(context: DirectNode, owner: DirectController, value: int) =
  context.viewBody:
    Button:
      this.identifier = "component-button"
      this.title = $value
      this.onAction(owner, value) do(
        this: Button, receiver: DirectController, count: int
      ):
        receiver.calls += count

proc observedCounter(context: DirectNode, owner: DirectController, value: Sigil[int]) =
  context.bindBody(value, owner, counterComponent)

proc conditionalComponent(
    context: DirectNode, owner: DirectController, value: Sigil[int], observe: bool
) =
  if observe:
    context.bindBody(value, owner, counterComponent)
  else:
    context.counterComponent(owner, 99)

proc changingRoot(context: DirectNode, owner: DirectController, value: int) =
  context.viewBody:
    if value == 0:
      Button:
        this.identifier = "old-component-root"
    else:
      Label:
        this.identifier = "new-component-root"

proc observedChangingRoot(
    context: DirectNode, owner: DirectController, value: Sigil[int]
) =
  context.bindBody(value, owner, changingRoot)

static:
  doAssert not compiles(
    block:
      let owner = TextOwner(text: newSigil("text"))
      let host = newDirectView()
      host.viewBody:
        TextField:
          bindingScope.bindTextField(
            "text", owner.text, owner, 0, readOwnedText, this, editOwnedText
          )
  )

  doAssert not compiles(
    block:
      let owner = TextOwner(text: newSigil("text"))
      let host = newDirectView()
      host.viewBody:
        Label:
          bindingScope.bindValue("text", owner.text, this) do(
            label: Label, value: string
          ):
            label.stringValue = value
  )

  doAssert not compiles(
    block:
      let host = newDirectView()
      let owner = DirectController()
      host.viewBody:
        Button("Add"):
          this.onAction(owner, 1) do(
            receiver: DirectController, amount: int, sender: DynamicAgent
          ):
            receiver.calls += amount
  )

  doAssert not compiles(
    block:
      let host = newDirectView()
      let owner: Responder = DirectController()
      host.viewBody:
        Button("Add"):
          this.onAction(owner) do(this: Button, receiver: DirectController):
            inc receiver.calls
  )

  doAssert not compiles(
    block:
      let host = newDirectView()
      host.viewBody:
        Button(title: "Remove")
  )

  doAssert not compiles(
    block:
      let host = newDirectView()
      host.viewBody:
        Button("First", title = "Second")
  )

  doAssert not compiles(
    block:
      let host = newDirectView()
      host.viewBody:
        Button(identifier = "x", "Title")
  )
  doAssert not compiles(
    block:
      let host = newDirectView()
      host.viewBody:
        Button(title = "Named", "Positional")
  )

suite "direct view composition":
  test "an inline action can clear its own host":
    let owner = DirectController(host: newDirectView())
    initResponder(owner)
    owner.host.viewBody:
      Button("Clear", identifier = "clear"):
        this.onAction(owner) do(this: Button, receiver: DirectController):
          inc receiver.calls
          receiver.host.clear()
    let button = Button(owner.host.viewWithIdentifier("clear"))
    require button.tryToPerform(performClick(), button)
    check owner.calls == 1
    check owner.host.arrangedSubviews.len == 0
    discard button.tryToPerform(performClick(), button)
    check owner.calls == 1

  test "body receiver is evaluated once and its update is completed":
    let first = newDirectView()
    let second = newDirectView()
    second.viewBody:
      Label(identifier = "second")
    let original = second.arrangedSubviews[0]
    var lookups = 0
    proc selectedHost(): DirectView =
      inc lookups
      if lookups == 1: first else: second

    selectedHost().viewBody:
      Button(identifier = "first")

    check lookups == 1
    require first.arrangedSubviews.len == 1
    check first.arrangedSubviews[0].identifier == "first"
    require second.arrangedSubviews.len == 1
    check second.arrangedSubviews[0] == original
    check second.arrangedSubviews[0].identifier == "second"

    first.viewBody:
      Label(identifier = "updated")
    require first.arrangedSubviews.len == 1
    check first.arrangedSubviews[0].identifier == "updated"

  test "the receiver stays alive until its body finishes":
    var host = newDirectView()
    var weakHost: BackRef[DirectView]
    weakHost.target = host
    host.viewBody:
      host = nil
      check not weakHost.isNil
      Button("mounted")
    check weakHost.isNil

  test "a widget setter sets its sizing policy for the current composition":
    let host = newDirectView()

    proc fillWidth(view: View) =
      view.arrangedSizing = svspFillAvailableWidth

    host.viewBody:
      TextField:
        fillWidth(this)
    let field = host.arrangedSubviews[0]
    check host.arrangedSubviewSizingPolicy(field) == svspFillAvailableWidth

    host.viewBody:
      TextField:
        this.stringValue = "Updated"
    check host.arrangedSubviews[0] == field
    check host.arrangedSubviewSizingPolicy(field) == svspAutomatic

    host.clear()
    expect ValueError:
      fillWidth(field)

  test "positional button title updates once per evaluation and before the body":
    let host = newDirectView()
    let owner = DirectController()
    var title = "First"
    var reads = 0
    var frames = 0
    proc readTitle(): string =
      inc reads
      title

    proc readFrame(): Rect =
      inc frames
      rect(1, 2, 100, 40)

    proc render() =
      host.viewBody:
        Button(readTitle(), readFrame(), identifier = "positional"):
          this.identifier = this.title
          this.onAction(owner, reads) do(
            this: Button, receiver: DirectController, count: int
          ):
            receiver.calls += count
        Button(readTitle())

    render()
    let button = Button(host.arrangedSubviews[0])
    let bodyless = Button(host.arrangedSubviews[1])
    check button.title == "First"
    check button.frame() == rect(1, 2, 100, 40)
    check button.identifier == "First"
    check bodyless.title == "First"
    check reads == 2
    check frames == 1
    title = "Second"
    render()
    check host.arrangedSubviews[0] == button
    check host.arrangedSubviews[1] == bodyless
    check button.title == "Second"
    check button.identifier == "Second"
    check bodyless.title == "Second"
    check reads == 4
    check frames == 1
    discard button.send(performClick(), ActionArgs(sender: button))
    check owner.calls == 3

  test "named properties update retained widgets before the optional body":
    let host = newDirectView()
    var title = "First"
    var reads = 0
    proc readTitle(): string =
      inc reads
      title

    proc render() =
      host.viewBody:
        Button(title = readTitle(), identifier = "short")
        Button(title = title):
          this.identifier = this.title
          this.title = "Body: " & this.title

    render()
    let short = Button(host.arrangedSubviews[0])
    let extended = Button(host.arrangedSubviews[1])
    check short.title == "First"
    check short.identifier == "short"
    check extended.identifier == "First"
    check extended.title == "Body: First"
    check reads == 1
    title = "Second"
    render()
    check host.arrangedSubviews[0] == short
    check host.arrangedSubviews[1] == extended
    check short.title == "Second"
    check extended.identifier == "Second"
    check extended.title == "Body: Second"
    check reads == 2

  test "positional arguments construct once and named properties call custom setters":
    let host = newDirectView()
    var creations = 0
    var caption = "First"
    proc nextSeed(): int =
      inc creations
      creations

    proc render() =
      host.viewBody:
        PropertyDirectView(nextSeed(), caption = caption)

    render()
    let view = PropertyDirectView(host.arrangedSubviews[0])
    check creations == 1
    check view.seed == 1
    check view.caption == "First"
    check view.writes == 1
    caption = "Second"
    render()
    check host.arrangedSubviews[0] == view
    check creations == 1
    check view.seed == 1
    check view.caption == "Second"
    check view.writes == 2

  test "patching text preserves drafts on unchanged input and applies new model text":
    let host = newDirectView()
    var value = "Model"
    proc render() =
      host.viewBody:
        TextField:
          this.patchText(value)

    render()
    let field = TextField(host.arrangedSubviews[0])
    field.stringValue = "Draft"
    render()
    check field.stringValue == "Draft"
    value = "New model"
    render()
    check host.arrangedSubviews[0] == field
    check field.stringValue == "New model"

  test "text ownership transfers across binding and omitted passes":
    let host = newDirectView()
    let owner = TextOwner(text: newSigil("bound"))
    var mode = 0
    var authored = "plain"
    proc render() =
      host.viewBody:
        TextField:
          if mode == 0:
            this.patchText(authored)
          elif mode == 1:
            this.bindTextField(
              "text", owner.text, owner, 0, readOwnedText, editOwnedText
            )

    render()
    let field = TextField(host.arrangedSubviews[0])
    mode = 1
    render()
    check field.stringValue == "bound"
    mode = 0
    render()
    check host.arrangedSubviews[0] == field
    check field.stringValue == "plain"
    check owner.edits == 0
    check owner.text{} == "bound"
    mode = 1
    render()
    mode = 2
    render()
    check field.stringValue == "bound"
    mode = 0
    render()
    check field.stringValue == "plain"
    mode = 1
    render()
    authored = "different"
    mode = 0
    render()
    check field.stringValue == "different"
    check owner.edits == 0

  test "initially bound text transfers to an authored value before queued work":
    let host = newDirectView()
    let owner = TextOwner(text: newSigil("bound"))
    var bound = true
    proc render() =
      host.viewBody:
        TextField:
          if bound:
            this.bindTextField(
              id = "text",
              input = owner.text,
              receiver = owner,
              getter = readOwnedText,
              edit = editOwnedText,
            )
          else:
            this.patchText("plain")

    render()
    let field = TextField(host.arrangedSubviews[0])
    owner.text <- "queued"
    bound = false
    render()
    discard drainMainThreadWork()
    check field.stringValue == "plain"
    check owner.text{} == "queued"
    check owner.edits == 0

  test "direct string Sigil bindings read and write the current source":
    let first = newSigil("initial")
    let second = newSigil("replacement")
    let host = newDirectView()
    var input = first
    proc render() =
      host.viewBody:
        TextField:
          this.bindTextField("text", input)

    render()
    let field = TextField(host.arrangedSubviews[0])
    check field.stringValue == "initial"
    field.stringValue = "edit"
    check first{} == "edit"
    first <- "from model"
    host.flushBindings()
    check field.stringValue == "from model"

    first <- "queued from old source"
    input = second
    render()
    discard drainMainThreadWork()
    check host.arrangedSubviews[0] == field
    check field.stringValue == "replacement"
    field.stringValue = "new edit"
    check second{} == "new edit"
    check first{} == "queued from old source"

  test "omitting a component body binding retires its old subscription":
    let host = newDirectView()
    let owner = DirectController()
    let value = newSigil(1)
    var observed = true
    proc render() =
      host.viewBody:
        component(conditionalComponent, owner, value, observed)

    render()
    let button = Button(host.viewWithIdentifier("component-button"))
    observed = false
    render()
    check value.subcriptions.len == 0
    value <- 2
    discard drainMainThreadWork()
    check button.title == "99"

  test "independent component root replacement updates its parent's actual children":
    let host = newDirectView()
    let owner = DirectController()
    let value = newSigil(0)
    host.viewBody:
      Label:
        this.identifier = "before"
      component(observedChangingRoot, owner, value)
      Label:
        this.identifier = "after"
    let old = host.arrangedSubviews[1]
    value <- 1
    discard drainMainThreadWork()
    check old.superview.isNil
    check host.arrangedSubviews.len == 3
    check host.arrangedSubviews[0].identifier == "before"
    check host.arrangedSubviews[1].identifier == "new-component-root"
    check host.arrangedSubviews[2].identifier == "after"
  test "owned components reuse views and retire bindings without session bookkeeping":
    let owner = DirectController()
    let count = newSigil(1)
    var host = newDirectView()
    var show = true
    proc render() =
      host.viewBody:
        if show:
          component(observedCounter, owner, count)

    render()
    let button = Button(host.viewWithIdentifier("component-button"))
    count <- 2
    discard drainMainThreadWork()
    check host.viewWithIdentifier("component-button") == button
    check button.title == "2"
    render()
    check count.subcriptions.len == 1
    count <- 3
    show = false
    render()
    discard drainMainThreadWork()
    check count.subcriptions.len == 0
    check button.title == "2"
    discard button.send(performClick(), ActionArgs(sender: button))
    check owner.calls == 0
    show = true
    render()
    let retained = Button(host.viewWithIdentifier("component-button"))
    var weakHost: BackRef[DirectView]
    weakHost.target = host
    count <- 4
    host = nil
    check weakHost.isNil
    check count.subcriptions.len == 0
    discard drainMainThreadWork()
    discard retained.send(performClick(), ActionArgs(sender: retained))
    check owner.calls == 0
    check retained.title == "3"

  test "the same reusable component has independent sibling identities":
    let owner = DirectController()
    let host = newDirectView()
    host.viewBody:
      component(counterComponent, owner, 1)
      component(counterComponent, owner, 2)
    let left = Button(host.arrangedSubviews[0])
    let right = Button(host.arrangedSubviews[1])
    check left != right
    discard left.send(performClick(), ActionArgs(sender: left))
    discard right.send(performClick(), ActionArgs(sender: right))
    check owner.calls == 3
  test "keyed rows move in place and retain provisional text":
    let host = newStackView()
    let session = newDirectViewSession(host)
    var ids = @["one", "two"]
    proc render() =
      session.viewBody:
        VStack:
          for id in ids:
            keyed(id):
              TextField:
                this.patchText(id)

    render()
    let stack = StackView(host.arrangedSubviews[0])
    let first = TextField(stack.arrangedSubviews[0])
    let second = stack.arrangedSubviews[1]
    first.stringValue = "editing"
    ids = @["two", "one"]
    render()
    check stack.arrangedSubviews[0] == second
    check stack.arrangedSubviews[1] == first
    check first.stringValue == "editing"
    session.close()
    check host.arrangedSubviews.len == 0

  test "duplicate sibling keys fail visibly":
    let host = newStackView()
    let session = newDirectViewSession(host)
    expect ValueError:
      session.viewBody:
        VStack:
          for id in ["same", "same"]:
            keyed(id):
              TextField:
                this.patchText(id)
    session.close()

  test "detached construction transfers a fresh root":
    let session = newDirectViewSession(newStackView(), detached = true)
    session.viewBody:
      Label(stringValue = "preview")
    let preview = session.takeDetachedRoot()
    check preview of Label
    check Label(preview).stringValue == "preview"
    check preview.superview.isNil

  test "inline actions use current context and removed controls become inert":
    let owner = DirectController()
    initResponder(owner)
    let session = newDirectViewSession(newStackView())
    var amount = 1
    proc render() =
      session.viewBody:
        Button:
          this.onAction(owner, amount) do(
            this: Button, receiver: DirectController, value: int
          ):
            receiver.calls += value

    render()
    let button = Button(session.host.arrangedSubviews[0])
    discard button.send(performClick(), ActionArgs(sender: button))
    check owner.calls == 1
    amount = 2
    render()
    discard button.send(performClick(), ActionArgs(sender: button))
    check owner.calls == 3
    session.close()
    discard button.send(performClick(), ActionArgs(sender: button))
    check owner.calls == 3

  test "keyed editor keeps its selection and marked text when reordered":
    let host = newStackView()
    let session = newDirectViewSession(host)
    let window = newWindow("Direct editor", frame = rect(0, 0, 500, 200))
    window.setContentView(host)
    defer:
      session.close()
      window.close()
    var ids = @["a", "b"]
    proc render() =
      session.viewBody:
        VStack:
          for id in ids:
            keyed(id):
              TextField:
                this.patchText(id & "lpha")

    render()
    let stack = StackView(host.arrangedSubviews[0])
    let field = TextField(stack.arrangedSubviews[0])
    require window.makeFirstResponder(field)
    let editor = TextView(field.currentEditor)
    editor.selectedRange = initTextRange(1, 2)
    editor.setMarkedTextValue("xy", initTextRange(1, 0), initTextRange(-1, 0))
    require editor.hasMarkedText
    let marked = editor.markedRange
    let selection = editor.selectedRange
    let text = editor.stringValue
    ids = @["b", "a"]
    render()
    check stack.arrangedSubviews[1] == field
    check field.currentEditor == editor
    check window.firstResponder == editor
    check editor.hasMarkedText
    check editor.markedRange == marked
    check editor.selectedRange == selection
    check editor.stringValue == text

  test "custom widgets and type replacements participate without a central registry":
    let session = newDirectViewSession(newStackView())
    var custom = true
    proc render() =
      session.viewBody:
        if custom:
          keyed("item"):
            CustomDirectView:
              this.identifier = "custom"
        else:
          keyed("item"):
            TextField:
              this.patchText("replacement")

    render()
    let old = session.host.arrangedSubviews[0]
    check old of CustomDirectView
    custom = false
    render()
    check session.host.arrangedSubviews[0] of TextField
    check old.superview.isNil
    session.close()

  test "sender-first handlers get the typed widget and can use receiver base types":
    let
      owner = DirectController()
      host = newDirectView()
    initResponder(owner)
    proc updateFocus(sender: Responder, receiver: Responder) =
      if sender of TextField:
        receiver.focusable = TextField(sender).stringValue().len > 0

    host.viewBody:
      VStack:
        Button("Add"):
          this.onAction(owner, 7) do(this: Button, receiver: DynamicAgent, amount: int):
            check this.title() == "Add"
            this.title = "Added"
            DirectController(receiver).calls += amount
        TextField:
          this.onChange(owner, updateFocus)
    let
      row = StackView(host.arrangedSubviews[0])
      button = Button(row.arrangedSubviews[0])
      field = TextField(row.arrangedSubviews[1])
    discard
      button.target().sendLocalIfHandled(button.action(), ActionArgs(sender: field))
    check button.title() == "Add"
    check owner.calls == 0
    require button.tryToPerform(performClick(), button)
    check button.title() == "Added"
    check not owner.focusable()
    field.stringValue = "new"
    check owner.calls == 7
    check owner.focusable()

  test "selector bindings deliver the widget to a weak protocol receiver":
    let host = newDirectView()
    var observed: BackRef[DirectController]
    var button: Button
    block:
      let owner = DirectController()
      initResponder(owner)
      discard owner.withProto()
      observed.target = owner
      let changeAction = recordDirectWidget()
      host.viewBody:
        Button("Run"):
          this.onAction(owner, recordDirectWidget())
        TextField:
          this.onChange(owner, changeAction)
      button = Button(host.arrangedSubviews[0])
      let field = TextField(host.arrangedSubviews[1])
      require button.tryToPerform(performClick(), button)
      check button.title == "Clicked"
      check owner.calls == 1
      field.stringValue = "new"
      check owner.calls == 4

    check observed.isNil
    button.title = "Released"
    discard button.tryToPerform(performClick(), button)
    check button.title == "Released"

  test "removed change handlers and expired receivers are inert":
    var observed: BackRef[DirectController]
    let session = newDirectViewSession(newStackView())
    var field: TextField
    block:
      let owner = DirectController()
      initResponder(owner)
      observed.target = owner
      session.viewBody:
        TextField:
          this.onChange(owner) do(this: TextField, receiver: DirectController):
            inc receiver.calls
      field = TextField(session.host.arrangedSubviews[0])
      field.stringValue = "changed"
      check owner.calls == 1
      session.close()
      field.stringValue = "removed"
      check owner.calls == 1
    check observed.isNil
    field.stringValue = "expired"
    session.close()
    field.stringValue = "removed"

  test "omitting an inline action disables the old callback":
    let owner = DirectController()
    initResponder(owner)
    let session = newDirectViewSession(newStackView())
    var enabled = true
    proc render() =
      session.viewBody:
        Button:
          if enabled:
            this.onAction(owner) do(this: Button, receiver: DirectController):
              inc receiver.calls

    render()
    let button = Button(session.host.arrangedSubviews[0])
    discard button.send(performClick(), ActionArgs(sender: button))
    check owner.calls == 1
    enabled = false
    render()
    discard button.send(performClick(), ActionArgs(sender: button))
    check owner.calls == 1
    session.close()

  test "removing a keyed node retires its queued bindings":
    let model = DirectBindingModel(value: 1)
    initResponder(model)
    let session = newDirectViewSession(newStackView())
    var visible = true
    proc readModel(model: DirectBindingModel): int =
      model.value

    proc render() =
      session.viewBody:
        if visible:
          keyed("field"):
            TextField:
              this.bindValue(
                id = "value",
                controller = model,
                signal = directChanged,
                getter = readModel,
                setter = writeDirect,
              )

    render()
    let field = TextField(session.host.arrangedSubviews[0])
    check field.stringValue == "1"
    model.value = 2
    emit model.directChanged(0)
    visible = false
    render()
    session.flushBindings()
    check field.stringValue == "1"
    emit model.directChanged(0)
    session.flushBindings()
    check field.stringValue == "1"
    session.close()

  test "a value binding can target a form field and defer its initial update":
    let host = newDirectView()
    let model = DirectBindingModel(value: 1)
    initResponder(model)
    proc readModel(model: DirectBindingModel): int =
      model.value

    let field = newTextField("Before signal")
    host.viewBody:
      FormView:
        this.addRow(newLabel("Value"), field)
        this.bindValue(
          "value", model, directChanged, readModel, field, writeDirect, false
        )

    check field.stringValue == "Before signal"
    model.value = 2
    emit model.directChanged(0)
    host.flushBindings()
    check field.stringValue == "2"

  test "form bindings follow the mounted widget and stop when its host expires":
    let owner = TextOwner(text: newSigil("initial"))
    initResponder(owner)
    var host = newDirectView()
    var form: FormView
    var scope: BindingScope
    proc render(showForm: bool) =
      host.viewBody:
        if showForm:
          keyed("entry"):
            FormView:
              if this.rows.len == 0:
                this.addRow(newLabel("Text"), newTextField(""))
              let field = TextField(this.rows[0].field)
              this.bindTextField(
                "text", owner.text, owner, 0, readOwnedText, field, editOwnedText
              )
              form = this
              scope = bindingScope
        else:
          keyed("entry"):
            Label("Replacement")

    render(true)
    let oldForm = form
    let oldScope = scope
    let oldField = TextField(oldForm.rows[0].field)
    render(true)
    check form == oldForm
    check scope == oldScope
    owner.text <- "before replacement"
    render(false)
    discard drainMainThreadWork()
    check oldField.stringValue == "initial"
    expect ValueError:
      oldForm.bindTextField(
        "text", owner.text, owner, 0, readOwnedText, oldField, editOwnedText
      )

    render(true)
    check form != oldForm
    check scope != oldScope
    let field = TextField(form.rows[0].field)
    field.stringValue = "edit"
    check owner.text{} == "edit"
    owner.text <- "queued before release"
    host = nil
    discard drainMainThreadWork()
    check field.stringValue == "edit"
    check not scope.isActive
    expect ValueError:
      form.bindTextField(
        "text", owner.text, owner, 0, readOwnedText, field, editOwnedText
      )
    field.stringValue = "late edit"
    check owner.text{} == "queued before release"

  test "a retained node cannot bind after its session expires":
    let owner = TextOwner(text: newSigil("initial"))
    initResponder(owner)
    let host = newStackView()
    var session = newDirectViewSession(host)
    let root = session.beginUpdate()
    let node = root.child(
      "field",
      "textfield",
      proc(): TextField =
        newTextField(""),
    )
    let field = TextField(node.view)
    field.bindTextField(
      "text", owner.text, owner, 0, readOwnedText, field, editOwnedText
    )
    session.endUpdate()
    check field.stringValue == "initial"

    session = nil
    check host.arrangedSubviews[0] == field
    check not node.bindingScope.isActive
    expect ValueError:
      field.bindTextField(
        "text", owner.text, owner, 0, readOwnedText, field, editOwnedText
      )
    owner.text <- "after release"
    discard drainMainThreadWork()
    check field.stringValue == "initial"

  test "a named button handler keeps its receiver weak":
    proc countClick(button: Button, owner: DirectController) =
      button.title = "Clicked"
      inc owner.calls

    var observed: BackRef[DirectController]
    let session = newDirectViewSession(newStackView())
    var button: Button
    block:
      let owner = DirectController()
      initResponder(owner)
      observed.target = owner
      session.viewBody:
        Button:
          this.onAction(owner, countClick)
      button = Button(session.host.arrangedSubviews[0])
      discard button.send(performClick(), ActionArgs(sender: button))
      check button.title == "Clicked"
      check owner.calls == 1
    check observed.isNil
    button.title = "Released"
    discard button.send(performClick(), ActionArgs(sender: button))
    check button.title == "Released"
    session.close()

  test "detached builders yield fresh Dragology geometry without live effects":
    let owner = DirectController()
    initResponder(owner)
    let model = DirectBindingModel(value: 7)
    initResponder(model)
    proc build(ids: seq[string]): View =
      let session = newDirectViewSession(newStackView(), detached = true)
      session.viewBody:
        VStack:
          for id in ids:
            keyed(id):
              HStack:
                this.identifier = id
                this{vpDraggable} = true
                TextField:
                  this.identifier = "field-" & id
                  this.bindValue(
                    "value", model, directChanged, model, 0, readDirect, writeDirect
                  )
                Button:
                  this.identifier = "button-" & id
                  this.title = "Preview"
                  this.onAction(owner) do(this: Button, receiver: DirectController):
                    inc receiver.calls
      session.takeDetachedRoot()

    let first = build(@["a", "b"])
    let second = build(@["b", "a"])
    check first.viewWithIdentifier("a") != second.viewWithIdentifier("a")
    check model.subcriptions.len == 0
    let button = Button(first.viewWithIdentifier("button-a"))
    discard button.send(performClick(), ActionArgs(sender: button))
    check owner.calls == 0
    model.value = 8
    emit model.directChanged(0)
    check TextField(first.viewWithIdentifier("field-a")).stringValue == "7"
    let env =
      DragEnvironment(bounds: rect(0, 0, 400, 180), appearance: initAppearance())
    let before = captureDragPreview(first, env)
    let after = captureDragPreview(second, env)
    check before.elements.len == 2
    check after.elements.len == 2
    check before.elements[before.find("a")].frame.origin.y <
      before.elements[before.find("b")].frame.origin.y
    check after.elements[after.find("b")].frame.origin.y <
      after.elements[after.find("a")].frame.origin.y

suite "direct collection rows":
  test "rows are materialized half a viewport above and below the viewport":
    var items: seq[ModelItem]
    for i in 0 ..< 100:
      items.add modelItem($i, title = "row " & $i, objectValue = toObj($i))
    let controller = newArrayController(items)
    let collection = newCollectionView(frame = rect(0, 0, 240, 90))
    collection.collectionLayout = newCollectionViewLayout(
      clkList,
      itemSize = initSize(200, 30),
      minimumLineSpacing = 0,
      edgeInsets = insets(0),
    )
    let rows = newCollectionRows(
      collection,
      controller,
      proc(row: DirectView, controller: ArrayController, id: string) =
        row.viewBody:
          Label:
            this.stringValue = controller.itemWithIdentifier(id).title,
    )
    defer:
      rows.close()
    discard buildRenders(collection)
    check collection.visibleItemIndexes == @[0, 1, 2]
    check collection.materializationItemIndexes == @[0, 1, 2, 3, 4]
    check collection.itemViewAtIndex(4) != nil
    check collection.itemViewAtIndex(5).isNil
    collection.scrollView.contentOffset = initPoint(0, 300)
    discard buildRenders(collection)
    check collection.visibleItemIndexes == @[10, 11, 12]
    check collection.materializationItemIndexes == @[8, 9, 10, 11, 12, 13, 14]
    check collection.itemViewAtIndex(7).isNil
    check collection.itemViewAtIndex(8) != nil
    check collection.itemViewAtIndex(14) != nil
    check collection.itemViewAtIndex(15).isNil
    let buffered = collection.itemViewAtIndex(14)
    collection.scrollView.contentOffset = initPoint(0, 360)
    discard buildRenders(collection)
    check collection.itemViewAtIndex(14) == buffered
    check collection.visibleItemViews.len == collection.materializationItemIndexes.len

  test "editing rows survive viewport eviction and model reorder, then retire on deletion":
    var items: seq[ModelItem]
    for i in 0 ..< 100:
      items.add modelItem($i, title = "row " & $i, objectValue = toObj("row " & $i))
    let controller = newArrayController(items)
    let collection = newCollectionView(frame = rect(0, 0, 240, 100))
    collection.collectionLayout = newCollectionViewLayout(
      clkList,
      itemSize = initSize(200, 30),
      minimumLineSpacing = 0,
      edgeInsets = insets(0),
    )
    let rows = newCollectionRows(
      collection,
      controller,
      proc(row: DirectView, controller: ArrayController, id: string) =
        row.viewBody:
          TextField:
            this.patchText(controller.itemWithIdentifier(id).title),
    )
    let window = newWindow("Virtual rows", frame = rect(0, 0, 240, 100))
    window.setContentView(collection)
    defer:
      rows.close()
      window.close()
    discard window.buildRenders()
    let row = DirectView(collection.itemViewAtIndex(0))
    require not row.isNil
    let field = TextField(row.arrangedSubviews[0])
    require window.makeFirstResponder(field)
    let editor = TextView(field.currentEditor)
    editor.selectedRange = initTextRange(1, 2)
    editor.setMarkedTextValue("xy", initTextRange(1, 0), initTextRange(-1, 0))
    let selection = editor.selectedRange
    let text = editor.stringValue
    let marked = editor.markedRange
    collection.scrollView.contentOffset = initPoint(0, 900)
    discard window.buildRenders()
    check collection.itemViewAtIndex(0) == row
    check not collection.itemViewAtIndex(30).isNil
    check collection.visibleItemViews.len <=
      collection.materializationItemIndexes.len + 1
    check field.currentEditor == editor
    check editor.selectedRange == selection
    check editor.markedRange == marked
    check editor.stringValue == text

    controller.insertItem(modelItem("new", objectValue = toObj("new")), 0)
    rows.flushBindings()
    check collection.itemViewAtIndex(1) == row
    check field.currentEditor == editor
    check editor.stringValue == text
    check controller.moveItem("0", 2)
    rows.flushBindings()
    check collection.itemViewAtIndex(2) == row
    check field.currentEditor == editor
    check editor.selectedRange == selection
    check editor.markedRange == marked
    collection.scrollView.contentOffset = initPoint(0, 0)
    discard window.buildRenders()
    check collection.itemViewAtIndex(2) == row
    check field.currentEditor == editor
    check editor.stringValue == text
    collection.scrollView.contentOffset = initPoint(0, 900)
    discard window.buildRenders()
    check controller.removeItem("0")
    check field.currentEditor.isNil
    controller.insertItem(
      modelItem("0", title = "replacement", objectValue = toObj("replacement")), 0
    )
    rows.flushBindings()
    check field.currentEditor.isNil
    check not row.containsView(field)
    check collection.visibleItemViews.len <= collection.materializationItemIndexes.len

  test "reused hosts retire old actions and synchronize selection":
    var items: seq[ModelItem]
    for i in 0 ..< 40:
      items.add modelItem($i, title = "row " & $i, objectValue = toObj($i))
    let controller = newArrayController(items)
    let owner = DirectController()
    let model = DirectBindingModel(value: 1)
    initResponder(owner)
    initResponder(model)
    let collection = newCollectionView(frame = rect(0, 0, 240, 90))
    collection.collectionLayout = newCollectionViewLayout(
      clkList,
      itemSize = initSize(200, 30),
      minimumLineSpacing = 0,
      edgeInsets = insets(0),
    )
    let rows = newCollectionRows(
      collection,
      controller,
      proc(row: DirectView, controller: ArrayController, id: string) =
        row.viewBody:
          VStack:
            TextField:
              this.bindValue(
                "value",
                model,
                directChanged,
                model,
                0,
                readDirect,
                writeDirect,
                initialApply = true,
              )
            Button:
              this.title = controller.itemWithIdentifier(id).title
              this.onAction(owner, id) do(
                this: Button, receiver: DirectController, key: string
              ):
                inc receiver.calls
      ,
    )
    defer:
      rows.close()
    discard buildRenders(collection)
    let firstRow = DirectView(collection.itemViewAtIndex(0))
    let contents = StackView(firstRow.arrangedSubviews[0])
    let oldField = TextField(contents.arrangedSubviews[0])
    let oldButton = Button(contents.arrangedSubviews[1])
    collection.selectedIndex = 0
    check controller.selectionController.selectedIdentifier == "0"
    model.value = 2
    emit model.directChanged(0)
    collection.scrollView.contentOffset = initPoint(0, 600)
    discard buildRenders(collection)
    check not collection.itemViewAtIndex(20).isNil
    check firstRow in collection.visibleItemViews
    check firstRow.accessibilityLabel() ==
      controller.itemWithIdentifier(firstRow.accessibilityIdentifier).title
    discard drainMainThreadWork()
    check oldField.stringValue == "1"
    model.value = 3
    emit model.directChanged(0)
    discard drainMainThreadWork()
    check oldField.stringValue == "1"
    discard oldButton.send(performClick(), ActionArgs(sender: oldButton))
    check owner.calls == 0
    check collection.itemViewAtIndex(0).isNil
    check collection.visibleItemViews.len <= collection.materializationItemIndexes.len
    controller.selectionController.setSelectedIdentifiers(["25"])
    rows.flushBindings()
    check collection.selectedIdentifier == "25"
    rows.close()
    check firstRow.arrangedSubviews.len == 0

  test "programmatic selection preserves editing and pointer selection transfers focus":
    var items: seq[ModelItem]
    for index in 0 ..< 50:
      items.add modelItem($index, title = "row " & $index, objectValue = toObj($index))
    let controller = newArrayController(items)
    let owner = TextOwner(text: newSigil("alpha"))
    initResponder(owner)
    let collection = newCollectionView(frame = rect(0, 0, 240, 100))
    collection.collectionLayout = newCollectionViewLayout(
      clkList,
      itemSize = initSize(200, 30),
      minimumLineSpacing = 0,
      edgeInsets = insets(0),
    )
    let rows = newCollectionRows(
      collection,
      controller,
      proc(row: DirectView, controller: ArrayController, id: string) =
        row.viewBody:
          if id == "0":
            TextField:
              this.bindTextField(
                "text", owner.text, owner, 0, readOwnedText, editOwnedText
              )
          else:
            Label:
              this.stringValue = controller.itemWithIdentifier(id).title,
    )
    let window = newWindow("Selection while editing", frame = rect(0, 0, 240, 100))
    window.setContentView(collection)
    defer:
      rows.close()
      window.close()
    discard window.buildRenders()
    let row = DirectView(collection.itemViewAtIndex(0))
    require not row.isNil
    let field = TextField(row.arrangedSubviews[0])
    require window.makeFirstResponder(field)
    let editor = TextView(field.currentEditor)
    editor.selectedRange = initTextRange(1, 2)
    editor.setMarkedTextValue("xy", initTextRange(1, 0), initTextRange(-1, 0))
    require editor.hasMarkedText
    let
      selection = editor.selectedRange
      marked = editor.markedRange
      text = editor.stringValue
      modelText = owner.text{}
      edits = owner.edits

    proc checkEditor() =
      check collection.itemViewAtIndex(0) == row
      check field.currentEditor == editor
      check window.firstResponder == editor
      check editor.hasMarkedText
      check editor.markedRange == marked
      check editor.selectedRange == selection
      check editor.stringValue == text
      check owner.text{} == modelText
      check owner.edits == edits
      check collection.visibleItemViews.len <=
        collection.materializationItemIndexes.len + 1

    collection.selectItemAtIndex(1)
    rows.flushBindings()
    check collection.selectedIdentifier == "1"
    check controller.selectionController.selectedIdentifier == "1"
    checkEditor()

    controller.selectionController.setSelectedIdentifiers(["30"])
    rows.flushBindings()
    check collection.selectedIdentifier == "30"
    check collection.scrollView.contentOffset.y > 0
    check not collection.itemViewAtIndex(30).isNil
    checkEditor()

    collection.selectItemAtIndex(32)
    rows.flushBindings()
    check collection.selectedIdentifier == "32"
    check controller.selectionController.selectedIdentifier == "32"
    checkEditor()

    collection.selectItemAtIndex(0)
    rows.flushBindings()
    check collection.selectedIdentifier == "0"
    check controller.selectionController.selectedIdentifier == "0"
    check collection.itemViewAtIndex(0) == row
    checkEditor()

    # Selecting a row with the pointer deliberately transfers focus out of the editor.
    let itemRect = collection.collectionItemRect(1)
    require not itemRect.isEmpty
    let point = collection.pointToWindow(
      initPoint(
        itemRect.origin.x + itemRect.size.width / 2,
        itemRect.origin.y + itemRect.size.height / 2,
      )
    )
    require window.mouseDownAt(point)
    require window.mouseUpAt(point)
    check collection.selectedIdentifier == "1"
    check controller.selectionController.selectedIdentifier == "1"
    check window.firstResponder == collection
    check field.currentEditor.isNil
