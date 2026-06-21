import merenda/nimkit

type LabeledPanel = ref object of View
  title: string
  titleColor: Color

protocol LabeledPanelDrawing of ViewDrawingProtocol:
  method draw(panel: LabeledPanel, context: DrawContext) =
    let titleRect = initRect(14.0, 11.0, max(panel.bounds.size.width - 28.0, 0.0), 24.0)
    discard context.addText(titleRect, panel.title, panel.titleColor)

proc newLabeledPanel(
    identifier, title: string, color: Color, titleColor = initColor(0.10, 0.12, 0.16)
): LabeledPanel =
  result = LabeledPanel(title: title, titleColor: titleColor)
  initViewFields(result)
  result.identifier = identifier
  result.background = color
  result.clipsToBounds = true
  result.accessibilityRole = arGroup
  result.accessibilityLabel = title
  result.accessibilityIdentifier = identifier
  result.toolTip = "Click to inspect " & identifier
  discard result.withProtocol(LabeledPanelDrawing)

proc setPanelTitle(panel: LabeledPanel, value: string) =
  panel.title = value
  panel.setNeedsDisplay(true)

let
  app = sharedApplication()
  window = newWindow("Nimkit View Inspector Demo", frame = initRect(120, 120, 940, 640))

  root = newView()
  title = newTitleLabel("View Inspector Demo")
  status =
    newStatusLabel("Click any view to inspect frame, constraints, and accessibility.")
  canvas = newView()
  toolbar = newLabeledPanel(
    "toolbar",
    "Navigation Toolbar",
    initColor(0.19, 0.27, 0.37),
    initColor(0.96, 0.98, 1.0),
  )
  sidebar = newLabeledPanel("sidebar", "Project Sidebar", initColor(0.87, 0.92, 0.90))
  editor = newLabeledPanel("editor", "Editor Surface", initColor(0.98, 0.96, 0.91))
  preview = newLabeledPanel("preview", "Preview Pane", initColor(0.90, 0.93, 0.98))
  timeline =
    newLabeledPanel("timeline", "Activity Timeline", initColor(0.95, 0.90, 0.96))
  card = newLabeledPanel("card", "Floating Card", initColor(0.99, 0.78, 0.48))
  searchField = newTextField("Search project")
  runButton = newButton("Run")
  healthSlider = newSlider(0.0, 100.0, 64.0)
  liveSwitch = newSwitchButton(true)

root.identifier = "root"
root.background = initColor(0.94, 0.95, 0.97)
root.accessibilityRole = arGroup
root.accessibilityLabel = "Demo root"
canvas.background = initColor(0.99, 0.995, 1.0)
canvas.accessibilityRole = arGroup
canvas.accessibilityLabel = "Demo canvas"
status.background = initColor(0.92, 0.98, 0.93, 1.0)
status.accessibilityElement = true
toolbar.setPanelTitle("Navigation Toolbar   search / run / live")
editor.setPanelTitle("Editor Surface   document.workspace.nim")
preview.setPanelTitle("Preview Pane   responsive layout")
timeline.setPanelTitle("Activity Timeline   constraints + accessibility")

searchField.identifier = "toolbar.searchField"
searchField.accessibilityLabel = "Project search"
runButton.identifier = "toolbar.runButton"
runButton.accessibilityLabel = "Run"
healthSlider.identifier = "preview.healthSlider"
healthSlider.accessibilityLabel = "Preview health"
liveSwitch.identifier = "preview.liveSwitch"
liveSwitch.accessibilityLabel = "Live preview"

root.addSubviews(
  autoNames(
    title, status, canvas, toolbar, sidebar, editor, preview, timeline, card,
    searchField, runButton, healthSlider, liveSwitch,
  )
)

activateConstraints:
  title[atTop] == root[atTop] + 20.0
  title[atLeft] == root[atLeft] + 24.0
  title[atRight] == root[atRight] - 24.0
  title[atHeight] == 30.0
  status[atTop] == title[atBottom] + 6.0
  status[atLeft] == title[atLeft]
  status[atRight] == title[atRight]
  status[atHeight] == 24.0
  canvas[atTop] == status[atBottom] + 16.0
  canvas[atLeft] == title[atLeft]
  canvas[atRight] == title[atRight]
  canvas[atBottom] == root[atBottom] - 24.0
  toolbar[atTop] == canvas[atTop] + 22.0
  toolbar[atLeft] == canvas[atLeft] + 22.0
  toolbar[atRight] == canvas[atRight] - 22.0
  toolbar[atHeight] == 50.0
  sidebar[atTop] == toolbar[atBottom] + 16.0
  sidebar[atLeft] == toolbar[atLeft]
  sidebar[atWidth] == 176.0
  sidebar[atBottom] == canvas[atBottom] - 22.0
  editor[atTop] == sidebar[atTop]
  editor[atLeft] == sidebar[atRight] + 18.0
  editor[atRight] == canvas[atRight] - 22.0
  editor[atHeight] == 132.0
  preview[atTop] == editor[atBottom] + 16.0
  preview[atLeft] == editor[atLeft]
  preview[atRight] == card[atLeft] - 18.0
  preview[atBottom] == timeline[atTop] - 16.0
  card[atTop] == preview[atTop] + 10.0
  card[atRight] == editor[atRight] - 10.0
  card[atWidth] == 184.0
  card[atHeight] >= 132.0 | priority = LayoutPriorityHigh
  timeline[atLeft] == editor[atLeft]
  timeline[atRight] == editor[atRight]
  timeline[atBottom] == sidebar[atBottom]
  timeline[atHeight] == 86.0
  searchField[atTop] == toolbar[atTop] + 13.0
  searchField[atLeft] == toolbar[atLeft] + 260.0
  searchField[atWidth] == 220.0
  runButton[atTop] == searchField[atTop]
  runButton[atLeft] == searchField[atRight] + 12.0
  runButton[atWidth] == 82.0
  healthSlider[atLeft] == preview[atLeft] + 18.0
  healthSlider[atRight] == liveSwitch[atLeft] - 16.0
  healthSlider[atBottom] == preview[atBottom] - 18.0
  liveSwitch[atRight] == preview[atRight] - 18.0
  liveSwitch[atCenterY] == healthSlider[atCenterY]

window.setContentView(root)
app.addWindow(window)

window.makeKeyAndOrderFront()
let inspectorPanel = showViewInspector(root, app)
inspectorPanel.inspector.selectView(toolbar)
app.run()
