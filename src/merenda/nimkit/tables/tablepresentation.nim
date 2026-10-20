## Table layout, drawing, and column presentation.
## Cell editing lives in tablecells; coordinated input lives in tableviews.

import std/[math, options, tables]

from figdraw import FigIdx
import sigils/core

import ../accessibility/accessibilityprotocols
import ../drawing
import ../app/dragging
import ../controls/controls
import ../containers/listbasics
import ../containers/scrollviews
import ../foundation/events
import ../foundation/selectors
import ../themes
import ../themes/themecore as themeCore
import ../foundation/types
import ../foundation/undomanagers
from ../view/viewgeometry import setFrameFromLayout
import ../view/views

import ./tablecore
import ./tableselection
import ./private/tablecoordination

proc `columnSizing=`*(tableView: TableView, sizing: TableViewColumnSizing)
proc `preferredContentWidth=`*(tableView: TableView, width: float32)
proc layoutTableContent(tableView: TableView)
proc syncVisibleTableCells(tableView: TableView)
proc drawTableDropTarget(
  tableView: TableView, context: DrawContext, rect: Rect, row: RowState
)

proc noteColumnsChanged*(tableView: TableView)
proc syncTableScrollChrome*(tableView: TableView)
proc removeColumnAtIndex(tableView: TableView, index: int)
proc removeColumnAt*(tableView: TableView, index: int)
proc removeColumn*(tableView: TableView, column: TableColumn)
proc removeColumn*(tableView: TableView, identifier: string)
proc syncVisibleRowViews(contentView: TableContentView)
proc drawTableRowItem*(
  tableView: TableView, context: DrawContext, rect: Rect, row: RowState
)

proc initTableRowView(tableView: TableView): TableRowView
proc drawTableHeader*(
  tableView: TableView, context: DrawContext, chrome: TableHeaderChrome
)

proc drawTableHeader*(tableView: TableView, context: DrawContext)

func isActive*(tracking: TableHeaderTracking): bool {.inline.} =
  tracking.part != thpNone

proc clear*(tracking: var TableHeaderTracking) =
  tracking = TableHeaderTracking()

proc `rowHeight=`*(tableView: TableView, height: float32) =
  let normalized = height.normalizedRowHeight()
  let previousHeight = tableView.rowHeight()
  tableView.xRowSizing.hasExplicitHeight = true
  if tableView.xRowSizing.height == normalized and previousHeight == normalized:
    return
  tableView.xRowSizing.height = normalized
  tableView.xScrollView.lineScroll = normalized
  tableView.xRowHeightMeasurement.valid = false
  tableView.requestTableReload()

proc `visibleRows=`*(tableView: TableView, rows: int) =
  let normalized = max(rows, 1)
  if tableView.xRowSizing.visibleRows == normalized:
    return
  tableView.xRowSizing.visibleRows = normalized
  tableView.requestTableReload()

proc `widthSizingMode=`*(tableView: TableView, mode: TableViewWidthSizingMode) =
  if tableView.xWidthSizing.mode == mode:
    return
  tableView.xWidthSizing.mode = mode
  tableView.invalidateTableWidthMeasurement()

proc `columnSizing=`*(tableView: TableView, sizing: TableViewColumnSizing) =
  if tableView.xWidthSizing.columnSizing == sizing:
    return
  tableView.xWidthSizing.columnSizing = sizing
  tableView.setNeedsLayout()
  tableView.needsDisplay = true

proc `preferredContentWidth=`*(tableView: TableView, width: float32) =
  let normalizedWidth = max(width, 0.0'f32)
  if tableView.xWidthSizing.preferredContentWidth == normalizedWidth:
    return
  tableView.xWidthSizing.preferredContentWidth = normalizedWidth
  tableView.invalidateTableWidthMeasurement()

proc `tableRole=`*(tableView: TableView, role: StyleRole) =
  if tableView.xTableRole == role:
    return
  tableView.xTableRole = role
  tableView.invalidateIntrinsicContentSize()
  tableView.needsDisplay = true

proc `rowItemRole=`*(tableView: TableView, role: StyleRole) =
  if tableView.xItemRole == role:
    return
  tableView.xItemRole = role
  tableView.invalidateColumnWidthMeasurements()
  tableView.invalidateIntrinsicContentSize()
  tableView.invalidateTableRows()

proc `title=`*(column: TableColumn, title: string) =
  if column.xTitle == title:
    return
  column.xTitle = title
  column.xWidthMeasurement.valid = false
  column.tableView().noteColumnsChanged()

proc `width=`*(column: TableColumn, width: float32) =
  let nextWidth = width.normalizedWidth(column.xWidth)
  if column.xWidth.resolved == nextWidth and column.xWidth.preferred == nextWidth:
    return
  column.xWidth.resolved = nextWidth
  column.xWidth.preferred = nextWidth
  column.tableView().noteColumnsChanged()

proc `minWidth=`*(column: TableColumn, width: float32) =
  let nextMin = width.normalizedColumnMetric(defaultTableStyle().columnMinWidth)
  if column.xWidth.min == nextMin:
    return
  column.xWidth.min = nextMin
  column.xWidth.max = max(column.xWidth.max, nextMin)
  column.xWidth.resolved = column.xWidth.resolved.normalizedWidth(column.xWidth)
  column.xWidth.preferred = column.xWidth.preferred.normalizedWidth(column.xWidth)
  column.tableView().noteColumnsChanged()

proc `maxWidth=`*(column: TableColumn, width: float32) =
  let nextMax = width.normalizedMaxWidth(column.xWidth.min)
  if column.xWidth.max == nextMax:
    return
  column.xWidth.max = nextMax
  column.xWidth.resolved = column.xWidth.resolved.normalizedWidth(column.xWidth)
  column.xWidth.preferred = column.xWidth.preferred.normalizedWidth(column.xWidth)
  column.tableView().noteColumnsChanged()

proc `alignment=`*(column: TableColumn, alignment: TextAlignment) =
  if column.xAlignment == alignment:
    return
  column.xAlignment = alignment
  column.tableView().noteColumnsChanged()

proc `resizePolicy=`*(column: TableColumn, policy: TableColumnResizePolicy) =
  if column.xResizePolicy == policy:
    return
  column.xResizePolicy = policy
  column.tableView().noteColumnsChanged()

proc `sizingPolicy=`*(column: TableColumn, policy: TableColumnSizingPolicy) =
  if column.xSizingPolicy == policy:
    return
  column.xSizingPolicy = policy
  column.xWidthMeasurement.valid = false
  if policy != tcspContentSized:
    column.xWidth.resolved = column.xWidth.preferred.normalizedWidth(column.xWidth)
  column.tableView().noteColumnsChanged()

proc `hidden=`*(column: TableColumn, hidden: bool) =
  if column.xHidden == hidden:
    return
  column.xHidden = hidden
  column.tableView().noteColumnsChanged()

proc `sortDirection=`*(column: TableColumn, direction: TableSortDirection) =
  if column.xSortDirection == direction:
    return
  column.xSortDirection = direction
  column.tableView().noteColumnsChanged()

proc `reuseIdentifier=`*(column: TableColumn, identifier: string) =
  if column.xReuseIdentifier == identifier:
    return
  column.xReuseIdentifier = identifier
  let tableView = column.tableView()
  if not tableView.isNil:
    tableView.clearTableCellSlots()
    tableView.noteColumnsChanged()

proc `styleId=`*(column: TableColumn, id: string) =
  if column.xStyleId == id:
    return
  column.xStyleId = id
  column.tableView().noteColumnsChanged()

proc `styleClasses=`*(column: TableColumn, classes: openArray[string]) =
  let nextClasses = @classes
  if column.xStyleClasses == nextClasses:
    return
  column.xStyleClasses = nextClasses
  column.tableView().noteColumnsChanged()

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
    sizingPolicy = tcspFixed,
) =
  var style: TableViewStyle
  if math.isNaN(minWidth) or math.isNaN(maxWidth) or math.isNaN(width):
    style = defaultTableStyle()
  column.xIdentifier = identifier
  column.xTitle = if title.len == 0: identifier else: title
  column.xWidth.min = minWidth.normalizedColumnMetric(style.columnMinWidth)
  column.xWidth.max = maxWidth.normalizedMaxWidth(column.xWidth.min)
  column.xWidth.resolved = width.normalizedWidth(column.xWidth)
  column.xWidth.preferred = column.xWidth.resolved
  column.xAlignment = alignment
  column.xResizePolicy = resizePolicy
  column.xSizingPolicy = sizingPolicy
  column.xReuseIdentifier = identifier

