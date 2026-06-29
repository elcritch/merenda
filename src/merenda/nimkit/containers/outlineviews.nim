import std/[options, strutils]

import sigils/core

import ./listbasics
import ./tableviews
import ../accessibility/accessibilityprotocols
import ../app/dragging
import ../app/pasteboards
import ../drawing
import ../themes
import ../foundation/events
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
    expandable*: bool

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
  if outlineView.isNil:
    return -1
  for index, item in outlineView.xOutlineItems:
    if item.identifier == identifier:
      return index
  -1

proc isItemExpanded*(outlineView: OutlineView, identifier: string): bool
proc outlineItemWithIdentifier*(
  outlineView: OutlineView, identifier: string
): OutlineItem

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

proc childrenForParent(
    outlineView: OutlineView, parentIdentifier: string
): seq[OutlineItem] =
  if outlineView.isNil:
    return @[]
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
    identifier: string, title: string, parentIdentifier = "", expandable = false
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
  if outlineView.isNil:
    @[]
  else:
    outlineView.xOutlineItems

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
    return
      outlineView.xOutlineItems[index].expandable or outlineView.hasChildren(identifier)
  let item = outlineView.sourcedOutlineItem(identifier)
  item.expandable or outlineView.hasChildren(identifier)

proc isItemExpanded*(outlineView: OutlineView, identifier: string): bool =
  (not outlineView.isNil) and outlineView.xExpanded.containsIdentifier(identifier)

proc outlineItemWithIdentifier*(
    outlineView: OutlineView, identifier: string
): OutlineItem =
  if outlineView.isNil:
    return OutlineItem()
  let index = outlineView.itemIndex(identifier)
  if index >= 0:
    return outlineView.xOutlineItems[index]
  outlineView.sourcedOutlineItem(identifier)

proc itemIdentifierForRow*(outlineView: OutlineView, row: int): string =
  outlineView.itemAtRow(row).identifier

proc parentIdentifierForItem*(outlineView: OutlineView, identifier: string): string =
  outlineView.outlineItemWithIdentifier(identifier).parentIdentifier

proc titleForItem*(outlineView: OutlineView, identifier: string): string =
  outlineView.outlineItemWithIdentifier(identifier).title

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
  if outlineView.isNil or not outlineView.isItemExpandable(identifier):
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
  if outlineView.isNil:
    return
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
  if outlineView.isNil:
    @[]
  else:
    outlineView.xExpanded

proc `expandedItemIdentifiers=`*(
    outlineView: OutlineView, identifiers: openArray[string]
) =
  if outlineView.isNil:
    return
  let previous = outlineView.xExpanded
  outlineView.xExpanded = @identifiers
  if outlineView.xExpanded == previous:
    return
  TableView(outlineView).reloadData()
  outlineView.postAccessibilityNotification(anExpandedChanged)

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
    rowRect = TableView(outlineView).rowItemRect(row)
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
  if outlineView.isNil or event.button != mbPrimary:
    return false
  let hit = outlineView.disclosureHitTest(event.location)
  if hit.row < 0 or hit.item.identifier.len == 0:
    return false
  outlineView.xTrackingDisclosureRow = hit.row
  outlineView.xTrackingDisclosureIdentifier = hit.item.identifier
  outlineView.xPressedDisclosureRow = hit.row
  outlineView.setNeedsDisplay(true)
  true

proc disclosureMouseUp*(outlineView: OutlineView, event: MouseEvent): bool =
  if outlineView.isNil or outlineView.xTrackingDisclosureRow < 0:
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
  outlineView.setNeedsDisplay(true)
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
    operations: DragOperations = {dgoMove},
    pasteboardName = DragPasteboardName,
): DraggingSession =
  if outlineView.isNil:
    return nil
  var rows: seq[int]
  for identifier in identifiers:
    let row = outlineView.rowForItem(identifier)
    if row >= 0:
      rows.add row
  TableView(outlineView).beginDraggingRows(rows, operations, pasteboardName)

