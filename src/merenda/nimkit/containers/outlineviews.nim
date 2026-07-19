import std/[options, strutils]

import sigils/core

import ./listbasics
import ./tableviews
import ../accessibility/accessibilityprotocols
import ../app/dragging
import ../app/pasteboards
import ../controls/controls
import ../drawing
import ../themes
import ../foundation/events
import ../foundation/objectvalues
import ../foundation/selectors
import ../foundation/types
import ../responder/responders
import ../view/viewprotos

export tableviews

type
  OutlineItem* = object
    identifier*: string
    parentIdentifier*: string
    title*: string
    objectValue*: ObjectValue
    cells*: seq[TableCellValue]
    enabled*: bool
    hidden*: bool
    expandable*: bool
    leaf*: bool
    image*: ImageResource
    tooltip*: string
    representedObject*: DynamicAgent
    userInfo*: DynamicAgent

  OutlineRow* = object
    item*: OutlineItem
    level*: int

  OutlineDisclosureHit* = object
    row*: int
    item*: OutlineItem
    rect*: Rect

  OutlineItemIdentity* = object
    identifier*: string
    parentIdentifier*: string
    row*: int
    level*: int
    expandable*: bool
    expanded*: bool
    visible*: bool

  OutlineAccessibilityElement* = object
    role*: AccessibilityRole
    row*: int
    identifier*: string
    label*: string
    frame*: Rect
    level*: int
    expanded*: bool
    selected*: bool
    action*: string

  OutlineView* = ref object of TableView
    xOutlineItems: seq[OutlineItem]
    xExpanded: seq[string]
    xSelectedIdentifiers: seq[string]
    xOutlineColumn: TableColumn
    xOutlineDataSource: DynamicAgent
    xOutlineDelegate: DynamicAgent
    xTrackingDisclosureRow: int
    xTrackingDisclosureIdentifier: string
    xPressedDisclosureRow: int

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

  method dropTargetForOutlineItem*(
    outlineView: OutlineView,
    identifier: string,
    row: int,
    proposedTarget: DraggingDropTarget,
  ): DraggingDropTarget {.optional.}

  method outlineDropTargetForLocation*(
    outlineView: OutlineView, location: Point, proposedTarget: DraggingDropTarget
  ): DraggingDropTarget {.optional.}

proc containsIdentifier(values: openArray[string], identifier: string): bool =
  for value in values:
    if value == identifier:
      return true
  false

proc itemIndex(outlineView: OutlineView, identifier: string): int =
  for index, item in outlineView.xOutlineItems:
    if item.identifier == identifier:
      return index
  -1

func outlineCellIndex(item: OutlineItem, columnIdentifier: string): int =
  for index, cell in item.cells:
    if cell.columnIdentifier == columnIdentifier:
      return index
  -1

func getValue*(item: OutlineItem, columnIdentifier = ""): Option[ObjectValue] =
  if columnIdentifier.len == 0:
    return some(item.objectValue)
  let index = item.outlineCellIndex(columnIdentifier)
  if index >= 0:
    some(item.cells[index].value)
  else:
    none(ObjectValue)

proc setValue*(item: var OutlineItem, columnIdentifier: string, value: ObjectValue) =
  if columnIdentifier.len == 0:
    item.objectValue = value
    return
  let index = item.outlineCellIndex(columnIdentifier)
  if index >= 0:
    item.cells[index].value = value
  else:
    item.cells.add tableCell(columnIdentifier, value)

proc `[]=`*(item: var OutlineItem, columnIdentifier: string, value: ObjectValue) =
  item.setValue(columnIdentifier, value)

proc displayTitle*(item: OutlineItem): string =
  if item.title.len > 0:
    item.title
  else:
    item.objectValue.formatObjectValue(initObjectFormatContext(role = ovrTableCell))

func outlineItemCanExpand(item: OutlineItem, hasChildren: bool): bool =
  (not item.leaf) and (item.expandable or hasChildren)

proc isItemExpanded*(outlineView: OutlineView, identifier: string): bool
proc outlineItemWithIdentifier*(
  outlineView: OutlineView, identifier: string
): OutlineItem

proc rowForItem*(outlineView: OutlineView, identifier: string): int
proc itemIdentifierForRow*(outlineView: OutlineView, row: int): string
proc selectedItemIdentifiers*(outlineView: OutlineView): seq[string]
proc `selectedItemIdentifiers=`*(
  outlineView: OutlineView, identifiers: openArray[string]
)

proc childrenForParent(
  outlineView: OutlineView, parentIdentifier: string
): seq[OutlineItem]

const
  OutlineIndentStep = 16.0'f32
  OutlineDisclosureLeading = 4.0'f32
  OutlineDisclosureMaxSize = 16.0'f32
  OutlineTextLeading = 24.0'f32
  OutlineTextTrailing = 6.0'f32

proc hasChildren(outlineView: OutlineView, identifier: string): bool =
  outlineView.childrenForParent(identifier).len > 0

proc sourcedOutlineItem(outlineView: OutlineView, identifier: string): OutlineItem =
  if outlineView.xOutlineDataSource.isNil:
    return OutlineItem()
  let item = outlineView.xOutlineDataSource.trySendLocal(
    outlineItem(), (outlineView: outlineView, identifier: identifier)
  )
  if item.isSome:
    item.get()
  else:
    OutlineItem()

