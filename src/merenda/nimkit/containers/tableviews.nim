import std/[algorithm, math, options, strutils, tables, times]

from figdraw/fignodes import FigIdx
import sigils/core

import ../accessibility/accessibilityprotocols
import ../drawing
import ../foundation/events
import ../app/dragging
import ../app/pasteboards
import ../app/userdefaults
import ../app/windows
import ../controls/controls
import ../containers/listbasics
import ../containers/scrollviews
import ../foundation/objectvalues
import ../foundation/selectors
import ../themes
import ../text/fieldeditors
import ../text/textviews
import ../foundation/types
import ../foundation/undomanagers
import ../view/views

const
  TableTypeSelectTimeout = 1.0
  TablePasteboardTypeRows* = "nimkit.table.rows"
  TablePasteboardTypeRowIdentifiers* = "nimkit.table.row-identifiers"
  TablePasteboardTypeColumns* = "nimkit.table.columns"
  TableSelectionIdentityPrefix = "ids:"

type
  TableModelError* = object of KeyError

  TableSelectionMode* = enum
    lsmNone
    lsmSingle
    lsmMultiple
    lsmExtended

  TableRowView = ref object of View
    xTableView: TableView
    xRow: RowState

  TableContentView = ref object of View
    xTableView: TableView
    xRowViews: seq[TableRowView]

  TableVisibleRowSummary* = object
    index*: int
    text*: string
    rect*: Rect
    states*: set[WidgetState]

  TableColumnResizePolicy* = enum
    tcrFixed
    tcrResizable

  TableSortDirection* = enum
    tsdNone
    tsdAscending
    tsdDescending

  TableRowUpdateKind* = enum
    trukInsert
    trukRemove
    trukMove
    trukReload

  TableRowUpdate* = object
    kind*: TableRowUpdateKind
    indexes*: seq[int]
    fromIndex*: int
    toIndex*: int
    identifiers*: seq[string]

  TableCellValue* = object
    columnIdentifier*: string
    value*: ObjectValue

  TableRowValue* = object
    identifier*: string
    objectValue*: ObjectValue
    cells*: seq[TableCellValue]
    enabled*: bool
    hidden*: bool
    representedObject*: DynamicAgent

  TableModelColumn* = object
    identifier*: string
    title*: string
    valueKey*: string
    width*: float32
    hidden*: bool

  TableModelSortDescriptor* = object
    columnIdentifier*: string
    direction*: TableSortDirection

  TableModelFilter* = proc(row: TableRowValue): bool {.closure.}

  TableRowIdentifierResolver* = proc(identifier: string): string {.closure.}

  TableModel* = ref object of DynamicAgent
    xRows: seq[TableRowValue]
    xColumns: seq[TableModelColumn]
    xSortDescriptors: seq[TableModelSortDescriptor]
    xFilter: TableModelFilter

  TableViewStateScope* = enum
    tvssAutomatic
    tvssApplication
    tvssDocument
    tvssWorkspace

  TableHeaderHitPart* = enum
    thpNone
    thpColumn
    thpResizeHandle

  TableHeaderDragIndicator* = object
    index*: int
    rect*: Rect
    visible*: bool

  TableHeaderChrome* = object
    headerFill*: Fill
    headerBorderColor*: Color
    cellFill*: Fill
    hoveredCellFill*: Fill
    pressedCellFill*: Fill
    cellBorderColor*: Color
    textColor*: Color
    sortIndicatorColor*: Color
    insertionIndicatorFill*: Fill
    borderWidth*: float32
    sortIndicatorWidth*: float32
    insertionWidth*: float32
    insertionCapWidth*: float32
    insertionCapHeight*: float32
    cornerRadius*: float32

  TableHeaderHit* = object
    column*: TableColumn
    columnIndex*: int
    part*: TableHeaderHitPart
    rect*: Rect

  TableEditingState* = object
    row*: int
    column*: TableColumn
    active*: bool
    validationError*: string
    validation*: ObjectValidationError
    objectValue*: ObjectValue

  TableColumnAutosaveRecord* = object
    identifier*: string
    width*: float32
    hidden*: bool
    sortDirection*: TableSortDirection

  TableViewState* = object
    columns*: seq[TableColumnAutosaveRecord]
    selectedRows*: seq[int]
    selectedRowIdentifiers*: seq[string]
    selectedColumns*: seq[string]
    expandedItems*: seq[string]

  TableViewStateStore* = ref object of DynamicAgent
    xStates: Table[string, TableViewState]

  TableView* = ref object of Control
    xColumns: seq[TableColumn]
    xSelectedIndex: int
    xSelectedIndexes: seq[int]
    xSelectionAnchor: int
    xSelectionLead: int
    xHighlightedIndex: int
    xScrollView: ScrollView
    xContentView: TableContentView
    xRowHeight: float32
    xVisibleRows: int
    xRowHeights: seq[float32]
    xRowOffsets: seq[float32]
    xRowHeightCacheValid: bool
    xComputingRowHeights: bool
    xSelectionMode: TableSelectionMode
    xTrackingItem: bool
    xPressedIndex: int
    xTypeSelectBuffer: string
    xTypeSelectLastTime: float
    xUsesAlternatingRowBackgrounds: bool
    xShowsRowSeparators: bool
    xTableRole: StyleRole
    xItemRole: StyleRole
    xRowCount: int
    xTableDataSource: DynamicAgent
    xTableDelegate: DynamicAgent
    xCellSlots: seq[TableCellSlot]
    xReusableCellViews: Table[string, seq[View]]
    xShowsHeader: bool
    xHeaderHeight: float32
    xHoveredColumn: TableColumn
    xPressedColumn: TableColumn
    xClickedRow: int
    xClickedColumn: TableColumn
    xSelectedColumns: seq[TableColumn]
    xAllowsColumnSelection: bool
    xEditing: TableEditingState
    xAutosaveName: string
    xStateStorage: DynamicAgent
    xStateScope: TableViewStateScope
    xWorkspaceIdentifier: string
    xHasRestoredState: bool
    xObservedStateWindow: Window
    xColumnAutosaveAliases: Table[string, string]
    xRowIdentifierAliases: Table[string, string]
    xRowIdentifierResolver: TableRowIdentifierResolver
    xBatchUpdateDepth: int
    xPendingRowUpdates: seq[TableRowUpdate]
    xTableDraggingSession: DraggingSession
    xTableDropTarget: DraggingDropTarget
    xEditingHostView: View
    xEditingCell: Cell
    xEditingHostIsRowView: bool
    xCancellingFieldEditor: bool
    xEndedEditingRow: int
    xEndedEditingColumn: TableColumn
    xEndedEditingCommitted: bool
    xHeaderTrackingPart: TableHeaderHitPart
    xTrackingColumn: TableColumn
    xTrackingColumnIndex: int
    xHeaderDragInsertionIndex: int
    xHeaderDragInsertionRect: Rect
    xHeaderDraggingColumn: bool
    xAllowsRowReordering: bool
    xRowDragStartIndex: int
    xRowDragStartPoint: Point
    xDragStartPoint: Point
    xDragStartWidth: float32

  TableCellSlot = object
    row: int
    column: TableColumn
    view: View

  TableColumn* = ref object
    xTableView: TableView
    xIdentifier: string
    xTitle: string
    xWidth: float32
    xMinWidth: float32
    xMaxWidth: float32
    xAlignment: TextAlignment
    xResizePolicy: TableColumnResizePolicy
    xHidden: bool
    xSortDirection: TableSortDirection
    xReuseIdentifier: string
    xStyleId: string
    xStyleClasses: seq[string]
    xUserInfo: DynamicAgent

const
  tsmNone* = TableSelectionMode.lsmNone
  tsmSingle* = TableSelectionMode.lsmSingle
  tsmMultiple* = TableSelectionMode.lsmMultiple
  tsmExtended* = TableSelectionMode.lsmExtended

const TableViewStateDefaultsPrefix = "nimkit.table.state."

proc noteColumnsChanged(tableView: TableView)
proc detachColumn(column: TableColumn)
proc removeColumnAtIndex(tableView: TableView, index: int)
proc removeColumnAt*(tableView: TableView, index: int)
proc resolvedRowCount(tableView: TableView): int
proc tableRowEnabled(tableView: TableView, row: int): bool
proc tableRowSelectable(tableView: TableView, row: int): bool
proc tableView*(contentView: TableContentView): TableView
proc scrollView*(tableView: TableView): ScrollView
proc contentView*(tableView: TableView): TableContentView
proc initTableRowView(tableView: TableView): TableRowView
proc syncVisibleRowViews(contentView: TableContentView)
proc viewportSize(tableView: TableView): Size
proc tableContentItemRect*(contentView: TableContentView, itemIndex: int): Rect
proc tableContentItemIndexAtPoint*(contentView: TableContentView, point: Point): int
proc visibleContentRows(contentView: TableContentView): tuple[first, last: int]
proc invalidateTableRows(tableView: TableView)
proc rowHeight*(tableView: TableView): float32
proc rowHeightForRow*(tableView: TableView, row: int): float32
proc reloadData*(tableView: TableView)
proc rowEnabled*(tableView: TableView, row: int): bool
proc rowSelectable*(tableView: TableView, row: int): bool
proc tableRowIdentifier*(tableView: TableView, row: int): string
proc tableRowIndexForIdentifier*(tableView: TableView, identifier: string): int
proc rowIdentifiersForRows(tableView: TableView, rows: openArray[int]): seq[string]
proc applySelectionForRowIdentifiers(
  tableView: TableView,
  identifiers: openArray[string],
  anchorIdentifier, leadIdentifier: string,
)

proc highlightedIndex*(tableView: TableView): int
proc usesAlternatingRowBackgrounds*(tableView: TableView): bool
proc selectionMode*(tableView: TableView): TableSelectionMode
proc `selectedIndexes=`*(tableView: TableView, indexes: openArray[int])
proc selectedRanges*(tableView: TableView): seq[Slice[int]]
proc uncachedRowHeightForRow(tableView: TableView, index: int): float32
proc invalidateRowHeightCache(tableView: TableView)
proc rowOffset(tableView: TableView, index: int): float32
proc rowIndexAtContentY(tableView: TableView, y: float32): int
proc contentHeight(tableView: TableView): float32
proc visibleRowsFrom(tableView: TableView, firstIndex: int, height: float32): int
proc maxFirstVisibleIndex(tableView: TableView): int
proc tileTableContent(tableView: TableView)
proc listContentOffset(tableView: TableView): Point
proc setTableContentOffset(tableView: TableView, offset: Point, invalidate: bool)
proc scrollItemToVisible(tableView: TableView, itemIndex: int)
proc selectedIndex*(tableView: TableView): int
proc len*(tableView: TableView): int
proc allowsRowReordering*(tableView: TableView): bool
proc reorderRows*(
  tableView: TableView, rows: openArray[int], target: DraggingDropTarget
): bool

proc visibleItemCount*(tableView: TableView): int
proc firstVisibleIndex*(tableView: TableView): int
proc scrollRows*(tableView: TableView, delta: int)
proc selectionLeadIndex(tableView: TableView): int
proc normalizeSelection(tableView: TableView, indexes: openArray[int]): seq[int]
proc firstSelectedIndex(tableView: TableView, indexes: openArray[int]): int
proc syncSelectedIndex(tableView: TableView)
proc syncSelectionCursor(tableView: TableView)
proc indexesInRange(selectionRange: Slice[int]): seq[int]
proc applySelectedIndexes(
  tableView: TableView, indexes: openArray[int], anchor: int, lead: int
)

proc selectItemAtIndex(tableView: TableView, index: int)
proc selectItemAtIndex(tableView: TableView, index: int, modifiers: set[KeyModifier])
proc activateItemAtIndex(tableView: TableView, index: int, modifiers: set[KeyModifier])
proc tableRowState(tableView: TableView, index: int): RowState
proc drawTableRowItem*(
  tableView: TableView, context: DrawContext, rect: Rect, row: RowState
)

proc autoscrollDraggingInfo(tableView: TableView, info: DraggingInfo): bool
proc normalizedReorderRows(tableView: TableView, rows: openArray[int]): seq[int]
proc insertionIndexForDropTarget(tableView: TableView, target: DraggingDropTarget): int
proc canReorderRows(
  tableView: TableView, rows: openArray[int], target: DraggingDropTarget
): bool

proc updateTableDropTarget(tableView: TableView, target: DraggingDropTarget)
proc tableHeaderHeight*(tableView: TableView): float32
proc defaultTableHeaderChrome*(): TableHeaderChrome
proc headerDragIndicator*(tableView: TableView): TableHeaderDragIndicator
proc resolvedRowHeight(tableView: TableView, row: int): float32
proc tableRowDidActivate(tableView: TableView, row: int)
proc tableColumnAtPoint(tableView: TableView, point: Point): TableColumn
proc headerInsertionIndexAtPoint(tableView: TableView, point: Point): int
proc headerInsertionRectForIndex(tableView: TableView, index: int): Rect
proc clearHeaderDragInsertion(tableView: TableView)
proc setHeaderDragInsertion(tableView: TableView, index: int)
proc autoscrollHeaderColumnDrag(tableView: TableView, point: Point): bool
proc syncHeaderTrackingAreas(tableView: TableView)
proc resetHeaderCursorRects(tableView: TableView)
proc tableCellHitPolicy(
  tableView: TableView, row: int, column: TableColumn, target: View, event: MouseEvent
): CellHitPolicy

proc defaultTableViewMouseDown*(tableView: TableView, event: MouseEvent): bool
proc defaultTableViewMouseDragged*(tableView: TableView, event: MouseEvent): bool
proc defaultTableViewMouseUp*(tableView: TableView, event: MouseEvent): bool
proc defaultTableViewKeyDown*(tableView: TableView, event: KeyEvent): bool

proc tableCellText*(tableView: TableView, row: int, column: TableColumn): string
proc tableCellObjectValue*(
  tableView: TableView, row: int, column: TableColumn
): ObjectValue

proc writeTableCellObjectValue*(
  tableView: TableView, row: int, column: TableColumn, value: ObjectValue
): bool

proc tableCellView*(tableView: TableView, row: int, column: TableColumn): View
proc rowCount*(tableView: TableView): int
proc columnAt*(tableView: TableView, index: int): TableColumn
proc enqueueReusableCellView(tableView: TableView, identifier: string, view: View)
proc recycleCellSlot(tableView: TableView, slot: TableCellSlot)
proc clearTableCellSlots(tableView: TableView)
proc syncVisibleTableCells(tableView: TableView)
proc prepareEditingSurface(tableView: TableView): bool
proc clearEditingSurface(tableView: TableView)
proc validateEditingValue(tableView: TableView, value: string): bool
proc parseEditingObjectValue(tableView: TableView, value: string): ObjectParseResult
proc finishCommitEditingCell(tableView: TableView, value: string): bool
proc finishCancelEditingCell(tableView: TableView): bool
proc moveEditingFromEndedCell(tableView: TableView, movement: TextEditMovement): bool
proc drawTableRow(tableView: TableView, context: DrawContext, rect: Rect, row: RowState)
proc resolveTableViewStateStorage(tableView: TableView): DynamicAgent
proc restoreStateIfNeeded(tableView: TableView)
proc observeTableStateWindow(tableView: TableView, window: Window)
proc unobserveTableStateWindow(tableView: TableView)
proc resolveColumnAutosaveIdentifier(tableView: TableView, identifier: string): string

proc drawTableDropTarget(
  tableView: TableView, context: DrawContext, rect: Rect, row: RowState
)

proc drawTableHeaderBackground*(
  tableView: TableView, context: DrawContext, rect: Rect, chrome: TableHeaderChrome
)

proc drawTableHeaderCellChrome*(
  tableView: TableView,
  context: DrawContext,
  column: TableColumn,
  rect: Rect,
  chrome: TableHeaderChrome,
  firstVisible = false,
  lastVisible = false,
)

proc drawTableHeaderCellTitle*(
  tableView: TableView,
  context: DrawContext,
  column: TableColumn,
  rect: Rect,
  chrome: TableHeaderChrome,
)

proc drawTableHeaderInsertionIndicator*(
  tableView: TableView, context: DrawContext, chrome: TableHeaderChrome
)

proc drawTableHeaderSortIndicator*(
  tableView: TableView,
  context: DrawContext,
  rect: Rect,
  direction: TableSortDirection,
  chrome: TableHeaderChrome,
)

proc drawTableHeaderResizeHandle*(
  tableView: TableView,
  context: DrawContext,
  column: TableColumn,
  rect: Rect,
  chrome: TableHeaderChrome,
)

proc syncTableScrollChrome(tableView: TableView)
proc tableFocusRingBox(box: ControlBoxStyle): ControlBoxStyle

proc raiseTableModelError(message: string) {.noinline, noreturn.} =
  raise newException(TableModelError, message)

proc installTableModelProtocols(model: TableModel)

func tableCell*(columnIdentifier: string, value: ObjectValue): TableCellValue =
  TableCellValue(columnIdentifier: columnIdentifier, value: value)

proc tableRow*(
    identifier = "",
    objectValue = emptyObjectValue(),
    cells: openArray[TableCellValue] = [],
    enabled = true,
    hidden = false,
    representedObject: DynamicAgent = nil,
): TableRowValue =
  TableRowValue(
    identifier: identifier,
    objectValue: objectValue,
    cells: @cells,
    enabled: enabled,
    hidden: hidden,
    representedObject: representedObject,
  )

func initTableModelColumn*(
    identifier: string, title = "", valueKey = "", width = 120.0'f32, hidden = false
): TableModelColumn =
  TableModelColumn(
    identifier: identifier,
    title: title,
    valueKey: valueKey,
    width: width,
    hidden: hidden,
  )

func initTableModelSortDescriptor*(
    columnIdentifier: string, direction = tsdAscending
): TableModelSortDescriptor =
  TableModelSortDescriptor(columnIdentifier: columnIdentifier, direction: direction)

func defaultTableRowUpdate(
    kind: TableRowUpdateKind,
    indexes: openArray[int] = [],
    identifiers: openArray[string] = [],
    fromIndex = -1,
    toIndex = -1,
): TableRowUpdate =
  TableRowUpdate(
    kind: kind,
    indexes: @indexes,
    fromIndex: fromIndex,
    toIndex: toIndex,
    identifiers: @identifiers,
  )

func initTableRowInsertUpdate*(
    indexes: openArray[int], identifiers: openArray[string] = []
): TableRowUpdate =
  defaultTableRowUpdate(trukInsert, indexes, identifiers)

func initTableRowRemoveUpdate*(
    indexes: openArray[int], identifiers: openArray[string] = []
): TableRowUpdate =
  defaultTableRowUpdate(trukRemove, indexes, identifiers)

func initTableRowReloadUpdate*(
    indexes: openArray[int], identifiers: openArray[string] = []
): TableRowUpdate =
  defaultTableRowUpdate(trukReload, indexes, identifiers)

func initTableRowMoveUpdate*(
    fromIndex, toIndex: int, identifiers: openArray[string] = []
): TableRowUpdate =
  defaultTableRowUpdate(
    trukMove, identifiers = identifiers, fromIndex = fromIndex, toIndex = toIndex
  )

func findCellIndex(row: TableRowValue, columnIdentifier: string): int =
  for index, cell in row.cells:
    if cell.columnIdentifier == columnIdentifier:
      return index
  -1

func hasValue*(row: TableRowValue, columnIdentifier: string): bool =
  columnIdentifier.len == 0 or row.findCellIndex(columnIdentifier) >= 0

func getValue*(row: TableRowValue, columnIdentifier = ""): Option[ObjectValue] =
  if columnIdentifier.len == 0:
    return some(row.objectValue)
  let index = row.findCellIndex(columnIdentifier)
  if index >= 0:
    some(row.cells[index].value)
  else:
    none(ObjectValue)

proc value*(
    row: TableRowValue, columnIdentifier = ""
): ObjectValue {.raises: [TableModelError].} =
  let found = row.getValue(columnIdentifier)
  if found.isSome:
    return found.get()
  raiseTableModelError("unknown table cell column identifier: " & columnIdentifier)

proc `[]`*(row: TableRowValue, columnIdentifier: string): ObjectValue =
  row.value(columnIdentifier)

proc setValue*(row: var TableRowValue, columnIdentifier: string, value: ObjectValue) =
  if columnIdentifier.len == 0:
    row.objectValue = value
    return
  let index = row.findCellIndex(columnIdentifier)
  if index >= 0:
    row.cells[index].value = value
  else:
    row.cells.add tableCell(columnIdentifier, value)

proc `[]=`*(row: var TableRowValue, columnIdentifier: string, value: ObjectValue) =
  row.setValue(columnIdentifier, value)

protocol TableViewDataSource {.selectorScope: protocol.}:
  method numberOfRows*(tableView: TableView): int {.optional.}
  method textForCell*(
    tableView: TableView, row: int, column: TableColumn
  ): string {.optional.}

  method objectValueForCell*(
    tableView: TableView, row: int, column: TableColumn
  ): ObjectValue {.optional.}

  method setObjectValueForCell*(
    tableView: TableView, row: int, column: TableColumn, value: ObjectValue
  ): bool {.optional.}

  method identifierForRow*(tableView: TableView, row: int): string {.optional.}
  method rowForIdentifier*(tableView: TableView, identifier: string): int {.optional.}

protocol TableViewEvents:
  proc selectionIsChanging*(tableView: TableView, sender: DynamicAgent) {.signal.}
  proc selectionDidChange*(tableView: TableView, sender: DynamicAgent) {.signal.}
  proc rowWasActivated*(tableView: TableView, sender: DynamicAgent) {.signal.}
  proc cellEditDidCommit*(
    tableView: TableView,
    sender: DynamicAgent,
    row: int,
    column: TableColumn,
    value: string,
  ) {.signal.}

  proc cellObjectValueDidCommit*(
    tableView: TableView,
    sender: DynamicAgent,
    row: int,
    column: TableColumn,
    value: ObjectValue,
  ) {.signal.}

  proc tableRowsDidUpdate*(
    tableView: TableView, sender: DynamicAgent, updates: seq[TableRowUpdate]
  ) {.signal.}

protocol TableViewDelegate {.selectorScope: protocol.}:
  method viewForCell*(
    tableView: TableView, row: int, column: TableColumn
  ): View {.optional.}

  method tableRowHeight*(tableView: TableView, row: int): float32 {.optional.}
  method isRowEnabled*(tableView: TableView, row: int): bool {.optional.}
  method shouldSelectTableRow*(tableView: TableView, row: int): bool {.optional.}
  method didSelectTableRow*(tableView: TableView, row: int) {.optional.}
  method shouldTrackCell*(
    tableView: TableView, row: int, column: TableColumn, target: View
  ): bool {.optional.}

  method hitPolicyForCell*(
    tableView: TableView, row: int, column: TableColumn, target: View, event: MouseEvent
  ): CellHitPolicy {.optional.}

  method didActivateRow*(tableView: TableView, row: int) {.optional.}
  method sortDescriptorsDidChange*(
    tableView: TableView, column: TableColumn, direction: TableSortDirection
  ) {.optional.}

  method shouldEditCell*(
    tableView: TableView, row: int, column: TableColumn
  ): bool {.optional.}

  method didBeginEditingCell*(
    tableView: TableView, row: int, column: TableColumn
  ) {.optional.}

  method fieldEditorFrameForCell*(
    tableView: TableView, row: int, column: TableColumn, proposedFrame: Rect
  ): Rect {.optional.}

  method validationErrorForCell*(
    tableView: TableView, row: int, column: TableColumn, value: string
  ): string {.optional.}

  method parseObjectValueForCell*(
    tableView: TableView, row: int, column: TableColumn, value: string
  ): ObjectParseResult {.optional.}

  method validationErrorForObjectValue*(
    tableView: TableView, row: int, column: TableColumn, value: ObjectValue
  ): ObjectValidationError {.optional.}

  method didCommitEditingCell*(
    tableView: TableView, row: int, column: TableColumn, value: string
  ) {.optional.}

  method didCommitEditingObjectValue*(
    tableView: TableView, row: int, column: TableColumn, value: ObjectValue
  ) {.optional.}

  method didCancelEditingCell*(
    tableView: TableView, row: int, column: TableColumn
  ) {.optional.}

  method validateDragOperation*(
    tableView: TableView, info: DraggingInfo
  ): DragOperations {.optional.}

  method acceptDragOperation*(
    tableView: TableView, info: DraggingInfo
  ): bool {.optional.}

  method validateDropOperation*(
    tableView: TableView,
    info: DraggingInfo,
    proposedOperation: DragOperations,
    target: DraggingDropTarget,
    position: DraggingDropPosition,
  ): DragOperations {.optional.}

  method acceptDropOperation*(
    tableView: TableView,
    info: DraggingInfo,
    operation: DragOperations,
    target: DraggingDropTarget,
    position: DraggingDropPosition,
  ): bool {.optional.}

  method tableDropTargetForLocation*(
    tableView: TableView, location: Point, proposedTarget: DraggingDropTarget
  ): DraggingDropTarget {.optional.}

  method shouldReorderRows*(
    tableView: TableView, rows: seq[int], target: DraggingDropTarget
  ): bool {.optional.}

  method performRowReorder*(
    tableView: TableView, rows: seq[int], target: DraggingDropTarget
  ): bool {.optional.}

  method drawRow*(
    tableView: TableView, context: DrawContext, rect: Rect, row: RowState
  ) {.optional.}

protocol TableViewEditingProtocol:
  method shouldBeginEditingCell*(row: int, column: TableColumn): bool
  method beginEditingCell*(row: int, column: TableColumn): bool
  method commitEditingCell*(value: string = ""): bool
  method cancelEditingCell*(): bool

protocol TableViewColumnProtocol:
  method columnAtPoint*(point: Point): TableColumn
  method headerHitTest*(point: Point): TableHeaderHit
  method resizeColumn*(column: TableColumn, width: float32)
  method moveColumn*(fromIndex, toIndex: int)
  method requestSort*(column: TableColumn, direction: TableSortDirection)
  method headerMouseDown*(event: MouseEvent): bool
  method headerMouseDragged*(event: MouseEvent): bool
  method headerMouseUp*(event: MouseEvent): bool
  method headerMouseMoved*(event: MouseEvent): bool

