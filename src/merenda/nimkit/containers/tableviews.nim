import std/[algorithm, math, options, strutils, tables, times]

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
import ../foundation/selectors
import ../themes
import ../text/fieldeditors
import ../text/textviews
import ../foundation/types
import ../view/views

const
  DefaultTableColumnWidth = 120.0'f32
  DefaultTableColumnMinWidth = 24.0'f32
  DefaultTableColumnMaxWidth = 10000.0'f32
  TableTypeSelectTimeout = 1.0
  TablePasteboardTypeRows* = "nimkit.table.rows"
  TablePasteboardTypeColumns* = "nimkit.table.columns"

type
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

  TableColumnAutosaveRecord* = object
    identifier*: string
    width*: float32
    hidden*: bool
    sortDirection*: TableSortDirection

  TableViewState* = object
    columns*: seq[TableColumnAutosaveRecord]
    selectedRows*: seq[int]
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
proc tableRowIdentifier(tableView: TableView, row: int): string
proc tableRowIndexForIdentifier(tableView: TableView, identifier: string): int
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

proc syncTableScrollChrome(tableView: TableView)

protocol TableViewDataSource {.selectorScope: protocol.}:
  method numberOfRows*(tableView: TableView): int {.optional.}
  method textForCell*(
    tableView: TableView, row: int, column: TableColumn
  ): string {.optional.}

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

