import sigils/core

import ./tableviews
import ../foundation/selectors
import ../foundation/types

export tableviews

type
  OutlineItem* = object
    identifier*: string
    parentIdentifier*: string
    title*: string
    expandable*: bool

  OutlineRow* = object
    item*: OutlineItem
    level*: int

  OutlineView* = ref object of TableView
    xOutlineItems: seq[OutlineItem]
    xExpanded: seq[string]
    xOutlineColumn: TableColumn

proc containsIdentifier(values: openArray[string], identifier: string): bool =
  for value in values:
    if value == identifier:
      return true
  false

proc itemIndex(outlineView: OutlineView, identifier: string): int =
  if outlineView.isNil:
    return -1
  for index, item in outlineView.xOutlineItems:
    if item.identifier == identifier:
      return index
  -1

proc isItemExpanded*(outlineView: OutlineView, identifier: string): bool

proc hasChildren(outlineView: OutlineView, identifier: string): bool =
  if outlineView.isNil:
    return false
  for item in outlineView.xOutlineItems:
    if item.parentIdentifier == identifier:
      return true
  false

proc appendVisibleRows(
    outlineView: OutlineView,
    parentIdentifier: string,
    level: int,
    rows: var seq[OutlineRow],
) =
  for item in outlineView.xOutlineItems:
    if item.parentIdentifier != parentIdentifier:
      continue
    rows.add OutlineRow(item: item, level: level)
    if outlineView.isItemExpanded(item.identifier):
      outlineView.appendVisibleRows(item.identifier, level + 1, rows)

proc initOutlineItem*(
    identifier: string,
    title: string,
    parentIdentifier = "",
    expandable = false,
): OutlineItem =
  OutlineItem(
    identifier: identifier,
    parentIdentifier: parentIdentifier,
    title: title,
    expandable: expandable,
  )

proc outlineColumn*(outlineView: OutlineView): TableColumn =
  if outlineView.isNil: nil else: outlineView.xOutlineColumn

proc `outlineColumn=`*(outlineView: OutlineView, column: TableColumn) =
  if outlineView.isNil or outlineView.xOutlineColumn == column:
    return
  outlineView.xOutlineColumn = column
  if not column.isNil and column.tableView() != TableView(outlineView):
    TableView(outlineView).addColumn(column)
  TableView(outlineView).reloadData()

proc outlineItems*(outlineView: OutlineView): seq[OutlineItem] =
  if outlineView.isNil: @[] else: outlineView.xOutlineItems

proc `outlineItems=`*(outlineView: OutlineView, items: openArray[OutlineItem]) =
  if outlineView.isNil:
    return
  outlineView.xOutlineItems = @items
  var nextExpanded: seq[string]
  for identifier in outlineView.xExpanded:
    if outlineView.itemIndex(identifier) >= 0:
      nextExpanded.add identifier
  outlineView.xExpanded = nextExpanded
  TableView(outlineView).reloadData()

proc visibleOutlineRows*(outlineView: OutlineView): seq[OutlineRow] =
  if outlineView.isNil:
    return @[]
  outlineView.appendVisibleRows("", 0, result)

proc rowCount*(outlineView: OutlineView): int =
  if outlineView.isNil:
    0
  else:
    outlineView.visibleOutlineRows().len

proc visibleOutlineItems*(outlineView: OutlineView): seq[OutlineItem] =
  for row in outlineView.visibleOutlineRows():
    result.add row.item

proc itemAtRow*(outlineView: OutlineView, row: int): OutlineItem =
  let rows = outlineView.visibleOutlineRows()
  if row in 0 ..< rows.len:
    rows[row].item
  else:
    OutlineItem()

proc rowForItem*(outlineView: OutlineView, identifier: string): int =
  let rows = outlineView.visibleOutlineRows()
  for index, row in rows:
    if row.item.identifier == identifier:
      return index
  -1

proc levelForRow*(outlineView: OutlineView, row: int): int =
  let rows = outlineView.visibleOutlineRows()
  if row in 0 ..< rows.len:
    rows[row].level
  else:
    -1

proc isItemExpandable*(outlineView: OutlineView, identifier: string): bool =
  let index = outlineView.itemIndex(identifier)
  if index < 0:
    return false
  outlineView.xOutlineItems[index].expandable or outlineView.hasChildren(identifier)

proc isItemExpanded*(outlineView: OutlineView, identifier: string): bool =
  (not outlineView.isNil) and outlineView.xExpanded.containsIdentifier(identifier)

proc expandItem*(outlineView: OutlineView, identifier: string) =
  if outlineView.isNil or not outlineView.isItemExpandable(identifier):
    return
  if outlineView.xExpanded.containsIdentifier(identifier):
    return
  outlineView.xExpanded.add identifier
  TableView(outlineView).reloadData()

proc collapseItem*(outlineView: OutlineView, identifier: string) =
  if outlineView.isNil:
    return
  var next: seq[string]
  for value in outlineView.xExpanded:
    if value != identifier:
      next.add value
  if next == outlineView.xExpanded:
    return
  outlineView.xExpanded = next
  TableView(outlineView).reloadData()

proc toggleItem*(outlineView: OutlineView, identifier: string) =
  if outlineView.isItemExpanded(identifier):
    outlineView.collapseItem(identifier)
  else:
    outlineView.expandItem(identifier)

proc outlineCellText(outlineView: OutlineView, row: int, column: TableColumn): string =
  let rows = outlineView.visibleOutlineRows()
  if row notin 0 ..< rows.len:
    return ""
  let outlineRow = rows[row]
  if column == outlineView.outlineColumn():
    for _ in 0 ..< outlineRow.level:
      result.add "  "
    if outlineView.isItemExpandable(outlineRow.item.identifier):
      result.add "> "
    else:
      result.add "  "
    result.add outlineRow.item.title
  else:
    result = outlineRow.item.title

protocol OutlineViewTableDataSource of TableViewDataSource:
  method numberOfRows(outlineView: OutlineView, tableView: TableView): int =
    outlineView.visibleOutlineRows().len

  method textForCell(
      outlineView: OutlineView, tableView: TableView, row: int, column: TableColumn
  ): string =
    outlineView.outlineCellText(row, column)

proc initOutlineViewFields*(outlineView: OutlineView, frame: Rect = AutoRect) =
  initTableViewFields(TableView(outlineView), frame)
  let column = newTableColumn("outline", "Outline", width = 220.0)
  outlineView.xOutlineColumn = column
  TableView(outlineView).addColumn(column)
  discard outlineView.withProtocol(OutlineViewTableDataSource)
  TableView(outlineView).dataSource = DynamicAgent(outlineView)

proc newOutlineView*(frame: Rect = AutoRect): OutlineView =
  result = OutlineView()
  initOutlineViewFields(result, frame)
