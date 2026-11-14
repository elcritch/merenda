## Weak, context-bound commands for presentation-owned actions.
import ./responders

type GuardedCommand*[R: Responder, C] = object
  receiver: BackRef[R]
  context: C
  valid: proc(receiver: R, context: C): bool {.nimcall.}

proc initGuardedCommand*[R: Responder, C](
    receiver: R, context: C, valid: proc(receiver: R, context: C): bool {.nimcall.}
): GuardedCommand[R, C] =
  ## Capture context using Nim value semantics. References within it retain
  ## their usual ownership; use value-only identity snapshots when appropriate.
  ## The predicate must be non-capturing and is evaluated at each dispatch.
  result.receiver.target = receiver
  result.context = context
  result.valid = valid

proc perform*[R: Responder, C](
    command: GuardedCommand[R, C], handler: proc(receiver: R, context: C) {.nimcall.}
): bool {.discardable.} =
  ## Resolve once, check current validity, then invoke the non-capturing handler.
  ## A released receiver, missing predicate or missing handler is not dispatched.
  let receiver = command.receiver{}
  if not receiver.isNil and not command.valid.isNil and not handler.isNil and
      command.valid(receiver, command.context):
    handler(receiver, command.context)
    result = true
