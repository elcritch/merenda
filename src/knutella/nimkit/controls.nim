import ./selectors
import ./types
import ./views

export views

type
  Control* = ref object of View
    xEnabled: bool
    xTarget: DynamicAgent
    xAction: ActionSelector

  ActionProc* = proc(sender: DynamicAgent) {.closure.}

  ClosureTarget* = ref object of Responder
    xCallback: ActionProc

protocol ControlProtocolInternal:
  required:
    method isEnabled(): bool
    method setEnabled(enabled: bool)
    method sendAction(): bool

protocol DefaultControl of ControlProtocolInternal:
  method isEnabled(self: Control): bool =
    self.xEnabled

  method setEnabled(self: Control, enabled: bool) =
    if self.xEnabled == enabled:
      return
    self.xEnabled = enabled
    self.setNeedsDisplay(true)

  method sendAction(self: Control): bool =
    if self.xTarget.isNil:
      return false
    var value: EmptyArgs
    self.xTarget.perform(self.xAction, ActionArgs(sender: DynamicAgent(self)), value)

proc initControlFields*(control: Control, frame: Rect) =
  initViewFields(control, frame)
  control.xEnabled = true
  discard control.replaceMethods(DefaultControl.init())

proc isEnabled*(control: Control): bool =
  control.send(isEnabled, ())

proc setEnabled*(control: Control, enabled: bool) =
  discard control.send(setEnabled, enabled)

proc target*(control: Control): DynamicAgent =
  control.xTarget

proc setTarget*(control: Control, target: DynamicAgent) =
  control.xTarget = target

proc setTarget*(control: Control, target: Responder) =
  control.xTarget = DynamicAgent(target)

proc action*(control: Control): ActionSelector =
  control.xAction

proc setAction*(control: Control, action: ActionSelector) =
  control.xAction = action

proc sendAction*(control: Control): bool =
  control.send(sendAction, ())

proc newActionTarget*(action: ActionSelector, callback: ActionProc): ClosureTarget =
  result = ClosureTarget()
  initResponder(result)
  result.xCallback = callback
  let fn: DynamicMethod = proc(self: DynamicAgent, invocation: var Invocation) =
    let target = ClosureTarget(self)
    let args = invocation.argsAs(ActionArgs)
    if not target.xCallback.isNil:
      target.xCallback(args.sender)
    invocation.setResult(())
  discard result.replaceMethod(action, fn)

let ControlProtocol* = ControlProtocolInternal
