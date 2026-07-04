import merenda/nimkit

import sigils/core
import sigils/selectors

type OutlineDemoController = ref object of Responder
  outline: OutlineView
  selectionLabel: Label
  activityLabel: Label

proc stateCell(value: string): TableCellValue =
  tableCell("state", toObj(value))

proc ownerCell(value: string): TableCellValue =
  tableCell("owner", toObj(value))

proc progressCell(value: string): TableCellValue =
  tableCell("progress", toObj(value))

proc itemCells(state, owner, progress: string): array[3, TableCellValue] =
  [stateCell(state), ownerCell(owner), progressCell(progress)]

proc demoItems(): seq[OutlineItem] =
  @[
    initOutlineItem(
      "product",
      "Product",
      expandable = true,
      cells = itemCells("Active", "Mara", "68%"),
      tooltip = "Product planning and release coordination",
    ),
    initOutlineItem(
      "roadmap",
      "Roadmap",
      parentIdentifier = "product",
      expandable = true,
      cells = itemCells("Review", "Iris", "42%"),
    ),
    initOutlineItem(
      "q3-desktop",
      "Desktop app refresh",
      parentIdentifier = "roadmap",
      leaf = true,
      cells = itemCells("Active", "Noah", "70%"),
    ),
    initOutlineItem(
      "q3-importer",
      "Importer polish",
      parentIdentifier = "roadmap",
      leaf = true,
      cells = itemCells("Queued", "Ren", "18%"),
    ),
    initOutlineItem(
      "research",
      "Research",
      parentIdentifier = "product",
      expandable = true,
      cells = itemCells("Active", "Leah", "55%"),
    ),
    initOutlineItem(
      "user-calls",
      "User interviews",
      parentIdentifier = "research",
      leaf = true,
      cells = itemCells("Done", "Ari", "100%"),
    ),
    initOutlineItem(
      "pricing",
      "Pricing study",
      parentIdentifier = "research",
      leaf = true,
      cells = itemCells("Blocked", "Sol", "24%"),
      enabled = false,
    ),
    initOutlineItem(
      "engineering",
      "Engineering",
      expandable = true,
      cells = itemCells("Active", "Owen", "74%"),
    ),
    initOutlineItem(
      "runtime",
      "Runtime",
      parentIdentifier = "engineering",
      expandable = true,
      cells = itemCells("Active", "Vik", "81%"),
    ),
    initOutlineItem(
      "scheduler",
      "Scheduler",
      parentIdentifier = "runtime",
      leaf = true,
      cells = itemCells("Done", "Vik", "100%"),
    ),
    initOutlineItem(
      "cache",
      "Cache invalidation",
      parentIdentifier = "runtime",
      leaf = true,
      cells = itemCells("Active", "June", "63%"),
    ),
    initOutlineItem(
      "interface",
      "Interface",
      parentIdentifier = "engineering",
      expandable = true,
      cells = itemCells("Review", "Nia", "88%"),
    ),
    initOutlineItem(
      "outline-demo",
      "OutlineView demo",
      parentIdentifier = "interface",
      leaf = true,
      cells = itemCells("Active", "Nia", "76%"),
    ),
    initOutlineItem(
      "table-editing",
      "Table editing pass",
      parentIdentifier = "interface",
      leaf = true,
      cells = itemCells("Done", "Paz", "100%"),
    ),
    initOutlineItem(
      "operations",
      "Operations",
      expandable = true,
      cells = itemCells("Queued", "June", "31%"),
    ),
    initOutlineItem(
      "qa",
      "QA matrix",
      parentIdentifier = "operations",
      leaf = true,
      cells = itemCells("Queued", "June", "12%"),
    ),
    initOutlineItem(
      "release-notes",
      "Release notes",
      parentIdentifier = "operations",
      leaf = true,
      cells = itemCells("Review", "Iris", "48%"),
    ),
  ]

proc valueText(outline: OutlineView, identifier, columnIdentifier: string): string =
  outline.valueForItem(identifier, columnIdentifier).formatObjectValue(
    initObjectFormatContext(role = ovrTableCell)
  )