proc newTableColumn*(
    identifier: string,
    title = "",
    width = NaN,
    minWidth = NaN,
    maxWidth = NaN,
    alignment = taLeft,
    resizePolicy = tcrResizable,
    sizingPolicy = tcspFixed,
): TableColumn =
  result = TableColumn()
  initTableColumnFields(
    result, identifier, title, width, minWidth, maxWidth, alignment, resizePolicy,
    sizingPolicy,
  )

proc visibleTableColumns(tableView: TableView): seq[TableColumn] =
  for column in tableView.visibleColumns():
    result.add column

func tableHeaderCornerRadii(chrome: TableHeaderChrome): themeCore.CornerRadii =
  initCornerRadii(chrome.cornerRadius, chrome.cornerRadius, 0.0'f32, 0.0'f32)

func tableHeaderCellCornerRadii(
    chrome: TableHeaderChrome, firstVisible, lastVisible: bool
): themeCore.CornerRadii =
  initCornerRadii(
    if firstVisible: chrome.cornerRadius else: 0.0'f32,
    if lastVisible: chrome.cornerRadius else: 0.0'f32,
    0.0'f32,
    0.0'f32,
  )

proc `rowHeaderWidth=`*(tableView: TableView, width: float32) =
  let nextWidth = max(width, 0.0'f32)
  if tableView.xRowHeaderSettings.width == nextWidth:
    return
  tableView.xRowHeaderSettings.width = nextWidth
  tableView.noteColumnsChanged()

proc `rowHeaderTitle=`*(tableView: TableView, title: string) =
  if tableView.xRowHeaderSettings.title == title:
    return
  tableView.xRowHeaderSettings.title = title
  tableView.needsDisplay = true

proc `showsRowHeader=`*(tableView: TableView, value: bool) =
  if tableView.xRowHeaderSettings.visible == value:
    return
  tableView.xRowHeaderSettings.visible = value
  tableView.noteColumnsChanged()

proc tableHeaderChrome(tableView: TableView, context: DrawContext): TableHeaderChrome =
  result = defaultTableHeaderChrome()
  if context.isNil:
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
  if context.isNil:
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
  let previousHeight = tableView.tableHeaderHeight()
  tableView.xHeaderSettings.hasExplicitHeight = true
  if tableView.xHeaderSettings.height == nextHeight and previousHeight == nextHeight:
    return
  tableView.xHeaderSettings.height = nextHeight
  tableView.noteColumnsChanged()

proc `showsHeader=`*(tableView: TableView, value: bool) =
  if tableView.xHeaderSettings.visible == value:
    return
  tableView.xHeaderSettings.visible = value
  tableView.noteColumnsChanged()

proc tableHeaderRect*(tableView: TableView): Rect =
  if not tableView.showsHeader():
    return rect(0.0, 0.0, 0.0, 0.0)
  let rowHeaderWidth = tableView.visibleRowHeaderWidth()
  rect(
    1.0'f32 + rowHeaderWidth,
    1.0'f32,
    max(tableView.bounds().size.width - 2.0'f32 - rowHeaderWidth, 0.0'f32),
    tableView.tableHeaderHeight(),
  )

proc tableColumnRect*(tableView: TableView, column: TableColumn): Rect =
  if column.isNil:
    return rect(0.0, 0.0, 0.0, 0.0)
  tableView.layoutTableContentIfNeeded()
  let contentView = tableView.contentView()
  let contentRect = tableView.columnRect(
    rect(0.0, 0.0, contentView.bounds().size.width, tableView.bounds().h), column
  )
  if contentRect.isEmpty:
    return rect(0.0, 0.0, 0.0, 0.0)
  contentView.rectToView(contentRect, tableView).intersection(tableView.bounds())

proc tableRowHeaderCornerRect*(tableView: TableView): Rect =
  if not tableView.showsRowHeader() or not tableView.showsHeader():
    return rect(0.0, 0.0, 0.0, 0.0)
  rect(
    1.0'f32, 1.0'f32, tableView.visibleRowHeaderWidth(), tableView.tableHeaderHeight()
  )

proc tableRowHeaderCellFrame(tableView: TableView, row: int): Rect =
  if not tableView.showsRowHeader():
    return rect(0.0, 0.0, 0.0, 0.0)
  tableView.layoutTableContentIfNeeded()
  let contentView = tableView.contentView()
  let rowRect = contentView.rectToView(contentView.tableContentItemRect(row), tableView)
  if rowRect.isEmpty:
    return rect(0.0, 0.0, 0.0, 0.0)

  rect(
    1.0'f32, rowRect.origin.y, tableView.visibleRowHeaderWidth(), rowRect.size.height
  )

proc tableRowHeaderCellRect*(tableView: TableView, row: int): Rect =
  tableView.tableRowHeaderCellFrame(row).intersection(tableView.tableRowHeaderRect())

proc tableRowHeaderResizeHandleRect*(tableView: TableView, row: int): Rect =
  if not tableView.showsRowHeader() or row notin 0 ..< tableView.len():
    return rect(0.0, 0.0, 0.0, 0.0)
  let
    rowRect = tableView.tableRowHeaderCellFrame(row)
    rowHeaderRect = tableView.tableRowHeaderRect()
    handleHeight = tableView.tableStyle().headerResizeHandleWidth

  rect(
    rowHeaderRect.origin.x,
    rowRect.maxY - handleHeight,
    rowHeaderRect.size.width,
    handleHeight,
  )
    .intersection(rowHeaderRect)

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
  if tableView.xHeaderTracking.insertionIndex < 0:
    return TableHeaderDragIndicator(index: -1)
  TableHeaderDragIndicator(
    index: tableView.xHeaderTracking.insertionIndex,
    rect: tableView.xHeaderTracking.insertionRect,
    visible: not tableView.xHeaderTracking.insertionRect.isEmpty,
  )

proc headerInsertionIndexAtPoint*(tableView: TableView, point: Point): int =
  if tableView.xColumns.len == 0:
    return -1
  var lastVisible = -1
  for index, column in tableView.xColumns:
    if not column.hidden():
      lastVisible = index
      let rect = tableView.tableHeaderColumnRect(column)
      if not rect.isEmpty and point.x < rect.origin.x + rect.size.width * 0.5'f32:
        return index
  if lastVisible >= 0:
    min(lastVisible + 1, tableView.xColumns.len)
  else:
    -1

proc headerInsertionRectForIndex(tableView: TableView, index: int): Rect =
  if index < 0 or tableView.xColumns.len == 0:
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
      if not column.hidden():
        let rect = tableView.tableHeaderColumnRect(column)
        if current >= index:
          x = rect.origin.x
          found = true
          break
        x = rect.maxX
    if not found:
      x = min(x, headerRect.maxX)
  rect(x - 1.0'f32, headerRect.origin.y, 3.0'f32, headerRect.size.height)

proc setHeaderDragInsertion*(tableView: TableView, index: int) =
  let bounded = max(0, min(index, tableView.xColumns.len))
  tableView.xHeaderTracking.insertionIndex = bounded
  tableView.xHeaderTracking.insertionRect =
    tableView.headerInsertionRectForIndex(bounded)

proc autoscrollHeaderColumnDrag*(tableView: TableView, point: Point): bool =
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
  tableView.discardCursorRects()
  if not tableView.showsHeader():
    return
  let resizeHandleWidth = tableView.tableStyle().headerResizeHandleWidth
  let rowHeaderRect = tableView.tableRowHeaderCornerRect()
  if not rowHeaderRect.isEmpty:
    tableView.addCursorRect(
      rect(
        rowHeaderRect.maxX - resizeHandleWidth,
        rowHeaderRect.origin.y,
        resizeHandleWidth * 2.0'f32,
        rowHeaderRect.size.height,
      ),
      TableHeaderResizeCursorName,
    )
  let rowHeaderBodyRect = tableView.tableRowHeaderRect()
  if not rowHeaderBodyRect.isEmpty:
    let rows = tableView.contentView().visibleContentRows()
    for row in rows.first ..< rows.last:
      let handleRect = tableView.tableRowHeaderResizeHandleRect(row)
      if not handleRect.isEmpty:
        tableView.addCursorRect(handleRect, TableRowHeaderResizeCursorName)
  for column in tableView.visibleColumns():
    if column.resizePolicy() == tcrResizable:
      let rect = tableView.tableHeaderColumnRect(column)
      if not rect.isEmpty:
        tableView.addCursorRect(
          rect(
            rect.maxX - resizeHandleWidth,
            rect.origin.y,
            resizeHandleWidth * 2.0'f32,
            rect.size.height,
          ),
          TableHeaderResizeCursorName,
        )

proc syncHeaderTrackingAreas*(tableView: TableView) =
  discard tableView.removeTrackingArea(TableHeaderTrackingTag)
  discard tableView.removeTrackingArea(TableRowHeaderTrackingTag)
  if tableView.showsHeader():
    tableView.addTrackingArea(
      ViewTrackingArea(
        rect: tableView.tableHeaderRect(),
        options: {vtoMouseEnteredAndExited, vtoMouseMoved, vtoCursorUpdate},
        tag: TableHeaderTrackingTag,
        owner: Responder(tableView),
      )
    )
  if tableView.showsRowHeader():
    let rowHeaderRect = tableView.tableRowHeaderRect()
    if not rowHeaderRect.isEmpty:
      tableView.addTrackingArea(
        ViewTrackingArea(
          rect: rowHeaderRect,
          options: {vtoMouseEnteredAndExited, vtoMouseMoved, vtoCursorUpdate},
          tag: TableRowHeaderTrackingTag,
          owner: Responder(tableView),
        )
      )
  tableView.resetHeaderCursorRects()

proc tableColumnAtPoint*(tableView: TableView, point: Point): TableColumn =
  tableView.columnAtPoint(tableView.contentView().pointFromView(point, tableView))

proc applyRowHeightResize*(tableView: TableView, row: int, height: float32) =
  if row notin 0 ..< tableView.len():
    return
  let normalized = height.normalizedRowHeight()
  if tableView.xRowSizing.overrides.getOrDefault(row, 0.0'f32) == normalized:
    return
  tableView.xRowSizing.overrides[row] = normalized
  tableView.invalidateRowHeightCache()
  tableView.clearTableCellSlots()
  tableView.invalidateIntrinsicContentSize()
  tableView.setNeedsLayout()
  tableView.invalidateTableRows()
  tableView.syncHeaderTrackingAreas()

proc layoutTableContent(tableView: TableView) =
  tableView.xScrollView.lineScroll = tableView.rowHeight()
  let
    offset = tableView.listContentOffset()
    layout = tableView.resolvedTableContentLayout()
  tableView.xScrollView.setFrameFromLayout(layout.scrollFrame)
  tableView.xContentView.setFrameFromLayout(
    rect(initPoint(0.0'f32, 0.0'f32), layout.documentSize)
  )
  tableView.xScrollView.tile()
  tableView.setTableContentOffset(offset, false)
  tableView.xContentView.syncVisibleRowViews()
  tableView.syncVisibleTableCells()

proc `highlightedIndex=`*(tableView: TableView, index: int) =
  let boundedIndex = if tableView.rowEnabled(index): index else: -1
  if tableView.xHighlightedIndex == boundedIndex:
    return
  tableView.xHighlightedIndex = boundedIndex
  tableView.invalidateTableRows()

proc setHighlightedColumn*(tableView: TableView, column: TableColumn) =
  var next = column
  if tvoColumnSelection notin tableView.xOptions or next.isNil or
      next.tableView() != tableView or next.hidden():
    next = nil
  if tableView.xHighlightedColumn == next:
    return
  tableView.xHighlightedColumn = next
  tableView.invalidateTableRows()

proc clearPointerRowHighlight*(tableView: TableView) =
  if tableView.xHighlightedIndex < 0:
    return
  tableView.xHighlightedIndex = -1
  tableView.invalidateTableRows()

proc clearPointerColumnHighlight*(tableView: TableView) =
  tableView.setHighlightedColumn(nil)

proc clearPointerHighlights*(tableView: TableView) =
  tableView.clearPointerRowHighlight()
  tableView.clearPointerColumnHighlight()

proc `usesAlternatingRowBackgrounds=`*(tableView: TableView, value: bool) =
  if (tvoAlternatingRowBackgrounds in tableView.xOptions) == value:
    return
  tableView.xOptions[tvoAlternatingRowBackgrounds] = value
  tableView.invalidateTableRows()

proc `showsRowSeparators=`*(tableView: TableView, value: bool) =
  if (tvoRowSeparators in tableView.xOptions) == value:
    return
  tableView.xOptions[tvoRowSeparators] = value
  tableView.invalidateTableRows()

proc `tracksPointerRowHighlights=`*(tableView: TableView, value: bool) =
  if (tvoPointerRowHighlights in tableView.xOptions) == value:
    return
  tableView.xOptions[tvoPointerRowHighlights] = value
  if not value:
    tableView.clearPointerRowHighlight()

proc `tracksPointerColumnHighlights=`*(tableView: TableView, value: bool) =
  if (tvoPointerColumnHighlights in tableView.xOptions) == value:
    return
  tableView.xOptions[tvoPointerColumnHighlights] = value
  if not value:
    tableView.clearPointerColumnHighlight()

proc `showsFocusedRowHighlight=`*(tableView: TableView, value: bool) =
  if (tvoFocusedRowHighlight in tableView.xOptions) == value:
    return
  tableView.xOptions[tvoFocusedRowHighlight] = value
  tableView.invalidateTableRows()

proc `showsFocusedColumnHighlight=`*(tableView: TableView, value: bool) =
  if (tvoFocusedColumnHighlight in tableView.xOptions) == value:
    return
  tableView.xOptions[tvoFocusedColumnHighlight] = value
  tableView.invalidateTableRows()

proc defaultDropTargetForDraggingLocation(
    tableView: TableView, location: Point
): DraggingDropTarget =
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

proc layoutHostedCell*(rowView: TableRowView, column: TableColumn, cellView: View) =
  let rowBounds =
    rect(0.0, 0.0, rowView.bounds().size.width, rowView.bounds().size.height)
  cellView.setFrameFromLayout(rowView.xTableView.columnRect(rowBounds, column))

proc syncVisibleTableCells(tableView: TableView) =
  let previousSlots = tableView.xCellSlots
  var
    nextSlots: seq[TableCellSlot]
    used = newSeq[bool](previousSlots.len)
  for rowView in tableView.xContentView.xRowViews:
    let row = rowView.xRow.index
    for column in tableView.columns:
      if not column.hidden():
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
          rowView.layoutHostedCell(column, cellView)
          cellView.hidden = false
          cellView.setWidgetState(ssDisabled, not tableView.rowEnabled(row))
          tableView.applyCellAccessibility(row, column, cellView)
          nextSlots.add TableCellSlot(row: row, column: column, view: cellView)
  for index, slot in previousSlots:
    if not used[index]:
      tableView.recycleCellSlot(slot)
  tableView.xCellSlots = nextSlots

proc rowItemStyle(
    tableView: TableView, context: DrawContext, states: set[WidgetState]
): RowItemStyle =
  context.appearance.resolveRowItemStyle(
    controlStyle(
      srRowItem, states, id = tableView.styleId(), classes = tableView.styleClasses()
    )
  )

proc focusedCellRingBox(
    tableView: TableView, context: DrawContext, style: RowItemStyle
): ControlBoxStyle =
  result = style.box
  let tableBox = context.appearance.resolveTableViewStyle(
    controlStyle(
      tableView.xTableRole,
      tableView.widgetStateSet(),
      id = tableView.styleId(),
      classes = tableView.styleClasses(),
    )
  ).box
  if result.focusRingWidth <= 0.0'f32:
    result.focusRingWidth = min(max(tableBox.focusRingWidth, 1.5'f32), 2.0'f32)
  if result.focusRingColor.a <= 0.0'f32:
    result.focusRingColor = tableBox.focusRingColor
  result.focusRingInset = 0.0
  result.cornerRadius = min(max(tableBox.cornerRadius - 1.0'f32, 2.0'f32), 4.0'f32)

func isTransparent(fillValue: Fill): bool =
  fillValue.kind == flColor and fillValue.color.a == 0'u8

proc selectedTableColumnFill(tableView: TableView, context: DrawContext): Fill =
  if context.isNil:
    return fill(color(0.0, 0.0, 0.0, 0.0))
  context.appearance.resolveFill(
    controlStyle(
      tableView.xTableRole,
      tableView.widgetStateSet(),
      id = tableView.styleId(),
      classes = tableView.styleClasses(),
    ),
    fill(color(0.0, 0.0, 0.0, 0.0)),
    StyleColumnSelectionFill,
  )

proc hoveredTableColumnFill(tableView: TableView, context: DrawContext): Fill =
  if context.isNil:
    return fill(color(0.0, 0.0, 0.0, 0.0))
  context.appearance.resolveFill(
    controlStyle(
      tableView.xTableRole,
      tableView.widgetStateSet(),
      id = tableView.styleId(),
      classes = tableView.styleClasses(),
    ),
    tableView.selectedTableColumnFill(context),
    StyleColumnHoverFill,
  )

proc shouldDrawSelectedTableColumn(tableView: TableView, column: TableColumn): bool =
  if column.isNil:
    return false
  if not tableView.xHighlightedColumn.isNil:
    column == tableView.xHighlightedColumn
  else:
    tvoFocusedColumnHighlight in tableView.xOptions and
      column in tableView.xSelectedColumns

proc drawSelectedTableColumn(
    tableView: TableView,
    context: DrawContext,
    row: int,
    column: TableColumn,
    rect: Rect,
) =
  if context.isNil or column.isNil or not tableView.shouldDrawSelectedTableColumn(
    column
  ):
    return
  let fillValue =
    if column == tableView.xHighlightedColumn:
      tableView.hoveredTableColumnFill(context)
    else:
      tableView.selectedTableColumnFill(context)
  if fillValue.isTransparent():
    return
  var fillRect = rect
  if tableView.showsRowSeparators() and row >= 0 and row < tableView.len() - 1:
    fillRect = rect(
      fillRect.origin.x,
      fillRect.origin.y,
      fillRect.size.width,
      max(fillRect.size.height - 1.0'f32, 0.0'f32),
    )
  if fillRect.isEmpty:
    return
  discard context.addRenderRectangle(context.renderRectFor(fillRect), fillValue)

proc drawFocusedTableCell(
    tableView: TableView,
    context: DrawContext,
    row: int,
    column: TableColumn,
    rect: Rect,
    style: RowItemStyle,
) =
  if context.isNil or column.isNil:
    return
  let
    isKeyboardFocusedCell =
      tableView.xFocusedColumn == column and row == tableView.selectionLeadIndex()
    isEditingCell =
      tableView.xCellEditing.state.active and tableView.xCellEditing.state.row == row and
      tableView.xCellEditing.state.column == column
  if not (isKeyboardFocusedCell or isEditingCell):
    return
  if not tableView.focused() and not isEditingCell:
    return
  var box = tableView.focusedCellRingBox(context, style)
  if box.focusRingWidth <= 0.0'f32 or box.focusRingColor.a <= 0.0'f32:
    return
  let ringRect = rect.inset(insets(max(box.focusRingWidth, 1.0'f32)))
  if ringRect.isEmpty:
    return
  let clipRect = context.visibleRect().intersection(ringRect)
  if clipRect.isEmpty:
    return
  let focusClip = context.addRenderRectangle(
    FocusRingDrawLevel,
    (-1).FigIdx,
    context.renderRectFor(clipRect),
    fill(color(0.0, 0.0, 0.0, 0.0)),
    clips = true,
  )
  discard context.addRenderRectangle(
    FocusRingDrawLevel,
    focusClip,
    context.renderRectFor(ringRect),
    fill(color(0.0, 0.0, 0.0, 0.0)),
    box.focusRingColor,
    box.focusRingWidth,
    box.cornerRadius,
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
  if tableView.xCellEditing.state.active and tableView.xCellEditing.state.row == row and
      tableView.xCellEditing.state.column == column:
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
  if context.isNil:
    return
  let
    drawingRow = tableView.drawingTableRowState(row)
    emptyRow = initRowState(drawingRow.index, "", states = drawingRow.states)
  tableView.drawTableRowItem(context, rect, emptyRow)
  if row.index < 0:
    return
  let
    rowBounds = rect(0.0, 0.0, rect.size.width, rect.size.height)
    style = tableView.rowItemStyle(context, drawingRow.states)
  for column in tableView.columns:
    if not column.hidden():
      let cellRect = tableView.columnRect(rowBounds, column)
      tableView.drawSelectedTableColumn(context, row.index, column, cellRect)
      if not tableView.hasHostedCell(row.index, column):
        tableView.drawTableCellText(context, row.index, column, cellRect, style)
      tableView.drawFocusedTableCell(context, row.index, column, cellRect, style)
  tableView.drawTableDropTarget(context, rect, row)

proc drawHorizontalTableDropIndicator(
    tableView: TableView,
    context: DrawContext,
    rect: Rect,
    position: DraggingDropPosition,
) =
  if context.isNil or rect.isEmpty:
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
  if context.isNil or row.index < 0:
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

func tableBodyRowTouchesEdge(rowEdge, viewportEdge: float32): bool =
  abs(rowEdge - viewportEdge) <= 0.5'f32

proc tableBodyRowCornerRadii(
    tableView: TableView, row: RowState
): themeCore.CornerRadii =
  if row.index < 0:
    return
  let
    tableStyle = tableView.tableStyle()
    radius = max(tableStyle.box.cornerRadius - tableStyle.box.borderWidth, 0.0'f32)
  if radius <= 0.0'f32:
    return
  let
    offset = tableView.listContentOffset()
    visibleTop = offset.y
    visibleBottom = visibleTop + tableView.viewportSize().height
    rowTop = tableView.rowOffset(row.index)
    rowBottom = rowTop + tableView.rowHeightForRow(row.index)
    touchesTop =
      not tableView.showsHeader() and tableBodyRowTouchesEdge(rowTop, visibleTop)
    touchesBottom = tableBodyRowTouchesEdge(rowBottom, visibleBottom)
  if not touchesTop and not touchesBottom:
    return
  initCornerRadii(
    if touchesTop: radius else: 0.0'f32,
    if touchesTop: radius else: 0.0'f32,
    if touchesBottom: radius else: 0.0'f32,
    if touchesBottom: radius else: 0.0'f32,
  )

proc tableFocusRingClipRect(
    tableView: TableView, focusRect: Rect, box: ControlBoxStyle
): Rect =
  let visualOutset = max(-box.focusRingInset + box.focusRingWidth * 0.5'f32, 0.0'f32)
  result = focusRect.inset(insets(-visualOutset))
  var ancestor = tableView.superview()
  while not ancestor.isNil:
    if ancestor.clipsToBounds:
      result = result.intersection(tableView.rectFromView(ancestor.bounds, ancestor))
      if result.isEmpty:
        return
    ancestor = ancestor.superview()

proc noteColumnsChanged*(tableView: TableView) =
  if tableView.isNil:
    return
  if not tableView.xFocusedColumn.isNil and (
    tableView.xFocusedColumn.tableView() != tableView or
    tableView.xFocusedColumn.hidden()
  ):
    tableView.clearFocusedColumn()
  if not tableView.xHighlightedColumn.isNil and (
    tableView.xHighlightedColumn.tableView() != tableView or
    tableView.xHighlightedColumn.hidden()
  ):
    tableView.xHighlightedColumn = nil
  tableView.invalidateColumnWidthMeasurements()
  tableView.syncTableScrollChrome()
  tableView.syncHeaderTrackingAreas()
  tableView.clearTableCellSlots()
  tableView.invalidateTableRows()
  tableView.invalidateTableWidthMeasurement()
  tableView.setNeedsLayout()
  tableView.needsDisplay = true

proc syncTableScrollChrome*(tableView: TableView) =
  tableView.xScrollView.scrollerInsets =
    insets(tableView.tableHeaderHeight(), 0.0, 0.0, 0.0)

proc detachColumn(column: TableColumn) =
  if column.xTableView.isNil:
    return
  column.xTableView.removeColumnAtIndex(
    column.xTableView.columnIndex(column.identifier)
  )

proc insertColumn*(tableView: TableView, column: TableColumn, index: int) =
  if column.isNil or column.identifier.len == 0:
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
  tableView.insertColumn(column, tableView.xColumns.len)

proc removeColumnAtIndex(tableView: TableView, index: int) =
  if index notin 0 ..< tableView.xColumns.len:
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
  column.xTableView = nil
  if tableView.xHighlightedColumn == column:
    tableView.xHighlightedColumn = nil
  tableView.noteColumnsChanged()

proc removeColumnAt*(tableView: TableView, index: int) =
  tableView.removeColumnAtIndex(index)

proc removeColumn*(tableView: TableView, column: TableColumn) =
  if column.isNil:
    return
  let index = tableView.columnIndex(column.identifier)
  if index >= 0 and tableView.xColumns[index] == column:
    tableView.removeColumnAtIndex(index)

proc removeColumn*(tableView: TableView, identifier: string) =
  tableView.removeColumnAtIndex(tableView.columnIndex(identifier))

proc removeLastRowView(contentView: TableContentView) =
  if contentView.xRowViews.len == 0:
    return
  let rowView = contentView.xRowViews[^1]
  contentView.xRowViews.setLen(contentView.xRowViews.len - 1)
  rowView.removeFromSuperview()

proc syncVisibleRowViews(contentView: TableContentView) =
  let
    tableView = contentView.tableView()
    rows = contentView.visibleContentRows()
    needed = max(rows.last - rows.first, 0)
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
  if context.isNil:
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
  let cornerRadii = tableView.tableBodyRowCornerRadii(row)
  if not cornerRadii.isZero:
    style.cornerRadii = some(cornerRadii)
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
  if tableView.xTableDelegate.isNil or context.isNil:
    return false
  tableView.xTableDelegate.sendLocalIfHandled(
    drawRow(), (tableView: tableView, context: context, rect: rect, row: row)
  )

proc measuredTableContentWidth(tableView: TableView, style: TextStyle): float32 =
  if tableView.xWidthMeasurement.matches(style):
    return tableView.xWidthMeasurement.width

  let source = tableView.dataSource()
  var widthHint = none(float32)
  if not source.isNil:
    widthHint = source.trySendLocal(tableIntrinsicContentWidth(), tableView)
  if widthHint.isSome and widthHint.get() >= 0.0'f32:
    result = widthHint.get()
  else:
    for index in 0 ..< tableView.len():
      result =
        max(result, textNaturalSize(tableView.rowTextForSummary(index), style).width)

  tableView.xWidthMeasurement = TableWidthMeasurement(
    width: result, fontName: style.fontName, fontSize: style.fontSize, valid: true
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
    totalRows = tableView.len()
    displayedRows =
      if totalRows == 0:
        max(tableView.visibleRows(), 1)
      else:
        visibleRowItemCount(totalRows, tableView.visibleRows())
  let summaryTextStyle =
    tableView.effectiveAppearance().resolveRowItemStyle(controlStyle(srRowItem)).text

  var naturalHeight = 0.0'f32
  if totalRows == 0 or tableView.usesFixedRowHeights():
    naturalHeight = tableView.rowHeight() * displayedRows.float32
  else:
    for index in 0 ..< displayedRows:
      naturalHeight += tableView.rowHeightForRow(index)

  let
    requestedContentWidth =
      case tableView.xWidthSizing.mode
      of tvwsmColumns:
        0.0'f32
      of tvwsmContent:
        tableView.measuredTableContentWidth(summaryTextStyle)
      of tvwsmPreferredWidth:
        tableView.xWidthSizing.preferredContentWidth
    bodyWidth = max(tableView.visibleColumnWidth(), requestedContentWidth)

  initSize(
    max(
      listStyle.minSize.width,
      max(
        itemStyle.minSize.width,
        tableView.visibleRowHeaderWidth() + bodyWidth + itemStyle.text.insets.horizontal +
          2.0'f32,
      ),
    ),
    max(
      listStyle.minSize.height, naturalHeight + tableView.tableHeaderHeight() + 2.0'f32
    ),
  )

protocol DefaultTableRowViewDrawing of ViewDrawingProtocol:
  method drawsStyledBackground(view: View): bool =
    true

  method draw(rowView: TableRowView, context: DrawContext) =
    let tableView = rowView.xTableView
    let rect = rowView.bounds()
    if not tableView.drawCustomTableRow(context, rect, rowView.xRow):
      tableView.drawTableRow(context, rect, rowView.xRow)

protocol DefaultTableRowViewLayout of ViewLayoutProtocol:
  method layoutSubviews(rowView: TableRowView) =
    # A sibling's intrinsic-size change can solve cached control geometry without
    # laying out the table. Restore this row's hosted frames in the same pass.
    for slot in rowView.xTableView.xCellSlots:
      if slot.row == rowView.xRow.index:
        rowView.layoutHostedCell(slot.column, slot.view)

protocol DefaultTableRowViewHitTesting of ViewProtocol:
  method pointInside(rowView: TableRowView, point: Point): bool =
    false

protocol DefaultTableRowViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(rowView: TableRowView): AccessibilityRole =
    arListItem

  method accessibilityLabel(rowView: TableRowView): string =
    rowView.xRow.text

  method accessibilityValue(rowView: TableRowView): string =
    $rowView.xRow.index

  method accessibilityTraits(rowView: TableRowView): AccessibilityTraits =
    if ssDisabled in rowView.xRow.states:
      result.incl atDisabled
    if ssFocused in rowView.xRow.states:
      result.incl atFocused
    if ssSelected in rowView.xRow.states:
      result.incl atSelected
    if rowView.xTableView.selectionMode() != tsmNone:
      result.incl atSelectable

  method isAccessibilityElement(rowView: TableRowView): bool =
    rowView.xRow.index >= 0

protocol DefaultTableContentViewDrawing of ViewDrawingProtocol:
  method drawsStyledBackground(view: View): bool =
    true

  method draw(contentView: TableContentView, context: DrawContext) =
    discard context.visibleRect()
    contentView.syncVisibleRowViews()
    contentView.tableView().syncVisibleTableCells()

protocol DefaultTableContentViewHitTesting of ViewProtocol:
  method pointInside(contentView: TableContentView, point: Point): bool =
    contentView.bounds().contains(point)

protocol DefaultTableViewLayout of ViewLayoutProtocol:
  method layoutStyleContext(tableView: TableView): StyleContext =
    tableView.tableStyleContext()

  method managesSubviewLayout(tableView: TableView, child: DynamicAgent): bool =
    if child == tableView.xScrollView or child == tableView.xContentView:
      return true
    let editor = Control(tableView).currentEditor()
    if not editor.isNil and child == editor:
      return true
    for rowView in tableView.xContentView.xRowViews:
      if child == rowView:
        return true
    for slot in tableView.xCellSlots:
      if child == slot.view:
        return true

  method layoutIntrinsicContentSize(tableView: TableView): IntrinsicSize =
    initIntrinsicSize(tableView.naturalSize())

  method layoutSubviews(tableView: TableView) =
    tableView.layoutTableContent()

proc initTableRowView(tableView: TableView): TableRowView =
  result = TableRowView()
  initTableBaseChild(result, false)
  result.xTableView = tableView
  discard result.withProtocol(DefaultTableRowViewDrawing)
  discard result.withProtocol(DefaultTableRowViewLayout)
  discard result.withProtocol(DefaultTableRowViewHitTesting)
  discard result.withProtocol(DefaultTableRowViewAccessibility)

proc initTableContentView*(tableView: TableView): TableContentView =
  result = TableContentView()
  initTableBaseChild(result, false)
  result.xTableView = tableView
  discard result.withProtocol(DefaultTableContentViewDrawing)
  discard result.withProtocol(DefaultTableContentViewHitTesting)

proc initTableScrollView*(tableView: TableView): ScrollView =
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
  result.acceptsFirstResponder = false
  result.autoresizingMaskConstraints = false

proc drawTableHeaderSortIndicator*(
    tableView: TableView,
    context: DrawContext,
    rect: Rect,
    direction: TableSortDirection,
    chrome: TableHeaderChrome,
    parent = (-1).FigIdx,
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

  discard context.addRenderLine(parent, leftBase, apex, indicatorFill, lineWeight)
  discard context.addRenderLine(parent, apex, rightBase, indicatorFill, lineWeight)

proc drawTableHeaderResizeHandle*(
    tableView: TableView,
    context: DrawContext,
    column: TableColumn,
    rect: Rect,
    chrome: TableHeaderChrome,
    parent = (-1).FigIdx,
) =
  if context.isNil or column.isNil or rect.isEmpty:
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
    parent,
    context.renderRectFor(rect(rect.maxX - 1.0'f32, handleY, 1.0, handleHeight)),
    fill(handleColor),
  )
  discard context.addRenderRectangle(
    parent,
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
    tableView: TableView,
    context: DrawContext,
    chrome: TableHeaderChrome,
    parent = (-1).FigIdx,
) =
  if context.isNil:
    return
  let indicator = tableView.headerDragIndicator()
  if not indicator.visible:
    return
  let
    rect = indicator.rect
    insertionRect =
      rect(rect.origin.x, rect.origin.y, chrome.insertionWidth, rect.size.height)
  discard context.addRenderRectangle(
    parent,
    context.renderRectFor(insertionRect),
    chrome.insertionIndicatorFill,
    cornerRadius = chrome.cornerRadius,
  )
  discard context.addRenderRectangle(
    parent,
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
    parent,
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
  if context.isNil or rect.isEmpty:
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
    parent = (-1).FigIdx,
) =
  if context.isNil or column.isNil or rect.isEmpty:
    return
  var background = chrome.cellFill
  if column == tableView.xPressedColumn:
    background = chrome.pressedCellFill
  elif column == tableView.xHoveredColumn:
    background = chrome.hoveredCellFill
  discard context.addRenderRectangle(
    parent,
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
    parent = (-1).FigIdx,
) =
  if context.isNil or column.isNil or rect.isEmpty:
    return
  let indicatorWidth =
    if column.sortDirection() == tsdNone: 0.0'f32 else: chrome.sortIndicatorWidth
  let titleRect = rect(
    rect.origin.x + 8.0'f32,
    rect.origin.y,
    max(rect.size.width - 16.0'f32 - indicatorWidth, 0.0'f32),
    rect.size.height,
  )
  discard context.addText(
    DefaultDrawLevel,
    parent,
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

proc drawTableRowHeaderCellTitle(
    tableView: TableView,
    context: DrawContext,
    text: string,
    rect: Rect,
    chrome: TableHeaderChrome,
    alignment = taRight,
    parent = (-1).FigIdx,
) =
  if context.isNil or rect.isEmpty or text.len == 0:
    return
  let
    titleRect = rect(
      rect.origin.x + 6.0'f32,
      rect.origin.y,
      max(rect.size.width - 12.0'f32, 0.0'f32),
      rect.size.height,
    )
    textStyle = context.appearance.resolveTextStyle(
      controlStyle(srTableHeaderCell), chrome.textColor, insets(0.0)
    )
  discard context.addText(
    DefaultDrawLevel,
    parent,
    titleRect,
    clippedText(text, titleRect.size.width, textStyle),
    textStyle,
    alignment,
  )

proc drawTableRowHeaderCorner*(
    tableView: TableView, context: DrawContext, chrome: TableHeaderChrome
) =
  if context.isNil:
    return
  let rect = tableView.tableRowHeaderCornerRect()
  if rect.isEmpty:
    return
  discard context.addRenderRectangle(
    context.renderRectFor(rect),
    chrome.cellFill,
    chrome.cellBorderColor,
    chrome.borderWidth,
    cornerRadius = chrome.cornerRadius,
    cornerRadii = initCornerRadii(chrome.cornerRadius, 0.0, 0.0, 0.0),
  )
  tableView.drawTableRowHeaderCellTitle(
    context, tableView.rowHeaderTitle(), rect, chrome, taCenter
  )
  discard context.addRenderRectangle(
    context.renderRectFor(
      rect(rect.maxX - chrome.borderWidth, rect.origin.y, chrome.borderWidth, rect.h)
    ),
    fill(chrome.cellBorderColor),
  )

proc drawTableRowHeaders*(
    tableView: TableView, context: DrawContext, chrome: TableHeaderChrome
) =
  if context.isNil or not tableView.showsRowHeader():
    return
  let
    clipRect = tableView.tableRowHeaderRect().intersection(tableView.visibleRect())
    rows = tableView.contentView().visibleContentRows()
  if clipRect.isEmpty:
    return
  let clip = context.addRenderRectangle(
    DefaultDrawLevel,
    (-1).FigIdx,
    context.renderRectFor(clipRect),
    fill(color(0.0, 0.0, 0.0, 0.0)),
    clips = true,
  )
  for row in rows.first ..< rows.last:
    let
      rect = tableView.tableRowHeaderCellFrame(row)
      visibleRect = rect.intersection(clipRect)
    if not visibleRect.isEmpty:
      discard context.addRenderRectangle(
        DefaultDrawLevel,
        clip,
        context.renderRectFor(rect),
        chrome.cellFill,
        chrome.cellBorderColor,
        chrome.borderWidth,
      )
      tableView.drawTableRowHeaderCellTitle(
        context, tableView.rowHeaderText(row), rect, chrome, parent = clip
      )

proc drawTableHeader*(
    tableView: TableView, context: DrawContext, chrome: TableHeaderChrome
) =
  if context.isNil or not tableView.showsHeader():
    return
  let headerRect = tableView.tableHeaderRect()
  if headerRect.isEmpty:
    return
  tableView.drawTableRowHeaderCorner(context, chrome)
  tableView.drawTableHeaderBackground(context, headerRect, chrome)
  let headerClip = context.addRenderRectangle(
    DefaultDrawLevel,
    (-1).FigIdx,
    context.renderRectFor(headerRect),
    fill(color(0.0, 0.0, 0.0, 0.0)),
    clips = true,
  )
  let visibleColumns = tableView.visibleTableColumns()
  for index, column in visibleColumns:
    let rect = tableView.tableHeaderColumnRect(column)
    if not rect.isEmpty:
      tableView.drawTableHeaderCellChrome(
        context,
        column,
        rect,
        chrome,
        index == 0,
        index == visibleColumns.high,
        headerClip,
      )
      tableView.drawTableHeaderCellTitle(context, column, rect, chrome, headerClip)
      tableView.drawTableHeaderSortIndicator(
        context, rect, column.sortDirection(), chrome, headerClip
      )
      tableView.drawTableHeaderResizeHandle(context, column, rect, chrome, headerClip)
  tableView.drawTableHeaderInsertionIndicator(context, chrome, headerClip)

proc drawTableHeader*(tableView: TableView, context: DrawContext) =
  tableView.drawTableHeader(context, tableView.tableHeaderChrome(context))

protocol DefaultTableViewDrawing of ViewDrawingProtocol:
  method drawsStyledBackground(view: View): bool =
    true

  method draw(tableView: TableView, context: DrawContext) =
    if context.isNil or tableView.bounds().isEmpty:
      return
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
    let headerChrome = tableView.tableHeaderChrome(context)
    tableView.drawTableHeader(context, headerChrome)
    tableView.drawTableRowHeaders(context, headerChrome)
    if ssFocusVisible in focusedState:
      let headerHeight = tableView.tableHeaderHeight()
      let visibleBounds = tableView.visibleRect()
      var focusRect = tableView.bounds()
      let rowHeaderRect = tableView.tableRowHeaderRect()
      if not rowHeaderRect.isEmpty:
        let bodyMinX = rowHeaderRect.maxX
        focusRect.w = max(focusRect.maxX - bodyMinX, 0.0'f32)
        focusRect.x = bodyMinX
      focusRect.y += headerHeight
      focusRect.h = max(focusRect.h - headerHeight, 0.0'f32)
      if not focusRect.intersection(visibleBounds).isEmpty:
        let focusBox = tableFocusRingBox(listStyle.box)
        let focusClipRect = tableView.tableFocusRingClipRect(focusRect, focusBox)
        if focusClipRect.isEmpty:
          return
        let focusClip = context.addRenderRectangle(
          FocusRingDrawLevel,
          (-1).FigIdx,
          context.renderRectFor(focusClipRect),
          fill(color(0.0, 0.0, 0.0, 0.0)),
          clips = true,
        )
        context.addFocusRing(
          FocusRingDrawLevel, focusClip, context.renderRectFor(focusRect), focusBox
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

proc tableViewportGeometryChanged*(tableView: TableView) {.slot.} =
  # Header and row-header drawing lives outside the scrolling document. Its
  # retained fragments must follow direct clip-view offset changes as well.
  tableView.needsDisplay = true

protocol DefaultTableViewColumnBehavior of TableViewColumnProtocol:
  method columnAtPoint(tableView: TableView, point: Point): TableColumn =
    var x = 0.0'f32
    for column in tableView.columns:
      if not column.hidden():
        let nextX = x + column.width()
        if point.x >= x and point.x < nextX:
          return column
        x = nextX

  method headerHitTest(tableView: TableView, point: Point): TableHeaderHit =
    result = TableHeaderHit(columnIndex: -1, row: -1, part: thpNone)
    let resizeHandleWidth = tableView.tableStyle().headerResizeHandleWidth
    let rowHeaderRect = tableView.tableRowHeaderCornerRect()
    if rowHeaderRect.contains(point):
      result.rect = rowHeaderRect
      if point.x >= rowHeaderRect.maxX - resizeHandleWidth:
        result.part = thpRowHeaderResizeHandle
      else:
        result.part = thpRowHeader
      return
    let rowHeaderBodyRect = tableView.tableRowHeaderRect()
    if rowHeaderBodyRect.contains(point):
      let contentView = tableView.contentView()
      let rows = contentView.visibleContentRows()
      for row in rows.first ..< rows.last:
        let handleRect = tableView.tableRowHeaderResizeHandleRect(row)
        if handleRect.contains(point):
          result.row = row
          result.rect = tableView.tableRowHeaderCellRect(row)
          result.part = thpRowHeaderRowResizeHandle
          return
      return
    if not tableView.tableHeaderRect().contains(point):
      return
    for index, column in tableView.xColumns:
      let rect = tableView.tableHeaderColumnRect(column)
      if not rect.isEmpty and column.resizePolicy() == tcrResizable:
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
    if column.isNil or column.tableView() != tableView:
      return
    if column.resizePolicy() == tcrFixed:
      return
    column.xWidth.userResized = true
    column.width = width
    if tableView.xCellEditing.state.active and
        tableView.xCellEditing.state.column == column:
      tableView.requestTableEditorLayout()
    tableView.syncHeaderTrackingAreas()
    tableView.setNeedsLayout()
    tableView.needsDisplay = true

  method moveColumn(tableView: TableView, fromIndex, toIndex: int) =
    if fromIndex notin 0 ..< tableView.xColumns.len:
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
    if column.isNil or column.tableView() != tableView:
      return
    let
      selectedIdentifiers =
        tableView.rowIdentifiersForRows(tableView.xRowSelection.indexes)
      anchorIdentifier = tableView.tableRowIdentifier(tableView.xRowSelection.anchor)
      leadIdentifier = tableView.tableRowIdentifier(tableView.xRowSelection.lead)
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
    if event.button != mbPrimary:
      return false
    let hit = tableView.tableHeaderHitTest(event.location)
    if hit.part == thpNone:
      return false
    tableView.xHeaderTracking = TableHeaderTracking(
      part: hit.part,
      column: hit.column,
      columnIndex: hit.columnIndex,
      row: hit.row,
      startPoint: event.location,
      insertionIndex: -1,
    )
    tableView.xPressedColumn = hit.column
    tableView.xHeaderTracking.startSize.width =
      if hit.part == thpRowHeaderResizeHandle:
        tableView.rowHeaderWidth()
      elif hit.part == thpRowHeaderRowResizeHandle:
        0.0'f32
      elif hit.column.isNil:
        0.0'f32
      else:
        hit.column.width()
    tableView.xHeaderTracking.startSize.height =
      if hit.part == thpRowHeaderRowResizeHandle:
        tableView.rowHeightForRow(hit.row)
      else:
        0.0'f32
    tableView.needsDisplay = true
    true

  method headerMouseDragged(tableView: TableView, event: MouseEvent): bool =
    if not tableView.xHeaderTracking.isActive():
      return false
    let
      startPoint = tableView.xHeaderTracking.startPoint
      startSize = tableView.xHeaderTracking.startSize
    case tableView.xHeaderTracking.part
    of thpRowHeaderResizeHandle:
      tableView.rowHeaderWidth = startSize.width + event.location.x - startPoint.x
    of thpRowHeaderRowResizeHandle:
      tableView.applyRowHeightResize(
        tableView.xHeaderTracking.row,
        startSize.height + event.location.y - startPoint.y,
      )
    of thpRowHeader:
      discard
    of thpResizeHandle:
      if tableView.xHeaderTracking.column.isNil:
        return false
      tableView.resizeColumn(
        tableView.xHeaderTracking.column,
        startSize.width + event.location.x - startPoint.x,
      )
    of thpColumn:
      if tableView.xHeaderTracking.column.isNil:
        return false
      if abs(event.location.x - startPoint.x) >
          tableView.tableStyle().headerDragThreshold:
        tableView.xHeaderTracking.draggingColumn = true
      if tableView.xHeaderTracking.draggingColumn:
        if not tableView.autoscrollHeaderColumnDrag(event.location):
          tableView.setHeaderDragInsertion(
            tableView.headerInsertionIndexAtPoint(event.location)
          )
        tableView.needsDisplay = true
    of thpNone:
      discard
    true

  method headerMouseUp(tableView: TableView, event: MouseEvent): bool =
    if not tableView.xHeaderTracking.isActive():
      return false
    let
      hit = tableView.tableHeaderHitTest(event.location)
      clickedColumn = tableView.xHeaderTracking.column
      clickedPart = tableView.xHeaderTracking.part
      fromIndex = tableView.xHeaderTracking.columnIndex
      moved =
        tableView.xHeaderTracking.draggingColumn or (
          clickedPart == thpColumn and
          abs(event.location.x - tableView.xHeaderTracking.startPoint.x) >
          tableView.tableStyle().headerDragThreshold
        )
      insertionIndex = tableView.xHeaderTracking.insertionIndex
    tableView.xHeaderTracking.clear()
    tableView.xPressedColumn = nil
    if clickedPart == thpColumn and not clickedColumn.isNil:
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
    tableView.needsDisplay = true
    true

  method headerMouseMoved(tableView: TableView, event: MouseEvent): bool =
    let column = tableView.tableHeaderHitTest(event.location).column
    if tableView.xHoveredColumn == column:
      return column != nil
    tableView.xHoveredColumn = column
    tableView.needsDisplay = true
    column != nil

proc installTableColumnProtocol*(tableView: TableView) =
  discard tableView.withProtocol(DefaultTableViewColumnBehavior)

proc installTableLayoutProtocol*(tableView: TableView) =
  discard tableView.withProtocol(DefaultTableViewLayout)

proc installTableDrawingProtocols*(tableView: TableView) =
  discard tableView.withProtocol(DefaultTableViewDrawing)
  discard tableView.withProtocol(DefaultTableViewAccessibility)
