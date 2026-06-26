import std/[options, strutils]

import sigils/core

import ../accessibility/accessibilityprotocols
import ../app/windows
import ../controls/controls
import ../drawing
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../themes
import ../view/views
import ./scrollviews
import ./tableviews

export controls, scrollviews, tableviews

type
  CascadingItem* = object
    identifier*: string
    parentIdentifier*: string
    title*: string
    leaf*: bool

  CascadingSelection* = object
    column*: int
    row*: int
    identifier*: string
    title*: string
    leaf*: bool

  CascadingView* = ref object of Control
    xItems: seq[CascadingItem]
    xDataSource: DynamicAgent
    xDelegate: DynamicAgent
    xScrollView: ScrollView
    xColumnContainer: View
    xColumns: seq[TableView]
    xSelectedPath: seq[string]
    xColumnWidth: float32
    xColumnSpacing: float32
    xMinColumnWidth: float32
    xShowsColumnHeaders: bool
    xSyncingColumnSelection: bool

const
  CascadingDefaultColumnWidth = 160.0'f32
  CascadingDefaultMinColumnWidth = 72.0'f32
  CascadingDefaultColumnSpacing = 1.0'f32
  CascadingColumnEdgeInset = 1.0'f32

proc reloadData*(view: CascadingView)
proc selectItem*(view: CascadingView, column, row: int)
proc selectedItem*(view: CascadingView): CascadingSelection
proc scrollView*(view: CascadingView): ScrollView
proc tableViewForColumn*(view: CascadingView, column: int): TableView
proc columnForTableView(view: CascadingView, tableView: TableView): int
proc cascadingItemWithIdentifier*(
  view: CascadingView, identifier: string
): CascadingItem

proc childrenForParent*(
  view: CascadingView, parentIdentifier: string
): seq[CascadingItem]

proc itemHasChildren*(view: CascadingView, identifier: string): bool
proc applySelectedPath(view: CascadingView, path: openArray[string])
proc focusColumnRelative(view: CascadingView, delta: int): bool
proc scrollColumnToVisible(view: CascadingView, column: int)

protocol CascadingDataSource {.selectorScope: protocol.}:
  method cascadingNumberOfChildren*(
    view: CascadingView, parentIdentifier: string
  ): int {.optional.}

  method cascadingChildIdentifier*(
    view: CascadingView, parentIdentifier: string, index: int
  ): string {.optional.}

  method cascadingItem*(
    view: CascadingView, identifier: string
  ): CascadingItem {.optional.}

  method cascadingItemTitle*(
    view: CascadingView, identifier: string
  ): string {.optional.}

  method isLeafCascadingItem*(
    view: CascadingView, identifier: string
  ): bool {.optional.}

protocol CascadingDelegate {.selectorScope: protocol.}:
  method shouldSelectCascadingItem*(
    view: CascadingView, column: int, row: int, identifier: string
  ): bool {.optional.}

  method didSelectCascadingItem*(
    view: CascadingView, column: int, row: int, identifier: string
  ) {.optional.}

  method didActivateCascadingItem*(
    view: CascadingView, column: int, row: int, identifier: string
  ) {.optional.}

  method rowHeightForCascadingColumn*(
    view: CascadingView, column: int
  ): float32 {.optional.}

protocol CascadingEvents:
  proc selectionIsChanging*(view: CascadingView, sender: DynamicAgent) {.signal.}
  proc selectionDidChange*(view: CascadingView, sender: DynamicAgent) {.signal.}
  proc itemWasActivated*(view: CascadingView, sender: DynamicAgent) {.signal.}

protocol CascadingSelectionProtocol:
  method selectionPath*(): seq[string]
  method setSelectionPath*(path: seq[string])
  method selectItemAt*(column, row: int)
  method currentSelection*(): CascadingSelection

protocol CascadingReloadProtocol:
  method reloadViewData*()
  method reloadViewColumn*(column: int)

proc initCascadingItem*(
    identifier: string, title: string, parentIdentifier = "", leaf = false
): CascadingItem =
  CascadingItem(
    identifier: identifier, parentIdentifier: parentIdentifier, title: title, leaf: leaf
  )

