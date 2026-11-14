## Scope-owned value bindings. All operations run on the owning GUI thread.
import std/tables
import sigils/[core, reactive, selectors]
import ../responder/responders
import ../foundation/mainthreadwork
import ../text/textfields
import ../app/collectionsigils

type
  BindingScope* = ref object of Responder
    bindings: Table[string, Binding]
    preview: bool
    disposed: bool
    schedule: proc() {.closure.}
    collecting, scheduled: bool
    ticket: uint64
    seen: Table[string, bool]

  Binding = ref object of Responder
    scope: BackRef[BindingScope]
    active, pending, needsConnect, updating: bool
    applyValue: proc(binding: Binding) {.nimcall.}
    editor: EditBinding
    disconnectEditor: proc(binding: Binding) {.closure.}
    generation: uint64
    sourceKey: pointer
    signalKey: string
    disconnectSource: proc(binding: Binding) {.closure.}

  EditBinding = ref object of Responder
    owner: BackRef[Binding]
    invoke: proc(editor: EditBinding) {.nimcall.}

  TextEditBinding[R, C] = ref object of EditBinding
    receiver: BackRef[R]
    field: BackRef[TextField]
    context: C
    edit: proc(receiver: R, context: C, text: string) {.nimcall.}

  ValueBinding[R, C, V, T] = ref object of Binding
    receiver: BackRef[R]
    target: BackRef[V]
    context: C
    getter: proc(receiver: R, context: C): T {.nimcall.}
    setter: proc(target: V, value: T) {.nimcall.}
    skipUnchanged, hasLast: bool
    lastValue: T

proc applyValue[R: Responder, C; V: Responder, T](base: Binding) =
  let binding = ValueBinding[R, C, V, T](base)
  let receiver = binding.receiver{}
  let target = binding.target{}
  if not receiver.isNil and not target.isNil:
    let generation = binding.generation
    let value = binding.getter(receiver, binding.context)
    if not binding.active or binding.generation != generation:
      return
    when compiles(value == binding.lastValue):
      if binding.skipUnchanged and binding.hasLast and value == binding.lastValue:
        return
    binding.lastValue = value
    binding.hasLast = true
    binding.updating = true
    try:
      binding.setter(target, value)
    finally:
      binding.updating = false

proc textEdited(editor: EditBinding, sender: DynamicAgent) {.slot.} =
  let owner = editor.owner{}
  if not owner.isNil and owner.active and not owner.updating:
    editor.invoke(editor)

proc invokeEdit[R: Responder, C](base: EditBinding) =
  let editor = TextEditBinding[R, C](base)
  let receiver = editor.receiver{}
  let field = editor.field{}
  if not receiver.isNil and not field.isNil:
    editor.edit(receiver, editor.context, field.stringValue)

proc setBoundText(field: TextField, value: string) {.nimcall.} =
  if field.stringValue != value:
    field.stringValue = value

proc newBindingScope*(preview = false): BindingScope =
  BindingScope(preview: preview)

proc onSchedule*(scope: BindingScope, callback: proc() {.closure.}) =
  ## Called on the GUI thread when the first pending update needs a flush.
  scope.schedule = callback

proc flushBindings*(scope: BindingScope)

proc invalidate(binding: Binding) {.slot.} =
  let scope = binding.scope{}
  if binding.active and not binding.pending and not scope.isNil and not scope.disposed:
    binding.pending = true
    if not scope.scheduled:
      scope.scheduled = true
      inc scope.ticket
      if not scope.schedule.isNil:
        scope.schedule()
      else:
        var weakScope: BackRef[BindingScope]
        weakScope.target = scope
        let ticket = scope.ticket
        scheduleMainThreadWork(
          proc(): bool =
            let current = weakScope{}
            if not current.isNil and not current.disposed and current.scheduled and
                current.ticket == ticket:
              current.flushBindings()
            false
        )

proc removeBinding*(scope: BindingScope, id: string)

proc beginBindings*(scope: BindingScope) =
  ## Mark registrations in this pass; endBindings removes omitted identities.
  scope.collecting = true
  scope.seen.clear()

proc endBindings*(scope: BindingScope) =
  if scope.collecting:
    scope.collecting = false
    var omitted: seq[string]
    for id in scope.bindings.keys:
      if not scope.seen.hasKey(id):
        omitted.add id
    for id in omitted:
      scope.removeBinding(id)

proc removeBinding*(scope: BindingScope, id: string) =
  if scope.bindings.hasKey(id):
    let binding = scope.bindings[id]
    binding.active = false
    if not binding.disconnectEditor.isNil:
      binding.disconnectEditor(binding)
      binding.disconnectEditor = nil
    binding.editor = nil
    binding.pending = false
    if not binding.disconnectSource.isNil:
      binding.disconnectSource(binding)
      binding.disconnectSource = nil
    binding.scope.clear()
    scope.bindings.del(id)

