import sigils/reactive
import sigils/selectors

import ./selectors
import ./types
import ./views

export views

type
  Control* = ref object of View
    xEnabled: Sigil[bool]
    xTarget: DynamicAgent
    xAction: ActionSelector

  ActionProc* = proc(sender: DynamicAgent) {.closure.}

  ClosureTarget* = ref object of Responder
    xCallback: ActionProc

proc initControlFields*(control: Control, frame: Rect) =
  initViewFields(control, frame)
  control.xEnabled = newSigil(true)

proc isEnabled*(control: Control): bool =
  control.xEnabled{}

proc setEnabled*(control: Control, enabled: bool) =
  if control.isEnabled == enabled:
    return
  control.xEnabled <- enabled
  control.setNeedsDisplay(true)

proc target*(control: Control): DynamicAgent =
  control.xTarget

proc setTarget*(control: Control, target: DynamicAgent) =
  control.xTarget = target

proc action*(control: Control): ActionSelector =
  control.xAction

proc setAction*(control: Control, action: ActionSelector) =
  control.xAction = action

proc sendAction*(control: Control): bool =
  if control.xTarget.isNil:
    return false
  var value: EmptyArgs
  control.xTarget.perform(
    control.xAction, ActionArgs(sender: DynamicAgent(control)), value
  )

proc closureActionImpl(target: ClosureTarget, args: ActionArgs): EmptyArgs =
  if not target.xCallback.isNil:
    target.xCallback(args.sender)

proc newActionTarget*(action: ActionSelector, callback: ActionProc): ClosureTarget =
  result = ClosureTarget()
  initResponder(result)
  result.xCallback = callback
  discard result.addMethod(action, toDynamicMethod(closureActionImpl))
