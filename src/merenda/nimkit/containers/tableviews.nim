import std/[math, options, strutils, tables]

import sigils/core

import ../accessibility/accessibilityprotocols
import ../drawing/drawing
import ../foundation/events
import ../app/dragging
import ../app/pasteboards
import ./listviews
import ../containers/listbasics
import ../containers/scrollviews
import ../foundation/selectors
import ../drawing/theme
import ../foundation/types
import ../view/views

export listviews except visibleRowViews

const
  DefaultTableColumnWidth = 120.0'f32
  DefaultTableColumnMinWidth = 24.0'f32
  DefaultTableColumnMaxWidth = 10000.0'f32
  TablePasteboardTypeRows* = "nimkit.table.rows"
  TablePasteboardTypeColumns* = "nimkit.table.columns"

type
  TableColumnResizePolicy* = enum
    tcrFixed
    tcrResizable

  TableSortDirection* = enum
    tsdNone
    tsdAscending
    tsdDescending

  TableHeaderHitPart* = enum
    thpNone
    thpColumn
    thpResizeHandle

  TableHeaderHit* = object
    column*: TableColumn
    columnIndex*: int
    part*: TableHeaderHitPart
    rect*: Rect

  TableEditingState* = object
    row*: int
    column*: TableColumn
    active*: bool

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

  TableView* = ref object of ListView
    xColumns: seq[TableColumn]
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
    xTableDraggingSession: DraggingSession
    xHeaderTrackingPart: TableHeaderHitPart
    xTrackingColumn: TableColumn
    xTrackingColumnIndex: int
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

proc noteColumnsChanged(tableView: TableView)
proc detachColumn(column: TableColumn)
proc removeColumnAtIndex(tableView: TableView, index: int)
proc resolvedRowCount(tableView: TableView): int
proc tableRowEnabled(tableView: TableView, row: int): bool
proc tableRowSelectable(tableView: TableView, row: int): bool
proc resolvedRowHeight(tableView: TableView, row: int): float32
proc tableRowDidActivate(tableView: TableView, row: int)
proc tableColumnAtPoint(tableView: TableView, point: Point): TableColumn
proc tableCellHitPolicy(
  tableView: TableView, row: int, column: TableColumn, target: View, event: MouseEvent
): CellHitPolicy

proc tableCellText*(tableView: TableView, row: int, column: TableColumn): string
proc tableCellView*(tableView: TableView, row: int, column: TableColumn): View
proc enqueueReusableCellView(tableView: TableView, identifier: string, view: View)
proc clearTableCellSlots(tableView: TableView)
proc syncVisibleTableCells(tableView: TableView)
proc drawTableRow(
  tableView: TableView, context: DrawContext, rect: Rect, row: ListRowState
)

proc syncTableScrollChrome(tableView: TableView)

protocol TableViewDataSource {.selectorScope: protocol.}:
  method numberOfRows*(tableView: TableView): int {.optional.}
  method textForCell*(
    tableView: TableView, row: int, column: TableColumn
  ): string {.optional.}

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

protocol TableViewListDataSource of ListViewDataSource:
  method rowCount(tableView: TableView, listView: ListView): int =
    resolvedRowCount(tableView)

  method objectValueForRow(tableView: TableView, listView: ListView, row: int): string =
    tableView.tableCellText(row, tableView.columnAt(0))

protocol TableViewListDelegate of ListViewDelegate:
  method rowIsEnabled(tableView: TableView, listView: ListView, row: int): bool =
    tableView.tableRowEnabled(row)

  method shouldSelectRow(tableView: TableView, listView: ListView, row: int): bool =
    tableView.tableRowSelectable(row)

  method hitPolicyForRow(
      tableView: TableView,
      listView: ListView,
      row: int,
      target: View,
      event: MouseEvent,
  ): CellHitPolicy =
    let column = tableView.tableColumnAtPoint(event.location)
    tableView.tableCellHitPolicy(row, column, target, event)

  method heightOfRow(tableView: TableView, listView: ListView, row: int): float32 =
    tableView.resolvedRowHeight(row)

  method rowDidActivate(tableView: TableView, listView: ListView, row: int) =
    tableView.tableRowDidActivate(row)

  method visibleRowsDidSync(tableView: TableView, listView: ListView) =
    tableView.syncVisibleTableCells()

  method drawRow(
      tableView: TableView,
      listView: ListView,
      context: DrawContext,
      rect: Rect,
      row: ListRowState,
  ) =
    tableView.drawTableRow(context, rect, row)