proc dataSource*(view: CascadingView): DynamicAgent =
  if view.isNil: nil else: view.xDataSource

proc `dataSource=`*(view: CascadingView, dataSource: DynamicAgent) =
  if view.isNil or view.xDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(CascadingDataSource)
  view.xDataSource = dataSource
  view.reloadData()

proc `dataSource=`*(view: CascadingView, dataSource: Responder) =
  view.dataSource = DynamicAgent(dataSource)

proc delegate*(view: CascadingView): DynamicAgent =
  if view.isNil: nil else: view.xDelegate

proc `delegate=`*(view: CascadingView, delegate: DynamicAgent) =
  if view.isNil or view.xDelegate == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(CascadingDelegate)
  view.xDelegate = delegate
  view.reloadData()

proc `delegate=`*(view: CascadingView, delegate: Responder) =
  view.delegate = DynamicAgent(delegate)

proc cascadingItems*(view: CascadingView): seq[CascadingItem] =
  if view.isNil:
    @[]
  else:
    view.xItems

proc `cascadingItems=`*(view: CascadingView, items: openArray[CascadingItem]) =
  if view.isNil:
    return
  view.xItems = @items
  view.reloadData()

proc columnWidth*(view: CascadingView): float32 =
  if view.isNil: 0.0'f32 else: view.xColumnWidth

proc `columnWidth=`*(view: CascadingView, width: float32) =
  if view.isNil:
    return
  let nextWidth = max(width, view.xMinColumnWidth)
  if view.xColumnWidth == nextWidth:
    return
  view.xColumnWidth = nextWidth
  view.setNeedsLayout()
  view.setNeedsDisplay(true)

proc minColumnWidth*(view: CascadingView): float32 =
  if view.isNil: 0.0'f32 else: view.xMinColumnWidth

