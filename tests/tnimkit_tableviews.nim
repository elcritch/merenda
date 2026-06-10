import std/[unicode, unittest]

import figdraw/fignodes
import sigils/core

import merenda/nimkit

type TableDataSourceSpy = ref object of Responder
  rows: int
  textCalls: seq[string]

type TableColumnUserInfo = ref object of Responder
  label: string

type TableDelegateSpy = ref object of Responder
  disabledRows: seq[int]
  nonselectableRows: seq[int]
  rowHeights: seq[float32]
  hostedColumns: seq[string]
  buttonColumns: seq[string]
  policyColumn: string
  policy: CellHitPolicy
  hasPolicy: bool
  shouldTrackColumn: string
  shouldTrackValue: bool
  hasShouldTrack: bool
  viewCalls: seq[string]
  activatedRows: seq[int]
  buttonActionRows: seq[int]

proc containsIndex(indexes: openArray[int], index: int): bool =
  for value in indexes:
    if value == index:
      return true
  false

proc containsValue(values: openArray[string], value: string): bool =
  for item in values:
    if item == value:
      return true
  false

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add(rune)

proc renderedTexts(view: View): seq[string] =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return @[]
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkText:
      result.add node.renderedText()

proc hostedTableCellCount(tableView: TableView): int =
  let content = tableView.contentView()
  if content.isNil:
    return 0
  for rowView in content.subviews():
    result += rowView.subviews().len

