import sigils/core
import sigils/selectors

import ../accessibility/accessibility
import ../app/windows except sendAction
import ../drawing
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../foundation/undomanagers
import ../text/fieldeditors
import ./buttons except isEnabled, setEnabled
import ./controls as controlbase
from ./cells import nil

export buttons

type
  MatrixSelectionMode* = enum
    msmNone
    msmRadio
    msmSingle
    msmMultiple

  Matrix* = ref object of Control
    xRows: int
    xColumns: int
    xCells: seq[ButtonCell]
    xPrototype: ButtonCell
    xSelectionMode: MatrixSelectionMode
    xCellSize: Size
    xIntercellSpacing: Size
    xHighlightedIndex: int
    xLeadIndex: int
    xSelectedIndex: int

protocol MatrixEvents:
  proc selectionDidChange*(matrix: Matrix, sender: DynamicAgent) {.signal.}

let
  controlIsEnabledSelector = selector[tuple[], bool]("isEnabled")
  controlSetEnabledSelector = selector[bool, void]("setEnabled")
  controlCanBecomeKeyViewSelector = selector[tuple[], bool]("canBecomeKeyView")
  controlShouldBecomeFirstResponderSelector =
    selector[tuple[], bool]("shouldBecomeFirstResponder")
  controlLayoutIntrinsicContentSizeSelector =
    selector[tuple[], IntrinsicSize]("layoutIntrinsicContentSize")
  controlSendActionSelector = selector[tuple[], bool]("sendAction")
  controlValidateEditingSelector = selector[tuple[], bool]("validateEditing")
  controlAbortEditingSelector = selector[tuple[], bool]("abortEditing")

proc invalidateMatrix(matrix: Matrix) =
  if not matrix.isNil:
    matrix.invalidateIntrinsicContentSize()
    matrix.setNeedsDisplay(true)

func normalizedCount(value: int): int =
  max(value, 0)

func normalizedColumns(value: int): int =
  max(value, 1)

func gridRows(itemCount, columns: int): int =
  if itemCount <= 0:
    0
  else:
    (itemCount + columns.normalizedColumns() - 1) div columns.normalizedColumns()

func validIndex(matrix: Matrix, index: int): bool =
  not matrix.isNil and index in 0 ..< matrix.xCells.len

func cellIndex(matrix: Matrix, row, column: int): int =
  if matrix.isNil or row < 0 or column < 0 or row >= matrix.xRows or
      column >= matrix.xColumns:
    -1
  else:
    row * matrix.xColumns + column

func rowForIndex(matrix: Matrix, index: int): int =
  if matrix.isNil or matrix.xColumns <= 0 or index < 0:
    -1
  else:
    index div matrix.xColumns

func columnForIndex(matrix: Matrix, index: int): int =
  if matrix.isNil or matrix.xColumns <= 0 or index < 0:
    -1
  else:
    index mod matrix.xColumns

proc clearSelectionStates(matrix: Matrix, exceptIndex = -1)
proc emitSelectionChangedIfNeeded(matrix: Matrix, before: seq[int])

proc selectedIndexes*(matrix: Matrix): seq[int] =
  if matrix.isNil:
    return
  for index, cell in matrix.xCells:
    if not cell.isNil and cell.state() in {bsOn, bsMixed}:
      result.add index

proc `selectedIndexes=`*(matrix: Matrix, indexes: openArray[int]) =
  if matrix.isNil:
    return
  var nextIndexes: seq[int]
  for index in indexes:
    if matrix.validIndex(index) and not matrix.xCells[index].isNil and
        index notin nextIndexes:
      case matrix.xSelectionMode
      of msmNone, msmMultiple:
        nextIndexes.add index
      of msmRadio, msmSingle:
        if nextIndexes.len == 0:
          nextIndexes.add index
  let before = matrix.selectedIndexes()
  if before == nextIndexes:
    return
  matrix.findUndoManager().registerSelectionChange(
    proc(indexes: seq[int]) =
      matrix.selectedIndexes = indexes,
    before,
    "Change Selection",
  )
  matrix.clearSelectionStates()
  for index in nextIndexes:
    matrix.xCells[index].setState(bsOn)
  matrix.xSelectedIndex =
    if nextIndexes.len == 0:
      -1
    else:
      nextIndexes[0]
  matrix.xLeadIndex = matrix.xSelectedIndex
  matrix.emitSelectionChangedIfNeeded(before)
  matrix.invalidateMatrix()