proc childrenForParent(
    outlineView: OutlineView, parentIdentifier: string
): seq[OutlineItem] =
  let source = outlineView.xOutlineDataSource
  if not source.isNil:
    let count = source.trySendLocal(
      numberOfChildren(), (outlineView: outlineView, parentIdentifier: parentIdentifier)
    )
    if count.isSome:
      for index in 0 ..< max(count.get(), 0):
        let identifier = source.trySendLocal(
          childIdentifier(),
          (outlineView: outlineView, parentIdentifier: parentIdentifier, index: index),
        )
        if identifier.isSome:
          let item = source.trySendLocal(
            outlineItem(), (outlineView: outlineView, identifier: identifier.get())
          )
          if item.isSome and not item.get().hidden:
            result.add item.get()
      return
  for item in outlineView.xOutlineItems:
    if item.parentIdentifier == parentIdentifier and not item.hidden:
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
    objectValue = emptyObjectValue(),
    cells: openArray[TableCellValue] = [],
    enabled = true,
    hidden = false,
    leaf = false,
    image: ImageResource = nil,
    tooltip = "",
    representedObject: DynamicAgent = nil,
    userInfo: DynamicAgent = nil,
): OutlineItem =
  OutlineItem(
    identifier: identifier,
    parentIdentifier: parentIdentifier,
    title: title,
    objectValue: objectValue,
    cells: @cells,
    enabled: enabled,
    hidden: hidden,
    expandable: expandable,
    leaf: leaf,
    image: image,
    tooltip: tooltip,
    representedObject: representedObject,
    userInfo: userInfo,
  )

proc outlineColumn*(outlineView: OutlineView): TableColumn =
  outlineView.xOutlineColumn

proc `outlineColumn=`*(outlineView: OutlineView, column: TableColumn) =
  if outlineView.xOutlineColumn == column:
    return
  outlineView.xOutlineColumn = column
  if not column.isNil and column.tableView() != TableView(outlineView):
    TableView(outlineView).addColumn(column)
  TableView(outlineView).reloadData()

proc outlineDataSource*(outlineView: OutlineView): DynamicAgent =
  outlineView.xOutlineDataSource

proc `outlineDataSource=`*(outlineView: OutlineView, dataSource: DynamicAgent) =
  if outlineView.xOutlineDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(OutlineViewDataSource)
  outlineView.xOutlineDataSource = dataSource
  TableView(outlineView).reloadData()

proc `outlineDataSource=`*(outlineView: OutlineView, dataSource: Responder) =
  outlineView.outlineDataSource = DynamicAgent(dataSource)

proc outlineDelegate*(outlineView: OutlineView): DynamicAgent =
  outlineView.xOutlineDelegate

proc `outlineDelegate=`*(outlineView: OutlineView, delegate: DynamicAgent) =
  if outlineView.xOutlineDelegate == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(OutlineViewDelegate)
  outlineView.xOutlineDelegate = delegate

proc `outlineDelegate=`*(outlineView: OutlineView, delegate: Responder) =
  outlineView.outlineDelegate = DynamicAgent(delegate)

proc outlineItems*(outlineView: OutlineView): seq[OutlineItem] =
  outlineView.xOutlineItems

proc `outlineItems=`*(outlineView: OutlineView, items: openArray[OutlineItem]) =
  let selectedIdentifiers = outlineView.selectedItemIdentifiers()
  outlineView.xOutlineItems = @items
  var nextExpanded: seq[string]
  for identifier in outlineView.xExpanded:
    if outlineView.itemIndex(identifier) >= 0:
      nextExpanded.add identifier
  outlineView.xExpanded = nextExpanded
  TableView(outlineView).reloadData()
  outlineView.selectedItemIdentifiers = selectedIdentifiers

proc outlineItemIdentifiers*(outlineView: OutlineView): seq[string] =
  for item in outlineView.xOutlineItems:
    if item.identifier.len > 0:
      result.add item.identifier

proc visibleOutlineRows*(outlineView: OutlineView): seq[OutlineRow] =
  outlineView.appendVisibleRows("", 0, result)

proc rowCount*(outlineView: OutlineView): int =
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

proc selectedItemIdentifiersFromRows(outlineView: OutlineView): seq[string] =
  for row in TableView(outlineView).selectedIndexes():
    let identifier = outlineView.itemIdentifierForRow(row)
    if identifier.len > 0 and identifier notin result:
      result.add identifier

proc selectedItemIdentifiers*(outlineView: OutlineView): seq[string] =
  outlineView.selectedItemIdentifiersFromRows()

proc selectedItemIdentifier*(outlineView: OutlineView): string =
  let identifiers = outlineView.selectedItemIdentifiers()
  if identifiers.len > 0:
    identifiers[0]
  else:
    ""

proc `selectedItemIdentifiers=`*(
    outlineView: OutlineView, identifiers: openArray[string]
) =
  var
    rows: seq[int]
    selectedIdentifiers: seq[string]
  for identifier in identifiers:
    let row = outlineView.rowForItem(identifier)
    if row >= 0 and row notin rows:
      rows.add row
      selectedIdentifiers.add identifier
  outlineView.xSelectedIdentifiers = selectedIdentifiers
  TableView(outlineView).selectedIndexes = rows
  outlineView.xSelectedIdentifiers = outlineView.selectedItemIdentifiersFromRows()

proc `selectedItemIdentifier=`*(outlineView: OutlineView, identifier: string) =
  if identifier.len > 0:
    outlineView.selectedItemIdentifiers = [identifier]
  else:
    outlineView.selectedItemIdentifiers = []

