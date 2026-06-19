import std/[options, strutils]

import sigils/core

import ./tableviews
import ../app/pasteboards
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../responder/responders

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

  OutlineDisclosureHit* = object
    row*: int
    item*: OutlineItem
    rect*: Rect

  OutlineView* = ref object of TableView
    xOutlineItems: seq[OutlineItem]
    xExpanded: seq[string]
    xOutlineColumn: TableColumn
    xOutlineDataSource: DynamicAgent
    xOutlineDelegate: DynamicAgent

protocol OutlineViewDataSource {.selectorScope: protocol.}:
  method numberOfChildren*(
    outlineView: OutlineView, parentIdentifier: string
  ): int {.optional.}
  method childIdentifier*(
    outlineView: OutlineView, parentIdentifier: string, index: int
  ): string {.optional.}
  method outlineItem*(
    outlineView: OutlineView, identifier: string
  ): OutlineItem {.optional.}

protocol OutlineViewDelegate {.selectorScope: protocol.}:
  method shouldExpandItem*(
    outlineView: OutlineView, identifier: string
  ): bool {.optional.}
  method didExpandItem*(outlineView: OutlineView, identifier: string) {.optional.}
  method shouldCollapseItem*(
    outlineView: OutlineView, identifier: string
  ): bool {.optional.}
  method didCollapseItem*(outlineView: OutlineView, identifier: string) {.optional.}

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
  let source = outlineView.xOutlineDataSource
  if not source.isNil:
    let count = source.trySendLocal(
      numberOfChildren(), (outlineView: outlineView, parentIdentifier: identifier)
    )
    if count.isSome:
      return count.get() > 0
  for item in outlineView.xOutlineItems:
    if item.parentIdentifier == identifier:
      return true
  false

proc sourcedOutlineItem(outlineView: OutlineView, identifier: string): OutlineItem =
  if outlineView.isNil or outlineView.xOutlineDataSource.isNil:
    return OutlineItem()
  let item = outlineView.xOutlineDataSource.trySendLocal(
    outlineItem(), (outlineView: outlineView, identifier: identifier)
  )
  if item.isSome:
    item.get()
  else:
    OutlineItem()

proc childrenForParent(outlineView: OutlineView, parentIdentifier: string): seq[OutlineItem] =
  if outlineView.isNil:
    return @[]
  let source = outlineView.xOutlineDataSource
  if not source.isNil:
    let count = source.trySendLocal(
      numberOfChildren(),
      (outlineView: outlineView, parentIdentifier: parentIdentifier),
    )
    if count.isSome:
      for index in 0 ..< max(count.get(), 0):
        let identifier = source.trySendLocal(
          childIdentifier(),
          (outlineView: outlineView, parentIdentifier: parentIdentifier, index: index),
        )
        if identifier.isNone:
          continue
        let item = source.trySendLocal(
          outlineItem(), (outlineView: outlineView, identifier: identifier.get())
        )
        if item.isSome:
          result.add item.get()
      return
  for item in outlineView.xOutlineItems:
    if item.parentIdentifier == parentIdentifier:
      result.add item

proc appendVisibleRows(
    outlineView: OutlineView,
    parentIdentifier: string,
    level: int,
    rows: var seq[OutlineRow],
) =
  for item in outlineView.childrenForParent(parentIdentifier):
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

proc outlineDataSource*(outlineView: OutlineView): DynamicAgent =
  if outlineView.isNil: nil else: outlineView.xOutlineDataSource

proc `outlineDataSource=`*(outlineView: OutlineView, dataSource: DynamicAgent) =
  if outlineView.isNil or outlineView.xOutlineDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(OutlineViewDataSource)
  outlineView.xOutlineDataSource = dataSource
  TableView(outlineView).reloadData()

proc `outlineDataSource=`*(outlineView: OutlineView, dataSource: Responder) =
  outlineView.outlineDataSource = DynamicAgent(dataSource)

proc outlineDelegate*(outlineView: OutlineView): DynamicAgent =
  if outlineView.isNil: nil else: outlineView.xOutlineDelegate

proc `outlineDelegate=`*(outlineView: OutlineView, delegate: DynamicAgent) =
  if outlineView.isNil or outlineView.xOutlineDelegate == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(OutlineViewDelegate)
  outlineView.xOutlineDelegate = delegate

proc `outlineDelegate=`*(outlineView: OutlineView, delegate: Responder) =
  outlineView.outlineDelegate = DynamicAgent(delegate)

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
  if index >= 0:
    return outlineView.xOutlineItems[index].expandable or outlineView.hasChildren(identifier)
  let item = outlineView.sourcedOutlineItem(identifier)
  item.expandable or outlineView.hasChildren(identifier)

proc isItemExpanded*(outlineView: OutlineView, identifier: string): bool =
  (not outlineView.isNil) and outlineView.xExpanded.containsIdentifier(identifier)

proc expandItem*(outlineView: OutlineView, identifier: string) =
  if outlineView.isNil or not outlineView.isItemExpandable(identifier):
    return
  if outlineView.xExpanded.containsIdentifier(identifier):
    return
  let delegate = outlineView.outlineDelegate()
  if not delegate.isNil:
    let allowed =
      delegate.trySendLocal(shouldExpandItem(), (outlineView: outlineView, identifier: identifier))
    if allowed.isSome and not allowed.get():
      return
  outlineView.xExpanded.add identifier
  TableView(outlineView).reloadData()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didExpandItem(), (outlineView: outlineView, identifier: identifier)
    )

