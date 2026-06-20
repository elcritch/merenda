import std/[math, strutils]

import merenda/nimkit

import sigils/core
import sigils/selectors

type
  InspectorController = ref object of Responder
    root: View
    selected: View
    status: Label
    selection: Label
    details: Label
    hierarchy: Label
    commandStatus: Label

  InspectablePanel = ref object of View
    controller: InspectorController

proc px(value: float32): string =
  $int(round(value))

proc rectSummary(rect: Rect): string =
  "x " & rect.origin.x.px & "  y " & rect.origin.y.px & "  w " & rect.size.width.px &
    "  h " & rect.size.height.px

proc colorSummary(color: Color): string =
  "rgba(" & $int(round(color.r * 255.0'f32)) & ", " & $int(round(color.g * 255.0'f32)) &
    ", " & $int(round(color.b * 255.0'f32)) & ", " & $int(round(color.a * 100.0'f32)) &
    "%)"

proc viewKind(view: View): string =
  if view.isNil:
    "None"
  elif view of Button:
    "Button"
  elif view of Slider:
    "Slider"
  elif view of SwitchButton:
    "SwitchButton"
  elif view of ComboBox:
    "ComboBox"
  elif view of Label:
    "Label"
  elif view of TextField:
    "TextField"
  elif view of StackView:
    "StackView"
  elif view of ScrollView:
    "ScrollView"
  elif view of InspectablePanel:
    "InspectablePanel"
  else:
    "View"

proc displayName(view: View): string =
  if view.isNil:
    return "none"
  if view.identifier.len > 0:
    return view.identifier
  view.viewKind

proc touches(constraint: LayoutConstraint, view: View): bool =
  not constraint.isNil and
    (constraint.xFirstItem == view or constraint.xSecondItem == view)

proc touchingConstraintCount(root, view: View): int =
  if root.isNil or view.isNil:
    return
  for constraint in root.constraints:
    if constraint.touches(view):
      inc result
  for child in root.subviews:
    result += child.touchingConstraintCount(view)

proc addTreeLines(lines: var seq[string], view, selected: View, depth: int) =
  if view.isNil or depth > 5:
    return
  let prefix = if view == selected: "-> " else: "   "
  lines.add repeat("  ", depth) & prefix & view.displayName & "  " & view.viewKind
  for child in view.subviews:
    lines.addTreeLines(child, selected, depth + 1)

proc hierarchySummary(root, selected: View): string =
  var lines: seq[string]
  lines.addTreeLines(root, selected, 0)
  lines.join("\n")

proc updateInspector(controller: InspectorController) =
  let view = controller.selected
  if view.isNil:
    controller.status.text = "Click a view in the demo window."
    controller.selection.text = "No selection"
    controller.details.text = ""
    controller.hierarchy.text = controller.root.hierarchySummary(nil)
    controller.commandStatus.text = ""
    return

  let
    frame = view.frame
    bounds = view.bounds
    accessibilityLabel = view.accessibilityLabel()
    accessibilityIdentifier = view.accessibilityIdentifier()
    hiddenText = if view.hidden: "hidden" else: "visible"
    touchCount = controller.root.touchingConstraintCount(view)

  controller.status.text = "Selected: " & view.displayName
  controller.selection.text = view.displayName & "  /  " & view.viewKind
  controller.details.text =
    "identifier: " & view.identifier & "\n" & "kind: " & view.viewKind & "\n" & "frame: " &
    frame.rectSummary & "\n" & "bounds: " & bounds.rectSummary & "\n" & "background: " &
    view.backgroundColor.colorSummary & "\n" & "state: " & hiddenText & "\n" &
    "children: " & $view.subviews.len & "\n" & "constraints here: " &
    $view.constraints.len & "\n" & "constraints touching: " & $touchCount & "\n" &
    "accessibility role: " & $view.accessibilityRole() & "\n" & "accessibility label: " &
    accessibilityLabel & "\n" & "accessibility id: " & accessibilityIdentifier
  controller.hierarchy.text = controller.root.hierarchySummary(view)
  controller.commandStatus.text = "Inspector synced."