proc selectItemWithIdentifier*(
    outlineView: OutlineView, identifier: string
): bool {.discardable.} =
  let row = outlineView.rowForItem(identifier)
  if row < 0:
    return false
  TableView(outlineView).selectedIndex = row
  outlineView.xSelectedIdentifiers = outlineView.selectedItemIdentifiersFromRows()
  true

proc reloadOutlineDataPreservingSelection(
    outlineView: OutlineView, selectedIdentifiers: openArray[string]
) =
  TableView(outlineView).reloadData()
  outlineView.selectedItemIdentifiers = selectedIdentifiers

proc localStorageIndexForChildIndex(
    outlineView: OutlineView, parentIdentifier: string, childIndex: int
): int =
  let target = max(childIndex, 0)
  var
    sibling = 0
    lastSiblingIndex = -1
  for index, item in outlineView.xOutlineItems:
    if item.parentIdentifier == parentIdentifier:
      if sibling == target:
        return index
      lastSiblingIndex = index
      inc sibling
  if lastSiblingIndex >= 0:
    lastSiblingIndex + 1
  else:
    outlineView.xOutlineItems.len

proc localDescendantIdentifiers(
    outlineView: OutlineView, identifier: string
): seq[string] =
  if identifier.len == 0:
    return
  for item in outlineView.xOutlineItems:
    if item.parentIdentifier == identifier:
      result.add item.identifier
      result.add outlineView.localDescendantIdentifiers(item.identifier)

proc addOutlineItem*(
    outlineView: OutlineView, item: OutlineItem
): bool {.discardable.} =
  let selectedIdentifiers = outlineView.selectedItemIdentifiers()
  outlineView.xOutlineItems.add item
  outlineView.reloadOutlineDataPreservingSelection(selectedIdentifiers)
  true

proc insertOutlineItem*(
    outlineView: OutlineView, item: OutlineItem, index: Natural
): bool {.discardable.} =
  let selectedIdentifiers = outlineView.selectedItemIdentifiers()
  let insertIndex = max(0, min(index.int, outlineView.xOutlineItems.len))
  outlineView.xOutlineItems.insert(item, insertIndex)
  outlineView.reloadOutlineDataPreservingSelection(selectedIdentifiers)
  true

proc insertOutlineChild*(
    outlineView: OutlineView,
    item: OutlineItem,
    parentIdentifier: string,
    index: Natural,
): bool {.discardable.} =
  let selectedIdentifiers = outlineView.selectedItemIdentifiers()
  var nextItem = item
  nextItem.parentIdentifier = parentIdentifier
  let storageIndex =
    outlineView.localStorageIndexForChildIndex(parentIdentifier, index.int)
  outlineView.xOutlineItems.insert(nextItem, storageIndex)
  outlineView.reloadOutlineDataPreservingSelection(selectedIdentifiers)
  true

proc removeOutlineItemWithIdentifier*(
    outlineView: OutlineView, identifier: string
): bool {.discardable.} =
  let index = outlineView.itemIndex(identifier)
  if index < 0:
    return false
  let selectedIdentifiers = outlineView.selectedItemIdentifiers()
  var removed = outlineView.localDescendantIdentifiers(identifier)
  removed.add identifier
  var nextItems: seq[OutlineItem]
  for item in outlineView.xOutlineItems:
    if item.identifier notin removed:
      nextItems.add item
  outlineView.xOutlineItems = nextItems
  var nextExpanded: seq[string]
  for expanded in outlineView.xExpanded:
    if expanded notin removed:
      nextExpanded.add expanded
  outlineView.xExpanded = nextExpanded
  outlineView.reloadOutlineDataPreservingSelection(selectedIdentifiers)
  true

proc removeAllOutlineItems*(outlineView: OutlineView) =
  outlineView.xOutlineItems.setLen(0)
  outlineView.xExpanded.setLen(0)
  outlineView.reloadOutlineDataPreservingSelection([])

proc moveOutlineItem*(
    outlineView: OutlineView, identifier, parentIdentifier: string, index: Natural
): bool {.discardable.} =
  let sourceIndex = outlineView.itemIndex(identifier)
  if sourceIndex < 0:
    return false
  let selectedIdentifiers = outlineView.selectedItemIdentifiers()
  var item = outlineView.xOutlineItems[sourceIndex]
  item.parentIdentifier = parentIdentifier
  outlineView.xOutlineItems.delete(sourceIndex)
  let storageIndex =
    outlineView.localStorageIndexForChildIndex(parentIdentifier, index.int)
  outlineView.xOutlineItems.insert(item, storageIndex)
  outlineView.reloadOutlineDataPreservingSelection(selectedIdentifiers)
  true

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
    return outlineView.xOutlineItems[index].outlineItemCanExpand(
      outlineView.hasChildren(identifier)
    )
  let item = outlineView.sourcedOutlineItem(identifier)
  item.outlineItemCanExpand(outlineView.hasChildren(identifier))

proc isItemExpanded*(outlineView: OutlineView, identifier: string): bool =
  outlineView.xExpanded.containsIdentifier(identifier)

proc outlineItemWithIdentifier*(
    outlineView: OutlineView, identifier: string
): OutlineItem =
  let index = outlineView.itemIndex(identifier)
  if index >= 0:
    return outlineView.xOutlineItems[index]
  outlineView.sourcedOutlineItem(identifier)

proc itemIdentifierForRow*(outlineView: OutlineView, row: int): string =
  outlineView.itemAtRow(row).identifier

