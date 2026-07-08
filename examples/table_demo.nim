import std/[algorithm, strutils]

import merenda/nimkit

import sigils/core
import sigils/selectors as dynamicSelectors

type
  BuildRow = object
    id: string
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
    contextRows: seq[int]

const ValidBuildStates = ["Running", "Queued", "Blocked", "Done", "Paused"]

func fieldText(row: BuildRow, identifier: string): string =
  case identifier
  of "project": row.project
  of "state": row.state
  of "owner": row.owner
  of "elapsed": row.elapsed
  else: ""

func canonicalState(value: string): string =
  let text = value.strip()
  for state in ValidBuildStates:
    if cmpIgnoreCase(text, state) == 0:
      return state
  text

func validElapsedValue(value: string): bool =
  let text = value.strip()
  if text.len < 2 or text[^1] notin {'m', 'h', 'd'}:
    return false
  for index in 0 ..< text.high:
    if text[index] < '0' or text[index] > '9':
      return false
  true

func validationError(column: TableColumn, value: string): string =
  if column.isNil:
    return ""
  let text = value.strip()
  if text.len == 0:
    return column.title & " cannot be blank"
  case column.identifier
  of "state":
    if text.canonicalState() notin ValidBuildStates:
      result = "State must be Running, Queued, Blocked, Done, or Paused"
  of "elapsed":
    if not text.validElapsedValue():
      result = "Elapsed should look like 12m, 2h, or 1d"
  else:
    discard

