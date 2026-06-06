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

proc controlIntrinsicContentSize(control: Control): IntrinsicSize =
  let controlCell = control.cell()
  if controlCell.isNil:
    NoIntrinsicContentSize
  else:
    controlCell.cellSize()

proc invalidateCellMetrics(control: Control) =
  if control.isNil:
    return
  control.invalidateIntrinsicContentSize()
  control.setNeedsDisplay(true)

proc syncActionCell(control: Control, cell: Cell) =
  if control.isNil or cell.isNil or not (cell of ActionCell):
    return
  let actionCell = ActionCell(cell)
  actionCell.setTarget(control.xTarget)
  actionCell.setAction(control.xAction)

proc defaultControlCell(): Cell =
  newActionCell()

protocol ControlProtocol from Control:
  method isEnabled*(self: Control): bool =
    self.cell().isEnabled()

  method setEnabled*(self: Control, enabled: bool) =
    self.cell().setEnabled(enabled)

  method canBecomeKeyView*(self: Control): bool =
    self.isEnabled() and View(self).viewCanBecomeKeyView()

  method layoutIntrinsicContentSize*(self: Control): IntrinsicSize =
    self.controlIntrinsicContentSize()

  method sendAction*(self: Control): bool =
    let target = self.target()
    if target.isNil:
      return false
    target.sendIfHandled(self.action(), ActionArgs(sender: DynamicAgent(self)))

proc enabled*(control: Control): bool =
  (not control.isNil) and control.isEnabled()

proc `enabled=`*(control: Control, enabled: bool) =
  if not control.isNil:
    control.setEnabled(enabled)

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

proc intrinsicContentSize*(control: Control): IntrinsicSize =
  control.controlIntrinsicContentSize()

proc sizeThatFits*(control: Control, proposedSize: FittingSize): Size =
  if control.isNil:
    return initSize(0.0, 0.0)
  let controlCell = control.cell()
  if controlCell.isNil:
    return control.bounds().size.constrainSize(proposedSize)

  let naturalSize = controlCell.cellSize().resolveIntrinsicSize(control.bounds().size)
  if not proposedSize.hasWidth and not proposedSize.hasHeight:
    return naturalSize

  let fittingBounds = initRect(
    0.0,
    0.0,
    if proposedSize.hasWidth: proposedSize.width else: naturalSize.width,
    if proposedSize.hasHeight: proposedSize.height else: naturalSize.height,
  )
  controlCell.cellSizeForBounds(fittingBounds)

proc sizeThatFits*(control: Control): Size =
  control.sizeThatFits(UnconstrainedFittingSize)

proc sizeThatFits*(control: Control, proposedSize: Size): Size =
  control.sizeThatFits(initFittingSize(proposedSize))

proc sizeToFit*(control: Control) =
  if control.isNil:
    return
  let frame = control.frame()
  control.setFrame(
    initRect(frame.origin, control.sizeThatFits(UnconstrainedFittingSize))
  )

proc initControlFields*(control: Control, frame: Rect = AutoRect, cell: Cell = nil) =
  initViewFields(control, frame)
  control.setHuggingPriority(LayoutPriorityHigh, laVertical)
  control.installCellForwarding()
  control.setCell(
    if cell.isNil:
      defaultControlCell()
    else:
      cell
  )
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
  if control.xCell == cell:
    control.syncActionCell(cell)
    return
  let oldCell = control.xCell
  if not oldCell.isNil and oldCell.controlView() == View(control):
    oldCell.setControlView(nil)
  control.xCell = cell
  control.syncActionCell(control.xCell)
  if not control.xCell.isNil:
    control.xCell.setControlView(control)
  control.invalidateCellMetrics()

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

proc `target=`*(control: Control, target: DynamicAgent) =
  control.setTarget(target)

proc setTarget*(control: Control, target: Responder) =
  control.setTarget(DynamicAgent(target))

proc `target=`*(control: Control, target: Responder) =
  control.setTarget(target)

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

proc `action=`*(control: Control, action: ActionSelector) =
  control.setAction(action)

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