proc selectedSummary(controller: OutlineDemoController): string =
  let identifier = controller.outline.selectedItemIdentifier()
  if identifier.len == 0:
    return "No item selected"

  let
    item = controller.outline.outlineItemWithIdentifier(identifier)
    children = controller.outline.childIdentifiersForItem(identifier)
    state = controller.outline.valueText(identifier, "state")
    owner = controller.outline.valueText(identifier, "owner")
    progress = controller.outline.valueText(identifier, "progress")
    level = controller.outline.levelForItem(identifier)
  result =
    item.displayTitle() & "\n" & state & " / " & owner & " / " & progress & "\nLevel " &
    $level
  if children.len > 0:
    result.add " / " & $children.len & " child item"
    if children.len != 1:
      result.add "s"

proc updateSelection(controller: OutlineDemoController) =
  controller.selectionLabel.text = controller.selectedSummary()

proc updateActivity(controller: OutlineDemoController, message: string) =
  controller.activityLabel.text = message

proc expandAll(controller: OutlineDemoController) =
  for identifier in controller.outline.outlineItemIdentifiers():
    if controller.outline.isItemExpandable(identifier):
      controller.outline.expandItem(identifier)
  controller.updateSelection()
  controller.updateActivity("Expanded all groups")

proc collapseAll(controller: OutlineDemoController) =
  controller.outline.expandedItemIdentifiers = []
  controller.updateSelection()
  controller.updateActivity("Collapsed all groups")

proc focusCurrent(controller: OutlineDemoController) =
  let identifier = controller.outline.selectedItemIdentifier()
  if identifier.len == 0:
    controller.updateActivity("No selected item to focus")
    return

  let
    item = controller.outline.outlineItemWithIdentifier(identifier)
    status = controller.outline.valueText(identifier, "state")
  controller.updateActivity("Focused " & item.displayTitle() & " (" & status & ")")

proc outlineSelectionDidChange(
    controller: OutlineDemoController, sender: DynamicAgent
) {.slot.} =
  if sender == DynamicAgent(controller.outline):
    controller.updateSelection()

protocol OutlineDemoDelegate of OutlineViewDelegate:
  method didExpandItem(
      controller: OutlineDemoController, outlineView: OutlineView, identifier: string
  ) =
    let title = outlineView.titleForItem(identifier)
    controller.updateActivity("Expanded " & title)
    controller.updateSelection()

  method didCollapseItem(
      controller: OutlineDemoController, outlineView: OutlineView, identifier: string
  ) =
    let title = outlineView.titleForItem(identifier)
    controller.updateActivity("Collapsed " & title)
    controller.updateSelection()

proc newOutlineDemoController(
    outline: OutlineView, selectionLabel, activityLabel: Label
): OutlineDemoController =
  result = OutlineDemoController(
    outline: outline, selectionLabel: selectionLabel, activityLabel: activityLabel
  )
  initResponder(result)
  discard result.withProtocol(OutlineDemoDelegate)

proc configureOutline(outline: OutlineView) =
  let
    outlineColumn = outline.outlineColumn()
    stateColumn = newTableColumn("state", "State", width = 92.0, alignment = taCenter)
    ownerColumn = newTableColumn("owner", "Owner", width = 92.0)
    progressColumn =
      newTableColumn("progress", "Progress", width = 92.0, alignment = taRight)

  outlineColumn.title = "Area"
  outlineColumn.minWidth = 180.0
  outlineColumn.width = 260.0
  outline.addColumn(stateColumn)
  outline.addColumn(ownerColumn)
  outline.addColumn(progressColumn)
  outline.outlineItems = demoItems()
  outline.expandedItemIdentifiers = ["product", "roadmap", "engineering", "runtime"]
  outline.selectedItemIdentifier = "q3-desktop"
  outline.visibleRows = 12
  outline.showsHeader = true
  outline.tableHeaderHeight = 26.0
  outline.rowHeight = 28.0
  outline.selectionMode = tsmSingle
  outline.usesAlternatingRowBackgrounds = true
  outline.showsRowSeparators = true
  outline.autosaveName = "outline-demo"