proc parentIdentifierForItem*(outlineView: OutlineView, identifier: string): string =
  outlineView.outlineItemWithIdentifier(identifier).parentIdentifier

proc titleForItem*(outlineView: OutlineView, identifier: string): string =
  outlineView.outlineItemWithIdentifier(identifier).displayTitle()

proc objectValueForItem*(outlineView: OutlineView, identifier: string): ObjectValue =
  outlineView.outlineItemWithIdentifier(identifier).objectValue

proc valueForItem*(
    outlineView: OutlineView, identifier: string, columnIdentifier = ""
): ObjectValue =
  let item = outlineView.outlineItemWithIdentifier(identifier)
  item.getValue(columnIdentifier).get(emptyObjectValue())

proc tooltipForItem*(outlineView: OutlineView, identifier: string): string =
  outlineView.outlineItemWithIdentifier(identifier).tooltip

proc imageForItem*(outlineView: OutlineView, identifier: string): ImageResource =
  outlineView.outlineItemWithIdentifier(identifier).image

proc representedObjectForItem*(
    outlineView: OutlineView, identifier: string
): DynamicAgent =
  outlineView.outlineItemWithIdentifier(identifier).representedObject

proc childIdentifiersForItem*(
    outlineView: OutlineView, identifier: string
): seq[string] =
  for child in outlineView.childrenForParent(identifier):
    result.add child.identifier

proc levelForItem*(outlineView: OutlineView, identifier: string): int =
  outlineView.levelForRow(outlineView.rowForItem(identifier))

proc isItemVisible*(outlineView: OutlineView, identifier: string): bool =
  outlineView.rowForItem(identifier) >= 0

proc outlineItemIdentity*(
    outlineView: OutlineView, identifier: string
): OutlineItemIdentity =
  let
    item = outlineView.outlineItemWithIdentifier(identifier)
    row = outlineView.rowForItem(identifier)
  OutlineItemIdentity(
    identifier: item.identifier,
    parentIdentifier: item.parentIdentifier,
    row: row,
    level: outlineView.levelForRow(row),
    expandable: outlineView.isItemExpandable(identifier),
    expanded: outlineView.isItemExpanded(identifier),
    visible: row >= 0,
  )

proc expandItem*(outlineView: OutlineView, identifier: string) =
  if not outlineView.isItemExpandable(identifier):
    return
  if outlineView.xExpanded.containsIdentifier(identifier):
    return
  let delegate = outlineView.outlineDelegate()
  if not delegate.isNil:
    let allowed = delegate.trySendLocal(
      shouldExpandItem(), (outlineView: outlineView, identifier: identifier)
    )
    if allowed.isSome and not allowed.get():
      return
  outlineView.xExpanded.add identifier
  TableView(outlineView).reloadData()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didExpandItem(), (outlineView: outlineView, identifier: identifier)
    )
  outlineView.postAccessibilityNotification(anExpandedChanged)

proc collapseItem*(outlineView: OutlineView, identifier: string) =
  let delegate = outlineView.outlineDelegate()
  if not delegate.isNil:
    let allowed = delegate.trySendLocal(
      shouldCollapseItem(), (outlineView: outlineView, identifier: identifier)
    )
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
  outlineView.postAccessibilityNotification(anExpandedChanged)

proc toggleItem*(outlineView: OutlineView, identifier: string) =
  if outlineView.isItemExpanded(identifier):
    outlineView.collapseItem(identifier)
  else:
    outlineView.expandItem(identifier)

proc expandedItemIdentifiers*(outlineView: OutlineView): seq[string] =
  outlineView.xExpanded

proc `expandedItemIdentifiers=`*(
    outlineView: OutlineView, identifiers: openArray[string]
) =
  let previous = outlineView.xExpanded
  outlineView.xExpanded = @identifiers
  if outlineView.xExpanded == previous:
    return
  TableView(outlineView).reloadData()
  outlineView.postAccessibilityNotification(anExpandedChanged)

proc expansionPersistenceString*(outlineView: OutlineView): string =
  outlineView.xExpanded.join(",")

proc restoreExpansionPersistenceString*(outlineView: OutlineView, value: string) =
  if value.len == 0:
    outlineView.xExpanded.setLen(0)
  else:
    outlineView.xExpanded = value.split(",")
  TableView(outlineView).reloadData()

proc disclosureRectInRowBounds(
    outlineView: OutlineView, row: int, rowBounds: Rect
): Rect =
  let item = outlineView.itemAtRow(row)
  if item.identifier.len == 0 or not outlineView.isItemExpandable(item.identifier):
    return rect(0.0, 0.0, 0.0, 0.0)
  let
    level = outlineView.levelForRow(row)
    size = min(rowBounds.size.height, OutlineDisclosureMaxSize)
  rect(
    rowBounds.origin.x + level.float32 * OutlineIndentStep + OutlineDisclosureLeading,
    rowBounds.origin.y + max((rowBounds.size.height - size) * 0.5'f32, 0.0'f32),
    size,
    size,
  )

proc disclosureRectForRow*(outlineView: OutlineView, row: int): Rect =
  outlineView.disclosureRectInRowBounds(row, TableView(outlineView).rowItemRect(row))

proc disclosureHitTest*(outlineView: OutlineView, point: Point): OutlineDisclosureHit =
  for row in 0 ..< outlineView.rowCount():
    let rect = outlineView.disclosureRectForRow(row)
    if rect.contains(point):
      return
        OutlineDisclosureHit(row: row, item: outlineView.itemAtRow(row), rect: rect)
  OutlineDisclosureHit(row: -1)

