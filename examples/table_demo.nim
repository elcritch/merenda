import std/[algorithm, strutils]

import merenda/nimkit

import sigils/core

type
  BuildRow = object
    project: string
    state: string
    owner: string
    elapsed: string

  ColumnInfo = ref object of Responder
    note: string

  TableDemoController = ref object of Responder
    rows: seq[BuildRow]
    table: TableView
    detail: Label
    activity: Label
    stateStore: TableViewStateStore

func fieldText(row: BuildRow, identifier: string): string =
  case identifier
  of "project": row.project
  of "state": row.state
  of "owner": row.owner
  of "elapsed": row.elapsed
  else: ""

func demoRows(): seq[BuildRow] =
  @[
    BuildRow(
      project: "Renderer Pipeline", state: "Running", owner: "Mara", elapsed: "12m"
    ),
    BuildRow(project: "Auth Gateway", state: "Queued", owner: "Iris", elapsed: "2h"),
    BuildRow(project: "Crash Reporter", state: "Blocked", owner: "Noah", elapsed: "1d"),
    BuildRow(project: "Asset Importer", state: "Done", owner: "Ren", elapsed: "8m"),
    BuildRow(project: "Search Index", state: "Running", owner: "Leah", elapsed: "34m"),
    BuildRow(project: "Telemetry", state: "Paused", owner: "Owen", elapsed: "5h"),
    BuildRow(project: "Installer", state: "Queued", owner: "June", elapsed: "18m"),
    BuildRow(project: "Sync Engine", state: "Done", owner: "Vik", elapsed: "42m"),
    BuildRow(project: "Inspector", state: "Running", owner: "Nia", elapsed: "7m"),
    BuildRow(project: "Preview Cache", state: "Queued", owner: "Sol", elapsed: "1h"),
    BuildRow(project: "Layout Tests", state: "Done", owner: "Ari", elapsed: "24m"),
    BuildRow(project: "Release Notes", state: "Done", owner: "Paz", elapsed: "3h"),
  ]

func rowAt(controller: TableDemoController, row: int): BuildRow =
  if row in 0 ..< controller.rows.len:
    controller.rows[row]
  else:
    BuildRow()

func cellText(row: BuildRow, column: TableColumn): string =
  case column.identifier
  of "project": row.project
  of "state": row.state
  of "owner": row.owner
  of "elapsed": row.elapsed
  of "action": "Inspect"
  else: ""

proc newColumnInfo(note: string): ColumnInfo =
  result = ColumnInfo(note: note)
  initResponder(result)

proc selectedProjectNames(controller: TableDemoController): seq[string] =
  for index in controller.table.selectedIndexes:
    if index in 0 ..< controller.rows.len:
      result.add controller.rows[index].project

proc selectedColumnNames(controller: TableDemoController): seq[string] =
  for column in controller.table.selectedColumns:
    if not column.isNil:
      result.add column.title

proc updateSelection(controller: TableDemoController) =
  let names = controller.selectedProjectNames()
  var text: string
  if names.len == 0:
    text = "No rows selected"
  elif names.len == 1:
    text = "Selected: " & names[0]
  else:
    text = "Selected " & $names.len & ": " & names.join(", ")
  let columns = controller.selectedColumnNames()
  if columns.len > 0:
    text.add "\nColumn: " & columns.join(", ")
  if not controller.table.clickedColumn.isNil:
    text.add "\nClicked: row " & $controller.table.clickedRow & ", " &
      controller.table.clickedColumn.title
  controller.detail.text = text

proc makeStateCell(state: string): Label =
  result = newStatusLabel(state)
  result.alignment = taCenter

proc onInspect(controller: TableDemoController, row: int) =
  let index = row
  if index in 0 ..< controller.rows.len:
    let build = controller.rows[index]
    let ownerColumn = controller.table.columnWithIdentifier("owner")
    controller.activity.text = "Inspecting: " & build.project & " (" & build.owner & ")"
    if not ownerColumn.isNil and controller.table.beginEditingCell(row, ownerColumn):
      controller.activity.text = controller.activity.text & "\nEditing owner cell"

proc sortRows(
    controller: TableDemoController, column: TableColumn, direction: TableSortDirection
) =
  if column.isNil or direction == tsdNone:
    return
  let identifier = column.identifier
  controller.rows.sort(
    proc(left, right: BuildRow): int =
      result = cmp(left.fieldText(identifier), right.fieldText(identifier))
      if direction == tsdDescending:
        result = -result
  )
  ListView(controller.table).reloadData()