const
  TitleHeight = 32.0
  SidebarWidth = 236.0

let
  app = sharedApplication()
  window = newWindow("NimKit Outline Demo", frame = rect(150, 130, 860, 460))
  root = newView()
  title = newTitleLabel("Outline View")
  outline = newOutlineView()
  selectionTitle = newHeadingLabel("Selection")
  selectionLabel = newStatusLabel("")
  activityTitle = newHeadingLabel("Activity")
  activityLabel = newStatusLabel("Use disclosure buttons or arrow keys to expand rows.")
  expandButton = newButton("Expand All")
  collapseButton = newButton("Collapse All")
  focusButton = newButton("Focus Selected")
  expandAction = actionSelector("outlineDemoExpandAll")
  collapseAction = actionSelector("outlineDemoCollapseAll")
  focusAction = actionSelector("outlineDemoFocusSelected")

outline.configureOutline()

let controller = newOutlineDemoController(outline, selectionLabel, activityLabel)

outline.outlineDelegate = controller
outline.connect(selectionDidChange, controller, outlineSelectionDidChange)

expandButton.target = newActionTarget(
  expandAction,
  proc(sender: DynamicAgent) =
    discard sender
    controller.expandAll(),
)
expandButton.action = expandAction

collapseButton.target = newActionTarget(
  collapseAction,
  proc(sender: DynamicAgent) =
    discard sender
    controller.collapseAll(),
)
collapseButton.action = collapseAction

focusButton.target = newActionTarget(
  focusAction,
  proc(sender: DynamicAgent) =
    discard sender
    controller.focusCurrent(),
)
focusButton.action = focusAction

root.addSubviews(
  autoNames(
    title, outline, selectionTitle, selectionLabel, activityTitle, activityLabel,
    expandButton, collapseButton, focusButton,
  )
)

title.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

activateConstraints:
  title[atHeight] == TitleHeight
  expandButton[atTop] == title[atBottom] + 14.0
  expandButton[atLeft] == title[atLeft]
  expandButton[atWidth] >= 8.5'em
  expandButton[atHeight] == 2.4'em
  collapseButton[atTop] == expandButton[atTop]
  collapseButton[atLeft] == expandButton[atRight] + 8.0
  collapseButton[atWidth] >= 9.0'em
  collapseButton[atHeight] == expandButton[atHeight]
  focusButton[atTop] == expandButton[atTop]
  focusButton[atLeft] == collapseButton[atRight] + 8.0
  focusButton[atWidth] >= 10.5'em
  focusButton[atHeight] == expandButton[atHeight]
  outline[atTop] == expandButton[atBottom] + 14.0
  outline[atLeft] == title[atLeft]
  outline[atRight] == selectionTitle[atLeft] - 22.0
  outline[atBottom] == root[atBottom] - 2'em
  selectionTitle[atTop] == outline[atTop] + 4.0
  selectionTitle[atRight] == title[atRight]
  selectionTitle[atWidth] == SidebarWidth
  selectionTitle[atHeight] == 1.5'em
  selectionLabel[atTop] == selectionTitle[atBottom] + 1'em
  selectionLabel[atLeft] == selectionTitle[atLeft]
  selectionLabel[atRight] == selectionTitle[atRight]
  activityTitle[atTop] == selectionLabel[atBottom] + 1.5'em
  activityTitle[atLeft] == selectionTitle[atLeft]
  activityTitle[atRight] == selectionTitle[atRight]
  activityTitle[atHeight] == 1.5'em
  activityLabel[atTop] == activityTitle[atBottom] + 1'em
  activityLabel[atLeft] == selectionTitle[atLeft]
  activityLabel[atRight] == selectionTitle[atRight]
  selectionLabel[atHeight] == 6'em
  activityLabel[atBottom] == outline[atBottom]

controller.updateSelection()
app.runWindow(window, root, outline)
