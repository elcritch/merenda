import std/[unicode, unittest]

import figdraw/fignodes
import sigils/core

import merenda/nimkit

type TableDataSourceSpy = ref object of Responder
  rows: int
  textCalls: seq[string]

type EditableTableRow = object
  project: string
  state: string
  owner: string
  elapsed: string

type EditableTableSpy = ref object of Responder
  rows: seq[EditableTableRow]
  commits: seq[string]

type TableEditSignalSpy = ref object of Agent
  source: EditableTableSpy
  events: seq[string]
  observedValues: seq[string]

type TableSelectionSignalSpy = ref object of Agent
  changingEvents: int
  changedEvents: int

type TableColumnUserInfo = ref object of Responder
  label: string

type TableDelegateSpy = ref object of Responder
  disabledRows: seq[int]
  nonselectableRows: seq[int]
  rowHeights: seq[float32]
  hostedColumns: seq[string]
  textFieldColumns: seq[string]
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
  sortChanges: seq[string]
  deniedEditRows: seq[int]
  rejectedEditValues: seq[string]
  editValidationError: string
  beganEdits: seq[string]
  committedEdits: seq[string]
  cancelledEdits: seq[string]
  dragOperation: DragOperations
  dragAccepted: bool

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
  let rowRect = tableView.rowItemRect(row)
  if rowRect.isEmpty:
    return initPoint(0.0, 0.0)
  let actionColumn = tableView.columnAt(1)
  if actionColumn.isNil or tableView.columnCount() < 2:
    return initPoint(
      rowRect.origin.x + rowRect.size.width * 0.5'f32,
      rowRect.origin.y + rowRect.size.height * 0.5'f32,
    )
  let actionX = actionColumn.width() * 0.5'f32
  let leftColumn = tableView.columnAt(0)
  if leftColumn.isNil:
    return initPoint(
      rowRect.origin.x + rowRect.size.width * 0.5'f32,
      rowRect.origin.y + rowRect.size.height * 0.5'f32,
    )
  initPoint(
    actionX + leftColumn.width(), rowRect.origin.y + rowRect.size.height * 0.5'f32
  )

proc tableCellPoint(tableView: TableView, row: int, column: TableColumn): Point =
  let rowRect = tableView.rowItemRect(row)
  if rowRect.isEmpty or column.isNil:
    return tableView.pointToWindow(initPoint(0.0, 0.0))
  let columnRect = tableView.tableColumnRect(column)
  tableView.pointToWindow(
    initPoint(
      columnRect.origin.x + columnRect.size.width * 0.5'f32,
      rowRect.origin.y + rowRect.size.height * 0.5'f32,
    )
  )

proc doubleClickTableCell(
    window: Window, tableView: TableView, row: int, column: TableColumn
): bool =
  let point = tableView.tableCellPoint(row, column)
  window.mouseDownAt(point, clickCount = 2) and window.mouseUpAt(point, clickCount = 2)

func keyForLetter(ch: char): Key =
  if ch in 'a' .. 'z':
    return Key(keyA.ord + ch.ord - 'a'.ord)
  if ch in 'A' .. 'Z':
    return Key(keyA.ord + ch.ord - 'A'.ord)
  keyUnknown

proc typeText(window: Window, text: string): bool =
  for ch in text:
    let key = ch.keyForLetter()
    if not window.dispatchKeyDown(KeyEvent(text: $ch, key: key, keyCode: key.ord)):
      return false
  true

proc pressKey(window: Window, key: Key, modifiers: set[KeyModifier] = {}): bool =
  window.dispatchKeyDown(KeyEvent(key: key, keyCode: key.ord, modifiers: modifiers))

func fieldText(row: EditableTableRow, identifier: string): string =
  case identifier
  of "project": row.project
  of "state": row.state
  of "owner": row.owner
  of "elapsed": row.elapsed
  else: ""

proc setFieldText(row: var EditableTableRow, identifier, value: string) =
  case identifier
  of "project":
    row.project = value
  of "state":
    row.state = value
  of "owner":
    row.owner = value
  of "elapsed":
    row.elapsed = value
  else:
    discard

proc rememberCellEditDidCommit(
    spy: TableEditSignalSpy,
    sender: DynamicAgent,
    row: int,
    column: TableColumn,
    value: string,
) {.slot.} =
  spy.events.add $row & ":" & column.identifier & ":" & value
  if not spy.source.isNil and row in 0 ..< spy.source.rows.len:
    spy.observedValues.add spy.source.rows[row].fieldText(column.identifier)

