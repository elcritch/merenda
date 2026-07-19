import ../foundation/selectors
import ../accessibility/accessibility
import ../text/fieldeditors
import ../text/texttypes
import ../text/textviews
import ../foundation/types
import ../view/views

export views

type
  Cell* = ref object of DynamicAgent
    xControlView: WeakRef[View]
    xEnabled: bool
    xHighlighted: bool
    xState: ButtonState
    xAllowsMixedState: bool
    xSendsActionOnEndEditing: bool
    xMirrorsControlViewState: bool

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

protocol CellEditingProtocol {.setterStyle: nim.}:
  method fieldEditorForView*(controlView: View): FieldEditor {.optional.}
  method setUpFieldEditorAttributes*(
    editor: FieldEditor, controlView: View
  ) {.optional.}

  method editWithFrame*(
    frame: Rect, controlView: View, editor: FieldEditor
  ) {.optional.}

  method selectWithFrame*(
    frame: Rect, controlView: View, editor: FieldEditor, start, length: int
  ) {.optional.}

  method endEditing*(editor: FieldEditor, controlView: View) {.optional.}
  property sendsActionOnEndEditing -> bool

protocol DefaultCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: Cell): IntrinsicSize =
    NoIntrinsicContentSize

  method cellSizeForBounds(cell: Cell, bounds: Rect): Size =
    cell.cellSize().resolveIntrinsicSize(bounds.size)

protocol DefaultCellEditing {.setterStyle: nim.} of CellEditingProtocol from Cell:
  method fieldEditorForView(cell: Cell, controlView: View): FieldEditor =
    nil

  method setUpFieldEditorAttributes(
      cell: Cell, editor: FieldEditor, controlView: View
  ) =
    discard

  method editWithFrame(
      cell: Cell, frame: Rect, controlView: View, editor: FieldEditor
  ) =
    if editor.isNil:
      return
    cell.setUpFieldEditorAttributes(editor, controlView)
    editor.frame = frame
    if not controlView.isNil and editor.superview() != controlView:
      controlView.addSubview(editor)

  method selectWithFrame(
      cell: Cell,
      frame: Rect,
      controlView: View,
      editor: FieldEditor,
      start, length: int,
  ) =
    cell.editWithFrame(frame, controlView, editor)
    if not editor.isNil:
      TextView(editor).selectedRange = initTextRange(start, length)

  method endEditing(cell: Cell, editor: FieldEditor, controlView: View) =
    if not editor.isNil and editor.superview() == controlView:
      editor.removeFromSuperview()

  property sendsActionOnEndEditing -> bool {.field: xSendsActionOnEndEditing.}

proc invalidateViewCellMetrics(view: View) =
  if not view.isNil:
    view.invalidateIntrinsicContentSize()
    view.needsDisplay = true

proc invalidateControlMetrics*(cell: Cell) =
  cell.controlView().invalidateViewCellMetrics()

proc updateControlView*(cell: Cell) =
  cell.invalidateControlMetrics()

proc initCellFields*(cell: Cell) =
  cell.xEnabled = true
  cell.xMirrorsControlViewState = true
  discard cell.withProtocol(DefaultCellMeasurement)
  discard cell.withProtocol(DefaultCellEditing)

proc initActionCellFields*(cell: ActionCell) =
  initCellFields(cell)

proc newCell*(): Cell =
  result = Cell()
  initCellFields(result)

proc newActionCell*(): ActionCell =
  result = ActionCell()
  initActionCellFields(result)

proc controlView*(cell: Cell): View =
  if cell.xControlView.isNil:
    return nil
  cell.xControlView[]

proc setControlView*(cell: Cell, view: View) =
  let oldView = cell.controlView()
  if oldView == view:
    return
  cell.xControlView =
    if view.isNil:
      WeakRef[View]()
    else:
      view.unsafeWeakRef()
  oldView.invalidateViewCellMetrics()
  if not view.isNil and cell.xMirrorsControlViewState:
    view.setWidgetState(ssDisabled, not cell.xEnabled)
    view.setWidgetState(ssHighlighted, cell.xHighlighted)
  cell.invalidateControlMetrics()

proc mirrorsControlViewState*(cell: Cell): bool =
  cell.xMirrorsControlViewState

proc setMirrorsControlViewState*(cell: Cell, value: bool) =
  if cell.xMirrorsControlViewState == value:
    return
  cell.xMirrorsControlViewState = value
  let view = cell.controlView()
  if not view.isNil and value:
    view.setWidgetState(ssDisabled, not cell.xEnabled)
    view.setWidgetState(ssHighlighted, cell.xHighlighted)

proc isEnabled*(cell: Cell): bool =
  let view = cell.controlView()
  result = cell.xEnabled
  if result and cell.xMirrorsControlViewState and not view.isNil:
    result = ssDisabled notin view.widgetStateSet()

proc setEnabled*(cell: Cell, enabled: bool) =
  let oldEnabled = cell.isEnabled()
  if cell.xEnabled == enabled and oldEnabled == enabled:
    return
  cell.xEnabled = enabled
  let view = cell.controlView()
  if not view.isNil and cell.xMirrorsControlViewState:
    view.setWidgetState(ssDisabled, not enabled)
  elif oldEnabled != enabled:
    cell.invalidateControlMetrics()

proc isHighlighted*(cell: Cell): bool =
  cell.xHighlighted

proc setHighlighted*(cell: Cell, highlighted: bool) =
  let oldHighlighted = cell.isHighlighted()
  if cell.xHighlighted == highlighted and oldHighlighted == highlighted:
    return
  cell.xHighlighted = highlighted
  let view = cell.controlView()
  if not view.isNil and cell.xMirrorsControlViewState:
    view.setWidgetState(ssHighlighted, highlighted)
  elif oldHighlighted != highlighted:
    cell.invalidateControlMetrics()

proc state*(cell: Cell): ButtonState =
  cell.xState

proc setState*(cell: Cell, state: ButtonState) =
  let normalized = state.normalizeState(cell.xAllowsMixedState)
  if cell.xState == normalized:
    return
  cell.xState = normalized
  cell.invalidateControlMetrics()
  cell.controlView().postAccessibilityNotification(anValueChanged)

proc allowsMixedState*(cell: Cell): bool =
  cell.xAllowsMixedState

proc setAllowsMixedState*(cell: Cell, value: bool) =
  if cell.xAllowsMixedState == value:
    return
  cell.xAllowsMixedState = value
  if not value and cell.xState == bsMixed:
    cell.setState(bsOff)
  else:
    cell.invalidateControlMetrics()

proc nextState*(cell: Cell): ButtonState =
  case cell.xState
  of bsOff:
    bsOn
  of bsOn:
    if cell.xAllowsMixedState: bsMixed else: bsOff
  of bsMixed:
    bsOff

proc setNextState*(cell: Cell) =
  cell.setState(cell.nextState())

proc target*(cell: ActionCell): DynamicAgent =
  cell.xTarget

proc setTarget*(cell: ActionCell, target: DynamicAgent) =
  cell.xTarget = target

proc action*(cell: ActionCell): ActionSelector =
  cell.xAction

proc setAction*(cell: ActionCell, action: ActionSelector) =
  cell.xAction = action