proc toggleItemAtPoint*(outlineView: OutlineView, point: Point): bool =
  let hit = outlineView.disclosureHitTest(point)
  if hit.row < 0 or hit.item.identifier.len == 0:
    return false
  outlineView.toggleItem(hit.item.identifier)
  true

proc disclosureMouseDown*(outlineView: OutlineView, event: MouseEvent): bool =
  if event.button != mbPrimary:
    return false
  let hit = outlineView.disclosureHitTest(event.location)
  if hit.row < 0 or hit.item.identifier.len == 0:
    return false
  outlineView.xTrackingDisclosureRow = hit.row
  outlineView.xTrackingDisclosureIdentifier = hit.item.identifier
  outlineView.xPressedDisclosureRow = hit.row
  outlineView.needsDisplay = true
  true

proc disclosureMouseUp*(outlineView: OutlineView, event: MouseEvent): bool =
  if outlineView.xTrackingDisclosureRow < 0:
    return false
  let
    trackingIdentifier = outlineView.xTrackingDisclosureIdentifier
    hit = outlineView.disclosureHitTest(event.location)
    clicked =
      hit.row == outlineView.xTrackingDisclosureRow and
      hit.item.identifier == trackingIdentifier
  outlineView.xTrackingDisclosureRow = -1
  outlineView.xTrackingDisclosureIdentifier = ""
  outlineView.xPressedDisclosureRow = -1
  if clicked:
    outlineView.toggleItem(trackingIdentifier)
  outlineView.needsDisplay = true
  true

proc handleOutlineKey*(outlineView: OutlineView, event: KeyEvent): bool =
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
    operations: DragOperations = {dgoMove},
    pasteboardName = DragPasteboardName,
): DraggingSession =
  var rows: seq[int]
  for identifier in identifiers:
    let row = outlineView.rowForItem(identifier)
    if row >= 0:
      rows.add row
  TableView(outlineView).beginDraggingRows(rows, operations, pasteboardName)

proc dropTargetForDraggingLocation*(
    outlineView: OutlineView, location: Point
): DraggingDropTarget =
  var proposedTarget = initDraggingDropTarget()
  let row = TableView(outlineView).rowItemIndexAtPoint(location)
  if row >= 0:
    let item = outlineView.itemAtRow(row)
    if item.identifier.len > 0:
      proposedTarget = initItemDropTarget(
        item.identifier, row, TableView(outlineView).rowItemRect(row)
      )
      let delegate = outlineView.outlineDelegate()
      if not delegate.isNil:
        let itemTarget = delegate.trySendLocal(
          dropTargetForOutlineItem(),
          (
            outlineView: outlineView,
            identifier: item.identifier,
            row: row,
            proposedTarget: proposedTarget,
          ),
        )
        if itemTarget.isSome:
          return itemTarget.get()
  let delegate = outlineView.outlineDelegate()
  if not delegate.isNil:
    let resolved = delegate.trySendLocal(
      outlineDropTargetForLocation(),
      (outlineView: outlineView, location: location, proposedTarget: proposedTarget),
    )
    if resolved.isSome:
      return resolved.get()
  proposedTarget

proc outlineCellObjectValue(
    outlineView: OutlineView, row: int, column: TableColumn
): ObjectValue =
  if column.isNil:
    return nilObjectValue()
  let item = outlineView.itemAtRow(row)
  if item.identifier.len == 0:
    return nilObjectValue()
  if column == outlineView.outlineColumn():
    if item.title.len > 0:
      return toObj(item.title)
    if item.objectValue.kind notin {ovNil, ovEmpty}:
      return item.objectValue
    return toObj(item.identifier)
  item.getValue(column.identifier()).get(emptyObjectValue())

proc setOutlineCellObjectValue(
    outlineView: OutlineView, row: int, column: TableColumn, value: ObjectValue
): bool =
  if column.isNil:
    return false
  let item = outlineView.itemAtRow(row)
  if item.identifier.len == 0:
    return false
  let index = outlineView.itemIndex(item.identifier)
  if index < 0:
    return false
  if column == outlineView.outlineColumn():
    outlineView.xOutlineItems[index].title =
      value.formatObjectValue(initObjectFormatContext(role = ovrTableCell))
    outlineView.xOutlineItems[index].objectValue = value
  else:
    outlineView.xOutlineItems[index].setValue(column.identifier(), value)
  TableView(outlineView).reloadRowsAtIndexes([row], [item.identifier])
  true

proc outlineCellText(outlineView: OutlineView, row: int, column: TableColumn): string =
  let rows = outlineView.visibleOutlineRows()
  if row notin 0 ..< rows.len or column.isNil:
    return ""
  let item = rows[row].item
  if column == outlineView.outlineColumn():
    return item.displayTitle()
  let value = item.getValue(column.identifier()).get(emptyObjectValue())
  value.formatObjectValue(initObjectFormatContext(role = ovrTableCell))

proc parseOutlineCellValue(
    outlineView: OutlineView,
    tableView: TableView,
    row: int,
    column: TableColumn,
    value: string,
): ObjectParseResult =
  let current = outlineView.outlineCellObjectValue(row, column)
  let expectedKind = if current.kind in {ovNil, ovEmpty}: ovString else: current.kind
  let context =
    Control(tableView).objectParseContext.expecting(expectedKind).withRole(ovrTableCell)
  Control(tableView).objectValueFormatter.parseObjectValue(value, context)