proc dispose*(scope: BindingScope) =
  if not scope.isNil and not scope.disposed:
    scope.disposed = true
    scope.scheduled = false
    inc scope.ticket
    var ids: seq[string]
    for id in scope.bindings.keys:
      ids.add id
    for id in ids:
      scope.removeBinding(id)
    scope.schedule = nil

proc flushBindings*(scope: BindingScope) =
  ## One pass: invalidations raised while applying wait for the next pass.
  if scope.isNil or scope.disposed:
    return
  scope.scheduled = false
  inc scope.ticket
  var pending: seq[tuple[binding: Binding, generation: uint64]]
  for binding in scope.bindings.values:
    if binding.pending:
      binding.pending = false
      pending.add (binding, binding.generation)
  for item in pending:
    if item.binding.active and item.binding.generation == item.generation:
      item.binding.applyValue(item.binding)

proc createValueBinding[R: Responder, C; V: Responder, T](
    scope: BindingScope,
    id: string,
    receiver: R,
    context: C,
    getter: proc(receiver: R, context: C): T {.nimcall.},
    target: V,
    setter: proc(target: V, value: T) {.nimcall.},
    sourceKey: pointer,
    signalKey: string,
    textBinding: bool,
): ValueBinding[R, C, V, T] =
  if scope.isNil or scope.disposed:
    raise newException(ValueError, "Binding scope is disposed")
  if scope.collecting:
    scope.seen[id] = true
  if scope.bindings.hasKey(id) and scope.bindings[id] of ValueBinding[R, C, V, T]:
    result = ValueBinding[R, C, V, T](scope.bindings[id])
    if result.sourceKey != sourceKey or result.signalKey != signalKey:
      result.hasLast = false
      if not result.disconnectSource.isNil:
        result.disconnectSource(result)
      result.disconnectSource = nil
      result.needsConnect = true
  else:
    scope.removeBinding(id)
    result = ValueBinding[R, C, V, T](active: true, needsConnect: true)
    result.scope.target = scope
    result.applyValue = applyValue[R, C, V, T]
    scope.bindings[id] = result
  inc result.generation
  if result.skipUnchanged != textBinding:
    if not result.disconnectEditor.isNil:
      result.disconnectEditor(result)
      result.disconnectEditor = nil
    result.editor = nil
    result.skipUnchanged = textBinding
    result.hasLast = false
  if result.getter != getter or result.setter != setter:
    result.hasLast = false
  if result.receiver{} != receiver or result.target{} != target:
    result.hasLast = false
  when compiles(result.context == context):
    if result.context != context:
      result.hasLast = false
  else:
    result.hasLast = false
  result.sourceKey = sourceKey
  result.signalKey = signalKey
  result.context = context
  result.getter = getter
  result.setter = setter
  result.receiver.target = receiver
  result.target.target = target
  result.pending = false

template bindValueImpl(
    scope: BindingScope,
    id: string,
    source: Responder,
    signal: untyped,
    receiver, context, getter, target, setter: untyped,
    initialApply: bool,
    textBinding: bool,
) =
  block:
    let binding = createValueBinding(
      scope,
      id,
      receiver,
      context,
      getter,
      target,
      setter,
      cast[pointer](source),
      astToStr(signal),
      textBinding,
    )
    if binding.needsConnect and not scope.preview and not source.isNil:
      proc makeDisconnect(input: typeof(source)): proc(owned: Binding) {.closure.} =
        var sourceRef: BackRef[typeof(source)]
        sourceRef{} = input
        result = proc(owned: Binding) =
          let current = sourceRef{}
          if not current.isNil:
            current.disconnect(signal, owned, invalidate)

      binding.needsConnect = false
      source.connect(signal, Binding(binding), invalidate, true)
      binding.disconnectSource = makeDisconnect(source)
    if initialApply:
      binding.applyValue(binding)

template bindValue*(
    scope: BindingScope,
    id: string,
    source: Responder,
    signal: untyped,
    receiver, context, getter, target, setter: untyped,
    initialApply: bool = true,
) =
  ## Replacing an ID disconnects its previous subscription before initial read.
  bindValueImpl(
    scope, id, source, signal, receiver, context, getter, target, setter, initialApply,
    false,
  )

template bindSigilValueImpl(
    scope: BindingScope,
    id: string,
    source: untyped,
    receiver, context, getter, target, setter: untyped,
    initialApply, textBinding: bool,
) =
  ## Explicit fixed Sigil input; rebind to replace its subscription.
  block:
    let binding = createValueBinding(
      scope,
      id,
      receiver,
      context,
      getter,
      target,
      setter,
      cast[pointer](source),
      "sigil.change",
      textBinding,
    )
    if binding.needsConnect and not scope.preview and not source.isNil:
      proc makeDisconnect(input: typeof(source)): proc(owned: Binding) {.closure.} =
        result = proc(owned: Binding) =
          input.disconnect(change, owned, invalidate)

      binding.needsConnect = false
      source.connect(change, Binding(binding), invalidate, true)
      binding.disconnectSource = makeDisconnect(source)
    if initialApply:
      binding.applyValue(binding)

