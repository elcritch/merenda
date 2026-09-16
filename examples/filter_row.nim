import std/strutils

import merenda/nimkit

import sigils/core

type
  EntryKind = enum
    ekNormal
    ekIgnored

  FilterMode = enum
    fmAll
    fmNormal
    fmIgnored

  FilterEntry = object
    identifier: string
    title: string
    kind: EntryKind
    status: string
    owner: string
    date: CalendarDate
    tags: seq[string]

  FilterDemoController = ref object of Responder
    entries: seq[FilterEntry]
    visibleIndexes: seq[int]
    table: TableView
    resultLabel: Label
    mode: FilterMode
    modeControl: SegmentedControl
    statusChoice: ComboBox
    ownerChoice: ComboBox
    statusFilter: string
    ownerFilter: string
    startButton: DatePickerButton
    endButton: DatePickerButton
    hasStartDate: bool
    hasEndDate: bool
    startDate: CalendarDate
    endDate: CalendarDate
    selectedTags: seq[string]
    tagField: TokenField

func entryCellText(entry: FilterEntry, column: TableColumn): string =
  case column.identifier
  of "entry":
    entry.title
  of "kind":
    case entry.kind
    of ekNormal: "Normal"
    of ekIgnored: "Ignored"
  of "status":
    entry.status
  of "owner":
    entry.owner
  of "date":
    entry.date.formatCalendarDate()
  of "labels":
    entry.tags.join(" · ")
  else:
    ""

const
  DemoStatuses = ["Open", "Review", "Blocked", "Done"]
  DemoOwners = ["Mara", "Iris", "Noah", "Ren", "Leah", "Owen"]
  DemoTags = [
    "Backend", "Frontend", "Billing", "Security", "Performance", "Docs", "Urgent",
    "Release", "Design", "Data", "Mobile", "Accessibility", "Migration", "Review",
    "API", "Testing", "Support", "Infra",
  ]
  DemoAreas = [
    "Account gateway", "Search index", "Invoice export", "Preview cache", "Sync engine",
    "Notification worker", "Import pipeline", "Access review", "Report builder",
    "Command palette", "Asset catalog", "Audit trail",
  ]

func demoEntries(): seq[FilterEntry] =
  for index in 0 ..< 48:
    var tags = @[DemoTags[index mod DemoTags.len]]
    if index mod 3 == 0:
      tags.add DemoTags[(index + 5) mod DemoTags.len]
    if index mod 8 == 0:
      tags.add "Urgent"
    let
      month = if index mod 2 == 0: 6 else: 7
      day = (index * 3) mod 28 + 1
      kind = if index mod 7 == 0 or index mod 11 == 0: ekIgnored else: ekNormal
    result.add FilterEntry(
      identifier: "entry-" & $index,
      title: DemoAreas[index mod DemoAreas.len] & " / " & $(index div DemoAreas.len + 1),
      kind: kind,
      status: DemoStatuses[index mod DemoStatuses.len],
      owner: DemoOwners[(index * 2) mod DemoOwners.len],
      date: initCalendarDate(2025, month, day),
      tags: tags,
    )

func tagMatches(entry: FilterEntry, selectedTags: openArray[string]): bool =
  if selectedTags.len == 0:
    return true
  for tag in selectedTags:
    if tag in entry.tags:
      return true
  false

func matchesFilters(controller: FilterDemoController, entry: FilterEntry): bool =
  case controller.mode
  of fmAll:
    discard
  of fmNormal:
    if entry.kind != ekNormal:
      return false
  of fmIgnored:
    if entry.kind != ekIgnored:
      return false
  if controller.statusFilter.len > 0 and entry.status != controller.statusFilter:
    return false
  if controller.ownerFilter.len > 0 and entry.owner != controller.ownerFilter:
    return false
  if controller.hasStartDate and entry.date < controller.startDate:
    return false
  if controller.hasEndDate and entry.date > controller.endDate:
    return false
  entry.tagMatches(controller.selectedTags)

proc entryAt(controller: FilterDemoController, row: int): FilterEntry =
  if row in 0 ..< controller.visibleIndexes.len:
    result = controller.entries[controller.visibleIndexes[row]]

proc applyFilters(controller: FilterDemoController) =
  controller.visibleIndexes.setLen(0)
  for index, entry in controller.entries:
    if controller.matchesFilters(entry):
      controller.visibleIndexes.add index
  controller.table.reloadData()
  controller.resultLabel.text =
    "Showing " & $controller.visibleIndexes.len & " of " & $controller.entries.len &
    " entries  ·  label filters match any selected label"

protocol FilterTableDataSource of TableViewDataSource:
  method numberOfRows(controller: FilterDemoController, tableView: TableView): int =
    controller.visibleIndexes.len

  method textForCell(
      controller: FilterDemoController,
      tableView: TableView,
      row: int,
      column: TableColumn,
  ): string =
    controller.entryAt(row).entryCellText(column)

  method identifierForRow(
      controller: FilterDemoController, tableView: TableView, row: int
  ): string =
    controller.entryAt(row).identifier

  method rowForIdentifier(
      controller: FilterDemoController, tableView: TableView, identifier: string
  ): int =
    for visibleRow, index in controller.visibleIndexes:
      if controller.entries[index].identifier == identifier:
        return visibleRow
    -1

