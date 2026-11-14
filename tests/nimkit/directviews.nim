import std/unittest
import sigils/core
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

  CustomDirectView = ref object of View

proc directChanged(model: DirectBindingModel, value: int) {.signal.}
proc readDirect(model: DirectBindingModel, context: int): int =
  model.value

proc writeDirect(field: TextField, value: int) =
  field.stringValue = $value

proc newCustomDirectView(): CustomDirectView =
  result = CustomDirectView()
  initViewFields(result)

suite "direct view composition":
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
      Label:
        this.stringValue = "preview"
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
