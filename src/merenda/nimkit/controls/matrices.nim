import sigils/core
import sigils/selectors

import ../accessibility/accessibility
import ../app/windows except sendAction
import ../drawing
import ../foundation/events
import ../foundation/objectvalues
import ../foundation/selectors
import ../foundation/types
import ../foundation/undomanagers
import ../responder/responders
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

  MatrixItemModel* = object
    identifier*: string
    title*: string
    objectValue*: ObjectValue
    state*: ButtonState
    enabled*: bool
    hidden*: bool
    tag*: int
    tooltip*: string
    image*: ImageResource
    action*: ActionSelector
    target*: DynamicAgent
    representedObject*: DynamicAgent
    userInfo*: DynamicAgent

  Matrix* = ref object of Control
    xRows: int
    xColumns: int
    xCells: seq[ButtonCell]
    xItemModels: seq[MatrixItemModel]
    xUsesItemModels: bool
    xDataSource: DynamicAgent
    xPrototype: ButtonCell
    xSelectionMode: MatrixSelectionMode
    xCellSize: Size
    xIntercellSpacing: Size
    xHighlightedIndex: int
    xLeadIndex: int
    xSelectedIndex: int

protocol MatrixDataSource {.selectorScope: protocol.}:
  method matrixItemCount*(matrix: Matrix): int

  method matrixItemModelAtIndex*(matrix: Matrix, index: int): MatrixItemModel

  method indexOfMatrixItemModelIdentifier*(matrix: Matrix, identifier: string): int

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
  index in 0 ..< matrix.xCells.len

func cellIndex(matrix: Matrix, row, column: int): int =
  if row < 0 or column < 0 or row >= matrix.xRows or column >= matrix.xColumns:
    -1
  else:
    row * matrix.xColumns + column

func rowForIndex(matrix: Matrix, index: int): int =
  if matrix.xColumns <= 0 or index < 0:
    -1
  else:
    index div matrix.xColumns

func columnForIndex(matrix: Matrix, index: int): int =
  if matrix.xColumns <= 0 or index < 0:
    -1
  else:
    index mod matrix.xColumns

proc clearSelectionStates(matrix: Matrix, exceptIndex = -1)
proc emitSelectionChangedIfNeeded(matrix: Matrix, before: seq[int])
proc firstSelectedIndex(matrix: Matrix): int
proc normalizeLeadAndSelection(matrix: Matrix)
proc configureCells(matrix: Matrix, rows, columns: int, prototype: ButtonCell)
proc syncMatrixModelSelectionStates(matrix: Matrix)

proc reloadData*(matrix: Matrix)
proc selectedItemIdentifiers*(matrix: Matrix): seq[string]
proc `selectedItemIdentifiers=`*(matrix: Matrix, identifiers: openArray[string])
proc matrixItemModels*(matrix: Matrix): seq[MatrixItemModel]
proc `matrixItemModels=`*(matrix: Matrix, models: openArray[MatrixItemModel])
proc indexOfMatrixItemIdentifier*(matrix: Matrix, identifier: string): int

proc initMatrixItemModel*(
    identifier = "",
    title = "",
    objectValue = emptyObjectValue(),
    state = bsOff,
    enabled = true,
    hidden = false,
    tag = 0,
    tooltip = "",
    image: ImageResource = nil,
    action: ActionSelector = ActionSelector(),
    target: DynamicAgent = nil,
    representedObject: DynamicAgent = nil,
    userInfo: DynamicAgent = nil,
): MatrixItemModel =
  MatrixItemModel(
    identifier: identifier,
    title: title,
    objectValue: objectValue,
    state: state,
    enabled: enabled,
    hidden: hidden,
    tag: tag,
    tooltip: tooltip,
    image: image,
    action: action,
    target: target,
    representedObject: representedObject,
    userInfo: userInfo,
  )

proc matrixItemModel*(cell: ButtonCell): MatrixItemModel =
  initMatrixItemModel(
    title = cell.title(),
    state = cell.state(),
    enabled = cells.isEnabled(cell),
    action = cell.action(),
    target = cell.target(),
  )

proc modelIndexForVisibleIndex(matrix: Matrix, visibleIndex: int): int =
  if visibleIndex < 0:
    return -1
  var current = 0
  for index, model in matrix.xItemModels:
    if not model.hidden:
      if current == visibleIndex:
        return index
      inc current
  -1

proc visibleIndexForModelIndex(matrix: Matrix, modelIndex: int): int =
  if modelIndex < 0:
    return -1
  var current = 0
  for index, model in matrix.xItemModels:
    if not model.hidden:
      if index == modelIndex:
        return current
      inc current
  -1

