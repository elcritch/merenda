## Action receivers with explicit weak or retained ownership.

import std/macros
import ./responders
import ../foundation/selectors

type
  ActionProc* = proc(sender: DynamicAgent) {.closure.}

  ActionAdapter* = ref object of Responder
    ## An action adapter explicitly owned by its control or item model.

  ClosureTarget* = ref object of ActionAdapter
    callback: ActionProc

  ReceiverActionTarget[T] = ref object of ActionAdapter
    receiver: BackRef[T]
    handler: proc(receiver: T, sender: DynamicAgent) {.nimcall.}

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

macro newActionTarget*(
    action: ActionSelector, receiver: typed, handler: untyped
): untyped =
  ## Create a retained adapter with a zeroing receiver link. The handler takes
  ## (receiver, sender) and is not called after the receiver is released.
  ## Inline handlers are marked nimcall before typing their body, rejecting captures.
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
  result = newCall(bindSym"newReceiverActionTarget", action, receiver, callback)