func normalizedColumnMetric(value, fallback: float32): float32 =
  if value.isNaN:
    fallback
  else:
    max(value, 0.0'f32)

func normalizedMaxWidth(value, minWidth: float32): float32 =
  max(value.normalizedColumnMetric(DefaultTableColumnMaxWidth), minWidth)

func normalizedWidth(value, minWidth, maxWidth: float32): float32 =
  min(max(value.normalizedColumnMetric(DefaultTableColumnWidth), minWidth), maxWidth)

proc tableView*(column: TableColumn): TableView =
  column.xTableView

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
  ListView(tableView).reloadData()

proc `dataSource=`*(tableView: TableView, dataSource: DynamicAgent) =
  if tableView.xTableDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(TableViewDataSource)
  tableView.clearTableCellSlots()
  tableView.xTableDataSource = dataSource
  ListView(tableView).reloadData()

proc `dataSource=`*(tableView: TableView, dataSource: Responder) =
  tableView.dataSource = DynamicAgent(dataSource)

proc `delegate=`*(tableView: TableView, delegate: DynamicAgent) =
  if tableView.xTableDelegate == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(TableViewDelegate)
  tableView.clearTableCellSlots()
  tableView.xTableDelegate = delegate
  ListView(tableView).reloadData()

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

proc resolvedRowHeight(tableView: TableView, row: int): float32 =
  if tableView.isNil:
    return 0.0'f32
  if row notin 0 ..< tableView.rowCount():
    return ListView(tableView).rowHeight()
  let delegate = tableView.delegate()
  if not delegate.isNil:
    let height =
      delegate.trySendLocal(tableRowHeight(), (tableView: tableView, row: row))
    if height.isSome:
      return height.get()
  ListView(tableView).rowHeight()

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

proc selectedIndex*(tableView: TableView): int =
  ListView(tableView).selectedIndex()

proc `selectedIndex=`*(tableView: TableView, index: int) =
  ListView(tableView).selectedIndex = index

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

proc autosaveName*(tableView: TableView): string =
  tableView.xAutosaveName

proc `autosaveName=`*(tableView: TableView, name: string) =
  tableView.xAutosaveName = name

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
    info: DraggingInfo, row = -1, column: TableColumn = nil
): DraggingInfo =
  if row >= 0 and not column.isNil:
    info.withDropTarget(initCellDropTarget(row, column.identifier()))
  elif row >= 0:
    info.withDropTarget(initRowDropTarget(row))
  elif not column.isNil:
    info.withDropTarget(initColumnDropTarget(column.identifier()))
  else:
    info.withDropTarget(initDraggingDropTarget())

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

proc findCellSlot(slots: openArray[TableCellSlot], row: int, column: TableColumn): int =
  for index, slot in slots:
    if slot.row == row and slot.column == column:
      return index
  -1

proc clearTableCellSlots(tableView: TableView) =
  if tableView.isNil:
    return
  for slot in tableView.xCellSlots:
    if not slot.view.isNil:
      tableView.enqueueReusableCellView(slot.column.reuseIdentifier(), slot.view)
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
  for (row, rowView, rowRect) in ListView(tableView).visibleRowViews():
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
        tableView.applyCellAccessibility(row, column, cellView)
        nextSlots.add TableCellSlot(row: row, column: column, view: cellView)
  for index, slot in previousSlots:
    if not used[index] and not slot.view.isNil:
      tableView.enqueueReusableCellView(slot.column.reuseIdentifier(), slot.view)
  tableView.xCellSlots = nextSlots

proc listItemStyle(
    tableView: TableView, context: DrawContext, states: set[WidgetState]
): ListItemStyle =
  context.appearance.resolveListItemStyle(
    initControlStyleContext(
      srListItem, states, id = tableView.styleId(), classes = tableView.styleClasses()
    )
  )

proc drawTableCellText(
    tableView: TableView,
    context: DrawContext,
    row: int,
    column: TableColumn,
    rect: Rect,
    style: ListItemStyle,
) =
  if rect.isEmpty:
    return
  let text = tableView.tableCellText(row, column)
  if text.len > 0:
    discard context.addText(
      style.listItemTextRect(rect), text, style.text.color, column.alignment()
    )

