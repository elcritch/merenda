import std/[math, options]

import sigils/core

import ./listviews
import ./selectors
import ./types
import ./views

export listviews

const
  DefaultTableColumnWidth = 120.0'f32
  DefaultTableColumnMinWidth = 24.0'f32
  DefaultTableColumnMaxWidth = 10000.0'f32

type
  TableColumnResizePolicy* = enum
    tcrFixed
    tcrResizable

  TableView* = ref object of ListView
    xColumns: seq[TableColumn]
    xRowCount: int
    xTableDataSource: DynamicAgent

  TableColumn* = ref object
    xTableView: TableView
    xIdentifier: string
    xTitle: string
    xWidth: float32
    xMinWidth: float32
    xMaxWidth: float32
    xAlignment: TextAlignment
    xResizePolicy: TableColumnResizePolicy
    xStyleId: string
    xStyleClasses: seq[string]
    xUserInfo: DynamicAgent

proc noteColumnsChanged(tableView: TableView)
proc detachColumn(column: TableColumn)
proc removeColumnAtIndex(tableView: TableView, index: int)
proc resolvedRowCount(tableView: TableView): int

protocol TableViewDataSource {.selectorScope: protocol.}:
  method numberOfRows*(tableView: TableView): int {.optional.}

protocol TableViewListDataSource of ListViewDataSource:
  method rowCount(tableView: TableView, listView: ListView): int =
    resolvedRowCount(tableView)

  method objectValueForRow(tableView: TableView, listView: ListView, row: int): string =
    ""

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
  tableView.xTableDataSource = dataSource
  ListView(tableView).reloadData()

proc `dataSource=`*(tableView: TableView, dataSource: Responder) =
  tableView.dataSource = DynamicAgent(dataSource)

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

proc noteColumnsChanged(tableView: TableView) =
  if tableView.isNil:
    return
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
  discard tableView.withProtocol(TableViewListDataSource)
  ListView(tableView).dataSource = DynamicAgent(tableView)

proc newTableView*(frame: Rect = AutoRect): TableView =
  result = TableView()
  initTableViewFields(result, frame)
