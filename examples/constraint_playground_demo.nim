import merenda/nimkit

import sigils/selectors

const
  SpacingValues = [4.0'f32, 8.0'f32, 14.0'f32, 22.0'f32]
  ToolbarHeights = [26.0'f32, 34.0'f32, 44.0'f32, 56.0'f32]
  SidebarWidths = [0.0'f32, 180.0'f32, 240.0'f32, 300.0'f32]

proc selectedFloat(combo: ComboBox, values: openArray[float32]): float32 =
  let index = combo.selectedIndex()
  if index >= 0 and index < values.len:
    values[index]
  else:
    values[0]

let
  app = sharedApplication()
  window =
    newWindow("Nimkit Constraint Playground", frame = initRect(140, 130, 900, 520))
  root = newView()

  title = newTitleLabel("Constraint Playground")
  subtitle = newStatusLabel("Change the controls on the right to rebuild constraints.")

  preview = newView()
  previewTitle = newLabel("Title Bar")
  previewSubtitle = newLabel("Subtitle Row")
  toolbar = newView()
  toolbarLabel = newLabel("Toolbar")
  content = newView()
  contentTitle = newHeadingLabel("Preview Content")
  contentBody = newStatusLabel("Alignment changes which anchor owns this card.")
  sidebar = newView()
  sidebarTitle = newHeadingLabel("Inspector")
  sidebarBody = newStatusLabel("Width can collapse to hidden.")
  card = newView()
  cardTitle = newHeadingLabel("Live Card")
  cardBody = newStatusLabel("This view is constrained inside the content area.")

  inspectorTitle = newHeadingLabel("Controls")
  spacingLabel = newFormLabel("Spacing")
  spacingChoice = newComboBox(["4 px", "8 px", "14 px", "22 px"])
  toolbarLabelControl = newFormLabel("Toolbar")
  toolbarChoice = newComboBox(["26 px", "34 px", "44 px", "56 px"])
  sidebarLabel = newFormLabel("Sidebar")
  sidebarChoice = newComboBox(["Hidden", "180 px", "240 px", "300 px"])
  alignmentLabel = newFormLabel("Card")
  alignmentChoice = newComboBox(["Left", "Center", "Right"])
  summary = newStatusLabel("")
  changedAction = actionSelector("constraintPlaygroundChanged")

var cxs: seq[LayoutConstraint]

proc updateSummary() =
  let
    spacing = spacingChoice.selectedFloat(SpacingValues)
    toolbarHeight = toolbarChoice.selectedFloat(ToolbarHeights)
    sidebarWidth = sidebarChoice.selectedFloat(SidebarWidths)
    sidebarText =
      if sidebarWidth <= 0.0'f32:
        "off"
      else:
        $int(sidebarWidth)
  summary.text =
    "S" & $int(spacing) & " T" & $int(toolbarHeight) & " W" & sidebarText & " " &
    alignmentChoice.stringValue