proc sendMatrixAction(matrix: Matrix): bool

proc firstEnabledIndex(matrix: Matrix): int =
  if matrix.isNil:
    return -1
  for index, cell in matrix.xCells:
    if not cell.isNil and cells.isEnabled(cell):
      return index
  -1

proc firstSelectedIndex(matrix: Matrix): int =
  if matrix.isNil:
    return -1
  for index, cell in matrix.xCells:
    if not cell.isNil and cell.state() in {bsOn, bsMixed}:
      return index
  -1

proc normalizeLeadAndSelection(matrix: Matrix) =
  if matrix.isNil:
    return
  if not matrix.validIndex(matrix.xLeadIndex) or matrix.xCells[matrix.xLeadIndex].isNil or
      not cells.isEnabled(matrix.xCells[matrix.xLeadIndex]):
    matrix.xLeadIndex = matrix.firstSelectedIndex()
    if matrix.xLeadIndex < 0:
      matrix.xLeadIndex = matrix.firstEnabledIndex()
  if not matrix.validIndex(matrix.xSelectedIndex) or
      matrix.xCells[matrix.xSelectedIndex].isNil or
      matrix.xCells[matrix.xSelectedIndex].state() == bsOff:
    matrix.xSelectedIndex = matrix.firstSelectedIndex()

proc attachCell(matrix: Matrix, cell: ButtonCell) =
  if cell.isNil:
    return
  cell.setMirrorsControlViewState(false)
  cell.setControlView(matrix)

proc detachCell(matrix: Matrix, cell: ButtonCell) =
  if not cell.isNil and cell.controlView() == View(matrix):
    cell.setControlView(nil)

proc clonedPrototype(matrix: Matrix): ButtonCell =
  let prototype =
    if matrix.isNil or matrix.xPrototype.isNil:
      newButtonCell()
    else:
      matrix.xPrototype
  prototype.copyButtonCell()

proc configureCells(matrix: Matrix, rows, columns: int, prototype: ButtonCell) =
  if matrix.isNil:
    return
  let
    nextRows = rows.normalizedCount()
    nextColumns = columns.normalizedColumns()
    nextCount = nextRows * nextColumns
  var nextCells = newSeq[ButtonCell](nextCount)

  if not prototype.isNil:
    matrix.xPrototype = prototype.copyButtonCell()
    matrix.xPrototype.setControlView(nil)
  elif matrix.xPrototype.isNil:
    matrix.xPrototype = newButtonCell()

  for index in 0 ..< nextCount:
    if index < matrix.xCells.len and not matrix.xCells[index].isNil:
      nextCells[index] = matrix.xCells[index]
    else:
      nextCells[index] = matrix.clonedPrototype()
    matrix.attachCell(nextCells[index])

  for index in nextCount ..< matrix.xCells.len:
    matrix.detachCell(matrix.xCells[index])

  matrix.xRows = nextRows
  matrix.xColumns = nextColumns
  matrix.xCells = nextCells
  matrix.normalizeLeadAndSelection()
  matrix.invalidateMatrix()

proc rows*(matrix: Matrix): int =
  if matrix.isNil: 0 else: matrix.xRows

proc rowCount*(matrix: Matrix): int =
  matrix.rows()

proc columns*(matrix: Matrix): int =
  if matrix.isNil: 0 else: matrix.xColumns

