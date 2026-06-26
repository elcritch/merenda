import std/[options, strutils]

import sigils/core

import ../accessibility/accessibilityprotocols
import ../controls/controls
import ../drawing
import ../foundation/selectors
import ../foundation/types
import ../themes
import ../view/views
import ./scrollviews
import ./tableviews

export controls, scrollviews, tableviews

type
  MillerColumnItem* = object
    identifier*: string
    parentIdentifier*: string
    title*: string
    leaf*: bool

  MillerColumnSelection* = object
    column*: int
    row*: int
    identifier*: string
    title*: string
    leaf*: bool

  MillerColumnView* = ref object of Control
    xItems: seq[MillerColumnItem]
    xDataSource: DynamicAgent
    xDelegate: DynamicAgent
    xColumns: seq[TableView]
    xSelectedPath: seq[string]
    xColumnWidth: float32
    xColumnSpacing: float32
    xMinColumnWidth: float32
    xShowsColumnHeaders: bool
    xSyncingColumnSelection: bool

const
  MillerColumnDefaultColumnWidth = 160.0'f32
  MillerColumnDefaultMinColumnWidth = 72.0'f32
  MillerColumnDefaultColumnSpacing = 1.0'f32

proc reloadData*(view: MillerColumnView)
proc selectItem*(view: MillerColumnView, column, row: int)
proc selectedItem*(view: MillerColumnView): MillerColumnSelection
proc tableViewForColumn*(view: MillerColumnView, column: int): TableView
proc columnForTableView(view: MillerColumnView, tableView: TableView): int
proc millerColumnItemWithIdentifier*(view: MillerColumnView, identifier: string): MillerColumnItem
proc childrenForParent*(view: MillerColumnView, parentIdentifier: string): seq[MillerColumnItem]
proc itemHasChildren*(view: MillerColumnView, identifier: string): bool
proc applySelectedPath(view: MillerColumnView, path: openArray[string])

protocol MillerColumnDataSource {.selectorScope: protocol.}:
  method millerColumnNumberOfChildren*(
    view: MillerColumnView, parentIdentifier: string
  ): int {.optional.}

  method millerColumnChildIdentifier*(
    view: MillerColumnView, parentIdentifier: string, index: int
  ): string {.optional.}

  method millerColumnItem*(view: MillerColumnView, identifier: string): MillerColumnItem {.optional.}

  method titleForMillerColumnItem*(view: MillerColumnView, identifier: string): string {.optional.}

  method isLeafMillerColumnItem*(view: MillerColumnView, identifier: string): bool {.optional.}

protocol MillerColumnDelegate {.selectorScope: protocol.}:
  method shouldSelectMillerColumnItem*(
    view: MillerColumnView, column: int, row: int, identifier: string
  ): bool {.optional.}

  method didSelectMillerColumnItem*(
    view: MillerColumnView, column: int, row: int, identifier: string
  ) {.optional.}

  method didActivateMillerColumnItem*(
    view: MillerColumnView, column: int, row: int, identifier: string
  ) {.optional.}

  method rowHeightForMillerColumn*(view: MillerColumnView, column: int): float32 {.optional.}

protocol MillerColumnEvents:
  proc selectionIsChanging*(view: MillerColumnView, sender: DynamicAgent) {.signal.}
  proc selectionDidChange*(view: MillerColumnView, sender: DynamicAgent) {.signal.}
  proc itemWasActivated*(view: MillerColumnView, sender: DynamicAgent) {.signal.}

protocol MillerColumnSelectionProtocol:
  method millerColumnSelectedPath*(): seq[string]
  method setMillerColumnSelectedPath*(path: seq[string])
  method selectMillerColumnItem*(column, row: int)
  method millerColumnSelection*(): MillerColumnSelection

protocol MillerColumnReloadProtocol:
  method reloadMillerColumnData*()
  method reloadMillerColumn*(column: int)

proc initMillerColumnItem*(
    identifier: string, title: string, parentIdentifier = "", leaf = false
): MillerColumnItem =
  MillerColumnItem(
    identifier: identifier, parentIdentifier: parentIdentifier, title: title, leaf: leaf
  )

proc dataSource*(view: MillerColumnView): DynamicAgent =
  if view.isNil: nil else: view.xDataSource