proc visibleItemCount(matrix: Matrix): int =
  for model in matrix.xItemModels:
    if not model.hidden:
      inc result

proc backingIndexOfMatrixItemIdentifier(matrix: Matrix, identifier: string): int =
  if identifier.len == 0:
    return -1
  for index, model in matrix.xItemModels:
    if model.identifier == identifier:
      return index
  -1

proc identifiersToSet(identifiers: openArray[string]): seq[string] =
  for identifier in identifiers:
    if identifier.len > 0 and identifier notin result:
      result.add identifier

proc selectedStateForModel(
    matrix: Matrix, model: MatrixItemModel, selectedIdentifiers: openArray[string]
): ButtonState =
  if selectedIdentifiers.len > 0 and model.identifier.len > 0:
    if model.identifier in selectedIdentifiers: bsOn else: bsOff
  else:
    model.state

proc applyMatrixItemModelToCell(
    matrix: Matrix,
    cell: ButtonCell,
    model: MatrixItemModel,
    selectedIdentifiers: openArray[string] = [],
) =
  if cell.isNil:
    return
  cell.setTitle(model.title)
  cell.setState(matrix.selectedStateForModel(model, selectedIdentifiers))
  cells.setEnabled(cell, model.enabled)
  cell.setTarget(model.target)
  cell.setAction(model.action)

proc clearMatrixItemCell(cell: ButtonCell) =
  cell.setTitle("")
  cell.setState(bsOff)
  cells.setEnabled(cell, false)
  cell.setTarget(nil)
  cell.setAction(ActionSelector())

proc normalizeModelBackedCellSelection(matrix: Matrix) =
  if matrix.xSelectionMode in {msmRadio, msmSingle}:
    let selected = matrix.firstSelectedIndex()
    for index, cell in matrix.xCells:
      if not cell.isNil and index != selected:
        cell.setState(bsOff)
    matrix.xSelectedIndex = selected
  else:
    matrix.xSelectedIndex = matrix.firstSelectedIndex()
  matrix.normalizeLeadAndSelection()

proc syncMatrixModelSelectionStates(matrix: Matrix) =
  if not matrix.xUsesItemModels:
    return
  for visibleIndex in 0 ..< matrix.xCells.len:
    let modelIndex = matrix.modelIndexForVisibleIndex(visibleIndex)
    if modelIndex >= 0:
      let cell = matrix.xCells[visibleIndex]
      matrix.xItemModels[modelIndex].state =
        if cell.isNil:
          bsOff
        else:
          cell.state()

proc rebuildMatrixCellsFromModels(
    matrix: Matrix, selectedIdentifiers: openArray[string] = []
) =
  let
    selected = selectedIdentifiers.identifiersToSet()
    count = matrix.visibleItemCount()
    columnCount = matrix.xColumns.normalizedColumns()
    rowCount = count.gridRows(columnCount)
  matrix.configureCells(rowCount, columnCount, matrix.xPrototype)
  var visibleIndex = 0
  for model in matrix.xItemModels:
    if not model.hidden:
      matrix.applyMatrixItemModelToCell(matrix.xCells[visibleIndex], model, selected)
      inc visibleIndex
  for index in visibleIndex ..< matrix.xCells.len:
    clearMatrixItemCell(matrix.xCells[index])
  matrix.normalizeModelBackedCellSelection()
  matrix.syncMatrixModelSelectionStates()
  matrix.invalidateMatrix()

proc selectedIndexes*(matrix: Matrix): seq[int] =
  for index, cell in matrix.xCells:
    if not cell.isNil and cell.state() in {bsOn, bsMixed}:
      result.add index

proc `selectedIndexes=`*(matrix: Matrix, indexes: openArray[int]) =
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
  matrix.syncMatrixModelSelectionStates()
  matrix.emitSelectionChangedIfNeeded(before)
  matrix.invalidateMatrix()

proc sendMatrixAction(matrix: Matrix): bool

proc firstEnabledIndex(matrix: Matrix): int =
  for index, cell in matrix.xCells:
    if not cell.isNil and cells.isEnabled(cell):
      return index
  -1

proc firstSelectedIndex(matrix: Matrix): int =
  for index, cell in matrix.xCells:
    if not cell.isNil and cell.state() in {bsOn, bsMixed}:
      return index
  -1

proc normalizeLeadAndSelection(matrix: Matrix) =
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
    if matrix.xPrototype.isNil:
      newButtonCell()
    else:
      matrix.xPrototype
  prototype.copyButtonCell()

