import std/unittest
import sigils/[core, reactive]
import merenda/nimkit/directviews/bindings
import merenda/nimkit/responder/responders
import merenda/nimkit/foundation/mainthreadwork
import merenda/nimkit/text/textfields

type Model = ref object of Responder
  value: int
  text: string
  edits: int
  observable: Sigil[int]
  triggerOnRead: bool
  sourceReads: int

type Target = ref object of Responder
  value: int
  writes: int

proc changed(model: Model, value: int) {.signal.}
proc readValue(model: Model, context: int): int =
  model.value + context

proc writeValue(target: Target, value: int) =
  target.value = value
  inc target.writes

proc readObservable(model: Model, context: int): int =
  model.observable{} + context

proc observableInput(model: Model): Sigil[int] =
  inc model.sourceReads
  model.observable

proc readText(model: Model, context: int): string =
  model.text

proc editText(model: Model, context: int, text: string) =
  inc model.edits
  discard text

proc readThenNotify(model: Model, context: int): int =
  result = model.value
  if model.triggerOnRead:
    model.triggerOnRead = false
    inc model.value
    emit model.changed(0)

proc readAlternateText(model: Model, context: int): string =
  model.text

proc writeText(field: TextField, text: string) =
  field.stringValue = text

suite "direct owned bindings":
  test "binding source expressions are evaluated once per registration":
    let model = Model(observable: newSigil(1))
    let target = Target()
    let scope = newBindingScope()
    defer:
      scope.dispose()
    scope.bindSigilValue(
      "value", model.observableInput(), model, 0, readObservable, target, writeValue
    )
    check model.sourceReads == 1
    model.observable <- 2
    discard drainMainThreadWork()
    check target.value == 2
    check model.sourceReads == 1
  test "direct Sigil binding switches inputs and keeps its widget weak":
    let first = newSigil(1)
    let second = newSigil(4)
    let scope = newBindingScope()
    var target = Target()
    proc show(target: Target, value: int) =
      target.value = value

    scope.bindValue("value", first, target, show)
    check target.value == 1
    first <- 3
    discard drainMainThreadWork()
    check target.value == 3
    scope.bindValue("value", second, target, show)
    check first.subcriptions.len == 0
    check second.subcriptions.len == 1
    check target.value == 4
    var weakTarget: BackRef[Target]
    weakTarget.target = target
    target = nil
    check weakTarget.isNil
    second <- 7
    discard drainMainThreadWork()
    scope.dispose()
    check second.subcriptions.len == 0

  test "coalesces, rebinds sources and tears down queued work":
    let a = Model(value: 1)
    let b = Model(value: 5)
    let target = Target()
    let scope = newBindingScope()
    scope.bindValue("value", a, changed, a, 2, readValue, target, writeValue)
    check target.value == 3
    for i in 0 ..< 20:
      scope.bindValue("value", a, changed, a, 2, readValue, target, writeValue)
      check a.subcriptions.len == 1
    let initialWrites = target.writes
    a.value = 4
    emit a.changed(0)
    emit a.changed(0)
    check scope.hasPendingBindings
    scope.flushBindings()
    check target.value == 6
    check target.writes == initialWrites + 1
    scope.bindValue("value", b, changed, b, 3, readValue, target, writeValue)
    check target.value == 8
    check a.subcriptions.len == 0
    check b.subcriptions.len == 1
    emit a.changed(0)
    check not scope.hasPendingBindings
    b.value = 9
    emit b.changed(0)
    scope.dispose()
    discard drainMainThreadWork()
    check target.value == 8

  test "preview and omitted bindings do not subscribe":
    let model = Model(value: 2)
    let target = Target()
    let preview = newBindingScope(preview = true)
    preview.bindValue("value", model, changed, model, 0, readValue, target, writeValue)
    check target.value == 2
    emit model.changed(0)
    check not preview.hasPendingBindings
    preview.dispose()
    let scope = newBindingScope()
    scope.bindValue("value", model, changed, model, 0, readValue, target, writeValue)
    scope.beginBindings()
    scope.endBindings()
    emit model.changed(0)
    check not scope.hasPendingBindings
    scope.dispose()

  test "text changes use controller and unrelated notifications preserve edits":
    let model = Model(text: "initial")
    let field = newTextField()
    let scope = newBindingScope()
    scope.bindTextField("text", model, changed, model, 0, readText, field, editText)
    check field.stringValue == "initial"
    field.stringValue = "provisional"
    emit model.changed(0)
    scope.flushBindings()
    check field.stringValue == "provisional"
    model.text = "external"
    emit model.changed(0)
    scope.flushBindings()
    check field.stringValue == "external"
    check model.edits == 1
    scope.dispose()

  test "Sigil subscriptions switch without accumulating observers":
    let first = newSigil(1)
    let second = newSigil(4)
    let model = Model(observable: first)
    let target = Target()
    let scope = newBindingScope()
    for i in 0 ..< 20:
      model.observable = if i mod 2 == 0: first else: second
      scope.bindSigilValue(
        "counter", model.observable, model, 0, readObservable, target, writeValue
      )
      check first.subcriptions.len + second.subcriptions.len == 1
    first <- 8
    check not scope.hasPendingBindings
    second <- 9
    check scope.hasPendingBindings
    discard drainMainThreadWork()
    check target.value == 9
    scope.dispose()
    check first.subcriptions.len + second.subcriptions.len == 0

  test "released receivers and scopes are not kept alive":
    var model = Model(value: 2)
    let source = Model()
    let target = Target()
    var weakModel: BackRef[Model]
    weakModel.target = model
    var scope = newBindingScope()
    scope.bindValue("value", source, changed, model, 0, readValue, target, writeValue)
    model = nil
    check weakModel.isNil
    emit source.changed(0)
    scope.flushBindings()
    check target.writes == 1
    var weakScope: BackRef[BindingScope]
    weakScope.target = scope
    scope = nil
    check weakScope.isNil
    emit source.changed(0)
    discard drainMainThreadWork()

  test "initial reads observe synchronous source invalidations":
    let model = Model(value: 1, triggerOnRead: true)
    let target = Target()
    let scope = newBindingScope()
    scope.bindValue(
      "value", model, changed, model, 0, readThenNotify, target, writeValue
    )
    check target.value == 1
    check scope.hasPendingBindings
    scope.flushBindings()
    check target.value == 2
    scope.dispose()

  test "switching a text ID to a generic binding removes its editor policy":
    let model = Model(text: "first")
    let field = newTextField()
    let scope = newBindingScope()
    scope.bindTextField("text", model, changed, model, 0, readText, field, editText)
    scope.bindValue("text", model, changed, model, 0, readText, field, writeText)
    let edits = model.edits
    field.stringValue = "local"
    check model.edits == edits
    emit model.changed(0)
    scope.flushBindings()
    check field.stringValue == "first"
    scope.dispose()

  test "changing text getters refreshes equal cached model values":
    let model = Model(text: "first")
    let field = newTextField()
    let scope = newBindingScope()
    scope.bindTextField("text", model, changed, model, 0, readText, field, editText)
    field.stringValue = "local"
    scope.bindTextField(
      "text", model, changed, model, 0, readAlternateText, field, editText
    )
    check field.stringValue == "first"
    scope.dispose()

  test "dropping a text scope leaves the retained field inert":
    let model = Model(text: "first")
    let field = newTextField()
    var scope = newBindingScope()
    scope.bindTextField("text", model, changed, model, 0, readText, field, editText)
    scope = nil
    field.stringValue = "local"
    check model.edits == 0
