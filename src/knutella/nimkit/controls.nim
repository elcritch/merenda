import ./cells
import ./selectors
import ./types
import ./views

export cells, views

type
  Control* = ref object of View
    xCell: Cell
    xTarget: DynamicAgent
    xAction: ActionSelector

  ActionProc* = proc(sender: DynamicAgent) {.closure.}

  ClosureTarget* = ref object of Responder
    xCallback: ActionProc

proc cell*(control: Control): Cell
proc setCell*(control: Control, cell: Cell)
proc selectedCell*(control: Control): Cell
proc target*(control: Control): DynamicAgent
proc action*(control: Control): ActionSelector

protocol ControlProtocolInternal from Control:
  method isEnabled*(self: Control): bool =
    self.cell().isEnabled()

  method setEnabled*(self: Control, enabled: bool) =
    self.cell().setEnabled(enabled)
    self.setNeedsDisplay(true)

  method canBecomeKeyView*(self: Control): bool =
    self.isEnabled() and View(self).viewCanBecomeKeyView()

  method sendAction*(self: Control): bool =
    let target = self.target()
    if target.isNil:
      return false
    target.sendIfHandled(self.action(), ActionArgs(sender: DynamicAgent(self)))

proc cellForwardingTarget*(control: Control, selector: SigilName): DynamicAgent =
  if control.isNil:
    return nil
  let controlCell = control.xCell
  if not controlCell.isNil and controlCell.respondsTo(selector):
    return DynamicAgent(controlCell)

proc installCellForwarding(control: Control) =
  control.setForwardingTarget(
    proc(self: DynamicAgent, selector: SigilName): DynamicAgent =
      cellForwardingTarget(Control(self), selector)
  )

proc initControlFields*(control: Control, frame: Rect) =
  initViewFields(control, frame)
  control.installCellForwarding()
  control.setCell(newActionCell())
  discard control.withProto()

proc cell*(control: Control): Cell =
  if control.isNil:
    return nil
  if control.xCell.isNil:
    control.setCell(newActionCell())
  control.xCell

proc setCell*(control: Control, cell: Cell) =
  if control.isNil:
    return
  control.xCell = cell
  let bound = control.xCell
  if not bound.isNil:
    bound.setControlView(control)
    if bound of ActionCell:
      let actionCell = ActionCell(bound)
      actionCell.setTarget(control.xTarget)
      actionCell.setAction(control.xAction)
  control.setNeedsDisplay(true)

proc selectedCell*(control: Control): Cell =
  control.cell()

proc target*(control: Control): DynamicAgent =
  let selected = control.selectedCell()
  if not selected.isNil and selected of ActionCell:
    return ActionCell(selected).target()
  control.xTarget

proc setTarget*(control: Control, target: DynamicAgent) =
  control.xTarget = target
  let selected = control.selectedCell()
  if not selected.isNil and selected of ActionCell:
    ActionCell(selected).setTarget(target)

proc setTarget*(control: Control, target: Responder) =
  control.setTarget(DynamicAgent(target))

proc action*(control: Control): ActionSelector =
  let selected = control.selectedCell()
  if not selected.isNil and selected of ActionCell:
    return ActionCell(selected).action()
  control.xAction

proc setAction*(control: Control, action: ActionSelector) =
  control.xAction = action
  let selected = control.selectedCell()
  if not selected.isNil and selected of ActionCell:
    ActionCell(selected).setAction(action)

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