proc drawTableRow(
    tableView: TableView, context: DrawContext, rect: Rect, row: ListRowState
) =
  if tableView.isNil or context.isNil:
    return
  let emptyRow = initListRowState(row.index, "", states = row.states)
  ListView(tableView).drawListRow(context, rect, emptyRow)
  if row.index < 0:
    return
  let
    rowBounds = initRect(0.0, 0.0, rect.size.width, rect.size.height)
    style = tableView.listItemStyle(context, row.states)
  for column in tableView.columns:
    if column.hidden():
      continue
    if not tableView.hasHostedCell(row.index, column):
      let cellRect = tableView.columnRect(rowBounds, column)
      tableView.drawTableCellText(context, row.index, column, cellRect, style)

proc noteColumnsChanged(tableView: TableView) =
  if tableView.isNil:
    return
  tableView.syncTableScrollChrome()
  tableView.clearTableCellSlots()
  tableView.invalidateIntrinsicContentSize()
  tableView.setNeedsLayout()
  tableView.setNeedsDisplay(true)

proc syncTableScrollChrome(tableView: TableView) =
  if tableView.isNil:
    return
  let scrollView = ListView(tableView).scrollView()
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

proc drawTableHeader*(tableView: TableView, context: DrawContext) =
  if tableView.isNil or context.isNil or not tableView.showsHeader():
    return
  let headerRect = tableView.tableHeaderRect()
  if headerRect.isEmpty:
    return
  discard context.addRenderRectangle(
    context.renderRectFor(headerRect),
    fill(initColor(0.88, 0.90, 0.94, 1.0)),
    initColor(0.60, 0.64, 0.70, 1.0),
    1.0'f32,
  )
  for column in tableView.visibleColumns():
    let rect = tableView.tableHeaderColumnRect(column)
    if rect.isEmpty:
      continue
    var background = initColor(0.90, 0.92, 0.96, 1.0)
    if column == tableView.xPressedColumn:
      background = initColor(0.76, 0.82, 0.91, 1.0)
    elif column == tableView.xHoveredColumn:
      background = initColor(0.84, 0.88, 0.95, 1.0)
    discard context.addRenderRectangle(
      context.renderRectFor(rect),
      fill(background),
      initColor(0.62, 0.66, 0.72, 1.0),
      1.0'f32,
    )
    var title = column.title()
    case column.sortDirection()
    of tsdAscending:
      title.add " ^"
    of tsdDescending:
      title.add " v"
    of tsdNone:
      discard
    context.addText(
      initRect(
        rect.origin.x + 8.0'f32,
        rect.origin.y,
        max(rect.size.width - 16.0'f32, 0.0'f32),
        rect.size.height,
      ),
      title,
      initColor(0.14, 0.18, 0.25, 1.0),
      column.alignment(),
    )

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
        if column.resizePolicy() == tcrResizable and point.x >= rect.maxX - 5.0'f32:
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
      let hit = tableView.tableHeaderHitTest(event.location)
      if hit.columnIndex >= 0 and hit.columnIndex != tableView.xTrackingColumnIndex:
        tableView.moveColumn(tableView.xTrackingColumnIndex, hit.columnIndex)
        tableView.xTrackingColumnIndex = hit.columnIndex
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
      moved = abs(event.location.x - tableView.xDragStartPoint.x) > 3.0'f32
    tableView.xHeaderTrackingPart = thpNone
    tableView.xTrackingColumn = nil
    tableView.xTrackingColumnIndex = -1
    tableView.xPressedColumn = nil
    if clickedPart == thpColumn and not moved and hit.column == clickedColumn:
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
    ListView(tableView).selectedIndex = row
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
    tableView.xEditing = TableEditingState(row: row, column: column, active: true)
    tableView.selectCell(row, column)
    let delegate = tableView.delegate()
    if not delegate.isNil:
      discard delegate.sendLocalIfHandled(
        didBeginEditingCell(), (tableView: tableView, row: row, column: column)
      )
    true

  method commitEditingCell(tableView: TableView, value: string): bool =
    if tableView.isNil or not tableView.xEditing.active:
      return false
    let editing = tableView.xEditing
    tableView.xEditing = TableEditingState(row: -1)
    let delegate = tableView.delegate()
    if not delegate.isNil:
      discard delegate.sendLocalIfHandled(
        didCommitEditingCell(),
        (tableView: tableView, row: editing.row, column: editing.column, value: value),
      )
    tableView.setNeedsDisplay(true)
    true

  method cancelEditingCell(tableView: TableView): bool =
    if tableView.isNil or not tableView.xEditing.active:
      return false
    let editing = tableView.xEditing
    tableView.xEditing = TableEditingState(row: -1)
    let delegate = tableView.delegate()
    if not delegate.isNil:
      discard delegate.sendLocalIfHandled(
        didCancelEditingCell(),
        (tableView: tableView, row: editing.row, column: editing.column),
      )
    tableView.setNeedsDisplay(true)
    true

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
      let operation = delegate.trySendLocal(
        validateDragOperation(), (tableView: tableView, info: info)
      )
      if operation.isSome:
        return operation.get()
    info.selectedOperations

  method acceptDragging(tableView: TableView, info: DraggingInfo): bool =
    if tableView.isNil:
      return false
    let delegate = tableView.delegate()
    if not delegate.isNil:
      let accepted =
        delegate.trySendLocal(acceptDragOperation(), (tableView: tableView, info: info))
      if accepted.isSome:
        return accepted.get()
    info.selectedOperations != NoDragOperations