proc `dataSource=`*(view: MillerColumnView, dataSource: DynamicAgent) =
  if view.isNil or view.xDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(MillerColumnDataSource)
  view.xDataSource = dataSource
  view.reloadData()

proc `dataSource=`*(view: MillerColumnView, dataSource: Responder) =
  view.dataSource = DynamicAgent(dataSource)

proc delegate*(view: MillerColumnView): DynamicAgent =
  if view.isNil: nil else: view.xDelegate

proc `delegate=`*(view: MillerColumnView, delegate: DynamicAgent) =
  if view.isNil or view.xDelegate == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(MillerColumnDelegate)
  view.xDelegate = delegate
  view.reloadData()

proc `delegate=`*(view: MillerColumnView, delegate: Responder) =
  view.delegate = DynamicAgent(delegate)

proc millerColumnItems*(view: MillerColumnView): seq[MillerColumnItem] =
  if view.isNil:
    @[]
  else:
    view.xItems

proc `millerColumnItems=`*(view: MillerColumnView, items: openArray[MillerColumnItem]) =
  if view.isNil:
    return
  view.xItems = @items
  view.reloadData()

proc columnWidth*(view: MillerColumnView): float32 =
  if view.isNil: 0.0'f32 else: view.xColumnWidth

proc `columnWidth=`*(view: MillerColumnView, width: float32) =
  if view.isNil:
    return
  let nextWidth = max(width, view.xMinColumnWidth)
  if view.xColumnWidth == nextWidth:
    return
  view.xColumnWidth = nextWidth
  view.setNeedsLayout()
  view.setNeedsDisplay(true)

proc minColumnWidth*(view: MillerColumnView): float32 =
  if view.isNil: 0.0'f32 else: view.xMinColumnWidth