proc columnCount*(matrix: Matrix): int =
  matrix.columns()

proc len*(matrix: Matrix): int =
  if matrix.isNil: 0 else: matrix.xCells.len

proc selectionMode*(matrix: Matrix): MatrixSelectionMode =
  if matrix.isNil: msmNone else: matrix.xSelectionMode

proc `selectionMode=`*(matrix: Matrix, mode: MatrixSelectionMode) =
  if matrix.isNil or matrix.xSelectionMode == mode:
    return
  matrix.xSelectionMode = mode
  if mode in {msmRadio, msmSingle}:
    let selected = matrix.firstSelectedIndex()
    for index, cell in matrix.xCells:
      if not cell.isNil and index != selected:
        cell.setState(bsOff)
    matrix.xSelectedIndex = selected
  matrix.normalizeLeadAndSelection()
  matrix.invalidateMatrix()

proc cellSize*(matrix: Matrix): Size =
  if matrix.isNil: AutoSize else: matrix.xCellSize

proc `cellSize=`*(matrix: Matrix, size: Size) =
  if matrix.isNil:
    return
  let normalized = initSize(size.width, size.height)
  if matrix.xCellSize == normalized:
    return
  matrix.xCellSize = normalized
  matrix.invalidateMatrix()

proc intercellSpacing*(matrix: Matrix): Size =
  if matrix.isNil:
    initSize(0.0, 0.0)
  else:
    matrix.xIntercellSpacing

proc `intercellSpacing=`*(matrix: Matrix, size: Size) =
  if matrix.isNil:
    return
  let normalized = initSize(size.width, size.height)
  if matrix.xIntercellSpacing == normalized:
    return
  matrix.xIntercellSpacing = normalized
  matrix.invalidateMatrix()

proc cellAtIndex*(matrix: Matrix, index: int): ButtonCell =
  if matrix.validIndex(index):
    matrix.xCells[index]
  else:
    nil

proc cellAt*(matrix: Matrix, row, column: int): ButtonCell =
  matrix.cellAtIndex(matrix.cellIndex(row, column))

proc `[]`*(matrix: Matrix, row, column: int): ButtonCell =
  matrix.cellAt(row, column)

proc setCellAt*(matrix: Matrix, row, column: int, cell: ButtonCell) =
  if matrix.isNil:
    return
  let index = matrix.cellIndex(row, column)
  if not matrix.validIndex(index):
    return
  let nextCell =
    if cell.isNil:
      matrix.clonedPrototype()
    else:
      cell
  if matrix.xCells[index] == nextCell:
    matrix.attachCell(nextCell)
    matrix.invalidateMatrix()
    return
  matrix.detachCell(matrix.xCells[index])
  matrix.xCells[index] = nextCell
  matrix.attachCell(nextCell)
  matrix.normalizeLeadAndSelection()
  matrix.invalidateMatrix()

proc `[]=`*(matrix: Matrix, row, column: int, cell: ButtonCell) =
  matrix.setCellAt(row, column, cell)

proc prototypeCell*(matrix: Matrix): ButtonCell =
  if matrix.isNil: nil else: matrix.xPrototype

proc renewRowsColumns*(
    matrix: Matrix, rows, columns: int, prototype: ButtonCell = nil
) =
  matrix.configureCells(rows, columns, prototype)

proc selectedIndex*(matrix: Matrix): int =
  if matrix.isNil:
    -1
  else:
    matrix.normalizeLeadAndSelection()
    matrix.xSelectedIndex

proc selectedRow*(matrix: Matrix): int =
  matrix.rowForIndex(matrix.selectedIndex())

proc selectedColumn*(matrix: Matrix): int =
  matrix.columnForIndex(matrix.selectedIndex())

proc selectedCell*(matrix: Matrix): ButtonCell =
  matrix.cellAtIndex(matrix.selectedIndex())