func demoRows(): seq[BuildRow] =
  @[
    BuildRow(
      id: "renderer-pipeline",
      project: "Renderer Pipeline",
      state: "Running",
      owner: "Mara",
      elapsed: "12m",
    ),
    BuildRow(
      id: "auth-gateway",
      project: "Auth Gateway",
      state: "Queued",
      owner: "Iris",
      elapsed: "2h",
    ),
    BuildRow(
      id: "crash-reporter",
      project: "Crash Reporter",
      state: "Blocked",
      owner: "Noah",
      elapsed: "1d",
    ),
    BuildRow(
      id: "asset-importer",
      project: "Asset Importer",
      state: "Done",
      owner: "Ren",
      elapsed: "8m",
    ),
    BuildRow(
      id: "search-index",
      project: "Search Index",
      state: "Running",
      owner: "Leah",
      elapsed: "34m",
    ),
    BuildRow(
      id: "telemetry",
      project: "Telemetry",
      state: "Paused",
      owner: "Owen",
      elapsed: "5h",
    ),
    BuildRow(
      id: "installer",
      project: "Installer",
      state: "Queued",
      owner: "June",
      elapsed: "18m",
    ),
    BuildRow(
      id: "sync-engine",
      project: "Sync Engine",
      state: "Done",
      owner: "Vik",
      elapsed: "42m",
    ),
    BuildRow(
      id: "inspector",
      project: "Inspector",
      state: "Running",
      owner: "Nia",
      elapsed: "7m",
    ),
    BuildRow(
      id: "preview-cache",
      project: "Preview Cache",
      state: "Queued",
      owner: "Sol",
      elapsed: "1h",
    ),
    BuildRow(
      id: "layout-tests",
      project: "Layout Tests",
      state: "Done",
      owner: "Ari",
      elapsed: "24m",
    ),
    BuildRow(
      id: "release-notes",
      project: "Release Notes",
      state: "Done",
      owner: "Paz",
      elapsed: "3h",
    ),
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

func isUnavailable(row: BuildRow): bool =
  row.state in ["Blocked", "Paused"]

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

proc makeStateCell(state: string): TextField =
  result = newTextField(state)
  result.alignment = taCenter
  result.styleClasses = ["table-state-cell"]

proc onInspect(controller: TableDemoController, row: int) =
  let index = row
  if index in 0 ..< controller.rows.len:
    let build = controller.rows[index]
    controller.activity.text = "Inspecting: " & build.project & " (" & build.owner & ")"

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
  controller.table.reloadData()

proc updateCellValue(
    controller: TableDemoController, row: int, column: TableColumn, value: string
) =
  if row notin 0 ..< controller.rows.len or column.isNil:
    return
  let text = value.strip()
  case column.identifier
  of "project":
    controller.rows[row].project = text
  of "state":
    controller.rows[row].state = text.canonicalState()
  of "owner":
    controller.rows[row].owner = text
  of "elapsed":
    controller.rows[row].elapsed = text
  else:
    discard
  controller.table.reloadData()
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
  result.enabled = not controller.rowAt(row).isUnavailable()

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

  method identifierForRow(
      controller: TableDemoController, tableView: TableView, row: int
  ): string =
    controller.rowAt(row).id

  method rowForIdentifier(
      controller: TableDemoController, tableView: TableView, identifier: string
  ): int =
    for index, row in controller.rows:
      if row.id == identifier:
        return index
    -1

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
    not controller.rowAt(row).isUnavailable()

  method shouldSelectTableRow(
      controller: TableDemoController, tableView: TableView, row: int
  ): bool =
    not controller.rowAt(row).isUnavailable()

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
      not controller.rowAt(row).isUnavailable()

  method didBeginEditingCell(
      controller: TableDemoController,
      tableView: TableView,
      row: int,
      column: TableColumn,
  ) =
    controller.activity.text =
      "Editing " & column.title & " for " & controller.rowAt(row).project

  method validationErrorForCell(
      controller: TableDemoController,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ): string =
    result = validationError(column, value)
    if result.len > 0:
      controller.activity.text =
        "Edit rejected for " & controller.rowAt(row).project & "\n" & result

  method didCommitEditingCell(
      controller: TableDemoController,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ) =
    controller.updateCellValue(row, column, value)
    let text = controller.rowAt(row).cellText(column)
    controller.activity.text = "Committed " & column.title & ": " & text

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
    case column.identifier
    of "action": chpSelectAndTrack
    of "state": chpSelectRow
    else: chpDefault

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

proc tableCellEditDidCommit(
    controller: TableDemoController,
    sender: DynamicAgent,
    row: int,
    column: TableColumn,
    value: string,
) {.slot.} =
  if sender != DynamicAgent(controller.table) or column.isNil:
    return
  if column.sortDirection == tsdNone:
    return
  controller.sortRows(column, column.sortDirection)
  controller.activity.text =
    "Committed " & column.title & ": " & value & "\nResorted by " & column.title

proc actionRows(controller: TableDemoController): seq[int] =
  if controller.contextRows.len > 0:
    controller.contextRows
  else:
    controller.table.selectedIndexes

proc updateContextRows(controller: TableDemoController, event: MouseEvent) =
  controller.contextRows = @[]
  let row = controller.table.rowItemIndexAtPoint(event.location)
  if row notin 0 ..< controller.rows.len:
    return
  if row in controller.table.selectedIndexes:
    controller.contextRows = controller.table.selectedIndexes
  else:
    controller.contextRows = @[row]
    let column = controller.table.columnAtPoint(event.location)
    if not column.isNil and controller.table.rowSelectable(row):
      controller.table.selectCell(row, column)

proc installContextRowTracking(controller: TableDemoController) =
  let wrapper: dynamicSelectors.AroundMethod = proc(
      self: DynamicAgent,
      invocation: var dynamicSelectors.Invocation,
      next: dynamicSelectors.DynamicMethod,
  ) =
    let event = invocation.argsAs(MouseEvent)
    if event.button == mbSecondary:
      controller.updateContextRows(event)
    if not next.isNil:
      next(self, invocation)
    elif not invocation.handled:
      invocation.setResult(false)

  discard DynamicAgent(controller.table).pushMethod(rightMouseDown(), wrapper)

proc inspectSelected(controller: TableDemoController, sender: DynamicAgent) =
  discard sender
  let rows = controller.actionRows()
  let row =
    if rows.len > 0:
      rows[0]
    else:
      -1
  if row < 0:
    controller.activity.text = "No selected or clicked row to inspect"
    return
  controller.onInspect(row)
  controller.contextRows = @[]

proc markSelectedState(controller: TableDemoController, state: string) =
  let rows = controller.actionRows()
  if rows.len == 0:
    controller.activity.text = "No selected or clicked rows to update"
    return
  var changed = 0
  for row in rows:
    if row in 0 ..< controller.rows.len:
      controller.rows[row].state = state
      inc changed
  controller.table.reloadData()
  controller.table.selectedIndexes = rows
  controller.updateSelection()
  controller.activity.text = "Marked " & $changed & " row(s) " & state
  controller.contextRows = @[]

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
  window = newWindow("Nimkit Table Demo", frame = rect(140, 140, 860, 380))
  root = newView()
  title = newTitleLabel("Table View")
  table = newTableView()
  detailTitle = newHeadingLabel("Selection")
  detail = newStatusLabel("")
  activityTitle = newHeadingLabel("Activation")
  activity = newStatusLabel("No row activated")
  controller = newTableDemoController(table, detail, activity)
  inspectContextAction = actionSelector("tableContextInspect")
  markRunningContextAction = actionSelector("tableContextMarkRunning")
  markDoneContextAction = actionSelector("tableContextMarkDone")

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
table.selectionMode = tsmExtended
table.allowsColumnSelection = true
table.usesAlternatingRowBackgrounds = true
table.showsRowSeparators = true
table.selectCell(0, projectColumn)
table.requestSort(projectColumn, tsdAscending)
table.saveState(controller.stateStore)
stateColumn.hidden = true
table.moveColumn(table.columnIndex("owner"), table.columnIndex("project"))
table.restoreState(controller.stateStore)
table.connect(selectionDidChange, controller, tableSelectionDidChange)
table.connect(cellEditDidCommit, controller, tableCellEditDidCommit)
controller.installContextRowTracking()

let
  tableContextMenu = newMenu("Table Context")
  inspectContextItem = newMenuItem("Inspect Selection", inspectContextAction)
  runningContextItem = newMenuItem("Mark Running", markRunningContextAction)
  doneContextItem = newMenuItem("Mark Done", markDoneContextAction)

inspectContextItem.target = newActionTarget(
  inspectContextAction,
  proc(sender: DynamicAgent) =
    controller.inspectSelected(sender),
)
runningContextItem.target = newActionTarget(
  markRunningContextAction,
  proc(sender: DynamicAgent) =
    discard sender
    controller.markSelectedState("Running"),
)
doneContextItem.target = newActionTarget(
  markDoneContextAction,
  proc(sender: DynamicAgent) =
    discard sender
    controller.markSelectedState("Done"),
)
discard tableContextMenu.addItem(inspectContextItem)
discard tableContextMenu.addSeparator()
discard tableContextMenu.addItem(runningContextItem)
discard tableContextMenu.addItem(doneContextItem)
table.menu = tableContextMenu

var tableAppearance = initAppearance()
let
  stateCellStyle = initStyleSelector(srTextField, classes = @["table-state-cell"])
  disabledStateCellStyle =
    initStyleSelector(srTextField, {ssDisabled}, classes = @["table-state-cell"])
tableAppearance[stateCellStyle, StyleFill] = fill(color(0.94, 0.97, 1.0, 1.0))
tableAppearance[stateCellStyle, StyleBorderColor] = color(0.68, 0.76, 0.86, 1.0)
tableAppearance[stateCellStyle, StyleTextColor] = color(0.11, 0.23, 0.36, 1.0)
tableAppearance[disabledStateCellStyle, StyleFill] = fill(color(0.73, 0.75, 0.79, 1.0))
tableAppearance[disabledStateCellStyle, StyleBorderColor] = color(0.55, 0.58, 0.64, 1.0)
tableAppearance[disabledStateCellStyle, StyleTextColor] = color(0.28, 0.31, 0.37, 1.0)
tableAppearance[disabledStateCellStyle, StyleBoxShadows] = newSeq[BoxShadow]()
table.appearance = tableAppearance

root.addSubviews(autoNames(title, table, detailTitle, detail, activityTitle, activity))

title.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

activateConstraints:
  title[atHeight] == TitleHeight
  table[atTop] == title[atBottom] + 20.0
  table[atLeft] == title[atLeft]
  table[atRight] == detailTitle[atLeft] - 22.0
  table[atBottom] == root[atBottom] - 2'em
  detailTitle[atTop] == table[atTop] + 4.0
  detailTitle[atRight] == title[atRight]
  detailTitle[atWidth] == SidebarWidth
  detailTitle[atHeight] == 1.5'em
  detail[atTop] == detailTitle[atBottom] + 1'em
  detail[atLeft] == detailTitle[atLeft]
  detail[atRight] == detailTitle[atRight]
  activityTitle[atTop] == detail[atBottom] + 1'em
  activityTitle[atLeft] == detailTitle[atLeft]
  activityTitle[atRight] == detailTitle[atRight]
  activityTitle[atHeight] == 1.5'em
  activity[atTop] == activityTitle[atBottom] + 1'em
  activity[atLeft] == detailTitle[atLeft]
  activity[atRight] == detailTitle[atRight]
  detail[atHeight] == activity[atHeight]
  activity[atBottom] == root[atBottom] - 4'em

controller.updateSelection()
app.runWindow(window, root, table)