proc `minColumnWidth=`*(view: MillerColumnView, width: float32) =
  if view.isNil:
    return
  let nextWidth = max(width, 1.0'f32)
  if view.xMinColumnWidth == nextWidth:
    return
  view.xMinColumnWidth = nextWidth
  view.xColumnWidth = max(view.xColumnWidth, nextWidth)
  view.setNeedsLayout()
  view.setNeedsDisplay(true)

proc columnSpacing*(view: MillerColumnView): float32 =
  if view.isNil: 0.0'f32 else: view.xColumnSpacing

proc `columnSpacing=`*(view: MillerColumnView, spacing: float32) =
  if view.isNil:
    return
  let nextSpacing = max(spacing, 0.0'f32)
  if view.xColumnSpacing == nextSpacing:
    return
  view.xColumnSpacing = nextSpacing
  view.setNeedsLayout()
  view.setNeedsDisplay(true)

proc showsColumnHeaders*(view: MillerColumnView): bool =
  (not view.isNil) and view.xShowsColumnHeaders

proc `showsColumnHeaders=`*(view: MillerColumnView, shows: bool) =
  if view.isNil or view.xShowsColumnHeaders == shows:
    return
  view.xShowsColumnHeaders = shows
  for column in view.xColumns:
    column.showsHeader = shows
  view.setNeedsLayout()
  view.setNeedsDisplay(true)

proc columnCount*(view: MillerColumnView): int =
  if view.isNil: 0 else: view.xColumns.len

proc tableViewForColumn*(view: MillerColumnView, column: int): TableView =
  if view.isNil or column notin 0 ..< view.xColumns.len:
    nil
  else:
    view.xColumns[column]

proc columnForTableView(view: MillerColumnView, tableView: TableView): int =
  if view.isNil:
    return -1
  for index, column in view.xColumns:
    if column == tableView:
      return index
  -1

proc localItemWithIdentifier(
    view: MillerColumnView, identifier: string
): tuple[found: bool, item: MillerColumnItem] =
  if view.isNil:
    return
  for item in view.xItems:
    if item.identifier == identifier:
      return (true, item)

proc millerColumnItemWithIdentifier*(view: MillerColumnView, identifier: string): MillerColumnItem =
  if view.isNil or identifier.len == 0:
    return
  let source = view.dataSource()
  if not source.isNil:
    let item =
      source.trySendLocal(millerColumnItem(), (view: view, identifier: identifier))
    if item.isSome:
      result = item.get()
      if result.identifier.len == 0:
        result.identifier = identifier
      if result.title.len == 0:
        let title = source.trySendLocal(
          titleForMillerColumnItem(), (view: view, identifier: identifier)
        )
        if title.isSome:
          result.title = title.get()
      if result.title.len == 0:
        result.title = result.identifier
      return
    let title = source.trySendLocal(
      titleForMillerColumnItem(), (view: view, identifier: identifier)
    )
    if title.isSome:
      return initMillerColumnItem(identifier, title.get())
  let local = view.localItemWithIdentifier(identifier)
  if local.found:
    local.item
  else:
    initMillerColumnItem(identifier, identifier, leaf = true)

proc parentIdentifierForColumn(view: MillerColumnView, column: int): string =
  if view.isNil or column <= 0:
    return ""
  if column - 1 in 0 ..< view.xSelectedPath.len:
    view.xSelectedPath[column - 1]
  else:
    ""

proc childrenForParent*(view: MillerColumnView, parentIdentifier: string): seq[MillerColumnItem] =
  if view.isNil:
    return @[]
  let source = view.dataSource()
  if not source.isNil:
    let count = source.trySendLocal(
      millerColumnNumberOfChildren(), (view: view, parentIdentifier: parentIdentifier)
    )
    if count.isSome:
      for index in 0 ..< max(count.get(), 0):
        let identifier = source.trySendLocal(
          millerColumnChildIdentifier(),
          (view: view, parentIdentifier: parentIdentifier, index: index),
        )
        if identifier.isNone or identifier.get().len == 0:
          continue
        var item = view.millerColumnItemWithIdentifier(identifier.get())
        if item.parentIdentifier.len == 0 and parentIdentifier.len > 0:
          item.parentIdentifier = parentIdentifier
        result.add item
      return
  for item in view.xItems:
    if item.parentIdentifier == parentIdentifier:
      result.add item

proc itemHasChildren*(view: MillerColumnView, identifier: string): bool =
  if view.isNil or identifier.len == 0:
    return false
  let source = view.dataSource()
  if not source.isNil:
    let count = source.trySendLocal(
      millerColumnNumberOfChildren(), (view: view, parentIdentifier: identifier)
    )
    if count.isSome:
      return count.get() > 0
    let leaf = source.trySendLocal(
      isLeafMillerColumnItem(), (view: view, identifier: identifier)
    )
    if leaf.isSome:
      return not leaf.get()
  for item in view.xItems:
    if item.parentIdentifier == identifier:
      return true
  false

proc millerColumnItemIsLeaf(view: MillerColumnView, item: MillerColumnItem): bool =
  if item.identifier.len == 0:
    return true
  let source = view.dataSource()
  if not source.isNil:
    let leaf = source.trySendLocal(
      isLeafMillerColumnItem(), (view: view, identifier: item.identifier)
    )
    if leaf.isSome:
      return leaf.get()
  if item.leaf:
    return true
  not view.itemHasChildren(item.identifier)

proc millerColumnRowForIdentifier(
    view: MillerColumnView, parentIdentifier, identifier: string
): int =
  if view.isNil or identifier.len == 0:
    return -1
  for index, item in view.childrenForParent(parentIdentifier):
    if item.identifier == identifier:
      return index
  -1

proc itemForColumnRow(view: MillerColumnView, column, row: int): MillerColumnItem =
  if view.isNil or row < 0:
    return
  let children = view.childrenForParent(view.parentIdentifierForColumn(column))
  if row in 0 ..< children.len:
    result = children[row]

proc titleForItem(view: MillerColumnView, item: MillerColumnItem): string =
  if item.title.len > 0: item.title else: item.identifier

proc selectionFor(
    view: MillerColumnView, column, row: int, item: MillerColumnItem
): MillerColumnSelection =
  MillerColumnSelection(
    column: column,
    row: row,
    identifier: item.identifier,
    title: view.titleForItem(item),
    leaf: view.millerColumnItemIsLeaf(item),
  )

proc selectedPath*(view: MillerColumnView): seq[string] =
  if view.isNil:
    @[]
  else:
    view.xSelectedPath

proc `selectedPath=`*(view: MillerColumnView, path: openArray[string]) =
  if view.isNil:
    return
  view.applySelectedPath(path)

proc selectedItem*(view: MillerColumnView): MillerColumnSelection =
  if view.isNil or view.xSelectedPath.len == 0:
    return MillerColumnSelection(column: -1, row: -1)
  let
    column = view.xSelectedPath.high
    identifier = view.xSelectedPath[^1]
    parent = view.parentIdentifierForColumn(column)
    row = view.millerColumnRowForIdentifier(parent, identifier)
    item = view.millerColumnItemWithIdentifier(identifier)
  view.selectionFor(column, row, item)

proc desiredColumnCount(view: MillerColumnView): int =
  if view.isNil or view.xSelectedPath.len == 0:
    return 1
  let selected = view.xSelectedPath[^1]
  if view.itemHasChildren(selected):
    view.xSelectedPath.len + 1
  else:
    view.xSelectedPath.len

proc syncMillerColumnLayout(view: MillerColumnView) =
  if view.isNil:
    return
  let bounds = view.bounds()
  var x = 0.0'f32
  for index, tableView in view.xColumns:
    let remaining = max(bounds.size.width - x, view.xMinColumnWidth)
    let width = min(max(view.xColumnWidth, view.xMinColumnWidth), remaining)
    tableView.frame = initRect(x, 0.0'f32, width, bounds.size.height)
    let column = tableView.columnAt(0)
    if not column.isNil:
      column.width = max(width, view.xMinColumnWidth)
    x += width
    if index < view.xColumns.high:
      x += view.xColumnSpacing

proc updateColumnSelections(view: MillerColumnView) =
  if view.isNil:
    return
  view.xSyncingColumnSelection = true
  try:
    for columnIndex, tableView in view.xColumns:
      tableView.reloadData()
      if columnIndex in 0 ..< view.xSelectedPath.len:
        let row = view.millerColumnRowForIdentifier(
          view.parentIdentifierForColumn(columnIndex),
          view.xSelectedPath[columnIndex],
        )
        tableView.selectedIndex = row
      else:
        tableView.selectedIndex = -1
  finally:
    view.xSyncingColumnSelection = false

proc initMillerColumnColumn(view: MillerColumnView): TableView =
  result = newTableView()
  result.showsHeader = view.xShowsColumnHeaders
  result.usesAlternatingRowBackgrounds = false
  result.selectionMode = tsmSingle
  result.dataSource = DynamicAgent(view)
  result.delegate = DynamicAgent(view)
  let column = newTableColumn("item", width = view.xColumnWidth)
  column.resizePolicy = tcrFixed
  result.addColumn(column)
  `hasHorizontalScroller=`(result.scrollView(), false)
  result.autoresizingMaskConstraints = false
  result.setAcceptsFirstResponder(true)

proc syncMillerColumnColumns(view: MillerColumnView) =
  if view.isNil:
    return
  let needed = view.desiredColumnCount()
  while view.xColumns.len > needed:
    let tableView = view.xColumns[^1]
    view.xColumns.setLen(view.xColumns.len - 1)
    if not tableView.isNil:
      tableView.removeFromSuperview()
  while view.xColumns.len < needed:
    let tableView = view.initMillerColumnColumn()
    view.xColumns.add tableView
    view.addSubview(tableView)
  view.syncMillerColumnLayout()
  view.updateColumnSelections()

proc pruneSelectedPath(view: MillerColumnView) =
  if view.isNil:
    return
  var parent = ""
  var nextPath: seq[string]
  for identifier in view.xSelectedPath:
    let row = view.millerColumnRowForIdentifier(parent, identifier)
    if row < 0:
      break
    nextPath.add identifier
    if not view.itemHasChildren(identifier):
      break
    parent = identifier
  view.xSelectedPath = nextPath

proc normalizedSelectedPath(view: MillerColumnView, path: openArray[string]): seq[string] =
  if view.isNil:
    return @[]
  let oldPath = view.xSelectedPath
  view.xSelectedPath = @path
  view.pruneSelectedPath()
  result = view.xSelectedPath
  view.xSelectedPath = oldPath

proc applySelectedPath(view: MillerColumnView, path: openArray[string]) =
  if view.isNil:
    return
  let nextPath = view.normalizedSelectedPath(path)
  if view.xSelectedPath == nextPath:
    view.updateColumnSelections()
    return
  emit view.selectionIsChanging(DynamicAgent(view))
  view.xSelectedPath = nextPath
  view.syncMillerColumnColumns()
  emit view.selectionDidChange(DynamicAgent(view))

proc reloadData*(view: MillerColumnView) =
  if view.isNil:
    return
  view.pruneSelectedPath()
  view.syncMillerColumnColumns()
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc reloadColumn*(view: MillerColumnView, column: int) =
  if view.isNil or column < 0:
    return
  if column < view.xSelectedPath.len:
    view.xSelectedPath.setLen(column)
  view.reloadData()

proc selectItem*(view: MillerColumnView, column, row: int) =
  if view.isNil or column < 0:
    return
  let item = view.itemForColumnRow(column, row)
  if item.identifier.len == 0:
    return
  let delegate = view.delegate()
  if not delegate.isNil:
    let allowed = delegate.trySendLocal(
      shouldSelectMillerColumnItem(),
      (view: view, column: column, row: row, identifier: item.identifier),
    )
    if allowed.isSome and not allowed.get():
      view.updateColumnSelections()
      return

  var nextPath = view.xSelectedPath
  if nextPath.len > column:
    nextPath.setLen(column)
  while nextPath.len < column:
    nextPath.add ""
  if nextPath.len == column:
    nextPath.add item.identifier
  else:
    nextPath[column] = item.identifier
  nextPath = view.normalizedSelectedPath(nextPath)

  if view.xSelectedPath == nextPath:
    view.updateColumnSelections()
    return

  emit view.selectionIsChanging(DynamicAgent(view))
  view.xSelectedPath = nextPath
  view.syncMillerColumnColumns()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didSelectMillerColumnItem(),
      (view: view, column: column, row: row, identifier: item.identifier),
    )
  emit view.selectionDidChange(DynamicAgent(view))

proc activateMillerColumnItem(view: MillerColumnView, column, row: int) =
  if view.isNil or column < 0 or row < 0:
    return
  let item = view.itemForColumnRow(column, row)
  if item.identifier.len == 0:
    return
  view.selectItem(column, row)
  let delegate = view.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didActivateMillerColumnItem(),
      (view: view, column: column, row: row, identifier: item.identifier),
    )
  emit view.itemWasActivated(DynamicAgent(view))
  discard view.sendAction()

protocol MillerColumnTableDataSource of TableViewDataSource:
  method numberOfRows(view: MillerColumnView, tableView: TableView): int =
    let column = view.columnForTableView(tableView)
    if column < 0:
      return 0
    view.childrenForParent(view.parentIdentifierForColumn(column)).len

  method textForCell(
      view: MillerColumnView, tableView: TableView, row: int, column: TableColumn
  ): string =
    discard column
    let columnIndex = view.columnForTableView(tableView)
    if columnIndex < 0:
      return ""
    view.titleForItem(view.itemForColumnRow(columnIndex, row))

  method identifierForRow(view: MillerColumnView, tableView: TableView, row: int): string =
    let columnIndex = view.columnForTableView(tableView)
    if columnIndex < 0:
      return ""
    view.itemForColumnRow(columnIndex, row).identifier

  method rowForIdentifier(
      view: MillerColumnView, tableView: TableView, identifier: string
  ): int =
    let columnIndex = view.columnForTableView(tableView)
    if columnIndex < 0:
      return -1
    view.millerColumnRowForIdentifier(
      view.parentIdentifierForColumn(columnIndex), identifier
    )

protocol MillerColumnTableDelegate of TableViewDelegate:
  method tableRowHeight(view: MillerColumnView, tableView: TableView, row: int): float32 =
    discard row
    let column = view.columnForTableView(tableView)
    let delegate = view.delegate()
    if column >= 0 and not delegate.isNil:
      let height = delegate.trySendLocal(
        rowHeightForMillerColumn(), (view: view, column: column)
      )
      if height.isSome:
        return height.get()
    tableView.rowHeight()

  method shouldSelectTableRow(view: MillerColumnView, tableView: TableView, row: int): bool =
    let column = view.columnForTableView(tableView)
    if column < 0:
      return false
    let item = view.itemForColumnRow(column, row)
    if item.identifier.len == 0:
      return false
    let delegate = view.delegate()
    if delegate.isNil:
      return true
    let allowed = delegate.trySendLocal(
      shouldSelectMillerColumnItem(),
      (view: view, column: column, row: row, identifier: item.identifier),
    )
    if allowed.isSome:
      allowed.get()
    else:
      true

  method didSelectTableRow(view: MillerColumnView, tableView: TableView, row: int) =
    if view.xSyncingColumnSelection:
      return
    view.selectItem(view.columnForTableView(tableView), row)

  method didActivateRow(view: MillerColumnView, tableView: TableView, row: int) =
    let column = view.columnForTableView(tableView)
    view.activateMillerColumnItem(column, row)

protocol MillerColumnViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: MillerColumnView): IntrinsicSize =
    let
      count = max(view.columnCount(), 1)
      width =
        view.xColumnWidth * count.float32 +
        view.xColumnSpacing * max(count - 1, 0).float32
      height = max(view.tableViewForColumn(0).rowHeight() * 5.0'f32, 96.0'f32)
    initIntrinsicSize(initSize(width, height))

  method layoutSubviews(view: MillerColumnView) =
    view.syncMillerColumnLayout()