proc `minColumnWidth=`*(view: CascadingView, width: float32) =
  if view.isNil:
    return
  let nextWidth = max(width, 1.0'f32)
  if view.xMinColumnWidth == nextWidth:
    return
  view.xMinColumnWidth = nextWidth
  view.xColumnWidth = max(view.xColumnWidth, nextWidth)
  view.setNeedsLayout()
  view.setNeedsDisplay(true)

proc columnSpacing*(view: CascadingView): float32 =
  if view.isNil: 0.0'f32 else: view.xColumnSpacing

proc `columnSpacing=`*(view: CascadingView, spacing: float32) =
  if view.isNil:
    return
  let nextSpacing = max(spacing, 0.0'f32)
  if view.xColumnSpacing == nextSpacing:
    return
  view.xColumnSpacing = nextSpacing
  view.setNeedsLayout()
  view.setNeedsDisplay(true)

proc showsColumnHeaders*(view: CascadingView): bool =
  (not view.isNil) and view.xShowsColumnHeaders

proc `showsColumnHeaders=`*(view: CascadingView, shows: bool) =
  if view.isNil or view.xShowsColumnHeaders == shows:
    return
  view.xShowsColumnHeaders = shows
  for column in view.xColumns:
    column.showsHeader = shows
  view.setNeedsLayout()
  view.setNeedsDisplay(true)

proc columnCount*(view: CascadingView): int =
  if view.isNil: 0 else: view.xColumns.len

proc scrollView*(view: CascadingView): ScrollView =
  if view.isNil: nil else: view.xScrollView

proc tableViewForColumn*(view: CascadingView, column: int): TableView =
  if view.isNil or column notin 0 ..< view.xColumns.len:
    nil
  else:
    view.xColumns[column]

proc columnForTableView(view: CascadingView, tableView: TableView): int =
  if view.isNil:
    return -1
  for index, column in view.xColumns:
    if column == tableView:
      return index
  -1

proc localItemWithIdentifier(
    view: CascadingView, identifier: string
): tuple[found: bool, item: CascadingItem] =
  if view.isNil:
    return
  for item in view.xItems:
    if item.identifier == identifier:
      return (true, item)

proc cascadingItemWithIdentifier*(
    view: CascadingView, identifier: string
): CascadingItem =
  if view.isNil or identifier.len == 0:
    return
  let source = view.dataSource()
  if not source.isNil:
    let item =
      source.trySendLocal(cascadingItem(), (view: view, identifier: identifier))
    if item.isSome:
      result = item.get()
      if result.identifier.len == 0:
        result.identifier = identifier
      if result.title.len == 0:
        let title = source.trySendLocal(
          cascadingItemTitle(), (view: view, identifier: identifier)
        )
        if title.isSome:
          result.title = title.get()
      if result.title.len == 0:
        result.title = result.identifier
      return
    let title =
      source.trySendLocal(cascadingItemTitle(), (view: view, identifier: identifier))
    if title.isSome:
      return initCascadingItem(identifier, title.get())
  let local = view.localItemWithIdentifier(identifier)
  if local.found:
    local.item
  else:
    initCascadingItem(identifier, identifier, leaf = true)

proc parentIdentifierForColumn(view: CascadingView, column: int): string =
  if view.isNil or column <= 0:
    return ""
  if column - 1 in 0 ..< view.xSelectedPath.len:
    view.xSelectedPath[column - 1]
  else:
    ""

proc childrenForParent*(
    view: CascadingView, parentIdentifier: string
): seq[CascadingItem] =
  if view.isNil:
    return @[]
  let source = view.dataSource()
  if not source.isNil:
    let count = source.trySendLocal(
      cascadingNumberOfChildren(), (view: view, parentIdentifier: parentIdentifier)
    )
    if count.isSome:
      for index in 0 ..< max(count.get(), 0):
        let identifier = source.trySendLocal(
          cascadingChildIdentifier(),
          (view: view, parentIdentifier: parentIdentifier, index: index),
        )
        if identifier.isNone or identifier.get().len == 0:
          continue
        var item = view.cascadingItemWithIdentifier(identifier.get())
        if item.parentIdentifier.len == 0 and parentIdentifier.len > 0:
          item.parentIdentifier = parentIdentifier
        result.add item
      return
  for item in view.xItems:
    if item.parentIdentifier == parentIdentifier:
      result.add item

proc itemHasChildren*(view: CascadingView, identifier: string): bool =
  if view.isNil or identifier.len == 0:
    return false
  let source = view.dataSource()
  if not source.isNil:
    let count = source.trySendLocal(
      cascadingNumberOfChildren(), (view: view, parentIdentifier: identifier)
    )
    if count.isSome:
      return count.get() > 0
    let leaf =
      source.trySendLocal(isLeafCascadingItem(), (view: view, identifier: identifier))
    if leaf.isSome:
      return not leaf.get()
  for item in view.xItems:
    if item.parentIdentifier == identifier:
      return true
  false

proc cascadingItemIsLeaf(view: CascadingView, item: CascadingItem): bool =
  if item.identifier.len == 0:
    return true
  let source = view.dataSource()
  if not source.isNil:
    let leaf = source.trySendLocal(
      isLeafCascadingItem(), (view: view, identifier: item.identifier)
    )
    if leaf.isSome:
      return leaf.get()
  if item.leaf:
    return true
  not view.itemHasChildren(item.identifier)

proc cascadingRowForIdentifier(
    view: CascadingView, parentIdentifier, identifier: string
): int =
  if view.isNil or identifier.len == 0:
    return -1
  for index, item in view.childrenForParent(parentIdentifier):
    if item.identifier == identifier:
      return index
  -1

proc itemForColumnRow(view: CascadingView, column, row: int): CascadingItem =
  if view.isNil or row < 0:
    return
  let children = view.childrenForParent(view.parentIdentifierForColumn(column))
  if row in 0 ..< children.len:
    result = children[row]

proc titleForItem(view: CascadingView, item: CascadingItem): string =
  if item.title.len > 0: item.title else: item.identifier

proc selectionFor(
    view: CascadingView, column, row: int, item: CascadingItem
): CascadingSelection =
  CascadingSelection(
    column: column,
    row: row,
    identifier: item.identifier,
    title: view.titleForItem(item),
    leaf: view.cascadingItemIsLeaf(item),
  )

proc selectedPath*(view: CascadingView): seq[string] =
  if view.isNil:
    @[]
  else:
    view.xSelectedPath

proc `selectedPath=`*(view: CascadingView, path: openArray[string]) =
  if view.isNil:
    return
  view.applySelectedPath(path)

proc selectedItem*(view: CascadingView): CascadingSelection =
  if view.isNil or view.xSelectedPath.len == 0:
    return CascadingSelection(column: -1, row: -1)
  let
    column = view.xSelectedPath.high
    identifier = view.xSelectedPath[^1]
    parent = view.parentIdentifierForColumn(column)
    row = view.cascadingRowForIdentifier(parent, identifier)
    item = view.cascadingItemWithIdentifier(identifier)
  view.selectionFor(column, row, item)

proc desiredColumnCount(view: CascadingView): int =
  if view.isNil or view.xSelectedPath.len == 0:
    return 1
  let selected = view.xSelectedPath[^1]
  if view.itemHasChildren(selected):
    view.xSelectedPath.len + 1
  else:
    view.xSelectedPath.len

proc columnsContentWidth(view: CascadingView): float32 =
  if view.isNil or view.xColumns.len == 0:
    return 0.0'f32
  let
    count = view.xColumns.len
    columnWidth = max(view.xColumnWidth, view.xMinColumnWidth)
    spacing = view.xColumnSpacing * max(count - 1, 0).float32
  columnWidth * count.float32 + spacing

proc syncCascadingLayout(view: CascadingView) =
  if view.isNil:
    return
  let bounds = view.bounds()
  if view.xScrollView.isNil or view.xColumnContainer.isNil:
    return
  let
    contentWidth = view.columnsContentWidth()
    documentWidth = max(contentWidth, bounds.size.width)
    oldOffset = view.xScrollView.contentOffset()
  view.xScrollView.frame = bounds
  view.xColumnContainer.frame =
    initRect(0.0'f32, 0.0'f32, documentWidth, bounds.size.height)
  view.xScrollView.tile()
  let
    viewport = view.xScrollView.viewportSize()
    columnWidth = max(view.xColumnWidth, view.xMinColumnWidth)
    documentHeight = viewport.height
  view.xColumnContainer.frame =
    initRect(0.0'f32, 0.0'f32, max(contentWidth, viewport.width), documentHeight)
  if view.xColumns.len == 0:
    view.xScrollView.tile()
    view.xScrollView.contentOffset = oldOffset
    return
  var x = 0.0'f32
  for index, tableView in view.xColumns:
    tableView.frame = initRect(x, 0.0'f32, columnWidth, documentHeight)
    let column = tableView.columnAt(0)
    if not column.isNil:
      column.width = max(columnWidth - CascadingColumnEdgeInset * 2.0'f32, 0.0'f32)
    x += columnWidth
    if index < view.xColumns.high:
      x += view.xColumnSpacing
  view.xScrollView.tile()
  view.xScrollView.contentOffset = oldOffset

proc scrollColumnToVisible(view: CascadingView, column: int) =
  if view.isNil or view.xScrollView.isNil or column notin 0 ..< view.xColumns.len:
    return
  let tableView = view.xColumns[column]
  if tableView.isNil or tableView.frame().isEmpty:
    return
  discard view.xScrollView.scrollRectToVisible(tableView.frame())

proc updateColumnSelections(view: CascadingView) =
  if view.isNil:
    return
  view.xSyncingColumnSelection = true
  try:
    for columnIndex, tableView in view.xColumns:
      tableView.reloadData()
      if columnIndex in 0 ..< view.xSelectedPath.len:
        let row = view.cascadingRowForIdentifier(
          view.parentIdentifierForColumn(columnIndex), view.xSelectedPath[columnIndex]
        )
        tableView.selectedIndex = row
      else:
        tableView.selectedIndex = -1
  finally:
    view.xSyncingColumnSelection = false

proc initCascadingTableView(view: CascadingView): TableView =
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

proc focusedColumnTable(view: CascadingView): TableView =
  if view.isNil:
    return nil
  let owner = view.window()
  if not (owner of Window):
    return nil
  let responder = Window(owner).firstResponder()
  if responder of TableView:
    let tableView = TableView(responder)
    if view.columnForTableView(tableView) >= 0:
      return tableView
  nil

proc focusColumn(view: CascadingView, column: int): bool =
  if view.isNil or column notin 0 ..< view.xColumns.len:
    return false
  let tableView = view.xColumns[column]
  if tableView.isNil:
    return false
  let owner = tableView.window()
  result =
    if owner of Window:
      Window(owner).makeFirstResponder(tableView)
    else:
      false
  view.scrollColumnToVisible(column)

proc clearSelectionFromColumn(view: CascadingView, column: int) =
  if view.isNil or column < 0 or view.xSelectedPath.len <= column:
    return
  var nextPath = view.xSelectedPath
  nextPath.setLen(column)
  view.applySelectedPath(nextPath)

proc focusColumnRelative(view: CascadingView, delta: int): bool =
  if view.isNil or delta == 0:
    return false
  let tableView = view.focusedColumnTable()
  if tableView.isNil:
    return false
  let column = view.columnForTableView(tableView)
  let nextColumn = column + delta
  if nextColumn notin 0 ..< view.xColumns.len:
    return false
  if delta > 0:
    let nextTableView = view.tableViewForColumn(nextColumn)
    if not nextTableView.isNil and nextTableView.selectedIndex() < 0 and
        nextTableView.rowCount() > 0:
      view.selectItem(nextColumn, 0)
  elif delta < 0:
    view.clearSelectionFromColumn(column)
  view.focusColumn(nextColumn)

proc syncCascadingColumns(view: CascadingView) =
  if view.isNil:
    return
  let needed = view.desiredColumnCount()
  while view.xColumns.len > needed:
    let tableView = view.xColumns[^1]
    view.xColumns.setLen(view.xColumns.len - 1)
    if not tableView.isNil:
      tableView.removeFromSuperview()
  while view.xColumns.len < needed:
    let tableView = view.initCascadingTableView()
    view.xColumns.add tableView
    if not view.xColumnContainer.isNil:
      view.xColumnContainer.addSubview(tableView)
  view.syncCascadingLayout()
  view.updateColumnSelections()

proc pruneSelectedPath(view: CascadingView) =
  if view.isNil:
    return
  var parent = ""
  var nextPath: seq[string]
  for identifier in view.xSelectedPath:
    let row = view.cascadingRowForIdentifier(parent, identifier)
    if row < 0:
      break
    nextPath.add identifier
    if not view.itemHasChildren(identifier):
      break
    parent = identifier
  view.xSelectedPath = nextPath

proc normalizedSelectedPath(view: CascadingView, path: openArray[string]): seq[string] =
  if view.isNil:
    return @[]
  let oldPath = view.xSelectedPath
  view.xSelectedPath = @path
  view.pruneSelectedPath()
  result = view.xSelectedPath
  view.xSelectedPath = oldPath

proc applySelectedPath(view: CascadingView, path: openArray[string]) =
  if view.isNil:
    return
  let nextPath = view.normalizedSelectedPath(path)
  if view.xSelectedPath == nextPath:
    view.updateColumnSelections()
    return
  emit view.selectionIsChanging(DynamicAgent(view))
  view.xSelectedPath = nextPath
  view.syncCascadingColumns()
  view.scrollColumnToVisible(min(view.xSelectedPath.len, view.xColumns.high))
  emit view.selectionDidChange(DynamicAgent(view))

proc reloadData*(view: CascadingView) =
  if view.isNil:
    return
  view.pruneSelectedPath()
  view.syncCascadingColumns()
  view.scrollColumnToVisible(min(view.xSelectedPath.len, view.xColumns.high))
  view.invalidateIntrinsicContentSize()
  view.setNeedsDisplay(true)

proc reloadColumn*(view: CascadingView, column: int) =
  if view.isNil or column < 0:
    return
  if column < view.xSelectedPath.len:
    view.xSelectedPath.setLen(column)
  view.reloadData()

proc selectItem*(view: CascadingView, column, row: int) =
  if view.isNil or column < 0:
    return
  let item = view.itemForColumnRow(column, row)
  if item.identifier.len == 0:
    return
  let delegate = view.delegate()
  if not delegate.isNil:
    let allowed = delegate.trySendLocal(
      shouldSelectCascadingItem(),
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
  view.syncCascadingColumns()
  view.scrollColumnToVisible(min(column + 1, view.xColumns.high))
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didSelectCascadingItem(),
      (view: view, column: column, row: row, identifier: item.identifier),
    )
  emit view.selectionDidChange(DynamicAgent(view))

proc activateCascadingItem(view: CascadingView, column, row: int) =
  if view.isNil or column < 0 or row < 0:
    return
  let item = view.itemForColumnRow(column, row)
  if item.identifier.len == 0:
    return
  view.selectItem(column, row)
  let delegate = view.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didActivateCascadingItem(),
      (view: view, column: column, row: row, identifier: item.identifier),
    )
  emit view.itemWasActivated(DynamicAgent(view))
  discard view.sendAction()

protocol CascadingTableDataSource of TableViewDataSource:
  method numberOfRows(view: CascadingView, tableView: TableView): int =
    let column = view.columnForTableView(tableView)
    if column < 0:
      return 0
    view.childrenForParent(view.parentIdentifierForColumn(column)).len

  method textForCell(
      view: CascadingView, tableView: TableView, row: int, column: TableColumn
  ): string =
    discard column
    let columnIndex = view.columnForTableView(tableView)
    if columnIndex < 0:
      return ""
    view.titleForItem(view.itemForColumnRow(columnIndex, row))

  method identifierForRow(view: CascadingView, tableView: TableView, row: int): string =
    let columnIndex = view.columnForTableView(tableView)
    if columnIndex < 0:
      return ""
    view.itemForColumnRow(columnIndex, row).identifier

  method rowForIdentifier(
      view: CascadingView, tableView: TableView, identifier: string
  ): int =
    let columnIndex = view.columnForTableView(tableView)
    if columnIndex < 0:
      return -1
    view.cascadingRowForIdentifier(
      view.parentIdentifierForColumn(columnIndex), identifier
    )

protocol CascadingTableDelegate of TableViewDelegate:
  method tableRowHeight(view: CascadingView, tableView: TableView, row: int): float32 =
    discard row
    let column = view.columnForTableView(tableView)
    let delegate = view.delegate()
    if column >= 0 and not delegate.isNil:
      let height = delegate.trySendLocal(
        rowHeightForCascadingColumn(), (view: view, column: column)
      )
      if height.isSome:
        return height.get()
    tableView.rowHeight()

  method shouldSelectTableRow(
      view: CascadingView, tableView: TableView, row: int
  ): bool =
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
      shouldSelectCascadingItem(),
      (view: view, column: column, row: row, identifier: item.identifier),
    )
    if allowed.isSome:
      allowed.get()
    else:
      true

  method didSelectTableRow(view: CascadingView, tableView: TableView, row: int) =
    if view.xSyncingColumnSelection:
      return
    view.selectItem(view.columnForTableView(tableView), row)

  method didActivateRow(view: CascadingView, tableView: TableView, row: int) =
    let column = view.columnForTableView(tableView)
    view.activateCascadingItem(column, row)

  method shouldEditCell(
      view: CascadingView, tableView: TableView, row: int, column: TableColumn
  ): bool =
    discard view
    discard tableView
    discard row
    discard column
    false

protocol CascadingViewKeyEvents of ResponderEventProtocol:
  method keyDown(view: CascadingView, event: KeyEvent): bool =
    if event.modifiers != {}:
      return false
    case event.key
    of keyArrowLeft:
      view.focusColumnRelative(-1)
    of keyArrowRight:
      view.focusColumnRelative(1)
    else:
      false

protocol CascadingViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(view: CascadingView): IntrinsicSize =
    let
      count = max(view.columnCount(), 1)
      width =
        view.xColumnWidth * count.float32 +
        view.xColumnSpacing * max(count - 1, 0).float32
      height = max(view.tableViewForColumn(0).rowHeight() * 5.0'f32, 96.0'f32)
    initIntrinsicSize(initSize(width, height))

  method layoutSubviews(view: CascadingView) =
    view.syncCascadingLayout()

protocol CascadingSelectionBehavior of CascadingSelectionProtocol:
  method selectionPath(view: CascadingView): seq[string] =
    if view.isNil:
      @[]
    else:
      view.xSelectedPath

  method setSelectionPath(view: CascadingView, path: seq[string]) =
    view.applySelectedPath(path)

  method selectItemAt(view: CascadingView, column, row: int) =
    view.selectItem(column, row)

  method currentSelection(view: CascadingView): CascadingSelection =
    selectedItem(view)

protocol CascadingReloadBehavior of CascadingReloadProtocol:
  method reloadViewData(view: CascadingView) =
    reloadData(view)

  method reloadViewColumn(view: CascadingView, column: int) =
    reloadColumn(view, column)

protocol CascadingDrawing of ViewDrawingProtocol:
  method draw(view: CascadingView, context: DrawContext) =
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

protocol CascadingAccessibility of AccessibilityProtocol:
  method accessibilityRole(view: CascadingView): AccessibilityRole =
    arGroup

  method accessibilityLabel(view: CascadingView): string =
    if view.xAccessibilityLabel.len > 0: view.xAccessibilityLabel else: "CascadingView"

  method accessibilityValue(view: CascadingView): string =
    view.selectedPath().join("/")

  method accessibilityTraits(view: CascadingView): AccessibilityTraits =
    result = view.xAccessibilityTraits + {atSelectable}
    if ssDisabled in view.xWidgetStates:
      result.incl atDisabled
    if view.focused():
      result.incl atFocused

  method isAccessibilityElement(view: CascadingView): bool =
    true

proc initCascadingMillerColumn*(view: CascadingView, frame: Rect = AutoRect) =
  initControlFields(view, frame)
  view.background = initColor(0.0, 0.0, 0.0, 0.0)
  view.clipsToBounds = true
  view.xColumnWidth = CascadingDefaultColumnWidth
  view.xMinColumnWidth = CascadingDefaultMinColumnWidth
  view.xColumnSpacing = CascadingDefaultColumnSpacing
  view.xShowsColumnHeaders = false
  view.xColumnContainer = newView()
  view.xColumnContainer.autoresizingMaskConstraints = false
  view.xScrollView = newScrollView(documentView = view.xColumnContainer)
  view.xScrollView.drawsBackground = false
  view.xScrollView.hasHorizontalScroller = true
  view.xScrollView.hasVerticalScroller = false
  view.xScrollView.horizontalLineScroll = view.xColumnWidth
  view.xScrollView.autoresizingMaskConstraints = false
  view.addSubview(view.xScrollView)
  view.setAcceptsFirstResponder(false)
  discard view.withProtocol(CascadingTableDataSource)
  discard view.withProtocol(CascadingTableDelegate)
  discard view.withProtocol(CascadingViewLayout)
  discard view.withProtocol(CascadingSelectionBehavior)
  discard view.withProtocol(CascadingReloadBehavior)
  discard view.withProtocol(CascadingViewKeyEvents)
  discard view.withProtocol(CascadingDrawing)
  discard view.withProtocol(CascadingAccessibility)
  view.syncCascadingColumns()
  view.applyInitialFrame(frame)

proc initCascadingMillerColumn*(frame: Rect = AutoRect): CascadingView =
  result = CascadingView()
  result.initCascadingMillerColumn(frame)

proc newCascadingView*(frame: Rect = AutoRect): CascadingView =
  result = initCascadingMillerColumn(frame)