proc selectedCells*(matrix: Matrix): seq[ButtonCell] =
  if matrix.isNil:
    return
  for cell in matrix.xCells:
    if not cell.isNil and cell.state() in {bsOn, bsMixed}:
      result.add cell

proc leadIndex*(matrix: Matrix): int =
  if matrix.isNil:
    -1
  else:
    matrix.normalizeLeadAndSelection()
    matrix.xLeadIndex

proc leadRow*(matrix: Matrix): int =
  matrix.rowForIndex(matrix.leadIndex())

proc leadColumn*(matrix: Matrix): int =
  matrix.columnForIndex(matrix.leadIndex())

proc clearHighlightedCell(matrix: Matrix) =
  if matrix.validIndex(matrix.xHighlightedIndex):
    matrix.xCells[matrix.xHighlightedIndex].setHighlighted(false)
  matrix.xHighlightedIndex = -1

proc setHighlightedIndex(matrix: Matrix, index: int) =
  if matrix.isNil or matrix.xHighlightedIndex == index:
    return
  matrix.clearHighlightedCell()
  if matrix.validIndex(index):
    matrix.xCells[index].setHighlighted(true)
    matrix.xHighlightedIndex = index
  matrix.setNeedsDisplay(true)

proc clearSelectionStates(matrix: Matrix, exceptIndex = -1) =
  if matrix.isNil:
    return
  for index, cell in matrix.xCells:
    if not cell.isNil and index != exceptIndex and cell.state() != bsOff:
      cell.setState(bsOff)

proc emitSelectionChangedIfNeeded(matrix: Matrix, before: seq[int]) =
  if matrix.isNil:
    return
  let after = matrix.selectedIndexes()
  if before != after:
    emit matrix.selectionDidChange(DynamicAgent(matrix))
    matrix.postAccessibilityNotification(anSelectionChanged)

proc selectIndex(matrix: Matrix, index: int, notify = false): bool =
  if matrix.isNil or not controlbase.isEnabled(matrix) or not matrix.validIndex(index):
    return false
  let cell = matrix.xCells[index]
  if cell.isNil or not cells.isEnabled(cell):
    return false

  let before = matrix.selectedIndexes()
  matrix.xLeadIndex = index
  case matrix.xSelectionMode
  of msmNone:
    case cell.buttonType()
    of btToggle, btCheckBox:
      cell.setNextState()
    of btRadio:
      cell.setState(bsOn)
    of btMomentary:
      discard
    matrix.xSelectedIndex = matrix.firstSelectedIndex()
  of msmRadio, msmSingle:
    matrix.clearSelectionStates(exceptIndex = index)
    cell.setState(bsOn)
    matrix.xSelectedIndex = index
  of msmMultiple:
    case cell.buttonType()
    of btMomentary:
      discard
    of btRadio:
      cell.setState(bsOn)
    of btToggle, btCheckBox:
      cell.setNextState()
    matrix.xSelectedIndex =
      if cell.state() in {bsOn, bsMixed}:
        index
      else:
        matrix.firstSelectedIndex()

  matrix.emitSelectionChangedIfNeeded(before)
  matrix.setNeedsDisplay(true)
  if notify:
    discard matrix.sendMatrixAction()
  true

proc selectCellAt*(matrix: Matrix, row, column: int, notify = false): bool =
  matrix.selectIndex(matrix.cellIndex(row, column), notify)

proc selectCellAtIndex*(matrix: Matrix, index: int, notify = false): bool =
  matrix.selectIndex(index, notify)

proc deselectAll*(matrix: Matrix) =
  if matrix.isNil:
    return
  matrix.selectedIndexes = @[]

proc cellNaturalSize(matrix: Matrix, cell: ButtonCell): Size =
  if cell.isNil:
    return initSize(0.0, 0.0)
  cell.cellSize().resolveIntrinsicSize(matrix.bounds().size)

