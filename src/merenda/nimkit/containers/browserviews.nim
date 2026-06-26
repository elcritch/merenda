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
  BrowserItem* = object
    identifier*: string
    parentIdentifier*: string
    title*: string
    leaf*: bool

  BrowserSelection* = object
    column*: int
    row*: int
    identifier*: string
    title*: string
    leaf*: bool

  Browser* = ref object of Control
    xItems: seq[BrowserItem]
    xDataSource: DynamicAgent
    xDelegate: DynamicAgent
    xColumns: seq[TableView]
    xSelectedPath: seq[string]
    xColumnWidth: float32
    xColumnSpacing: float32
    xMinColumnWidth: float32
    xShowsColumnHeaders: bool

const
  BrowserDefaultColumnWidth = 160.0'f32
  BrowserDefaultMinColumnWidth = 72.0'f32
  BrowserDefaultColumnSpacing = 1.0'f32

proc reloadData*(browser: Browser)
proc selectItem*(browser: Browser, column, row: int)
proc selectedItem*(browser: Browser): BrowserSelection
proc tableViewForColumn*(browser: Browser, column: int): TableView
proc browserItemWithIdentifier*(browser: Browser, identifier: string): BrowserItem
proc childrenForParent*(browser: Browser, parentIdentifier: string): seq[BrowserItem]
proc itemHasChildren*(browser: Browser, identifier: string): bool

protocol BrowserDataSource {.selectorScope: protocol.}:
  method browserNumberOfChildren*(
    browser: Browser, parentIdentifier: string
  ): int {.optional.}

  method browserChildIdentifier*(
    browser: Browser, parentIdentifier: string, index: int
  ): string {.optional.}

  method browserItem*(browser: Browser, identifier: string): BrowserItem {.optional.}

  method titleForBrowserItem*(browser: Browser, identifier: string): string {.optional.}

  method isLeafBrowserItem*(browser: Browser, identifier: string): bool {.optional.}

protocol BrowserDelegate {.selectorScope: protocol.}:
  method shouldSelectBrowserItem*(
    browser: Browser, column: int, row: int, identifier: string
  ): bool {.optional.}

  method didSelectBrowserItem*(
    browser: Browser, column: int, row: int, identifier: string
  ) {.optional.}

  method didActivateBrowserItem*(
    browser: Browser, column: int, row: int, identifier: string
  ) {.optional.}

  method rowHeightForBrowserColumn*(browser: Browser, column: int): float32 {.optional.}

protocol BrowserEvents:
  proc selectionIsChanging*(browser: Browser, sender: DynamicAgent) {.signal.}
  proc selectionDidChange*(browser: Browser, sender: DynamicAgent) {.signal.}
  proc itemWasActivated*(browser: Browser, sender: DynamicAgent) {.signal.}

protocol BrowserSelectionProtocol:
  method selectedPath*(): seq[string]
  method setSelectedPath*(path: seq[string])
  method selectBrowserItem*(column, row: int)
  method browserSelection*(): BrowserSelection

protocol BrowserReloadProtocol:
  method reloadBrowserData*()
  method reloadBrowserColumn*(column: int)

proc initBrowserItem*(
    identifier: string, title: string, parentIdentifier = "", leaf = false
): BrowserItem =
  BrowserItem(
    identifier: identifier, parentIdentifier: parentIdentifier, title: title, leaf: leaf
  )

proc dataSource*(browser: Browser): DynamicAgent =
  if browser.isNil: nil else: browser.xDataSource

proc `dataSource=`*(browser: Browser, dataSource: DynamicAgent) =
  if browser.isNil or browser.xDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(BrowserDataSource)
  browser.xDataSource = dataSource
  browser.reloadData()

proc `dataSource=`*(browser: Browser, dataSource: Responder) =
  browser.dataSource = DynamicAgent(dataSource)

proc delegate*(browser: Browser): DynamicAgent =
  if browser.isNil: nil else: browser.xDelegate

proc `delegate=`*(browser: Browser, delegate: DynamicAgent) =
  if browser.isNil or browser.xDelegate == delegate:
    return
  if not delegate.isNil:
    discard delegate.adopt(BrowserDelegate)
  browser.xDelegate = delegate
  browser.reloadData()