protocol TableViewDelegate {.selectorScope: protocol.}:
  method viewForCell*(
    tableView: TableView, row: int, column: TableColumn
  ): View {.optional.}

  method tableRowHeight*(tableView: TableView, row: int): float32 {.optional.}
  method isRowEnabled*(tableView: TableView, row: int): bool {.optional.}
  method shouldSelectTableRow*(tableView: TableView, row: int): bool {.optional.}
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

  method validationErrorForCell*(
    tableView: TableView, row: int, column: TableColumn, value: string
  ): string {.optional.}

  method didCommitEditingCell*(
    tableView: TableView, row: int, column: TableColumn, value: string
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
  TableHeaderResizeHandleWidth = 5.0'f32
  TableHeaderDragThreshold = 3.0'f32
  TableHeaderAutoscrollEdge = 18.0'f32
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

func normalizedColumnMetric(value, fallback: float32): float32 =
  if value.isNaN:
    fallback
  else:
    max(value, 0.0'f32)

func normalizedMaxWidth(value, minWidth: float32): float32 =
  max(value.normalizedColumnMetric(DefaultTableColumnMaxWidth), minWidth)

func normalizedWidth(value, minWidth, maxWidth: float32): float32 =
  min(max(value.normalizedColumnMetric(DefaultTableColumnWidth), minWidth), maxWidth)

proc tableView*(contentView: TableContentView): TableView =
  if contentView.isNil: nil else: contentView.xTableView

proc tableView*(column: TableColumn): TableView =
  column.xTableView

proc scrollView*(tableView: TableView): ScrollView =
  if tableView.isNil: nil else: tableView.xScrollView

proc contentView*(tableView: TableView): TableContentView =
  if tableView.isNil: nil else: tableView.xContentView

proc initTableBaseChild(view: View, clipsToBounds: bool) =
  initViewFields(view, initRect(0.0, 0.0, 0.0, 0.0))
  view.background = initColor(0.0, 0.0, 0.0, 0.0)
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
  let nextMin = width.normalizedColumnMetric(DefaultTableColumnMinWidth)
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
    width = DefaultTableColumnWidth,
    minWidth = DefaultTableColumnMinWidth,
    maxWidth = DefaultTableColumnMaxWidth,
    alignment = taLeft,
    resizePolicy = tcrResizable,
) =
  column.xIdentifier = identifier
  column.xTitle = if title.len == 0: identifier else: title
  column.xMinWidth = minWidth.normalizedColumnMetric(DefaultTableColumnMinWidth)
  column.xMaxWidth = maxWidth.normalizedMaxWidth(column.xMinWidth)
  column.xWidth = width.normalizedWidth(column.xMinWidth, column.xMaxWidth)
  column.xAlignment = alignment
  column.xResizePolicy = resizePolicy
  column.xSortDirection = tsdNone
  column.xReuseIdentifier = identifier

proc newTableColumn*(
    identifier: string,
    title = "",
    width = DefaultTableColumnWidth,
    minWidth = DefaultTableColumnMinWidth,
    maxWidth = DefaultTableColumnMaxWidth,
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
    return initRect(0.0, 0.0, 0.0, 0.0)
  var x = bounds.origin.x
  for current in tableView.xColumns:
    if current.hidden():
      continue
    if current == column:
      let width = min(current.width(), max(bounds.maxX - x, 0.0'f32))
      return initRect(x, bounds.origin.y, width, bounds.size.height)
    x += current.width()
  initRect(bounds.origin.x, bounds.origin.y, 0.0, 0.0)

proc tableHeaderHeight*(tableView: TableView): float32 =
  if not tableView.xShowsHeader: 0.0'f32 else: tableView.xHeaderHeight

proc defaultTableHeaderChrome*(): TableHeaderChrome =
  TableHeaderChrome(
    headerFill: fill(initColor(0.88, 0.90, 0.94, 1.0)),
    headerBorderColor: initColor(0.60, 0.64, 0.70, 1.0),
    cellFill: fill(initColor(0.90, 0.92, 0.96, 1.0)),
    hoveredCellFill: fill(initColor(0.84, 0.88, 0.95, 1.0)),
    pressedCellFill: fill(initColor(0.76, 0.82, 0.91, 1.0)),
    cellBorderColor: initColor(0.62, 0.66, 0.72, 1.0),
    textColor: initColor(0.14, 0.18, 0.25, 1.0),
    sortIndicatorColor: initColor(0.12, 0.20, 0.34, 0.95),
    insertionIndicatorFill: fill(initColor(0.16, 0.36, 0.84, 0.95)),
    borderWidth: 1.0'f32,
    sortIndicatorWidth: 24.0'f32,
    insertionWidth: 3.0'f32,
    insertionCapWidth: 9.0'f32,
    insertionCapHeight: 3.0'f32,
    cornerRadius: 1.5'f32,
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
    return initRect(0.0, 0.0, 0.0, 0.0)
  initRect(
    1.0'f32,
    1.0'f32,
    max(tableView.bounds().size.width - 2.0'f32, 0.0'f32),
    tableView.tableHeaderHeight(),
  )

proc tableColumnRect*(tableView: TableView, column: TableColumn): Rect =
  tableView.columnRect(tableView.bounds(), column)

proc tableHeaderColumnRect*(tableView: TableView, column: TableColumn): Rect =
  tableView.columnRect(tableView.tableHeaderRect(), column)

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
    return initRect(0.0, 0.0, 0.0, 0.0)
  let headerRect = tableView.tableHeaderRect()
  if headerRect.isEmpty:
    return initRect(0.0, 0.0, 0.0, 0.0)
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
  initRect(x - 1.0'f32, headerRect.origin.y, 3.0'f32, headerRect.size.height)

proc clearHeaderDragInsertion(tableView: TableView) =
  if tableView.isNil:
    return
  tableView.xHeaderDragInsertionIndex = -1
  tableView.xHeaderDragInsertionRect = initRect(0.0, 0.0, 0.0, 0.0)

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
  if point.x <= headerRect.minX + TableHeaderAutoscrollEdge:
    tableView.setHeaderDragInsertion(0)
    return true
  if point.x >= headerRect.maxX - TableHeaderAutoscrollEdge:
    tableView.setHeaderDragInsertion(tableView.xColumns.len)
    return true
  false

proc resetHeaderCursorRects(tableView: TableView) =
  if tableView.isNil:
    return
  tableView.discardCursorRects()
  if not tableView.showsHeader():
    return
  for column in tableView.visibleColumns():
    if column.resizePolicy() != tcrResizable:
      continue
    let rect = tableView.tableHeaderColumnRect(column)
    if rect.isEmpty:
      continue
    tableView.addCursorRect(
      initRect(
        rect.maxX - TableHeaderResizeHandleWidth,
        rect.origin.y,
        TableHeaderResizeHandleWidth * 2.0'f32,
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
  let text =
    source.trySendLocal(textForCell(), (tableView: tableView, row: row, column: column))
  if text.isSome:
    text.get()
  else:
    ""

proc tableRowIdentifier(tableView: TableView, row: int): string =
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

proc tableRowIndexForIdentifier(tableView: TableView, identifier: string): int =
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
    scrollFrame = initRect(
      1.0'f32,
      1.0'f32,
      max(tableView.bounds().size.width - 2.0'f32, 0.0'f32),
      max(tableView.bounds().size.height - 2.0'f32, 0.0'f32),
    )
  tableView.xScrollView.frame = scrollFrame
  let
    verticalVisible = tableView.contentHeight() > scrollFrame.size.height
    documentWidth = max(
      scrollFrame.size.width -
        (if verticalVisible: tableView.xScrollView.scrollerThickness()
        else: 0.0'f32),
      0.0'f32,
    )
    size = initSize(documentWidth, tableView.contentHeight())
  tableView.xContentView.frame = initRect(0.0'f32, 0.0'f32, size.width, size.height)
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
  tableView.scrollContentRectToVisible(
    tableView.xContentView.tableContentItemRect(itemIndex)
  )

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
  emit tableView.selectionIsChanging(DynamicAgent(tableView))
  tableView.xSelectedIndexes = nextIndexes
  tableView.syncSelectedIndex()
  tableView.xSelectionAnchor = nextAnchor
  tableView.xSelectionLead = nextLead
  if nextLead >= 0:
    tableView.scrollItemToVisible(nextLead)
  tableView.invalidateTableRows()
  emit tableView.selectionDidChange(DynamicAgent(tableView))

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
    tableView.setTableContentOffset(scrollView.maximumContentOffset(), true)
  elif target < 0:
    tableView.setTableContentOffset(initPoint(0.0'f32, 0.0'f32), true)

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
  tableView.invalidateRowHeightCache()
  if tableView.xSelectionMode == tsmSingle and tableView.xSelectedIndexes.len > 0 and
      tableView.len() > 0:
    tableView.xSelectedIndexes[0] =
      min(max(tableView.xSelectedIndexes[0], -1), tableView.len() - 1)
  if tableView.xSelectionMode == tsmSingle and
      tableView.xSelectedIndex >= tableView.len() and tableView.len() > 0:
    tableView.xSelectedIndex = tableView.len() - 1
  if tableView.xSelectedIndexes.len == 0 and tableView.xSelectedIndex >= 0:
    tableView.xSelectedIndexes.add tableView.xSelectedIndex
  tableView.xSelectedIndexes = tableView.normalizeSelection(tableView.xSelectedIndexes)
  tableView.syncSelectedIndex()
  tableView.syncSelectionCursor()

  if not tableView.rowEnabled(tableView.xHighlightedIndex):
    tableView.xHighlightedIndex = -1
  if not tableView.rowEnabled(tableView.xPressedIndex):
    tableView.xPressedIndex = -1
  tableView.tileTableContent()
  tableView.setTableContentOffset(
    initPoint(
      0.0'f32, tableView.rowOffset(min(oldFirst, tableView.maxFirstVisibleIndex()))
    ),
    false,
  )
  if tableView.xSelectedIndex >= 0:
    tableView.scrollItemToVisible(tableView.xSelectedIndex)
  tableView.invalidateIntrinsicContentSize()
  tableView.invalidateTableRows()

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
    return initRect(0.0, 0.0, 0.0, 0.0)
  let contentRect = contentView.tableContentItemRect(itemIndex)
  if contentRect.isEmpty:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let visibleRect =
    contentView.rectToView(contentRect, tableView).intersection(tableView.bounds())
  if visibleRect.size.height < tableView.rowHeightForRow(itemIndex) or
      visibleRect.isEmpty:
    initRect(0.0, 0.0, 0.0, 0.0)
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
  tableView.setTableContentOffset(
    initPoint(0.0'f32, tableView.rowOffset(nextFirst)), false
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
      return initRowDropTarget(row, rowRect, tableDropPositionForRow(location, rowRect))
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
  tableView.setNeedsDisplay(true)

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
  parseRowIndexes(info.pasteboard.stringForType(TablePasteboardTypeRows))

proc tableDraggingColumns*(info: DraggingInfo): seq[string] =
  parseIdentifiers(info.pasteboard.stringForType(TablePasteboardTypeColumns))

proc tableDropRow*(info: DraggingInfo): int =
  info.dropTarget.row

proc tableDropColumn*(info: DraggingInfo): string =
  info.dropTarget.column

proc tableDropPosition*(info: DraggingInfo): DraggingDropPosition =
  info.dropTarget.position

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
    let rowBounds = initRect(0.0, 0.0, rowRect.size.width, rowRect.size.height)
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
    return (nil, initRect(0.0, 0.0, 0.0, 0.0))
  for (index, rowView, rowRect) in tableView.visibleRowViews():
    if index == row:
      return (rowView, rowRect)
  (nil, initRect(0.0, 0.0, 0.0, 0.0))

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
    return initRect(0.0, 0.0, 0.0, 0.0)
  if tableView.xEditingHostIsRowView:
    let row = tableView.visibleRowView(tableView.xEditing.row)
    let rowBounds = initRect(0.0, 0.0, row.rect.size.width, row.rect.size.height)
    tableView.columnRect(rowBounds, tableView.xEditing.column)
  else:
    tableView.xEditingHostView.bounds()

proc removeFieldEditorFromSurface(tableView: TableView, editor: FieldEditor) =
  if tableView.isNil or editor.isNil:
    return
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
    editor.frame = frame
    if not tableView.xEditingHostView.isNil and
        editor.superview() != tableView.xEditingHostView:
      tableView.xEditingHostView.addSubview(editor)
    editor.selectedRange = initTextRange(0, editor.textStorage().len)

proc validateEditingValue(tableView: TableView, value: string): bool =
  if tableView.isNil or not tableView.xEditing.active:
    return true
  let hadError = tableView.xEditing.validationError.len > 0
  tableView.xEditing.validationError = ""
  if hadError:
    tableView.setNeedsDisplay(true)
  let delegate = tableView.delegate()
  if delegate.isNil:
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
    tableView.xEditing.validationError = validation.get()
    tableView.setNeedsDisplay(true)
    return false
  true

proc finishCommitEditingCell(tableView: TableView, value: string): bool =
  if tableView.isNil or not tableView.xEditing.active:
    return false
  if not tableView.validateEditingValue(value):
    return false
  let editing = tableView.xEditing
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
  emit tableView.cellEditDidCommit(
    DynamicAgent(tableView), editing.row, editing.column, value
  )
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
    initControlStyleContext(
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
    discard context.addText(
      style.rowItemTextRect(rect), text, style.text.color, column.alignment()
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
    rowBounds = initRect(0.0, 0.0, rect.size.width, rect.size.height)
    style = tableView.rowItemStyle(context, row.states)
  for column in tableView.columns:
    if column.hidden():
      continue
    if not tableView.hasHostedCell(row.index, column):
      let cellRect = tableView.columnRect(rowBounds, column)
      tableView.drawTableCellText(context, row.index, column, cellRect, style)
  tableView.drawTableDropTarget(context, rect, row)

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
  let indicatorY =
    case target.position
    of ddpBefore:
      indicatorBounds.minY
    of ddpOn:
      max(indicatorBounds.maxY - 2.0'f32, indicatorBounds.minY)
    of ddpAfter:
      max(indicatorBounds.maxY - 2.0'f32, indicatorBounds.minY)
  let indicatorRect =
    initRect(indicatorBounds.origin.x, indicatorY, indicatorBounds.size.width, 2.0)
  discard
    context.addRenderRectangle(indicatorRect, fill(initColor(0.18, 0.42, 0.88, 0.95)))

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
  scrollView.scrollerInsets =
    initEdgeInsets(tableView.tableHeaderHeight(), 0.0, 0.0, 0.0)

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

proc initTableViewState*(
    columns: openArray[TableColumnAutosaveRecord] = [],
    selectedRows: openArray[int] = [],
    selectedColumns: openArray[string] = [],
    expandedItems: openArray[string] = [],
): TableViewState =
  TableViewState(
    columns: @columns,
    selectedRows: @selectedRows,
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
    return initRect(0.0, 0.0, 0.0, 0.0)
  initRect(
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
    style.fill = some(fill(initColor(0.96, 0.97, 0.99, 1.0)))
  context.drawRowItem(
    rect, row, style, tableView.xItemRole, tableView.styleId(), tableView.styleClasses()
  )
  if tableView.showsRowSeparators() and row.index >= 0 and
      row.index < tableView.len() - 1:
    let
      separatorStates: set[WidgetState] = row.states * {ssDisabled}
      itemStyle = context.appearance.resolveRowItemStyle(
        initControlStyleContext(
          tableView.xItemRole,
          separatorStates,
          id = tableView.styleId(),
          classes = tableView.styleClasses(),
        )
      )
      separatorRect = initRect(rect.origin.x, rect.maxY - 1.0'f32, rect.size.width, 1.0)
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
      initControlStyleContext(
        tableView.xTableRole,
        listState,
        id = tableView.styleId(),
        classes = tableView.styleClasses(),
      )
    )
    itemStyle = appearance.resolveRowItemStyle(
      initControlStyleContext(
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
  for index in 0 ..< tableView.len():
    maxTextWidth =
      max(maxTextWidth, textNaturalSize(tableView.rowTextForSummary(index)).width)
    if index < rowCount:
      naturalHeight += tableView.rowHeightForRow(index)
  if tableView.len() == 0:
    naturalHeight = tableView.rowHeight() * rowCount.float32

  initSize(
    max(
      listStyle.minSize.width,
      max(
        itemStyle.minSize.width,
        maxTextWidth + itemStyle.text.insets.horizontal + 2.0'f32,
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
  tableView.invalidateTableRows()
  true

proc defaultTableViewMouseDragged*(tableView: TableView, event: MouseEvent): bool =
  if tableView.isNil:
    return false
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
  result.background = initColor(0.0, 0.0, 0.0, 0.0)
  result.clipsToBounds = true
  result.hasHorizontalScroller = false
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
      initRect(rect.origin.x, rect.origin.y, chrome.insertionWidth, rect.size.height)
  discard context.addRenderRectangle(
    context.renderRectFor(insertionRect),
    chrome.insertionIndicatorFill,
    cornerRadius = chrome.cornerRadius,
  )
  discard context.addRenderRectangle(
    context.renderRectFor(
      initRect(
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
      initRect(
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
  )

proc drawTableHeaderCellChrome*(
    tableView: TableView,
    context: DrawContext,
    column: TableColumn,
    rect: Rect,
    chrome: TableHeaderChrome,
) =
  if tableView.isNil or context.isNil or column.isNil or rect.isEmpty:
    return
  var background = chrome.cellFill
  if column == tableView.xPressedColumn:
    background = chrome.pressedCellFill
  elif column == tableView.xHoveredColumn:
    background = chrome.hoveredCellFill
  discard context.addRenderRectangle(
    context.renderRectFor(rect), background, chrome.cellBorderColor, chrome.borderWidth
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
  context.addText(
    initRect(
      rect.origin.x + 8.0'f32,
      rect.origin.y,
      max(rect.size.width - 16.0'f32 - indicatorWidth, 0.0'f32),
      rect.size.height,
    ),
    column.title(),
    chrome.textColor,
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
  for column in tableView.visibleColumns():
    let rect = tableView.tableHeaderColumnRect(column)
    if rect.isEmpty:
      continue
    tableView.drawTableHeaderCellChrome(context, column, rect, chrome)
    tableView.drawTableHeaderCellTitle(context, column, rect, chrome)
    tableView.drawTableHeaderSortIndicator(
      context, rect, column.sortDirection(), chrome
    )
  tableView.drawTableHeaderInsertionIndicator(context, chrome)

proc drawTableHeader*(tableView: TableView, context: DrawContext) =
  tableView.drawTableHeader(context, defaultTableHeaderChrome())

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
    for index, column in tableView.xColumns:
      let rect = tableView.tableHeaderColumnRect(column)
      if rect.contains(point):
        result.column = column
        result.columnIndex = index
        result.rect = rect
        if column.resizePolicy() == tcrResizable and
            point.x >= rect.maxX - TableHeaderResizeHandleWidth:
          result.part = thpResizeHandle
        else:
          result.part = thpColumn
        return

  method resizeColumn(tableView: TableView, column: TableColumn, width: float32) =
    if tableView.isNil or column.isNil or column.tableView() != tableView:
      return
    if column.resizePolicy() == tcrFixed:
      return
    column.width = width

  method moveColumn(tableView: TableView, fromIndex, toIndex: int) =
    if tableView.isNil or fromIndex notin 0 ..< tableView.xColumns.len:
      return
    let boundedTo = max(0, min(toIndex, tableView.xColumns.len - 1))
    if fromIndex == boundedTo:
      return
    let column = tableView.xColumns[fromIndex]
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
      if abs(event.location.x - tableView.xDragStartPoint.x) > TableHeaderDragThreshold:
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
        abs(event.location.x - tableView.xDragStartPoint.x) > TableHeaderDragThreshold
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
    tableView.selectedIndex = row
    if tableView.xAllowsColumnSelection:
      tableView.xSelectedColumns = @[column]
    tableView.xClickedRow = row
    tableView.xClickedColumn = column
    tableView.setNeedsDisplay(true)

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
    tableView.xSelectedColumns = next
    tableView.setNeedsDisplay(true)

  method selectionPersistenceString(tableView: TableView): string =
    var first = true
    for row in tableView.selectedIndexes():
      if not first:
        result.add ","
      result.add $row
      first = false

  method restoreSelectionPersistenceString(tableView: TableView, value: string) =
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
    if tableView.xEditing.validationError.len > 0:
      tableView.xEditing.validationError = ""
      tableView.setNeedsDisplay(true)

  method shouldBeginEditing(tableView: TableView, editor: FieldEditor): bool =
    not tableView.isNil and tableView.xEditing.active

  method shouldEndEditing(tableView: TableView, editor: FieldEditor): bool =
    if tableView.isNil:
      return true
    if tableView.xCancellingFieldEditor:
      return true
    tableView.validateEditingValue(TextView(editor).stringValue())

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
    result = beginDraggingSession(
      DynamicAgent(tableView),
      [
        initDraggingItem(TablePasteboardTypeRows, initPasteboardStringItem(payload)),
        initDraggingItem(PasteboardTypeString, initPasteboardStringItem(payload)),
      ],
      operations,
      pasteboardName,
    )
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

  method validateDragging(tableView: TableView, info: DraggingInfo): DragOperations =
    if tableView.isNil:
      return NoDragOperations
    let delegate = tableView.delegate()
    if not delegate.isNil:
      let validated = delegate.trySendLocal(
        validateDropOperation(),
        (
          tableView: tableView,
          info: info,
          proposedOperation: info.selectedOperations,
          target: info.dropTarget,
          position: info.dropTarget.position,
        ),
      )
      if validated.isSome:
        return validated.get()
      let operation = delegate.trySendLocal(
        validateDragOperation(), (tableView: tableView, info: info)
      )
      if operation.isSome:
        return operation.get()
    info.selectedOperations

  method acceptDragging(tableView: TableView, info: DraggingInfo): bool =
    if tableView.isNil:
      return false
    let operation = tableView.validateDragging(info)
    if operation == NoDragOperations:
      return false
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
    let session = tableView.draggingSession()
    if not session.isNil and session.state() == dssActive:
      let target = tableView.dropTargetForDraggingLocation(event.location)
      tableView.updateTableDropTarget(target)
      discard
        updateDraggingSession(session, event.location, DynamicAgent(tableView), target)
      discard autoscrollDraggingSession(
        session, event.location, DynamicAgent(tableView), target
      )
      return true
    tableView.defaultTableViewMouseDragged(event)

  method mouseUp(tableView: TableView, event: MouseEvent): bool =
    if tableView.xTrackingColumn != nil:
      return tableView.headerMouseUp(event)
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
    initTableViewState(
      tableView.columnAutosaveRecords(), tableView.selectedIndexes(), selectedColumns
    )

  method restoreState(tableView: TableView, state: TableViewState) =
    if tableView.isNil:
      return
    tableView.restoreColumnAutosaveRecords(state.columns)
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
        initControlStyleContext(
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
      var focusRect = tableView.bounds()
      focusRect.origin.y += headerHeight
      focusRect.size.height = max(focusRect.size.height - headerHeight, 0.0'f32)
      if not focusRect.isEmpty:
        context.addFocusRing(context.renderRectFor(focusRect), listStyle.box)

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
  tableView.xSelectedIndex = -1
  tableView.xSelectedIndexes = @[]
  tableView.xSelectionAnchor = -1
  tableView.xSelectionLead = -1
  tableView.xHighlightedIndex = -1
  tableView.xPressedIndex = -1
  tableView.xRowHeight = 22.0'f32
  tableView.xVisibleRows = 5
  tableView.xSelectionMode = tsmSingle
  tableView.xTableRole = srTableView
  tableView.xItemRole = srRowItem
  tableView.xRowCount = 0
  tableView.xShowsHeader = true
  tableView.xHeaderHeight = 24.0'f32
  tableView.xClickedRow = -1
  tableView.xAllowsColumnSelection = false
  tableView.xEditing = TableEditingState(row: -1)
  tableView.xEndedEditingRow = -1
  tableView.xTableDropTarget = initDraggingDropTarget()
  tableView.xStateScope = tvssAutomatic
  tableView.xColumnAutosaveAliases = initTable[string, string]()
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