const
  TableHeaderTrackingTag = 0x74001
  TableHeaderResizeCursorName = "resizeLeftRight"

protocol TableViewSelectionProtocol:
  method shouldSelectCell*(row: int, column: TableColumn): bool
  method selectCell*(row: int, column: TableColumn)
  method setSelectedColumns*(columns: seq[TableColumn])
  method selectionPersistenceString*(): string
  method restoreSelectionPersistenceString*(value: string)

protocol TableViewDraggingProtocol:
  method beginDraggingRows*(
    rows: seq[int], operations: DragOperations, pasteboardName: string
  ): DraggingSession

  method beginDraggingColumns*(
    columns: seq[TableColumn], operations: DragOperations, pasteboardName: string
  ): DraggingSession

  method validateDragging*(info: DraggingInfo): DragOperations
  method acceptDragging*(info: DraggingInfo): bool
  method reorderTableRows*(rows: seq[int], target: DraggingDropTarget): bool

protocol TableViewPersistenceProtocol:
  method columnAutosaveRecords*(): seq[TableColumnAutosaveRecord]
  method restoreColumnAutosaveRecords*(records: seq[TableColumnAutosaveRecord])

protocol TableViewStateProtocol:
  method captureState*(): TableViewState
  method restoreState*(state: TableViewState)

protocol TableViewStateStorageProtocol:
  method saveTableViewState*(name: string, state: TableViewState) {.optional.}
  method loadTableViewState*(name: string): TableViewState {.optional.}
  method hasTableViewState*(name: string): bool {.optional.}

func tableModelColumnIdentifier(column: TableModelColumn): string =
  if column.identifier.len > 0: column.identifier else: column.valueKey

func tableModelColumnTitle(column: TableModelColumn): string =
  if column.title.len > 0:
    column.title
  elif column.identifier.len > 0:
    column.identifier
  else:
    column.valueKey

proc tableModelColumnKey(model: TableModel, column: TableColumn): string =
  if column.isNil:
    return ""
  let identifier = column.xIdentifier
  if not model.isNil:
    for modelColumn in model.xColumns:
      if modelColumn.tableModelColumnIdentifier() == identifier:
        if modelColumn.valueKey.len > 0:
          return modelColumn.valueKey
        return modelColumn.tableModelColumnIdentifier()
  identifier

proc compareTableObjectValues(a, b: ObjectValue): int =
  case a.kind
  of ovInt:
    if b.kind == ovInt:
      return cmp(a.intValue, b.intValue)
    if b.kind == ovFloat:
      return cmp(a.intValue.float, b.floatValue)
  of ovFloat:
    if b.kind == ovFloat:
      return cmp(a.floatValue, b.floatValue)
    if b.kind == ovInt:
      return cmp(a.floatValue, b.intValue.float)
  of ovString:
    if b.kind == ovString:
      return cmp(a.text, b.text)
  of ovBool:
    if b.kind == ovBool:
      return cmp(a.boolValue, b.boolValue)
  else:
    discard
  cmp(a.formatObjectValue(), b.formatObjectValue())

proc compareTableRows(
    a, b: TableRowValue, descriptors: openArray[TableModelSortDescriptor]
): int =
  for descriptor in descriptors:
    if descriptor.direction == tsdNone:
      continue
    let
      left = a.getValue(descriptor.columnIdentifier).get(emptyObjectValue())
      right = b.getValue(descriptor.columnIdentifier).get(emptyObjectValue())
    result = compareTableObjectValues(left, right)
    if result != 0:
      if descriptor.direction == tsdDescending:
        result = -result
      return

proc sourceIndexOfIdentifier(model: TableModel, identifier: string): int =
  if model.isNil or identifier.len == 0:
    return -1
  for index, row in model.xRows:
    if row.identifier == identifier:
      return index
  -1

proc arrangedSourceIndexes(model: TableModel): seq[int] =
  if model.isNil:
    return
  for index, row in model.xRows:
    if row.hidden:
      continue
    if not model.xFilter.isNil and not model.xFilter(row):
      continue
    result.add index
  if model.xSortDescriptors.len > 0:
    result.sort(
      proc(a, b: int): int =
        compareTableRows(model.xRows[a], model.xRows[b], model.xSortDescriptors)
    )

proc arrangedSourceIndex(model: TableModel, index: int): int =
  let indexes = model.arrangedSourceIndexes()
  if index in 0 ..< indexes.len:
    indexes[index]
  else:
    -1

proc initTableModelFields*(
    model: TableModel,
    rows: openArray[TableRowValue] = [],
    columns: openArray[TableModelColumn] = [],
) =
  model.xRows = @rows
  model.xColumns = @columns
  model.installTableModelProtocols()

proc newTableModel*(
    rows: openArray[TableRowValue] = [], columns: openArray[TableModelColumn] = []
): TableModel =
  result = TableModel()
  result.initTableModelFields(rows, columns)

proc len*(model: TableModel): int =
  model.arrangedSourceIndexes().len

proc sourceLen*(model: TableModel): int =
  if model.isNil: 0 else: model.xRows.len

proc rows*(model: TableModel): seq[TableRowValue] =
  if model.isNil:
    @[]
  else:
    model.xRows

proc `rows=`*(model: TableModel, rows: openArray[TableRowValue]) =
  if not model.isNil:
    model.xRows = @rows

proc arrangedRows*(model: TableModel): seq[TableRowValue] =
  for index in model.arrangedSourceIndexes():
    result.add model.xRows[index]

proc columns*(model: TableModel): seq[TableModelColumn] =
  if model.isNil:
    @[]
  else:
    model.xColumns

proc `columns=`*(model: TableModel, columns: openArray[TableModelColumn]) =
  if not model.isNil:
    model.xColumns = @columns

proc sortDescriptors*(model: TableModel): seq[TableModelSortDescriptor] =
  if model.isNil:
    @[]
  else:
    model.xSortDescriptors

proc `sortDescriptors=`*(
    model: TableModel, descriptors: openArray[TableModelSortDescriptor]
) =
  if not model.isNil:
    model.xSortDescriptors = @descriptors

proc filter*(model: TableModel): TableModelFilter =
  if model.isNil: nil else: model.xFilter

proc `filter=`*(model: TableModel, filter: TableModelFilter) =
  if not model.isNil:
    model.xFilter = filter

proc getRowAt*(model: TableModel, index: int): Option[TableRowValue] =
  let sourceIndex = model.arrangedSourceIndex(index)
  if sourceIndex >= 0:
    some(model.xRows[sourceIndex])
  else:
    none(TableRowValue)

proc rowAt*(model: TableModel, index: int): TableRowValue =
  let found = model.getRowAt(index)
  if found.isSome:
    return found.get()
  tableRow()

proc getRowWithIdentifier*(
    model: TableModel, identifier: string
): Option[TableRowValue] =
  let index = model.sourceIndexOfIdentifier(identifier)
  if index >= 0:
    some(model.xRows[index])
  else:
    none(TableRowValue)

proc rowWithIdentifier*(
    model: TableModel, identifier: string
): TableRowValue {.raises: [TableModelError].} =
  let found = model.getRowWithIdentifier(identifier)
  if found.isSome:
    return found.get()
  raiseTableModelError("unknown table row identifier: " & identifier)

proc indexOfIdentifier*(model: TableModel, identifier: string): int =
  let indexes = model.arrangedSourceIndexes()
  for arrangedIndex, sourceIndex in indexes:
    if model.xRows[sourceIndex].identifier == identifier:
      return arrangedIndex
  -1

proc addRow*(model: TableModel, row: TableRowValue) =
  if model.isNil:
    return
  if row.identifier.len > 0 and model.sourceIndexOfIdentifier(row.identifier) >= 0:
    raiseTableModelError("duplicate table row identifier: " & row.identifier)
  model.xRows.add row

proc insertRow*(model: TableModel, row: TableRowValue, index: int) =
  if model.isNil:
    return
  if row.identifier.len > 0 and model.sourceIndexOfIdentifier(row.identifier) >= 0:
    raiseTableModelError("duplicate table row identifier: " & row.identifier)
  let insertIndex = max(0, min(index, model.xRows.len))
  model.xRows.insert(row, insertIndex)

proc removeRow*(model: TableModel, identifier: string): bool {.discardable.} =
  let index = model.sourceIndexOfIdentifier(identifier)
  if index < 0:
    return false
  model.xRows.delete(index)
  true

proc moveRow*(model: TableModel, identifier: string, toIndex: int): bool =
  let index = model.sourceIndexOfIdentifier(identifier)
  if index < 0:
    return false
  let row = model.xRows[index]
  model.xRows.delete(index)
  let insertIndex = max(0, min(toIndex, model.xRows.len))
  model.xRows.insert(row, insertIndex)
  true

proc valueForRow*(
    model: TableModel, identifier, columnIdentifier: string
): ObjectValue {.raises: [TableModelError].} =
  model.rowWithIdentifier(identifier).value(columnIdentifier)

proc setValue*(
    model: TableModel, identifier, columnIdentifier: string, value: ObjectValue
) =
  let index = model.sourceIndexOfIdentifier(identifier)
  if index < 0:
    raiseTableModelError("unknown table row identifier: " & identifier)
  model.xRows[index].setValue(columnIdentifier, value)

proc objectValueForTableModelCell(
    model: TableModel, row: int, column: TableColumn
): ObjectValue =
  let rowValue = model.rowAt(row)
  rowValue.getValue(model.tableModelColumnKey(column)).get(rowValue.objectValue)

proc setObjectValueForTableModelCell(
    model: TableModel, row: int, column: TableColumn, value: ObjectValue
): bool =
  let sourceIndex = model.arrangedSourceIndex(row)
  if sourceIndex < 0:
    return false
  model.xRows[sourceIndex].setValue(model.tableModelColumnKey(column), value)
  true

proc parseTableModelCellValue(
    model: TableModel,
    tableView: TableView,
    row: int,
    column: TableColumn,
    value: string,
): ObjectParseResult =
  let current = model.objectValueForTableModelCell(row, column)
  let expectedKind = if current.kind in {ovNil, ovEmpty}: ovString else: current.kind
  let context =
    Control(tableView).objectParseContext.expecting(expectedKind).withRole(ovrTableCell)
  Control(tableView).objectValueFormatter.parseObjectValue(value, context)

protocol TableModelTableDataSource of TableViewDataSource:
  method numberOfRows(model: TableModel, tableView: TableView): int =
    discard tableView
    model.len()

  method objectValueForCell(
      model: TableModel, tableView: TableView, row: int, column: TableColumn
  ): ObjectValue =
    discard tableView
    model.objectValueForTableModelCell(row, column)

  method textForCell(
      model: TableModel, tableView: TableView, row: int, column: TableColumn
  ): string =
    let value = model.objectValueForTableModelCell(row, column)
    Control(tableView).formatObjectValue(value, ovrTableCell)

  method setObjectValueForCell(
      model: TableModel,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: ObjectValue,
  ): bool =
    discard tableView
    model.setObjectValueForTableModelCell(row, column, value)

  method identifierForRow(model: TableModel, tableView: TableView, row: int): string =
    discard tableView
    model.rowAt(row).identifier

  method rowForIdentifier(
      model: TableModel, tableView: TableView, identifier: string
  ): int =
    discard tableView
    model.indexOfIdentifier(identifier)

protocol TableModelTableDelegate of TableViewDelegate:
  method isRowEnabled(model: TableModel, tableView: TableView, row: int): bool =
    discard tableView
    model.rowAt(row).enabled

  method parseObjectValueForCell(
      model: TableModel,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ): ObjectParseResult =
    model.parseTableModelCellValue(tableView, row, column, value)

  method sortDescriptorsDidChange(
      model: TableModel,
      tableView: TableView,
      column: TableColumn,
      direction: TableSortDirection,
  ) =
    if direction == tsdNone:
      model.sortDescriptors = []
    else:
      model.sortDescriptors =
        [initTableModelSortDescriptor(model.tableModelColumnKey(column), direction)]
    tableView.reloadData()

proc installTableModelProtocols(model: TableModel) =
  if model.isNil:
    return
  discard model.withProtocol(TableModelTableDataSource)
  discard model.withProtocol(TableModelTableDelegate)

proc tableStyleContext(tableView: TableView): StyleContext =
  if tableView.isNil:
    return controlStyle(srTableView)
  controlStyle(
    tableView.xTableRole,
    tableView.widgetStateSet(),
    id = tableView.styleId,
    classes = tableView.styleClasses,
  )

proc tableStyle(tableView: TableView): TableViewStyle =
  if tableView.isNil:
    return initAppearance().resolveTableViewStyle(controlStyle(srTableView))
  tableView.effectiveAppearance().resolveTableViewStyle(tableView.tableStyleContext())

proc defaultTableStyle(): TableViewStyle =
  initAppearance().resolveTableViewStyle(controlStyle(srTableView))

proc tableRole*(tableView: TableView): StyleRole =
  if tableView.isNil: srTableView else: tableView.xTableRole

proc `tableRole=`*(tableView: TableView, role: StyleRole) =
  if tableView.isNil or tableView.xTableRole == role:
    return
  tableView.xTableRole = role
  tableView.invalidateIntrinsicContentSize()
  tableView.setNeedsDisplay(true)

proc rowItemRole*(tableView: TableView): StyleRole =
  if tableView.isNil: srRowItem else: tableView.xItemRole

proc `rowItemRole=`*(tableView: TableView, role: StyleRole) =
  if tableView.isNil or tableView.xItemRole == role:
    return
  tableView.xItemRole = role
  tableView.invalidateIntrinsicContentSize()
  tableView.invalidateTableRows()