template bindSigilValue*(
    scope: BindingScope,
    id: string,
    source: untyped,
    receiver, context, getter, target, setter: untyped,
    initialApply: bool = true,
) =
  ## Observe an explicit Sigil input with a weak receiver and value context.
  bindSigilValueImpl(
    scope, id, source, receiver, context, getter, target, setter, initialApply, false
  )

proc hasPendingBindings*(scope: BindingScope): bool =
  if not scope.isNil and not scope.disposed:
    for binding in scope.bindings.values:
      if binding.pending:
        return true

proc bindValue*[T; V: Responder](
    scope: BindingScope,
    id: string,
    input: Sigil[T],
    target: V,
    apply: proc(target: V, value: T) {.nimcall.},
) =
  ## Bind a Sigil directly to a weak widget target. The scope retains the input;
  ## callers need no extra receiver, context, or forwarding getter.
  proc readInput(target: V, input: Sigil[T]): T {.nimcall.} =
    unBindSigilEvents:
      result = input{}

  bindSigilValue(scope, id, input, target, input, readInput, target, apply)

proc bindValue*[T; V: Responder](
    scope: BindingScope,
    id: string,
    input: CollectionValue[T],
    target: V,
    apply: proc(target: V, value: T) {.nimcall.},
) =
  ## Read-only collection projection, sharing the normal binding lifetime.
  proc readInput(target: V, input: CollectionValue[T]): T {.nimcall.} =
    input.snapshot()

  bindSigilValue(scope, id, input, target, input, readInput, target, apply)

proc bindValue*[K, T; V: Responder](
    scope: BindingScope,
    id: string,
    input: CollectionSigil[K, T],
    target: V,
    apply: proc(target: V, value: seq[T]) {.nimcall.},
) =
  proc readInput(target: V, input: CollectionSigil[K, T]): seq[T] {.nimcall.} =
    input.snapshot()

  bindSigilValue(scope, id, input, target, input, readInput, target, apply)

proc installTextEdit[R: Responder, C](
    binding: ValueBinding[R, C, TextField, string],
    receiver: R,
    context: C,
    field: TextField,
    edit: proc(receiver: R, context: C, text: string) {.nimcall.},
) =
  binding.skipUnchanged = true
  var editor: TextEditBinding[R, C]
  if not binding.editor.isNil:
    editor = TextEditBinding[R, C](binding.editor)
    if editor.field{} != field:
      if not binding.disconnectEditor.isNil:
        binding.disconnectEditor(binding)
      binding.editor = nil
      editor = nil
  if editor.isNil:
    editor = TextEditBinding[R, C](invoke: invokeEdit[R, C])
    editor.owner.target = binding
    editor.field.target = field
    binding.editor = editor
    var fieldRef: BackRef[TextField]
    fieldRef.target = field
    binding.disconnectEditor = proc(owned: Binding) =
      let current = fieldRef{}
      if not current.isNil and not owned.editor.isNil:
        current.disconnect(textDidChange, owned.editor, textEdited)
    field.connect(textDidChange, EditBinding(editor), textEdited)
  editor.receiver.target = receiver
  editor.context = context
  editor.edit = edit

template bindTextField*(
    scope: BindingScope,
    id: string,
    source: Responder,
    signal: untyped,
    receiver, context, getter, field, edit: untyped,
) =
  ## The edit callback performs controller validation, undo, and model mutation.
  block:
    bindValueImpl(
      scope, id, source, signal, receiver, context, getter, field, setBoundText, false,
      true,
    )
    let binding = ValueBinding[typeof(receiver), typeof(context), TextField, string](
      scope.bindings[id]
    )
    if not scope.preview:
      installTextEdit(binding, receiver, context, field, edit)
    else:
      binding.skipUnchanged = true
    binding.applyValue(binding)

template bindTextField*(
    scope: BindingScope,
    id: string,
    controller: Responder,
    signal: untyped,
    context, getter, field, edit: untyped,
) =
  ## Common MVC case: the controller both emits changes and owns edit commands.
  bindTextField(scope, id, controller, signal, controller, context, getter, field, edit)

template bindTextField*[T](
    scope: BindingScope,
    id: string,
    input: Sigil[T],
    receiver, context, getter, field, edit: untyped,
) =
  ## Observe a Sigil snapshot while routing edits through a weak controller.
  block:
    bindSigilValueImpl(
      scope, id, input, receiver, context, getter, field, setBoundText, false, true
    )
    let binding = ValueBinding[typeof(receiver), typeof(context), TextField, string](
      scope.bindings[id]
    )
    if not scope.preview:
      installTextEdit(binding, receiver, context, field, edit)
    binding.applyValue(binding)
