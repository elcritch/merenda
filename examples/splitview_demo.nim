import merenda/nimkit

import sigils/selectors

proc paneStack(): StackView =
  result = newStackView(laVertical)
  result.spacing = 10.0
  result.alignment = svaFill
  result.distribution = svdNatural

proc titledPane(title: string, controls: openArray[View]): Box =
  let content = paneStack()
  for control in controls:
    content.addArrangedSubview(control)
  result = newGroupBox(title)
  result.contentView = content

let
  app = sharedApplication()
  window = newWindow("NimKit Split View Demo", frame = initRect(160, 140, 780, 460))
  root = newView()

  mainSplit = newSplitView(laHorizontal)
  detailSplit = newSplitView(laVertical)

  toggleSidebarAction = actionSelector("splitDemoToggleSidebar")
  toggleInspectorAction = actionSelector("splitDemoToggleInspector")
  sidebarToggle = newButton("Toggle Sidebar")
  inspectorToggle = newButton("Toggle Inspector")

  sidebar = titledPane(
    "Sidebar",
    [
      View(newHeadingLabel("Projects")),
      View(newButton("Dashboard")),
      View(newButton("Documents")),
      View(newButton("Reports")),
      View(newHorizontalSeparator()),
      View(sidebarToggle),
    ],
  )
  editor = titledPane(
    "Editor",
    [
      View(newTitleLabel("Quarterly Report")),
      View(newStatusLabel("Drag either divider to resize the workspace panes.")),
      View(newTextField("Revenue summary")),
      View(newTextField("Operating notes")),
      View(newButton("Save Draft")),
    ],
  )
  inspector = titledPane(
    "Inspector",
    [
      View(newHeadingLabel("Properties")),
      View(newCheckBox("Include charts")),
      View(newCheckBox("Lock section")),
      View(newComboBox(["Draft", "Review", "Final"])),
      View(inspectorToggle),
    ],
  )

proc toggleSidebar(sender: DynamicAgent) =
  discard sender
  mainSplit.setPaneCollapsed(0, not mainSplit.isPaneCollapsed(0))

proc toggleInspector(sender: DynamicAgent) =
  discard sender
  detailSplit.setPaneCollapsed(1, not detailSplit.isPaneCollapsed(1))

sidebarToggle.target = newActionTarget(toggleSidebarAction, toggleSidebar)
sidebarToggle.action = toggleSidebarAction
inspectorToggle.target = newActionTarget(toggleInspectorAction, toggleInspector)
inspectorToggle.action = toggleInspectorAction

detailSplit.addPane(editor, minSize = 180.0)
detailSplit.addPane(inspector, minSize = 120.0, collapsible = true)
detailSplit.setPositionOfDivider(0, 300.0)

mainSplit.addPane(sidebar, minSize = 140.0, maxSize = 280.0, collapsible = true)
mainSplit.addPane(detailSplit, minSize = 280.0)
mainSplit.setPositionOfDivider(0, 180.0)

root.addSubview(mainSplit)
mainSplit.pinEdges(
  toGuide = root.contentLayoutGuide(insets(18.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

window.minSize = initSize(520.0, 320.0)
window.setContentView(root)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