protocol MillerColumnSelectionBehavior of MillerColumnSelectionProtocol:
  method millerColumnSelectedPath(view: MillerColumnView): seq[string] =
    if view.isNil:
      @[]
    else:
      view.xSelectedPath

  method setMillerColumnSelectedPath(view: MillerColumnView, path: seq[string]) =
    view.applySelectedPath(path)

  method selectMillerColumnItem(view: MillerColumnView, column, row: int) =
    view.selectItem(column, row)

  method millerColumnSelection(view: MillerColumnView): MillerColumnSelection =
    selectedItem(view)

protocol MillerColumnReloadBehavior of MillerColumnReloadProtocol:
  method reloadMillerColumnData(view: MillerColumnView) =
    reloadData(view)

  method reloadMillerColumn(view: MillerColumnView, column: int) =
    reloadColumn(view, column)

protocol MillerColumnDrawing of ViewDrawingProtocol:
  method draw(view: MillerColumnView, context: DrawContext) =
    if view.isNil or context.isNil or view.bounds().isEmpty:
      return
    let style = context.appearance.resolveTableViewStyle(
      initControlStyleContext(
        srTableView,
        view.widgetStateSet(),
        id = view.styleId(),
        classes = view.styleClasses(),
      )
    )
    discard context.addRenderRectangle(
      context.renderRectFor(view.bounds()),
      style.box.fill,
      style.box.borderColor,
      style.box.borderWidth,
      style.box.cornerRadius,
      style.box.shadows,
      clips = true,
    )
    if view.isFocusVisible():
      context.addFocusRing(context.renderRectFor(view.bounds()), style.box)

