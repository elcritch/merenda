import std/unittest
import sigils/core
import sigils/reactive
import merenda/nimkit/foundation/mainthreadwork
import merenda/nimkit
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

proc readOwnedText(owner: TextOwner, context: int): string =
  owner.text{}

proc editOwnedText(owner: TextOwner, context: int, value: string) =
  inc owner.edits
  owner.text <- value

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
      onAction(owner, value) do(
        receiver: DirectController, count: int, sender: DynamicAgent
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
          onAction(owner, reads) do(
            receiver: DirectController, count: int, sender: DynamicAgent
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

  test "named text preserves drafts on unchanged input and applies new model text":
    let host = newDirectView()
    var value = "Model"
    proc render() =
      host.viewBody:
        TextField(stringValue = value)

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
            this.stringValue = authored
          elif mode == 1:
            bindingScope.bindTextField(
              "text", owner.text, owner, 0, readOwnedText, this, editOwnedText
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
            bindingScope.bindTextField(
              "text", owner.text, owner, 0, readOwnedText, this, editOwnedText
            )
          else:
            this.stringValue = "plain"

    render()
    let field = TextField(host.arrangedSubviews[0])
    owner.text <- "queued"
    bound = false
    render()
    discard drainMainThreadWork()
    check field.stringValue == "plain"
    check owner.text{} == "queued"
    check owner.edits == 0

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
                this.stringValue = id

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
                this.stringValue = id
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
          onAction(owner, amount) do(
            receiver: DirectController, value: int, sender: DynamicAgent
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
                this.stringValue = id & "lpha"

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
              this.stringValue = "replacement"

    render()
    let old = session.host.arrangedSubviews[0]
    check old of CustomDirectView
    custom = false
    render()
    check session.host.arrangedSubviews[0] of TextField
    check old.superview.isNil
    session.close()

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
          onChange(owner) do(receiver: DirectController, sender: DynamicAgent):
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
            onAction(owner) do(receiver: DirectController, sender: DynamicAgent):
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
    proc render() =
      session.viewBody:
        if visible:
          keyed("field"):
            TextField:
              bindingScope.bindValue(
                "value", model, directChanged, model, 0, readDirect, this, writeDirect
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

  test "an expired explicit receiver does not invoke a handler":
    var observed: BackRef[DirectController]
    let session = newDirectViewSession(newStackView())
    var button: Button
    block:
      let owner = DirectController()
      initResponder(owner)
      observed.target = owner
      session.viewBody:
        Button:
          onAction(owner) do(receiver: DirectController, sender: DynamicAgent):
            inc receiver.calls
      button = Button(session.host.arrangedSubviews[0])
      discard button.send(performClick(), ActionArgs(sender: button))
      check owner.calls == 1
    check observed.isNil
    discard button.send(performClick(), ActionArgs(sender: button))
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
                this[vpDraggable] = true
                TextField:
                  this.identifier = "field-" & id
                  bindingScope.bindValue(
                    "value", model, directChanged, model, 0, readDirect, this,
                    writeDirect,
                  )
                Button:
                  this.identifier = "button-" & id
                  this.title = "Preview"
                  onAction(owner) do(receiver: DirectController, sender: DynamicAgent):
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