proc configureCells(matrix: Matrix, rows, columns: int, prototype: ButtonCell) =
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
  matrix.xRows

proc rowCount*(matrix: Matrix): int =
  matrix.rows()

proc columns*(matrix: Matrix): int =
  matrix.xColumns

proc columnCount*(matrix: Matrix): int =
  matrix.columns()

proc len*(matrix: Matrix): int =
  matrix.xCells.len

proc selectionMode*(matrix: Matrix): MatrixSelectionMode =
  matrix.xSelectionMode

proc `selectionMode=`*(matrix: Matrix, mode: MatrixSelectionMode) =
  if matrix.xSelectionMode == mode:
    return
  matrix.xSelectionMode = mode
  if mode in {msmRadio, msmSingle}:
    let selected = matrix.firstSelectedIndex()
    for index, cell in matrix.xCells:
      if not cell.isNil and index != selected:
        cell.setState(bsOff)
    matrix.xSelectedIndex = selected
  matrix.normalizeLeadAndSelection()
  matrix.syncMatrixModelSelectionStates()
  matrix.invalidateMatrix()

proc cellSize*(matrix: Matrix): Size =
  matrix.xCellSize

proc `cellSize=`*(matrix: Matrix, size: Size) =
  let normalized = initSize(size.width, size.height)
  if matrix.xCellSize == normalized:
    return
  matrix.xCellSize = normalized
  matrix.invalidateMatrix()

proc intercellSpacing*(matrix: Matrix): Size =
  matrix.xIntercellSpacing

proc `intercellSpacing=`*(matrix: Matrix, size: Size) =
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
  matrix.xPrototype

proc renewRowsColumns*(
    matrix: Matrix, rows, columns: int, prototype: ButtonCell = nil
) =
  if matrix.xUsesItemModels:
    let selected = matrix.selectedItemIdentifiers()
    if not prototype.isNil:
      matrix.xPrototype = prototype.copyButtonCell()
      matrix.xPrototype.setControlView(nil)
    elif matrix.xPrototype.isNil:
      matrix.xPrototype = newButtonCell()
    matrix.xColumns = columns.normalizedColumns()
    matrix.rebuildMatrixCellsFromModels(selected)
  else:
    matrix.configureCells(rows, columns, prototype)

proc dataSource*(matrix: Matrix): DynamicAgent =
  matrix.xDataSource

proc `dataSource=`*(matrix: Matrix, dataSource: DynamicAgent) =
  if matrix.xDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(MatrixDataSource)
  matrix.xDataSource = dataSource
  matrix.reloadData()

proc `dataSource=`*(matrix: Matrix, dataSource: Responder) =
  matrix.dataSource = DynamicAgent(dataSource)

proc matrixItemIdentifiers*(matrix: Matrix): seq[string] =
  if matrix.xUsesItemModels:
    for model in matrix.xItemModels:
      if not model.hidden and model.identifier.len > 0:
        result.add model.identifier

proc matrixItemAtIndex*(matrix: Matrix, index: int): MatrixItemModel =
  if matrix.xUsesItemModels:
    let modelIndex = matrix.modelIndexForVisibleIndex(index)
    if modelIndex >= 0:
      result = matrix.xItemModels[modelIndex]
      let cell = matrix.cellAtIndex(index)
      if not cell.isNil:
        result.title = cell.title()
        result.state = cell.state()
        result.enabled = cells.isEnabled(cell)
        result.action = cell.action()
        result.target = cell.target()
      return
  matrix.cellAtIndex(index).matrixItemModel()

proc matrixItemModels*(matrix: Matrix): seq[MatrixItemModel] =
  if matrix.xUsesItemModels:
    matrix.syncMatrixModelSelectionStates()
    return matrix.xItemModels
  for cell in matrix.xCells:
    result.add cell.matrixItemModel()

proc `matrixItemModels=`*(matrix: Matrix, models: openArray[MatrixItemModel]) =
  let selected = matrix.selectedItemIdentifiers()
  matrix.xDataSource = nil
  matrix.xItemModels = @models
  matrix.xUsesItemModels = true
  matrix.rebuildMatrixCellsFromModels(selected)