proc resolvedCellSize(matrix: Matrix): Size =
  if matrix.isNil:
    return initSize(0.0, 0.0)
  if matrix.xCellSize.hasWidth and matrix.xCellSize.hasHeight:
    return matrix.xCellSize
  var natural = initSize(0.0, 0.0)
  for cell in matrix.xCells:
    let cellSize = matrix.cellNaturalSize(cell)
    natural.width = max(natural.width, cellSize.width)
    natural.height = max(natural.height, cellSize.height)
  matrix.xCellSize.resolveAutoSize(natural)

proc naturalMatrixSize(matrix: Matrix): Size =
  if matrix.isNil or matrix.xRows <= 0 or matrix.xColumns <= 0:
    return initSize(0.0, 0.0)
  let cellSize = matrix.resolvedCellSize()
  initSize(
    cellSize.width * matrix.xColumns.float32 +
      matrix.xIntercellSpacing.width * max(matrix.xColumns - 1, 0).float32,
    cellSize.height * matrix.xRows.float32 +
      matrix.xIntercellSpacing.height * max(matrix.xRows - 1, 0).float32,
  )

proc cellFrameAtIndex*(matrix: Matrix, index: int): Rect =
  if not matrix.validIndex(index):
    return initRect(0.0, 0.0, 0.0, 0.0)
  let
    cellSize = matrix.resolvedCellSize()
    row = matrix.rowForIndex(index)
    column = matrix.columnForIndex(index)
  initRect(
    matrix.bounds().origin.x +
      column.float32 * (cellSize.width + matrix.xIntercellSpacing.width),
    matrix.bounds().origin.y +
      row.float32 * (cellSize.height + matrix.xIntercellSpacing.height),
    cellSize.width,
    cellSize.height,
  )

proc cellFrameAt*(matrix: Matrix, row, column: int): Rect =
  matrix.cellFrameAtIndex(matrix.cellIndex(row, column))

proc cellIndexAtPoint*(matrix: Matrix, point: Point): int =
  if matrix.isNil or not matrix.bounds().contains(point):
    return -1
  for index in 0 ..< matrix.xCells.len:
    if matrix.cellFrameAtIndex(index).contains(point):
      return index
  -1

proc moveLead(matrix: Matrix, rowDelta, columnDelta: int, notify = true): bool =
  if matrix.isNil or matrix.xRows <= 0 or matrix.xColumns <= 0:
    return false
  let
    current = max(matrix.leadIndex(), matrix.firstEnabledIndex())
    currentRow = matrix.rowForIndex(current)
    currentColumn = matrix.columnForIndex(current)
  if currentRow < 0 or currentColumn < 0:
    return false

  var
    nextRow = min(max(currentRow + rowDelta, 0), matrix.xRows - 1)
    nextColumn = min(max(currentColumn + columnDelta, 0), matrix.xColumns - 1)
    nextIndex = matrix.cellIndex(nextRow, nextColumn)
  while matrix.validIndex(nextIndex) and not cells.isEnabled(matrix.xCells[nextIndex]):
    let advancedRow = min(max(nextRow + rowDelta, 0), matrix.xRows - 1)
    let advancedColumn = min(max(nextColumn + columnDelta, 0), matrix.xColumns - 1)
    if advancedRow == nextRow and advancedColumn == nextColumn:
      return false
    nextRow = advancedRow
    nextColumn = advancedColumn
    nextIndex = matrix.cellIndex(nextRow, nextColumn)

  if not matrix.validIndex(nextIndex) or nextIndex == current:
    return false
  if matrix.xSelectionMode in {msmRadio, msmSingle}:
    matrix.selectIndex(nextIndex, notify)
  else:
    matrix.xLeadIndex = nextIndex
    matrix.setNeedsDisplay(true)
    true

proc currentActionCell(matrix: Matrix): ActionCell =
  var cell = matrix.selectedCell()
  if cell.isNil:
    cell = matrix.cellAtIndex(matrix.xLeadIndex)
  if cell.isNil:
    nil
  else:
    ActionCell(cell)