proc updateCellValue(
    controller: TableDemoController, row: int, column: TableColumn, value: string
) =
  if row notin 0 ..< controller.rows.len or column.isNil:
    return
  case column.identifier
  of "project":
    controller.rows[row].project = value
  of "state":
    controller.rows[row].state = value
  of "owner":
    controller.rows[row].owner = value
  of "elapsed":
    controller.rows[row].elapsed = value
  else:
    discard
  ListView(controller.table).reloadData()
  controller.updateSelection()

proc makeActionButton(controller: TableDemoController, row: int): Button =
  result = newButton("Inspect")
  let action = actionSelector("tableInspect")
  result.target = newActionTarget(
    action,
    proc(sender: DynamicAgent) =
      controller.onInspect(row),
  )
  result.action = action
  result.enabled = controller.rowAt(row).state != "Paused"

protocol TableDemoDataSource of TableViewDataSource:
  method numberOfRows(controller: TableDemoController, tableView: TableView): int =
    controller.rows.len

  method textForCell(
      controller: TableDemoController,
      tableView: TableView,
      row: int,
      column: TableColumn,
  ): string =
    controller.rowAt(row).cellText(column)

protocol TableDemoDelegate of TableViewDelegate:
  method viewForCell(
      controller: TableDemoController,
      tableView: TableView,
      row: int,
      column: TableColumn,
  ): View =
    if column.identifier == "state":
      return controller.rowAt(row).state.makeStateCell()
    if column.identifier == "action":
      return controller.makeActionButton(row)
    nil

  method tableRowHeight(
      controller: TableDemoController, tableView: TableView, row: int
  ): float32 =
    28.0

  method isRowEnabled(
      controller: TableDemoController, tableView: TableView, row: int
  ): bool =
    controller.rowAt(row).state != "Paused"

  method shouldSelectTableRow(
      controller: TableDemoController, tableView: TableView, row: int
  ): bool =
    controller.rowAt(row).state != "Blocked"

  method sortDescriptorsDidChange(
      controller: TableDemoController,
      tableView: TableView,
      column: TableColumn,
      direction: TableSortDirection,
  ) =
    controller.sortRows(column, direction)
    controller.activity.text = "Sorted by " & column.title & " (" & $direction & ")"

  method shouldEditCell(
      controller: TableDemoController,
      tableView: TableView,
      row: int,
      column: TableColumn,
  ): bool =
    column.identifier in ["project", "state", "owner", "elapsed"] and
      controller.rowAt(row).state != "Blocked"

  method didBeginEditingCell(
      controller: TableDemoController,
      tableView: TableView,
      row: int,
      column: TableColumn,
  ) =
    controller.activity.text = "Editing " & column.title & " for row " & $row

  method didCommitEditingCell(
      controller: TableDemoController,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ) =
    controller.updateCellValue(row, column, value)
    controller.activity.text = "Committed " & column.title & ": " & value

  method didCancelEditingCell(
      controller: TableDemoController,
      tableView: TableView,
      row: int,
      column: TableColumn,
  ) =
    controller.activity.text = "Cancelled edit for " & column.title & " row " & $row

  method hitPolicyForCell(
      controller: TableDemoController,
      tableView: TableView,
      row: int,
      column: TableColumn,
      target: View,
      event: MouseEvent,
  ): CellHitPolicy =
    if column.identifier == "action": chpSelectAndTrack else: chpDefault

  method didActivateRow(
      controller: TableDemoController, tableView: TableView, row: int
  ) =
    let build = controller.rowAt(row)
    if build.project.len > 0:
      controller.activity.text =
        "Activated: " & build.project & " (" & build.state & ")"

proc tableSelectionDidChange(
    controller: TableDemoController, sender: DynamicAgent
) {.slot.} =
  if sender == DynamicAgent(controller.table):
    controller.updateSelection()

proc newTableDemoController(
    table: TableView, detail, activity: Label
): TableDemoController =
  result = TableDemoController(
    rows: demoRows(),
    table: table,
    detail: detail,
    activity: activity,
    stateStore: newTableViewStateStore(),
  )
  initResponder(result)
  discard result.withProtocol(TableDemoDataSource)
  discard result.withProtocol(TableDemoDelegate)