func normalizedColumnMetric(value, fallback: float32): float32 =
  if value.isNaN:
    fallback
  else:
    max(value, 0.0'f32)

proc normalizedMaxWidth(value, minWidth: float32): float32 =
  max(value.normalizedColumnMetric(defaultTableStyle().columnMaxWidth), minWidth)

proc normalizedWidth(value, minWidth, maxWidth: float32): float32 =
  min(
    max(value.normalizedColumnMetric(defaultTableStyle().columnWidth), minWidth),
    maxWidth,
  )

proc tableView*(contentView: TableContentView): TableView =
  if contentView.isNil: nil else: contentView.xTableView

proc tableView*(column: TableColumn): TableView =
  column.xTableView

proc scrollView*(tableView: TableView): ScrollView =
  if tableView.isNil: nil else: tableView.xScrollView

proc contentView*(tableView: TableView): TableContentView =
  if tableView.isNil: nil else: tableView.xContentView

proc initTableBaseChild(view: View, clipsToBounds: bool) =
  initViewFields(view, rect(0.0, 0.0, 0.0, 0.0))
  view.background = color(0.0, 0.0, 0.0, 0.0)
  view.autoresizingMaskConstraints = false
  view.clipsToBounds = clipsToBounds
  view.setAcceptsFirstResponder(false)

proc rowTextForSummary(tableView: TableView, row: int): string =
  let column = tableView.columnAt(0)
  tableView.tableCellText(row, column)

proc identifier*(column: TableColumn): string =
  column.xIdentifier

proc title*(column: TableColumn): string =
  column.xTitle

proc `title=`*(column: TableColumn, title: string) =
  if column.xTitle == title:
    return
  column.xTitle = title
  column.tableView().noteColumnsChanged()

proc width*(column: TableColumn): float32 =
  column.xWidth

proc `width=`*(column: TableColumn, width: float32) =
  let nextWidth = width.normalizedWidth(column.xMinWidth, column.xMaxWidth)
  if column.xWidth == nextWidth:
    return
  column.xWidth = nextWidth
  column.tableView().noteColumnsChanged()

proc minWidth*(column: TableColumn): float32 =
  column.xMinWidth

proc `minWidth=`*(column: TableColumn, width: float32) =
  let nextMin = width.normalizedColumnMetric(defaultTableStyle().columnMinWidth)
  if column.xMinWidth == nextMin:
    return
  column.xMinWidth = nextMin
  column.xMaxWidth = max(column.xMaxWidth, nextMin)
  column.xWidth = column.xWidth.normalizedWidth(column.xMinWidth, column.xMaxWidth)
  column.tableView().noteColumnsChanged()

proc maxWidth*(column: TableColumn): float32 =
  column.xMaxWidth

proc `maxWidth=`*(column: TableColumn, width: float32) =
  let nextMax = width.normalizedMaxWidth(column.xMinWidth)
  if column.xMaxWidth == nextMax:
    return
  column.xMaxWidth = nextMax
  column.xWidth = column.xWidth.normalizedWidth(column.xMinWidth, column.xMaxWidth)
  column.tableView().noteColumnsChanged()

proc alignment*(column: TableColumn): TextAlignment =
  column.xAlignment

proc `alignment=`*(column: TableColumn, alignment: TextAlignment) =
  if column.xAlignment == alignment:
    return
  column.xAlignment = alignment
  column.tableView().noteColumnsChanged()

proc resizePolicy*(column: TableColumn): TableColumnResizePolicy =
  column.xResizePolicy

proc `resizePolicy=`*(column: TableColumn, policy: TableColumnResizePolicy) =
  if column.xResizePolicy == policy:
    return
  column.xResizePolicy = policy
  column.tableView().noteColumnsChanged()

proc hidden*(column: TableColumn): bool =
  column.xHidden

proc `hidden=`*(column: TableColumn, hidden: bool) =
  if column.xHidden == hidden:
    return
  column.xHidden = hidden
  column.tableView().noteColumnsChanged()

proc sortDirection*(column: TableColumn): TableSortDirection =
  column.xSortDirection

proc `sortDirection=`*(column: TableColumn, direction: TableSortDirection) =
  if column.xSortDirection == direction:
    return
  column.xSortDirection = direction
  column.tableView().noteColumnsChanged()

proc reuseIdentifier*(column: TableColumn): string =
  if column.isNil:
    ""
  elif column.xReuseIdentifier.len > 0:
    column.xReuseIdentifier
  else:
    column.identifier()

proc `reuseIdentifier=`*(column: TableColumn, identifier: string) =
  if column.xReuseIdentifier == identifier:
    return
  column.xReuseIdentifier = identifier
  let tableView = column.tableView()
  if not tableView.isNil:
    tableView.clearTableCellSlots()
    tableView.noteColumnsChanged()

proc styleId*(column: TableColumn): string =
  column.xStyleId

proc `styleId=`*(column: TableColumn, id: string) =
  if column.xStyleId == id:
    return
  column.xStyleId = id
  column.tableView().noteColumnsChanged()

proc styleClasses*(column: TableColumn): seq[string] =
  column.xStyleClasses

proc `styleClasses=`*(column: TableColumn, classes: openArray[string]) =
  let nextClasses = @classes
  if column.xStyleClasses == nextClasses:
    return
  column.xStyleClasses = nextClasses
  column.tableView().noteColumnsChanged()

proc userInfo*(column: TableColumn): DynamicAgent =
  column.xUserInfo

proc `userInfo=`*(column: TableColumn, userInfo: DynamicAgent) =
  if column.xUserInfo == userInfo:
    return
  column.xUserInfo = userInfo
  column.tableView().noteColumnsChanged()

proc initTableColumnFields*(
    column: TableColumn,
    identifier: string,
    title = "",
    width = NaN,
    minWidth = NaN,
    maxWidth = NaN,
    alignment = taLeft,
    resizePolicy = tcrResizable,
) =
  let style = defaultTableStyle()
  column.xIdentifier = identifier
  column.xTitle = if title.len == 0: identifier else: title
  column.xMinWidth = minWidth.normalizedColumnMetric(style.columnMinWidth)
  column.xMaxWidth = maxWidth.normalizedMaxWidth(column.xMinWidth)
  column.xWidth = width.normalizedWidth(column.xMinWidth, column.xMaxWidth)
  column.xAlignment = alignment
  column.xResizePolicy = resizePolicy
  column.xSortDirection = tsdNone
  column.xReuseIdentifier = identifier

proc newTableColumn*(
    identifier: string,
    title = "",
    width = NaN,
    minWidth = NaN,
    maxWidth = NaN,
    alignment = taLeft,
    resizePolicy = tcrResizable,
): TableColumn =
  result = TableColumn()
  initTableColumnFields(
    result, identifier, title, width, minWidth, maxWidth, alignment, resizePolicy
  )

proc dataSource*(tableView: TableView): DynamicAgent =
  tableView.xTableDataSource

proc delegate*(tableView: TableView): DynamicAgent =
  tableView.xTableDelegate

proc resolvedRowCount(tableView: TableView): int =
  if tableView.isNil:
    return 0
  let source = tableView.dataSource()
  if not source.isNil:
    let count = source.trySendLocal(numberOfRows(), tableView)
    if count.isSome:
      return max(count.get(), 0)
  max(tableView.xRowCount, 0)

proc rowCount*(tableView: TableView): int =
  tableView.resolvedRowCount()

proc `rowCount=`*(tableView: TableView, count: int) =
  let nextCount = max(count, 0)
  if tableView.xRowCount == nextCount:
    return
  tableView.xRowCount = nextCount
  tableView.reloadData()

proc `dataSource=`*(tableView: TableView, dataSource: DynamicAgent) =
  if tableView.xTableDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(TableViewDataSource)
  tableView.clearTableCellSlots()
  tableView.xTableDataSource = dataSource
  tableView.reloadData()

proc `dataSource=`*(tableView: TableView, dataSource: Responder) =
  tableView.dataSource = DynamicAgent(dataSource)

proc `delegate=`*(tableView: TableView, delegate: DynamicAgent) =
  if tableView.xTableDelegate == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(TableViewDelegate)
  tableView.clearTableCellSlots()
  tableView.xTableDelegate = delegate
  tableView.reloadData()

proc `delegate=`*(tableView: TableView, delegate: Responder) =
  tableView.delegate = DynamicAgent(delegate)

proc columnCount*(tableView: TableView): int =
  tableView.xColumns.len

proc columnAt*(tableView: TableView, index: int): TableColumn =
  if index notin 0 ..< tableView.xColumns.len:
    nil
  else:
    tableView.xColumns[index]

proc columnIndex*(tableView: TableView, identifier: string): int =
  if tableView.isNil:
    return -1
  for index, column in tableView.xColumns:
    if column.identifier == identifier:
      return index
  -1

proc columnWithIdentifier*(tableView: TableView, identifier: string): TableColumn =
  let index = tableView.columnIndex(identifier)
  if index < 0:
    nil
  else:
    tableView.xColumns[index]

proc containsColumn*(tableView: TableView, identifier: string): bool =
  tableView.columnIndex(identifier) >= 0

iterator columns*(tableView: TableView): TableColumn =
  if not tableView.isNil:
    for column in tableView.xColumns:
      yield column

iterator visibleColumns*(tableView: TableView): TableColumn =
  if not tableView.isNil:
    for column in tableView.xColumns:
      if not column.hidden():
        yield column

proc columnRect(tableView: TableView, bounds: Rect, column: TableColumn): Rect =
  if tableView.isNil or column.isNil:
    return rect(0.0, 0.0, 0.0, 0.0)
  var x = bounds.origin.x
  for current in tableView.xColumns:
    if current.hidden():
      continue
    if current == column:
      let width = min(current.width(), max(bounds.maxX - x, 0.0'f32))
      return rect(x, bounds.origin.y, width, bounds.size.height)
    x += current.width()
  rect(bounds.origin.x, bounds.origin.y, 0.0, 0.0)

proc visibleColumnWidth(tableView: TableView): float32 =
  if tableView.isNil:
    return 0.0'f32
  for column in tableView.visibleColumns():
    result += column.width()

proc visibleTableColumns(tableView: TableView): seq[TableColumn] =
  if not tableView.isNil:
    for column in tableView.visibleColumns():
      result.add column

func tableHeaderCornerRadii(chrome: TableHeaderChrome): CornerRadii =
  initCornerRadii(chrome.cornerRadius, chrome.cornerRadius, 0.0'f32, 0.0'f32)

func tableHeaderCellCornerRadii(
    chrome: TableHeaderChrome, firstVisible, lastVisible: bool
): CornerRadii =
  initCornerRadii(
    if firstVisible: chrome.cornerRadius else: 0.0'f32,
    if lastVisible: chrome.cornerRadius else: 0.0'f32,
    0.0'f32,
    0.0'f32,
  )

proc tableHeaderHeight*(tableView: TableView): float32 =
  if not tableView.xShowsHeader: 0.0'f32 else: tableView.xHeaderHeight

proc defaultTableHeaderChrome*(): TableHeaderChrome =
  TableHeaderChrome(
    headerFill:
      linear(color(0.97, 0.98, 0.99, 0.78), color(0.78, 0.81, 0.86, 0.78), fgaY),
    headerBorderColor: color(0.52, 0.56, 0.62, 0.92),
    cellFill: linear(color(1.0, 1.0, 1.0, 0.64), color(0.82, 0.84, 0.88, 0.64), fgaY),
    hoveredCellFill:
      linear(color(1.0, 1.0, 1.0, 0.72), color(0.74, 0.78, 0.84, 0.72), fgaY),
    pressedCellFill:
      linear(color(0.72, 0.75, 0.80, 0.78), color(0.58, 0.62, 0.68, 0.78), fgaY),
    cellBorderColor: color(0.54, 0.58, 0.64, 0.76),
    textColor: color(0.12, 0.14, 0.18, 1.0),
    sortIndicatorColor: color(0.10, 0.13, 0.18, 0.95),
    insertionIndicatorFill: fill(color(0.16, 0.36, 0.84, 0.95)),
    borderWidth: 1.0'f32,
    sortIndicatorWidth: 24.0'f32,
    insertionWidth: 3.0'f32,
    insertionCapWidth: 9.0'f32,
    insertionCapHeight: 3.0'f32,
    cornerRadius: 5.0'f32,
  )

proc tableHeaderChrome(tableView: TableView, context: DrawContext): TableHeaderChrome =
  result = defaultTableHeaderChrome()
  if tableView.isNil or context.isNil:
    return
  let
    tableStates = tableView.widgetStateSet()
    tableId = tableView.styleId()
    tableClasses = tableView.styleClasses()
    tableContext = controlStyle(
      tableView.xTableRole, tableStates, id = tableId, classes = tableClasses
    )
    headerContext =
      controlStyle(srTableHeader, tableStates, id = tableId, classes = tableClasses)
    cellContext =
      controlStyle(srTableHeaderCell, tableStates, id = tableId, classes = tableClasses)
    hoveredCellContext = controlStyle(
      srTableHeaderCell, tableStates + {ssHovered}, id = tableId, classes = tableClasses
    )
    pressedCellContext = controlStyle(
      srTableHeaderCell, tableStates + {ssPressed}, id = tableId, classes = tableClasses
    )

  result.headerFill = context.appearance.resolveFill(headerContext, result.headerFill)
  result.headerBorderColor = context.appearance.resolveColor(
    headerContext, StyleBorderColor, result.headerBorderColor
  )
  result.insertionIndicatorFill = context.appearance.resolveFill(
    headerContext, result.insertionIndicatorFill, StyleInsertionIndicatorFill
  )
  result.cellFill = context.appearance.resolveFill(cellContext, result.cellFill)
  result.hoveredCellFill =
    context.appearance.resolveFill(hoveredCellContext, result.hoveredCellFill)
  result.pressedCellFill =
    context.appearance.resolveFill(pressedCellContext, result.pressedCellFill)
  result.cellBorderColor = context.appearance.resolveColor(
    cellContext, StyleBorderColor, result.cellBorderColor
  )
  result.textColor =
    context.appearance.resolveColor(cellContext, StyleTextColor, result.textColor)
  result.sortIndicatorColor = context.appearance.resolveColor(
    cellContext, StyleMarkColor, result.sortIndicatorColor
  )
  let tableCornerRadius = context.appearance.resolveLength(
    tableContext, StyleCornerRadius, result.cornerRadius
  )
  result.cornerRadius = context.appearance.resolveLength(
    headerContext, StyleCornerRadius, max(tableCornerRadius - 1.0'f32, 0.0'f32)
  )

proc tableDropIndicatorFill(tableView: TableView, context: DrawContext): Fill =
  if tableView.isNil or context.isNil:
    return fill(color(0.18, 0.42, 0.88, 0.95))
  context.appearance.resolveFill(
    controlStyle(
      tableView.xTableRole,
      tableView.widgetStateSet(),
      id = tableView.styleId(),
      classes = tableView.styleClasses(),
    ),
    fill(color(0.18, 0.42, 0.88, 0.95)),
    StyleDropIndicatorFill,
  )

proc `tableHeaderHeight=`*(tableView: TableView, height: float32) =
  let nextHeight = max(height, 0.0'f32)
  if tableView.xHeaderHeight == nextHeight:
    return
  tableView.xHeaderHeight = nextHeight
  tableView.noteColumnsChanged()

proc showsHeader*(tableView: TableView): bool =
  tableView.xShowsHeader

proc `showsHeader=`*(tableView: TableView, value: bool) =
  if tableView.xShowsHeader == value:
    return
  tableView.xShowsHeader = value
  tableView.noteColumnsChanged()

proc tableHeaderRect*(tableView: TableView): Rect =
  if not tableView.showsHeader():
    return rect(0.0, 0.0, 0.0, 0.0)
  rect(
    1.0'f32,
    1.0'f32,
    max(tableView.bounds().size.width - 2.0'f32, 0.0'f32),
    tableView.tableHeaderHeight(),
  )

proc tableColumnRect*(tableView: TableView, column: TableColumn): Rect =
  tableView.columnRect(tableView.bounds(), column)

proc tableHeaderColumnRect*(tableView: TableView, column: TableColumn): Rect =
  let
    headerRect = tableView.tableHeaderRect()
    contentOffset = tableView.listContentOffset()
    documentWidth = max(tableView.visibleColumnWidth(), headerRect.size.width)
    documentHeaderRect = rect(
      headerRect.origin.x - contentOffset.x,
      headerRect.origin.y,
      documentWidth,
      headerRect.size.height,
    )
  tableView.columnRect(documentHeaderRect, column)

proc tableHeaderHitTest*(tableView: TableView, point: Point): TableHeaderHit =
  tableView.headerHitTest(point)

proc headerDragIndicator*(tableView: TableView): TableHeaderDragIndicator =
  if tableView.isNil or tableView.xHeaderDragInsertionIndex < 0:
    return TableHeaderDragIndicator(index: -1)
  TableHeaderDragIndicator(
    index: tableView.xHeaderDragInsertionIndex,
    rect: tableView.xHeaderDragInsertionRect,
    visible: not tableView.xHeaderDragInsertionRect.isEmpty,
  )

proc headerInsertionIndexAtPoint(tableView: TableView, point: Point): int =
  if tableView.isNil or tableView.xColumns.len == 0:
    return -1
  var lastVisible = -1
  for index, column in tableView.xColumns:
    if column.hidden():
      continue
    lastVisible = index
    let rect = tableView.tableHeaderColumnRect(column)
    if rect.isEmpty:
      continue
    if point.x < rect.origin.x + rect.size.width * 0.5'f32:
      return index
  if lastVisible >= 0:
    min(lastVisible + 1, tableView.xColumns.len)
  else:
    -1

proc headerInsertionRectForIndex(tableView: TableView, index: int): Rect =
  if tableView.isNil or index < 0 or tableView.xColumns.len == 0:
    return rect(0.0, 0.0, 0.0, 0.0)
  let headerRect = tableView.tableHeaderRect()
  if headerRect.isEmpty:
    return rect(0.0, 0.0, 0.0, 0.0)
  var x = headerRect.origin.x
  if index >= tableView.xColumns.len:
    for column in tableView.xColumns:
      if not column.hidden():
        x = tableView.tableHeaderColumnRect(column).maxX
  else:
    var found = false
    for current in 0 ..< tableView.xColumns.len:
      let column = tableView.xColumns[current]
      if column.hidden():
        continue
      let rect = tableView.tableHeaderColumnRect(column)
      if current >= index:
        x = rect.origin.x
        found = true
        break
      x = rect.maxX
    if not found:
      x = min(x, headerRect.maxX)
  rect(x - 1.0'f32, headerRect.origin.y, 3.0'f32, headerRect.size.height)

proc clearHeaderDragInsertion(tableView: TableView) =
  if tableView.isNil:
    return
  tableView.xHeaderDragInsertionIndex = -1
  tableView.xHeaderDragInsertionRect = rect(0.0, 0.0, 0.0, 0.0)

proc setHeaderDragInsertion(tableView: TableView, index: int) =
  if tableView.isNil:
    return
  let bounded = max(0, min(index, tableView.xColumns.len))
  tableView.xHeaderDragInsertionIndex = bounded
  tableView.xHeaderDragInsertionRect = tableView.headerInsertionRectForIndex(bounded)

proc autoscrollHeaderColumnDrag(tableView: TableView, point: Point): bool =
  if tableView.isNil:
    return false
  let headerRect = tableView.tableHeaderRect()
  if headerRect.isEmpty:
    return false
  let autoscrollEdge = tableView.tableStyle().headerAutoscrollEdge
  if point.x <= headerRect.minX + autoscrollEdge:
    tableView.setHeaderDragInsertion(0)
    return true
  if point.x >= headerRect.maxX - autoscrollEdge:
    tableView.setHeaderDragInsertion(tableView.xColumns.len)
    return true
  false

proc resetHeaderCursorRects(tableView: TableView) =
  if tableView.isNil:
    return
  tableView.discardCursorRects()
  if not tableView.showsHeader():
    return
  let resizeHandleWidth = tableView.tableStyle().headerResizeHandleWidth
  for column in tableView.visibleColumns():
    if column.resizePolicy() != tcrResizable:
      continue
    let rect = tableView.tableHeaderColumnRect(column)
    if rect.isEmpty:
      continue
    tableView.addCursorRect(
      rect(
        rect.maxX - resizeHandleWidth,
        rect.origin.y,
        resizeHandleWidth * 2.0'f32,
        rect.size.height,
      ),
      TableHeaderResizeCursorName,
    )

proc syncHeaderTrackingAreas(tableView: TableView) =
  if tableView.isNil:
    return
  discard tableView.removeTrackingArea(TableHeaderTrackingTag)
  if tableView.showsHeader():
    tableView.addTrackingArea(
      ViewTrackingArea(
        rect: tableView.tableHeaderRect(),
        options: {vtoMouseEnteredAndExited, vtoMouseMoved, vtoCursorUpdate},
        tag: TableHeaderTrackingTag,
        owner: Responder(tableView),
      )
    )
  tableView.resetHeaderCursorRects()

proc validCell(tableView: TableView, row: int, column: TableColumn): bool =
  not tableView.isNil and row in 0 ..< tableView.rowCount() and not column.isNil and
    column.tableView() == tableView

proc tableCellText*(tableView: TableView, row: int, column: TableColumn): string =
  if not tableView.validCell(row, column):
    return ""
  let source = tableView.dataSource()
  if source.isNil:
    return ""
  let value = source.trySendLocal(
    objectValueForCell(), (tableView: tableView, row: row, column: column)
  )
  if value.isSome:
    return Control(tableView).formatObjectValue(value.get(), ovrTableCell)
  let text =
    source.trySendLocal(textForCell(), (tableView: tableView, row: row, column: column))
  if text.isSome:
    text.get()
  else:
    ""

proc tableCellObjectValue*(
    tableView: TableView, row: int, column: TableColumn
): ObjectValue =
  if not tableView.validCell(row, column):
    return nilObjectValue()
  let source = tableView.dataSource()
  if source.isNil:
    return emptyObjectValue()
  let value = source.trySendLocal(
    objectValueForCell(), (tableView: tableView, row: row, column: column)
  )
  if value.isSome:
    return value.get()
  let text =
    source.trySendLocal(textForCell(), (tableView: tableView, row: row, column: column))
  if text.isSome:
    toObj(text.get())
  else:
    emptyObjectValue()

proc writeTableCellObjectValue*(
    tableView: TableView, row: int, column: TableColumn, value: ObjectValue
): bool =
  if not tableView.validCell(row, column):
    return false
  let source = tableView.dataSource()
  if source.isNil:
    return true
  let written = source.trySendLocal(
    setObjectValueForCell(),
    (tableView: tableView, row: row, column: column, value: value),
  )
  if written.isSome:
    written.get()
  else:
    true

proc tableRowIdentifier*(tableView: TableView, row: int): string =
  if tableView.isNil or row notin 0 ..< tableView.len():
    return ""
  let source = tableView.dataSource()
  if source.isNil:
    return ""
  let identifier =
    source.trySendLocal(identifierForRow(), (tableView: tableView, row: row))
  if identifier.isSome:
    identifier.get()
  else:
    ""

proc directTableRowIndexForIdentifier(tableView: TableView, identifier: string): int =
  if tableView.isNil or identifier.len == 0:
    return -1
  let source = tableView.dataSource()
  if source.isNil:
    return -1
  let direct = source.trySendLocal(
    rowForIdentifier(), (tableView: tableView, identifier: identifier)
  )
  if direct.isSome and direct.get() in 0 ..< tableView.len():
    return direct.get()
  for row in 0 ..< tableView.len():
    if tableView.tableRowIdentifier(row) == identifier:
      return row
  -1

proc resolveTableRowIdentifier(tableView: TableView, identifier: string): string =
  if tableView.isNil or identifier.len == 0:
    return ""
  if tableView.directTableRowIndexForIdentifier(identifier) >= 0:
    return identifier
  if identifier in tableView.xRowIdentifierAliases:
    let aliased = tableView.xRowIdentifierAliases[identifier]
    if tableView.directTableRowIndexForIdentifier(aliased) >= 0:
      return aliased
  if not tableView.xRowIdentifierResolver.isNil:
    let resolved = tableView.xRowIdentifierResolver(identifier)
    if tableView.directTableRowIndexForIdentifier(resolved) >= 0:
      return resolved
  ""

proc tableRowIndexForIdentifier*(tableView: TableView, identifier: string): int =
  let resolved = tableView.resolveTableRowIdentifier(identifier)
  if resolved.len == 0:
    -1
  else:
    tableView.directTableRowIndexForIdentifier(resolved)

proc getTableRowIdentifier*(tableView: TableView, row: int): Option[string] =
  let identifier = tableView.tableRowIdentifier(row)
  if identifier.len > 0:
    some(identifier)
  else:
    none(string)

proc requireTableRowIdentifier*(tableView: TableView, row: int): string =
  let identifier = tableView.tableRowIdentifier(row)
  if identifier.len > 0:
    return identifier
  raiseTableModelError("missing table row identifier at row: " & $row)

proc getTableRowIndexForIdentifier*(
    tableView: TableView, identifier: string
): Option[int] =
  let row = tableView.tableRowIndexForIdentifier(identifier)
  if row >= 0:
    some(row)
  else:
    none(int)

proc requireTableRowIndexForIdentifier*(tableView: TableView, identifier: string): int =
  let row = tableView.tableRowIndexForIdentifier(identifier)
  if row >= 0:
    return row
  raiseTableModelError("unknown table row identifier: " & identifier)

proc setRowIdentifierAlias*(
    tableView: TableView, oldIdentifier, newIdentifier: string
) =
  if tableView.isNil or oldIdentifier.len == 0:
    return
  if newIdentifier.len == 0:
    tableView.xRowIdentifierAliases.del(oldIdentifier)
  else:
    tableView.xRowIdentifierAliases[oldIdentifier] = newIdentifier

proc clearRowIdentifierAliases*(tableView: TableView) =
  if not tableView.isNil:
    tableView.xRowIdentifierAliases.clear()

proc rowIdentifierResolver*(tableView: TableView): TableRowIdentifierResolver =
  if tableView.isNil: nil else: tableView.xRowIdentifierResolver

proc `rowIdentifierResolver=`*(
    tableView: TableView, resolver: TableRowIdentifierResolver
) =
  if not tableView.isNil:
    tableView.xRowIdentifierResolver = resolver

proc rowIdentifiersForRows(tableView: TableView, rows: openArray[int]): seq[string] =
  for row in rows:
    let identifier = tableView.tableRowIdentifier(row)
    if identifier.len == 0:
      return @[]
    result.add identifier

proc applySelectionForRowIdentifiers(
    tableView: TableView,
    identifiers: openArray[string],
    anchorIdentifier, leadIdentifier: string,
) =
  if tableView.isNil or identifiers.len == 0:
    return
  var rows: seq[int]
  for identifier in identifiers:
    let row = tableView.tableRowIndexForIdentifier(identifier)
    if row >= 0:
      rows.add row
  tableView.applySelectedIndexes(
    rows,
    tableView.tableRowIndexForIdentifier(anchorIdentifier),
    tableView.tableRowIndexForIdentifier(leadIdentifier),
  )

proc tableCellView*(tableView: TableView, row: int, column: TableColumn): View =
  if not tableView.validCell(row, column):
    return nil
  let delegate = tableView.delegate()
  if delegate.isNil:
    return nil
  var cellView: View
  discard delegate.performLocal(
    viewForCell(), (tableView: tableView, row: row, column: column), cellView
  )
  cellView

proc applyCellAccessibility(
    tableView: TableView, row: int, column: TableColumn, cell: View
) =
  if cell.isNil:
    return
  if not cell.xHasAccessibilityRole:
    cell.accessibilityRole = arCell
  if cell.xAccessibilityLabel.len == 0:
    cell.accessibilityLabel = tableView.tableCellText(row, column)
  cell.xAccessibilityTraits.incl atSelectable

proc dequeueReusableCellView*(tableView: TableView, identifier: string): View =
  if tableView.isNil or identifier.len == 0:
    return nil
  if identifier notin tableView.xReusableCellViews:
    return nil
  var views = tableView.xReusableCellViews[identifier]
  if views.len == 0:
    return nil
  result = views[^1]
  views.setLen(views.len - 1)
  tableView.xReusableCellViews[identifier] = views
  if not result.isNil:
    result.hidden = false

proc enqueueReusableCellView(tableView: TableView, identifier: string, view: View) =
  if tableView.isNil or view.isNil or identifier.len == 0:
    return
  view.hidden = true
  if view.superview() != nil:
    view.removeFromSuperview()
  tableView.xReusableCellViews.mgetOrPut(identifier, @[]).add view

proc recycleCellSlot(tableView: TableView, slot: TableCellSlot) =
  if tableView.isNil or slot.view.isNil:
    return
  let identifier =
    if slot.column.isNil:
      ""
    else:
      slot.column.reuseIdentifier()
  if identifier.len > 0:
    tableView.enqueueReusableCellView(identifier, slot.view)
  else:
    slot.view.hidden = true
    if slot.view.superview() != nil:
      slot.view.removeFromSuperview()

proc tableRowEnabled(tableView: TableView, row: int): bool =
  if tableView.isNil or row notin 0 ..< tableView.rowCount():
    return false
  let delegate = tableView.delegate()
  if delegate.isNil:
    return true
  let enabled = delegate.trySendLocal(isRowEnabled(), (tableView: tableView, row: row))
  if enabled.isSome:
    enabled.get()
  else:
    true

proc tableRowSelectable(tableView: TableView, row: int): bool =
  if not tableView.tableRowEnabled(row):
    return false
  let delegate = tableView.delegate()
  if delegate.isNil:
    return true
  let selectable =
    delegate.trySendLocal(shouldSelectTableRow(), (tableView: tableView, row: row))
  if selectable.isSome:
    selectable.get()
  else:
    true

proc tableColumnAtPoint(tableView: TableView, point: Point): TableColumn =
  tableView.columnAtPoint(point)

proc tableCellHitPolicy(
    tableView: TableView, row: int, column: TableColumn, target: View, event: MouseEvent
): CellHitPolicy =
  if tableView.isNil or column.isNil or row notin 0 ..< tableView.rowCount():
    return chpDefault
  let delegate = tableView.delegate()
  if delegate.isNil:
    return chpDefault
  let explicitPolicy = delegate.trySendLocal(
    hitPolicyForCell(),
    (tableView: tableView, row: row, column: column, target: target, event: event),
  )
  if explicitPolicy.isSome and explicitPolicy.get() != chpDefault:
    return explicitPolicy.get()
  let shouldTrack = delegate.trySendLocal(
    shouldTrackCell(), (tableView: tableView, row: row, column: column, target: target)
  )
  if shouldTrack.isSome:
    if shouldTrack.get(): chpTrackCell else: chpSelectRow
  else:
    chpDefault

proc viewportSize(tableView: TableView): Size =
  let scrollView = tableView.scrollView()
  if scrollView.isNil:
    initSize(0.0, 0.0)
  else:
    scrollView.viewportSize()

proc invalidateTableRows(tableView: TableView) =
  if tableView.isNil:
    return
  if not tableView.xContentView.isNil:
    tableView.xContentView.syncVisibleRowViews()
  if not tableView.xScrollView.isNil:
    tableView.xScrollView.setNeedsDisplay(true)
    let scroller = tableView.xScrollView.verticalScroller()
    if not scroller.isNil:
      scroller.setNeedsDisplay(true)
  if not tableView.xContentView.isNil:
    tableView.xContentView.setNeedsDisplay(true)
  tableView.setNeedsDisplay(true)

proc uncachedRowHeightForRow(tableView: TableView, index: int): float32 =
  if tableView.isNil or index notin 0 ..< tableView.len():
    return 0.0'f32
  tableView.resolvedRowHeight(index).normalizedRowHeight()

proc ensureRowHeightCache(tableView: TableView) =
  if tableView.isNil or tableView.xRowHeightCacheValid or tableView.xComputingRowHeights:
    return
  tableView.xComputingRowHeights = true
  try:
    var
      heights: seq[float32]
      offsets: seq[float32]
      offset = 0.0'f32
    for index in 0 ..< tableView.len():
      offsets.add offset
      let height = tableView.uncachedRowHeightForRow(index)
      heights.add height
      offset += height
    tableView.xRowHeights = heights
    tableView.xRowOffsets = offsets
    tableView.xRowHeightCacheValid = true
  finally:
    tableView.xComputingRowHeights = false

proc invalidateRowHeightCache(tableView: TableView) =
  if not tableView.isNil:
    tableView.xRowHeightCacheValid = false

proc rowOffset(tableView: TableView, index: int): float32 =
  if tableView.isNil or index <= 0:
    return 0.0'f32
  tableView.ensureRowHeightCache()
  if index >= tableView.xRowHeights.len:
    for height in tableView.xRowHeights:
      result += height
  elif index < tableView.xRowOffsets.len:
    result = tableView.xRowOffsets[index]

proc rowIndexAtContentY(tableView: TableView, y: float32): int =
  if tableView.isNil or tableView.len() <= 0:
    return -1
  tableView.ensureRowHeightCache()
  let targetY = max(y, 0.0'f32)
  for index, offset in tableView.xRowOffsets:
    if targetY < offset + tableView.xRowHeights[index]:
      return index
  tableView.len() - 1

proc contentHeight(tableView: TableView): float32 =
  tableView.rowOffset(tableView.len())

proc visibleRowsFrom(tableView: TableView, firstIndex: int, height: float32): int =
  if tableView.isNil or tableView.len() <= 0 or firstIndex < 0 or height <= 0.0'f32:
    return 0
  var
    count = 0
    consumed = 0.0'f32
    index = firstIndex
  while index < tableView.len():
    let next = consumed + tableView.rowHeightForRow(index)
    if count > 0 and next > height:
      break
    consumed = next
    inc count
    inc index
  max(count, 1)

proc maxFirstVisibleIndex(tableView: TableView): int =
  if tableView.isNil or tableView.len() <= 0:
    return 0
  tableView.rowIndexAtContentY(
    max(tableView.contentHeight() - tableView.viewportSize().height, 0.0'f32)
  )

proc listContentOffset(tableView: TableView): Point =
  let scrollView = tableView.scrollView()
  if scrollView.isNil:
    initPoint(0.0, 0.0)
  else:
    scrollView.contentOffset()

proc setTableContentOffset(tableView: TableView, offset: Point, invalidate: bool) =
  let scrollView = tableView.scrollView()
  if scrollView.isNil:
    return
  let oldOffset = scrollView.contentOffset()
  scrollView.contentOffset = offset
  let nextOffset = scrollView.contentOffset()
  if oldOffset != nextOffset and invalidate:
    tableView.invalidateTableRows()
  if not tableView.xContentView.isNil:
    tableView.xContentView.syncVisibleRowViews()

proc tileTableContent(tableView: TableView) =
  if tableView.isNil or tableView.xScrollView.isNil or tableView.xContentView.isNil:
    return
  let
    offset = tableView.listContentOffset()
    scrollFrame = rect(
      1.0'f32,
      1.0'f32,
      max(tableView.bounds().size.width - 2.0'f32, 0.0'f32),
      max(tableView.bounds().size.height - 2.0'f32, 0.0'f32),
    )
  tableView.xScrollView.frame = scrollFrame
  let
    contentHeight = tableView.contentHeight()
    columnWidth = tableView.visibleColumnWidth()
    horizontalVisible = columnWidth > scrollFrame.size.width
    verticalHeight =
      scrollFrame.size.height -
      (if horizontalVisible: tableView.xScrollView.scrollerThickness()
      else: 0.0'f32)
    verticalVisible = contentHeight > max(verticalHeight, 0.0'f32)
    viewportWidth =
      scrollFrame.size.width -
      (if verticalVisible: tableView.xScrollView.scrollerThickness()
      else: 0.0'f32)
    documentWidth = max(columnWidth, max(viewportWidth, 0.0'f32))
    size = initSize(documentWidth, contentHeight)
  tableView.xContentView.frame = rect(0.0'f32, 0.0'f32, size.width, size.height)
  tableView.xScrollView.tile()
  tableView.setTableContentOffset(offset, false)

proc scrollContentRectToVisible(tableView: TableView, rect: Rect) =
  let oldFirst = tableView.firstVisibleIndex()
  let scrollView = tableView.scrollView()
  if rect.isEmpty or scrollView.isNil:
    return
  if scrollView.scrollRectToVisible(rect):
    tableView.xContentView.syncVisibleRowViews()
  if tableView.firstVisibleIndex() != oldFirst:
    tableView.invalidateTableRows()

proc scrollItemToVisible(tableView: TableView, itemIndex: int) =
  if tableView.isNil or itemIndex < 0 or itemIndex >= tableView.len():
    return
  var rect = tableView.xContentView.tableContentItemRect(itemIndex)
  let offset = tableView.listContentOffset()
  rect.x = offset.x
  rect.w = tableView.viewportSize().width
  tableView.scrollContentRectToVisible(rect)

proc selectionContains(tableView: TableView, index: int): bool =
  for selectedIndex in tableView.xSelectedIndexes:
    if selectedIndex == index:
      return true
  false

proc tableRowState(tableView: TableView, index: int): RowState =
  if tableView.isNil or index notin 0 ..< tableView.len():
    initRowState(-1, "", states = {})
  else:
    var rowStates: set[WidgetState] = {}
    if not tableView.rowEnabled(index):
      rowStates.incl(ssDisabled)
    if tableView.selectionContains(index):
      rowStates.incl(ssSelected)
    if index == tableView.highlightedIndex():
      rowStates.incl(ssHovered)
    if tableView.usesAlternatingRowBackgrounds() and index mod 2 == 1:
      rowStates.incl(ssAlternating)
    if index == tableView.xPressedIndex:
      rowStates.incl(ssPressed)
    if ssFocused in tableView.widgetStateSet():
      rowStates.incl(ssFocused)
    initRowState(index, tableView.rowTextForSummary(index), states = rowStates)

proc indexesInRange(selectionRange: Slice[int]): seq[int] =
  if selectionRange.b < selectionRange.a:
    return @[]
  for index in selectionRange.a .. selectionRange.b:
    result.add index

proc firstSelectedIndex(tableView: TableView, indexes: openArray[int]): int =
  if indexes.len == 0:
    -1
  else:
    indexes[0]

proc syncSelectedIndex(tableView: TableView) =
  tableView.xSelectedIndex = tableView.firstSelectedIndex(tableView.xSelectedIndexes)

proc normalizeSelection(tableView: TableView, indexes: openArray[int]): seq[int] =
  if tableView.isNil or tableView.xSelectionMode == tsmNone or tableView.len() == 0:
    return @[]
  for index in indexes:
    if tableView.rowSelectable(index):
      result.add index
  result.sort()
  var writeIndex = 0
  for index in result:
    if writeIndex == 0 or result[writeIndex - 1] != index:
      result[writeIndex] = index
      inc writeIndex
  result.setLen(writeIndex)
  if tableView.xSelectionMode == tsmSingle and result.len > 1:
    result.setLen(1)

proc normalizeSelectionAnchor(tableView: TableView, anchor: int): int =
  if tableView.rowSelectable(anchor): anchor else: tableView.xSelectedIndex

proc syncSelectionCursor(tableView: TableView) =
  if tableView.xSelectedIndexes.len == 0:
    tableView.xSelectionAnchor = -1
    tableView.xSelectionLead = -1
    return
  if tableView.xSelectionMode == tsmSingle:
    tableView.xSelectionAnchor = tableView.xSelectedIndex
    tableView.xSelectionLead = tableView.xSelectedIndex
    return
  if not tableView.rowSelectable(tableView.xSelectionAnchor):
    tableView.xSelectionAnchor = tableView.xSelectedIndex
  if not tableView.rowSelectable(tableView.xSelectionLead):
    tableView.xSelectionLead = tableView.xSelectedIndex

proc validTableIndex(tableView: TableView, index: int): bool =
  not tableView.isNil and index >= 0 and index < tableView.len()

proc firstSelectableIndex(tableView: TableView): int =
  for index in 0 ..< tableView.len():
    if tableView.rowSelectable(index):
      return index
  -1

proc lastSelectableIndex(tableView: TableView): int =
  for countdown in 0 ..< tableView.len():
    let index = tableView.len() - countdown - 1
    if tableView.rowSelectable(index):
      return index
  -1

proc nextSelectableIndex(tableView: TableView, index, delta: int): int =
  if tableView.isNil or delta == 0 or tableView.len() == 0:
    return -1
  let step = if delta < 0: -1 else: 1
  var current = index
  while current >= 0 and current < tableView.len():
    if tableView.rowSelectable(current):
      return current
    current += step
  -1

proc applySelectedIndexes(
    tableView: TableView, indexes: openArray[int], anchor: int, lead: int
) =
  let nextIndexes = tableView.normalizeSelection(indexes)
  let
    nextSelected = tableView.firstSelectedIndex(nextIndexes)
    nextAnchor =
      if nextIndexes.len == 0:
        -1
      elif tableView.rowSelectable(anchor):
        anchor
      else:
        nextSelected
    nextLead =
      if nextIndexes.len == 0:
        -1
      elif tableView.rowSelectable(lead):
        lead
      else:
        nextSelected
    selectionChanged = tableView.xSelectedIndexes != nextIndexes
  if not selectionChanged:
    tableView.xSelectionAnchor = nextAnchor
    tableView.xSelectionLead = nextLead
    if nextLead >= 0:
      tableView.scrollItemToVisible(nextLead)
    return
  let beforeIndexes = tableView.xSelectedIndexes
  tableView.findUndoManager().registerSelectionChange(
    proc(indexes: seq[int]) =
      tableView.selectedIndexes = indexes,
    beforeIndexes,
    "Change Selection",
  )
  emit tableView.selectionIsChanging(DynamicAgent(tableView))
  tableView.xSelectedIndexes = nextIndexes
  tableView.syncSelectedIndex()
  tableView.xSelectionAnchor = nextAnchor
  tableView.xSelectionLead = nextLead
  if nextLead >= 0:
    tableView.scrollItemToVisible(nextLead)
  tableView.invalidateTableRows()
  emit tableView.selectionDidChange(DynamicAgent(tableView))
  tableView.postAccessibilityNotification(anSelectionChanged)
  if nextSelected >= 0:
    let delegate = tableView.delegate()
    if not delegate.isNil:
      discard delegate.sendLocalIfHandled(
        didSelectTableRow(), (tableView: tableView, row: nextSelected)
      )

proc selectItemAtIndex(tableView: TableView, index: int) =
  if tableView.isNil or tableView.xSelectionMode == tsmNone:
    return
  let boundedIndex = if index < 0 or index >= tableView.len(): -1 else: index
  if boundedIndex >= 0 and not tableView.rowSelectable(boundedIndex):
    return
  if tableView.xSelectedIndex == boundedIndex and tableView.xSelectedIndexes.len <= 1:
    if boundedIndex >= 0:
      tableView.scrollItemToVisible(boundedIndex)
    return
  if boundedIndex < 0:
    tableView.selectedIndexes = @[]
  else:
    tableView.applySelectedIndexes([boundedIndex], boundedIndex, boundedIndex)

proc rangeSelectionIndexes(anchor, lead: int): seq[int] =
  if anchor < 0 or lead < 0:
    return @[]
  let
    firstIndex = min(anchor, lead)
    lastIndex = max(anchor, lead)
  for index in firstIndex .. lastIndex:
    result.add index

proc extendSelectionToIndex(tableView: TableView, index: int) =
  if tableView.xSelectionMode != tsmExtended:
    tableView.selectItemAtIndex(index)
    return
  let boundedIndex = if tableView.validTableIndex(index): index else: -1
  if boundedIndex < 0 or not tableView.rowSelectable(boundedIndex):
    return
  let anchor = tableView.normalizeSelectionAnchor(tableView.xSelectionAnchor)
  tableView.applySelectedIndexes(
    rangeSelectionIndexes(anchor, boundedIndex), anchor, boundedIndex
  )

proc toggleSelectionAtIndex(tableView: TableView, index: int) =
  if tableView.xSelectionMode notin {tsmMultiple, tsmExtended}:
    tableView.selectItemAtIndex(index)
    return
  if not tableView.rowSelectable(index):
    return
  var nextIndexes: seq[int]
  if tableView.selectionContains(index):
    for selectedIndex in tableView.xSelectedIndexes:
      if selectedIndex != index:
        nextIndexes.add selectedIndex
  else:
    nextIndexes = tableView.xSelectedIndexes
    nextIndexes.add index
  tableView.applySelectedIndexes(nextIndexes, index, index)

proc usesDiscontiguousSelection(modifiers: set[KeyModifier]): bool =
  kmCommand in modifiers or kmControl in modifiers

proc selectItemAtIndex(tableView: TableView, index: int, modifiers: set[KeyModifier]) =
  if tableView.isNil or tableView.xSelectionMode == tsmNone:
    return
  if kmShift in modifiers and tableView.xSelectionMode == tsmExtended:
    tableView.extendSelectionToIndex(index)
  elif modifiers.usesDiscontiguousSelection() and
      tableView.xSelectionMode in {tsmMultiple, tsmExtended}:
    tableView.toggleSelectionAtIndex(index)
  else:
    tableView.selectItemAtIndex(index)

proc selectionLeadIndex(tableView: TableView): int =
  if tableView.validTableIndex(tableView.xSelectionLead):
    tableView.xSelectionLead
  else:
    tableView.selectedIndex()

proc sendTableActivation(tableView: TableView, index: int) =
  if not tableView.rowEnabled(index):
    return
  tableView.tableRowDidActivate(index)
  emit tableView.rowWasActivated(DynamicAgent(tableView))
  discard tableView.sendAction()

proc activateItemAtIndex(
    tableView: TableView, index: int, modifiers: set[KeyModifier]
) =
  if tableView.isNil or not tableView.rowEnabled(index):
    return
  if tableView.selectionMode() != tsmNone:
    if not tableView.rowSelectable(index):
      return
    tableView.selectItemAtIndex(index, modifiers)
  tableView.sendTableActivation(index)

proc typeSelectStartIndex(tableView: TableView): int =
  if tableView.selectionLeadIndex() >= 0:
    tableView.selectionLeadIndex() + 1
  elif tableView.selectedIndex() >= 0:
    tableView.selectedIndex() + 1
  else:
    tableView.firstVisibleIndex()

proc rowTextMatchesPrefix(
    tableView: TableView, index: int, normalizedPrefix: string
): bool =
  tableView.rowTextForSummary(index).toLowerAscii().startsWith(normalizedPrefix)

proc firstRowMatchingText(tableView: TableView, text: string): int =
  if tableView.isNil or text.len == 0 or tableView.len() == 0:
    return -1
  let
    normalized = text.toLowerAscii()
    start = max(tableView.typeSelectStartIndex(), 0)
  for offset in 0 ..< tableView.len():
    let index = (start + offset) mod tableView.len()
    if tableView.rowSelectable(index) and
        tableView.rowTextMatchesPrefix(index, normalized):
      return index
  -1

proc selectItemMatchingText(tableView: TableView, text: string): bool =
  if tableView.selectionMode() == tsmNone:
    return false
  let index = tableView.firstRowMatchingText(text)
  if index < 0:
    return false
  tableView.selectItemAtIndex(index)
  true

proc isTypeSelectEvent(event: KeyEvent): bool =
  event.text.len > 0 and event.text notin [" ", "\n", "\r", "\t"] and
    event.modifiers * {kmControl, kmOption, kmCommand} == {}

proc handleTypeSelect(tableView: TableView, event: KeyEvent): bool =
  if not event.isTypeSelectEvent():
    return false
  let now = epochTime()
  if now - tableView.xTypeSelectLastTime > TableTypeSelectTimeout:
    tableView.xTypeSelectBuffer = ""
  tableView.xTypeSelectLastTime = now
  tableView.xTypeSelectBuffer.add event.text
  if tableView.selectItemMatchingText(tableView.xTypeSelectBuffer):
    return true
  if event.text != tableView.xTypeSelectBuffer:
    tableView.xTypeSelectBuffer = event.text
    return tableView.selectItemMatchingText(tableView.xTypeSelectBuffer)
  false

proc moveSelectionTo(tableView: TableView, index: int, extend = false, direction = 1) =
  if tableView.len() == 0 or tableView.selectionMode() == tsmNone:
    return
  let targetIndex = max(0, min(index, tableView.len() - 1))
  var boundedIndex = tableView.nextSelectableIndex(targetIndex, direction)
  if boundedIndex < 0 and direction > 0:
    boundedIndex = tableView.nextSelectableIndex(targetIndex, -1)
  elif boundedIndex < 0 and direction < 0:
    boundedIndex = tableView.nextSelectableIndex(targetIndex, 1)
  if boundedIndex < 0:
    return
  if extend and tableView.xSelectionMode == tsmExtended:
    tableView.extendSelectionToIndex(boundedIndex)
  else:
    tableView.selectItemAtIndex(boundedIndex)

proc moveSelection(tableView: TableView, delta: int, extend = false) =
  let start =
    if tableView.selectionLeadIndex() >= 0:
      tableView.selectionLeadIndex()
    elif delta > 0:
      tableView.firstVisibleIndex() - 1
    elif delta < 0:
      tableView.firstVisibleIndex() + tableView.visibleItemCount()
    else:
      tableView.firstVisibleIndex()
  tableView.moveSelectionTo(start + delta, extend, delta)

proc pageSelection(tableView: TableView, deltaPages: int, extend = false) =
  let delta = deltaPages * max(tableView.visibleItemCount(), 1)
  if delta == 0:
    return
  let start =
    if tableView.selectionLeadIndex() >= 0:
      tableView.selectionLeadIndex()
    elif delta > 0:
      tableView.firstVisibleIndex() - 1
    else:
      tableView.firstVisibleIndex() + tableView.visibleItemCount()
  let target = start + delta
  tableView.moveSelectionTo(target, extend, delta)
  let scrollView = tableView.scrollView()
  if scrollView.isNil:
    return
  if target >= tableView.len():
    let
      currentOffset = scrollView.contentOffset()
      maximumOffset = scrollView.maximumContentOffset()
    tableView.setTableContentOffset(initPoint(currentOffset.x, maximumOffset.y), true)
  elif target < 0:
    let currentOffset = scrollView.contentOffset()
    tableView.setTableContentOffset(initPoint(currentOffset.x, 0.0'f32), true)

proc autoscrollDraggingInfo(tableView: TableView, info: DraggingInfo): bool =
  if tableView.isNil or tableView.scrollView().isNil:
    return false
  let bounds = tableView.bounds()
  if bounds.isEmpty:
    return false
  let edge = max(tableView.rowHeight(), 12.0'f32)
  if info.location.y < bounds.minY + edge:
    tableView.scrollRows(-1)
    return true
  if info.location.y > bounds.maxY - edge:
    tableView.scrollRows(1)
    return true

proc resolvedRowHeight(tableView: TableView, row: int): float32 =
  if tableView.isNil:
    return 0.0'f32
  if row notin 0 ..< tableView.rowCount():
    return tableView.rowHeight()
  let delegate = tableView.delegate()
  if not delegate.isNil:
    let height =
      delegate.trySendLocal(tableRowHeight(), (tableView: tableView, row: row))
    if height.isSome:
      return height.get()
  tableView.rowHeight()

proc tableRowDidActivate(tableView: TableView, row: int) =
  let delegate = tableView.delegate()
  if delegate.isNil:
    return
  discard
    delegate.sendLocalIfHandled(didActivateRow(), (tableView: tableView, row: row))

proc clickedRow*(tableView: TableView): int =
  tableView.xClickedRow

proc clickedColumn*(tableView: TableView): TableColumn =
  tableView.xClickedColumn

proc clickedColumnIndex*(tableView: TableView): int =
  if tableView.isNil or tableView.xClickedColumn.isNil:
    -1
  else:
    tableView.columnIndex(tableView.xClickedColumn.identifier())

proc rowHeight*(tableView: TableView): float32 =
  tableView.xRowHeight.normalizedRowHeight()

proc rowHeightForRow*(tableView: TableView, row: int): float32 =
  if tableView.isNil:
    return 0.0'f32
  tableView.uncachedRowHeightForRow(row)

proc `rowHeight=`*(tableView: TableView, height: float32) =
  let normalized = height.normalizedRowHeight()
  if tableView.xRowHeight == normalized:
    return
  tableView.xRowHeight = normalized
  if not tableView.xScrollView.isNil:
    tableView.xScrollView.lineScroll = normalized
  tableView.xRowHeightCacheValid = false
  tableView.reloadData()

proc rowEnabled*(tableView: TableView, row: int): bool =
  tableView.tableRowEnabled(row)

proc rowSelectable*(tableView: TableView, row: int): bool =
  tableView.tableRowSelectable(row)

proc highlightedIndex*(tableView: TableView): int =
  tableView.xHighlightedIndex

proc `highlightedIndex=`*(tableView: TableView, index: int) =
  let boundedIndex = if tableView.rowEnabled(index): index else: -1
  if tableView.xHighlightedIndex == boundedIndex:
    return
  tableView.xHighlightedIndex = boundedIndex
  tableView.invalidateTableRows()

proc reloadData*(tableView: TableView) =
  let oldFirst = tableView.firstVisibleIndex()
  let
    oldFirstIdentifier = tableView.tableRowIdentifier(oldFirst)
    selectedIdentifiers = tableView.rowIdentifiersForRows(tableView.xSelectedIndexes)
    anchorIdentifier = tableView.tableRowIdentifier(tableView.xSelectionAnchor)
    leadIdentifier = tableView.tableRowIdentifier(tableView.xSelectionLead)
    editingIdentifier =
      if tableView.xEditing.active:
        tableView.tableRowIdentifier(tableView.xEditing.row)
      else:
        ""
  tableView.clearTableCellSlots()
  tableView.invalidateRowHeightCache()
  if selectedIdentifiers.len > 0:
    tableView.applySelectionForRowIdentifiers(
      selectedIdentifiers, anchorIdentifier, leadIdentifier
    )
  else:
    if tableView.xSelectionMode == tsmSingle and tableView.xSelectedIndexes.len > 0 and
        tableView.len() > 0:
      tableView.xSelectedIndexes[0] =
        min(max(tableView.xSelectedIndexes[0], -1), tableView.len() - 1)
    if tableView.xSelectionMode == tsmSingle and
        tableView.xSelectedIndex >= tableView.len() and tableView.len() > 0:
      tableView.xSelectedIndex = tableView.len() - 1
    if tableView.xSelectedIndexes.len == 0 and tableView.xSelectedIndex >= 0:
      tableView.xSelectedIndexes.add tableView.xSelectedIndex
    tableView.xSelectedIndexes =
      tableView.normalizeSelection(tableView.xSelectedIndexes)
    tableView.syncSelectedIndex()
    tableView.syncSelectionCursor()

  if not tableView.rowEnabled(tableView.xHighlightedIndex):
    tableView.xHighlightedIndex = -1
  if not tableView.rowEnabled(tableView.xPressedIndex):
    tableView.xPressedIndex = -1
  if tableView.xEditing.active and editingIdentifier.len > 0:
    let editingRow = tableView.tableRowIndexForIdentifier(editingIdentifier)
    if editingRow >= 0:
      tableView.xEditing.row = editingRow
    else:
      tableView.xEditing = TableEditingState(row: -1)
      Control(tableView).clearValidationError()
      tableView.clearEditingSurface()
  tableView.tileTableContent()
  let restoredFirst =
    if oldFirstIdentifier.len > 0:
      let row = tableView.tableRowIndexForIdentifier(oldFirstIdentifier)
      if row >= 0: row else: oldFirst
    else:
      oldFirst
  tableView.setTableContentOffset(
    initPoint(
      0.0'f32, tableView.rowOffset(min(restoredFirst, tableView.maxFirstVisibleIndex()))
    ),
    false,
  )
  if tableView.xSelectedIndex >= 0:
    tableView.scrollItemToVisible(tableView.xSelectedIndex)
  tableView.invalidateIntrinsicContentSize()
  tableView.invalidateTableRows()

proc flushTableRowUpdates(tableView: TableView, updates: openArray[TableRowUpdate]) =
  if tableView.isNil or updates.len == 0:
    return
  let
    selectedIdentifiers = tableView.rowIdentifiersForRows(tableView.xSelectedIndexes)
    anchorIdentifier = tableView.tableRowIdentifier(tableView.xSelectionAnchor)
    leadIdentifier = tableView.tableRowIdentifier(tableView.xSelectionLead)
    editingIdentifier =
      if tableView.xEditing.active:
        tableView.tableRowIdentifier(tableView.xEditing.row)
      else:
        ""
  tableView.clearTableCellSlots()
  tableView.invalidateRowHeightCache()
  tableView.tileTableContent()
  if selectedIdentifiers.len > 0:
    tableView.applySelectionForRowIdentifiers(
      selectedIdentifiers, anchorIdentifier, leadIdentifier
    )
  else:
    tableView.xSelectedIndexes =
      tableView.normalizeSelection(tableView.xSelectedIndexes)
    tableView.syncSelectedIndex()
    tableView.syncSelectionCursor()
  if tableView.xEditing.active and editingIdentifier.len > 0:
    let editingRow = tableView.tableRowIndexForIdentifier(editingIdentifier)
    if editingRow >= 0:
      tableView.xEditing.row = editingRow
  if tableView.xEditing.active and
      not tableView.validCell(tableView.xEditing.row, tableView.xEditing.column):
    tableView.xEditing = TableEditingState(row: -1)
    Control(tableView).clearValidationError()
    tableView.clearEditingSurface()
  tableView.invalidateIntrinsicContentSize()
  tableView.invalidateTableRows()
  emit tableView.tableRowsDidUpdate(DynamicAgent(tableView), @updates)

proc beginTableUpdates*(tableView: TableView) =
  if not tableView.isNil:
    inc tableView.xBatchUpdateDepth

proc endTableUpdates*(tableView: TableView) =
  if tableView.isNil or tableView.xBatchUpdateDepth <= 0:
    return
  dec tableView.xBatchUpdateDepth
  if tableView.xBatchUpdateDepth == 0 and tableView.xPendingRowUpdates.len > 0:
    let updates = tableView.xPendingRowUpdates
    tableView.xPendingRowUpdates.setLen(0)
    tableView.flushTableRowUpdates(updates)

proc applyTableRowUpdates*(tableView: TableView, updates: openArray[TableRowUpdate]) =
  if tableView.isNil or updates.len == 0:
    return
  if tableView.xBatchUpdateDepth > 0:
    for update in updates:
      tableView.xPendingRowUpdates.add update
    return
  tableView.flushTableRowUpdates(updates)

proc insertRowsAtIndexes*(
    tableView: TableView, indexes: openArray[int], identifiers: openArray[string] = []
) =
  tableView.applyTableRowUpdates([initTableRowInsertUpdate(indexes, identifiers)])

proc removeRowsAtIndexes*(
    tableView: TableView, indexes: openArray[int], identifiers: openArray[string] = []
) =
  tableView.applyTableRowUpdates([initTableRowRemoveUpdate(indexes, identifiers)])

proc reloadRowsAtIndexes*(
    tableView: TableView, indexes: openArray[int], identifiers: openArray[string] = []
) =
  tableView.applyTableRowUpdates([initTableRowReloadUpdate(indexes, identifiers)])

proc moveRow*(tableView: TableView, fromIndex, toIndex: int) =
  tableView.applyTableRowUpdates([initTableRowMoveUpdate(fromIndex, toIndex)])

proc selectedIndexes*(tableView: TableView): seq[int] =
  tableView.xSelectedIndexes

proc `selectedIndexes=`*(tableView: TableView, indexes: openArray[int]) =
  let nextIndexes = tableView.normalizeSelection(indexes)
  tableView.applySelectedIndexes(
    nextIndexes,
    tableView.firstSelectedIndex(nextIndexes),
    tableView.firstSelectedIndex(nextIndexes),
  )

proc selectedRange*(tableView: TableView): Slice[int] =
  let ranges = tableView.selectedRanges()
  if ranges.len == 0:
    0 .. -1
  else:
    ranges[0]

proc `selectedRange=`*(tableView: TableView, selectionRange: Slice[int]) =
  let indexes = selectionRange.indexesInRange()
  tableView.selectedIndexes = indexes

proc selectedRanges*(tableView: TableView): seq[Slice[int]] =
  if tableView.xSelectedIndexes.len == 0:
    return @[]
  var
    firstIndex = tableView.xSelectedIndexes[0]
    previousIndex = firstIndex
  for offset in 1 ..< tableView.xSelectedIndexes.len:
    let index = tableView.xSelectedIndexes[offset]
    if index == previousIndex + 1:
      previousIndex = index
    else:
      result.add firstIndex .. previousIndex
      firstIndex = index
      previousIndex = index
  result.add firstIndex .. previousIndex

proc selectionMode*(tableView: TableView): TableSelectionMode =
  tableView.xSelectionMode

proc `selectionMode=`*(tableView: TableView, mode: TableSelectionMode) =
  if tableView.xSelectionMode == mode:
    return
  tableView.xSelectionMode = mode
  if mode == tsmNone:
    tableView.xSelectedIndex = -1
    tableView.xSelectedIndexes.setLen(0)
    tableView.xSelectionAnchor = -1
    tableView.xSelectionLead = -1
  elif mode == tsmSingle and tableView.xSelectedIndexes.len > 1:
    tableView.xSelectedIndexes.setLen(1)
    tableView.xSelectedIndex = tableView.xSelectedIndexes[0]
    tableView.xSelectionAnchor = tableView.xSelectedIndex
    tableView.xSelectionLead = tableView.xSelectedIndex
  tableView.reloadData()

proc visibleRows*(tableView: TableView): int =
  tableView.xVisibleRows

proc `visibleRows=`*(tableView: TableView, rows: int) =
  let normalized = max(rows, 1)
  if tableView.xVisibleRows == normalized:
    return
  tableView.xVisibleRows = normalized
  tableView.reloadData()

proc usesAlternatingRowBackgrounds*(tableView: TableView): bool =
  tableView.xUsesAlternatingRowBackgrounds

proc `usesAlternatingRowBackgrounds=`*(tableView: TableView, value: bool) =
  if tableView.xUsesAlternatingRowBackgrounds == value:
    return
  tableView.xUsesAlternatingRowBackgrounds = value
  tableView.invalidateTableRows()

proc showsRowSeparators*(tableView: TableView): bool =
  tableView.xShowsRowSeparators

proc `showsRowSeparators=`*(tableView: TableView, value: bool) =
  if tableView.xShowsRowSeparators == value:
    return
  tableView.xShowsRowSeparators = value
  tableView.invalidateTableRows()

proc allowsRowReordering*(tableView: TableView): bool =
  (not tableView.isNil) and tableView.xAllowsRowReordering

proc `allowsRowReordering=`*(tableView: TableView, value: bool) =
  if tableView.isNil or tableView.xAllowsRowReordering == value:
    return
  tableView.xAllowsRowReordering = value
  if not value:
    tableView.xRowDragStartIndex = -1
    tableView.updateTableDropTarget(initDraggingDropTarget())

proc selectedIndex*(tableView: TableView): int =
  tableView.xSelectedIndex

proc `selectedIndex=`*(tableView: TableView, index: int) =
  if index < 0:
    tableView.selectedIndexes = @[]
  else:
    tableView.selectItemAtIndex(index)

proc rowItemRect*(tableView: TableView, itemIndex: int): Rect =
  tableView.tileTableContent()
  let contentView = tableView.contentView()
  if contentView.isNil:
    return rect(0.0, 0.0, 0.0, 0.0)
  let contentRect = contentView.tableContentItemRect(itemIndex)
  if contentRect.isEmpty:
    return rect(0.0, 0.0, 0.0, 0.0)
  let visibleRect =
    contentView.rectToView(contentRect, tableView).intersection(tableView.bounds())
  if visibleRect.size.height < tableView.rowHeightForRow(itemIndex) or
      visibleRect.isEmpty:
    rect(0.0, 0.0, 0.0, 0.0)
  else:
    visibleRect

proc rowItemIndexAtPoint*(tableView: TableView, point: Point): int =
  tableView.tileTableContent()
  let contentView = tableView.contentView()
  if contentView.isNil:
    return -1
  contentView.tableContentItemIndexAtPoint(contentView.pointFromView(point, tableView))

proc len*(tableView: TableView): int =
  if tableView.isNil:
    0
  else:
    tableView.rowCount()

proc visibleItemCount*(tableView: TableView): int =
  if tableView.len() <= 0:
    return 0
  let
    contentHeight = tableView.viewportSize().height
    visibleFromBounds =
      tableView.visibleRowsFrom(tableView.firstVisibleIndex(), contentHeight)
    preferredRows =
      if visibleFromBounds > 0:
        visibleFromBounds
      else:
        tableView.visibleRows()
  visibleRowItemCount(tableView.len(), preferredRows)

proc firstVisibleIndex*(tableView: TableView): int =
  tableView.rowIndexAtContentY(tableView.listContentOffset().y)

proc visibleRowSummaries*(tableView: TableView): seq[TableVisibleRowSummary] =
  if tableView.isNil:
    return @[]
  tableView.tileTableContent()
  let contentView = tableView.contentView()
  if contentView.isNil:
    return @[]
  for index in contentView.visibleContentRows().first ..<
      contentView.visibleContentRows().last:
    let row = tableView.tableRowState(index)
    let contentRect = contentView.tableContentItemRect(index)
    let rect =
      contentView.rectToView(contentRect, tableView).intersection(tableView.bounds())
    if not rect.isEmpty:
      result.add TableVisibleRowSummary(
        index: row.index,
        text: row.text,
        rect: rect,
        states: row.states * {ssDisabled, ssFocused, ssSelected, ssHovered},
      )

iterator visibleRowViews*(
    tableView: TableView
): tuple[index: int, view: View, rect: Rect] =
  if not tableView.isNil:
    tableView.tileTableContent()
    let contentView = tableView.contentView()
    if not contentView.isNil:
      contentView.syncVisibleRowViews()
      for rowView in contentView.xRowViews:
        yield (rowView.xRow.index, View(rowView), rowView.frame())

proc scrollRows*(tableView: TableView, delta: int) =
  if delta == 0:
    return
  let oldFirst = tableView.firstVisibleIndex()
  let nextFirst = max(oldFirst + delta, 0)
  let offset = tableView.listContentOffset()
  tableView.setTableContentOffset(
    initPoint(offset.x, tableView.rowOffset(nextFirst)), false
  )
  if tableView.firstVisibleIndex() != oldFirst:
    tableView.invalidateTableRows()

proc activateItemAtIndex*(tableView: TableView, index: int) =
  if tableView.isNil:
    return
  tableView.activateItemAtIndex(index, {})

proc allowsColumnSelection*(tableView: TableView): bool =
  (not tableView.isNil) and tableView.xAllowsColumnSelection

proc `allowsColumnSelection=`*(tableView: TableView, value: bool) =
  if tableView.xAllowsColumnSelection == value:
    return
  tableView.xAllowsColumnSelection = value
  if not value:
    tableView.xSelectedColumns.setLen(0)
  tableView.setNeedsDisplay(true)

proc selectedColumns*(tableView: TableView): seq[TableColumn] =
  tableView.xSelectedColumns

proc `selectedColumns=`*(tableView: TableView, columns: openArray[TableColumn]) =
  tableView.setSelectedColumns(@columns)

proc editingState*(tableView: TableView): TableEditingState =
  tableView.xEditing

proc editingValidationError*(tableView: TableView): string =
  if tableView.isNil: "" else: tableView.xEditing.validationError

proc editingValidation*(tableView: TableView): ObjectValidationError =
  if tableView.isNil:
    initObjectValidationError()
  else:
    tableView.xEditing.validation

proc autosaveName*(tableView: TableView): string =
  tableView.xAutosaveName

proc `autosaveName=`*(tableView: TableView, name: string) =
  if tableView.isNil or tableView.xAutosaveName == name:
    return
  tableView.xAutosaveName = name
  tableView.xHasRestoredState = false

proc stateStorage*(tableView: TableView): DynamicAgent =
  if tableView.isNil: nil else: tableView.xStateStorage

proc `stateStorage=`*(tableView: TableView, storage: DynamicAgent) =
  if tableView.isNil or tableView.xStateStorage == storage:
    return
  tableView.xStateStorage = storage
  tableView.xHasRestoredState = false

proc `stateStorage=`*(tableView: TableView, storage: Responder) =
  tableView.stateStorage = DynamicAgent(storage)

proc stateScope*(tableView: TableView): TableViewStateScope =
  if tableView.isNil: tvssAutomatic else: tableView.xStateScope

proc `stateScope=`*(tableView: TableView, scope: TableViewStateScope) =
  if tableView.isNil or tableView.xStateScope == scope:
    return
  tableView.xStateScope = scope
  tableView.xHasRestoredState = false

proc workspaceIdentifier*(tableView: TableView): string =
  if tableView.isNil: "" else: tableView.xWorkspaceIdentifier

proc `workspaceIdentifier=`*(tableView: TableView, identifier: string) =
  if tableView.isNil or tableView.xWorkspaceIdentifier == identifier:
    return
  tableView.xWorkspaceIdentifier = identifier
  tableView.xHasRestoredState = false

proc registerColumnAutosaveAlias*(
    tableView: TableView, oldIdentifier, newIdentifier: string
) =
  if tableView.isNil or oldIdentifier.len == 0 or newIdentifier.len == 0:
    return
  tableView.xColumnAutosaveAliases[oldIdentifier] = newIdentifier
  tableView.xHasRestoredState = false

proc clearColumnAutosaveAliases*(tableView: TableView) =
  if tableView.isNil:
    return
  tableView.xColumnAutosaveAliases.clear()
  tableView.xHasRestoredState = false

proc resolveColumnAutosaveIdentifier(tableView: TableView, identifier: string): string =
  if tableView.isNil:
    return identifier
  result = identifier
  var seen: seq[string]
  while result in tableView.xColumnAutosaveAliases and result notin seen:
    seen.add result
    result = tableView.xColumnAutosaveAliases[result]

proc draggingSession*(tableView: TableView): DraggingSession =
  tableView.xTableDraggingSession

proc beginDraggingRows*(
    tableView: TableView,
    rows: openArray[int],
    operations: DragOperations = {dgoMove},
    pasteboardName: string = DragPasteboardName,
): DraggingSession =
  if tableView.isNil:
    return nil
  let resolved = tableView.trySendLocal(
    beginDraggingRows(),
    (rows: @rows, operations: operations, pasteboardName: pasteboardName),
  )
  if resolved.isSome:
    resolved.get()
  else:
    nil

proc beginDraggingColumns*(
    tableView: TableView,
    columns: openArray[TableColumn],
    operations: DragOperations = {dgoMove},
    pasteboardName: string = DragPasteboardName,
): DraggingSession =
  if tableView.isNil:
    return nil
  let resolved = tableView.trySendLocal(
    beginDraggingColumns(),
    (columns: @columns, operations: operations, pasteboardName: pasteboardName),
  )
  if resolved.isSome:
    resolved.get()
  else:
    nil

proc draggingInfo*(tableView: TableView): DraggingInfo =
  if tableView.xTableDraggingSession.isNil:
    DraggingInfo()
  else:
    tableView.xTableDraggingSession.draggingInfo()

proc withDropTarget*(
    info: DraggingInfo, row = -1, column: TableColumn = nil, position = ddpOn
): DraggingInfo =
  if row >= 0 and not column.isNil:
    info.withDropTarget(initCellDropTarget(row, column.identifier()))
  elif row >= 0:
    info.withDropTarget(initRowDropTarget(row, position = position))
  elif not column.isNil:
    info.withDropTarget(initColumnDropTarget(column.identifier(), position = position))
  else:
    info.withDropTarget(initDraggingDropTarget())

func tableDropPositionForAxis(
    value, minValue, maxValue: float32
): DraggingDropPosition =
  let edge = (maxValue - minValue) * 0.25'f32
  if value <= minValue + edge:
    ddpBefore
  elif value >= maxValue - edge:
    ddpAfter
  else:
    ddpOn

func tableDropPositionForRow(location: Point, rect: Rect): DraggingDropPosition =
  tableDropPositionForAxis(location.y, rect.minY, rect.maxY)

func tableInsertionPositionForRow(location: Point, rect: Rect): DraggingDropPosition =
  if location.y < rect.origin.y + rect.size.height * 0.5'f32: ddpBefore else: ddpAfter

func tableDropPositionForColumn(location: Point, rect: Rect): DraggingDropPosition =
  tableDropPositionForAxis(location.x, rect.minX, rect.maxX)

proc draggingTableRows(tableView: TableView): bool =
  let session = tableView.draggingSession()
  not session.isNil and session.state() == dssActive and
    session.pasteboard().stringForType(TablePasteboardTypeRows).len > 0

proc defaultDropTargetForDraggingLocation(
    tableView: TableView, location: Point
): DraggingDropTarget =
  if tableView.isNil:
    return initDraggingDropTarget()
  let
    row = tableView.rowItemIndexAtPoint(location)
    headerHit = tableView.tableHeaderHitTest(location)
    column =
      if headerHit.part == thpNone:
        tableView.tableColumnAtPoint(location)
      else:
        headerHit.column
  if row >= 0 and not column.isNil:
    let
      rowRect = tableView.rowItemRect(row)
      cellRect = tableView.columnRect(rowRect, column)
    if tableView.draggingTableRows():
      let position = tableInsertionPositionForRow(location, rowRect)
      return initRowDropTarget(row, rowRect, position)
    return initCellDropTarget(row, column.identifier(), cellRect)
  if row >= 0:
    let rowRect = tableView.rowItemRect(row)
    return initRowDropTarget(row, rowRect, tableDropPositionForRow(location, rowRect))
  if not headerHit.column.isNil:
    let columnRect = tableView.tableHeaderColumnRect(headerHit.column)
    return initColumnDropTarget(
      headerHit.column.identifier(),
      columnRect,
      tableDropPositionForColumn(location, columnRect),
    )
  initDraggingDropTarget()

proc dropTargetForDraggingLocation*(
    tableView: TableView, location: Point
): DraggingDropTarget =
  if tableView.isNil:
    return initDraggingDropTarget()
  let proposedTarget = tableView.defaultDropTargetForDraggingLocation(location)
  let delegate = tableView.delegate()
  if not delegate.isNil:
    let resolved = delegate.trySendLocal(
      tableDropTargetForLocation(),
      (tableView: tableView, location: location, proposedTarget: proposedTarget),
    )
    if resolved.isSome:
      return resolved.get()
  proposedTarget

proc activeDropTarget(tableView: TableView): DraggingDropTarget =
  if tableView.isNil:
    return initDraggingDropTarget()
  if not tableView.xTableDraggingSession.isNil and
      tableView.xTableDraggingSession.state() == dssActive:
    return tableView.xTableDraggingSession.dropTarget()
  tableView.xTableDropTarget

proc currentDropTarget*(tableView: TableView): DraggingDropTarget =
  tableView.activeDropTarget()

proc updateTableDropTarget(tableView: TableView, target: DraggingDropTarget) =
  if tableView.isNil or tableView.xTableDropTarget == target:
    return
  tableView.xTableDropTarget = target
  tableView.invalidateTableRows()

proc joinRowIndexes(rows: openArray[int]): string =
  for index, row in rows:
    if index > 0:
      result.add ","
    result.add $row

proc joinIdentifiers(identifiers: openArray[string]): string =
  for index, identifier in identifiers:
    if index > 0:
      result.add ","
    result.add identifier

proc parseRowIndexes(value: string): seq[int] =
  for part in value.split(","):
    let text = part.strip()
    if text.len > 0:
      try:
        result.add parseInt(text)
      except ValueError:
        discard

proc parseIdentifiers(value: string): seq[string] =
  for part in value.split(","):
    let identifier = part.strip()
    if identifier.len > 0:
      result.add identifier

proc tableDraggingRows*(info: DraggingInfo): seq[int] =
  if info.pasteboard.isNil:
    return @[]
  parseRowIndexes(info.pasteboard.stringForType(TablePasteboardTypeRows))

proc tableDraggingRowIdentifiers*(info: DraggingInfo): seq[string] =
  if info.pasteboard.isNil:
    return @[]
  parseIdentifiers(info.pasteboard.stringForType(TablePasteboardTypeRowIdentifiers))

proc tableDraggingColumns*(info: DraggingInfo): seq[string] =
  if info.pasteboard.isNil:
    return @[]
  parseIdentifiers(info.pasteboard.stringForType(TablePasteboardTypeColumns))

proc tableDropRow*(info: DraggingInfo): int =
  info.dropTarget.row

proc tableDropColumn*(info: DraggingInfo): string =
  info.dropTarget.column

proc tableDropPosition*(info: DraggingInfo): DraggingDropPosition =
  info.dropTarget.position

proc normalizedReorderRows(tableView: TableView, rows: openArray[int]): seq[int] =
  if tableView.isNil:
    return
  for row in rows:
    if row in 0 ..< tableView.len() and row notin result:
      result.add row
  result.sort()

func adjustedReorderInsertionIndex(rows: openArray[int], insertionIndex: int): int =
  result = max(insertionIndex, 0)
  for row in rows:
    if row < insertionIndex:
      dec result
  result = max(result, 0)

func rowsAreContiguous(rows: openArray[int]): bool =
  if rows.len <= 1:
    return true
  for index in 1 ..< rows.len:
    if rows[index] != rows[index - 1] + 1:
      return false
  true

func reorderWouldChange(rows: openArray[int], adjustedInsertionIndex: int): bool =
  rows.len > 0 and not (rows.rowsAreContiguous() and adjustedInsertionIndex == rows[0])

proc insertionIndexForDropTarget(
    tableView: TableView, target: DraggingDropTarget
): int =
  if tableView.isNil or target.kind != ddtRow:
    return -1
  let row = max(0, min(target.row, tableView.len()))
  case target.position
  of ddpAfter:
    min(row + 1, tableView.len())
  of ddpOn, ddpBefore:
    row

proc canReorderRows(
    tableView: TableView, rows: openArray[int], target: DraggingDropTarget
): bool =
  if tableView.isNil or not tableView.allowsRowReordering():
    return false
  let normalizedRows = tableView.normalizedReorderRows(rows)
  if normalizedRows.len == 0:
    return false
  let insertionIndex = tableView.insertionIndexForDropTarget(target)
  if insertionIndex < 0:
    return false
  let adjustedIndex = adjustedReorderInsertionIndex(normalizedRows, insertionIndex)
  if not normalizedRows.reorderWouldChange(adjustedIndex):
    return false

  let delegate = tableView.delegate()
  if not delegate.isNil:
    let allowed = delegate.trySendLocal(
      shouldReorderRows(), (tableView: tableView, rows: normalizedRows, target: target)
    )
    if allowed.isSome:
      return allowed.get()
  true

proc canReorderTableModelRows(model: TableModel): bool =
  not model.isNil and model.xSortDescriptors.len == 0 and model.xFilter.isNil and
    model.len() == model.sourceLen()

proc reorderTableModelRows(
    tableView: TableView,
    model: TableModel,
    rows: openArray[int],
    target: DraggingDropTarget,
): bool =
  if tableView.isNil or not model.canReorderTableModelRows():
    return false
  let normalizedRows = tableView.normalizedReorderRows(rows)
  if not tableView.canReorderRows(normalizedRows, target):
    return false

  let
    insertionIndex = tableView.insertionIndexForDropTarget(target)
    adjustedIndex = adjustedReorderInsertionIndex(normalizedRows, insertionIndex)
    selectedIdentifiers = tableView.rowIdentifiersForRows(tableView.xSelectedIndexes)
    anchorIdentifier = tableView.tableRowIdentifier(tableView.xSelectionAnchor)
    leadIdentifier = tableView.tableRowIdentifier(tableView.xSelectionLead)

  var
    nextRows = model.rows()
    movingRows: seq[TableRowValue]
  for row in normalizedRows:
    movingRows.add nextRows[row]
  for index in countdown(normalizedRows.high, 0):
    nextRows.delete(normalizedRows[index])
  for index, row in movingRows:
    nextRows.insert(row, adjustedIndex + index)

  model.rows = nextRows
  tableView.xSelectedIndexes.setLen(0)
  tableView.xSelectedIndex = -1
  tableView.xSelectionAnchor = -1
  tableView.xSelectionLead = -1
  tableView.reloadData()
  if selectedIdentifiers.len > 0:
    tableView.applySelectionForRowIdentifiers(
      selectedIdentifiers, anchorIdentifier, leadIdentifier
    )
  else:
    var nextSelection: seq[int]
    for index in 0 ..< movingRows.len:
      nextSelection.add adjustedIndex + index
    tableView.selectedIndexes = nextSelection
  true

proc defaultReorderRows(
    tableView: TableView, rows: openArray[int], target: DraggingDropTarget
): bool =
  if tableView.isNil:
    return false
  let normalizedRows = tableView.normalizedReorderRows(rows)
  if not tableView.canReorderRows(normalizedRows, target):
    return false

  let delegate = tableView.delegate()
  if not delegate.isNil:
    let performed = delegate.trySendLocal(
      performRowReorder(), (tableView: tableView, rows: normalizedRows, target: target)
    )
    if performed.isSome:
      return performed.get()

  let source = tableView.dataSource()
  if source of TableModel:
    return tableView.reorderTableModelRows(TableModel(source), normalizedRows, target)
  false

proc reorderRows*(
    tableView: TableView, rows: openArray[int], target: DraggingDropTarget
): bool =
  if tableView.isNil:
    return false
  let reordered =
    tableView.trySendLocal(reorderTableRows(), (rows: @rows, target: target))
  if reordered.isSome:
    reordered.get()
  else:
    false

proc isInternalTableRowDrag(tableView: TableView, info: DraggingInfo): bool =
  not tableView.isNil and info.source == DynamicAgent(tableView) and
    info.tableDraggingRows().len > 0

proc isTableRowReorderDrag(tableView: TableView, info: DraggingInfo): bool =
  tableView.isInternalTableRowDrag(info) and tableView.allowsRowReordering() and
    info.dropTarget.kind == ddtRow

proc canAcceptTableRowReorder(tableView: TableView, info: DraggingInfo): bool =
  tableView.isTableRowReorderDrag(info) and dgoMove in info.allowedOperations and
    tableView.canReorderRows(info.tableDraggingRows(), info.dropTarget)

proc findCellSlot(slots: openArray[TableCellSlot], row: int, column: TableColumn): int =
  for index, slot in slots:
    if slot.row == row and slot.column == column:
      return index
  -1

proc clearTableCellSlots(tableView: TableView) =
  if tableView.isNil:
    return
  for slot in tableView.xCellSlots:
    tableView.recycleCellSlot(slot)
  tableView.xCellSlots.setLen(0)

proc recycleVisibleCellViews*(tableView: TableView) =
  tableView.clearTableCellSlots()

proc hasHostedCell(tableView: TableView, row: int, column: TableColumn): bool =
  not tableView.isNil and tableView.xCellSlots.findCellSlot(row, column) >= 0

proc syncVisibleTableCells(tableView: TableView) =
  if tableView.isNil:
    return
  let previousSlots = tableView.xCellSlots
  var
    nextSlots: seq[TableCellSlot]
    used = newSeq[bool](previousSlots.len)
  for (row, rowView, rowRect) in tableView.visibleRowViews():
    let rowBounds = rect(0.0, 0.0, rowRect.size.width, rowRect.size.height)
    for column in tableView.columns:
      if column.hidden():
        continue
      var cellView: View
      let previousIndex = previousSlots.findCellSlot(row, column)
      if previousIndex >= 0:
        used[previousIndex] = true
        cellView = previousSlots[previousIndex].view
      else:
        cellView = tableView.tableCellView(row, column)
      if not cellView.isNil:
        if cellView.superview() != rowView:
          rowView.addSubview(cellView)
        cellView.frame = tableView.columnRect(rowBounds, column)
        cellView.hidden = false
        cellView.setWidgetState(ssDisabled, not tableView.rowEnabled(row))
        tableView.applyCellAccessibility(row, column, cellView)
        nextSlots.add TableCellSlot(row: row, column: column, view: cellView)
  for index, slot in previousSlots:
    if not used[index]:
      tableView.recycleCellSlot(slot)
  tableView.xCellSlots = nextSlots

proc visibleCellView(tableView: TableView, row: int, column: TableColumn): View =
  if tableView.isNil:
    return nil
  let index = tableView.xCellSlots.findCellSlot(row, column)
  if index >= 0:
    tableView.xCellSlots[index].view
  else:
    nil

proc visibleRowView(tableView: TableView, row: int): tuple[view: View, rect: Rect] =
  if tableView.isNil:
    return (nil, rect(0.0, 0.0, 0.0, 0.0))
  for (index, rowView, rowRect) in tableView.visibleRowViews():
    if index == row:
      return (rowView, rowRect)
  (nil, rect(0.0, 0.0, 0.0, 0.0))

proc prepareEditingSurface(tableView: TableView): bool =
  if tableView.isNil or not tableView.xEditing.active:
    return false
  tableView.xEditingHostView = nil
  tableView.xEditingCell = nil
  tableView.xEditingHostIsRowView = false

  tableView.scrollItemToVisible(tableView.xEditing.row)
  tableView.syncVisibleTableCells()

  let cellView =
    tableView.visibleCellView(tableView.xEditing.row, tableView.xEditing.column)
  if not cellView.isNil:
    tableView.xEditingHostView = cellView
    if cellView of Control:
      tableView.xEditingCell = Control(cellView).cell()
    return true

  let row = tableView.visibleRowView(tableView.xEditing.row)
  if row.view.isNil:
    return false
  tableView.xEditingHostView = row.view
  tableView.xEditingHostIsRowView = true
  true

proc clearEditingSurface(tableView: TableView) =
  if tableView.isNil:
    return
  tableView.xEditingHostView = nil
  tableView.xEditingCell = nil
  tableView.xEditingHostIsRowView = false

proc fieldEditorFrameForEditing(tableView: TableView): Rect =
  if tableView.isNil or tableView.xEditingHostView.isNil:
    return rect(0.0, 0.0, 0.0, 0.0)
  if tableView.xEditingHostIsRowView:
    let row = tableView.visibleRowView(tableView.xEditing.row)
    let rowBounds = rect(0.0, 0.0, row.rect.size.width, row.rect.size.height)
    let cellFrame = tableView.columnRect(rowBounds, tableView.xEditing.column)
    let delegate = tableView.delegate()
    if not delegate.isNil:
      let frame = delegate.trySendLocal(
        fieldEditorFrameForCell(),
        (
          tableView: tableView,
          row: tableView.xEditing.row,
          column: tableView.xEditing.column,
          proposedFrame: cellFrame,
        ),
      )
      if frame.isSome:
        return frame.get()
    let style = tableView.effectiveAppearance().resolveRowItemStyle(
        controlStyle(
          tableView.xItemRole,
          tableView.widgetStateSet(),
          id = tableView.styleId(),
          classes = tableView.styleClasses(),
        )
      )
    return style.rowItemTextRect(cellFrame)
  tableView.xEditingHostView.bounds()

proc fieldEditorTextStyleForEditing(tableView: TableView): TextStyle =
  if tableView.isNil:
    return initAppearance().resolveRowItemStyle(controlStyle(srRowItem)).text
  let style = tableView.effectiveAppearance().resolveRowItemStyle(
      controlStyle(
        tableView.xItemRole,
        tableView.widgetStateSet(),
        id = tableView.styleId(),
        classes = tableView.styleClasses(),
      )
    )
  style.text

proc removeFieldEditorFromSurface(tableView: TableView, editor: FieldEditor) =
  if tableView.isNil or editor.isNil:
    return
  TextView(editor).clearTextStyleOverride()
  if tableView.xEditingHostView of Control:
    Control(tableView.xEditingHostView).setCurrentEditor(nil)
  if not tableView.xEditingCell.isNil:
    tableView.xEditingCell.endEditing(editor, tableView.xEditingHostView)
  elif editor.superview() == tableView.xEditingHostView:
    editor.removeFromSuperview()

proc installFieldEditorOnSurface(tableView: TableView, editor: FieldEditor) =
  if tableView.isNil or editor.isNil:
    return
  if tableView.xEditingHostView.isNil and not tableView.prepareEditingSurface():
    return
  let frame = tableView.fieldEditorFrameForEditing()
  if not tableView.xEditingCell.isNil:
    tableView.xEditingCell.selectWithFrame(
      frame, tableView.xEditingHostView, editor, 0, editor.textStorage().len
    )
    if tableView.xEditingHostView of Control:
      Control(tableView.xEditingHostView).setCurrentEditor(editor)
  else:
    let textView = TextView(editor)
    textView.setTextStyleOverride(tableView.fieldEditorTextStyleForEditing())
    textView.alignment = tableView.xEditing.column.alignment()
    editor.frame = frame
    editor.bounds = rect(0.0, 0.0, frame.size.width, frame.size.height)
    if not tableView.xEditingHostView.isNil and
        editor.superview() != tableView.xEditingHostView:
      tableView.xEditingHostView.addSubview(editor)
    editor.selectedRange = initTextRange(0, editor.textStorage().len)

proc setEditingValidation(tableView: TableView, error: ObjectValidationError) =
  if tableView.isNil or not tableView.xEditing.active:
    return
  let hadError = tableView.xEditing.validation.failed()
  tableView.xEditing.validation = error
  tableView.xEditing.validationError =
    if error.failed():
      error.displayMessage()
    else:
      ""
  if error.failed():
    Control(tableView).setValidationError(error)
  else:
    Control(tableView).clearValidationError()
  if hadError or error.failed():
    tableView.setNeedsDisplay(true)

proc parseEditingObjectValue(tableView: TableView, value: string): ObjectParseResult =
  if tableView.isNil or not tableView.xEditing.active:
    return initObjectParseResult(toObj(value))
  let delegate = tableView.delegate()
  if not delegate.isNil:
    let parsed = delegate.trySendLocal(
      parseObjectValueForCell(),
      (
        tableView: tableView,
        row: tableView.xEditing.row,
        column: tableView.xEditing.column,
        value: value,
      ),
    )
    if parsed.isSome:
      return parsed.get()
  Control(tableView).parseEditedObjectValue(value, ovrTableCell)

proc validateEditingValue(tableView: TableView, value: string): bool =
  if tableView.isNil or not tableView.xEditing.active:
    return true
  tableView.setEditingValidation(initObjectValidationError())
  let parsed = tableView.parseEditingObjectValue(value)
  if parsed.failed():
    tableView.setEditingValidation(parsed.error)
    return false
  let delegate = tableView.delegate()
  if delegate.isNil:
    tableView.xEditing.objectValue = parsed.value
    return true
  let validation = delegate.trySendLocal(
    validationErrorForCell(),
    (
      tableView: tableView,
      row: tableView.xEditing.row,
      column: tableView.xEditing.column,
      value: value,
    ),
  )
  if validation.isSome and validation.get().len > 0:
    tableView.setEditingValidation(
      initObjectValidationError(
        oveCustom,
        message = validation.get(),
        input = value,
        expectedKind = parsed.value.kind,
        actualKind = parsed.value.kind,
      )
    )
    return false
  let objectValidation = delegate.trySendLocal(
    validationErrorForObjectValue(),
    (
      tableView: tableView,
      row: tableView.xEditing.row,
      column: tableView.xEditing.column,
      value: parsed.value,
    ),
  )
  if objectValidation.isSome and objectValidation.get().failed():
    tableView.setEditingValidation(objectValidation.get())
    return false
  tableView.xEditing.objectValue = parsed.value
  true

proc finishCommitEditingCell(tableView: TableView, value: string): bool =
  if tableView.isNil or not tableView.xEditing.active:
    return false
  if not tableView.validateEditingValue(value):
    return false
  let editing = tableView.xEditing
  let objectValue = editing.objectValue
  if not tableView.writeTableCellObjectValue(editing.row, editing.column, objectValue):
    tableView.setEditingValidation(
      initObjectValidationError(
        oveRejected,
        message = "Cell value was rejected by the data source",
        input = value,
        expectedKind = objectValue.kind,
        actualKind = objectValue.kind,
      )
    )
    return false
  tableView.xEndedEditingRow = editing.row
  tableView.xEndedEditingColumn = editing.column
  tableView.xEndedEditingCommitted = true
  tableView.xEditing = TableEditingState(row: -1)
  tableView.clearEditingSurface()
  let delegate = tableView.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didCommitEditingCell(),
      (tableView: tableView, row: editing.row, column: editing.column, value: value),
    )
    discard delegate.sendLocalIfHandled(
      didCommitEditingObjectValue(),
      (
        tableView: tableView,
        row: editing.row,
        column: editing.column,
        value: objectValue,
      ),
    )
  emit tableView.cellEditDidCommit(
    DynamicAgent(tableView), editing.row, editing.column, value
  )
  emit tableView.cellObjectValueDidCommit(
    DynamicAgent(tableView), editing.row, editing.column, objectValue
  )
  Control(tableView).clearValidationError()
  tableView.clearTableCellSlots()
  tableView.setNeedsDisplay(true)
  true

proc finishCancelEditingCell(tableView: TableView): bool =
  if tableView.isNil or not tableView.xEditing.active:
    return false
  let editing = tableView.xEditing
  tableView.xEndedEditingRow = editing.row
  tableView.xEndedEditingColumn = editing.column
  tableView.xEndedEditingCommitted = false
  tableView.xEditing = TableEditingState(row: -1)
  Control(tableView).clearValidationError()
  tableView.clearEditingSurface()
  let delegate = tableView.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didCancelEditingCell(),
      (tableView: tableView, row: editing.row, column: editing.column),
    )
  tableView.setNeedsDisplay(true)
  true

proc editableColumns(tableView: TableView): seq[TableColumn] =
  if not tableView.isNil:
    for column in tableView.visibleColumns():
      result.add column

proc editableCellInRowAfter(
    tableView: TableView, row: int, column: TableColumn, direction: int
): TableEditingState =
  result = TableEditingState(row: -1)
  if tableView.isNil or row notin 0 ..< tableView.rowCount():
    return
  let columns = tableView.editableColumns()
  if columns.len == 0:
    return
  var columnIndex = -1
  for index, current in columns:
    if current == column:
      columnIndex = index
      break
  if columnIndex < 0:
    columnIndex = (if direction >= 0: -1 else: columns.len)
  var nextColumnIndex = columnIndex
  while true:
    nextColumnIndex += (if direction >= 0: 1 else: -1)
    if nextColumnIndex < 0 or nextColumnIndex >= columns.len:
      return
    let nextColumn = columns[nextColumnIndex]
    if tableView.shouldBeginEditingCell(row, nextColumn):
      return TableEditingState(row: row, column: nextColumn, active: true)

proc moveEditingFromEndedCell(tableView: TableView, movement: TextEditMovement): bool =
  if tableView.isNil or not tableView.xEndedEditingCommitted:
    return false
  var next = TableEditingState(row: -1)
  case movement
  of temTab:
    next = tableView.editableCellInRowAfter(
      tableView.xEndedEditingRow, tableView.xEndedEditingColumn, 1
    )
  of temBacktab:
    next = tableView.editableCellInRowAfter(
      tableView.xEndedEditingRow, tableView.xEndedEditingColumn, -1
    )
  of temReturn, temNone:
    discard
  if next.row < 0 or next.column.isNil:
    return false
  tableView.beginEditingCell(next.row, next.column)

proc rowItemStyle(
    tableView: TableView, context: DrawContext, states: set[WidgetState]
): RowItemStyle =
  context.appearance.resolveRowItemStyle(
    controlStyle(
      srRowItem, states, id = tableView.styleId(), classes = tableView.styleClasses()
    )
  )

proc drawTableCellText(
    tableView: TableView,
    context: DrawContext,
    row: int,
    column: TableColumn,
    rect: Rect,
    style: RowItemStyle,
) =
  if rect.isEmpty:
    return
  if tableView.xEditing.active and tableView.xEditing.row == row and
      tableView.xEditing.column == column:
    return
  let text = tableView.tableCellText(row, column)
  if text.len > 0:
    let textRect = style.rowItemTextRect(rect)
    let textRoot = context.addRenderRectangle(
      context.renderRectFor(textRect), fill(color(0.0, 0.0, 0.0, 0.0)), clips = true
    )
    discard context.addText(
      DefaultDrawLevel,
      textRoot,
      textRect,
      clippedText(text, textRect.size.width, style.text),
      style.text,
      column.alignment(),
    )

proc drawTableRow(
    tableView: TableView, context: DrawContext, rect: Rect, row: RowState
) =
  if tableView.isNil or context.isNil:
    return
  let emptyRow = initRowState(row.index, "", states = row.states)
  tableView.drawTableRowItem(context, rect, emptyRow)
  if row.index < 0:
    return
  let
    rowBounds = rect(0.0, 0.0, rect.size.width, rect.size.height)
    style = tableView.rowItemStyle(context, row.states)
  for column in tableView.columns:
    if column.hidden():
      continue
    if not tableView.hasHostedCell(row.index, column):
      let cellRect = tableView.columnRect(rowBounds, column)
      tableView.drawTableCellText(context, row.index, column, cellRect, style)
  tableView.drawTableDropTarget(context, rect, row)

proc drawHorizontalTableDropIndicator(
    tableView: TableView,
    context: DrawContext,
    rect: Rect,
    position: DraggingDropPosition,
) =
  if tableView.isNil or context.isNil or rect.isEmpty:
    return
  let
    chrome = tableView.tableHeaderChrome(context)
    indicatorFill = tableView.tableDropIndicatorFill(context)
    thickness = max(chrome.insertionWidth, 2.0'f32)
    capWidth = max(chrome.insertionCapHeight, thickness)
    capHeight = max(chrome.insertionCapWidth, thickness)
    lineY =
      case position
      of ddpBefore:
        rect.minY
      of ddpOn, ddpAfter:
        max(rect.maxY - thickness, rect.minY)
    lineRect = rect(rect.origin.x, lineY, rect.size.width, thickness)
    capY = lineY + (thickness - capHeight) * 0.5'f32
    leftCap = rect(rect.origin.x, capY, capWidth, capHeight)
    rightCap = rect(rect.maxX - capWidth, capY, capWidth, capHeight)

  discard context.addRenderRectangle(
    context.renderRectFor(lineRect), indicatorFill, cornerRadius = chrome.cornerRadius
  )
  discard context.addRenderRectangle(
    context.renderRectFor(leftCap), indicatorFill, cornerRadius = chrome.cornerRadius
  )
  discard context.addRenderRectangle(
    context.renderRectFor(rightCap), indicatorFill, cornerRadius = chrome.cornerRadius
  )

proc drawTableDropTarget(
    tableView: TableView, context: DrawContext, rect: Rect, row: RowState
) =
  if tableView.isNil or context.isNil or row.index < 0:
    return
  let target = tableView.activeDropTarget()
  if target.kind notin {ddtRow, ddtCell, ddtItem} or target.row != row.index:
    return
  var indicatorBounds = rect
  if target.kind == ddtCell and target.column.len > 0:
    let column = tableView.columnWithIdentifier(target.column)
    if not column.isNil:
      indicatorBounds = tableView.columnRect(rect, column)
  tableView.drawHorizontalTableDropIndicator(context, indicatorBounds, target.position)

proc tableFocusRingBox(box: ControlBoxStyle): ControlBoxStyle =
  result = box
  if result.focusRingInset > 0.0'f32:
    result.focusRingInset = min(result.focusRingInset, result.focusRingWidth * 0.5'f32)

proc noteColumnsChanged(tableView: TableView) =
  if tableView.isNil:
    return
  tableView.syncTableScrollChrome()
  tableView.syncHeaderTrackingAreas()
  tableView.clearTableCellSlots()
  tableView.invalidateIntrinsicContentSize()
  tableView.setNeedsLayout()
  tableView.setNeedsDisplay(true)

proc syncTableScrollChrome(tableView: TableView) =
  if tableView.isNil:
    return
  let scrollView = tableView.scrollView()
  if scrollView.isNil:
    return
  scrollView.scrollerInsets = insets(tableView.tableHeaderHeight(), 0.0, 0.0, 0.0)

proc detachColumn(column: TableColumn) =
  if column.isNil or column.xTableView.isNil:
    return
  column.xTableView.removeColumnAtIndex(
    column.xTableView.columnIndex(column.identifier)
  )

proc insertColumn*(tableView: TableView, column: TableColumn, index: int) =
  if tableView.isNil or column.isNil or column.identifier.len == 0:
    return
  let duplicateIndex = tableView.columnIndex(column.identifier)
  if duplicateIndex >= 0 and tableView.xColumns[duplicateIndex] != column:
    return
  if duplicateIndex >= 0:
    tableView.removeColumnAtIndex(duplicateIndex)
  elif not column.tableView().isNil:
    column.detachColumn()
  let boundedIndex = max(0, min(index, tableView.xColumns.len))
  tableView.findUndoManager().registerCollectionInsert(
    proc(index: int) =
      tableView.removeColumnAt(index),
    boundedIndex,
    "Insert Column",
  )
  column.xTableView = tableView
  tableView.xColumns.insert(column, boundedIndex)
  tableView.noteColumnsChanged()

proc addColumn*(tableView: TableView, column: TableColumn) =
  if not tableView.isNil:
    tableView.insertColumn(column, tableView.xColumns.len)

proc removeColumnAtIndex(tableView: TableView, index: int) =
  if tableView.isNil or index notin 0 ..< tableView.xColumns.len:
    return
  let column = tableView.xColumns[index]
  tableView.findUndoManager().registerCollectionRemove(
    proc(index: int, column: TableColumn) =
      tableView.insertColumn(column, index),
    index,
    column,
    "Remove Column",
  )
  tableView.xColumns.delete(index)
  if not column.isNil:
    column.xTableView = nil
  tableView.noteColumnsChanged()

proc removeColumnAt*(tableView: TableView, index: int) =
  tableView.removeColumnAtIndex(index)

proc removeColumn*(tableView: TableView, column: TableColumn) =
  if tableView.isNil or column.isNil:
    return
  let index = tableView.columnIndex(column.identifier)
  if index >= 0 and tableView.xColumns[index] == column:
    tableView.removeColumnAtIndex(index)

proc removeColumn*(tableView: TableView, identifier: string) =
  tableView.removeColumnAtIndex(tableView.columnIndex(identifier))

proc bindTableModel*(tableView: TableView, model: TableModel) =
  if tableView.isNil:
    return
  if model.isNil:
    tableView.dataSource = DynamicAgent(nil)
    tableView.delegate = DynamicAgent(nil)
    return
  model.installTableModelProtocols()
  for modelColumn in model.columns():
    let identifier = modelColumn.tableModelColumnIdentifier()
    if identifier.len == 0:
      continue
    var column = tableView.columnWithIdentifier(identifier)
    if column.isNil:
      column = newTableColumn(
        identifier, modelColumn.tableModelColumnTitle(), width = modelColumn.width
      )
      tableView.addColumn(column)
    else:
      column.title = modelColumn.tableModelColumnTitle()
      if modelColumn.width > 0.0'f32:
        column.width = modelColumn.width
    column.hidden = modelColumn.hidden
  tableView.dataSource = DynamicAgent(model)
  tableView.delegate = DynamicAgent(model)
  tableView.reloadData()

proc initTableViewState*(
    columns: openArray[TableColumnAutosaveRecord] = [],
    selectedRows: openArray[int] = [],
    selectedColumns: openArray[string] = [],
    expandedItems: openArray[string] = [],
    selectedRowIdentifiers: openArray[string] = [],
): TableViewState =
  TableViewState(
    columns: @columns,
    selectedRows: @selectedRows,
    selectedRowIdentifiers: @selectedRowIdentifiers,
    selectedColumns: @selectedColumns,
    expandedItems: @expandedItems,
  )

proc newTableViewStateStore*(): TableViewStateStore

proc tableViewStateScopeKey(kind, identifier: string): string =
  if identifier.len == 0:
    kind
  elif identifier.startsWith(kind & ":"):
    identifier
  else:
    kind & ":" & identifier

proc tableViewStateStoreForDefaults*(
    defaults: UserDefaults, identifier: string
): TableViewStateStore =
  let resolvedDefaults =
    if defaults.isNil:
      sharedUserDefaults()
    else:
      defaults
  let key =
    if identifier.len == 0:
      TableViewStateDefaultsPrefix & "application"
    else:
      TableViewStateDefaultsPrefix & identifier
  let existing = resolvedDefaults.objectForKey(key)
  if existing.isSome and existing.get() of TableViewStateStore:
    return TableViewStateStore(existing.get())
  result = newTableViewStateStore()
  resolvedDefaults.setObjectForKey(key, DynamicAgent(result))

proc userDefaultsTableViewStateStore*(): TableViewStateStore =
  tableViewStateStoreForDefaults(sharedUserDefaults(), "")

proc workspaceTableViewStateStore*(identifier: string): TableViewStateStore =
  if identifier.len == 0:
    return userDefaultsTableViewStateStore()
  tableViewStateStoreForDefaults(
    sharedUserDefaults(), tableViewStateScopeKey("workspace", identifier)
  )

proc documentTableViewStateStore*(identifier: string): TableViewStateStore =
  if identifier.len == 0:
    return userDefaultsTableViewStateStore()
  tableViewStateStoreForDefaults(
    sharedUserDefaults(), tableViewStateScopeKey("document", identifier)
  )

proc stateProviderForTableView(tableView: TableView): Responder =
  var responder: Responder =
    if tableView.isNil:
      nil
    else:
      Responder(tableView)
  while not responder.isNil:
    if responder.trySendLocal(defaultsStore(), ()).isSome or
        responder.trySendLocal(defaultsScopeId(), ()).isSome:
      return responder
    responder = responder.nextResponder()

proc stateStorageFromProvider(provider: Responder): DynamicAgent =
  if provider.isNil:
    return nil
  let
    storage = provider.trySendLocal(defaultsStore(), ())
    identifier = provider.trySendLocal(defaultsScopeId(), ())
    scopeId =
      if identifier.isSome:
        identifier.get()
      else:
        ""
  if storage.isSome:
    let store = storage.get()
    if store of TableViewStateStore:
      return store
    if store of UserDefaults:
      return DynamicAgent(
        tableViewStateStoreForDefaults(
          UserDefaults(store), tableViewStateScopeKey("document", scopeId)
        )
      )
  if scopeId.len > 0:
    return DynamicAgent(documentTableViewStateStore(scopeId))

proc resolveTableViewStateStorage(tableView: TableView): DynamicAgent =
  if tableView.isNil:
    return nil
  if not tableView.xStateStorage.isNil:
    return tableView.xStateStorage
  case tableView.xStateScope
  of tvssApplication:
    DynamicAgent(userDefaultsTableViewStateStore())
  of tvssWorkspace:
    DynamicAgent(workspaceTableViewStateStore(tableView.xWorkspaceIdentifier))
  of tvssDocument:
    let storage = stateStorageFromProvider(tableView.stateProviderForTableView())
    if storage.isNil:
      DynamicAgent(userDefaultsTableViewStateStore())
    else:
      storage
  of tvssAutomatic:
    if tableView.xWorkspaceIdentifier.len > 0:
      DynamicAgent(workspaceTableViewStateStore(tableView.xWorkspaceIdentifier))
    else:
      let storage = stateStorageFromProvider(tableView.stateProviderForTableView())
      if storage.isNil:
        DynamicAgent(userDefaultsTableViewStateStore())
      else:
        storage

proc saveState*(tableView: TableView, storage: DynamicAgent) =
  if tableView.isNil or storage.isNil or tableView.autosaveName().len == 0:
    return
  discard storage.sendLocalIfHandled(
    saveTableViewState(),
    (name: tableView.autosaveName(), state: tableView.captureState()),
  )

proc restoreState*(tableView: TableView, storage: DynamicAgent) =
  if tableView.isNil or storage.isNil or tableView.autosaveName().len == 0:
    return
  let name = tableView.autosaveName()
  let hasState = storage.trySendLocal(hasTableViewState(), name)
  if hasState.isSome and not hasState.get():
    return
  let state = storage.trySendLocal(loadTableViewState(), name)
  if state.isSome:
    tableView.restoreState(state.get())

proc saveAutosavedState*(tableView: TableView) =
  tableView.saveState(tableView.resolveTableViewStateStorage())

proc restoreAutosavedState*(tableView: TableView) =
  tableView.restoreState(tableView.resolveTableViewStateStorage())

proc restoreStateIfNeeded(tableView: TableView) =
  if tableView.isNil or tableView.xHasRestoredState:
    return
  tableView.restoreAutosavedState()
  tableView.xHasRestoredState = true

protocol TableViewStateStoreBehavior of TableViewStateStorageProtocol:
  method saveTableViewState(
      store: TableViewStateStore, name: string, state: TableViewState
  ) =
    if store.isNil or name.len == 0:
      return
    store.xStates[name] = state

  method loadTableViewState(store: TableViewStateStore, name: string): TableViewState =
    if name.len == 0:
      return initTableViewState()
    store.xStates.getOrDefault(name, initTableViewState())

  method hasTableViewState(store: TableViewStateStore, name: string): bool =
    name in store.xStates

proc newTableViewStateStore*(): TableViewStateStore =
  result = TableViewStateStore()
  result.xStates = initTable[string, TableViewState]()
  discard result.withProtocol(TableViewStateStoreBehavior)

proc hasState*(store: TableViewStateStore, name: string): bool =
  not store.isNil and name in store.xStates

proc state*(store: TableViewStateStore, name: string): TableViewState =
  if store.isNil:
    return initTableViewState()
  store.xStates.getOrDefault(name, initTableViewState())

proc tableContentItemRect*(contentView: TableContentView, itemIndex: int): Rect =
  let tableView = contentView.tableView()
  if contentView.isNil or tableView.isNil or itemIndex notin 0 ..< tableView.len():
    return rect(0.0, 0.0, 0.0, 0.0)
  rect(
    0.0'f32,
    tableView.rowOffset(itemIndex),
    max(contentView.bounds().size.width, 0.0'f32),
    tableView.rowHeightForRow(itemIndex),
  )

proc tableContentItemIndexAtPoint*(contentView: TableContentView, point: Point): int =
  let tableView = contentView.tableView()
  if contentView.isNil or tableView.isNil or not contentView.bounds().contains(point):
    return -1
  let index = tableView.rowIndexAtContentY(point.y)
  if index < 0 or index >= tableView.len():
    return -1
  index

proc visibleContentRows(contentView: TableContentView): tuple[first, last: int] =
  let tableView = contentView.tableView()
  if contentView.isNil or tableView.isNil or tableView.len() <= 0:
    return (0, 0)
  let visible = contentView.visibleRect()
  if visible.isEmpty:
    return (0, 0)
  result.first = max(tableView.rowIndexAtContentY(visible.minY), 0)
  result.last = result.first
  while result.last < tableView.len() and tableView.rowOffset(result.last) < visible.maxY:
    inc result.last
  if result.last < result.first:
    result.last = result.first

proc configureRowView(rowView: TableRowView, itemIndex: int) =
  let tableView = rowView.xTableView
  if rowView.isNil or tableView.isNil or tableView.xContentView.isNil:
    return
  rowView.xRow = tableView.tableRowState(itemIndex)
  rowView.frame = tableView.xContentView.tableContentItemRect(itemIndex)

proc removeLastRowView(contentView: TableContentView) =
  if contentView.isNil or contentView.xRowViews.len == 0:
    return
  let rowView = contentView.xRowViews[^1]
  contentView.xRowViews.setLen(contentView.xRowViews.len - 1)
  rowView.removeFromSuperview()

proc syncVisibleRowViews(contentView: TableContentView) =
  if contentView.isNil:
    return
  let
    tableView = contentView.tableView()
    rows = contentView.visibleContentRows()
    needed = max(rows.last - rows.first, 0)
  if tableView.isNil:
    return
  while contentView.xRowViews.len < needed:
    let rowView = initTableRowView(tableView)
    contentView.xRowViews.add rowView
    contentView.addSubview(rowView)
  while contentView.xRowViews.len > needed:
    contentView.removeLastRowView()
  for slot in 0 ..< needed:
    contentView.xRowViews[slot].configureRowView(rows.first + slot)

proc drawTableRowItem*(
    tableView: TableView, context: DrawContext, rect: Rect, row: RowState
) =
  if tableView.isNil or context.isNil:
    return
  var style = initRowStyle()
  let interactiveFillStates =
    row.states * {ssSelected, ssHovered, ssHighlighted, ssPressed}
  if ssDisabled notin row.states and ssAlternating in row.states and
      interactiveFillStates == {} and style.fill.isNone:
    style.fill = some(
      context.appearance.resolveFill(
        controlStyle(
          tableView.xItemRole,
          row.states,
          id = tableView.styleId(),
          classes = tableView.styleClasses(),
        ),
        fill(color(0.96, 0.97, 0.99, 1.0)),
        StyleAlternatingFill,
      )
    )
  context.drawRowItem(
    rect, row, style, tableView.xItemRole, tableView.styleId(), tableView.styleClasses()
  )
  if tableView.showsRowSeparators() and row.index >= 0 and
      row.index < tableView.len() - 1:
    let
      separatorStates: set[WidgetState] = row.states * {ssDisabled}
      itemStyle = context.appearance.resolveRowItemStyle(
        controlStyle(
          tableView.xItemRole,
          separatorStates,
          id = tableView.styleId(),
          classes = tableView.styleClasses(),
        )
      )
      separatorRect = rect(rect.origin.x, rect.maxY - 1.0'f32, rect.size.width, 1.0)
    discard context.addRenderRectangle(separatorRect, fill(itemStyle.box.borderColor))

proc drawCustomTableRow(
    tableView: TableView, context: DrawContext, rect: Rect, row: RowState
): bool =
  if tableView.isNil or tableView.xTableDelegate.isNil or context.isNil:
    return false
  tableView.xTableDelegate.sendLocalIfHandled(
    drawRow(), (tableView: tableView, context: context, rect: rect, row: row)
  )

proc naturalSize(tableView: TableView): Size =
  let
    appearance = tableView.effectiveAppearance()
    listState = tableView.widgetStateSet()
    itemState = tableView.widgetStateSet()
    listStyle = appearance.resolveTableViewStyle(
      controlStyle(
        tableView.xTableRole,
        listState,
        id = tableView.styleId(),
        classes = tableView.styleClasses(),
      )
    )
    itemStyle = appearance.resolveRowItemStyle(
      controlStyle(
        tableView.xItemRole,
        itemState,
        id = tableView.styleId(),
        classes = tableView.styleClasses(),
      )
    )
    rowCount =
      if tableView.len() == 0:
        max(tableView.visibleRows(), 1)
      else:
        visibleRowItemCount(tableView.len(), tableView.visibleRows())

  var
    maxTextWidth = 0.0'f32
    naturalHeight = 0.0'f32
  let summaryTextStyle =
    tableView.effectiveAppearance().resolveRowItemStyle(controlStyle(srRowItem)).text
  for index in 0 ..< tableView.len():
    maxTextWidth = max(
      maxTextWidth,
      textNaturalSize(tableView.rowTextForSummary(index), summaryTextStyle).width,
    )
    if index < rowCount:
      naturalHeight += tableView.rowHeightForRow(index)
  if tableView.len() == 0:
    naturalHeight = tableView.rowHeight() * rowCount.float32

  initSize(
    max(
      listStyle.minSize.width,
      max(
        itemStyle.minSize.width,
        max(tableView.visibleColumnWidth(), maxTextWidth) +
          itemStyle.text.insets.horizontal + 2.0'f32,
      ),
    ),
    max(
      listStyle.minSize.height, naturalHeight + tableView.tableHeaderHeight() + 2.0'f32
    ),
  )

protocol DefaultTableRowViewDrawing of ViewDrawingProtocol:
  method draw(rowView: TableRowView, context: DrawContext) =
    let tableView = rowView.xTableView
    if rowView.isNil or tableView.isNil:
      return
    let rect = rowView.bounds()
    if not tableView.drawCustomTableRow(context, rect, rowView.xRow):
      tableView.drawTableRow(context, rect, rowView.xRow)

protocol DefaultTableRowViewHitTesting of ViewProtocol:
  method pointInside(rowView: TableRowView, point: Point): bool =
    false

protocol DefaultTableRowViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(rowView: TableRowView): AccessibilityRole =
    arListItem

  method accessibilityLabel(rowView: TableRowView): string =
    if rowView.isNil: "" else: rowView.xRow.text

  method accessibilityValue(rowView: TableRowView): string =
    if rowView.isNil:
      ""
    else:
      $rowView.xRow.index

  method accessibilityTraits(rowView: TableRowView): AccessibilityTraits =
    if rowView.isNil:
      return
    if ssDisabled in rowView.xRow.states:
      result.incl atDisabled
    if ssFocused in rowView.xRow.states:
      result.incl atFocused
    if ssSelected in rowView.xRow.states:
      result.incl atSelected
    if not rowView.xTableView.isNil and rowView.xTableView.selectionMode() != tsmNone:
      result.incl atSelectable

  method isAccessibilityElement(rowView: TableRowView): bool =
    not rowView.isNil and rowView.xRow.index >= 0

protocol DefaultTableContentViewDrawing of ViewDrawingProtocol:
  method draw(contentView: TableContentView, context: DrawContext) =
    contentView.syncVisibleRowViews()
    let tableView = contentView.tableView()
    if not tableView.isNil:
      tableView.syncVisibleTableCells()

protocol DefaultTableContentViewHitTesting of ViewProtocol:
  method pointInside(contentView: TableContentView, point: Point): bool =
    contentView.bounds().contains(point)

protocol DefaultTableViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(tableView: TableView): IntrinsicSize =
    initIntrinsicSize(tableView.naturalSize())

  method layoutSubviews(tableView: TableView) =
    tableView.tileTableContent()

func hasExceededDragThreshold(startPoint, location: Point, threshold: float32): bool =
  max(abs(location.x - startPoint.x), abs(location.y - startPoint.y)) >= threshold

proc clearRowDragState(tableView: TableView) =
  if tableView.isNil:
    return
  tableView.xRowDragStartIndex = -1
  tableView.xRowDragStartPoint = initPoint(0.0, 0.0)

proc rowReorderDragRows(tableView: TableView): seq[int] =
  if tableView.isNil or tableView.xRowDragStartIndex < 0:
    return
  if tableView.selectionMode() != tsmNone and
      tableView.selectionContains(tableView.xRowDragStartIndex):
    tableView.selectedIndexes()
  else:
    @[tableView.xRowDragStartIndex]

proc shouldBeginRowReorderDrag(tableView: TableView, event: MouseEvent): bool =
  if tableView.isNil or not tableView.isEnabled() or event.button != mbPrimary:
    return false
  if not tableView.allowsRowReordering() or not tableView.xTrackingItem:
    return false
  if tableView.xRowDragStartIndex < 0 or
      not tableView.rowEnabled(tableView.xRowDragStartIndex):
    return false
  if tableView.selectionMode() != tsmNone and
      not tableView.rowSelectable(tableView.xRowDragStartIndex):
    return false
  tableView.xRowDragStartPoint.hasExceededDragThreshold(
    event.location, tableView.tableStyle().headerDragThreshold
  )

proc tryBeginRowReorderDrag(tableView: TableView, event: MouseEvent): bool =
  if tableView.isNil or not tableView.shouldBeginRowReorderDrag(event):
    return false
  if tableView.selectionMode() != tsmNone and
      not tableView.selectionContains(tableView.xRowDragStartIndex):
    tableView.selectItemAtIndex(tableView.xRowDragStartIndex)

  let rows = tableView.normalizedReorderRows(tableView.rowReorderDragRows())
  if rows.len == 0:
    return false

  let session = tableView.beginDraggingRows(rows, {dgoMove}, DragPasteboardName)
  if session.isNil:
    return false

  let target = tableView.dropTargetForDraggingLocation(event.location)
  tableView.xTrackingItem = false
  tableView.highlightedIndex = -1
  tableView.xPressedIndex = -1
  tableView.updateTableDropTarget(target)
  discard
    updateDraggingSession(session, event.location, DynamicAgent(tableView), target)
  discard
    autoscrollDraggingSession(session, event.location, DynamicAgent(tableView), target)
  true

proc updateActiveTableDrag(tableView: TableView, event: MouseEvent): bool =
  if tableView.isNil:
    return false
  let session = tableView.draggingSession()
  if session.isNil or session.state() != dssActive:
    return false
  let target = tableView.dropTargetForDraggingLocation(event.location)
  tableView.updateTableDropTarget(target)
  discard
    updateDraggingSession(session, event.location, DynamicAgent(tableView), target)
  discard
    autoscrollDraggingSession(session, event.location, DynamicAgent(tableView), target)
  true

proc performActiveTableDrag(tableView: TableView, event: MouseEvent): bool =
  if tableView.isNil:
    return false
  let session = tableView.draggingSession()
  if session.isNil or session.state() != dssActive:
    return false

  let target = tableView.dropTargetForDraggingLocation(event.location)
  tableView.updateTableDropTarget(target)
  discard
    updateDraggingSession(session, event.location, DynamicAgent(tableView), target)
  let performed =
    performDraggingOperation(session, DynamicAgent(tableView), event.location, target)
  if performed:
    session.endDraggingSession(session.selectedOperations())
  else:
    session.cancelDraggingSession()
  tableView.xTrackingItem = false
  tableView.xPressedIndex = -1
  tableView.clearRowDragState()
  true

proc defaultTableViewMouseDown*(tableView: TableView, event: MouseEvent): bool =
  if tableView.isNil or not tableView.isEnabled() or event.button != mbPrimary:
    return false
  let owner = tableView.window()
  if owner of Window:
    discard Window(owner).makeFirstResponder(tableView)
  tableView.xTrackingItem = true
  let index = tableView.rowItemIndexAtPoint(event.location)
  tableView.highlightedIndex = index
  tableView.xPressedIndex = tableView.highlightedIndex()
  tableView.xRowDragStartIndex = index
  tableView.xRowDragStartPoint = event.location
  tableView.invalidateTableRows()
  true

proc defaultTableViewMouseDragged*(tableView: TableView, event: MouseEvent): bool =
  if tableView.isNil:
    return false
  if tableView.tryBeginRowReorderDrag(event):
    return true
  if tableView.isEnabled() and tableView.xTrackingItem:
    let index = tableView.rowItemIndexAtPoint(event.location)
    tableView.highlightedIndex = index
    tableView.xPressedIndex = tableView.highlightedIndex()
    tableView.invalidateTableRows()
    return true
  false

proc defaultTableViewMouseUp*(tableView: TableView, event: MouseEvent): bool =
  if tableView.isNil or not tableView.isEnabled() or event.button != mbPrimary:
    return false
  let index =
    if tableView.xTrackingItem:
      tableView.rowItemIndexAtPoint(event.location)
    else:
      -1
  tableView.xTrackingItem = false
  tableView.xPressedIndex = -1
  tableView.clearRowDragState()
  if index >= 0:
    tableView.activateItemAtIndex(index, event.modifiers)
  tableView.setNeedsDisplay(true)
  true

proc defaultTableViewKeyDown*(tableView: TableView, event: KeyEvent): bool =
  if tableView.isNil or not tableView.isEnabled():
    return false
  result = true
  let extendSelection = kmShift in event.modifiers
  case event.key
  of keyArrowDown:
    tableView.moveSelection(1, extendSelection)
  of keyArrowUp:
    tableView.moveSelection(-1, extendSelection)
  of keyPageDown:
    tableView.pageSelection(1, extendSelection)
  of keyPageUp:
    tableView.pageSelection(-1, extendSelection)
  of keyHome:
    tableView.moveSelectionTo(tableView.firstSelectableIndex(), extendSelection)
  of keyEnd:
    tableView.moveSelectionTo(tableView.lastSelectableIndex(), extendSelection, -1)
  of keyEnter, keySpace:
    let activeIndex = tableView.selectionLeadIndex()
    if activeIndex >= 0:
      tableView.sendTableActivation(activeIndex)
  else:
    result = tableView.handleTypeSelect(event) or event.text.len > 0

protocol DefaultTableViewMouseHitPolicy of MouseHitPolicyProtocol:
  method mouseHitPolicy(tableView: TableView, args: MouseHitPolicyArgs): CellHitPolicy =
    if tableView.isNil or not tableView.isEnabled() or args.event.button != mbPrimary:
      return chpDefault
    let row = tableView.rowItemIndexAtPoint(args.event.location)
    if row < 0:
      return chpDefault
    let
      target =
        if args.target of View:
          View(args.target)
        else:
          nil
      column = tableView.tableColumnAtPoint(args.event.location)
    tableView.tableCellHitPolicy(row, column, target, args.event)

  method applyMouseHitPolicy(tableView: TableView, args: MouseHitPolicyArgs): bool =
    if tableView.isNil or not tableView.isEnabled() or args.event.button != mbPrimary:
      return false
    let
      row = tableView.rowItemIndexAtPoint(args.event.location)
      column = tableView.tableColumnAtPoint(args.event.location)
    if row < 0:
      return false
    let owner = tableView.window()
    if owner of Window:
      discard Window(owner).makeFirstResponder(tableView, focusVisible = false)
    tableView.selectCell(row, column)
    tableView.highlightedIndex = row
    tableView.xPressedIndex = row
    tableView.invalidateTableRows()
    true

proc initTableRowView(tableView: TableView): TableRowView =
  result = TableRowView()
  initTableBaseChild(result, false)
  result.xTableView = tableView
  discard result.withProtocol(DefaultTableRowViewDrawing)
  discard result.withProtocol(DefaultTableRowViewHitTesting)
  discard result.withProtocol(DefaultTableRowViewAccessibility)

proc initTableContentView(tableView: TableView): TableContentView =
  result = TableContentView()
  initTableBaseChild(result, false)
  result.xTableView = tableView
  discard result.withProtocol(DefaultTableContentViewDrawing)
  discard result.withProtocol(DefaultTableContentViewHitTesting)

proc initTableScrollView(tableView: TableView): ScrollView =
  result = ScrollView()
  initScrollViewFields(result)
  result.background = color(0.0, 0.0, 0.0, 0.0)
  result.drawsBackground = false
  result.clipsToBounds = true
  result.hasHorizontalScroller = true
  result.hasVerticalScroller = true
  result.autohidesScrollers = true
  result.scrollerThickness = 12.0'f32
  result.lineScroll = tableView.rowHeight()
  result.setAcceptsFirstResponder(false)
  result.autoresizingMaskConstraints = false

proc drawTableHeaderSortIndicator*(
    tableView: TableView,
    context: DrawContext,
    rect: Rect,
    direction: TableSortDirection,
    chrome: TableHeaderChrome,
) =
  if direction == tsdNone or context.isNil:
    return
  discard tableView
  let
    indicatorWidth = max(chrome.sortIndicatorWidth, 18.0'f32)
    centerX = rect.maxX - indicatorWidth * 0.5'f32 - 4.0'f32
    centerY = rect.origin.y + rect.size.height * 0.5'f32
    halfWidth = 5.0'f32
    halfHeight = 3.5'f32
    lineWeight = 1.8'f32

  let
    apexY =
      if direction == tsdAscending:
        centerY - halfHeight
      else:
        centerY + halfHeight
    baseY =
      if direction == tsdAscending:
        centerY + halfHeight
      else:
        centerY - halfHeight
    apex = initPoint(centerX, apexY)
    leftBase = initPoint(centerX - halfWidth, baseY)
    rightBase = initPoint(centerX + halfWidth, baseY)
    indicatorFill = fill(chrome.sortIndicatorColor)

  discard context.addRenderLine(leftBase, apex, indicatorFill, lineWeight)
  discard context.addRenderLine(apex, rightBase, indicatorFill, lineWeight)

proc drawTableHeaderResizeHandle*(
    tableView: TableView,
    context: DrawContext,
    column: TableColumn,
    rect: Rect,
    chrome: TableHeaderChrome,
) =
  if tableView.isNil or context.isNil or column.isNil or rect.isEmpty:
    return
  if column.resizePolicy() != tcrResizable:
    return
  let
    handleHeight = max(rect.size.height - 8.0'f32, 0.0'f32)
    handleY = rect.origin.y + (rect.size.height - handleHeight) * 0.5'f32
    handleColor = color(
      chrome.cellBorderColor.r,
      chrome.cellBorderColor.g,
      chrome.cellBorderColor.b,
      min(chrome.cellBorderColor.a, 0.72'f32),
    )
    softHandleColor = color(
      chrome.cellBorderColor.r,
      chrome.cellBorderColor.g,
      chrome.cellBorderColor.b,
      min(chrome.cellBorderColor.a, 0.32'f32),
    )
  if handleHeight <= 0.0'f32:
    return
  discard context.addRenderRectangle(
    context.renderRectFor(rect(rect.maxX - 1.0'f32, handleY, 1.0, handleHeight)),
    fill(handleColor),
  )
  discard context.addRenderRectangle(
    context.renderRectFor(
      rect(
        rect.maxX - 3.0'f32,
        handleY + 2.0'f32,
        1.0,
        max(handleHeight - 4.0'f32, 0.0'f32),
      )
    ),
    fill(softHandleColor),
  )

proc drawTableHeaderInsertionIndicator*(
    tableView: TableView, context: DrawContext, chrome: TableHeaderChrome
) =
  if tableView.isNil or context.isNil:
    return
  let indicator = tableView.headerDragIndicator()
  if not indicator.visible:
    return
  let
    rect = indicator.rect
    insertionRect =
      rect(rect.origin.x, rect.origin.y, chrome.insertionWidth, rect.size.height)
  discard context.addRenderRectangle(
    context.renderRectFor(insertionRect),
    chrome.insertionIndicatorFill,
    cornerRadius = chrome.cornerRadius,
  )
  discard context.addRenderRectangle(
    context.renderRectFor(
      rect(
        rect.origin.x - (chrome.insertionCapWidth - chrome.insertionWidth) * 0.5'f32,
        rect.origin.y,
        chrome.insertionCapWidth,
        chrome.insertionCapHeight,
      )
    ),
    chrome.insertionIndicatorFill,
    cornerRadius = chrome.cornerRadius,
  )
  discard context.addRenderRectangle(
    context.renderRectFor(
      rect(
        rect.origin.x - (chrome.insertionCapWidth - chrome.insertionWidth) * 0.5'f32,
        rect.maxY - chrome.insertionCapHeight,
        chrome.insertionCapWidth,
        chrome.insertionCapHeight,
      )
    ),
    chrome.insertionIndicatorFill,
    cornerRadius = chrome.cornerRadius,
  )

proc drawTableHeaderBackground*(
    tableView: TableView, context: DrawContext, rect: Rect, chrome: TableHeaderChrome
) =
  if tableView.isNil or context.isNil or rect.isEmpty:
    return
  discard context.addRenderRectangle(
    context.renderRectFor(rect),
    chrome.headerFill,
    chrome.headerBorderColor,
    chrome.borderWidth,
    cornerRadius = chrome.cornerRadius,
    cornerRadii = chrome.tableHeaderCornerRadii(),
  )

proc drawTableHeaderCellChrome*(
    tableView: TableView,
    context: DrawContext,
    column: TableColumn,
    rect: Rect,
    chrome: TableHeaderChrome,
    firstVisible = false,
    lastVisible = false,
) =
  if tableView.isNil or context.isNil or column.isNil or rect.isEmpty:
    return
  var background = chrome.cellFill
  if column == tableView.xPressedColumn:
    background = chrome.pressedCellFill
  elif column == tableView.xHoveredColumn:
    background = chrome.hoveredCellFill
  discard context.addRenderRectangle(
    context.renderRectFor(rect),
    background,
    chrome.cellBorderColor,
    chrome.borderWidth,
    cornerRadius = chrome.cornerRadius,
    cornerRadii = chrome.tableHeaderCellCornerRadii(firstVisible, lastVisible),
  )

proc drawTableHeaderCellTitle*(
    tableView: TableView,
    context: DrawContext,
    column: TableColumn,
    rect: Rect,
    chrome: TableHeaderChrome,
) =
  if tableView.isNil or context.isNil or column.isNil or rect.isEmpty:
    return
  let indicatorWidth =
    if column.sortDirection() == tsdNone: 0.0'f32 else: chrome.sortIndicatorWidth
  let titleRect = rect(
    rect.origin.x + 8.0'f32,
    rect.origin.y,
    max(rect.size.width - 16.0'f32 - indicatorWidth, 0.0'f32),
    rect.size.height,
  )
  context.addText(
    titleRect,
    clippedText(
      column.title(),
      titleRect.size.width,
      context.appearance.resolveTextStyle(
        controlStyle(srTableHeaderCell), chrome.textColor, insets(0.0)
      ),
    ),
    context.appearance.resolveTextStyle(
      controlStyle(srTableHeaderCell), chrome.textColor, insets(0.0)
    ),
    column.alignment(),
  )

proc drawTableHeader*(
    tableView: TableView, context: DrawContext, chrome: TableHeaderChrome
) =
  if tableView.isNil or context.isNil or not tableView.showsHeader():
    return
  let headerRect = tableView.tableHeaderRect()
  if headerRect.isEmpty:
    return
  tableView.drawTableHeaderBackground(context, headerRect, chrome)
  let visibleColumns = tableView.visibleTableColumns()
  for index, column in visibleColumns:
    let rect = tableView.tableHeaderColumnRect(column)
    if rect.isEmpty:
      continue
    tableView.drawTableHeaderCellChrome(
      context, column, rect, chrome, index == 0, index == visibleColumns.high
    )
    tableView.drawTableHeaderCellTitle(context, column, rect, chrome)
    tableView.drawTableHeaderSortIndicator(
      context, rect, column.sortDirection(), chrome
    )
    tableView.drawTableHeaderResizeHandle(context, column, rect, chrome)
  tableView.drawTableHeaderInsertionIndicator(context, chrome)

proc drawTableHeader*(tableView: TableView, context: DrawContext) =
  tableView.drawTableHeader(context, tableView.tableHeaderChrome(context))

protocol DefaultTableViewColumnBehavior of TableViewColumnProtocol:
  method columnAtPoint(tableView: TableView, point: Point): TableColumn =
    if tableView.isNil:
      return nil
    var x = 0.0'f32
    for column in tableView.columns:
      if column.hidden():
        continue
      let nextX = x + column.width()
      if point.x >= x and point.x < nextX:
        return column
      x = nextX

  method headerHitTest(tableView: TableView, point: Point): TableHeaderHit =
    result = TableHeaderHit(columnIndex: -1, part: thpNone)
    if tableView.isNil or not tableView.tableHeaderRect().contains(point):
      return
    let resizeHandleWidth = tableView.tableStyle().headerResizeHandleWidth
    for index, column in tableView.xColumns:
      let rect = tableView.tableHeaderColumnRect(column)
      if rect.isEmpty or column.resizePolicy() != tcrResizable:
        continue
      let handleRect = rect(
        rect.maxX - resizeHandleWidth,
        rect.origin.y,
        resizeHandleWidth * 2.0'f32,
        rect.size.height,
      )
      if handleRect.contains(point):
        result.column = column
        result.columnIndex = index
        result.part = thpResizeHandle
        result.rect = rect
        return
    for index, column in tableView.xColumns:
      let rect = tableView.tableHeaderColumnRect(column)
      if rect.contains(point):
        result.column = column
        result.columnIndex = index
        result.rect = rect
        result.part = thpColumn
        return

  method resizeColumn(tableView: TableView, column: TableColumn, width: float32) =
    if tableView.isNil or column.isNil or column.tableView() != tableView:
      return
    if column.resizePolicy() == tcrFixed:
      return
    column.width = width
    if tableView.xEditing.active and tableView.xEditing.column == column:
      tableView.clearEditingSurface()
      let editor = Control(tableView).currentEditor()
      if not editor.isNil:
        tableView.installFieldEditorOnSurface(editor)
    tableView.syncHeaderTrackingAreas()
    tableView.setNeedsLayout()
    tableView.setNeedsDisplay(true)

  method moveColumn(tableView: TableView, fromIndex, toIndex: int) =
    if tableView.isNil or fromIndex notin 0 ..< tableView.xColumns.len:
      return
    let boundedTo = max(0, min(toIndex, tableView.xColumns.len - 1))
    if fromIndex == boundedTo:
      return
    let column = tableView.xColumns[fromIndex]
    tableView.findUndoManager().registerCollectionMove(
      proc(fromIndex, toIndex: int) =
        tableView.moveColumn(fromIndex, toIndex),
      fromIndex,
      boundedTo,
      "Move Column",
    )
    tableView.xColumns.delete(fromIndex)
    tableView.xColumns.insert(column, boundedTo)
    tableView.noteColumnsChanged()

  method requestSort(
      tableView: TableView, column: TableColumn, direction: TableSortDirection
  ) =
    if tableView.isNil or column.isNil or column.tableView() != tableView:
      return
    let
      selectedIdentifiers = tableView.rowIdentifiersForRows(tableView.xSelectedIndexes)
      anchorIdentifier = tableView.tableRowIdentifier(tableView.xSelectionAnchor)
      leadIdentifier = tableView.tableRowIdentifier(tableView.xSelectionLead)
    for current in tableView.xColumns.mitems:
      if current != column and current.xSortDirection != tsdNone:
        current.xSortDirection = tsdNone
    column.sortDirection = direction
    let delegate = tableView.delegate()
    if not delegate.isNil:
      discard delegate.sendLocalIfHandled(
        sortDescriptorsDidChange(),
        (tableView: tableView, column: column, direction: direction),
      )
    tableView.applySelectionForRowIdentifiers(
      selectedIdentifiers, anchorIdentifier, leadIdentifier
    )

  method headerMouseDown(tableView: TableView, event: MouseEvent): bool =
    if tableView.isNil or event.button != mbPrimary:
      return false
    let hit = tableView.tableHeaderHitTest(event.location)
    if hit.part == thpNone or hit.column.isNil:
      return false
    tableView.xHeaderTrackingPart = hit.part
    tableView.xTrackingColumn = hit.column
    tableView.xTrackingColumnIndex = hit.columnIndex
    tableView.xPressedColumn = hit.column
    tableView.xHeaderDraggingColumn = false
    tableView.clearHeaderDragInsertion()
    tableView.xDragStartPoint = event.location
    tableView.xDragStartWidth = hit.column.width()
    tableView.setNeedsDisplay(true)
    true

  method headerMouseDragged(tableView: TableView, event: MouseEvent): bool =
    if tableView.isNil or tableView.xTrackingColumn.isNil:
      return false
    case tableView.xHeaderTrackingPart
    of thpResizeHandle:
      tableView.resizeColumn(
        tableView.xTrackingColumn,
        tableView.xDragStartWidth + event.location.x - tableView.xDragStartPoint.x,
      )
    of thpColumn:
      if abs(event.location.x - tableView.xDragStartPoint.x) >
          tableView.tableStyle().headerDragThreshold:
        tableView.xHeaderDraggingColumn = true
      if tableView.xHeaderDraggingColumn:
        if not tableView.autoscrollHeaderColumnDrag(event.location):
          tableView.setHeaderDragInsertion(
            tableView.headerInsertionIndexAtPoint(event.location)
          )
        tableView.setNeedsDisplay(true)
    of thpNone:
      discard
    true

  method headerMouseUp(tableView: TableView, event: MouseEvent): bool =
    if tableView.isNil or tableView.xTrackingColumn.isNil:
      return false
    let
      hit = tableView.tableHeaderHitTest(event.location)
      clickedColumn = tableView.xTrackingColumn
      clickedPart = tableView.xHeaderTrackingPart
      fromIndex = tableView.xTrackingColumnIndex
      moved =
        tableView.xHeaderDraggingColumn or
        abs(event.location.x - tableView.xDragStartPoint.x) >
        tableView.tableStyle().headerDragThreshold
      insertionIndex = tableView.xHeaderDragInsertionIndex
    tableView.xHeaderTrackingPart = thpNone
    tableView.xTrackingColumn = nil
    tableView.xTrackingColumnIndex = -1
    tableView.xHeaderDraggingColumn = false
    tableView.xPressedColumn = nil
    tableView.clearHeaderDragInsertion()
    if clickedPart == thpColumn:
      if moved:
        let targetIndex =
          if insertionIndex < 0:
            tableView.headerInsertionIndexAtPoint(event.location)
          else:
            insertionIndex
        if targetIndex >= 0:
          var toIndex = targetIndex
          if fromIndex < targetIndex:
            dec toIndex
          toIndex = max(0, min(toIndex, tableView.xColumns.len - 1))
          tableView.moveColumn(fromIndex, toIndex)
      elif hit.column == clickedColumn:
        let nextDirection =
          if clickedColumn.sortDirection() == tsdAscending:
            tsdDescending
          else:
            tsdAscending
        tableView.requestSort(clickedColumn, nextDirection)
    tableView.setNeedsDisplay(true)
    true

  method headerMouseMoved(tableView: TableView, event: MouseEvent): bool =
    if tableView.isNil:
      return false
    let column = tableView.tableHeaderHitTest(event.location).column
    if tableView.xHoveredColumn == column:
      return column != nil
    tableView.xHoveredColumn = column
    tableView.setNeedsDisplay(true)
    column != nil

protocol DefaultTableViewSelectionBehavior of TableViewSelectionProtocol:
  method shouldSelectCell(tableView: TableView, row: int, column: TableColumn): bool =
    tableView.validCell(row, column)

  method selectCell(tableView: TableView, row: int, column: TableColumn) =
    if not tableView.shouldSelectCell(row, column):
      return
    let previousSelectedIndexes = tableView.xSelectedIndexes
    let previousSelectedColumns = tableView.xSelectedColumns
    if tableView.xAllowsColumnSelection:
      tableView.xSelectedColumns = @[column]
    tableView.selectedIndex = row
    tableView.xClickedRow = row
    tableView.xClickedColumn = column
    tableView.setNeedsDisplay(true)
    if tableView.xAllowsColumnSelection and
        previousSelectedColumns != tableView.xSelectedColumns and
        previousSelectedIndexes == tableView.xSelectedIndexes:
      emit tableView.selectionDidChange(DynamicAgent(tableView))
      tableView.postAccessibilityNotification(anSelectionChanged)

  method setSelectedColumns(tableView: TableView, columns: seq[TableColumn]) =
    if tableView.isNil or not tableView.xAllowsColumnSelection:
      return
    var next: seq[TableColumn]
    for column in columns:
      if column.isNil or column.tableView() != tableView:
        continue
      var seen = false
      for existing in next:
        if existing == column:
          seen = true
      if not seen:
        next.add column
    if tableView.xSelectedColumns == next:
      return
    tableView.xSelectedColumns = next
    tableView.setNeedsDisplay(true)
    emit tableView.selectionDidChange(DynamicAgent(tableView))
    tableView.postAccessibilityNotification(anSelectionChanged)

  method selectionPersistenceString(tableView: TableView): string =
    let selectedIdentifiers =
      tableView.rowIdentifiersForRows(tableView.selectedIndexes())
    if selectedIdentifiers.len > 0:
      return TableSelectionIdentityPrefix & joinIdentifiers(selectedIdentifiers)
    var first = true
    for row in tableView.selectedIndexes():
      if not first:
        result.add ","
      result.add $row
      first = false

  method restoreSelectionPersistenceString(tableView: TableView, value: string) =
    if value.startsWith(TableSelectionIdentityPrefix):
      let payload =
        if value.len > TableSelectionIdentityPrefix.len:
          value[TableSelectionIdentityPrefix.len .. ^1]
        else:
          ""
      let identifiers = parseIdentifiers(payload)
      if identifiers.len == 0:
        tableView.selectedIndexes = []
      else:
        tableView.applySelectionForRowIdentifiers(identifiers, "", "")
      return
    var rows: seq[int]
    var token = ""
    for ch in value:
      if ch == ',':
        if token.len > 0:
          try:
            rows.add parseInt(token)
          except ValueError:
            discard
        token.setLen(0)
      else:
        token.add ch
    if token.len > 0:
      try:
        rows.add parseInt(token)
      except ValueError:
        discard
    tableView.selectedIndexes = rows

protocol DefaultTableViewEditingBehavior of TableViewEditingProtocol:
  method shouldBeginEditingCell(
      tableView: TableView, row: int, column: TableColumn
  ): bool =
    if not tableView.validCell(row, column):
      return false
    let delegate = tableView.delegate()
    if not delegate.isNil:
      let allowed = delegate.trySendLocal(
        shouldEditCell(), (tableView: tableView, row: row, column: column)
      )
      if allowed.isSome:
        return allowed.get()
    true

  method beginEditingCell(tableView: TableView, row: int, column: TableColumn): bool =
    if not tableView.shouldBeginEditingCell(row, column):
      return false
    if tableView.xEditing.active:
      if tableView.xEditing.row == row and tableView.xEditing.column == column:
        let owner = tableView.window()
        if owner of Window:
          return Window(owner).makeFirstResponder(tableView)
        return true
      let editor = Control(tableView).activeEditor()
      if not editor.isNil and editor.client() == tableView:
        if not editor.commitEditing():
          return false
      elif not tableView.finishCommitEditingCell(""):
        return false
    tableView.xEditing = TableEditingState(row: row, column: column, active: true)
    tableView.selectCell(row, column)
    discard tableView.prepareEditingSurface()
    let delegate = tableView.delegate()
    if not delegate.isNil:
      discard delegate.sendLocalIfHandled(
        didBeginEditingCell(), (tableView: tableView, row: row, column: column)
      )
    let owner = tableView.window()
    if owner of Window:
      return Window(owner).makeFirstResponder(tableView)
    true

  method commitEditingCell(tableView: TableView, value: string): bool =
    if tableView.isNil or not tableView.xEditing.active:
      return false
    let editor = Control(tableView).activeEditor()
    if not editor.isNil and editor.client() == tableView:
      if value.len > 0:
        TextView(editor).stringValue = value
      return editor.commitEditing()
    tableView.finishCommitEditingCell(value)

  method cancelEditingCell(tableView: TableView): bool =
    if tableView.isNil or not tableView.xEditing.active:
      return false
    let editor = Control(tableView).activeEditor()
    if not editor.isNil and editor.client() == tableView:
      tableView.xCancellingFieldEditor = true
      result = editor.cancelEditing()
      tableView.xCancellingFieldEditor = false
      if result:
        let owner = tableView.window()
        if owner of Window and Window(owner).firstResponder() == editor:
          discard Window(owner).makeFirstResponder(nil)
      return
    tableView.finishCancelEditingCell()

protocol DefaultTableViewFieldEditorClient of FieldEditorClient:
  method fieldEditorForClient(
      tableView: TableView, defaultEditor: FieldEditor
  ): FieldEditor =
    if tableView.isNil or not tableView.xEditing.active:
      return defaultEditor
    if tableView.xEditingHostView.isNil:
      discard tableView.prepareEditingSurface()
    if not tableView.xEditingCell.isNil:
      let editor = tableView.xEditingCell.fieldEditorForView(tableView.xEditingHostView)
      if not editor.isNil:
        return editor
    defaultEditor

  method usesFieldEditor(tableView: TableView, editor: FieldEditor): bool =
    not tableView.isNil and tableView.xEditing.active

  method stringForFieldEditor(tableView: TableView, editor: FieldEditor): string =
    if tableView.isNil or not tableView.xEditing.active:
      ""
    else:
      tableView.tableCellText(tableView.xEditing.row, tableView.xEditing.column)

  method setStringFromFieldEditor(
      tableView: TableView, editor: FieldEditor, value: string
  ) =
    discard

  method didBeginEditing(tableView: TableView, editor: FieldEditor) =
    if tableView.isNil:
      return
    Control(tableView).setCurrentEditor(editor)
    tableView.installFieldEditorOnSurface(editor)
    tableView.focused = true
    tableView.focusVisible = editor.isFocusVisible()
    tableView.setNeedsDisplay(true)

  method didChangeFocusInEditor(tableView: TableView, editor: FieldEditor) =
    if tableView.isNil or Control(tableView).activeEditor() != editor:
      return
    tableView.focused = editor.isFocused()
    tableView.focusVisible = editor.isFocusVisible()

  method didChangeTextInEditor(tableView: TableView, editor: FieldEditor) =
    if tableView.isNil or not tableView.xEditing.active:
      return
    if tableView.xEditing.validation.failed():
      tableView.setEditingValidation(initObjectValidationError())

  method shouldBeginEditing(tableView: TableView, editor: FieldEditor): bool =
    not tableView.isNil and tableView.xEditing.active

  method shouldEndEditing(tableView: TableView, editor: FieldEditor): bool =
    if tableView.isNil:
      return true
    if tableView.xCancellingFieldEditor:
      return true
    tableView.validateEditingValue(TextView(editor).stringValue())

  method validationErrorForEditor(
      tableView: TableView, editor: FieldEditor
  ): ObjectValidationError =
    tableView.editingValidation()

  method didEndEditing(tableView: TableView, editor: FieldEditor) =
    if tableView.isNil:
      return
    tableView.removeFieldEditorFromSurface(editor)
    Control(tableView).setCurrentEditor(nil)
    tableView.focused = false
    tableView.focusVisible = false
    tableView.setNeedsDisplay(true)

  method didEndEditingReason(
      tableView: TableView, editor: FieldEditor, reason: TextEditReason
  ) =
    if tableView.isNil:
      return
    case reason
    of terCancel:
      discard tableView.finishCancelEditingCell()
    of terCommit, terFocusChange, terProgrammatic:
      discard tableView.finishCommitEditingCell(TextView(editor).stringValue())

  method didEndEditingMovement(
      tableView: TableView, editor: FieldEditor, movement: TextEditMovement
  ) =
    if tableView.isNil:
      return
    if not tableView.moveEditingFromEndedCell(movement):
      let owner = tableView.window()
      if owner of Window and Window(owner).firstResponder() == editor:
        case movement
        of temTab:
          if not Window(owner).selectKeyViewFollowingView(tableView):
            discard Window(owner).makeFirstResponder(tableView)
        of temBacktab:
          if not Window(owner).selectKeyViewPrecedingView(tableView):
            discard Window(owner).makeFirstResponder(tableView)
        of temReturn, temNone:
          discard Window(owner).makeFirstResponder(tableView)

protocol DefaultTableViewDraggingBehavior of TableViewDraggingProtocol:
  method beginDraggingRows(
      tableView: TableView,
      rows: seq[int],
      operations: DragOperations,
      pasteboardName: string,
  ): DraggingSession =
    if tableView.isNil:
      return nil
    var validRows: seq[int]
    for row in rows:
      if row in 0 ..< tableView.rowCount():
        validRows.add row
    if validRows.len == 0:
      return nil
    let payload = joinRowIndexes(validRows)
    var items =
      @[
        initDraggingItem(TablePasteboardTypeRows, initPasteboardStringItem(payload)),
        initDraggingItem(PasteboardTypeString, initPasteboardStringItem(payload)),
      ]
    let identifiers = tableView.rowIdentifiersForRows(validRows)
    if identifiers.len > 0:
      items.add initDraggingItem(
        TablePasteboardTypeRowIdentifiers,
        initPasteboardStringItem(joinIdentifiers(identifiers)),
      )
    result =
      beginDraggingSession(DynamicAgent(tableView), items, operations, pasteboardName)
    tableView.xTableDraggingSession = result

  method beginDraggingColumns(
      tableView: TableView,
      columns: seq[TableColumn],
      operations: DragOperations,
      pasteboardName: string,
  ): DraggingSession =
    if tableView.isNil:
      return nil
    var identifiers: seq[string]
    for column in columns:
      if not column.isNil and column.tableView() == tableView:
        identifiers.add column.identifier()
    if identifiers.len == 0:
      return nil
    let payload = joinIdentifiers(identifiers)
    result = beginDraggingSession(
      DynamicAgent(tableView),
      [
        initDraggingItem(TablePasteboardTypeColumns, initPasteboardStringItem(payload)),
        initDraggingItem(PasteboardTypeString, initPasteboardStringItem(payload)),
      ],
      operations,
      pasteboardName,
    )
    tableView.xTableDraggingSession = result

  method reorderTableRows(
      tableView: TableView, rows: seq[int], target: DraggingDropTarget
  ): bool =
    tableView.defaultReorderRows(rows, target)

  method validateDragging(tableView: TableView, info: DraggingInfo): DragOperations =
    if tableView.isNil:
      return NoDragOperations
    let
      isRowReorder = tableView.isTableRowReorderDrag(info)
      rowReorderOperation =
        if tableView.canAcceptTableRowReorder(info):
          {dgoMove}
        else:
          NoDragOperations
      proposedOperation =
        if isRowReorder: rowReorderOperation else: info.selectedOperations
    let delegate = tableView.delegate()
    if not delegate.isNil:
      let validated = delegate.trySendLocal(
        validateDropOperation(),
        (
          tableView: tableView,
          info: info,
          proposedOperation: proposedOperation,
          target: info.dropTarget,
          position: info.dropTarget.position,
        ),
      )
      if validated.isSome:
        if isRowReorder:
          return validated.get() * rowReorderOperation
        return validated.get()
      if isRowReorder:
        return rowReorderOperation
      let operation = delegate.trySendLocal(
        validateDragOperation(), (tableView: tableView, info: info)
      )
      if operation.isSome:
        if isRowReorder:
          return operation.get() * rowReorderOperation
        return operation.get()
    if isRowReorder:
      return rowReorderOperation
    info.selectedOperations

  method acceptDragging(tableView: TableView, info: DraggingInfo): bool =
    if tableView.isNil:
      return false
    let operation = tableView.validateDragging(info)
    if operation == NoDragOperations:
      return false
    if tableView.isTableRowReorderDrag(info):
      return
        dgoMove in operation and
        tableView.reorderRows(info.tableDraggingRows(), info.dropTarget)
    let delegate = tableView.delegate()
    if not delegate.isNil:
      let acceptedDrop = delegate.trySendLocal(
        acceptDropOperation(),
        (
          tableView: tableView,
          info: info,
          operation: operation,
          target: info.dropTarget,
          position: info.dropTarget.position,
        ),
      )
      if acceptedDrop.isSome:
        return acceptedDrop.get()
      let accepted =
        delegate.trySendLocal(acceptDragOperation(), (tableView: tableView, info: info))
      if accepted.isSome:
        return accepted.get()
    true

protocol DefaultTableViewDraggingSource of DraggingSourceProtocol:
  method draggingSourceOperationMask(
      tableView: TableView, info: DraggingInfo
  ): DragOperations =
    info.allowedOperations

  method draggingSessionEnded(tableView: TableView, info: DraggingInfo) =
    if not tableView.isNil and tableView.xTableDraggingSession == info.session:
      tableView.xTableDraggingSession = nil
      tableView.updateTableDropTarget(initDraggingDropTarget())

protocol DefaultTableViewDraggingDestination of DraggingDestinationProtocol:
  method draggingEntered(tableView: TableView, info: DraggingInfo): DragOperations =
    tableView.updateTableDropTarget(info.dropTarget)
    tableView.validateDragging(info)

  method draggingUpdated(tableView: TableView, info: DraggingInfo): DragOperations =
    tableView.updateTableDropTarget(info.dropTarget)
    tableView.validateDragging(info)

  method draggingExited(tableView: TableView, info: DraggingInfo) =
    tableView.updateTableDropTarget(initDraggingDropTarget())

  method prepareForDragOperation(tableView: TableView, info: DraggingInfo): bool =
    tableView.validateDragging(info) != NoDragOperations

  method performDragOperation(tableView: TableView, info: DraggingInfo): bool =
    tableView.acceptDragging(info)

  method concludeDragOperation(tableView: TableView, info: DraggingInfo) =
    tableView.updateTableDropTarget(initDraggingDropTarget())

  method autoscrollDraggingSession(tableView: TableView, info: DraggingInfo): bool =
    tableView.autoscrollDraggingInfo(info)

protocol DefaultTableViewEvents of ResponderEventProtocol:
  method updateTrackingAreas(tableView: TableView, event: MouseEvent): bool =
    discard event
    tableView.syncHeaderTrackingAreas()
    true

  method cursorUpdate(tableView: TableView, event: MouseEvent): bool =
    if tableView.isNil:
      return false
    tableView.tableHeaderHitTest(event.location).part == thpResizeHandle

  method mouseDown(tableView: TableView, event: MouseEvent): bool =
    if tableView.headerMouseDown(event):
      return true
    tableView.defaultTableViewMouseDown(event)

  method mouseDragged(tableView: TableView, event: MouseEvent): bool =
    if tableView.xTrackingColumn != nil:
      return tableView.headerMouseDragged(event)
    if tableView.updateActiveTableDrag(event):
      return true
    tableView.defaultTableViewMouseDragged(event)

  method mouseUp(tableView: TableView, event: MouseEvent): bool =
    if tableView.xTrackingColumn != nil:
      return tableView.headerMouseUp(event)
    if tableView.performActiveTableDrag(event):
      return true
    let handled = tableView.defaultTableViewMouseUp(event)
    if event.clickCount >= 2:
      let
        row = tableView.rowItemIndexAtPoint(event.location)
        column = tableView.tableColumnAtPoint(event.location)
      if tableView.shouldBeginEditingCell(row, column):
        return tableView.beginEditingCell(row, column)
    handled

  method mouseMoved(tableView: TableView, event: MouseEvent): bool =
    if tableView.headerMouseMoved(event):
      return true
    if tableView.isEnabled():
      tableView.highlightedIndex = tableView.rowItemIndexAtPoint(event.location)
      return true
    false

  method keyDown(tableView: TableView, event: KeyEvent): bool =
    if event.key == keyEnter:
      let row =
        if tableView.selectedIndex() >= 0:
          tableView.selectedIndex()
        elif tableView.clickedRow() >= 0:
          tableView.clickedRow()
        else:
          -1
      let column =
        if not tableView.clickedColumn().isNil:
          tableView.clickedColumn()
        else:
          tableView.columnAt(0)
      if tableView.shouldBeginEditingCell(row, column):
        return tableView.beginEditingCell(row, column)
    tableView.defaultTableViewKeyDown(event)

protocol DefaultTableViewPersistenceBehavior of TableViewPersistenceProtocol:
  method columnAutosaveRecords(tableView: TableView): seq[TableColumnAutosaveRecord] =
    for column in tableView.xColumns:
      result.add TableColumnAutosaveRecord(
        identifier: column.identifier(),
        width: column.width(),
        hidden: column.hidden(),
        sortDirection: column.sortDirection(),
      )

  method restoreColumnAutosaveRecords(
      tableView: TableView, records: seq[TableColumnAutosaveRecord]
  ) =
    if tableView.isNil:
      return
    var ordered: seq[TableColumn]
    var restored: seq[TableColumn]
    for record in records:
      let resolvedIdentifier =
        tableView.resolveColumnAutosaveIdentifier(record.identifier)
      let column = tableView.columnWithIdentifier(resolvedIdentifier)
      if column.isNil:
        continue
      if column in restored:
        continue
      column.xWidth = record.width.normalizedWidth(column.xMinWidth, column.xMaxWidth)
      column.xHidden = record.hidden
      column.xSortDirection = record.sortDirection
      ordered.add column
      restored.add column
    for column in tableView.xColumns:
      var seen = false
      for existing in ordered:
        if existing == column:
          seen = true
      if not seen:
        ordered.add column
    tableView.xColumns = ordered
    tableView.noteColumnsChanged()

protocol DefaultTableViewStateBehavior of TableViewStateProtocol:
  method captureState(tableView: TableView): TableViewState =
    var selectedColumns: seq[string]
    for column in tableView.selectedColumns():
      if not column.isNil:
        selectedColumns.add column.identifier()
    let selectedRowIdentifiers =
      tableView.rowIdentifiersForRows(tableView.selectedIndexes())
    initTableViewState(
      tableView.columnAutosaveRecords(),
      tableView.selectedIndexes(),
      selectedColumns,
      selectedRowIdentifiers = selectedRowIdentifiers,
    )

  method restoreState(tableView: TableView, state: TableViewState) =
    if tableView.isNil:
      return
    tableView.restoreColumnAutosaveRecords(state.columns)
    if state.selectedRowIdentifiers.len > 0:
      var hasRestoredRow = false
      for identifier in state.selectedRowIdentifiers:
        if tableView.tableRowIndexForIdentifier(identifier) >= 0:
          hasRestoredRow = true
          break
      if hasRestoredRow:
        tableView.applySelectionForRowIdentifiers(state.selectedRowIdentifiers, "", "")
      else:
        tableView.selectedIndexes = state.selectedRows
    else:
      tableView.selectedIndexes = state.selectedRows
    if tableView.allowsColumnSelection():
      var columns: seq[TableColumn]
      for identifier in state.selectedColumns:
        let column = tableView.columnWithIdentifier(
          tableView.resolveColumnAutosaveIdentifier(identifier)
        )
        if not column.isNil:
          columns.add column
      tableView.selectedColumns = columns

protocol TableViewStateWindowLifecycleSlots of WindowLifecycleEvents:
  proc willClose(tableView: TableView) {.slot.} =
    tableView.saveAutosavedState()

proc unobserveTableStateWindow(tableView: TableView) =
  if tableView.isNil or tableView.xObservedStateWindow.isNil:
    return
  tableView.unobserveProtocol(
    tableView.xObservedStateWindow, TableViewStateWindowLifecycleSlots
  )
  tableView.xObservedStateWindow = nil

proc observeTableStateWindow(tableView: TableView, window: Window) =
  if tableView.isNil or tableView.xObservedStateWindow == window:
    return
  tableView.unobserveTableStateWindow()
  if window.isNil:
    return
  tableView.observeProtocol(window, TableViewStateWindowLifecycleSlots)
  tableView.xObservedStateWindow = window

protocol TableViewStateViewLifecycleSlots of ViewLifecycleProtocol:
  proc saveTableStateBeforeWindowChange(
      tableView: TableView, window: Responder
  ) {.slotFor: viewWillMoveToWindow.} =
    let currentWindow =
      if tableView.window() of Window:
        Window(tableView.window())
      else:
        nil
    if not currentWindow.isNil and DynamicAgent(currentWindow) != DynamicAgent(window):
      tableView.saveAutosavedState()
      tableView.unobserveTableStateWindow()
      tableView.xHasRestoredState = false

  proc restoreTableStateAfterWindowChange(
      tableView: TableView
  ) {.slotFor: viewDidMoveToWindow.} =
    let currentWindow =
      if tableView.window() of Window:
        Window(tableView.window())
      else:
        nil
    tableView.observeTableStateWindow(currentWindow)
    if not currentWindow.isNil:
      tableView.restoreStateIfNeeded()

protocol DefaultTableViewDrawing of ViewDrawingProtocol:
  method draw(tableView: TableView, context: DrawContext) =
    if tableView.isNil or context.isNil or tableView.bounds().isEmpty:
      return
    tableView.tileTableContent()
    let
      classes = tableView.styleClasses()
      focusedState = tableView.widgetStateSet()
      listStyle = context.appearance.resolveTableViewStyle(
        controlStyle(
          tableView.xTableRole,
          focusedState,
          id = tableView.styleId(),
          classes = classes,
        )
      )
    discard context.addRenderRectangle(
      context.renderRectFor(tableView.bounds()),
      listStyle.box.fill,
      listStyle.box.borderColor,
      listStyle.box.borderWidth,
      listStyle.box.cornerRadius,
      listStyle.box.shadows,
      clips = true,
    )
    tableView.drawTableHeader(context)
    if ssFocusVisible in focusedState:
      let headerHeight = tableView.tableHeaderHeight()
      let visibleBounds = tableView.visibleRect()
      var focusRect = tableView.bounds()
      focusRect.y += headerHeight
      focusRect.h = max(focusRect.h - headerHeight, 0.0'f32)
      if not focusRect.intersection(visibleBounds).isEmpty:
        let focusClip = context.addRenderRectangle(
          FocusRingDrawLevel,
          (-1).FigIdx,
          tableView.rectToWindow(visibleBounds),
          fill(color(0.0, 0.0, 0.0, 0.0)),
          clips = true,
        )
        context.addFocusRing(
          FocusRingDrawLevel,
          focusClip,
          tableView.rectToWindow(focusRect),
          tableFocusRingBox(listStyle.box),
        )

protocol DefaultTableViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(tableView: TableView): AccessibilityRole =
    arTable

  method accessibilityValue(tableView: TableView): string =
    $tableView.rowCount()

  method accessibilityTraits(tableView: TableView): AccessibilityTraits =
    result = tableView.xAccessibilityTraits + {atSelectable}
    if ssDisabled in tableView.xWidgetStates:
      result.incl atDisabled
    if tableView.focused():
      result.incl atFocused

  method isAccessibilityElement(tableView: TableView): bool =
    true

proc initTableViewFields*(tableView: TableView, frame: Rect = AutoRect) =
  initControlFields(tableView, frame)
  tableView.xTableRole = srTableView
  let style = tableView.tableStyle()
  tableView.xSelectedIndex = -1
  tableView.xSelectedIndexes = @[]
  tableView.xSelectionAnchor = -1
  tableView.xSelectionLead = -1
  tableView.xHighlightedIndex = -1
  tableView.xPressedIndex = -1
  tableView.xRowHeight = style.rowHeight
  tableView.xVisibleRows = 5
  tableView.xSelectionMode = tsmSingle
  tableView.xItemRole = srRowItem
  tableView.xRowCount = 0
  tableView.xShowsHeader = true
  tableView.xHeaderHeight = style.headerHeight
  tableView.xClickedRow = -1
  tableView.xAllowsColumnSelection = false
  tableView.xEditing = TableEditingState(row: -1)
  tableView.xEndedEditingRow = -1
  tableView.xTableDropTarget = initDraggingDropTarget()
  tableView.xStateScope = tvssAutomatic
  tableView.xColumnAutosaveAliases = initTable[string, string]()
  tableView.xRowIdentifierAliases = initTable[string, string]()
  tableView.xTrackingColumnIndex = -1
  tableView.xHeaderDragInsertionIndex = -1
  tableView.xReusableCellViews = initTable[string, seq[View]]()
  tableView.xScrollView = initTableScrollView(tableView)
  tableView.xContentView = initTableContentView(tableView)
  tableView.xScrollView.documentView = tableView.xContentView
  tableView.setAcceptsFirstResponder(true)
  tableView.clipsToBounds = true
  tableView.addSubview(tableView.xScrollView)
  tableView.syncTableScrollChrome()
  tableView.syncHeaderTrackingAreas()
  discard tableView.withProtocol(DefaultTableViewLayout)
  discard tableView.withProtocol(DefaultTableViewColumnBehavior)
  discard tableView.withProtocol(DefaultTableViewSelectionBehavior)
  discard tableView.withProtocol(DefaultTableViewEditingBehavior)
  discard tableView.withProtocol(DefaultTableViewFieldEditorClient)
  discard tableView.withProtocol(DefaultTableViewEvents)
  discard tableView.withProtocol(DefaultTableViewMouseHitPolicy)
  discard tableView.withProtocol(DefaultTableViewDraggingBehavior)
  discard tableView.withProtocol(DefaultTableViewDraggingSource)
  discard tableView.withProtocol(DefaultTableViewDraggingDestination)
  discard tableView.withProtocol(DefaultTableViewPersistenceBehavior)
  discard tableView.withProtocol(DefaultTableViewStateBehavior)
  discard tableView.withProtocol(TableViewStateViewLifecycleSlots)
  tableView.observeProtocol(tableView, TableViewStateViewLifecycleSlots)
  discard tableView.withProtocol(DefaultTableViewDrawing)
  discard tableView.withProtocol(DefaultTableViewAccessibility)
  tableView.applyInitialFrame(frame)

proc newTableView*(frame: Rect = AutoRect): TableView =
  result = TableView()
  initTableViewFields(result, frame)