proc matrixAction(matrix: Matrix): ActionSelector =
  let cell = matrix.currentActionCell()
  if not cell.isNil and cell.action().name.len > 0:
    return cell.action()
  Control(matrix).action()

proc matrixTarget(matrix: Matrix): DynamicAgent =
  let cell = matrix.currentActionCell()
  if not cell.isNil and not cell.target().isNil:
    return cell.target()
  Control(matrix).target()

proc sendMatrixAction(matrix: Matrix): bool =
  var handled = false
  let
    action = matrix.matrixAction()
    target = matrix.matrixTarget()
  if not target.isNil:
    handled =
      target.sendLocalIfHandled(action, ActionArgs(sender: DynamicAgent(matrix)))
  else:
    let owner = matrix.window()
    if owner of Window:
      handled = windows.sendAction(Window(owner), action, DynamicAgent(matrix))
  emit matrix.actionDidSend(DynamicAgent(matrix))
  handled

proc matrixIsEnabled(matrix: Matrix): bool =
  cells.isEnabled(Control(matrix).cell())

proc matrixSetEnabled(matrix: Matrix, enabled: bool) =
  cells.setEnabled(Control(matrix).cell(), enabled)

proc matrixCanBecomeKeyView(matrix: Matrix): bool =
  matrix.matrixIsEnabled() and View(matrix).viewCanBecomeKeyView()

proc matrixShouldBecomeFirstResponder(matrix: Matrix): bool =
  matrix.matrixIsEnabled() and matrix.acceptsFirstResponder()

proc matrixLayoutIntrinsicContentSize(matrix: Matrix): IntrinsicSize =
  initIntrinsicSize(matrix.naturalMatrixSize())

proc matrixValidateEditing(matrix: Matrix): bool =
  let editor = Control(matrix).currentEditor()
  editor.isNil or editor.validateEditing()

proc matrixAbortEditing(matrix: Matrix): bool =
  let editor = Control(matrix).currentEditor()
  if editor.isNil:
    return false
  result = editor.cancelEditing()
  if result:
    let owner = matrix.window()
    if owner of Window and Window(owner).firstResponder() == editor:
      discard Window(owner).makeFirstResponder(nil)

proc matrixIsEnabledMethod(matrix: Matrix, args: tuple[]): bool =
  discard args
  matrix.matrixIsEnabled()

proc matrixSetEnabledMethod(self: DynamicAgent, invocation: var Invocation) =
  Matrix(self).matrixSetEnabled(invocation.argsAs(bool))
  invocation.setResult(())

proc matrixCanBecomeKeyViewMethod(matrix: Matrix, args: tuple[]): bool =
  discard args
  matrix.matrixCanBecomeKeyView()

proc matrixShouldBecomeFirstResponderMethod(matrix: Matrix, args: tuple[]): bool =
  discard args
  matrix.matrixShouldBecomeFirstResponder()

proc matrixLayoutIntrinsicContentSizeMethod(
    matrix: Matrix, args: tuple[]
): IntrinsicSize =
  discard args
  matrix.matrixLayoutIntrinsicContentSize()

proc sendMatrixActionMethod(matrix: Matrix, args: tuple[]): bool =
  discard args
  matrix.sendMatrixAction()

proc matrixValidateEditingMethod(matrix: Matrix, args: tuple[]): bool =
  discard args
  matrix.matrixValidateEditing()

proc matrixAbortEditingMethod(matrix: Matrix, args: tuple[]): bool =
  discard args
  matrix.matrixAbortEditing()

