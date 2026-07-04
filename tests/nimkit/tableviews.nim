import std/[algorithm, options, sequtils, unicode, unittest]

import figdraw/fignodes
import sigils/core

import merenda/nimkit
import merenda/nimkit/foundation/types as nimkitTypes

type TableDataSourceSpy = ref object of Responder
  rows: int
  textCalls: seq[string]

type EditableTableRow = object
  project: string
  state: string
  owner: string
  elapsed: string

type SortableTableRow = object
  id: string
  project: string
  rank: string

type EditableTableSpy = ref object of Responder
  rows: seq[EditableTableRow]
  commits: seq[string]

type SortableTableSpy = ref object of Responder
  rows: seq[SortableTableRow]
  sortChanges: seq[string]

type TableEditSignalSpy = ref object of Agent
  source: EditableTableSpy
  events: seq[string]
  observedValues: seq[string]

type TableSelectionSignalSpy = ref object of Agent
  changingEvents: int
  changedEvents: int

type TableUpdateSignalSpy = ref object of Agent
  updateKinds: seq[TableRowUpdateKind]

type TableColumnUserInfo = ref object of Responder
  label: string

type TableStateProviderSpy = ref object of Responder
  identifier: string
  defaults: UserDefaults

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
  selectedRows: seq[int]
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
  dropValidationCalls: seq[string]
  dropAcceptCalls: seq[string]
  hasReorderPolicy: bool
  reorderAllowed: bool
  reorderAccepted: bool
  reorderValidationCalls: seq[string]
  reorderPerformCalls: seq[string]

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

proc dropTargetSummary(rows: openArray[int], target: DraggingDropTarget): string =
  for index, row in rows:
    if index > 0:
      result.add ","
    result.add $row
  result.add ":" & $target.kind & ":" & $target.position & ":" & $target.row

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

proc renderedRectangleCount(view: View): int =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return 0
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkRectangle:
      inc result

proc renderedRect(node: Fig): nimkitTypes.Rect =
  nimkitTypes.initRect(
    node.screenBox.x.float32, node.screenBox.y.float32, node.screenBox.w.float32,
    node.screenBox.h.float32,
  )

func rectsClose(left, right: nimkitTypes.Rect): bool =
  abs(left.origin.x - right.origin.x) <= 0.01'f32 and
    abs(left.origin.y - right.origin.y) <= 0.01'f32 and
    abs(left.size.width - right.size.width) <= 0.01'f32 and
    abs(left.size.height - right.size.height) <= 0.01'f32

proc renderedRectangleWithFill(
    view: View, rect: nimkitTypes.Rect, fillValue: Fill
): bool =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return false
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkRectangle and node.fill == fillValue and
        node.renderedRect().rectsClose(rect):
      return true