proc `delegate=`*(browser: Browser, delegate: Responder) =
  browser.delegate = DynamicAgent(delegate)

proc browserItems*(browser: Browser): seq[BrowserItem] =
  if browser.isNil:
    @[]
  else:
    browser.xItems

proc `browserItems=`*(browser: Browser, items: openArray[BrowserItem]) =
  if browser.isNil:
    return
  browser.xItems = @items
  browser.reloadData()

proc columnWidth*(browser: Browser): float32 =
  if browser.isNil: 0.0'f32 else: browser.xColumnWidth

proc `columnWidth=`*(browser: Browser, width: float32) =
  if browser.isNil:
    return
  let nextWidth = max(width, browser.xMinColumnWidth)
  if browser.xColumnWidth == nextWidth:
    return
  browser.xColumnWidth = nextWidth
  browser.setNeedsLayout()
  browser.setNeedsDisplay(true)

proc minColumnWidth*(browser: Browser): float32 =
  if browser.isNil: 0.0'f32 else: browser.xMinColumnWidth

proc `minColumnWidth=`*(browser: Browser, width: float32) =
  if browser.isNil:
    return
  let nextWidth = max(width, 1.0'f32)
  if browser.xMinColumnWidth == nextWidth:
    return
  browser.xMinColumnWidth = nextWidth
  browser.xColumnWidth = max(browser.xColumnWidth, nextWidth)
  browser.setNeedsLayout()
  browser.setNeedsDisplay(true)

proc columnSpacing*(browser: Browser): float32 =
  if browser.isNil: 0.0'f32 else: browser.xColumnSpacing

proc `columnSpacing=`*(browser: Browser, spacing: float32) =
  if browser.isNil:
    return
  let nextSpacing = max(spacing, 0.0'f32)
  if browser.xColumnSpacing == nextSpacing:
    return
  browser.xColumnSpacing = nextSpacing
  browser.setNeedsLayout()
  browser.setNeedsDisplay(true)

proc showsColumnHeaders*(browser: Browser): bool =
  (not browser.isNil) and browser.xShowsColumnHeaders

proc `showsColumnHeaders=`*(browser: Browser, shows: bool) =
  if browser.isNil or browser.xShowsColumnHeaders == shows:
    return
  browser.xShowsColumnHeaders = shows
  for column in browser.xColumns:
    column.showsHeader = shows
  browser.setNeedsLayout()
  browser.setNeedsDisplay(true)

proc columnCount*(browser: Browser): int =
  if browser.isNil: 0 else: browser.xColumns.len

proc tableViewForColumn*(browser: Browser, column: int): TableView =
  if browser.isNil or column notin 0 ..< browser.xColumns.len:
    nil
  else:
    browser.xColumns[column]

proc columnForTableView(browser: Browser, tableView: TableView): int =
  if browser.isNil:
    return -1
  for index, column in browser.xColumns:
    if column == tableView:
      return index
  -1

proc localItemWithIdentifier(
    browser: Browser, identifier: string
): tuple[found: bool, item: BrowserItem] =
  if browser.isNil:
    return
  for item in browser.xItems:
    if item.identifier == identifier:
      return (true, item)

proc browserItemWithIdentifier*(browser: Browser, identifier: string): BrowserItem =
  if browser.isNil or identifier.len == 0:
    return
  let source = browser.dataSource()
  if not source.isNil:
    let item =
      source.trySendLocal(browserItem(), (browser: browser, identifier: identifier))
    if item.isSome:
      result = item.get()
      if result.identifier.len == 0:
        result.identifier = identifier
      if result.title.len == 0:
        let title = source.trySendLocal(
          titleForBrowserItem(), (browser: browser, identifier: identifier)
        )
        if title.isSome:
          result.title = title.get()
      if result.title.len == 0:
        result.title = result.identifier
      return
    let title = source.trySendLocal(
      titleForBrowserItem(), (browser: browser, identifier: identifier)
    )
    if title.isSome:
      return initBrowserItem(identifier, title.get())
  let local = browser.localItemWithIdentifier(identifier)
  if local.found:
    local.item
  else:
    initBrowserItem(identifier, identifier, leaf = true)

proc parentIdentifierForColumn(browser: Browser, column: int): string =
  if browser.isNil or column <= 0:
    return ""
  if column - 1 in 0 ..< browser.xSelectedPath.len:
    browser.xSelectedPath[column - 1]
  else:
    ""

proc childrenForParent*(browser: Browser, parentIdentifier: string): seq[BrowserItem] =
  if browser.isNil:
    return @[]
  let source = browser.dataSource()
  if not source.isNil:
    let count = source.trySendLocal(
      browserNumberOfChildren(), (browser: browser, parentIdentifier: parentIdentifier)
    )
    if count.isSome:
      for index in 0 ..< max(count.get(), 0):
        let identifier = source.trySendLocal(
          browserChildIdentifier(),
          (browser: browser, parentIdentifier: parentIdentifier, index: index),
        )
        if identifier.isNone or identifier.get().len == 0:
          continue
        var item = browser.browserItemWithIdentifier(identifier.get())
        if item.parentIdentifier.len == 0 and parentIdentifier.len > 0:
          item.parentIdentifier = parentIdentifier
        result.add item
      return
  for item in browser.xItems:
    if item.parentIdentifier == parentIdentifier:
      result.add item

proc itemHasChildren*(browser: Browser, identifier: string): bool =
  if browser.isNil or identifier.len == 0:
    return false
  let source = browser.dataSource()
  if not source.isNil:
    let count = source.trySendLocal(
      browserNumberOfChildren(), (browser: browser, parentIdentifier: identifier)
    )
    if count.isSome:
      return count.get() > 0
    let leaf = source.trySendLocal(
      isLeafBrowserItem(), (browser: browser, identifier: identifier)
    )
    if leaf.isSome:
      return not leaf.get()
  for item in browser.xItems:
    if item.parentIdentifier == identifier:
      return true
  false

proc browserItemIsLeaf(browser: Browser, item: BrowserItem): bool =
  if item.identifier.len == 0:
    return true
  let source = browser.dataSource()
  if not source.isNil:
    let leaf = source.trySendLocal(
      isLeafBrowserItem(), (browser: browser, identifier: item.identifier)
    )
    if leaf.isSome:
      return leaf.get()
  if item.leaf:
    return true
  not browser.itemHasChildren(item.identifier)

proc browserRowForIdentifier(
    browser: Browser, parentIdentifier, identifier: string
): int =
  if browser.isNil or identifier.len == 0:
    return -1
  for index, item in browser.childrenForParent(parentIdentifier):
    if item.identifier == identifier:
      return index
  -1

proc itemForColumnRow(browser: Browser, column, row: int): BrowserItem =
  if browser.isNil or row < 0:
    return
  let children = browser.childrenForParent(browser.parentIdentifierForColumn(column))
  if row in 0 ..< children.len:
    result = children[row]

proc titleForItem(browser: Browser, item: BrowserItem): string =
  if item.title.len > 0: item.title else: item.identifier

proc selectionFor(
    browser: Browser, column, row: int, item: BrowserItem
): BrowserSelection =
  BrowserSelection(
    column: column,
    row: row,
    identifier: item.identifier,
    title: browser.titleForItem(item),
    leaf: browser.browserItemIsLeaf(item),
  )

proc selectedPath*(browser: Browser): seq[string] =
  if browser.isNil:
    @[]
  else:
    browser.xSelectedPath

proc `selectedPath=`*(browser: Browser, path: openArray[string]) =
  if browser.isNil:
    return
  browser.setSelectedPath(@path)

proc selectedItem*(browser: Browser): BrowserSelection =
  if browser.isNil or browser.xSelectedPath.len == 0:
    return BrowserSelection(column: -1, row: -1)
  let
    column = browser.xSelectedPath.high
    identifier = browser.xSelectedPath[^1]
    parent = browser.parentIdentifierForColumn(column)
    row = browser.browserRowForIdentifier(parent, identifier)
    item = browser.browserItemWithIdentifier(identifier)
  browser.selectionFor(column, row, item)

proc desiredColumnCount(browser: Browser): int =
  if browser.isNil or browser.xSelectedPath.len == 0:
    return 1
  let selected = browser.xSelectedPath[^1]
  if browser.itemHasChildren(selected):
    browser.xSelectedPath.len + 1
  else:
    browser.xSelectedPath.len

proc syncBrowserLayout(browser: Browser) =
  if browser.isNil:
    return
  let bounds = browser.bounds()
  var x = 0.0'f32
  for index, tableView in browser.xColumns:
    let remaining = max(bounds.size.width - x, browser.xMinColumnWidth)
    let width = min(max(browser.xColumnWidth, browser.xMinColumnWidth), remaining)
    tableView.frame = initRect(x, 0.0'f32, width, bounds.size.height)
    let column = tableView.columnAt(0)
    if not column.isNil:
      column.width = max(width, browser.xMinColumnWidth)
    x += width
    if index < browser.xColumns.high:
      x += browser.xColumnSpacing

proc updateColumnSelections(browser: Browser) =
  if browser.isNil:
    return
  for columnIndex, tableView in browser.xColumns:
    tableView.reloadData()
    if columnIndex in 0 ..< browser.xSelectedPath.len:
      let row = browser.browserRowForIdentifier(
        browser.parentIdentifierForColumn(columnIndex),
        browser.xSelectedPath[columnIndex],
      )
      tableView.selectedIndex = row
    else:
      tableView.selectedIndex = -1

proc initBrowserColumn(browser: Browser): TableView =
  result = newTableView()
  result.showsHeader = browser.xShowsColumnHeaders
  result.usesAlternatingRowBackgrounds = false
  result.selectionMode = tsmSingle
  result.dataSource = DynamicAgent(browser)
  result.delegate = DynamicAgent(browser)
  let column = newTableColumn("item", width = browser.xColumnWidth)
  column.resizePolicy = tcrFixed
  result.addColumn(column)
  `hasHorizontalScroller=`(result.scrollView(), false)
  result.autoresizingMaskConstraints = false
  result.setAcceptsFirstResponder(true)

proc syncBrowserColumns(browser: Browser) =
  if browser.isNil:
    return
  let needed = browser.desiredColumnCount()
  while browser.xColumns.len > needed:
    let tableView = browser.xColumns[^1]
    browser.xColumns.setLen(browser.xColumns.len - 1)
    if not tableView.isNil:
      tableView.removeFromSuperview()
  while browser.xColumns.len < needed:
    let tableView = browser.initBrowserColumn()
    browser.xColumns.add tableView
    browser.addSubview(tableView)
  browser.syncBrowserLayout()
  browser.updateColumnSelections()

proc pruneSelectedPath(browser: Browser) =
  if browser.isNil:
    return
  var parent = ""
  var nextPath: seq[string]
  for identifier in browser.xSelectedPath:
    let row = browser.browserRowForIdentifier(parent, identifier)
    if row < 0:
      break
    nextPath.add identifier
    if not browser.itemHasChildren(identifier):
      break
    parent = identifier
  browser.xSelectedPath = nextPath

proc normalizedSelectedPath(browser: Browser, path: openArray[string]): seq[string] =
  if browser.isNil:
    return @[]
  let oldPath = browser.xSelectedPath
  browser.xSelectedPath = @path
  browser.pruneSelectedPath()
  result = browser.xSelectedPath
  browser.xSelectedPath = oldPath

proc reloadData*(browser: Browser) =
  if browser.isNil:
    return
  browser.pruneSelectedPath()
  browser.syncBrowserColumns()
  browser.invalidateIntrinsicContentSize()
  browser.setNeedsDisplay(true)

proc reloadColumn*(browser: Browser, column: int) =
  if browser.isNil or column < 0:
    return
  if column < browser.xSelectedPath.len:
    browser.xSelectedPath.setLen(column)
  browser.reloadData()

proc selectItem*(browser: Browser, column, row: int) =
  if browser.isNil or column < 0:
    return
  let item = browser.itemForColumnRow(column, row)
  if item.identifier.len == 0:
    return
  let delegate = browser.delegate()
  if not delegate.isNil:
    let allowed = delegate.trySendLocal(
      shouldSelectBrowserItem(),
      (browser: browser, column: column, row: row, identifier: item.identifier),
    )
    if allowed.isSome and not allowed.get():
      browser.updateColumnSelections()
      return

  var nextPath = browser.xSelectedPath
  if nextPath.len > column:
    nextPath.setLen(column)
  while nextPath.len < column:
    nextPath.add ""
  if nextPath.len == column:
    nextPath.add item.identifier
  else:
    nextPath[column] = item.identifier
  nextPath = browser.normalizedSelectedPath(nextPath)

  if browser.xSelectedPath == nextPath:
    browser.updateColumnSelections()
    return

  emit browser.selectionIsChanging(DynamicAgent(browser))
  browser.xSelectedPath = nextPath
  browser.syncBrowserColumns()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didSelectBrowserItem(),
      (browser: browser, column: column, row: row, identifier: item.identifier),
    )
  emit browser.selectionDidChange(DynamicAgent(browser))

proc activateBrowserItem(browser: Browser, column, row: int) =
  if browser.isNil or column < 0 or row < 0:
    return
  let item = browser.itemForColumnRow(column, row)
  if item.identifier.len == 0:
    return
  browser.selectItem(column, row)
  let delegate = browser.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didActivateBrowserItem(),
      (browser: browser, column: column, row: row, identifier: item.identifier),
    )
  emit browser.itemWasActivated(DynamicAgent(browser))
  discard browser.sendAction()

protocol BrowserTableDataSource of TableViewDataSource:
  method numberOfRows(browser: Browser, tableView: TableView): int =
    let column = browser.columnForTableView(tableView)
    if column < 0:
      return 0
    browser.childrenForParent(browser.parentIdentifierForColumn(column)).len

  method textForCell(
      browser: Browser, tableView: TableView, row: int, column: TableColumn
  ): string =
    discard column
    let columnIndex = browser.columnForTableView(tableView)
    if columnIndex < 0:
      return ""
    browser.titleForItem(browser.itemForColumnRow(columnIndex, row))

  method identifierForRow(browser: Browser, tableView: TableView, row: int): string =
    let columnIndex = browser.columnForTableView(tableView)
    if columnIndex < 0:
      return ""
    browser.itemForColumnRow(columnIndex, row).identifier

  method rowForIdentifier(
      browser: Browser, tableView: TableView, identifier: string
  ): int =
    let columnIndex = browser.columnForTableView(tableView)
    if columnIndex < 0:
      return -1
    browser.browserRowForIdentifier(
      browser.parentIdentifierForColumn(columnIndex), identifier
    )

protocol BrowserTableDelegate of TableViewDelegate:
  method tableRowHeight(browser: Browser, tableView: TableView, row: int): float32 =
    discard row
    let column = browser.columnForTableView(tableView)
    let delegate = browser.delegate()
    if column >= 0 and not delegate.isNil:
      let height = delegate.trySendLocal(
        rowHeightForBrowserColumn(), (browser: browser, column: column)
      )
      if height.isSome:
        return height.get()
    tableView.rowHeight()

  method shouldSelectTableRow(browser: Browser, tableView: TableView, row: int): bool =
    let column = browser.columnForTableView(tableView)
    if column < 0:
      return false
    let item = browser.itemForColumnRow(column, row)
    if item.identifier.len == 0:
      return false
    let delegate = browser.delegate()
    if delegate.isNil:
      return true
    let allowed = delegate.trySendLocal(
      shouldSelectBrowserItem(),
      (browser: browser, column: column, row: row, identifier: item.identifier),
    )
    if allowed.isSome:
      allowed.get()
    else:
      true

  method didActivateRow(browser: Browser, tableView: TableView, row: int) =
    let column = browser.columnForTableView(tableView)
    browser.activateBrowserItem(column, row)

protocol BrowserViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(browser: Browser): IntrinsicSize =
    let
      count = max(browser.columnCount(), 1)
      width =
        browser.xColumnWidth * count.float32 +
        browser.xColumnSpacing * max(count - 1, 0).float32
      height = max(browser.tableViewForColumn(0).rowHeight() * 5.0'f32, 96.0'f32)
    initIntrinsicSize(initSize(width, height))

  method layoutSubviews(browser: Browser) =
    browser.syncBrowserLayout()

protocol BrowserSelectionBehavior of BrowserSelectionProtocol:
  method selectedPath(browser: Browser): seq[string] =
    if browser.isNil:
      @[]
    else:
      browser.xSelectedPath

  method setSelectedPath(browser: Browser, path: seq[string]) =
    if browser.isNil:
      return
    let nextPath = browser.normalizedSelectedPath(path)
    if browser.xSelectedPath == nextPath:
      browser.updateColumnSelections()
      return
    emit browser.selectionIsChanging(DynamicAgent(browser))
    browser.xSelectedPath = nextPath
    browser.syncBrowserColumns()
    emit browser.selectionDidChange(DynamicAgent(browser))

  method selectBrowserItem(browser: Browser, column, row: int) =
    browser.selectItem(column, row)

  method browserSelection(browser: Browser): BrowserSelection =
    selectedItem(browser)

protocol BrowserReloadBehavior of BrowserReloadProtocol:
  method reloadBrowserData(browser: Browser) =
    reloadData(browser)

  method reloadBrowserColumn(browser: Browser, column: int) =
    reloadColumn(browser, column)

protocol BrowserDrawing of ViewDrawingProtocol:
  method draw(browser: Browser, context: DrawContext) =
    if browser.isNil or context.isNil or browser.bounds().isEmpty:
      return
    let style = context.appearance.resolveTableViewStyle(
      initControlStyleContext(
        srTableView,
        browser.widgetStateSet(),
        id = browser.styleId(),
        classes = browser.styleClasses(),
      )
    )
    discard context.addRenderRectangle(
      context.renderRectFor(browser.bounds()),
      style.box.fill,
      style.box.borderColor,
      style.box.borderWidth,
      style.box.cornerRadius,
      style.box.shadows,
      clips = true,
    )
    if browser.isFocusVisible():
      context.addFocusRing(context.renderRectFor(browser.bounds()), style.box)

protocol BrowserAccessibility of AccessibilityProtocol:
  method accessibilityRole(browser: Browser): AccessibilityRole =
    arGroup

  method accessibilityLabel(browser: Browser): string =
    if browser.xAccessibilityLabel.len > 0: browser.xAccessibilityLabel else: "Browser"

  method accessibilityValue(browser: Browser): string =
    browser.selectedPath().join("/")

  method accessibilityTraits(browser: Browser): AccessibilityTraits =
    result = browser.xAccessibilityTraits + {atSelectable}
    if ssDisabled in browser.xWidgetStates:
      result.incl atDisabled
    if browser.focused():
      result.incl atFocused

  method isAccessibilityElement(browser: Browser): bool =
    true

proc initBrowserFields*(browser: Browser, frame: Rect = AutoRect) =
  initControlFields(browser, frame)
  browser.background = initColor(0.0, 0.0, 0.0, 0.0)
  browser.clipsToBounds = true
  browser.xColumnWidth = BrowserDefaultColumnWidth
  browser.xMinColumnWidth = BrowserDefaultMinColumnWidth
  browser.xColumnSpacing = BrowserDefaultColumnSpacing
  browser.xShowsColumnHeaders = false
  browser.setAcceptsFirstResponder(false)
  discard browser.withProtocol(BrowserTableDataSource)
  discard browser.withProtocol(BrowserTableDelegate)
  discard browser.withProtocol(BrowserViewLayout)
  discard browser.withProtocol(BrowserSelectionBehavior)
  discard browser.withProtocol(BrowserReloadBehavior)
  discard browser.withProtocol(BrowserDrawing)
  discard browser.withProtocol(BrowserAccessibility)
  browser.syncBrowserColumns()
  browser.applyInitialFrame(frame)

proc newBrowser*(frame: Rect = AutoRect): Browser =
  result = Browser()
  initBrowserFields(result, frame)
