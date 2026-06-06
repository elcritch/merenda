import ./selectors
import ./types
import ./views

export views

type
  Cell* = ref object of DynamicAgent
    xControlView: WeakRef[View]
    xEnabled: bool
    xHighlighted: bool
    xState: ButtonState
    xAllowsMixedState: bool

  ActionCell* = ref object of Cell
    xTarget: DynamicAgent
    xAction: ActionSelector

proc normalizeState(value: ButtonState, allowsMixedState: bool): ButtonState =
  if value == bsMixed and allowsMixedState:
    return bsMixed
  if value == bsOn:
    return bsOn
  bsOff

proc controlView*(cell: Cell): View

protocol CellMeasurementProtocol:
  method cellSize*(): IntrinsicSize
  method cellSizeForBounds*(bounds: Rect): Size

protocol DefaultCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: Cell): IntrinsicSize =
    NoIntrinsicContentSize

  method cellSizeForBounds(cell: Cell, bounds: Rect): Size =
    cell.cellSize().resolveIntrinsicSize(bounds.size)

proc invalidateViewCellMetrics(view: View) =
  if not view.isNil:
    view.invalidateIntrinsicContentSize()
    view.setNeedsDisplay(true)

proc invalidateControlMetrics*(cell: Cell) =
  cell.controlView().invalidateViewCellMetrics()

proc updateControlView*(cell: Cell) =
  cell.invalidateControlMetrics()

proc initCellFields*(cell: Cell) =
  cell.xEnabled = true
  discard cell.withProtocol(DefaultCellMeasurement)

proc initActionCellFields*(cell: ActionCell) =
  initCellFields(cell)

proc newCell*(): Cell =
  result = Cell()
  initCellFields(result)

proc newActionCell*(): ActionCell =
  result = ActionCell()
  initActionCellFields(result)

proc controlView*(cell: Cell): View =
  if cell.isNil or cell.xControlView.isNil:
    return nil
  cell.xControlView[]

proc setControlView*(cell: Cell, view: View) =
  if cell.isNil:
    return
  let oldView = cell.controlView()
  if oldView == view:
    return
  cell.xControlView =
    if view.isNil:
      WeakRef[View]()
    else:
      view.unsafeWeakRef()
  oldView.invalidateViewCellMetrics()
  cell.invalidateControlMetrics()

proc isEnabled*(cell: Cell): bool =
  (not cell.isNil) and cell.xEnabled

proc setEnabled*(cell: Cell, enabled: bool) =
  if cell.isNil or cell.xEnabled == enabled:
    return
  cell.xEnabled = enabled
  cell.invalidateControlMetrics()

proc isHighlighted*(cell: Cell): bool =
  (not cell.isNil) and cell.xHighlighted

proc setHighlighted*(cell: Cell, highlighted: bool) =
  if cell.isNil or cell.xHighlighted == highlighted:
    return
  cell.xHighlighted = highlighted
  cell.invalidateControlMetrics()

proc state*(cell: Cell): ButtonState =
  if cell.isNil:
    return bsOff
  cell.xState

proc setState*(cell: Cell, state: ButtonState) =
  if cell.isNil:
    return
  let normalized = state.normalizeState(cell.xAllowsMixedState)
  if cell.xState == normalized:
    return
  cell.xState = normalized
  cell.invalidateControlMetrics()

proc allowsMixedState*(cell: Cell): bool =
  (not cell.isNil) and cell.xAllowsMixedState

proc setAllowsMixedState*(cell: Cell, value: bool) =
  if cell.isNil:
    return
  if cell.xAllowsMixedState == value:
    return
  cell.xAllowsMixedState = value
  if not value and cell.xState == bsMixed:
    cell.setState(bsOff)
  else:
    cell.invalidateControlMetrics()

proc nextState*(cell: Cell): ButtonState =
  if cell.isNil:
    return bsOff
  case cell.xState
  of bsOff:
    bsOn
  of bsOn:
    if cell.xAllowsMixedState: bsMixed else: bsOff
  of bsMixed:
    bsOff

proc setNextState*(cell: Cell) =
  if cell.isNil:
    return
  cell.setState(cell.nextState())

proc target*(cell: ActionCell): DynamicAgent =
  if cell.isNil:
    return nil
  cell.xTarget

proc setTarget*(cell: ActionCell, target: DynamicAgent) =
  if cell.isNil:
    return
  cell.xTarget = target

proc action*(cell: ActionCell): ActionSelector =
  if cell.isNil:
    return default(ActionSelector)
  cell.xAction

proc setAction*(cell: ActionCell, action: ActionSelector) =
  if cell.isNil:
    return
  cell.xAction = action
