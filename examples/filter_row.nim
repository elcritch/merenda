import std/strutils

import merenda/nimkit

import sigils/core
import sigils/selectors as dynamicSelectors

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
    modeButtons: array[FilterMode, Button]
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
    tagChoice: ComboBox
    tagOptions: ComboBoxOptionList
    tagQuery: string
    chipScroll: ScrollView
    chipRow: StackView

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
  for mode in FilterMode:
    if sender == DynamicAgent(controller.modeButtons[mode]):
      controller.mode = mode
  for mode in FilterMode:
    controller.modeButtons[mode].state = if mode == controller.mode: bsOn else: bsOff
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

proc setTagEnabled(controller: FilterDemoController, tag: string, enabled: bool) =
  var options = controller.tagOptions.options
  for index, option in options:
    if option.identifier == tag:
      options[index].enabled = enabled
  controller.tagOptions.options = options
  controller.tagChoice.reloadData()

proc rebuildTagChips(controller: FilterDemoController)

proc removeTag(controller: FilterDemoController, tag: string) =
  for index, selected in controller.selectedTags:
    if selected == tag:
      controller.selectedTags.delete(index)
      break
  controller.setTagEnabled(tag, true)
  controller.rebuildTagChips()
  controller.applyFilters()

proc clearTagQuery(controller: FilterDemoController) =
  controller.tagQuery.setLen(0)
  controller.tagChoice.closePopup()
  controller.tagChoice.deselectItem()
  controller.tagChoice.optionFilterText = ""
  controller.tagChoice.text = "Add labels..."

proc onTagChanged(controller: FilterDemoController, sender: DynamicAgent) =
  discard sender
  let tag = controller.tagChoice.stringValue
  if tag.len == 0 or tag == "Add labels..." or tag in controller.selectedTags:
    return
  controller.selectedTags.add tag
  controller.setTagEnabled(tag, false)
  controller.clearTagQuery()
  controller.rebuildTagChips()
  controller.applyFilters()

proc installTagAutocomplete(controller: FilterDemoController) =
  let wrapper: dynamicSelectors.AroundMethod = proc(
      self: DynamicAgent,
      invocation: var dynamicSelectors.Invocation,
      next: dynamicSelectors.DynamicMethod,
  ) =
    let event = invocation.argsAs(KeyEvent)
    if event.modifiers == {} and event.key in {keyBackspace, keyDelete}:
      if controller.tagQuery.len > 0:
        controller.tagQuery.setLen(controller.tagQuery.len - 1)
      controller.tagChoice.optionFilterText = controller.tagQuery
      controller.tagChoice.text = controller.tagQuery
      controller.tagChoice.openPopup()
      invocation.setResult(true)
      return
    if event.modifiers == {} and event.text.len > 0:
      controller.tagQuery.add event.text
      controller.tagChoice.text = controller.tagQuery
      controller.tagChoice.optionFilterText = controller.tagQuery
      controller.tagChoice.openPopup()
      invocation.setResult(true)
      return
    if not next.isNil:
      next(self, invocation)
    elif not invocation.handled:
      invocation.setResult(false)

  discard DynamicAgent(controller.tagChoice).pushMethod(keyDown(), wrapper)

proc rebuildTagChips(controller: FilterDemoController) =
  for child in controller.chipRow.arrangedSubviews:
    child.removeFromSuperview()

  if controller.selectedTags.len == 0:
    let empty = newStatusLabel("No labels selected")
    controller.chipRow.addArrangedSubview(empty)
  else:
    for tag in controller.selectedTags:
      let
        chip = newButton(tag & "  ×")
        chipTag = tag
        action = actionSelector("filterRemoveTag")
      chip.styleClasses = @["filter-chip"]
      chip.target = newActionTarget(
        action,
        proc(sender: DynamicAgent) =
          discard sender
          controller.removeTag(chipTag),
      )
      chip.action = action
      controller.chipRow.addArrangedSubview(chip)

  controller.chipRow.sizeToFit()
  controller.chipScroll.tile()

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
  modeRow = newStackView(laHorizontal)
  statusChoice = newComboBox()
  ownerChoice = newComboBox()
  startButton = newDatePickerButton("From")
  endButton = newDatePickerButton("Until")
  tagChoice = newComboBox()
  chipScroll = newScrollView()
  chipRow = newStackView(laHorizontal)
  resultLabel = newStatusLabel("")
  table = newTableView()
  controller = newFilterDemoController(table, resultLabel)

