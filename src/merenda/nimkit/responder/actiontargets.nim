## Action receivers with explicit weak or retained ownership.

import std/macros
import ../../foundation/backrefs
import ./responders
import ../core/selectors

type
  ActionProc* = proc(sender: DynamicAgent) {.closure.}

  ActionAdapter* = ref object of Responder
    ## An action adapter explicitly owned by its control or item model.

  ClosureTarget* = ref object of ActionAdapter
    callback: ActionProc

  ReceiverActionTarget[T] = ref object of ActionAdapter
    receiver: BackRef[T]
    handler: proc(receiver: T, sender: DynamicAgent) {.nimcall.}

  ContextActionTarget[T, C] = ref object of ActionAdapter
    receiver: BackRef[T]
    context: C
    handler: proc(receiver: T, context: C, sender: DynamicAgent) {.nimcall.}

  ActionTargetKind = enum
    atkWeak
    atkOwned

  ActionTarget* = object
    ## Copies preserve receiver identity and the selected ownership policy.
    case kind: ActionTargetKind
    of atkWeak:
      reference: BackRef[Responder]
    of atkOwned:
      owner: Responder

proc `{}`*(target: ActionTarget): Responder =
  case target.kind
  of atkWeak:
    target.reference{}
  of atkOwned:
    target.owner

proc `{}=`*(storage: var ActionTarget, target: DynamicAgent) =
  var reference: BackRef[Responder]
  if storage.kind == atkWeak:
    reference = storage.reference
  reference{} = target
  storage = ActionTarget(kind: atkWeak, reference: reference)

proc `{}=`*(storage: var ActionTarget, target: Responder) =
  storage{} = asDynamicAgent(target)

proc setRetainedTarget*(storage: var ActionTarget, target: DynamicAgent) =
  ## Explicit retained assignment, also used by the action-cell adapter API.
  if target.isNil:
    storage = ActionTarget()
  elif target of Responder:
    storage = ActionTarget(kind: atkOwned, owner: Responder(target))
  else:
    raise newException(ValueError, "Action target must be a Responder")

proc `{}=`*(storage: var ActionTarget, target: ClosureTarget) =
  storage.setRetainedTarget(asDynamicAgent(target))

proc `{}=`*(storage: var ActionTarget, target: ActionAdapter) =
  storage.setRetainedTarget(asDynamicAgent(target))

proc `{}=`*(storage: var ActionTarget, target: typeof(nil)) =
  storage = ActionTarget()

proc retainedTarget*(storage: ActionTarget): DynamicAgent =
  if storage.kind == atkOwned:
    result = asDynamicAgent(storage.owner)

proc invokeClosureTarget(self: DynamicAgent, invocation: var Invocation) =
  let target = ClosureTarget(self)
  let args = invocation.argsAs(ActionArgs)
  if not target.callback.isNil:
    target.callback(args.sender)
  invocation.setResult(())

proc newActionTarget*(action: ActionSelector, callback: ActionProc): ClosureTarget =
  result = ClosureTarget(callback: callback)
  initResponder(result)
  discard result.replaceMethod(action, DynamicMethod(invokeClosureTarget))

proc invokeReceiverAction[T: Responder](
    self: DynamicAgent, invocation: var Invocation
) =
  let adapter = ReceiverActionTarget[T](self)
  let receiver = adapter.receiver{}
  invocation.setResult(())
  if not receiver.isNil and not adapter.handler.isNil:
    adapter.handler(receiver, invocation.argsAs(ActionArgs).sender)

proc newReceiverActionTarget[T: Responder](
    action: ActionSelector,
    receiver: T,
    handler: proc(receiver: T, sender: DynamicAgent) {.nimcall.},
): ActionAdapter =
  ## Retain a non-capturing handler and track its receiver without owning it.
  let adapter = ReceiverActionTarget[T](handler: handler)
  initResponder(adapter)
  adapter.receiver.target = receiver
  discard adapter.replaceMethod(action, DynamicMethod(invokeReceiverAction[T]))
  result = adapter

proc nonCapturingHandler(handler: NimNode): NimNode =
  let callback = handler.copyNimTree()
  if callback.kind in {nnkDo, nnkLambda, nnkProcDef}:
    if callback.pragma.kind == nnkEmpty:
      callback.pragma = newNimNode(nnkPragma)
    var hasNimcall = false
    for pragma in callback.pragma:
      if pragma.eqIdent("closure"):
        error("Action handlers must be non-capturing nimcall procs", callback)
      if pragma.eqIdent("nimcall"):
        hasNimcall = true
    if not hasNimcall:
      callback.pragma.add ident("nimcall")
  callback

proc invokeContextAction[T: Responder, C](
    self: DynamicAgent, invocation: var Invocation
) =
  let adapter = ContextActionTarget[T, C](self)
  let receiver = adapter.receiver{}
  invocation.setResult(())
  if not receiver.isNil and not adapter.handler.isNil:
    adapter.handler(receiver, adapter.context, invocation.argsAs(ActionArgs).sender)

proc newContextActionTarget[T: Responder, C](
    action: ActionSelector,
    receiver: T,
    context: C,
    handler: proc(receiver: T, context: C, sender: DynamicAgent) {.nimcall.},
): ActionAdapter =
  let adapter = ContextActionTarget[T, C](context: context, handler: handler)
  initResponder(adapter)
  adapter.receiver.target = receiver
  discard adapter.replaceMethod(action, DynamicMethod(invokeContextAction[T, C]))
  result = adapter

type MissingActionArgument = object

# Nim 2.2 can type an inline callback as a closure when these forms are
# separate macro overloads, before the macro can mark it nimcall.
macro newActionTarget*(
    action: ActionSelector,
    receiver: Responder,
    context: untyped = MissingActionArgument(),
    handler: untyped = MissingActionArgument(),
): untyped =
  ## Create an adapter with a zeroing receiver link and a non-capturing
  ## handler taking (receiver, sender). An optional context argument precedes
  ## the handler, which then takes (receiver, context, sender). Context follows
  ## normal Nim value semantics; owning references in it remain owning references.
  if handler.kind in {nnkCall, nnkObjConstr} and
      handler[0].eqIdent("MissingActionArgument"):
    result = newCall(
      bindSym"newReceiverActionTarget", action, receiver, nonCapturingHandler(context)
    )
  elif context.kind in {nnkCall, nnkObjConstr} and
      context[0].eqIdent("MissingActionArgument"):
    result = newCall(
      bindSym"newReceiverActionTarget", action, receiver, nonCapturingHandler(handler)
    )
  else:
    result = newCall(
      bindSym"newContextActionTarget",
      action,
      receiver,
      context,
      nonCapturingHandler(handler),
    )
