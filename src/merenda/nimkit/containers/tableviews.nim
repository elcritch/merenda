import std/[math, options]

import sigils/core

import ../drawing/drawing
import ../foundation/events
import ./listviews
import ../containers/listbasics
import ../foundation/selectors
import ../drawing/theme
import ../foundation/types
import ../view/views

export listviews except visibleRowViews

const
  DefaultTableColumnWidth = 120.0'f32
  DefaultTableColumnMinWidth = 24.0'f32
  DefaultTableColumnMaxWidth = 10000.0'f32

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

  TableDragOperation* = enum
    tdoNone
    tdoCopy
    tdoMove
    tdoLink

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

  TableDraggingInfo* = object
    rows*: seq[int]
    columns*: seq[string]
    operation*: TableDragOperation
    pasteboardName*: string

  TableView* = ref object of ListView
    xColumns: seq[TableColumn]
    xRowCount: int
    xTableDataSource: DynamicAgent
    xTableDelegate: DynamicAgent
    xCellSlots: seq[TableCellSlot]
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
    xDraggingInfo: TableDraggingInfo

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
proc clearTableCellSlots(tableView: TableView)
proc syncVisibleTableCells(tableView: TableView)
proc drawTableRow(
  tableView: TableView, context: DrawContext, rect: Rect, row: ListRowState
)

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
  method validateDragging*(
    tableView: TableView, info: TableDraggingInfo
  ): TableDragOperation {.optional.}
  method acceptDragging*(
    tableView: TableView, info: TableDraggingInfo
  ): bool {.optional.}

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
  if column.isNil: nil else: column.xTableView

proc identifier*(column: TableColumn): string =
  if column.isNil: "" else: column.xIdentifier

proc title*(column: TableColumn): string =
  if column.isNil: "" else: column.xTitle

proc `title=`*(column: TableColumn, title: string) =
  if column.isNil or column.xTitle == title:
    return
  column.xTitle = title
  column.tableView().noteColumnsChanged()

proc width*(column: TableColumn): float32 =
  if column.isNil: 0.0'f32 else: column.xWidth

proc `width=`*(column: TableColumn, width: float32) =
  if column.isNil:
    return
  let nextWidth = width.normalizedWidth(column.xMinWidth, column.xMaxWidth)
  if column.xWidth == nextWidth:
    return
  column.xWidth = nextWidth
  column.tableView().noteColumnsChanged()

proc minWidth*(column: TableColumn): float32 =
  if column.isNil: 0.0'f32 else: column.xMinWidth

proc `minWidth=`*(column: TableColumn, width: float32) =
  if column.isNil:
    return
  let nextMin = width.normalizedColumnMetric(DefaultTableColumnMinWidth)
  if column.xMinWidth == nextMin:
    return
  column.xMinWidth = nextMin
  column.xMaxWidth = max(column.xMaxWidth, nextMin)
  column.xWidth = column.xWidth.normalizedWidth(column.xMinWidth, column.xMaxWidth)
  column.tableView().noteColumnsChanged()

proc maxWidth*(column: TableColumn): float32 =
  if column.isNil: 0.0'f32 else: column.xMaxWidth

proc `maxWidth=`*(column: TableColumn, width: float32) =
  if column.isNil:
    return
  let nextMax = width.normalizedMaxWidth(column.xMinWidth)
  if column.xMaxWidth == nextMax:
    return
  column.xMaxWidth = nextMax
  column.xWidth = column.xWidth.normalizedWidth(column.xMinWidth, column.xMaxWidth)
  column.tableView().noteColumnsChanged()

proc alignment*(column: TableColumn): TextAlignment =
  if column.isNil: taLeft else: column.xAlignment

proc `alignment=`*(column: TableColumn, alignment: TextAlignment) =
  if column.isNil or column.xAlignment == alignment:
    return
  column.xAlignment = alignment
  column.tableView().noteColumnsChanged()

proc resizePolicy*(column: TableColumn): TableColumnResizePolicy =
  if column.isNil: tcrFixed else: column.xResizePolicy

proc `resizePolicy=`*(column: TableColumn, policy: TableColumnResizePolicy) =
  if column.isNil or column.xResizePolicy == policy:
    return
  column.xResizePolicy = policy
  column.tableView().noteColumnsChanged()

proc hidden*(column: TableColumn): bool =
  (not column.isNil) and column.xHidden

proc `hidden=`*(column: TableColumn, hidden: bool) =
  if column.isNil or column.xHidden == hidden:
    return
  column.xHidden = hidden
  column.tableView().noteColumnsChanged()

proc sortDirection*(column: TableColumn): TableSortDirection =
  if column.isNil: tsdNone else: column.xSortDirection

proc `sortDirection=`*(column: TableColumn, direction: TableSortDirection) =
  if column.isNil or column.xSortDirection == direction:
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
  if column.isNil or column.xReuseIdentifier == identifier:
    return
  column.xReuseIdentifier = identifier
  let tableView = column.tableView()
  if not tableView.isNil:
    tableView.clearTableCellSlots()
    tableView.noteColumnsChanged()