proc rememberTableSelectionIsChanging(
    spy: TableSelectionSignalSpy, sender: DynamicAgent
) {.slot.} =
  inc spy.changingEvents
  discard sender

proc rememberTableSelectionDidChange(
    spy: TableSelectionSignalSpy, sender: DynamicAgent
) {.slot.} =
  inc spy.changedEvents
  discard sender

proc newTableSelectionSignalSpy(): TableSelectionSignalSpy =
  TableSelectionSignalSpy()

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
        ,
      )
      button.action = action
      return button
    if delegate.textFieldColumns.containsValue(column.identifier):
      return newTextField(text)
    newLabel(text)

  method tableRowHeight(
      delegate: TableDelegateSpy, tableView: TableView, row: int
  ): float32 =
    if row in 0 ..< delegate.rowHeights.len:
      delegate.rowHeights[row]
    else:
      tableView.rowHeight()

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

  method sortDescriptorsDidChange(
      delegate: TableDelegateSpy,
      tableView: TableView,
      column: TableColumn,
      direction: TableSortDirection,
  ) =
    delegate.sortChanges.add column.identifier & ":" & $direction

  method shouldEditCell(
      delegate: TableDelegateSpy, tableView: TableView, row: int, column: TableColumn
  ): bool =
    not delegate.deniedEditRows.containsIndex(row)

  method didBeginEditingCell(
      delegate: TableDelegateSpy, tableView: TableView, row: int, column: TableColumn
  ) =
    delegate.beganEdits.add column.identifier & ":" & $row

  method validationErrorForCell(
      delegate: TableDelegateSpy,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ): string =
    if delegate.rejectedEditValues.containsValue(value):
      return delegate.editValidationError
    ""

  method didCommitEditingCell(
      delegate: TableDelegateSpy,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ) =
    delegate.committedEdits.add column.identifier & ":" & $row & ":" & value

  method didCancelEditingCell(
      delegate: TableDelegateSpy, tableView: TableView, row: int, column: TableColumn
  ) =
    delegate.cancelledEdits.add column.identifier & ":" & $row

  method validateDragOperation(
      delegate: TableDelegateSpy, tableView: TableView, info: DraggingInfo
  ): DragOperations =
    if delegate.dragOperation == NoDragOperations:
      info.selectedOperations
    else:
      delegate.dragOperation

  method acceptDragOperation(
      delegate: TableDelegateSpy, tableView: TableView, info: DraggingInfo
  ): bool =
    delegate.dragAccepted

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

protocol EditableTableSpyDataSource of TableViewDataSource:
  method numberOfRows(source: EditableTableSpy, tableView: TableView): int =
    source.rows.len

  method textForCell(
      source: EditableTableSpy, tableView: TableView, row: int, column: TableColumn
  ): string =
    if row in 0 ..< source.rows.len:
      source.rows[row].fieldText(column.identifier)
    else:
      ""

protocol EditableTableSpyDelegate of TableViewDelegate:
  method viewForCell(
      source: EditableTableSpy, tableView: TableView, row: int, column: TableColumn
  ): View =
    if row in 0 ..< source.rows.len and column.identifier == "state":
      let field = newTextField(source.rows[row].fieldText(column.identifier))
      field.alignment = taCenter
      return field
    nil

  method hitPolicyForCell(
      source: EditableTableSpy,
      tableView: TableView,
      row: int,
      column: TableColumn,
      target: View,
      event: MouseEvent,
  ): CellHitPolicy =
    if column.identifier == "state": chpSelectRow else: chpDefault

  method didCommitEditingCell(
      source: EditableTableSpy,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ) =
    if row in 0 ..< source.rows.len:
      source.rows[row].setFieldText(column.identifier, value)
      source.commits.add column.identifier & ":" & value
      tableView.reloadData()

proc newEditableTableSpy(rows: openArray[EditableTableRow]): EditableTableSpy =
  result = EditableTableSpy(rows: @rows)
  initResponder(result)
  discard result.withProtocol(EditableTableSpyDataSource)
  discard result.withProtocol(EditableTableSpyDelegate)

proc newEditableTableSpy(row: EditableTableRow): EditableTableSpy =
  newEditableTableSpy([row])