proc selectView(controller: InspectorController, view: View) =
  let previous = controller.selected
  if previous == view:
    controller.updateInspector()
    return
  controller.selected = view
  if not previous.isNil:
    previous.setNeedsDisplay(true)
  if not view.isNil:
    view.setNeedsDisplay(true)
  controller.updateInspector()

protocol InspectablePanelEvents of ResponderEventProtocol:
  method mouseDown(panel: InspectablePanel, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false
    panel.controller.selectView(View(panel))
    true

protocol InspectablePanelDrawing of ViewDrawingProtocol:
  method draw(panel: InspectablePanel, context: DrawContext) =
    if panel.controller.isNil or panel.controller.selected != View(panel):
      return
    let ring = panel.bounds.inset(initEdgeInsets(2.0'f32))
    discard context.addRenderRectangle(
      ring,
      initColor(0.0, 0.0, 0.0, 0.0),
      initColor(0.0, 0.45, 1.0, 0.95),
      3.0'f32,
      8.0'f32,
    )

proc newInspectorController(): InspectorController =
  result = InspectorController()
  initResponder(result)

proc newInspectablePanel(
    controller: InspectorController,
    identifier, title: string,
    color: Color,
    titleColor = initColor(0.10, 0.12, 0.16),
): InspectablePanel =
  result = InspectablePanel(controller: controller)
  initViewFields(result)
  result.identifier = identifier
  result.background = color
  result.accessibilityRole = arGroup
  result.accessibilityLabel = title
  result.accessibilityIdentifier = identifier
  result.toolTip = "Click to inspect " & identifier
  discard result.withProtocol(InspectablePanelEvents)
  discard result.withProtocol(InspectablePanelDrawing)

  let label = newHeadingLabel(title, frame = initRect(14, 11, 240, 24))
  label.identifier = identifier & ".title"
  label.background = initColor(0.0, 0.0, 0.0, 0.0)
  label.textColor = titleColor
  result.addSubview(label)

proc setPanelTitle(panel: InspectablePanel, value: string) =
  if panel.subviews.len > 0 and panel.subviews[0] of Label:
    Label(panel.subviews[0]).text = value

let
  app = sharedApplication()
  window = newWindow("Nimkit View Inspector Demo", frame = initRect(120, 120, 860, 560))
  inspectorWindow = newPanel("Inspector", frame = initRect(1010, 140, 360, 580))
  controller = newInspectorController()

  root = newView()
  title = newTitleLabel("View Inspector Demo")
  status = newStatusLabel("Click any colored region, then watch the Inspector window.")
  canvas = newView()
  toolbar = newInspectablePanel(
    controller,
    "toolbar",
    "Navigation Toolbar",
    initColor(0.19, 0.27, 0.37),
    initColor(0.96, 0.98, 1.0),
  )
  sidebar = newInspectablePanel(
    controller, "sidebar", "Project Sidebar", initColor(0.87, 0.92, 0.90)
  )
  editor = newInspectablePanel(
    controller, "editor", "Editor Surface", initColor(0.98, 0.96, 0.91)
  )
  preview = newInspectablePanel(
    controller, "preview", "Preview Pane", initColor(0.90, 0.93, 0.98)
  )
  timeline = newInspectablePanel(
    controller, "timeline", "Activity Timeline", initColor(0.95, 0.90, 0.96)
  )
  card = newInspectablePanel(
    controller, "card", "Floating Card", initColor(0.99, 0.78, 0.48)
  )
  searchField = newTextField("Search project")
  runButton = newButton("Run")
  healthSlider = newSlider(0.0, 100.0, 64.0)
  liveSwitch = newSwitchButton(true)
  inspectorRoot = newView()
  inspectorTitle = newTitleLabel("Inspector")
  selectedLabel = newStatusLabel("")
  detailsTitle = newHeadingLabel("Selection")
  details = newStatusLabel("")
  hierarchyTitle = newHeadingLabel("Hierarchy")
  hierarchy = newStatusLabel("")
  commandsTitle = newHeadingLabel("Commands")
  hiddenButton = newButton("Toggle Hidden")
  rootButton = newButton("Select Root")
  colorChoice = newComboBox(["Graphite", "Sky", "Mint", "Amber", "Rose"])
  commandStatus = newStatusLabel("")

controller.root = root
controller.status = status
controller.selection = selectedLabel
controller.details = details
controller.hierarchy = hierarchy
controller.commandStatus = commandStatus

root.identifier = "root"
root.background = initColor(0.94, 0.95, 0.97)
root.accessibilityRole = arGroup
root.accessibilityLabel = "Demo root"
canvas.background = initColor(0.99, 0.995, 1.0)
canvas.accessibilityRole = arGroup
canvas.accessibilityLabel = "Demo canvas"
inspectorRoot.background = initColor(0.94, 0.95, 0.97)
for label in [status, selectedLabel, details, hierarchy, commandStatus]:
  label.background = initColor(0.92, 0.98, 0.93, 1.0)
  label.accessibilityElement = true
details.background = initColor(0.99, 0.99, 1.0)
hierarchy.background = initColor(0.99, 0.99, 1.0)
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
hiddenButton.identifier = "inspector.hiddenButton"
rootButton.identifier = "inspector.rootButton"
colorChoice.identifier = "inspector.colorChoice"
colorChoice.selectedIndex = 0

let
  inspectAction = actionSelector("viewInspectorInspect")
  hiddenAction = actionSelector("viewInspectorToggleHidden")
  rootAction = actionSelector("viewInspectorSelectRoot")
  colorAction = actionSelector("viewInspectorSetColor")

runButton.target = newActionTarget(
  inspectAction,
  proc(sender: DynamicAgent) =
    controller.selectView(View(runButton)),
)
runButton.action = inspectAction
healthSlider.target = newActionTarget(
  inspectAction,
  proc(sender: DynamicAgent) =
    controller.selectView(View(healthSlider)),
)
healthSlider.action = inspectAction
liveSwitch.target = newActionTarget(
  inspectAction,
  proc(sender: DynamicAgent) =
    controller.selectView(View(liveSwitch)),
)
liveSwitch.action = inspectAction
hiddenButton.target = newActionTarget(
  hiddenAction,
  proc(sender: DynamicAgent) =
    let view = controller.selected
    if view.isNil:
      controller.commandStatus.text = "No selected view."
    elif view == root:
      controller.commandStatus.text = "Root stays visible."
    else:
      view.hidden = not view.hidden
      controller.updateInspector(),
)
hiddenButton.action = hiddenAction
rootButton.target = newActionTarget(
  rootAction,
  proc(sender: DynamicAgent) =
    controller.selectView(root),
)
rootButton.action = rootAction
colorChoice.target = newActionTarget(
  colorAction,
  proc(sender: DynamicAgent) =
    let view = controller.selected
    if view.isNil:
      controller.commandStatus.text = "No selected view."
    else:
      case colorChoice.selectedIndex
      of 1:
        view.background = initColor(0.82, 0.91, 0.99)
      of 2:
        view.background = initColor(0.82, 0.94, 0.87)
      of 3:
        view.background = initColor(1.0, 0.78, 0.48)
      of 4:
        view.background = initColor(0.96, 0.82, 0.90)
      else:
        view.background = initColor(0.86, 0.88, 0.91)
      controller.updateInspector(),
)
colorChoice.action = colorAction

root.addSubviews(
  autoNames(
    title, status, canvas, toolbar, sidebar, editor, preview, timeline, card,
    searchField, runButton, healthSlider, liveSwitch,
  )
)
inspectorRoot.addSubviews(
  autoNames(
    inspectorTitle, selectedLabel, detailsTitle, details, hierarchyTitle, hierarchy,
    commandsTitle, hiddenButton, rootButton, colorChoice, commandStatus,
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
  toolbar[atHeight] == 54.0
  sidebar[atTop] == toolbar[atBottom] + 18.0
  sidebar[atLeft] == toolbar[atLeft]
  sidebar[atWidth] == 176.0
  sidebar[atBottom] == canvas[atBottom] - 22.0
  editor[atTop] == sidebar[atTop]
  editor[atLeft] == sidebar[atRight] + 18.0
  editor[atRight] == canvas[atRight] - 22.0
  editor[atHeight] == 154.0
  preview[atTop] == editor[atBottom] + 18.0
  preview[atLeft] == editor[atLeft]
  preview[atRight] == card[atLeft] - 18.0
  preview[atBottom] == timeline[atTop] - 18.0
  card[atTop] == preview[atTop] + 10.0
  card[atRight] == editor[atRight] - 10.0
  card[atWidth] == 184.0
  card[atHeight] >= 132.0 | priority = LayoutPriorityHigh
  timeline[atLeft] == editor[atLeft]
  timeline[atRight] == editor[atRight]
  timeline[atBottom] == sidebar[atBottom]
  timeline[atHeight] == 92.0
  searchField[atTop] == toolbar[atTop] + 13.0
  searchField[atLeft] == toolbar[atLeft] + 260.0
  searchField[atWidth] == 220.0
  runButton[atTop] == searchField[atTop]
  runButton[atLeft] == searchField[atRight] + 12.0
  runButton[atWidth] == 82.0
  healthSlider[atLeft] == preview[atLeft] + 18.0
  healthSlider[atRight] == card[atLeft] - 36.0
  healthSlider[atBottom] == preview[atBottom] - 22.0
  liveSwitch[atRight] == preview[atRight] - 18.0
  liveSwitch[atBottom] == preview[atBottom] - 20.0

activateConstraints:
  inspectorTitle[atTop] == inspectorRoot[atTop] + 18.0
  inspectorTitle[atLeft] == inspectorRoot[atLeft] + 18.0
  inspectorTitle[atRight] == inspectorRoot[atRight] - 18.0
  inspectorTitle[atHeight] == 30.0
  selectedLabel[atTop] == inspectorTitle[atBottom] + 8.0
  selectedLabel[atLeft] == inspectorTitle[atLeft]
  selectedLabel[atRight] == inspectorTitle[atRight]
  selectedLabel[atHeight] == 24.0
  detailsTitle[atTop] == selectedLabel[atBottom] + 16.0
  detailsTitle[atLeft] == selectedLabel[atLeft]
  detailsTitle[atRight] == selectedLabel[atRight]
  detailsTitle[atHeight] == 24.0
  details[atTop] == detailsTitle[atBottom] + 6.0
  details[atLeft] == selectedLabel[atLeft]
  details[atRight] == selectedLabel[atRight]
  details[atHeight] == 174.0
  hierarchyTitle[atTop] == details[atBottom] + 14.0
  hierarchyTitle[atLeft] == selectedLabel[atLeft]
  hierarchyTitle[atRight] == selectedLabel[atRight]
  hierarchyTitle[atHeight] == 24.0
  hierarchy[atTop] == hierarchyTitle[atBottom] + 6.0
  hierarchy[atLeft] == selectedLabel[atLeft]
  hierarchy[atRight] == selectedLabel[atRight]
  hierarchy[atHeight] == 112.0
  commandsTitle[atTop] == hierarchy[atBottom] + 12.0
  commandsTitle[atLeft] == selectedLabel[atLeft]
  commandsTitle[atRight] == selectedLabel[atRight]
  commandsTitle[atHeight] == 22.0
  hiddenButton[atTop] == commandsTitle[atBottom] + 8.0
  hiddenButton[atLeft] == selectedLabel[atLeft]
  hiddenButton[atWidth] == 118.0
  rootButton[atTop] == hiddenButton[atTop]
  rootButton[atLeft] == hiddenButton[atRight] + 8.0
  rootButton[atWidth] == 104.0
  colorChoice[atTop] == hiddenButton[atTop]
  colorChoice[atLeft] == rootButton[atRight] + 8.0
  colorChoice[atRight] == selectedLabel[atRight]
  commandStatus[atTop] == hiddenButton[atBottom] + 10.0
  commandStatus[atLeft] == selectedLabel[atLeft]
  commandStatus[atRight] == selectedLabel[atRight]
  commandStatus[atHeight] == 24.0

controller.selectView(toolbar)

window.setContentView(root)
inspectorWindow.setContentView(inspectorRoot)
app.addWindow(window)
app.addWindow(inspectorWindow)

window.makeKeyAndOrderFront()
inspectorWindow.orderFront()
app.run()