proc dropTargetForDraggingLocation*(
    outlineView: OutlineView, location: Point
): DraggingDropTarget =
  if outlineView.isNil:
    return initDraggingDropTarget()
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

proc outlineCellText(outlineView: OutlineView, row: int, column: TableColumn): string =
  let rows = outlineView.visibleOutlineRows()
  if row notin 0 ..< rows.len:
    return ""
  let outlineRow = rows[row]
  outlineRow.item.title

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
    label: item.title,
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
    label: item.title,
    frame: TableView(outlineView).rowItemRect(row),
    level: outlineView.levelForRow(row),
    expanded: outlineView.isItemExpanded(item.identifier),
    selected: TableView(outlineView).selectedIndex() == row,
  )

proc outlineAccessibilityElements*(
    outlineView: OutlineView
): seq[OutlineAccessibilityElement] =
  if outlineView.isNil:
    return @[]
  for row in 0 ..< outlineView.rowCount():
    result.add outlineView.outlineAccessibilityElementForRow(row)
    let disclosure = outlineView.disclosureAccessibilityElementForRow(row)
    if disclosure.row >= 0:
      result.add disclosure

proc drawDisclosureAffordance(
    outlineView: OutlineView, context: DrawContext, row: int, rect: Rect
) =
  if outlineView.isNil or context.isNil or rect.isEmpty:
    return
  let
    item = outlineView.itemAtRow(row)
    pressed = row == outlineView.xPressedDisclosureRow
    expanded = outlineView.isItemExpanded(item.identifier)
    color = initColor(0.22, 0.26, 0.32, 1.0)
    borderAlpha = if pressed: 1.0'f32 else: 0.42'f32
    shellFill =
      if pressed:
        initColor(0.74, 0.80, 0.90, 1.0)
      else:
        initColor(0.0, 0.0, 0.0, 0.0)
    shell = rect.inset(insets(2.0'f32))
  discard context.addRenderRectangle(
    context.renderRectFor(shell),
    fill(shellFill),
    initColor(0.48, 0.54, 0.64, borderAlpha),
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
          initRect(
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
          initRect(
            centerX - 1.0'f32 + index.float32,
            centerY - height * 0.5'f32,
            1.0'f32,
            height,
          )
        ),
        fill(color),
      )

proc drawOutlineDisclosures*(outlineView: OutlineView, context: DrawContext) =
  if outlineView.isNil or context.isNil:
    return
  for row in 0 ..< outlineView.rowCount():
    let rect = outlineView.disclosureRectForRow(row)
    if not rect.isEmpty:
      outlineView.drawDisclosureAffordance(context, row, rect)

proc outlineColumnRectForRow(
    outlineView: OutlineView, column: TableColumn, rowBounds: Rect
): Rect =
  if outlineView.isNil or column.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  var x = rowBounds.origin.x
  for current in TableView(outlineView).columns():
    if current.hidden():
      continue
    let rect = initRect(x, rowBounds.origin.y, current.width(), rowBounds.size.height)
    if current == column:
      return rect
    x += current.width()
  initRect(0.0, 0.0, 0.0, 0.0)

proc outlineTextRectForCell(
    outlineView: OutlineView, row: int, column: TableColumn, rowBounds: Rect
): Rect =
  result = outlineView.outlineColumnRectForRow(column, rowBounds)
  if result.isEmpty:
    return
  if column == outlineView.outlineColumn():
    let indent = outlineView.levelForRow(row).float32 * 16.0'f32 + 24.0'f32
    result.origin.x += indent
    result.size.width = max(result.size.width - indent - 6.0'f32, 0.0'f32)
  else:
    result.origin.x += 6.0'f32
    result.size.width = max(result.size.width - 12.0'f32, 0.0'f32)

proc drawOutlineRowText(
    outlineView: OutlineView, context: DrawContext, row: int, rowBounds: Rect
) =
  if outlineView.isNil or context.isNil or row < 0:
    return
  for column in TableView(outlineView).columns():
    if column.hidden():
      continue
    let
      text = outlineView.outlineCellText(row, column)
      textRect = outlineView.outlineTextRectForCell(row, column, rowBounds)
      textStyle = context.appearance.resolveTextStyle(
        controlStyle(srRowItem), initColor(0.14, 0.18, 0.25, 1.0), insets(0.0)
      )
    if text.len > 0 and not textRect.isEmpty:
      discard context.addText(textRect, text, textStyle, column.alignment())

proc drawOutlineDropTarget(
    outlineView: OutlineView, context: DrawContext, row: int, rowBounds: Rect
) =
  if outlineView.isNil or context.isNil or row < 0:
    return
  let target = TableView(outlineView).currentDropTarget()
  if target.kind notin {ddtItem, ddtRow, ddtCell} or target.row != row:
    return
  let indicatorRect = initRect(
    rowBounds.origin.x,
    max(rowBounds.maxY - 2.0'f32, rowBounds.minY),
    rowBounds.size.width,
    2.0,
  )
  discard
    context.addRenderRectangle(indicatorRect, fill(initColor(0.18, 0.42, 0.88, 0.95)))

protocol OutlineViewDrawing of ViewDrawingProtocol:
  method draw(outlineView: OutlineView, context: DrawContext) =
    if outlineView.isNil or context.isNil or outlineView.bounds().isEmpty:
      return
    discard context.addRenderRectangle(
      context.renderRectFor(outlineView.bounds()),
      fill(initColor(0.98, 0.985, 0.995, 1.0)),
      initColor(0.66, 0.68, 0.73, 1.0),
      1.0'f32,
      0.0'f32,
      clips = true,
    )
    TableView(outlineView).drawTableHeader(context)

protocol OutlineViewEvents of ResponderEventProtocol:
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
      outlineView.setNeedsDisplay(true)
      return true
    let session = TableView(outlineView).draggingSession()
    if not session.isNil and session.state() == dssActive:
      let target = outlineView.dropTargetForDraggingLocation(event.location)
      discard updateDraggingSession(
        session, event.location, DynamicAgent(outlineView), target
      )
      outlineView.setNeedsDisplay(true)
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
    if outlineView.isNil:
      return initTableViewState()
    var selectedColumns: seq[string]
    for column in TableView(outlineView).selectedColumns():
      if not column.isNil:
        selectedColumns.add column.identifier()
    initTableViewState(
      TableView(outlineView).columnAutosaveRecords(),
      TableView(outlineView).selectedIndexes(),
      selectedColumns,
      outlineView.expandedItemIdentifiers(),
    )

  method restoreState(outlineView: OutlineView, state: TableViewState) =
    if outlineView.isNil:
      return
    TableView(outlineView).restoreColumnAutosaveRecords(state.columns)
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
    let rowBounds = initRect(0.0, 0.0, rect.size.width, rect.size.height)
    let disclosure = outlineView.disclosureRectForRow(row.index)
    if not disclosure.isEmpty:
      let localDisclosure = initRect(
        disclosure.origin.x - rect.origin.x,
        disclosure.origin.y - rect.origin.y,
        disclosure.size.width,
        disclosure.size.height,
      )
      outlineView.drawDisclosureAffordance(context, row.index, localDisclosure)
    outlineView.drawOutlineRowText(context, row.index, rowBounds)
    outlineView.drawOutlineDropTarget(context, row.index, rowBounds)

protocol OutlineViewTableDataSource of TableViewDataSource:
  method numberOfRows(outlineView: OutlineView, tableView: TableView): int =
    outlineView.visibleOutlineRows().len

  method textForCell(
      outlineView: OutlineView, tableView: TableView, row: int, column: TableColumn
  ): string =
    outlineView.outlineCellText(row, column)

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

proc newOutlineView*(frame: Rect = AutoRect): OutlineView =
  result = OutlineView()
  initOutlineViewFields(result, frame)