proc reloadData*(matrix: Matrix) =
  if matrix.xDataSource.isNil:
    if matrix.xUsesItemModels:
      matrix.rebuildMatrixCellsFromModels(matrix.selectedItemIdentifiers())
    return

  let count = matrix.xDataSource.trySendLocal(matrixItemCount(), matrix)
  if count.isNone:
    return
  let selected = matrix.selectedItemIdentifiers()
  var models: seq[MatrixItemModel]
  for index in 0 ..< count.get():
    let model = matrix.xDataSource.trySendLocal(
      matrixItemModelAtIndex(), (matrix: matrix, index: index)
    )
    if model.isSome:
      models.add model.get()
  matrix.xItemModels = models
  matrix.xUsesItemModels = true
  matrix.rebuildMatrixCellsFromModels(selected)

proc indexOfMatrixItemIdentifier*(matrix: Matrix, identifier: string): int =
  if identifier.len == 0:
    return -1
  if not matrix.xDataSource.isNil:
    let found = matrix.xDataSource.trySendLocal(
      indexOfMatrixItemModelIdentifier(), (matrix: matrix, identifier: identifier)
    )
    if found.isSome:
      return found.get()
  if matrix.xUsesItemModels:
    var visibleIndex = 0
    for model in matrix.xItemModels:
      if not model.hidden:
        if model.identifier == identifier:
          return visibleIndex
        inc visibleIndex
  -1

proc selectedItemIdentifiers*(matrix: Matrix): seq[string] =
  for index in matrix.selectedIndexes():
    let model = matrix.matrixItemAtIndex(index)
    if model.identifier.len > 0 and model.identifier notin result:
      result.add model.identifier

proc selectedItemIdentifier*(matrix: Matrix): string =
  let identifiers = matrix.selectedItemIdentifiers()
  if identifiers.len > 0:
    identifiers[0]
  else:
    ""

proc `selectedItemIdentifiers=`*(matrix: Matrix, identifiers: openArray[string]) =
  var indexes: seq[int]
  for identifier in identifiers:
    let index = matrix.indexOfMatrixItemIdentifier(identifier)
    if index >= 0 and index notin indexes:
      indexes.add index
  matrix.selectedIndexes = indexes

proc `selectedItemIdentifier=`*(matrix: Matrix, identifier: string) =
  if identifier.len > 0:
    matrix.selectedItemIdentifiers = [identifier]
  else:
    matrix.selectedItemIdentifiers = []

proc addMatrixItem*(
    matrix: Matrix, model: MatrixItemModel
): ButtonCell {.discardable.} =
  let selected = matrix.selectedItemIdentifiers()
  matrix.xUsesItemModels = true
  matrix.xItemModels.add model
  matrix.rebuildMatrixCellsFromModels(selected)
  if model.identifier.len > 0:
    return matrix.cellAtIndex(matrix.indexOfMatrixItemIdentifier(model.identifier))
  if not model.hidden:
    return matrix.cellAtIndex(matrix.visibleIndexForModelIndex(matrix.xItemModels.high))

proc insertMatrixItem*(
    matrix: Matrix, model: MatrixItemModel, index: Natural
): ButtonCell {.discardable.} =
  let
    selected = matrix.selectedItemIdentifiers()
    modelIndex = max(0, min(index.int, matrix.xItemModels.len))
  matrix.xUsesItemModels = true
  matrix.xItemModels.insert(model, modelIndex)
  matrix.rebuildMatrixCellsFromModels(selected)
  if model.identifier.len > 0:
    return matrix.cellAtIndex(matrix.indexOfMatrixItemIdentifier(model.identifier))
  if not model.hidden:
    return matrix.cellAtIndex(matrix.visibleIndexForModelIndex(modelIndex))

proc removeMatrixItemWithIdentifier*(
    matrix: Matrix, identifier: string
): bool {.discardable.} =
  let modelIndex = matrix.backingIndexOfMatrixItemIdentifier(identifier)
  if modelIndex < 0:
    return false
  var selected = matrix.selectedItemIdentifiers()
  let selectedIndex = selected.find(identifier)
  if selectedIndex >= 0:
    selected.delete(selectedIndex)
  matrix.xItemModels.delete(modelIndex)
  matrix.xUsesItemModels = true
  matrix.rebuildMatrixCellsFromModels(selected)
  true

proc removeAllMatrixItems*(matrix: Matrix) =
  matrix.xItemModels.setLen(0)
  matrix.xUsesItemModels = true
  matrix.rebuildMatrixCellsFromModels()

proc moveMatrixItem*(matrix: Matrix, fromIndex, toIndex: int): bool {.discardable.} =
  if fromIndex < 0 or fromIndex >= matrix.xItemModels.len:
    return false
  let
    selected = matrix.selectedItemIdentifiers()
    item = matrix.xItemModels[fromIndex]
  matrix.xItemModels.delete(fromIndex)
  let insertIndex = max(0, min(toIndex, matrix.xItemModels.len))
  matrix.xItemModels.insert(item, insertIndex)
  matrix.xUsesItemModels = true
  matrix.rebuildMatrixCellsFromModels(selected)
  true