proc rebuildPreviewConstraints() =
  if cxs.len > 0:
    deactivateConstraints(cxs)
    cxs.setLen(0)

  let
    spacing = spacingChoice.selectedFloat(SpacingValues)
    toolbarHeight = toolbarChoice.selectedFloat(ToolbarHeights)
    sidebarWidth = sidebarChoice.selectedFloat(SidebarWidths)
    alignment = alignmentChoice.selectedIndex()

  let sidebarCollapsed = sidebarWidth <= 0.0'f32
  for view in [sidebar, sidebarTitle, sidebarBody]:
    view.hidden = sidebarCollapsed

  cxs.add cx(previewTitle[atTop] == preview[atTop] + 14.0)
  cxs.add cx(previewTitle[atLeft] == preview[atLeft] + 18.0)
  cxs.add cx(previewTitle[atWidth] == 260.0)
  cxs.add cx(previewTitle[atHeight] == 24.0)
  cxs.add cx(previewSubtitle[atTop] == previewTitle[atBottom] + spacing)
  cxs.add cx(previewSubtitle[atLeft] == previewTitle[atLeft])
  cxs.add cx(previewSubtitle[atWidth] == 320.0)
  cxs.add cx(previewSubtitle[atHeight] == 20.0)
  cxs.add cx(toolbar[atTop] == previewSubtitle[atBottom] + spacing)
  cxs.add cx(toolbar[atLeft] == preview[atLeft] + 18.0)
  cxs.add cx(toolbar[atRight] == preview[atRight] - 18.0)
  cxs.add cx(toolbar[atHeight] == toolbarHeight)
  cxs.add cx(content[atTop] == toolbar[atBottom] + spacing)
  cxs.add cx(content[atLeft] == toolbar[atLeft])
  cxs.add cx(content[atBottom] == preview[atBottom] - 16.0)

  if sidebarWidth > 0.0'f32:
    cxs.add cx(sidebar[atTop] == content[atTop])
    cxs.add cx(sidebar[atRight] == toolbar[atRight])
    cxs.add cx(sidebar[atBottom] == content[atBottom])
    cxs.add cx(sidebar[atWidth] == sidebarWidth)
    cxs.add cx(content[atRight] == sidebar[atLeft] - spacing)
  else:
    cxs.add cx(sidebar[atTop] == content[atTop])
    cxs.add cx(sidebar[atRight] == toolbar[atRight])
    cxs.add cx(sidebar[atBottom] == content[atBottom])
    cxs.add cx(sidebar[atWidth] == 0.0)
    cxs.add cx(content[atRight] == toolbar[atRight])

  cxs.add cx(card[atTop] == contentTitle[atBottom] + 4 * spacing)
  cxs.add cx(card[atWidth] == 240.0)
  cxs.add cx(card[atHeight] >= 108.0, priority = LayoutPriorityHigh)
  cxs.add cx(card[atBottom] == content[atBottom] - 100.0, priority = LayoutPriorityLow)
  case alignment
  of 1:
    cxs.add cx(card[atCenterX] == content[atCenterX])
  of 2:
    cxs.add cx(card[atRight] == content[atRight] - spacing)
  else:
    cxs.add cx(card[atLeft] == content[atLeft] + spacing)

  activateConstraints(cxs)
  updateSummary()

proc onChanged(sender: DynamicAgent) =
  if not sender.isNil:
    rebuildPreviewConstraints()

let target = newActionTarget(changedAction, onChanged)
preview.background = color(0.99, 0.99, 1.0)
previewTitle.background = color(0.83, 0.90, 0.98)
previewSubtitle.background = color(0.90, 0.94, 0.98)
toolbar.background = color(0.17, 0.27, 0.36)
content.background = color(0.96, 0.93, 0.87)
sidebar.background = color(0.88, 0.92, 0.89)
card.background = color(0.99, 0.78, 0.50)

toolbarLabel.textColor = color(1.0, 1.0, 1.0)
cardTitle.textColor = color(0.10, 0.08, 0.06)
cardBody.textColor = color(0.12, 0.10, 0.08)

spacingChoice.selectedIndex = 2
toolbarChoice.selectedIndex = 1
sidebarChoice.selectedIndex = 2
alignmentChoice.selectedIndex = 1

for combo in [spacingChoice, toolbarChoice, sidebarChoice, alignmentChoice]:
  combo.target = target
  combo.action = changedAction

root.addSubviews(
  autoNames(
    title, subtitle, preview, previewTitle, previewSubtitle, toolbar, content, sidebar,
    card, toolbarLabel, contentTitle, contentBody, sidebarTitle, sidebarBody, cardTitle,
    cardBody, inspectorTitle, spacingLabel, spacingChoice, toolbarLabelControl,
    toolbarChoice, sidebarLabel, sidebarChoice, alignmentLabel, alignmentChoice, summary,
  )
)