proc disclosureAccessibilityElementForRow*(
    outlineView: OutlineView, row: int
): OutlineAccessibilityElement =
  let item = outlineView.itemAtRow(row)
  if item.identifier.len == 0 or not outlineView.isItemExpandable(item.identifier):
    return OutlineAccessibilityElement(row: -1)
  let action =
    if outlineView.isItemExpanded(item.identifier):
      AccessibilityActionCollapse
    else:
      AccessibilityActionExpand
  OutlineAccessibilityElement(
    role: arDisclosureButton,
    row: row,
    identifier: item.identifier & ".disclosure",
    label: item.displayTitle(),
    frame: outlineView.disclosureRectForRow(row),
    level: outlineView.levelForRow(row),
    expanded: outlineView.isItemExpanded(item.identifier),
    selected: TableView(outlineView).selectedIndex() == row,
    action: action,
  )

proc outlineAccessibilityElementForRow*(
    outlineView: OutlineView, row: int
): OutlineAccessibilityElement =
  let item = outlineView.itemAtRow(row)
  if item.identifier.len == 0:
    return OutlineAccessibilityElement(row: -1)
  OutlineAccessibilityElement(
    role: arOutlineRow,
    row: row,
    identifier: item.identifier,
    label: item.displayTitle(),
    frame: TableView(outlineView).rowItemRect(row),
    level: outlineView.levelForRow(row),
    expanded: outlineView.isItemExpanded(item.identifier),
    selected: TableView(outlineView).selectedIndex() == row,
  )

proc outlineAccessibilityElements*(
    outlineView: OutlineView
): seq[OutlineAccessibilityElement] =
  for row in 0 ..< outlineView.rowCount():
    result.add outlineView.outlineAccessibilityElementForRow(row)
    let disclosure = outlineView.disclosureAccessibilityElementForRow(row)
    if disclosure.row >= 0:
      result.add disclosure

proc outlineModelDidChange*(outlineView: OutlineView, sender: DynamicAgent) {.slot.} =
  discard sender
  let selectedIdentifiers =
    if outlineView.xSelectedIdentifiers.len > 0:
      outlineView.xSelectedIdentifiers
    else:
      outlineView.selectedItemIdentifiers()
  TableView(outlineView).reloadData()
  outlineView.selectedItemIdentifiers = selectedIdentifiers

proc outlineSelectionDidChange*(
    outlineView: OutlineView, sender: DynamicAgent
) {.slot.} =
  discard sender
  outlineView.xSelectedIdentifiers = outlineView.selectedItemIdentifiersFromRows()