proc newTableEditSignalSpy(source: EditableTableSpy): TableEditSignalSpy =
  TableEditSignalSpy(source: source)

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

  test "table headers hit test resize reorder and sort columns":
    let
      tableView = newTableView(frame = initRect(0, 0, 300, 160))
      delegate = newTableDelegateSpy()
      name = newTableColumn("name", "Name", width = 120.0, minWidth = 80.0)
      age = newTableColumn("age", "Age", width = 60.0)

    tableView.delegate = delegate
    tableView.addColumn(name)
    tableView.addColumn(age)

    check tableView.showsHeader()
    check tableView.tableHeaderHeight() == 24.0'f32
    check tableView.tableHeaderHitTest(initPoint(20.0'f32, 10.0'f32)).column == name
    check tableView.tableHeaderHitTest(initPoint(118.0'f32, 10.0'f32)).part ==
      thpResizeHandle

    tableView.resizeColumn(name, 70.0)
    check name.width == 80.0'f32

    tableView.requestSort(age, tsdAscending)
    check age.sortDirection == tsdAscending
    check delegate.sortChanges == @["age:tsdAscending"]

    tableView.moveColumn(1, 0)
    check tableView.columnAt(0) == age
    check tableView.columnAt(1) == name

    age.hidden = true
    var visible: seq[string]
    for column in tableView.visibleColumns():
      visible.add column.identifier
    check visible == @["name"]

  test "table header rendering mouse tracking and persistence adapters":
    let
      tableView = newTableView(frame = initRect(0, 0, 300, 160))
      name = newTableColumn("name", "Name", width = 120.0)
      age = newTableColumn("age", "Age", width = 60.0)
      store = newTableViewStateStore()

    tableView.addColumn(name)
    tableView.addColumn(age)
    tableView.autosaveName = "people"

    var texts = tableView.renderedTexts()
    check texts.contains("Name")
    check texts.contains("Age")

    check tableView.headerMouseMoved(
      MouseEvent(location: initPoint(20.0, 10.0), button: mbPrimary)
    )
    check tableView.headerMouseDown(
      MouseEvent(location: initPoint(20.0, 10.0), button: mbPrimary)
    )
    check tableView.headerMouseUp(
      MouseEvent(location: initPoint(20.0, 10.0), button: mbPrimary)
    )
    check name.sortDirection == tsdAscending

    check tableView.headerMouseDown(
      MouseEvent(location: initPoint(118.0, 10.0), button: mbPrimary)
    )
    check tableView.headerMouseDragged(
      MouseEvent(location: initPoint(180.0, 10.0), button: mbPrimary)
    )
    check tableView.headerMouseUp(
      MouseEvent(location: initPoint(180.0, 10.0), button: mbPrimary)
    )
    check name.width > 120.0'f32

    tableView.saveState(store)
    name.width = 80.0
    tableView.restoreState(store)
    check name.width > 120.0'f32

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
    tableView.showsHeader = false
    tableView.addColumn(newTableColumn("name", "Name", width = 120.0))
    tableView.addColumn(newTableColumn("age", "Age", width = 80.0))
    tableView.delegate = delegate

    var texts = tableView.renderedTexts()
    let summaries: seq[TableVisibleRowSummary] = tableView.visibleRowSummaries()
    check summaries.len == 2
    let content: View = tableView.contentView()
    check not content.isNil
    check tableView.hostedTableCellCount() == 4
    check texts.contains("name:0")
    check texts.contains("age:0")
    check texts.contains("name:1")
    check texts.contains("age:1")

    tableView.scrollRows(1)
    texts = tableView.renderedTexts()

    let scrollSummaries: seq[TableVisibleRowSummary] = tableView.visibleRowSummaries()
    check scrollSummaries[0].index == 1
    check tableView.hostedTableCellCount() == 4
    check not texts.contains("name:0")
    check not texts.contains("age:0")
    check texts.contains("name:1")
    check texts.contains("age:1")
    check texts.contains("name:2")
    check texts.contains("age:2")

  test "table view selection signals are emitted from public API":
    let
      tableView = newTableView()
      spy = newTableSelectionSignalSpy()

    tableView.selectionMode = tsmSingle
    tableView.rowCount = 3

    tableView.connect(selectionIsChanging, spy, rememberTableSelectionIsChanging)
    tableView.connect(selectionDidChange, spy, rememberTableSelectionDidChange)

    tableView.selectedIndex = 1
    check spy.changedEvents == 1
    check spy.changingEvents == 1

    tableView.selectedIndex = 1
    check spy.changedEvents == 1
    check spy.changingEvents == 1

    tableView.selectedIndex = 2
    check spy.changedEvents == 2
    check spy.changingEvents == 2

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

    tableView.selectionMode = tsmMultiple
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
    tableView.showsHeader = false
    tableView.addColumn(newTableColumn("project", "Project", width = 160.0))
    tableView.addColumn(newTableColumn("state", "State", width = 80.0))
    tableView.dataSource = source
    tableView.delegate = delegate
    tableView.rowHeight = 28.0
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    check window.mouseDownAt(tableView.pointToWindow(initPoint(170.0'f32, 42.0'f32)))
    check window.mouseUpAt(tableView.pointToWindow(initPoint(170.0'f32, 42.0'f32)))
    check tableView.selectedIndex == 1

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
    tableView.showsHeader = false
    tableView.addColumn(newTableColumn("project", "Project", width = 160.0))
    tableView.addColumn(newTableColumn("action", "Action", width = 90.0))
    tableView.dataSource = source
    tableView.delegate = delegate
    tableView.rowHeight = 28.0
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    let point = tableView.pointToWindow(initPoint(178.0'f32, 42.0'f32))
    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check tableView.selectedIndex == -1

  test "table action buttons use row-local callbacks when selection does not change":
    let
      window = newWindow("Table hosted button action", frame = initRect(0, 0, 360, 190))
      root = newView(frame = initRect(0, 0, 360, 190))
      tableView = newTableView(frame = initRect(10, 10, 280, 84))
      source = newTableDataSourceSpy(3)
      delegate = newTableDelegateSpy()

    tableView.addColumn(newTableColumn("name", "Name", width = 160.0))
    tableView.addColumn(newTableColumn("action", "Action", width = 88.0))
    tableView.showsHeader = false
    tableView.dataSource = source
    delegate.buttonColumns = @["action"]
    delegate.nonselectableRows = @[1]
    tableView.selectionMode = tsmNone
    tableView.delegate = delegate
    tableView.rowHeight = 22.0
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
    tableView.showsHeader = false
    tableView.addColumn(newTableColumn("project", "Project", width = 160.0))
    tableView.addColumn(newTableColumn("action", "Action", width = 90.0))
    tableView.dataSource = source
    tableView.delegate = delegate
    tableView.rowHeight = 28.0
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    let point = tableView.pointToWindow(initPoint(178.0'f32, 42.0'f32))
    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check tableView.selectedIndex == 1
    check delegate.buttonActionRows == @[1]
    check delegate.beganEdits.len == 0

    tableView.selectedIndex = -1
    delegate.hasPolicy = false
    delegate.hasShouldTrack = true
    delegate.shouldTrackColumn = "action"
    delegate.shouldTrackValue = false
    discard delegate.withProtocol(TableDelegateShouldTrackSpyMethods)

    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check tableView.selectedIndex == 1

  test "table view keeps inherited row selection behavior":
    let tableView = newTableView()

    tableView.rowCount = 5
    tableView.selectionMode = tsmExtended
    tableView.selectedRange = 1 .. 3

    check tableView.selectedIndexes == @[1, 2, 3]
    check tableView.selectedRange == 1 .. 3

  test "table view tracks selected columns clicked cell editing persistence and drag state":
    let
      tableView = newTableView()
      delegate = newTableDelegateSpy()
      name = newTableColumn("name", "Name", width = 120.0)
      state = newTableColumn("state", "State", width = 80.0)

    tableView.rowCount = 4
    tableView.addColumn(name)
    tableView.addColumn(state)
    tableView.delegate = delegate
    tableView.allowsColumnSelection = true

    tableView.selectCell(2, state)
    check tableView.clickedRow == 2
    check tableView.clickedColumn == state
    check tableView.clickedColumnIndex == 1
    check tableView.selectedColumns == @[state]
    check tableView.selectedIndex == 2

    check tableView.beginEditingCell(2, state)
    check tableView.editingState.active
    check delegate.beganEdits == @["state:2"]
    check tableView.commitEditingCell("done")
    check not tableView.editingState.active
    check delegate.committedEdits == @["state:2:done"]

    delegate.deniedEditRows = @[1]
    check not tableView.beginEditingCell(1, name)
    check tableView.beginEditingCell(3, name)
    check tableView.cancelEditingCell()
    check delegate.cancelledEdits == @["name:3"]

    tableView.autosaveName = "main-table"
    state.hidden = true
    tableView.requestSort(name, tsdDescending)
    let records = tableView.columnAutosaveRecords()
    check tableView.autosaveName == "main-table"
    check records.len == 2

    tableView.moveColumn(1, 0)
    state.hidden = false
    name.width = 200.0
    tableView.restoreColumnAutosaveRecords(records)
    check tableView.columnAt(0) == name
    check tableView.columnAt(1) == state
    check state.hidden
    check name.sortDirection == tsdDescending

    delegate.dragOperation = {dgoCopy}
    delegate.dragAccepted = true
    let session = tableView.beginDraggingRows(@[0, 3, 9], {dgoMove}, DragPasteboardName)
    let info = session.draggingInfo()
    check info.tableDraggingRows() == @[0, 3]
    check info.selectedOperations == {dgoMove}
    check tableView.validateDragging(info) == {dgoCopy}
    check tableView.acceptDragging(info)

    let selectionState = tableView.selectionPersistenceString()
    tableView.selectedIndexes = []
    tableView.restoreSelectionPersistenceString(selectionState)
    check tableView.selectedIndexes == @[3]

    let columnDrag =
      tableView.beginDraggingColumns(@[name, state], {dgoCopy}, DragPasteboardName)
    let columnInfo = columnDrag.draggingInfo()
    check columnInfo.tableDraggingColumns() == @["name", "state"]
    check pasteboardWithName(DragPasteboardName).stringForType(PasteboardTypeString) ==
      "name,state"
    let targeted = columnInfo.withDropTarget(row = 1, column = state)
    check targeted.tableDropRow() == 1
    check targeted.tableDropColumn() == "state"

  test "table view hosts field editors for editable cells validates and navigates":
    let
      window = newWindow("Table cell editing", frame = initRect(0, 0, 420, 180))
      root = newView(frame = initRect(0, 0, 420, 180))
      tableView = newTableView(frame = initRect(10, 10, 320, 100))
      source = newTableDataSourceSpy(3)
      delegate = newTableDelegateSpy()
      name = newTableColumn("name", "Name", width = 160.0)
      state = newTableColumn("state", "State", width = 110.0)

    tableView.showsHeader = false
    tableView.addColumn(name)
    tableView.addColumn(state)
    tableView.dataSource = source
    delegate.hostedColumns = @["name"]
    delegate.textFieldColumns = @["name"]
    delegate.rejectedEditValues = @["bad"]
    delegate.editValidationError = "Name cannot be bad"
    tableView.delegate = delegate
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    check tableView.beginEditingCell(0, name)
    check tableView.editingState.active
    check tableView.editingState.row == 0
    check tableView.editingState.column == name
    check delegate.beganEdits == @["name:0"]
    check window.firstResponder == window.fieldEditor()
    check window.fieldEditorClient() == tableView
    check window.fieldEditor().superview() of TextField
    check TextView(window.fieldEditor()).stringValue == "name:0"
    let hostedField = TextField(window.fieldEditor().superview())
    check hostedField.currentEditor() == window.fieldEditor()

    TextView(window.fieldEditor()).stringValue = "bad"
    let editingTexts = hostedField.renderedTexts()
    check editingTexts.containsValue("bad")
    check not editingTexts.containsValue("name:0")
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check tableView.editingState.active
    check tableView.editingState.row == 0
    check tableView.editingValidationError == "Name cannot be bad"
    check delegate.committedEdits.len == 0
    check window.fieldEditorClient() == tableView

    check window.pressKey(keyEscape)
    check not tableView.editingState.active
    check delegate.cancelledEdits == @["name:0"]
    check window.firstResponder() == tableView
    let cancelledTexts = tableView.renderedTexts()
    check cancelledTexts.containsValue("name:0")
    check not cancelledTexts.containsValue("bad")

    check tableView.beginEditingCell(0, name)
    check tableView.editingState.active
    check tableView.editingState.row == 0
    check tableView.editingState.column == name
    check window.fieldEditorClient() == tableView

    TextView(window.fieldEditor()).stringValue = "fixed"
    check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check delegate.committedEdits == @["name:0:fixed"]
    check tableView.editingState.active
    check tableView.editingState.row == 0
    check tableView.editingState.column == state
    check window.fieldEditorClient() == tableView

    check tableView.cancelEditingCell()
    check not tableView.editingState.active
    check delegate.cancelledEdits == @["name:0", "state:0"]
    check window.firstResponder() == tableView

  test "table view user edits hosted and drawn text cells render committed values":
    let
      window =
        newWindow("Table hosted edit integration", frame = initRect(0, 0, 560, 140))
      root = newView(frame = initRect(0, 0, 560, 140))
      tableView = newTableView(frame = initRect(12, 12, 500, 44))
      source = newEditableTableSpy(
        EditableTableRow(
          project: "Alpha", state: "Queued", owner: "June", elapsed: "18m"
        )
      )
      editSpy = newTableEditSignalSpy(source)
      project = newTableColumn("project", "Project", width = 120.0)
      state = newTableColumn("state", "State", width = 180.0, alignment = taCenter)
      owner = newTableColumn("owner", "Owner", width = 80.0)
      elapsed = newTableColumn("elapsed", "Elapsed", width = 60.0)

    tableView.showsHeader = false
    tableView.addColumn(project)
    tableView.addColumn(state)
    tableView.addColumn(owner)
    tableView.addColumn(elapsed)
    tableView.dataSource = source
    tableView.delegate = source
    tableView.connect(cellEditDidCommit, editSpy, rememberCellEditDidCommit)
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    let edits = [
      (column: project, oldValue: "Alpha", newValue: "Beta"),
      (column: state, oldValue: "Queued", newValue: "Done"),
      (column: owner, oldValue: "June", newValue: "Mira"),
      (column: elapsed, oldValue: "18m", newValue: "9h"),
    ]
    for edit in edits:
      check tableView.renderedTexts().containsValue(edit.oldValue)
      check window.doubleClickTableCell(tableView, 0, edit.column)
      check tableView.editingState.active
      check window.firstResponder == window.fieldEditor()
      check TextView(window.fieldEditor()).stringValue == edit.oldValue

      check window.typeText(edit.newValue)
      let editingTexts = tableView.renderedTexts()
      check editingTexts.containsValue(edit.newValue)
      check not editingTexts.containsValue(edit.oldValue)

      check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
      check not tableView.editingState.active
      check source.rows[0].fieldText(edit.column.identifier) == edit.newValue
      check source.commits[^1] == edit.column.identifier & ":" & edit.newValue
      check editSpy.events[^1] == "0:" & edit.column.identifier & ":" & edit.newValue
      check editSpy.observedValues[^1] == edit.newValue
      let committedTexts = tableView.renderedTexts()
      check committedTexts.containsValue(edit.newValue)
      check not committedTexts.containsValue(edit.oldValue)

      check window.doubleClickTableCell(tableView, 0, edit.column)
      check tableView.editingState.active
      check TextView(window.fieldEditor()).stringValue == edit.newValue
      let reopenedTexts = tableView.renderedTexts()
      check reopenedTexts.containsValue(edit.newValue)
      check not reopenedTexts.containsValue(edit.oldValue)
      check tableView.cancelEditingCell()

  test "table view return commits edits and keeps row navigation active":
    let
      window =
        newWindow("Table return edit navigation", frame = initRect(0, 0, 560, 150))
      root = newView(frame = initRect(0, 0, 560, 150))
      tableView = newTableView(frame = initRect(12, 12, 500, 64))
      source = newEditableTableSpy(
        [
          EditableTableRow(
            project: "Alpha", state: "Queued", owner: "June", elapsed: "18m"
          ),
          EditableTableRow(
            project: "Gamma", state: "Running", owner: "Mira", elapsed: "7m"
          ),
        ]
      )
      project = newTableColumn("project", "Project", width = 140.0)
      state = newTableColumn("state", "State", width = 160.0, alignment = taCenter)
      owner = newTableColumn("owner", "Owner", width = 90.0)
      elapsed = newTableColumn("elapsed", "Elapsed", width = 70.0)

    tableView.showsHeader = false
    tableView.addColumn(project)
    tableView.addColumn(state)
    tableView.addColumn(owner)
    tableView.addColumn(elapsed)
    tableView.dataSource = source
    tableView.delegate = source
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    check window.doubleClickTableCell(tableView, 0, project)
    check window.typeText("Beta")
    check window.pressKey(keyEnter)
    check source.rows[0].project == "Beta"
    check not tableView.editingState.active
    check window.firstResponder() == tableView
    check tableView.selectedIndex() == 0
    check tableView.renderedTexts().containsValue("Beta")
    check not tableView.renderedTexts().containsValue("Alpha")

    check window.pressKey(keyArrowDown)
    check tableView.selectedIndex() == 1
    check window.pressKey(keyArrowUp)
    check tableView.selectedIndex() == 0

    check tableView.beginEditingCell(1, project)
    check window.typeText("Delta")
    check window.pressKey(keyEnter)
    check source.rows[1].project == "Delta"
    check not tableView.editingState.active
    check window.firstResponder() == tableView
    let committedTexts = tableView.renderedTexts()
    check committedTexts.containsValue("Beta")
    check committedTexts.containsValue("Delta")
    check not committedTexts.containsValue("Gamma")

  test "table view tab and shift-tab commit and move across editable cells":
    let
      window = newWindow("Table tab edit navigation", frame = initRect(0, 0, 560, 150))
      root = newView(frame = initRect(0, 0, 560, 150))
      tableView = newTableView(frame = initRect(12, 12, 500, 44))
      source = newEditableTableSpy(
        EditableTableRow(
          project: "Alpha", state: "Queued", owner: "June", elapsed: "18m"
        )
      )
      project = newTableColumn("project", "Project", width = 140.0)
      state = newTableColumn("state", "State", width = 160.0, alignment = taCenter)
      owner = newTableColumn("owner", "Owner", width = 90.0)

    tableView.showsHeader = false
    tableView.addColumn(project)
    tableView.addColumn(state)
    tableView.addColumn(owner)
    tableView.dataSource = source
    tableView.delegate = source
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    check window.doubleClickTableCell(tableView, 0, project)
    check window.typeText("Beta")
    check window.pressKey(keyTab)
    check source.rows[0].project == "Beta"
    check tableView.editingState.active
    check tableView.editingState.row == 0
    check tableView.editingState.column == state
    check tableView.clickedColumn() == state
    check TextView(window.fieldEditor()).stringValue == "Queued"

    check window.typeText("Done")
    check window.pressKey(keyTab)
    check source.rows[0].state == "Done"
    check tableView.editingState.active
    check tableView.editingState.column == owner
    check tableView.clickedColumn() == owner
    check TextView(window.fieldEditor()).stringValue == "June"

    check window.typeText("Mira")
    check window.pressKey(keyTab)
    check source.rows[0].owner == "Mira"
    check not tableView.editingState.active
    check window.firstResponder() == tableView
    let forwardTexts = tableView.renderedTexts()
    check forwardTexts.containsValue("Beta")
    check forwardTexts.containsValue("Done")
    check forwardTexts.containsValue("Mira")
    check not forwardTexts.containsValue("Alpha")
    check not forwardTexts.containsValue("Queued")
    check not forwardTexts.containsValue("June")

    check window.doubleClickTableCell(tableView, 0, owner)
    check window.typeText("Nova")
    check window.pressKey(keyTab, {kmShift})
    check source.rows[0].owner == "Nova"
    check tableView.editingState.active
    check tableView.editingState.column == state
    check tableView.clickedColumn() == state
    check TextView(window.fieldEditor()).stringValue == "Done"

    check window.typeText("Blocked")
    check window.pressKey(keyTab, {kmShift})
    check source.rows[0].state == "Blocked"
    check tableView.editingState.active
    check tableView.editingState.column == project
    check tableView.clickedColumn() == project
    check TextView(window.fieldEditor()).stringValue == "Beta"

    check window.typeText("Gamma")
    check window.pressKey(keyTab, {kmShift})
    check source.rows[0].project == "Gamma"
    check not tableView.editingState.active
    check window.firstResponder() == tableView
    let backwardTexts = tableView.renderedTexts()
    check backwardTexts.containsValue("Gamma")
    check backwardTexts.containsValue("Blocked")
    check backwardTexts.containsValue("Nova")
    check not backwardTexts.containsValue("Beta")
    check not backwardTexts.containsValue("Done")
    check not backwardTexts.containsValue("Mira")

  test "table view escape cancels drawn and hosted cell edits":
    let
      window =
        newWindow("Table escape edit cancellation", frame = initRect(0, 0, 560, 140))
      root = newView(frame = initRect(0, 0, 560, 140))
      tableView = newTableView(frame = initRect(12, 12, 500, 44))
      source = newEditableTableSpy(
        EditableTableRow(
          project: "Alpha", state: "Queued", owner: "June", elapsed: "18m"
        )
      )
      project = newTableColumn("project", "Project", width = 140.0)
      state = newTableColumn("state", "State", width = 160.0, alignment = taCenter)
      owner = newTableColumn("owner", "Owner", width = 90.0)

    tableView.showsHeader = false
    tableView.addColumn(project)
    tableView.addColumn(state)
    tableView.addColumn(owner)
    tableView.dataSource = source
    tableView.delegate = source
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    check window.doubleClickTableCell(tableView, 0, owner)
    check window.typeText("Mira")
    check tableView.renderedTexts().containsValue("Mira")
    check not tableView.renderedTexts().containsValue("June")
    check window.pressKey(keyEscape)
    check not tableView.editingState.active
    check window.firstResponder() == tableView
    check source.rows[0].owner == "June"
    check source.commits.len == 0
    check tableView.renderedTexts().containsValue("June")
    check not tableView.renderedTexts().containsValue("Mira")

    check window.doubleClickTableCell(tableView, 0, state)
    check window.typeText("Done")
    check tableView.renderedTexts().containsValue("Done")
    check not tableView.renderedTexts().containsValue("Queued")
    check window.pressKey(keyEscape)
    check not tableView.editingState.active
    check window.firstResponder() == tableView
    check source.rows[0].state == "Queued"
    check source.commits.len == 0
    let restoredTexts = tableView.renderedTexts()
    check restoredTexts.containsValue("Queued")
    check restoredTexts.containsValue("June")
    check not restoredTexts.containsValue("Done")

  test "table view edits drawn text cells and returns focus to row selection":
    let
      window = newWindow("Table drawn cell editing", frame = initRect(0, 0, 420, 180))
      root = newView(frame = initRect(0, 0, 420, 180))
      tableView = newTableView(frame = initRect(10, 10, 320, 100))
      source = newTableDataSourceSpy(2)
      delegate = newTableDelegateSpy()
      name = newTableColumn("name", "Name", width = 160.0)
      state = newTableColumn("state", "State", width = 110.0)

    tableView.showsHeader = false
    tableView.addColumn(name)
    tableView.addColumn(state)
    tableView.dataSource = source
    tableView.delegate = delegate
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    check tableView.beginEditingCell(0, state)
    check window.firstResponder == window.fieldEditor()
    check window.fieldEditor().superview() != nil
    check TextView(window.fieldEditor()).stringValue == "state:0"

    TextView(window.fieldEditor()).stringValue = "done"
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check delegate.committedEdits == @["state:0:done"]
    check not tableView.editingState.active
    check window.firstResponder() == tableView
    check tableView.selectedIndex() == 0

    check window.pressKey(keyArrowDown)
    check tableView.selectedIndex() == 1
    check window.pressKey(keyEnter)
    check tableView.editingState.active
    check tableView.editingState.row == 1
    check tableView.editingState.column == state

    TextView(window.fieldEditor()).stringValue = "last"
    check window.pressKey(keyEnter)
    check delegate.committedEdits == @["state:0:done", "state:1:last"]
    check not tableView.editingState.active
    check window.firstResponder() == tableView

  test "table view queues hosted cell views by reuse identifier":
    let
      tableView = newTableView(frame = initRect(0, 0, 260, 46))
      delegate = newTableDelegateSpy()
      name = newTableColumn("name", "Name", width = 120.0)

    name.reuseIdentifier = "text-cell"
    tableView.rowCount = 4
    tableView.addColumn(name)
    tableView.delegate = delegate
    discard tableView.renderedTexts()

    tableView.recycleVisibleCellViews()
    let reused = tableView.dequeueReusableCellView("text-cell")
    check not reused.isNil

  test "table view pages to scroll edge when trailing rows are disabled":
    let
      window =
        newWindow("Table disabled trailing row", frame = initRect(0, 0, 360, 260))
      root = newView(frame = initRect(0, 0, 360, 260))
      tableView = newTableView(frame = initRect(10, 10, 260, 224))
      delegate = newTableDelegateSpy()
      scrollView = tableView.scrollView()

    tableView.rowCount = 12
    tableView.addColumn(newTableColumn("project", "Project", width = 160.0))
    tableView.rowHeight = 28.0
    delegate.disabledRows = @[11]
    tableView.delegate = delegate
    tableView.selectedIndex = 0
    root.addSubview(tableView)
    window.setContentView(root)

    check window.makeFirstResponder(tableView)
    check window.dispatchKeyDown(KeyEvent(key: keyPageDown, keyCode: keyPageDown.ord))
    check window.dispatchKeyDown(KeyEvent(key: keyPageDown, keyCode: keyPageDown.ord))
    check tableView.selectedIndex == 10
    check scrollView.contentOffset().y == scrollView.maximumContentOffset().y

    check window.dispatchKeyDown(KeyEvent(key: keyPageDown, keyCode: keyPageDown.ord))
    check tableView.selectedIndex == 10
    check scrollView.contentOffset().y == scrollView.maximumContentOffset().y