protocol DefaultTableViewDraggingSource of DraggingSourceProtocol:
  method draggingSourceOperationMask(
      tableView: TableView, info: DraggingInfo
  ): DragOperations =
    info.allowedOperations

  method draggingSessionEnded(tableView: TableView, info: DraggingInfo) =
    if not tableView.isNil and tableView.xTableDraggingSession == info.session:
      tableView.xTableDraggingSession = nil

protocol DefaultTableViewDraggingDestination of DraggingDestinationProtocol:
  method draggingEntered(tableView: TableView, info: DraggingInfo): DragOperations =
    tableView.validateDragging(info)

  method draggingUpdated(tableView: TableView, info: DraggingInfo): DragOperations =
    tableView.validateDragging(info)

  method prepareForDragOperation(tableView: TableView, info: DraggingInfo): bool =
    tableView.validateDragging(info) != NoDragOperations

  method performDragOperation(tableView: TableView, info: DraggingInfo): bool =
    tableView.acceptDragging(info)

  method autoscrollDraggingSession(tableView: TableView, info: DraggingInfo): bool =
    ListView(tableView).autoscrollDraggingInfo(info)

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
    for record in records:
      let column = tableView.columnWithIdentifier(record.identifier)
      if column.isNil:
        continue
      column.xWidth = record.width.normalizedWidth(column.xMinWidth, column.xMaxWidth)
      column.xHidden = record.hidden
      column.xSortDirection = record.sortDirection
      ordered.add column
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
        let column = tableView.columnWithIdentifier(identifier)
        if not column.isNil:
          columns.add column
      tableView.selectedColumns = columns

protocol DefaultTableViewDrawing of ViewDrawingProtocol:
  method draw(tableView: TableView, context: DrawContext) =
    if tableView.isNil or context.isNil or tableView.bounds().isEmpty:
      return
    discard context.addRenderRectangle(
      context.renderRectFor(tableView.bounds()),
      fill(initColor(0.98, 0.985, 0.995, 1.0)),
      initColor(0.66, 0.68, 0.73, 1.0),
      1.0'f32,
      0.0'f32,
      clips = true,
    )
    tableView.drawTableHeader(context)

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
  initListViewFields(ListView(tableView), frame = frame)
  tableView.xRowCount = 0
  tableView.xShowsHeader = true
  tableView.xHeaderHeight = 24.0'f32
  tableView.xClickedRow = -1
  tableView.xAllowsColumnSelection = false
  tableView.xEditing = TableEditingState(row: -1)
  tableView.xTrackingColumnIndex = -1
  tableView.xReusableCellViews = initTable[string, seq[View]]()
  tableView.syncTableScrollChrome()
  discard tableView.withProtocol(DefaultTableViewColumnBehavior)
  discard tableView.withProtocol(DefaultTableViewSelectionBehavior)
  discard tableView.withProtocol(DefaultTableViewEditingBehavior)
  discard tableView.withProtocol(DefaultTableViewDraggingBehavior)
  discard tableView.withProtocol(DefaultTableViewDraggingSource)
  discard tableView.withProtocol(DefaultTableViewDraggingDestination)
  discard tableView.withProtocol(DefaultTableViewPersistenceBehavior)
  discard tableView.withProtocol(DefaultTableViewStateBehavior)
  discard tableView.withProtocol(DefaultTableViewDrawing)
  discard tableView.withProtocol(DefaultTableViewAccessibility)
  discard tableView.withProtocol(TableViewListDataSource)
  discard tableView.withProtocol(TableViewListDelegate)
  ListView(tableView).dataSource = DynamicAgent(tableView)
  ListView(tableView).delegate = DynamicAgent(tableView)

proc newTableView*(frame: Rect = AutoRect): TableView =
  result = TableView()
  initTableViewFields(result, frame)