proc moveMatrixItemWithIdentifier*(
    matrix: Matrix, identifier: string, toIndex: int
): bool {.discardable.} =
  matrix.moveMatrixItem(matrix.backingIndexOfMatrixItemIdentifier(identifier), toIndex)

proc selectedIndex*(matrix: Matrix): int =
  matrix.normalizeLeadAndSelection()
  matrix.xSelectedIndex

proc selectedRow*(matrix: Matrix): int =
  matrix.rowForIndex(matrix.selectedIndex())

proc selectedColumn*(matrix: Matrix): int =
  matrix.columnForIndex(matrix.selectedIndex())

proc selectedCell*(matrix: Matrix): ButtonCell =
  matrix.cellAtIndex(matrix.selectedIndex())

proc selectedCells*(matrix: Matrix): seq[ButtonCell] =
  for cell in matrix.xCells:
    if not cell.isNil and cell.state() in {bsOn, bsMixed}:
      result.add cell

proc leadIndex*(matrix: Matrix): int =
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
  if matrix.xHighlightedIndex == index:
    return
  matrix.clearHighlightedCell()
  if matrix.validIndex(index):
    matrix.xCells[index].setHighlighted(true)
    matrix.xHighlightedIndex = index
  matrix.setNeedsDisplay(true)

proc clearSelectionStates(matrix: Matrix, exceptIndex = -1) =
  for index, cell in matrix.xCells:
    if not cell.isNil and index != exceptIndex and cell.state() != bsOff:
      cell.setState(bsOff)

proc emitSelectionChangedIfNeeded(matrix: Matrix, before: seq[int]) =
  let after = matrix.selectedIndexes()
  if before != after:
    emit matrix.selectionDidChange(DynamicAgent(matrix))
    matrix.postAccessibilityNotification(anSelectionChanged)

proc selectIndex(matrix: Matrix, index: int, notify = false): bool =
  if not controlbase.isEnabled(matrix) or not matrix.validIndex(index):
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

  matrix.syncMatrixModelSelectionStates()
  matrix.emitSelectionChangedIfNeeded(before)
  matrix.setNeedsDisplay(true)
  if notify:
    discard matrix.sendMatrixAction()
  true

proc selectCellAt*(matrix: Matrix, row, column: int, notify = false): bool =
  matrix.selectIndex(matrix.cellIndex(row, column), notify)

proc selectCellAtIndex*(matrix: Matrix, index: int, notify = false): bool =
  matrix.selectIndex(index, notify)

proc selectMatrixItemWithIdentifier*(
    matrix: Matrix, identifier: string, notify = false
): bool {.discardable.} =
  let index = matrix.indexOfMatrixItemIdentifier(identifier)
  if index >= 0:
    matrix.selectCellAtIndex(index, notify)
  else:
    false

proc deselectAll*(matrix: Matrix) =
  matrix.selectedIndexes = @[]

proc cellNaturalSize(matrix: Matrix, cell: ButtonCell): Size =
  if cell.isNil:
    return initSize(0.0, 0.0)
  cell.cellSize().resolveIntrinsicSize(matrix.bounds().size)

proc resolvedCellSize(matrix: Matrix): Size =
  if matrix.xCellSize.hasWidth and matrix.xCellSize.hasHeight:
    return matrix.xCellSize
  var natural = initSize(0.0, 0.0)
  for cell in matrix.xCells:
    let cellSize = matrix.cellNaturalSize(cell)
    natural.width = max(natural.width, cellSize.width)
    natural.height = max(natural.height, cellSize.height)
  matrix.xCellSize.resolveAutoSize(natural)

proc naturalMatrixSize(matrix: Matrix): Size =
  if matrix.xRows <= 0 or matrix.xColumns <= 0:
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
    return rect(0.0, 0.0, 0.0, 0.0)
  let
    cellSize = matrix.resolvedCellSize()
    row = matrix.rowForIndex(index)
    column = matrix.columnForIndex(index)
  rect(
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
  if not matrix.bounds().contains(point):
    return -1
  for index in 0 ..< matrix.xCells.len:
    if matrix.cellFrameAtIndex(index).contains(point):
      return index
  -1

proc moveLead(matrix: Matrix, rowDelta, columnDelta: int, notify = true): bool =
  if matrix.xRows <= 0 or matrix.xColumns <= 0:
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