proc styleId*(column: TableColumn): string =
  if column.isNil: "" else: column.xStyleId

proc `styleId=`*(column: TableColumn, id: string) =
  if column.isNil or column.xStyleId == id:
    return
  column.xStyleId = id
  column.tableView().noteColumnsChanged()

proc styleClasses*(column: TableColumn): seq[string] =
  if column.isNil:
    @[]
  else:
    column.xStyleClasses

proc `styleClasses=`*(column: TableColumn, classes: openArray[string]) =
  if column.isNil:
    return
  let nextClasses = @classes
  if column.xStyleClasses == nextClasses:
    return
  column.xStyleClasses = nextClasses
  column.tableView().noteColumnsChanged()

proc userInfo*(column: TableColumn): DynamicAgent =
  if column.isNil: nil else: column.xUserInfo

proc `userInfo=`*(column: TableColumn, userInfo: DynamicAgent) =
  if column.isNil or column.xUserInfo == userInfo:
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
  if tableView.isNil: nil else: tableView.xTableDataSource

proc delegate*(tableView: TableView): DynamicAgent =
  if tableView.isNil: nil else: tableView.xTableDelegate

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
  if tableView.isNil:
    return
  let nextCount = max(count, 0)
  if tableView.xRowCount == nextCount:
    return
  tableView.xRowCount = nextCount
  ListView(tableView).reloadData()

proc `dataSource=`*(tableView: TableView, dataSource: DynamicAgent) =
  if tableView.isNil or tableView.xTableDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(TableViewDataSource)
  tableView.clearTableCellSlots()
  tableView.xTableDataSource = dataSource
  ListView(tableView).reloadData()

proc `dataSource=`*(tableView: TableView, dataSource: Responder) =
  tableView.dataSource = DynamicAgent(dataSource)

proc `delegate=`*(tableView: TableView, delegate: DynamicAgent) =
  if tableView.isNil or tableView.xTableDelegate == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(TableViewDelegate)
  tableView.clearTableCellSlots()
  tableView.xTableDelegate = delegate
  ListView(tableView).reloadData()

proc `delegate=`*(tableView: TableView, delegate: Responder) =
  tableView.delegate = DynamicAgent(delegate)

proc columnCount*(tableView: TableView): int =
  if tableView.isNil: 0 else: tableView.xColumns.len

proc columnAt*(tableView: TableView, index: int): TableColumn =
  if tableView.isNil or index notin 0 ..< tableView.xColumns.len:
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
  if tableView.isNil or not tableView.xShowsHeader:
    0.0'f32
  else:
    tableView.xHeaderHeight