activateConstraints:
  title[atTop] == root[atTop] + 18.0
  title[atLeft] == root[atLeft] + 22.0
  title[atWidth] == 320.0
  title[atHeight] == 28.0
  subtitle[atTop] == title[atBottom] + 5.0
  subtitle[atLeft] == title[atLeft]
  subtitle[atWidth] == 420.0
  subtitle[atHeight] == 20.0
  preview[atTop] == subtitle[atBottom] + 14.0
  preview[atLeft] == title[atLeft]
  preview[atRight] == inspectorTitle[atLeft] - 24.0
  preview[atBottom] == root[atBottom] - 18.0
  inspectorTitle[atTop] == title[atTop] + 2.0
  inspectorTitle[atRight] == root[atRight] - 22.0
  inspectorTitle[atWidth] == 220.0
  inspectorTitle[atHeight] == 24.0
  spacingLabel[atTop] == inspectorTitle[atBottom] + 18.0
  spacingLabel[atLeft] == inspectorTitle[atLeft]
  spacingLabel[atWidth] == 72.0
  spacingChoice[atTop] == spacingLabel[atTop]
  spacingChoice[atLeft] == spacingLabel[atRight] + 12.0
  spacingChoice[atRight] == inspectorTitle[atRight]
  toolbarLabelControl[atTop] == spacingChoice[atBottom] + 14.0
  toolbarLabelControl[atLeft] == spacingLabel[atLeft]
  toolbarLabelControl[atWidth] == spacingLabel[atWidth]
  toolbarChoice[atTop] == toolbarLabelControl[atTop]
  toolbarChoice[atLeft] == spacingChoice[atLeft]
  toolbarChoice[atRight] == spacingChoice[atRight]
  sidebarLabel[atTop] == toolbarChoice[atBottom] + 14.0
  sidebarLabel[atLeft] == spacingLabel[atLeft]
  sidebarLabel[atWidth] == spacingLabel[atWidth]
  sidebarChoice[atTop] == sidebarLabel[atTop]
  sidebarChoice[atLeft] == spacingChoice[atLeft]
  sidebarChoice[atRight] == spacingChoice[atRight]
  alignmentLabel[atTop] == sidebarChoice[atBottom] + 14.0
  alignmentLabel[atLeft] == spacingLabel[atLeft]
  alignmentLabel[atWidth] == spacingLabel[atWidth]
  alignmentChoice[atTop] == alignmentLabel[atTop]
  alignmentChoice[atLeft] == spacingChoice[atLeft]
  alignmentChoice[atRight] == spacingChoice[atRight]
  summary[atTop] == alignmentChoice[atBottom] + 22.0
  summary[atLeft] == inspectorTitle[atLeft]
  summary[atRight] == inspectorTitle[atRight]
  summary[atHeight] == 24.0
  toolbarLabel[atCenterX] == toolbar[atCenterX]
  toolbarLabel[atCenterY] == toolbar[atCenterY]
  contentTitle[atTop] == content[atTop] + 12.0
  contentTitle[atLeft] == content[atLeft] + 14.0
  contentTitle[atRight] == content[atRight] - 14.0
  contentTitle[atHeight] == 24.0
  contentBody[atTop] == contentTitle[atBottom] + 6.0
  contentBody[atLeft] == contentTitle[atLeft]
  contentBody[atRight] == contentTitle[atRight]
  contentBody[atHeight] == 22.0
  sidebarTitle[atTop] == sidebar[atTop] + 12.0
  sidebarTitle[atLeft] == sidebar[atLeft] + 16.0
  sidebarTitle[atRight] == sidebar[atRight] - 16.0
  sidebarTitle[atHeight] == 24.0
  sidebarBody[atTop] == sidebarTitle[atBottom] + 6.0
  sidebarBody[atLeft] == sidebarTitle[atLeft]
  sidebarBody[atRight] == sidebarTitle[atRight]
  sidebarBody[atHeight] == 42.0
  cardTitle[atTop] == card[atTop] + 14.0
  cardTitle[atLeft] == card[atLeft] + 16.0
  cardTitle[atRight] == card[atRight] - 16.0
  cardTitle[atHeight] == 24.0
  cardBody[atTop] == cardTitle[atBottom] + 6.0
  cardBody[atLeft] == cardTitle[atLeft]
  cardBody[atRight] == cardTitle[atRight]
  cardBody[atHeight] == 54.0

rebuildPreviewConstraints()

window.setContentView(root)
discard window.makeFirstResponder(spacingChoice)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