proc renderedVisibleSortIndicatorCount(view: View, minimumY = -1.0'f32): int =
  let
    renders = buildRenders(view)
    chrome = defaultTableHeaderChrome()
  if DefaultDrawLevel notin renders:
    return 0
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkRectangle and node.fill.kind == flColor and
        node.fill.color == chrome.sortIndicatorColor.rgba and
        node.screenBox.y >= minimumY and node.screenBox.w >= 6.0 and
        node.screenBox.h >= 1.5 and abs(node.rotation) >= 10.0:
      inc result

proc hostedTableCellCount(tableView: TableView): int =
  let content = tableView.contentView()
  if content.isNil:
    return 0
  for rowView in content.subviews():
    result += rowView.subviews().len

proc selectedTableRowIdentifiers(tableView: TableView): seq[string] =
  for index in tableView.selectedIndexes:
    let identifier = tableView.tableRowIdentifier(index)
    if identifier.len > 0:
      result.add identifier

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

proc clickTableCell(
    window: Window,
    tableView: TableView,
    row: int,
    column: TableColumn,
    modifiers: set[KeyModifier] = {},
): bool =
  let point = tableView.tableCellPoint(row, column)
  window.mouseDownAt(point, modifiers = modifiers) and
    window.mouseUpAt(point, modifiers = modifiers)

proc clickTableHeader(
    window: Window,
    tableView: TableView,
    column: TableColumn,
    modifiers: set[KeyModifier] = {},
): bool =
  let rect = tableView.tableHeaderColumnRect(column)
  if rect.isEmpty:
    return false
  let point = tableView.pointToWindow(
    initPoint(
      rect.origin.x + rect.size.width * 0.5, rect.origin.y + rect.size.height * 0.5
    )
  )
  window.mouseDownAt(point, modifiers = modifiers) and
    window.mouseUpAt(point, modifiers = modifiers)

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

func fieldText(row: SortableTableRow, identifier: string): string =
  case identifier
  of "project": row.project
  of "rank": row.rank
  else: row.id

proc tableModelRows(): seq[TableRowValue] =
  @[
    tableRow(
      "ada",
      objectValue = toObj("Ada"),
      cells = [
        tableCell("name", toObj("Ada")),
        tableCell("score", toObj(31)),
        tableCell("active", toObj(true)),
      ],
    ),
    tableRow(
      "grace",
      objectValue = toObj("Grace"),
      cells = [
        tableCell("name", toObj("Grace")),
        tableCell("score", toObj(45)),
        tableCell("active", toObj(true)),
      ],
    ),
    tableRow(
      "alan",
      objectValue = toObj("Alan"),
      cells = [
        tableCell("name", toObj("Alan")),
        tableCell("score", toObj(27)),
        tableCell("active", toObj(false)),
      ],
    ),
  ]

proc tableModelColumns(): seq[TableModelColumn] =
  @[
    initTableModelColumn("name", "Name", "name", 120.0),
    initTableModelColumn("score", "Score", "score", 64.0),
  ]

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

proc rememberTableRowsDidUpdate(
    spy: TableUpdateSignalSpy, sender: DynamicAgent, updates: seq[TableRowUpdate]
) {.slot.} =
  discard sender
  for update in updates:
    spy.updateKinds.add update.kind

proc newTableSelectionSignalSpy(): TableSelectionSignalSpy =
  TableSelectionSignalSpy()

proc newTableUpdateSignalSpy(): TableUpdateSignalSpy =
  TableUpdateSignalSpy()

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

  method didSelectTableRow(delegate: TableDelegateSpy, tableView: TableView, row: int) =
    delegate.selectedRows.add row

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

  method validateDropOperation(
      delegate: TableDelegateSpy,
      tableView: TableView,
      info: DraggingInfo,
      proposedOperation: DragOperations,
      target: DraggingDropTarget,
      position: DraggingDropPosition,
  ): DragOperations =
    delegate.dropValidationCalls.add(
      $target.kind & ":" & $position & ":" & target.column & ":" & $target.row
    )
    if delegate.dragOperation == NoDragOperations:
      proposedOperation
    else:
      delegate.dragOperation

  method acceptDropOperation(
      delegate: TableDelegateSpy,
      tableView: TableView,
      info: DraggingInfo,
      operation: DragOperations,
      target: DraggingDropTarget,
      position: DraggingDropPosition,
  ): bool =
    delegate.dropAcceptCalls.add(
      $operation & ":" & $target.kind & ":" & $position & ":" & target.column & ":" &
        $target.row
    )
    delegate.dragAccepted

  method shouldReorderRows(
      delegate: TableDelegateSpy,
      tableView: TableView,
      rows: seq[int],
      target: DraggingDropTarget,
  ): bool =
    delegate.reorderValidationCalls.add dropTargetSummary(rows, target)
    if delegate.hasReorderPolicy: delegate.reorderAllowed else: true

protocol TableDelegateReorderPerformSpyMethods of TableViewDelegate:
  method performRowReorder(
      delegate: TableDelegateSpy,
      tableView: TableView,
      rows: seq[int],
      target: DraggingDropTarget,
  ): bool =
    delegate.reorderPerformCalls.add dropTargetSummary(rows, target)
    delegate.reorderAccepted

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

protocol TableStateProviderSpyMethods of UserDefaultsProvider:
  method defaultsStore(provider: TableStateProviderSpy): DynamicAgent =
    DynamicAgent(provider.defaults)

  method defaultsScopeId(provider: TableStateProviderSpy): string =
    provider.identifier

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

protocol SortableTableSpyDataSource of TableViewDataSource:
  method numberOfRows(source: SortableTableSpy, tableView: TableView): int =
    source.rows.len

  method textForCell(
      source: SortableTableSpy, tableView: TableView, row: int, column: TableColumn
  ): string =
    if row in 0 ..< source.rows.len:
      source.rows[row].fieldText(column.identifier)
    else:
      ""

  method identifierForRow(
      source: SortableTableSpy, tableView: TableView, row: int
  ): string =
    if row in 0 ..< source.rows.len:
      source.rows[row].id
    else:
      ""

  method rowForIdentifier(
      source: SortableTableSpy, tableView: TableView, identifier: string
  ): int =
    for index, row in source.rows:
      if row.id == identifier:
        return index
    -1

protocol SortableTableSpyDelegate of TableViewDelegate:
  method sortDescriptorsDidChange(
      source: SortableTableSpy,
      tableView: TableView,
      column: TableColumn,
      direction: TableSortDirection,
  ) =
    source.sortChanges.add column.identifier & ":" & $direction
    source.rows.sort(
      proc(left, right: SortableTableRow): int =
        result =
          cmp(left.fieldText(column.identifier), right.fieldText(column.identifier))
        if direction == tsdDescending:
          result = -result
    )
    tableView.reloadData()

proc newEditableTableSpy(rows: openArray[EditableTableRow]): EditableTableSpy =
  result = EditableTableSpy(rows: @rows)
  initResponder(result)
  discard result.withProtocol(EditableTableSpyDataSource)
  discard result.withProtocol(EditableTableSpyDelegate)

proc newEditableTableSpy(row: EditableTableRow): EditableTableSpy =
  newEditableTableSpy([row])

proc newSortableTableSpy(rows: openArray[SortableTableRow]): SortableTableSpy =
  result = SortableTableSpy(rows: @rows)
  initResponder(result)
  discard result.withProtocol(SortableTableSpyDataSource)
  discard result.withProtocol(SortableTableSpyDelegate)

proc selectedRowIds(source: SortableTableSpy, tableView: TableView): seq[string] =
  for index in tableView.selectedIndexes:
    if index in 0 ..< source.rows.len:
      result.add source.rows[index].id

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

proc newTableStateProviderSpy(identifier: string): TableStateProviderSpy =
  result = TableStateProviderSpy(identifier: identifier, defaults: newUserDefaults())
  initResponder(result)
  discard result.withProtocol(TableStateProviderSpyMethods)

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
      tableView = newTableView(frame = initRect(12, 24, 300, 160))
      name = newTableColumn("name", "Name", width = 120.0)
      age = newTableColumn("age", "Age", width = 60.0)
      store = newTableViewStateStore()

    tableView.addColumn(name)
    tableView.addColumn(age)
    tableView.autosaveName = "people"

    check tableView.trackingAreas.len == 1
    check tableView.trackingAreas[0].rect == tableView.tableHeaderRect()
    check tableView.cursorRects.len == 2
    check tableView.cursorRects[0].cursor == "resizeLeftRight"

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
    texts = tableView.renderedTexts()
    check texts.contains("Name")
    check not texts.contains("Name ^")
    check not texts.contains("Name v")
    check tableView.renderedRectangleCount() >= 6
    check tableView.renderedVisibleSortIndicatorCount(tableView.frame.origin.y) >= 2

    check tableView.headerMouseDown(
      MouseEvent(location: initPoint(20.0, 10.0), button: mbPrimary)
    )
    check tableView.headerMouseUp(
      MouseEvent(location: initPoint(20.0, 10.0), button: mbPrimary)
    )
    check name.sortDirection == tsdDescending
    check tableView.renderedVisibleSortIndicatorCount(tableView.frame.origin.y) >= 2

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

  test "table state storage restores renamed columns and selected column aliases":
    let
      store = newTableViewStateStore()
      oldTable = newTableView()
      oldName = newTableColumn("fullName", "Name", width = 180.0)
      oldAge = newTableColumn("age", "Age", width = 64.0)

    oldTable.autosaveName = "people.alias"
    oldTable.allowsColumnSelection = true
    oldTable.addColumn(oldName)
    oldTable.addColumn(oldAge)
    oldTable.selectedColumns = [oldName]
    oldName.sortDirection = tsdDescending
    oldAge.hidden = true
    oldTable.saveState(store)

    let
      newTable = newTableView()
      newName = newTableColumn("name", "Name", width = 80.0)
      newAge = newTableColumn("age", "Age", width = 40.0)

    newTable.autosaveName = "people.alias"
    newTable.allowsColumnSelection = true
    newTable.addColumn(newAge)
    newTable.addColumn(newName)
    newTable.registerColumnAutosaveAlias("fullName", "name")
    newTable.restoreState(store)

    check newTable.columnAt(0) == newName
    check newTable.columnAt(1) == newAge
    check newName.width == oldName.width
    check newName.sortDirection == tsdDescending
    check newAge.hidden
    check newTable.selectedColumns == @[newName]

  test "table state saves on window close and restores from workspace scope":
    let
      workspaceId = "tnimkit.table.workspace.lifecycle"
      firstWindow = newWindow("Table lifecycle save", frame = initRect(0, 0, 320, 160))
      firstRoot = newView(frame = initRect(0, 0, 320, 160))
      firstTable = newTableView(frame = initRect(0, 0, 240, 80))
      firstName = newTableColumn("name", "Name", width = 90.0)
      store = workspaceTableViewStateStore(workspaceId)

    firstTable.autosaveName = "people.lifecycle"
    firstTable.workspaceIdentifier = workspaceId
    firstTable.addColumn(firstName)
    firstRoot.addSubview(firstTable)
    firstWindow.setContentView(firstRoot)
    firstName.width = 170.0
    firstWindow.close()

    check store.hasState("people.lifecycle")
    check store.state("people.lifecycle").columns[0].width == 170.0'f32

    let
      secondWindow =
        newWindow("Table lifecycle restore", frame = initRect(0, 0, 320, 160))
      secondRoot = newView(frame = initRect(0, 0, 320, 160))
      secondTable = newTableView(frame = initRect(0, 0, 240, 80))
      secondName = newTableColumn("name", "Name", width = 72.0)

    secondTable.autosaveName = "people.lifecycle"
    secondTable.workspaceIdentifier = workspaceId
    secondTable.addColumn(secondName)
    secondRoot.addSubview(secondTable)
    secondWindow.setContentView(secondRoot)

    check secondName.width == 170.0'f32

  test "table state can resolve document-scoped storage from responder chain":
    let
      documentId = "document:file:///tmp/table-state.nim"
      provider = newTableStateProviderSpy(documentId)
      window = newWindow("Table document state", frame = initRect(0, 0, 320, 160))
      root = newView(frame = initRect(0, 0, 320, 160))
      tableView = newTableView(frame = initRect(0, 0, 240, 80))
      column = newTableColumn("name", "Name", width = 96.0)

    window.setNextResponder(provider)
    tableView.autosaveName = "people.document"
    tableView.stateScope = tvssDocument
    tableView.addColumn(column)
    root.addSubview(tableView)
    window.setContentView(root)
    column.width = 144.0
    tableView.saveAutosavedState()

    let store = tableViewStateStoreForDefaults(provider.defaults, documentId)
    check store.hasState("people.document")
    check store.state("people.document").columns[0].width == 144.0'f32

  test "table header column dragging previews insertion and drops at edge":
    let
      tableView = newTableView(frame = initRect(0, 0, 230, 140))
      project = newTableColumn("project", "Project", width = 90.0)
      state = newTableColumn("state", "State", width = 70.0)
      owner = newTableColumn("owner", "Owner", width = 70.0)

    tableView.addColumn(project)
    tableView.addColumn(state)
    tableView.addColumn(owner)

    check tableView.headerMouseDown(
      MouseEvent(location: initPoint(20.0, 10.0), button: mbPrimary)
    )
    check tableView.headerMouseDragged(
      MouseEvent(location: initPoint(226.0, 10.0), button: mbPrimary)
    )
    let indicator = tableView.headerDragIndicator()
    check indicator.visible
    check indicator.index == 3
    check indicator.rect.origin.x >= tableView.tableHeaderRect().maxX - 2.0'f32

    check tableView.headerMouseUp(
      MouseEvent(location: initPoint(226.0, 10.0), button: mbPrimary)
    )
    check tableView.columnAt(0) == state
    check tableView.columnAt(1) == owner
    check tableView.columnAt(2) == project
    check not tableView.headerDragIndicator().visible

  test "table view keeps clicked selection on row identities after header sort":
    let
      window = newWindow("Table sort keeps selection", frame = initRect(0, 0, 420, 180))
      root = newView(frame = initRect(0, 0, 420, 180))
      tableView = newTableView(frame = initRect(10, 10, 300, 140))
      source = newSortableTableSpy(
        [
          SortableTableRow(id: "a", project: "Alpha", rank: "3"),
          SortableTableRow(id: "b", project: "Bravo", rank: "1"),
          SortableTableRow(id: "c", project: "Charlie", rank: "2"),
          SortableTableRow(id: "d", project: "Delta", rank: "4"),
        ]
      )
      project = newTableColumn("project", "Project", width = 160.0)
      rank = newTableColumn("rank", "Rank", width = 70.0)

    tableView.selectionMode = tsmExtended
    tableView.addColumn(project)
    tableView.addColumn(rank)
    tableView.dataSource = source
    tableView.delegate = source
    tableView.rowHeight = 24.0
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    check window.clickTableCell(tableView, 0, project)
    check window.clickTableCell(tableView, 2, project, {kmCommand})
    check tableView.selectedIndexes == @[0, 2]
    check source.selectedRowIds(tableView) == @["a", "c"]

    check window.clickTableHeader(tableView, rank)
    check source.sortChanges == @["rank:tsdAscending"]
    check source.rows.mapIt(it.id) == @["b", "c", "a", "d"]
    check tableView.selectedIndexes == @[1, 2]
    check source.selectedRowIds(tableView) == @["c", "a"]

  test "table model adapter backs typed object values and editing writeback":
    let
      model = newTableModel(tableModelRows(), tableModelColumns())
      tableView = newTableView()

    tableView.bindTableModel(model)
    let
      nameColumn = tableView.columnWithIdentifier("name")
      scoreColumn = tableView.columnWithIdentifier("score")

    check tableView.columnCount == 2
    check tableView.rowCount == 3
    check not nameColumn.isNil
    check not scoreColumn.isNil
    check tableView.requireTableRowIdentifier(0) == "ada"
    check tableView.requireTableRowIndexForIdentifier("alan") == 2
    check tableView.getTableRowIndexForIdentifier("missing").isNone
    expect TableModelError:
      discard tableView.requireTableRowIdentifier(99)

    check tableView.tableCellText(1, nameColumn) == "Grace"
    check tableView.tableCellObjectValue(0, scoreColumn).requireInt() == 31

    check tableView.beginEditingCell(0, scoreColumn)
    check tableView.commitEditingCell("32")
    check model.valueForRow("ada", "score").requireInt() == 32

    check tableView.beginEditingCell(0, scoreColumn)
    check not tableView.commitEditingCell("not an int")
    check tableView.editingState.active
    check tableView.editingValidation().kind == oveParseFailed
    check model.valueForRow("ada", "score").requireInt() == 32
    check tableView.cancelEditingCell()

    tableView.selectedIndexes = [0]
    tableView.requestSort(scoreColumn, tsdDescending)
    check model.sortDescriptors ==
      @[initTableModelSortDescriptor("score", tsdDescending)]
    check tableView.tableRowIdentifier(0) == "grace"
    check tableView.selectedIndexes == @[1]
    check tableView.selectedTableRowIdentifiers() == @["ada"]

  test "table view persists row identities drags identifiers and batches row updates":
    let
      model = newTableModel(tableModelRows(), tableModelColumns())
      tableView = newTableView()
      signals = newTableUpdateSignalSpy()

    tableView.bindTableModel(model)
    tableView.selectionMode = tsmExtended
    tableView.selectedIndexes = [0, 2]

    let selectionState = tableView.selectionPersistenceString()
    check selectionState == "ids:ada,alan"

    var rows = model.rows()
    rows[0].identifier = "ada-lovelace"
    model.rows = rows
    tableView.setRowIdentifierAlias("ada", "ada-lovelace")
    tableView.selectedIndexes = []
    tableView.restoreSelectionPersistenceString(selectionState)
    check tableView.selectedTableRowIdentifiers() == @["ada-lovelace", "alan"]

    let drag = tableView.beginDraggingRows(
      tableView.selectedIndexes(), {dgoCopy}, DragPasteboardName
    )
    check not drag.isNil
    let info = drag.draggingInfo()
    check info.tableDraggingRows() == @[0, 2]
    check info.tableDraggingRowIdentifiers() == @["ada-lovelace", "alan"]

    tableView.connect(tableRowsDidUpdate, signals, rememberTableRowsDidUpdate)
    model.addRow(
      tableRow(
        "edith",
        objectValue = toObj("Edith"),
        cells = [tableCell("name", toObj("Edith")), tableCell("score", toObj(38))],
      )
    )

    tableView.beginTableUpdates()
    tableView.insertRowsAtIndexes([3], ["edith"])
    tableView.reloadRowsAtIndexes([1], ["grace"])
    tableView.moveRow(3, 1)
    tableView.removeRowsAtIndexes([0], ["ada-lovelace"])
    check signals.updateKinds == newSeq[TableRowUpdateKind]()

    tableView.endTableUpdates()
    check signals.updateKinds == @[trukInsert, trukReload, trukMove, trukRemove]

  test "table view reorders table model rows when enabled":
    let
      model = newTableModel(tableModelRows(), tableModelColumns())
      tableView = newTableView()

    tableView.bindTableModel(model)
    tableView.selectionMode = tsmExtended
    tableView.selectedIndexes = [0, 2]

    check not tableView.reorderRows([0], initRowInsertionDropTarget(2, ddpBefore))
    check model.arrangedRows().mapIt(it.identifier) == @["ada", "grace", "alan"]

    tableView.allowsRowReordering = true
    check not tableView.reorderRows([0], initRowInsertionDropTarget(0, ddpBefore))
    check tableView.reorderRows([0], initRowInsertionDropTarget(2, ddpBefore))
    check model.arrangedRows().mapIt(it.identifier) == @["grace", "ada", "alan"]
    check tableView.selectedIndexes == @[1, 2]
    check tableView.selectedTableRowIdentifiers() == @["ada", "alan"]

  test "table row reordering uses delegate approval and override hooks":
    let
      model = newTableModel(tableModelRows(), tableModelColumns())
      tableView = newTableView()
      delegate = newTableDelegateSpy()
      target = initRowInsertionDropTarget(2, ddpBefore)

    tableView.bindTableModel(model)
    tableView.delegate = delegate
    tableView.allowsRowReordering = true
    delegate.hasReorderPolicy = true
    delegate.reorderAllowed = false

    check not tableView.reorderRows([0], target)
    check model.arrangedRows().mapIt(it.identifier) == @["ada", "grace", "alan"]
    check delegate.reorderValidationCalls == @["0:ddtRow:ddpBefore:2"]

    delegate.hasReorderPolicy = false
    delegate.reorderAccepted = true
    discard delegate.withProtocol(TableDelegateReorderPerformSpyMethods)

    check tableView.reorderRows([0], target)
    check model.arrangedRows().mapIt(it.identifier) == @["ada", "grace", "alan"]
    check delegate.reorderPerformCalls == @["0:ddtRow:ddpBefore:2"]

  test "table view starts and commits row reordering from mouse drag":
    let
      window = newWindow("Table row drag reorder", frame = initRect(0, 0, 360, 180))
      root = newView(frame = initRect(0, 0, 360, 180))
      tableView = newTableView(frame = initRect(10, 10, 260, 100))
      model = newTableModel(tableModelRows(), tableModelColumns())

    tableView.showsHeader = false
    tableView.bindTableModel(model)
    tableView.allowsRowReordering = true
    tableView.rowHeight = 24.0
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    let
      firstRow = tableView.rowItemRect(0)
      secondRow = tableView.rowItemRect(1)
      start = tableView.pointToWindow(
        initPoint(firstRow.origin.x + 8.0'f32, firstRow.origin.y + 12.0'f32)
      )
      drop = tableView.pointToWindow(
        initPoint(secondRow.origin.x + 8.0'f32, secondRow.maxY - 1.0'f32)
      )

    check window.mouseDownAt(start)
    check window.mouseDraggedAt(drop)
    check not tableView.draggingSession().isNil
    check tableView.currentDropTarget().kind == ddtRow
    check tableView.currentDropTarget().position == ddpAfter

    let
      chrome = defaultTableHeaderChrome()
      indicatorFill = fill(initColor(0.18, 0.42, 0.88, 0.95))
      targetRect = tableView.rectToWindow(tableView.rowItemRect(1))
      indicatorY = targetRect.maxY - chrome.insertionWidth
      capY = indicatorY + (chrome.insertionWidth - chrome.insertionCapWidth) * 0.5'f32
      indicatorRect = initRect(
        targetRect.origin.x, indicatorY, targetRect.size.width, chrome.insertionWidth
      )
      leftCapRect = initRect(
        targetRect.origin.x, capY, chrome.insertionCapHeight, chrome.insertionCapWidth
      )
      rightCapRect = initRect(
        targetRect.maxX - chrome.insertionCapHeight,
        capY,
        chrome.insertionCapHeight,
        chrome.insertionCapWidth,
      )

    check root.renderedRectangleWithFill(indicatorRect, indicatorFill)
    check root.renderedRectangleWithFill(leftCapRect, indicatorFill)
    check root.renderedRectangleWithFill(rightCapRect, indicatorFill)

    check window.mouseUpAt(drop)
    check tableView.draggingSession().isNil
    check model.arrangedRows().mapIt(it.identifier) == @["grace", "ada", "alan"]
    check tableView.selectedTableRowIdentifiers() == @["ada"]

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

  test "table view reloadData refreshes hosted cell views from updated data":
    let
      tableView = newTableView(frame = initRect(0, 0, 320, 46))
      source = newEditableTableSpy(
        EditableTableRow(
          project: "Alpha", state: "Queued", owner: "June", elapsed: "18m"
        )
      )
      project = newTableColumn("project", "Project", width = 160.0)
      state = newTableColumn("state", "State", width = 100.0, alignment = taCenter)

    tableView.showsHeader = false
    tableView.addColumn(project)
    tableView.addColumn(state)
    tableView.dataSource = source
    tableView.delegate = source

    let initialTexts = tableView.renderedTexts()
    check initialTexts.containsValue("Queued")

    source.rows[0].state = "Running"
    tableView.reloadData()

    let updatedTexts = tableView.renderedTexts()
    check updatedTexts.containsValue("Running")
    check not updatedTexts.containsValue("Queued")

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

  test "table view selection delegate is notified from public API":
    let
      tableView = newTableView()
      delegate = newTableDelegateSpy()

    tableView.selectionMode = tsmSingle
    tableView.rowCount = 3
    tableView.delegate = delegate

    tableView.selectedIndex = 1
    tableView.selectedIndex = 1
    tableView.selectedIndex = 2
    tableView.selectedIndex = -1

    check delegate.selectedRows == @[1, 2]

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
    check delegate.dropValidationCalls == @["ddtNone:ddpOn::-1", "ddtNone:ddpOn::-1"]
    check delegate.dropAcceptCalls == @["{dgoCopy}:ddtNone:ddpOn::-1"]

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
    let rowTargeted = columnInfo.withDropTarget(row = 1, position = ddpBefore)
    check rowTargeted.tableDropRow() == 1
    check rowTargeted.tableDropPosition() == ddpBefore
    let columnTargeted = columnInfo.withDropTarget(column = state, position = ddpAfter)
    check columnTargeted.tableDropColumn() == "state"
    check columnTargeted.tableDropPosition() == ddpAfter

  test "table view resolves row insertion and column drop targets":
    let
      tableView = newTableView(frame = initRect(0, 0, 220, 120))
      name = newTableColumn("name", "Name", width = 120.0)
      state = newTableColumn("state", "State", width = 80.0)

    tableView.rowCount = 3
    tableView.addColumn(name)
    tableView.addColumn(state)

    discard tableView.beginDraggingRows(@[0], {dgoMove}, DragPasteboardName)
    let rowRect = tableView.rowItemRect(1)
    let rowX = rowRect.origin.x + 8.0'f32
    let rowBefore = tableView.dropTargetForDraggingLocation(
      initPoint(rowX, rowRect.origin.y + 1.0'f32)
    )
    let rowMiddle = tableView.dropTargetForDraggingLocation(
      initPoint(rowX, rowRect.origin.y + rowRect.size.height * 0.5'f32)
    )
    let rowAfter =
      tableView.dropTargetForDraggingLocation(initPoint(rowX, rowRect.maxY - 1.0'f32))
    check rowBefore.kind == ddtRow
    check rowBefore.row == 1
    check rowBefore.position == ddpBefore
    check rowMiddle.kind == ddtRow
    check rowMiddle.position == ddpAfter
    check rowAfter.kind == ddtRow
    check rowAfter.position == ddpAfter

    discard tableView.beginDraggingColumns(@[name], {dgoMove}, DragPasteboardName)
    let columnRect = tableView.tableHeaderColumnRect(state)
    let columnY = columnRect.origin.y + columnRect.size.height * 0.5'f32
    let columnBefore = tableView.dropTargetForDraggingLocation(
      initPoint(columnRect.origin.x + 1.0'f32, columnY)
    )
    let columnOn = tableView.dropTargetForDraggingLocation(
      initPoint(columnRect.origin.x + columnRect.size.width * 0.5'f32, columnY)
    )
    let columnAfter = tableView.dropTargetForDraggingLocation(
      initPoint(columnRect.maxX - 1.0'f32, columnY)
    )
    check columnBefore.kind == ddtColumn
    check columnBefore.column == "name"
    check columnBefore.position == ddpAfter
    check columnOn.kind == ddtColumn
    check columnOn.position == ddpOn
    check columnAfter.kind == ddtColumn
    check columnAfter.position == ddpAfter

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

  test "table view row navigation preserves horizontal scroll offset":
    let
      window = newWindow("Table row scroll x offset", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      tableView = newTableView(frame = initRect(10, 10, 100, 72))
      scrollView = tableView.scrollView()

    tableView.showsHeader = false
    tableView.rowCount = 12
    tableView.rowHeight = 24.0
    tableView.addColumn(newTableColumn("project", "Project", width = 180.0))
    root.addSubview(tableView)
    window.setContentView(root)
    discard buildRenders(root)

    scrollView.contentOffset = initPoint(12.0, 0.0)
    check scrollView.contentOffset().x == 12.0'f32

    tableView.selectedIndex = 0
    check scrollView.contentOffset().x == 12.0'f32

    tableView.selectedIndex = 1
    check scrollView.contentOffset().x == 12.0'f32

    tableView.scrollRows(1)
    check scrollView.contentOffset().x == 12.0'f32

    check window.makeFirstResponder(tableView)
    check window.pressKey(keyPageDown)
    check scrollView.contentOffset().x == 12.0'f32

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