protocol MillerColumnAccessibility of AccessibilityProtocol:
  method accessibilityRole(view: MillerColumnView): AccessibilityRole =
    arGroup

  method accessibilityLabel(view: MillerColumnView): string =
    if view.xAccessibilityLabel.len > 0: view.xAccessibilityLabel else: "MillerColumnView"

  method accessibilityValue(view: MillerColumnView): string =
    view.selectedPath().join("/")

  method accessibilityTraits(view: MillerColumnView): AccessibilityTraits =
    result = view.xAccessibilityTraits + {atSelectable}
    if ssDisabled in view.xWidgetStates:
      result.incl atDisabled
    if view.focused():
      result.incl atFocused

  method isAccessibilityElement(view: MillerColumnView): bool =
    true

proc initMillerColumnViewFields*(view: MillerColumnView, frame: Rect = AutoRect) =
  initControlFields(view, frame)
  view.background = initColor(0.0, 0.0, 0.0, 0.0)
  view.clipsToBounds = true
  view.xColumnWidth = MillerColumnDefaultColumnWidth
  view.xMinColumnWidth = MillerColumnDefaultMinColumnWidth
  view.xColumnSpacing = MillerColumnDefaultColumnSpacing
  view.xShowsColumnHeaders = false
  view.setAcceptsFirstResponder(false)
  discard view.withProtocol(MillerColumnTableDataSource)
  discard view.withProtocol(MillerColumnTableDelegate)
  discard view.withProtocol(MillerColumnViewLayout)
  discard view.withProtocol(MillerColumnSelectionBehavior)
  discard view.withProtocol(MillerColumnReloadBehavior)
  discard view.withProtocol(MillerColumnDrawing)
  discard view.withProtocol(MillerColumnAccessibility)
  view.syncMillerColumnColumns()
  view.applyInitialFrame(frame)

proc newMillerColumnView*(frame: Rect = AutoRect): MillerColumnView =
  result = MillerColumnView()
  initMillerColumnViewFields(result, frame)