proc collapseItem*(outlineView: OutlineView, identifier: string) =
  if outlineView.isNil:
    return
  let delegate = outlineView.outlineDelegate()
  if not delegate.isNil:
    let allowed =
      delegate.trySendLocal(shouldCollapseItem(), (outlineView: outlineView, identifier: identifier))
    if allowed.isSome and not allowed.get():
      return
  var next: seq[string]
  for value in outlineView.xExpanded:
    if value != identifier:
      next.add value
  if next == outlineView.xExpanded:
    return
  outlineView.xExpanded = next
  TableView(outlineView).reloadData()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didCollapseItem(), (outlineView: outlineView, identifier: identifier)
    )

proc toggleItem*(outlineView: OutlineView, identifier: string) =
  if outlineView.isItemExpanded(identifier):
    outlineView.collapseItem(identifier)
  else:
    outlineView.expandItem(identifier)

proc expandedItemIdentifiers*(outlineView: OutlineView): seq[string] =
  if outlineView.isNil: @[] else: outlineView.xExpanded

proc `expandedItemIdentifiers=`*(outlineView: OutlineView, identifiers: openArray[string]) =
  if outlineView.isNil:
    return
  outlineView.xExpanded = @identifiers
  TableView(outlineView).reloadData()

proc expansionPersistenceString*(outlineView: OutlineView): string =
  if outlineView.isNil:
    return ""
  outlineView.xExpanded.join(",")

proc restoreExpansionPersistenceString*(outlineView: OutlineView, value: string) =
  if outlineView.isNil:
    return
  if value.len == 0:
    outlineView.xExpanded.setLen(0)
  else:
    outlineView.xExpanded = value.split(",")
  TableView(outlineView).reloadData()

proc disclosureRectForRow*(outlineView: OutlineView, row: int): Rect =
  if outlineView.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let item = outlineView.itemAtRow(row)
  if item.identifier.len == 0 or not outlineView.isItemExpandable(item.identifier):
    return initRect(0.0, 0.0, 0.0, 0.0)
  let
    rowRect = TableView(outlineView).listItemRect(row)
    level = outlineView.levelForRow(row)
    size = min(rowRect.size.height, 16.0'f32)
  initRect(
    rowRect.origin.x + level.float32 * 16.0'f32 + 4.0'f32,
    rowRect.origin.y + max((rowRect.size.height - size) * 0.5'f32, 0.0'f32),
    size,
    size,
  )

proc disclosureHitTest*(outlineView: OutlineView, point: Point): OutlineDisclosureHit =
  if outlineView.isNil:
    return OutlineDisclosureHit(row: -1)
  for row in 0 ..< outlineView.rowCount():
    let rect = outlineView.disclosureRectForRow(row)
    if rect.contains(point):
      return OutlineDisclosureHit(row: row, item: outlineView.itemAtRow(row), rect: rect)
  OutlineDisclosureHit(row: -1)

proc toggleItemAtPoint*(outlineView: OutlineView, point: Point): bool =
  let hit = outlineView.disclosureHitTest(point)
  if hit.row < 0 or hit.item.identifier.len == 0:
    return false
  outlineView.toggleItem(hit.item.identifier)
  true

proc handleOutlineKey*(outlineView: OutlineView, event: KeyEvent): bool =
  if outlineView.isNil:
    return false
  let row = TableView(outlineView).selectedIndex()
  if row < 0:
    return false
  let item = outlineView.itemAtRow(row)
  case event.key
  of keyArrowRight:
    if outlineView.isItemExpandable(item.identifier) and
        not outlineView.isItemExpanded(item.identifier):
      outlineView.expandItem(item.identifier)
      return true
  of keyArrowLeft:
    if outlineView.isItemExpanded(item.identifier):
      outlineView.collapseItem(item.identifier)
      return true
  of keySpace, keyEnter:
    if outlineView.isItemExpandable(item.identifier):
      outlineView.toggleItem(item.identifier)
      return true
  else:
    discard
  false

proc beginDraggingItems*(
    outlineView: OutlineView,
    identifiers: openArray[string],
    operation = tdoMove,
    pasteboardName = DragPasteboardName,
): TableDraggingInfo =
  if outlineView.isNil:
    return TableDraggingInfo()
  var rows: seq[int]
  for identifier in identifiers:
    let row = outlineView.rowForItem(identifier)
    if row >= 0:
      rows.add row
  TableView(outlineView).beginDraggingRows(rows, operation, pasteboardName)

proc outlineCellText(outlineView: OutlineView, row: int, column: TableColumn): string =
  let rows = outlineView.visibleOutlineRows()
  if row notin 0 ..< rows.len:
    return ""
  let outlineRow = rows[row]
  if column == outlineView.outlineColumn():
    for _ in 0 ..< outlineRow.level:
      result.add "  "
    if outlineView.isItemExpandable(outlineRow.item.identifier):
      result.add(if outlineView.isItemExpanded(outlineRow.item.identifier): "v " else: "> ")
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