protocol FilterTableDelegate of TableViewDelegate:
  method tableRowHeight(
      controller: FilterDemoController, tableView: TableView, row: int
  ): float32 =
    28.0

  method shouldSelectTableRow(
      controller: FilterDemoController, tableView: TableView, row: int
  ): bool =
    true

proc newFilterDemoController(
    table: TableView, resultLabel: Label
): FilterDemoController =
  result = FilterDemoController(
    entries: demoEntries(),
    table: table,
    resultLabel: resultLabel,
    mode: fmAll,
    startDate: initCalendarDate(2025, 6, 10),
    endDate: initCalendarDate(2025, 7, 24),
    selectedTags: @["Backend", "Urgent", "Review"],
  )
  initResponder(result)
  discard result.withProtocol(FilterTableDataSource)
  discard result.withProtocol(FilterTableDelegate)

proc selectedChoice(comboBox: ComboBox): string =
  let index = comboBox.indexOfSelectedItem()
  if index > 0:
    comboBox.optionIdentifierAtIndex(index)
  else:
    ""

proc onModeChanged(controller: FilterDemoController, sender: DynamicAgent) =
  if sender == DynamicAgent(controller.modeControl):
    let index = controller.modeControl.selectedSegmentIndex()
    if index in 0 .. ord(high(FilterMode)):
      controller.mode = FilterMode(index)
  controller.applyFilters()

proc onChoiceChanged(controller: FilterDemoController, sender: DynamicAgent) =
  if sender == DynamicAgent(controller.statusChoice):
    controller.statusFilter = controller.statusChoice.selectedChoice()
  elif sender == DynamicAgent(controller.ownerChoice):
    controller.ownerFilter = controller.ownerChoice.selectedChoice()
  controller.applyFilters()

proc setStartDate(controller: FilterDemoController, date: CalendarDate) =
  controller.startDate = date
  controller.hasStartDate = true
  controller.applyFilters()

proc setEndDate(controller: FilterDemoController, date: CalendarDate) =
  controller.endDate = date
  controller.hasEndDate = true
  controller.applyFilters()

proc onTagFieldChanged(controller: FilterDemoController, field: TokenField) =
  controller.selectedTags.setLen(0)
  for option in field.selectedOptions:
    controller.selectedTags.add option.identifier
  controller.applyFilters()

proc makeChoiceOptions(
    anyIdentifier, anyTitle: string, values: openArray[string]
): ComboBoxOptionList =
  result = newComboBoxOptionList()
  result.add(
    initComboBoxOption(
      identifier = anyIdentifier,
      displayText = anyTitle,
      objectValue = emptyObjectValue(),
    )
  )
  for value in values:
    result.add(
      initComboBoxOption(
        identifier = value, displayText = value, objectValue = toObj(value)
      )
    )

proc makeFilterAppearance(): Appearance =
  var appearance = initAppearance()
  let
    segment = initStyleSelector(srButton, classes = @["filter-segment"])
    selectedSegment =
      initStyleSelector(srButton, {ssSelected}, classes = @["filter-segment"])
    chip = initStyleSelector(srButton, classes = @["filter-chip"])
    autocomplete = initStyleSelector(srComboBox, classes = @["filter-autocomplete"])
  appearance[segment, StyleFill] = fill(color(0.93, 0.95, 0.98, 1.0))
  appearance[segment, StyleBorderColor] = color(0.64, 0.70, 0.80, 1.0)
  appearance[segment, StyleBorderWidth] = 1.0
  appearance[segment, StyleCornerRadius] = 8.0
  appearance[segment, StyleTextColor] = color(0.18, 0.24, 0.33, 1.0)
  appearance[segment, StyleTextInsets] = insets(0.0, 10.0)
  appearance[segment, StyleMinimumSize] = initSize(0.0, 30.0)
  appearance[selectedSegment, StyleFill] = fill(color(0.16, 0.43, 0.82, 1.0))
  appearance[selectedSegment, StyleBorderColor] = color(0.10, 0.32, 0.68, 1.0)
  appearance[selectedSegment, StyleTextColor] = color(1.0, 1.0, 1.0, 1.0)
  appearance[chip, StyleFill] = fill(color(0.88, 0.94, 1.0, 1.0))
  appearance[chip, StyleBorderColor] = color(0.47, 0.64, 0.88, 1.0)
  appearance[chip, StyleBorderWidth] = 1.0
  appearance[chip, StyleCornerRadius] = 13.0
  appearance[chip, StyleTextColor] = color(0.12, 0.28, 0.56, 1.0)
  appearance[chip, StyleTextInsets] = insets(0.0, 10.0)
  appearance[chip, StyleMinimumSize] = initSize(0.0, 28.0)
  appearance[autocomplete, StyleMinimumSize] = initSize(180.0, 30.0)
  result = appearance

