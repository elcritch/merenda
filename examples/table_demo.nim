import std/strutils

import merenda/nimkit

import sigils/core

type
  BuildRow = object
    project: string
    state: string
    owner: string
    elapsed: string

  TableDemoController = ref object of Responder
    rows: seq[BuildRow]
    table: TableView
    detail: Label
    activity: Label

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
    BuildRow(project: "Release Notes", state: "Paused", owner: "Paz", elapsed: "3h"),
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
  else: ""

proc selectedProjectNames(controller: TableDemoController): seq[string] =
  for index in controller.table.selectedIndexes:
    if index in 0 ..< controller.rows.len:
      result.add controller.rows[index].project

proc updateSelection(controller: TableDemoController) =
  let names = controller.selectedProjectNames()
  if names.len == 0:
    controller.detail.text = "No rows selected"
  elif names.len == 1:
    controller.detail.text = "Selected: " & names[0]
  else:
    controller.detail.text = "Selected " & $names.len & ": " & names.join(", ")

proc makeStateCell(state: string): Label =
  result = newStatusLabel(state)
  result.alignment = taCenter

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
    nil

  method tableRowHeight(
      controller: TableDemoController, tableView: TableView, row: int
  ): float32 =
    28.0

  method isRowEnabled(
      controller: TableDemoController, tableView: TableView, row: int
  ): bool =
    controller.rowAt(row).state != "Paused"

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
    rows: demoRows(), table: table, detail: detail, activity: activity
  )
  initResponder(result)
  discard result.withProtocol(TableDemoDataSource)
  discard result.withProtocol(TableDemoDelegate)

const
  ProjectColumnWidth = 190.0
  StateColumnWidth = 100.0
  OwnerColumnWidth = 110.0
  ElapsedColumnWidth = 80.0
  TableWidth =
    ProjectColumnWidth + StateColumnWidth + OwnerColumnWidth + ElapsedColumnWidth + 20.0

let
  app = sharedApplication()
  window = newWindow("Nimkit Table Demo", frame = initRect(140, 140, 740, 380))
  root = newView()
  title = newTitleLabel("Table View")
  projectHeader = newStatusLabel("Project")
  stateHeader = newStatusLabel("State")
  ownerHeader = newStatusLabel("Owner")
  elapsedHeader = newStatusLabel("Elapsed")
  table = newTableView()
  detailTitle = newHeadingLabel("Selection")
  detail = newStatusLabel("")
  activityTitle = newHeadingLabel("Activation")
  activity = newStatusLabel("No row activated")
  controller = newTableDemoController(table, detail, activity)

root.background = initColor(0.95, 0.96, 0.98)

stateHeader.alignment = taCenter
elapsedHeader.alignment = taRight

table.addColumn(newTableColumn("project", "Project", width = ProjectColumnWidth))
table.addColumn(
  newTableColumn("state", "State", width = StateColumnWidth, alignment = taCenter)
)
table.addColumn(newTableColumn("owner", "Owner", width = OwnerColumnWidth))
table.addColumn(
  newTableColumn("elapsed", "Elapsed", width = ElapsedColumnWidth, alignment = taRight)
)
table.dataSource = controller
table.delegate = controller
table.visibleRows = 8
table.rowHeight = 28.0
table.selectionMode = lsmExtended
table.usesAlternatingRowBackgrounds = true
table.showsRowSeparators = true
table.selectedIndex = 0
table.connect(selectionDidChange, controller, tableSelectionDidChange)

root.addSubview(
  title, projectHeader, stateHeader, ownerHeader, elapsedHeader, table, detailTitle,
  detail, activityTitle, activity,
)

title.pinEdges(
  toGuide = root.contentLayoutGuide(initEdgeInsets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

activate(
  cx(projectHeader.topAnchor == title.bottomAnchor + 18.0),
  cx(projectHeader.leftAnchor == table.leftAnchor),
  cx(projectHeader.widthAnchor == ProjectColumnWidth),
  cx(stateHeader.topAnchor == projectHeader.topAnchor),
  cx(stateHeader.leftAnchor == projectHeader.rightAnchor),
  cx(stateHeader.widthAnchor == StateColumnWidth),
  cx(ownerHeader.topAnchor == projectHeader.topAnchor),
  cx(ownerHeader.leftAnchor == stateHeader.rightAnchor),
  cx(ownerHeader.widthAnchor == OwnerColumnWidth),
  cx(elapsedHeader.topAnchor == projectHeader.topAnchor),
  cx(elapsedHeader.leftAnchor == ownerHeader.rightAnchor),
  cx(elapsedHeader.widthAnchor == ElapsedColumnWidth),
  cx(table.topAnchor == projectHeader.bottomAnchor + 6.0),
  cx(table.leftAnchor == title.leftAnchor),
  cx(table.widthAnchor == TableWidth),
  cx(table.heightAnchor == 224.0),
  cx(detailTitle.topAnchor == table.topAnchor + 4.0),
  cx(detailTitle.leftAnchor == table.rightAnchor + 22.0),
  cx(detailTitle.rightAnchor == title.rightAnchor),
  cx(detail.topAnchor == detailTitle.bottomAnchor + 10.0),
  cx(detail.leftAnchor == detailTitle.leftAnchor),
  cx(detail.rightAnchor == detailTitle.rightAnchor),
  cx(activityTitle.topAnchor == detail.bottomAnchor + 28.0),
  cx(activityTitle.leftAnchor == detailTitle.leftAnchor),
  cx(activityTitle.rightAnchor == detailTitle.rightAnchor),
  cx(activity.topAnchor == activityTitle.bottomAnchor + 10.0),
  cx(activity.leftAnchor == detailTitle.leftAnchor),
  cx(activity.rightAnchor == detailTitle.rightAnchor),
)

controller.updateSelection()
window.setContentView(root)
discard window.makeFirstResponder(table)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