const
  ProjectColumnWidth = 190.0
  StateColumnWidth = 100.0
  OwnerColumnWidth = 110.0
  ElapsedColumnWidth = 80.0
  ActionColumnWidth = 90.0
  TitleHeight = 32.0
  SidebarWidth = 220.0

let
  app = sharedApplication()
  window = newWindow("Nimkit Table Demo", frame = initRect(140, 140, 860, 380))
  root = newView()
  title = newTitleLabel("Table View")
  table = newTableView()
  detailTitle = newHeadingLabel("Selection")
  detail = newStatusLabel("")
  activityTitle = newHeadingLabel("Activation")
  activity = newStatusLabel("No row activated")
  controller = newTableDemoController(table, detail, activity)

root.background = initColor(0.95, 0.96, 0.98)

let
  projectColumn =
    newTableColumn("project", "Project", width = ProjectColumnWidth, minWidth = 150.0)
  stateColumn =
    newTableColumn("state", "State", width = StateColumnWidth, alignment = taCenter)
  ownerColumn = newTableColumn("owner", "Owner", width = OwnerColumnWidth)
  elapsedColumn = newTableColumn(
    "elapsed",
    "Elapsed",
    width = ElapsedColumnWidth,
    alignment = taRight,
    resizePolicy = tcrFixed,
  )
  actionColumn = newTableColumn(
    "action",
    "Action",
    width = ActionColumnWidth,
    minWidth = 72.0,
    maxWidth = 120.0,
    alignment = taCenter,
  )
  scratchColumn = newTableColumn("scratch", "Scratch")

projectColumn.styleClasses = ["primary"]
projectColumn.userInfo = newColumnInfo("Primary project identity")
stateColumn.reuseIdentifier = "status-cell"
actionColumn.resizePolicy = tcrFixed
scratchColumn.hidden = true
discard projectColumn.userInfo of ColumnInfo
table.addColumn(projectColumn)
table.addColumn(stateColumn)
table.addColumn(elapsedColumn)
table.insertColumn(ownerColumn, table.columnIndex("elapsed"))
table.addColumn(scratchColumn)
table.removeColumn("scratch")
if table.containsColumn("action") == false:
  table.addColumn(actionColumn)
if not table.columnWithIdentifier("elapsed").isNil:
  table.columnWithIdentifier("elapsed").title = "Elapsed"

for column in table.columns:
  column.styleId = "table-column-" & column.identifier

table.dataSource = controller
table.delegate = controller
table.autosaveName = "table-demo"
table.visibleRows = 8
table.showsHeader = true
table.tableHeaderHeight = 26.0
table.rowHeight = 28.0
table.selectionMode = lsmExtended
table.allowsColumnSelection = true
table.usesAlternatingRowBackgrounds = true
table.showsRowSeparators = true
table.selectedIndex = 0
table.selectedColumns = [projectColumn]
table.requestSort(projectColumn, tsdAscending)
table.saveState(controller.stateStore)
stateColumn.hidden = true
table.moveColumn(table.columnIndex("owner"), table.columnIndex("project"))
table.restoreState(controller.stateStore)
table.connect(selectionDidChange, controller, tableSelectionDidChange)

root.addSubview(title, table, detailTitle, detail, activityTitle, activity)

title.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

activate(
  cx(title[anHeight] == TitleHeight),
  cx(table[anTop] == title[anBottom] + 20.0),
  cx(table[anLeft] == title[anLeft]),
  cx(table[anRight] == detailTitle[anLeft] - 22.0),
  cx(table[anBottom] == root[anBottom] - 28.0),
  cx(detailTitle[anTop] == table[anTop] + 4.0),
  cx(detailTitle[anRight] == title[anRight]),
  cx(detailTitle[anWidth] == SidebarWidth),
  cx(detail[anTop] == detailTitle[anBottom] + 10.0),
  cx(detail[anLeft] == detailTitle[anLeft]),
  cx(detail[anRight] == detailTitle[anRight]),
  cx(activityTitle[anTop] == detail[anBottom] + 28.0),
  cx(activityTitle[anLeft] == detailTitle[anLeft]),
  cx(activityTitle[anRight] == detailTitle[anRight]),
  cx(activity[anTop] == activityTitle[anBottom] + 10.0),
  cx(activity[anLeft] == detailTitle[anLeft]),
  cx(activity[anRight] == detailTitle[anRight]),
)

controller.updateSelection()
window.setContentView(root)
discard window.makeFirstResponder(table)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