proc tableActionPoint(tableView: TableView, row: int): Point =
  let rowRect = tableView.listItemRect(row)
  if rowRect.isEmpty:
    return initPoint(0.0, 0.0)
  let actionColumn = tableView.columnAt(1)
  if actionColumn.isNil or tableView.columnCount() < 2:
    return initPoint(
      rowRect.origin.x + rowRect.size.width * 0.5'f32,
      rowRect.origin.y + rowRect.size.height * 0.5'f32
    )
  let actionX = actionColumn.width() * 0.5'f32
  let leftColumn = tableView.columnAt(0)
  if leftColumn.isNil:
    return initPoint(
      rowRect.origin.x + rowRect.size.width * 0.5'f32,
      rowRect.origin.y + rowRect.size.height * 0.5'f32
    )
  initPoint(actionX + leftColumn.width(), rowRect.origin.y + rowRect.size.height * 0.5'f32)

protocol TableDataSourceSpyMethods of TableViewDataSource:
  method numberOfRows(source: TableDataSourceSpy, tableView: TableView): int =
    source.rows

  method textForCell(
      source: TableDataSourceSpy, tableView: TableView, row: int, column: TableColumn
  ): string =
    result = column.identifier & ":" & $row
    source.textCalls.add result

protocol TableDelegateSpyMethods of TableViewDelegate:
  method viewForCell(
      delegate: TableDelegateSpy, tableView: TableView, row: int, column: TableColumn
  ): View =
    let text = column.identifier & ":" & $row
    delegate.viewCalls.add text
    if delegate.hostedColumns.len > 0 and
        not delegate.hostedColumns.containsValue(column.identifier):
      return nil
    if delegate.buttonColumns.containsValue(column.identifier):
      let action = actionSelector("tableAction")
      let button = newButton(text)
      button.target = newActionTarget(
        action,
        proc(sender: DynamicAgent) =
          delegate.buttonActionRows.add row
      )
      button.action = action
      return button
    newLabel(text)

  method tableRowHeight(
      delegate: TableDelegateSpy, tableView: TableView, row: int
  ): float32 =
    if row in 0 ..< delegate.rowHeights.len:
      delegate.rowHeights[row]
    else:
      ListView(tableView).rowHeight()

  method isRowEnabled(
      delegate: TableDelegateSpy, tableView: TableView, row: int
  ): bool =
    not delegate.disabledRows.containsIndex(row)

  method shouldSelectTableRow(
      delegate: TableDelegateSpy, tableView: TableView, row: int
  ): bool =
    not delegate.nonselectableRows.containsIndex(row)

  method hitPolicyForCell(
      delegate: TableDelegateSpy,
      tableView: TableView,
      row: int,
      column: TableColumn,
      target: View,
      event: MouseEvent,
  ): CellHitPolicy =
    if delegate.hasPolicy and column.identifier == delegate.policyColumn:
      return delegate.policy
    chpDefault

  method didActivateRow(delegate: TableDelegateSpy, tableView: TableView, row: int) =
    delegate.activatedRows.add row

protocol TableDelegateShouldTrackSpyMethods of TableViewDelegate:
  method shouldTrackCell(
      delegate: TableDelegateSpy,
      tableView: TableView,
      row: int,
      column: TableColumn,
      target: View,
  ): bool =
    if delegate.hasShouldTrack and column.identifier == delegate.shouldTrackColumn:
      return delegate.shouldTrackValue
    true

proc newTableDataSourceSpy(rows: int): TableDataSourceSpy =
  result = TableDataSourceSpy(rows: rows)
  initResponder(result)
  discard result.withProtocol(TableDataSourceSpyMethods)

proc newTableDelegateSpy(): TableDelegateSpy =
  result = TableDelegateSpy()
  initResponder(result)
  discard result.withProtocol(TableDelegateSpyMethods)

suite "NimKit TableView":
  test "table columns expose stable identifiers and mutable display properties":
    let column = newTableColumn(
      "name",
      title = "Name",
      width = 160.0,
      minWidth = 40.0,
      maxWidth = 240.0,
      alignment = taCenter,
      resizePolicy = tcrResizable,
    )

    check column.identifier == "name"
    check column.title == "Name"
    check column.width == 160.0'f32
    check column.minWidth == 40.0'f32
    check column.maxWidth == 240.0'f32
    check column.alignment == taCenter
    check column.resizePolicy == tcrResizable

    column.width = 500.0
    check column.width == 240.0'f32
    column.minWidth = 180.0
    check column.width == 240.0'f32
    column.maxWidth = 190.0
    check column.width == 190.0'f32

    column.title = "Full Name"
    column.alignment = taRight
    column.resizePolicy = tcrFixed
    column.styleId = "primary-name"
    column.styleClasses = ["primary", "text"]
    let userInfo = TableColumnUserInfo(label: "metadata")
    initResponder(userInfo)
    column.userInfo = userInfo

    check column.title == "Full Name"
    check column.alignment == taRight
    check column.resizePolicy == tcrFixed
    check column.styleId == "primary-name"
    check column.styleClasses == @["primary", "text"]
    check column.userInfo == DynamicAgent(userInfo)

  test "table view maintains ordered unique columns":
    let
      tableView = newTableView()
      name = newTableColumn("name", "Name")
      age = newTableColumn("age", "Age")
      email = newTableColumn("email", "Email")

    tableView.addColumn(name)
    tableView.addColumn(email)
    tableView.insertColumn(age, 1)

    check tableView.columnCount == 3
    check tableView.columnAt(0) == name
    check tableView.columnAt(1) == age
    check tableView.columnAt(2) == email
    check tableView.columnIndex("age") == 1
    check tableView.columnWithIdentifier("email") == email
    check tableView.containsColumn("name")
    check name.tableView == tableView

    tableView.addColumn(newTableColumn("age", "Duplicate Age"))
    check tableView.columnCount == 3

    var identifiers: seq[string]
    for column in tableView.columns:
      identifiers.add column.identifier
    check identifiers == @["name", "age", "email"]

    tableView.removeColumn("age")
    check tableView.columnCount == 2
    check age.tableView.isNil
    check tableView.columnIndex("age") == -1

    tableView.removeColumn(email)
    check tableView.columnCount == 1
    check email.tableView.isNil

  test "table columns move cleanly between table views":
    let
      first = newTableView()
      second = newTableView()
      column = newTableColumn("name", "Name")

    first.addColumn(column)
    check first.columnCount == 1
    check column.tableView == first

    second.addColumn(column)
    check first.columnCount == 0
    check second.columnCount == 1
    check second.columnAt(0) == column
    check column.tableView == second

  test "table view row count can be local or data-source backed":
    let tableView = newTableView()

    tableView.rowCount = 4
    check tableView.rowCount == 4
    check len(tableView) == 4

    let source = newTableDataSourceSpy(7)
    tableView.dataSource = source
    check tableView.dataSource == DynamicAgent(source)
    check tableView.rowCount == 7
    check len(tableView) == 7

  test "table view resolves text and hosted cell views through explicit hooks":
    let
      tableView = newTableView()
      source = newTableDataSourceSpy(3)
      delegate = newTableDelegateSpy()
      name = newTableColumn("name", "Name")

    tableView.addColumn(name)
    tableView.dataSource = source
    tableView.delegate = delegate
    source.textCalls.setLen(0)

    check tableView.tableCellText(2, name) == "name:2"
    check source.textCalls == @["name:2"]

    let cellView = tableView.tableCellView(1, name)
    check not cellView.isNil
    check delegate.viewCalls == @["name:1"]

  test "table view falls back to text cells when view hook returns nil":
    let
      tableView = newTableView(frame = initRect(0, 0, 260, 68))
      source = newTableDataSourceSpy(2)
      delegate = newTableDelegateSpy()
      name = newTableColumn("name", "Name", width = 120.0)
      state = newTableColumn("state", "State", width = 80.0)

    delegate.hostedColumns = @["state"]
    tableView.addColumn(name)
    tableView.addColumn(state)
    tableView.dataSource = source
    tableView.delegate = delegate

    check tableView.tableCellView(0, name).isNil

    let texts = tableView.renderedTexts()
    check texts.contains("name:0")
    check texts.contains("state:0")

  test "table view renders text cells for every visible column":
    let
      tableView = newTableView(frame = initRect(0, 0, 260, 68))
      source = newTableDataSourceSpy(3)

    tableView.addColumn(newTableColumn("name", "Name", width = 120.0))
    tableView.addColumn(newTableColumn("age", "Age", width = 80.0))
    tableView.dataSource = source

    let texts = tableView.renderedTexts()

    check texts.contains("name:0")
    check texts.contains("age:0")
    check texts.contains("name:1")
    check texts.contains("age:1")

  test "table view hosts cell views only for visible rows":
    let
      tableView = newTableView(frame = initRect(0, 0, 260, 46))
      delegate = newTableDelegateSpy()

    tableView.rowCount = 5
    tableView.addColumn(newTableColumn("name", "Name", width = 120.0))
    tableView.addColumn(newTableColumn("age", "Age", width = 80.0))
    tableView.delegate = delegate

    var texts = tableView.renderedTexts()
    check tableView.visibleRowSummaries().len == 2
    check tableView.hostedTableCellCount() == 4
    check texts.contains("name:0")
    check texts.contains("age:0")
    check texts.contains("name:1")
    check texts.contains("age:1")

    tableView.scrollRows(1)
    texts = tableView.renderedTexts()

    check tableView.visibleRowSummaries()[0].index == 1
    check tableView.hostedTableCellCount() == 4
    check not texts.contains("name:0")
    check not texts.contains("age:0")
    check texts.contains("name:1")
    check texts.contains("age:1")
    check texts.contains("name:2")
    check texts.contains("age:2")

  test "table row policy hooks feed inherited list row behavior":
    let
      tableView = newTableView()
      delegate = newTableDelegateSpy()

    tableView.rowCount = 4
    delegate.disabledRows = @[1]
    delegate.nonselectableRows = @[2]
    delegate.rowHeights = @[20.0'f32, 30.0'f32, 40.0'f32, 50.0'f32]
    tableView.delegate = delegate

    check tableView.rowEnabled(0)
    check not tableView.rowEnabled(1)
    check tableView.rowSelectable(0)
    check not tableView.rowSelectable(1)
    check not tableView.rowSelectable(2)
    check tableView.rowHeightForRow(3) == 50.0'f32

    tableView.selectionMode = lsmMultiple
    tableView.selectedIndexes = [0, 1, 2, 3]
    check tableView.selectedIndexes == @[0, 3]

  test "table activation hook receives activated row":
    let
      tableView = newTableView()
      delegate = newTableDelegateSpy()

    tableView.rowCount = 3
    tableView.delegate = delegate
    tableView.activateItemAtIndex(2)

    check delegate.activatedRows == @[2]

  test "table view selects rows through hosted label cells":
    let
      window =
        newWindow("Table hosted label selection", frame = initRect(0, 0, 360, 180))
      root = newView(frame = initRect(0, 0, 360, 180))
      tableView = newTableView(frame = initRect(10, 10, 260, 90))
      source = newTableDataSourceSpy(3)
      delegate = newTableDelegateSpy()

    delegate.hostedColumns = @["state"]
    tableView.addColumn(newTableColumn("project", "Project", width = 160.0))
    tableView.addColumn(newTableColumn("state", "State", width = 80.0))
    tableView.dataSource = source
    tableView.delegate = delegate
    ListView(tableView).rowHeight = 28.0
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    check window.mouseDownAt(tableView.pointToWindow(initPoint(170.0'f32, 42.0'f32)))
    check window.mouseUpAt(tableView.pointToWindow(initPoint(170.0'f32, 42.0'f32)))
    check ListView(tableView).selectedIndex == 1

  test "table view lets interactive hosted cells consume clicks by default":
    let
      window =
        newWindow("Table hosted button default", frame = initRect(0, 0, 360, 180))
      root = newView(frame = initRect(0, 0, 360, 180))
      tableView = newTableView(frame = initRect(10, 10, 280, 90))
      source = newTableDataSourceSpy(3)
      delegate = newTableDelegateSpy()

    delegate.hostedColumns = @["action"]
    delegate.buttonColumns = @["action"]
    tableView.addColumn(newTableColumn("project", "Project", width = 160.0))
    tableView.addColumn(newTableColumn("action", "Action", width = 90.0))
    tableView.dataSource = source
    tableView.delegate = delegate
    ListView(tableView).rowHeight = 28.0
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    let point = tableView.pointToWindow(initPoint(178.0'f32, 42.0'f32))
    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check ListView(tableView).selectedIndex == -1

  test "table action buttons use row-local callbacks when selection does not change":
    let
      window =
        newWindow("Table hosted button action", frame = initRect(0, 0, 360, 190))
      root = newView(frame = initRect(0, 0, 360, 190))
      tableView = newTableView(frame = initRect(10, 10, 280, 84))
      source = newTableDataSourceSpy(3)
      delegate = newTableDelegateSpy()

    tableView.addColumn(newTableColumn("name", "Name", width = 160.0))
    tableView.addColumn(newTableColumn("action", "Action", width = 88.0))
    tableView.dataSource = source
    delegate.buttonColumns = @["action"]
    delegate.nonselectableRows = @[1]
    tableView.selectionMode = lsmNone
    tableView.delegate = delegate
    ListView(tableView).rowHeight = 22.0
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    let point = tableView.pointToWindow(tableActionPoint(tableView, 1))
    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check delegate.buttonActionRows == @[1]

  test "table view cell hit policy can select rows around hosted controls":
    let
      window = newWindow("Table hosted button policy", frame = initRect(0, 0, 360, 180))
      root = newView(frame = initRect(0, 0, 360, 180))
      tableView = newTableView(frame = initRect(10, 10, 280, 90))
      source = newTableDataSourceSpy(3)
      delegate = newTableDelegateSpy()

    delegate.hostedColumns = @["action"]
    delegate.buttonColumns = @["action"]
    delegate.hasPolicy = true
    delegate.policyColumn = "action"
    delegate.policy = chpSelectAndTrack
    tableView.addColumn(newTableColumn("project", "Project", width = 160.0))
    tableView.addColumn(newTableColumn("action", "Action", width = 90.0))
    tableView.dataSource = source
    tableView.delegate = delegate
    ListView(tableView).rowHeight = 28.0
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    let point = tableView.pointToWindow(initPoint(178.0'f32, 42.0'f32))
    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check ListView(tableView).selectedIndex == 1

    ListView(tableView).selectedIndex = -1
    delegate.hasPolicy = false
    delegate.hasShouldTrack = true
    delegate.shouldTrackColumn = "action"
    delegate.shouldTrackValue = false
    discard delegate.withProtocol(TableDelegateShouldTrackSpyMethods)

    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check ListView(tableView).selectedIndex == 1

  test "table view keeps inherited row selection behavior":
    let tableView = newTableView()

    tableView.rowCount = 5
    tableView.selectionMode = lsmExtended
    ListView(tableView).selectedRange = 1 .. 3

    check tableView.selectedIndexes == @[1, 2, 3]
    check ListView(tableView).selectedRange == 1 .. 3

  test "table view pages to scroll edge when trailing rows are disabled":
    let
      window =
        newWindow("Table disabled trailing row", frame = initRect(0, 0, 360, 260))
      root = newView(frame = initRect(0, 0, 360, 260))
      tableView = newTableView(frame = initRect(10, 10, 260, 224))
      delegate = newTableDelegateSpy()
      scrollView = ListView(tableView).scrollView()

    tableView.rowCount = 12
    tableView.addColumn(newTableColumn("project", "Project", width = 160.0))
    ListView(tableView).rowHeight = 28.0
    delegate.disabledRows = @[11]
    tableView.delegate = delegate
    ListView(tableView).selectedIndex = 0
    root.addSubview(tableView)
    window.setContentView(root)

    check window.makeFirstResponder(tableView)
    check window.dispatchKeyDown(KeyEvent(key: keyPageDown, keyCode: keyPageDown.ord))
    check window.dispatchKeyDown(KeyEvent(key: keyPageDown, keyCode: keyPageDown.ord))
    check ListView(tableView).selectedIndex == 10
    check scrollView.contentOffset().y == scrollView.maximumContentOffset().y

    check window.dispatchKeyDown(KeyEvent(key: keyPageDown, keyCode: keyPageDown.ord))
    check ListView(tableView).selectedIndex == 10
    check scrollView.contentOffset().y == scrollView.maximumContentOffset().y