proc drawDisclosureAffordance(
    outlineView: OutlineView, context: DrawContext, row: int, rect: Rect
) =
  if context.isNil or rect.isEmpty:
    return
  let
    item = outlineView.itemAtRow(row)
    pressed = row == outlineView.xPressedDisclosureRow
    expanded = outlineView.isItemExpanded(item.identifier)
    color = color(0.22, 0.26, 0.32, 1.0)
    borderAlpha = if pressed: 1.0'f32 else: 0.42'f32
    shellFill =
      if pressed:
        color(0.74, 0.80, 0.90, 1.0)
      else:
        color(0.0, 0.0, 0.0, 0.0)
    shell = rect.inset(insets(2.0'f32))
  discard context.addRenderRectangle(
    context.renderRectFor(shell),
    fill(shellFill),
    color(0.48, 0.54, 0.64, borderAlpha),
    if pressed: 1.0'f32 else: 0.6'f32,
    3.0'f32,
  )
  let
    centerX = rect.origin.x + rect.size.width * 0.5'f32
    centerY = rect.origin.y + rect.size.height * 0.5'f32
  if expanded:
    for index in 0 .. 2:
      let width = 7.0'f32 - index.float32 * 2.0'f32
      discard context.addRenderRectangle(
        context.renderRectFor(
          rect(
            centerX - width * 0.5'f32, centerY - 2.0'f32 + index.float32, width, 1.0'f32
          )
        ),
        fill(color),
      )
  else:
    for index in 0 .. 2:
      let height = 7.0'f32 - index.float32 * 2.0'f32
      discard context.addRenderRectangle(
        context.renderRectFor(
          rect(
            centerX - 1.0'f32 + index.float32,
            centerY - height * 0.5'f32,
            1.0'f32,
            height,
          )
        ),
        fill(color),
      )

proc drawOutlineDisclosures*(outlineView: OutlineView, context: DrawContext) =
  if context.isNil:
    return
  for row in 0 ..< outlineView.rowCount():
    let rect = outlineView.disclosureRectForRow(row)
    if not rect.isEmpty:
      outlineView.drawDisclosureAffordance(context, row, rect)

proc outlineColumnRectForRow(
    outlineView: OutlineView, column: TableColumn, rowBounds: Rect
): Rect =
  if column.isNil:
    return rect(0.0, 0.0, 0.0, 0.0)
  var x = rowBounds.origin.x
  for current in TableView(outlineView).columns():
    if not current.hidden():
      let rect = rect(x, rowBounds.origin.y, current.width(), rowBounds.size.height)
      if current == column:
        return rect
      x += current.width()
  rect(0.0, 0.0, 0.0, 0.0)

proc outlineTextRectForCellFrame(
    outlineView: OutlineView, row: int, column: TableColumn, cellFrame: Rect
): Rect =
  result = cellFrame
  if result.isEmpty:
    return
  if column == outlineView.outlineColumn():
    let indent =
      outlineView.levelForRow(row).float32 * OutlineIndentStep + OutlineTextLeading
    result.x += indent
    result.w = max(result.w - indent - OutlineTextTrailing, 0.0'f32)
  else:
    result.x += 6.0'f32
    result.w = max(result.w - 12.0'f32, 0.0'f32)

proc outlineTextRectForCell(
    outlineView: OutlineView, row: int, column: TableColumn, rowBounds: Rect
): Rect =
  outlineView.outlineTextRectForCellFrame(
    row, column, outlineView.outlineColumnRectForRow(column, rowBounds)
  )

proc drawOutlineRowText(
    outlineView: OutlineView, context: DrawContext, row: RowState, rowBounds: Rect
) =
  if context.isNil or row.index < 0:
    return
  let
    tableView = TableView(outlineView)
    editing = tableView.editingState()
    textStyle = context.appearance.resolveRowItemStyle(
      controlStyle(
        srRowItem,
        row.states,
        id = outlineView.styleId(),
        classes = outlineView.styleClasses(),
      )
    ).text
  for column in tableView.columns():
    let isEditingCell =
      editing.active and editing.row == row.index and editing.column == column
    if not column.hidden() and not isEditingCell:
      let
        text = outlineView.outlineCellText(row.index, column)
        textRect = outlineView.outlineTextRectForCell(row.index, column, rowBounds)
      if text.len > 0 and not textRect.isEmpty:
        let textRoot = context.addRenderRectangle(
          context.renderRectFor(textRect), fill(color(0.0, 0.0, 0.0, 0.0)), clips = true
        )
        discard context.addText(
          DefaultDrawLevel,
          textRoot,
          textRect,
          clippedText(text, textRect.size.width, textStyle),
          textStyle,
          column.alignment(),
        )

proc drawOutlineDropTarget(
    outlineView: OutlineView, context: DrawContext, row: int, rowBounds: Rect
) =
  if context.isNil or row < 0:
    return
  let target = TableView(outlineView).currentDropTarget()
  if target.kind notin {ddtItem, ddtRow, ddtCell} or target.row != row:
    return
  let indicatorRect = rect(
    rowBounds.origin.x,
    max(rowBounds.maxY - 2.0'f32, rowBounds.minY),
    rowBounds.size.width,
    2.0,
  )
  let indicatorFill = context.appearance.resolveFill(
    controlStyle(
      TableView(outlineView).tableRole(),
      outlineView.widgetStateSet(),
      id = outlineView.styleId(),
      classes = outlineView.styleClasses(),
    ),
    fill(color(0.18, 0.42, 0.88, 0.95)),
    StyleDropIndicatorFill,
  )
  discard context.addRenderRectangle(indicatorRect, indicatorFill)

protocol OutlineViewDrawing of ViewDrawingProtocol:
  method draw(outlineView: OutlineView, context: DrawContext) =
    if context.isNil or outlineView.bounds().isEmpty:
      return
    let
      tableView = TableView(outlineView)
      style = context.appearance.resolveTableViewStyle(
        controlStyle(
          tableView.tableRole(),
          outlineView.widgetStateSet(),
          id = outlineView.styleId(),
          classes = outlineView.styleClasses(),
        )
      )
    discard context.addRenderRectangle(
      context.renderRectFor(outlineView.bounds()),
      style.box.fill,
      style.box.borderColor,
      style.box.borderWidth,
      style.box.cornerRadius,
      style.box.shadows,
      clips = true,
    )
    tableView.drawTableHeader(context)

protocol OutlineViewEvents of ResponderEventProtocol:
  method keyDown(outlineView: OutlineView, event: KeyEvent): bool =
    case event.key
    of keyArrowLeft, keyArrowRight:
      if outlineView.handleOutlineKey(event):
        return true
    else:
      discard
    let next = outlineView.performNext(keyDown, event)
    if next.isSome:
      next.get()
    else:
      false

  method mouseDown(outlineView: OutlineView, event: MouseEvent): bool =
    if outlineView.disclosureMouseDown(event):
      return true
    let next = outlineView.performNext(mouseDown, event)
    if next.isSome:
      next.get()
    else:
      false

  method mouseDragged(outlineView: OutlineView, event: MouseEvent): bool =
    if outlineView.xTrackingDisclosureRow >= 0:
      let hit = outlineView.disclosureHitTest(event.location)
      outlineView.xPressedDisclosureRow =
        if hit.row == outlineView.xTrackingDisclosureRow and
            hit.item.identifier == outlineView.xTrackingDisclosureIdentifier:
          hit.row
        else:
          -1
      outlineView.needsDisplay = true
      return true
    let session = TableView(outlineView).draggingSession()
    if not session.isNil and session.state() == dssActive:
      let target = outlineView.dropTargetForDraggingLocation(event.location)
      discard updateDraggingSession(
        session, event.location, DynamicAgent(outlineView), target
      )
      outlineView.needsDisplay = true
      discard autoscrollDraggingSession(
        session, event.location, DynamicAgent(outlineView), target
      )
      return true
    let next = outlineView.performNext(mouseDragged, event)
    if next.isSome:
      next.get()
    else:
      false

  method mouseUp(outlineView: OutlineView, event: MouseEvent): bool =
    if outlineView.disclosureMouseUp(event):
      return true
    let next = outlineView.performNext(mouseUp, event)
    if next.isSome:
      next.get()
    else:
      false

protocol OutlineViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(outlineView: OutlineView): AccessibilityRole =
    arOutline

  method accessibilityLabel(outlineView: OutlineView): string =
    if outlineView.xAccessibilityLabel.len > 0:
      outlineView.xAccessibilityLabel
    else:
      outlineView.xIdentifier

  method accessibilityValue(outlineView: OutlineView): string =
    $outlineView.rowCount()

protocol OutlineViewStateBehavior of TableViewStateProtocol:
  method captureState(outlineView: OutlineView): TableViewState =
    var selectedColumns: seq[string]
    for column in TableView(outlineView).selectedColumns():
      if not column.isNil:
        selectedColumns.add column.identifier()
    initTableViewState(
      TableView(outlineView).columnAutosaveRecords(),
      TableView(outlineView).selectedIndexes(),
      selectedColumns,
      outlineView.expandedItemIdentifiers(),
      selectedRowIdentifiers = outlineView.selectedItemIdentifiers(),
    )

  method restoreState(outlineView: OutlineView, state: TableViewState) =
    TableView(outlineView).restoreColumnAutosaveRecords(state.columns)
    if state.selectedRowIdentifiers.len > 0:
      outlineView.selectedItemIdentifiers = state.selectedRowIdentifiers
      if outlineView.selectedItemIdentifiers().len == 0:
        TableView(outlineView).selectedIndexes = state.selectedRows
    else:
      TableView(outlineView).selectedIndexes = state.selectedRows
    if TableView(outlineView).allowsColumnSelection():
      var columns: seq[TableColumn]
      for identifier in state.selectedColumns:
        let column = TableView(outlineView).columnWithIdentifier(identifier)
        if not column.isNil:
          columns.add column
      TableView(outlineView).selectedColumns = columns
    outlineView.expandedItemIdentifiers = state.expandedItems

protocol OutlineViewTableDelegate of TableViewDelegate:
  method isRowEnabled(outlineView: OutlineView, tableView: TableView, row: int): bool =
    discard tableView
    outlineView.itemAtRow(row).enabled

  method fieldEditorFrameForCell(
      outlineView: OutlineView,
      tableView: TableView,
      row: int,
      column: TableColumn,
      proposedFrame: Rect,
  ): Rect =
    discard tableView
    outlineView.outlineTextRectForCellFrame(row, column, proposedFrame)

  method parseObjectValueForCell(
      outlineView: OutlineView,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ): ObjectParseResult =
    outlineView.parseOutlineCellValue(tableView, row, column, value)

  method drawRow(
      outlineView: OutlineView,
      tableView: TableView,
      context: DrawContext,
      rect: Rect,
      row: RowState,
  ) =
    let emptyRow = initRowState(row.index, "", states = row.states)
    TableView(outlineView).drawTableRowItem(context, rect, emptyRow)
    if row.index < 0:
      return
    let rowBounds = rect(0.0, 0.0, rect.size.width, rect.size.height)
    let disclosure = outlineView.disclosureRectInRowBounds(row.index, rowBounds)
    if not disclosure.isEmpty:
      outlineView.drawDisclosureAffordance(context, row.index, disclosure)
    outlineView.drawOutlineRowText(context, row, rowBounds)
    outlineView.drawOutlineDropTarget(context, row.index, rowBounds)

protocol OutlineViewTableDataSource of TableViewDataSource:
  method numberOfRows(outlineView: OutlineView, tableView: TableView): int =
    outlineView.visibleOutlineRows().len

  method objectValueForCell(
      outlineView: OutlineView, tableView: TableView, row: int, column: TableColumn
  ): ObjectValue =
    discard tableView
    outlineView.outlineCellObjectValue(row, column)

  method setObjectValueForCell(
      outlineView: OutlineView,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: ObjectValue,
  ): bool =
    discard tableView
    outlineView.setOutlineCellObjectValue(row, column, value)

  method textForCell(
      outlineView: OutlineView, tableView: TableView, row: int, column: TableColumn
  ): string =
    discard tableView
    outlineView.outlineCellText(row, column)

  method identifierForRow(
      outlineView: OutlineView, tableView: TableView, row: int
  ): string =
    discard tableView
    outlineView.itemIdentifierForRow(row)

  method rowForIdentifier(
      outlineView: OutlineView, tableView: TableView, identifier: string
  ): int =
    discard tableView
    outlineView.rowForItem(identifier)

proc initOutlineViewFields*(outlineView: OutlineView, frame: Rect = AutoRect) =
  initTableViewFields(TableView(outlineView), frame)
  outlineView.xTrackingDisclosureRow = -1
  outlineView.xPressedDisclosureRow = -1
  let column = newTableColumn("outline", "Outline", width = 220.0)
  outlineView.xOutlineColumn = column
  TableView(outlineView).addColumn(column)
  discard outlineView.withProtocol(OutlineViewTableDataSource)
  discard outlineView.withProtocol(OutlineViewTableDelegate)
  discard outlineView.withProtocol(OutlineViewDrawing)
  discard DynamicAgent(outlineView).pushMethods(OutlineViewEvents.init())
  discard outlineView.withProtocol(OutlineViewAccessibility)
  discard outlineView.withProtocol(OutlineViewStateBehavior)
  TableView(outlineView).dataSource = DynamicAgent(outlineView)
  TableView(outlineView).delegate = DynamicAgent(outlineView)
  outlineView.connect(selectionDidChange, outlineView, outlineSelectionDidChange)

proc newOutlineView*(frame: Rect = AutoRect): OutlineView =
  result = OutlineView()
  initOutlineViewFields(result, frame)