let
  app = sharedApplication()
  window = newWindow("NimKit Filter Row Demo", frame = rect(120, 80, 1240, 760))
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel("Long table, one filter row")
  subtitle = newStatusLabel(
    "Every control below changes the table immediately. Type in Add labels... to search."
  )
  filterRow = newStackView(laHorizontal)
  modeControl = newSegmentedControl(["All entries", "Normal only", "Ignored only"])
  statusChoice = newComboBox()
  ownerChoice = newComboBox()
  startButton = newDatePickerButton("From")
  endButton = newDatePickerButton("Until")
  tagField = newTokenField(placeholder = "Add labels...")
  resultLabel = newStatusLabel("")
  table = newTableView()
  controller = newFilterDemoController(table, resultLabel)

root.appearance = makeFilterAppearance()
filterRow.spacing = 8.0
filterRow.alignment = svaCenter
filterRow.distribution = svdNatural

controller.statusChoice = statusChoice
controller.ownerChoice = ownerChoice
controller.startButton = startButton
controller.endButton = endButton
startButton.selectedDate = controller.startDate
endButton.selectedDate = controller.endDate
controller.tagField = tagField

statusChoice.dataSource = makeChoiceOptions("any-status", "Any status", DemoStatuses)
ownerChoice.dataSource = makeChoiceOptions("any-owner", "Any owner", DemoOwners)
statusChoice.selectedIndex = 0
ownerChoice.selectedIndex = 0
statusChoice.styleClasses = @["filter-choice"]
ownerChoice.styleClasses = @["filter-choice"]

tagField.inputStyleClasses = @["filter-autocomplete"]
tagField.chipStyleClasses = @["filter-chip"]
tagField.maxVisibleItems = 6
tagField.popupPresentation = ppInline
var tagOptions: seq[ComboBoxOption]
for tag in DemoTags:
  tagOptions.add(
    initComboBoxOption(identifier = tag, displayText = tag, objectValue = toObj(tag))
  )
tagField.options = tagOptions
for tag in controller.selectedTags:
  discard tagField.selectOptionWithIdentifier(tag, notify = false)
tagField.onChange = proc(field: TokenField) =
  controller.onTagFieldChanged(field)

let
  modeAction = actionSelector("filterModeChanged")
  choiceAction = actionSelector("filterChoiceChanged")
  modeTarget = newActionTarget(
    modeAction,
    proc(sender: DynamicAgent) =
      controller.onModeChanged(sender),
  )
  choiceTarget = newActionTarget(
    choiceAction,
    proc(sender: DynamicAgent) =
      controller.onChoiceChanged(sender),
  )

controller.modeControl.styleClasses = @["filter-segment"]
controller.modeControl.target = modeTarget
controller.modeControl.action = modeAction
controller.modeControl.selectedSegmentIndex = ord(controller.mode)

for combo in [statusChoice, ownerChoice]:
  combo.target = choiceTarget
  combo.action = choiceAction

startButton.onSelect = proc(date: CalendarDate) =
  controller.setStartDate(date)
endButton.onSelect = proc(date: CalendarDate) =
  controller.setEndDate(date)

filterRow.addArrangedSubview(
  modeControl, statusChoice, ownerChoice, startButton, endButton, tagField
)
layout.addArrangedSubview(title, subtitle, filterRow)
layout.addArrangedSubview(resultLabel)
layout.addArrangedSubview(table, svspFillAvailableSpace)

table.addColumn(newTableColumn("entry", "Entry", width = 210.0, minWidth = 160.0))
table.addColumn(newTableColumn("kind", "Kind", width = 86.0, alignment = taCenter))
table.addColumn(newTableColumn("status", "Status", width = 100.0))
table.addColumn(newTableColumn("owner", "Owner", width = 100.0))
table.addColumn(newTableColumn("date", "Updated", width = 112.0))
table.addColumn(newTableColumn("labels", "Labels", width = 330.0))
table.dataSource = controller
table.delegate = controller
table.visibleRows = 14
table.showsHeader = true
table.tableHeaderHeight = 28.0
table.rowHeight = 28.0
table.selectionMode = tsmSingle
table.usesAlternatingRowBackgrounds = true
table.showsRowSeparators = true

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(22.0, 24.0, 18.0, 24.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

activateConstraints:
  title[atHeight] == 34.0
  subtitle[atHeight] == 22.0
  filterRow[atHeight] == 34.0
  modeControl[atWidth] == 284.0
  statusChoice[atWidth] == 130.0
  ownerChoice[atWidth] == 130.0
  startButton[atWidth] == 136.0
  endButton[atWidth] == 136.0
  tagField[atWidth] == 190.0

controller.applyFilters()
app.runWindow(window, root)