proc `tableHeaderHeight=`*(tableView: TableView, height: float32) =
  if tableView.isNil:
    return
  let nextHeight = max(height, 0.0'f32)
  if tableView.xHeaderHeight == nextHeight:
    return
  tableView.xHeaderHeight = nextHeight
  tableView.noteColumnsChanged()

proc showsHeader*(tableView: TableView): bool =
  (not tableView.isNil) and tableView.xShowsHeader

proc `showsHeader=`*(tableView: TableView, value: bool) =
  if tableView.isNil or tableView.xShowsHeader == value:
    return
  tableView.xShowsHeader = value
  tableView.noteColumnsChanged()

proc tableHeaderRect*(tableView: TableView): Rect =
  if tableView.isNil or not tableView.showsHeader():
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

proc resizeColumn*(tableView: TableView, column: TableColumn, width: float32) =
  if tableView.isNil or column.isNil or column.tableView() != tableView:
    return
  if column.resizePolicy() == tcrFixed:
    return
  column.width = width

proc moveColumn*(tableView: TableView, fromIndex, toIndex: int) =
  if tableView.isNil or fromIndex notin 0 ..< tableView.xColumns.len:
    return
  let boundedTo = max(0, min(toIndex, tableView.xColumns.len - 1))
  if fromIndex == boundedTo:
    return
  let column = tableView.xColumns[fromIndex]
  tableView.xColumns.delete(fromIndex)
  tableView.xColumns.insert(column, boundedTo)
  tableView.noteColumnsChanged()

proc requestSort*(
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
  if tableView.isNil: -1 else: tableView.xClickedRow

proc clickedColumn*(tableView: TableView): TableColumn =
  if tableView.isNil: nil else: tableView.xClickedColumn

proc clickedColumnIndex*(tableView: TableView): int =
  if tableView.isNil or tableView.xClickedColumn.isNil:
    -1
  else:
    tableView.columnIndex(tableView.xClickedColumn.identifier())

proc allowsColumnSelection*(tableView: TableView): bool =
  (not tableView.isNil) and tableView.xAllowsColumnSelection

proc `allowsColumnSelection=`*(tableView: TableView, value: bool) =
  if tableView.isNil or tableView.xAllowsColumnSelection == value:
    return
  tableView.xAllowsColumnSelection = value
  if not value:
    tableView.xSelectedColumns.setLen(0)
  tableView.setNeedsDisplay(true)

proc selectedColumns*(tableView: TableView): seq[TableColumn] =
  if tableView.isNil: @[] else: tableView.xSelectedColumns

proc `selectedColumns=`*(tableView: TableView, columns: openArray[TableColumn]) =
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

proc selectCell*(tableView: TableView, row: int, column: TableColumn) =
  if not tableView.validCell(row, column):
    return
  ListView(tableView).selectedIndex = row
  if tableView.xAllowsColumnSelection:
    tableView.xSelectedColumns = @[column]
  tableView.xClickedRow = row
  tableView.xClickedColumn = column
  tableView.setNeedsDisplay(true)

proc editingState*(tableView: TableView): TableEditingState =
  if tableView.isNil: TableEditingState(row: -1) else: tableView.xEditing

proc beginEditingCell*(tableView: TableView, row: int, column: TableColumn): bool =
  if not tableView.validCell(row, column):
    return false
  let delegate = tableView.delegate()
  if not delegate.isNil:
    let allowed =
      delegate.trySendLocal(shouldEditCell(), (tableView: tableView, row: row, column: column))
    if allowed.isSome and not allowed.get():
      return false
  tableView.xEditing = TableEditingState(row: row, column: column, active: true)
  tableView.selectCell(row, column)
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didBeginEditingCell(), (tableView: tableView, row: row, column: column)
    )
  true

proc commitEditingCell*(tableView: TableView, value = ""): bool =
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

proc cancelEditingCell*(tableView: TableView): bool =
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

proc autosaveName*(tableView: TableView): string =
  if tableView.isNil: "" else: tableView.xAutosaveName

proc `autosaveName=`*(tableView: TableView, name: string) =
  if tableView.isNil:
    return
  tableView.xAutosaveName = name

proc columnAutosaveRecords*(tableView: TableView): seq[TableColumnAutosaveRecord] =
  if tableView.isNil:
    return @[]
  for column in tableView.xColumns:
    result.add TableColumnAutosaveRecord(
      identifier: column.identifier(),
      width: column.width(),
      hidden: column.hidden(),
      sortDirection: column.sortDirection(),
    )

proc restoreColumnAutosaveRecords*(
    tableView: TableView, records: openArray[TableColumnAutosaveRecord]
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

proc draggingInfo*(tableView: TableView): TableDraggingInfo =
  if tableView.isNil: TableDraggingInfo() else: tableView.xDraggingInfo

proc beginDraggingRows*(
    tableView: TableView,
    rows: openArray[int],
    operation = tdoMove,
    pasteboardName = "drag",
): TableDraggingInfo =
  if tableView.isNil:
    return TableDraggingInfo()
  var validRows: seq[int]
  for row in rows:
    if row in 0 ..< tableView.rowCount():
      validRows.add row
  result = TableDraggingInfo(
    rows: validRows,
    columns: @[],
    operation: operation,
    pasteboardName: pasteboardName,
  )
  tableView.xDraggingInfo = result

proc validateDragging*(tableView: TableView, info: TableDraggingInfo): TableDragOperation =
  if tableView.isNil:
    return tdoNone
  let delegate = tableView.delegate()
  if not delegate.isNil:
    let operation =
      delegate.trySendLocal(validateDragging(), (tableView: tableView, info: info))
    if operation.isSome:
      return operation.get()
  info.operation

proc acceptDragging*(tableView: TableView, info: TableDraggingInfo): bool =
  if tableView.isNil:
    return false
  let delegate = tableView.delegate()
  if not delegate.isNil:
    let accepted =
      delegate.trySendLocal(acceptDragging(), (tableView: tableView, info: info))
    if accepted.isSome:
      return accepted.get()
  info.operation != tdoNone

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
      slot.view.removeFromSuperview()
  tableView.xCellSlots.setLen(0)

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
        nextSlots.add TableCellSlot(row: row, column: column, view: cellView)
  for index, slot in previousSlots:
    if not used[index] and not slot.view.isNil:
      slot.view.removeFromSuperview()
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
  tableView.clearTableCellSlots()
  tableView.invalidateIntrinsicContentSize()
  tableView.setNeedsLayout()
  tableView.setNeedsDisplay(true)

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

proc initTableViewFields*(tableView: TableView, frame: Rect = AutoRect) =
  initListViewFields(ListView(tableView), frame = frame)
  tableView.xRowCount = 0
  tableView.xShowsHeader = true
  tableView.xHeaderHeight = 24.0'f32
  tableView.xClickedRow = -1
  tableView.xAllowsColumnSelection = false
  tableView.xEditing = TableEditingState(row: -1)
  discard tableView.withProtocol(TableViewListDataSource)
  discard tableView.withProtocol(TableViewListDelegate)
  ListView(tableView).dataSource = DynamicAgent(tableView)
  ListView(tableView).delegate = DynamicAgent(tableView)

proc newTableView*(frame: Rect = AutoRect): TableView =
  result = TableView()
  initTableViewFields(result, frame)