proc installMatrixControlProtocol(matrix: Matrix) =
  discard matrix.replaceMethods(
    ControlProtocol,
    [
      controlIsEnabledSelector => toDynamicMethod(matrixIsEnabledMethod),
      controlSetEnabledSelector => matrixSetEnabledMethod,
      controlCanBecomeKeyViewSelector => toDynamicMethod(matrixCanBecomeKeyViewMethod),
      controlShouldBecomeFirstResponderSelector =>
        toDynamicMethod(matrixShouldBecomeFirstResponderMethod),
      controlLayoutIntrinsicContentSizeSelector =>
        toDynamicMethod(matrixLayoutIntrinsicContentSizeMethod),
      controlSendActionSelector => toDynamicMethod(sendMatrixActionMethod),
      controlValidateEditingSelector => toDynamicMethod(matrixValidateEditingMethod),
      controlAbortEditingSelector => toDynamicMethod(matrixAbortEditingMethod),
    ],
  )

protocol DefaultMatrixDrawing of ViewDrawingProtocol:
  method draw(matrix: Matrix, context: DrawContext) =
    if matrix.isNil:
      return
    matrix.normalizeLeadAndSelection()
    for index, cell in matrix.xCells:
      let focusVisible = matrix.isFocusVisible() and index == matrix.xLeadIndex
      context.drawButtonCell(cell, matrix, matrix.cellFrameAtIndex(index), focusVisible)

protocol DefaultMatrixEvents of ResponderEventProtocol:
  method mouseDown(matrix: Matrix, event: MouseEvent): bool =
    if not controlbase.isEnabled(matrix) or event.button != mbPrimary:
      return false
    let index = matrix.cellIndexAtPoint(event.location)
    if not matrix.validIndex(index) or not cells.isEnabled(matrix.xCells[index]):
      return false
    matrix.xLeadIndex = index
    matrix.setHighlightedIndex(index)
    true

  method mouseDragged(matrix: Matrix, event: MouseEvent): bool =
    if not controlbase.isEnabled(matrix) or event.button != mbPrimary:
      return false
    if matrix.xHighlightedIndex < 0:
      return false
    let index = matrix.cellIndexAtPoint(event.location)
    if index == matrix.xHighlightedIndex:
      matrix.setHighlightedIndex(index)
    else:
      matrix.setHighlightedIndex(-1)
    true

  method mouseUp(matrix: Matrix, event: MouseEvent): bool =
    if not controlbase.isEnabled(matrix) or event.button != mbPrimary:
      return false
    let
      pressedIndex = matrix.xHighlightedIndex
      releaseIndex = matrix.cellIndexAtPoint(event.location)
    matrix.clearHighlightedCell()
    if matrix.validIndex(pressedIndex) and pressedIndex == releaseIndex:
      return matrix.selectIndex(pressedIndex, notify = true)
    true

  method keyDown(matrix: Matrix, event: KeyEvent): bool =
    if not controlbase.isEnabled(matrix):
      return false
    case event.key
    of keyArrowLeft:
      matrix.moveLead(0, -1)
    of keyArrowRight:
      matrix.moveLead(0, 1)
    of keyArrowUp:
      matrix.moveLead(-1, 0)
    of keyArrowDown:
      matrix.moveLead(1, 0)
    of keyHome:
      let index = matrix.firstEnabledIndex()
      if matrix.xSelectionMode in {msmRadio, msmSingle}:
        matrix.selectIndex(index, notify = true)
      elif matrix.validIndex(index):
        matrix.xLeadIndex = index
        matrix.setNeedsDisplay(true)
        true
      else:
        false
    of keyEnd:
      var last = -1
      for index, cell in matrix.xCells:
        if not cell.isNil and cells.isEnabled(cell):
          last = index
      if matrix.xSelectionMode in {msmRadio, msmSingle}:
        matrix.selectIndex(last, notify = true)
      elif matrix.validIndex(last):
        matrix.xLeadIndex = last
        matrix.setNeedsDisplay(true)
        true
      else:
        false
    of keySpace, keyEnter:
      matrix.selectIndex(matrix.leadIndex(), notify = true)
    else:
      false