root.appearance = makeFilterAppearance()
filterRow.spacing = 8.0
filterRow.alignment = svaCenter
filterRow.distribution = svdNatural
modeRow.spacing = 2.0
modeRow.alignment = svaCenter
modeRow.distribution = svdNatural
chipRow.spacing = 6.0
chipRow.alignment = svaCenter
chipRow.distribution = svdNatural

for mode in FilterMode:
  let button =
    case mode
    of fmAll:
      newButton("All entries")
    of fmNormal:
      newButton("Normal only")
    of fmIgnored:
      newButton("Ignored only")
  button.buttonType = btToggle
  button.styleClasses = @["filter-segment"]
  controller.modeButtons[mode] = button
  modeRow.addArrangedSubview(button)

controller.statusChoice = statusChoice
controller.ownerChoice = ownerChoice
controller.startButton = startButton
controller.endButton = endButton
startButton.selectedDate = controller.startDate
endButton.selectedDate = controller.endDate
controller.tagChoice = tagChoice
controller.chipScroll = chipScroll
controller.chipRow = chipRow

statusChoice.dataSource = makeChoiceOptions("any-status", "Any status", DemoStatuses)
ownerChoice.dataSource = makeChoiceOptions("any-owner", "Any owner", DemoOwners)
statusChoice.selectedIndex = 0
ownerChoice.selectedIndex = 0
statusChoice.styleClasses = @["filter-choice"]
ownerChoice.styleClasses = @["filter-choice"]

tagChoice.styleClasses = @["filter-autocomplete"]
tagChoice.editable = false
tagChoice.maxVisibleItems = 6
tagChoice.popupPresentation = ppInline
tagChoice.text = "Add labels..."
controller.tagOptions = newComboBoxOptionList()
for tag in DemoTags:
  controller.tagOptions.add(
    initComboBoxOption(identifier = tag, displayText = tag, objectValue = toObj(tag))
  )
tagChoice.dataSource = controller.tagOptions

let
  modeAction = actionSelector("filterModeChanged")
  choiceAction = actionSelector("filterChoiceChanged")
  tagAction = actionSelector("filterTagChanged")
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
  tagTarget = newActionTarget(
    tagAction,
    proc(sender: DynamicAgent) =
      controller.onTagChanged(sender),
  )

for mode in FilterMode:
  controller.modeButtons[mode].target = modeTarget
  controller.modeButtons[mode].action = modeAction
controller.modeButtons[fmAll].state = bsOn

for combo in [statusChoice, ownerChoice]:
  combo.target = choiceTarget
  combo.action = choiceAction

tagChoice.target = tagTarget
tagChoice.action = tagAction

startButton.onSelect = proc(date: CalendarDate) =
  controller.setStartDate(date)
endButton.onSelect = proc(date: CalendarDate) =
  controller.setEndDate(date)
controller.installTagAutocomplete()

filterRow.addArrangedSubview(
  modeRow, statusChoice, ownerChoice, startButton, endButton, tagChoice
)
layout.addArrangedSubview(title, subtitle, filterRow)
chipScroll.documentView = chipRow
layout.addArrangedSubview(chipScroll, resultLabel)
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
  modeRow[atWidth] == 284.0
  statusChoice[atWidth] == 130.0
  ownerChoice[atWidth] == 130.0
  startButton[atWidth] == 136.0
  endButton[atWidth] == 136.0
  tagChoice[atWidth] == 190.0
  chipScroll[atHeight] == 34.0

controller.rebuildTagChips()
controller.applyFilters()
app.runWindow(window, root)