protocol DefaultMatrixAccessibility of AccessibilityProtocol:
  method accessibilityRole(matrix: Matrix): AccessibilityRole =
    arGroup

  method accessibilityLabel(matrix: Matrix): string =
    if matrix.xAccessibilityLabel.len > 0:
      matrix.xAccessibilityLabel
    else:
      matrix.identifier()

  method accessibilityValue(matrix: Matrix): string =
    let selected = matrix.selectedCell()
    if selected.isNil:
      ""
    else:
      selected.title()

  method accessibilityTraits(matrix: Matrix): AccessibilityTraits =
    result = matrix.xAccessibilityTraits
    if not controlbase.isEnabled(matrix):
      result.incl atDisabled
    if matrix.focused():
      result.incl atFocused
    if matrix.selectedIndex() >= 0:
      result.incl atSelected

  method isAccessibilityElement(matrix: Matrix): bool =
    true

proc initMatrixFields*(
    matrix: Matrix,
    rows = 1,
    columns = 1,
    prototype: ButtonCell = nil,
    frame: Rect = AutoRect,
) =
  let baseCell = newActionCell()
  initControlFields(matrix, frame, baseCell)
  matrix.xHighlightedIndex = -1
  matrix.xLeadIndex = -1
  matrix.xSelectedIndex = -1
  matrix.xSelectionMode = msmRadio
  matrix.xCellSize = AutoSize
  matrix.xIntercellSpacing = initSize(8.0, 6.0)
  matrix.setAcceptsFirstResponder(true)
  matrix.installMatrixControlProtocol()
  discard matrix.withProtocol(DefaultMatrixDrawing)
  discard matrix.withProtocol(DefaultMatrixEvents)
  discard matrix.withProtocol(DefaultMatrixAccessibility)
  matrix.configureCells(rows, columns, prototype)
  matrix.applyInitialFrame(frame)

proc newMatrix*(
    rows = 1, columns = 1, prototype: ButtonCell = nil, frame: Rect = AutoRect
): Matrix =
  result = Matrix()
  initMatrixFields(result, rows, columns, prototype, frame)

proc newRadioMatrix*(
    titles: openArray[string], columns = 1, frame: Rect = AutoRect
): Matrix =
  let prototype = newButtonCell()
  prototype.setButtonType(btRadio)
  result = newMatrix(titles.len.gridRows(columns), columns, prototype, frame)
  result.selectionMode = msmRadio
  for index, title in titles:
    result.cellAtIndex(index).setTitle(title)
  for index in titles.len ..< result.len:
    result.cellAtIndex(index).setTitle("")
    cells.setEnabled(result.cellAtIndex(index), false)
  if titles.len > 0:
    discard result.selectCellAtIndex(0)
    result.xLeadIndex = 0
  result.applyInitialFrame(frame)

proc newCheckMatrix*(
    titles: openArray[string], columns = 1, frame: Rect = AutoRect
): Matrix =
  let prototype = newButtonCell()
  prototype.setButtonType(btCheckBox)
  result = newMatrix(titles.len.gridRows(columns), columns, prototype, frame)
  result.selectionMode = msmMultiple
  for index, title in titles:
    result.cellAtIndex(index).setTitle(title)
  for index in titles.len ..< result.len:
    result.cellAtIndex(index).setTitle("")
    cells.setEnabled(result.cellAtIndex(index), false)
  result.applyInitialFrame(frame)

proc newButtonMatrix*(
    titles: openArray[string], columns = 1, frame: Rect = AutoRect
): Matrix =
  let prototype = newButtonCell()
  prototype.setButtonType(btMomentary)
  result = newMatrix(titles.len.gridRows(columns), columns, prototype, frame)
  result.selectionMode = msmNone
  for index, title in titles:
    result.cellAtIndex(index).setTitle(title)
  for index in titles.len ..< result.len:
    result.cellAtIndex(index).setTitle("")
    cells.setEnabled(result.cellAtIndex(index), false)
  result.applyInitialFrame(frame)
