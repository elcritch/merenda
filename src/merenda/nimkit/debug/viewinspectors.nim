import std/[math, strutils]

import sigils/selectors

import ../accessibility/accessibility
import ../app/application
import ../app/windows
import ../controls/buttons
import ../controls/comboboxes
import ../controls/controls
import ../controls/sliders
import ../controls/switchbuttons
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../containers/scrollviews
import ../containers/stackviews
import ./selectionrings
import ./viewselection
import ../text/textfields
import ../view/views

type
  ViewInspector* = ref object of View
    xRoot: View
    xSelected: View
    xSelectionRing: SelectionRing
    xSelectionRingStyle: SelectionRingStyle
    xShowsSelectionRing: bool
    xViewSelection: ViewSelection
    xSelectsViewsOnMouseDown: bool
    xTitle: Label
    xSelection: Label
    xDetailsTitle: Label
    xDetails: Label
    xHierarchyTitle: Label
    xHierarchy: Label
    xCommandsTitle: Label
    xHiddenButton: Button
    xRootButton: Button
    xColorChoice: ComboBox
    xCommandStatus: Label

  ViewInspectorPanel* = object
    window*: Window
    inspector*: ViewInspector

proc detach*(inspector: ViewInspector)

protocol ViewInspectorWindowLifecycleSlots of WindowLifecycleEvents:
  proc willClose(inspector: ViewInspector) {.slot.} =
    inspector.detach()

proc px(value: float32): string =
  $int(round(value))

proc rectSummary(rect: Rect): string =
  "x " & rect.origin.x.px & "  y " & rect.origin.y.px & "  w " & rect.size.width.px &
    "  h " & rect.size.height.px

proc colorSummary(color: Color): string =
  "rgba(" & $int(round(color.r * 255.0'f32)) & ", " & $int(round(color.g * 255.0'f32)) &
    ", " & $int(round(color.b * 255.0'f32)) & ", " & $int(round(color.a * 100.0'f32)) &
    "%)"

proc inspectedKind(view: View): string =
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
  else:
    "View"

proc inspectedDisplayName(view: View): string =
  if view.isNil:
    return "none"
  if view.identifier.len > 0:
    return view.identifier
  view.inspectedKind

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
  lines.add repeat("  ", depth) & prefix & view.inspectedDisplayName & "  " &
    view.inspectedKind
  for child in view.subviews:
    lines.addTreeLines(child, selected, depth + 1)

proc hierarchySummary(root, selected: View): string =
  var lines: seq[string]
  lines.addTreeLines(root, selected, 0)
  lines.join("\n")

proc refresh*(inspector: ViewInspector)
proc selectView*(inspector: ViewInspector, view: View)

proc updateViewSelection(inspector: ViewInspector) =
  discard inspector.xViewSelection.uninstall()
  if inspector.xRoot.isNil or not inspector.xSelectsViewsOnMouseDown:
    return

  let
    inspectorRef = inspector.unsafeWeakRef()
    handler: ViewSelectionHandler = proc(view: View, event: MouseEvent) =
      discard event
      if not inspectorRef.isNil:
        inspectorRef[].selectView(view)
    removalHandler: ViewSelectionRemovalHandler = proc(view: View) =
      if not inspectorRef.isNil and view.containsView(inspectorRef[].xSelected):
        inspectorRef[].selectView(nil)

  inspector.xViewSelection =
    installViewSelection(inspector.xRoot, handler, removalHandler = removalHandler)

proc updateSelectionRing(inspector: ViewInspector, view: View) =
  discard inspector.xSelectionRing.uninstall()
  inspector.xSelected = view
  if inspector.xShowsSelectionRing and not view.isNil:
    inspector.xSelectionRing = installSelectionRing(view, inspector.xSelectionRingStyle)

proc inspectedRoot*(inspector: ViewInspector): View =
  if inspector.isNil: nil else: inspector.xRoot

proc `inspectedRoot=`*(inspector: ViewInspector, root: View) =
  if inspector.isNil:
    return
  inspector.xRoot = root
  inspector.updateViewSelection()
  if not inspector.xSelected.isNil and
      (root.isNil or not root.containsView(inspector.xSelected)):
    inspector.updateSelectionRing(nil)
  inspector.refresh()

proc selectedView*(inspector: ViewInspector): View =
  if inspector.isNil: nil else: inspector.xSelected

proc selectView*(inspector: ViewInspector, view: View) =
  if inspector.isNil:
    return
  inspector.updateSelectionRing(view)
  inspector.refresh()

proc detach*(inspector: ViewInspector) =
  if inspector.isNil:
    return
  discard inspector.xViewSelection.uninstall()
  discard inspector.xSelectionRing.uninstall()
  inspector.xRoot = nil
  inspector.xSelected = nil
  inspector.refresh()

proc selectionRingStyle*(inspector: ViewInspector): SelectionRingStyle =
  if inspector.isNil:
    initSelectionRingStyle()
  else:
    inspector.xSelectionRingStyle

proc `selectionRingStyle=`*(inspector: ViewInspector, style: SelectionRingStyle) =
  if inspector.isNil:
    return
  inspector.xSelectionRingStyle = style
  inspector.updateSelectionRing(inspector.xSelected)

proc showsSelectionRing*(inspector: ViewInspector): bool =
  not inspector.isNil and inspector.xShowsSelectionRing

proc `showsSelectionRing=`*(inspector: ViewInspector, value: bool) =
  if inspector.isNil or inspector.xShowsSelectionRing == value:
    return
  inspector.xShowsSelectionRing = value
  inspector.updateSelectionRing(inspector.xSelected)

proc selectsViewsOnMouseDown*(inspector: ViewInspector): bool =
  not inspector.isNil and inspector.xSelectsViewsOnMouseDown

proc `selectsViewsOnMouseDown=`*(inspector: ViewInspector, value: bool) =
  if inspector.isNil or inspector.xSelectsViewsOnMouseDown == value:
    return
  inspector.xSelectsViewsOnMouseDown = value
  inspector.updateViewSelection()

proc refresh*(inspector: ViewInspector) =
  if inspector.isNil:
    return

  let view = inspector.xSelected
  if view.isNil:
    inspector.xSelection.text = "No selection"
    inspector.xDetails.text = ""
    inspector.xHierarchy.text = inspector.xRoot.hierarchySummary(nil)
    inspector.xCommandStatus.text = "Select a view to inspect."
    return

  let
    frame = view.frame
    bounds = view.bounds
    accessibilityLabel = view.accessibilityLabel()
    accessibilityIdentifier = view.accessibilityIdentifier()
    hiddenText = if view.hidden: "hidden" else: "visible"
    touchCount = inspector.xRoot.touchingConstraintCount(view)

  inspector.xSelection.text = view.inspectedDisplayName & "  /  " & view.inspectedKind
  inspector.xDetails.text =
    "identifier: " & view.identifier & "\n" & "kind: " & view.inspectedKind & "\n" &
    "frame: " & frame.rectSummary & "\n" & "bounds: " & bounds.rectSummary & "\n" &
    "background: " & view.backgroundColor.colorSummary & "\n" & "state: " & hiddenText &
    "\n" & "children: " & $view.subviews.len & "\n" & "constraints here: " &
    $view.constraints.len & "\n" & "constraints touching: " & $touchCount & "\n" &
    "accessibility role: " & $view.accessibilityRole() & "\n" & "accessibility label: " &
    accessibilityLabel & "\n" & "accessibility id: " & accessibilityIdentifier
  inspector.xHierarchy.text = inspector.xRoot.hierarchySummary(view)
  inspector.xCommandStatus.text = "Inspector synced."

proc setSelectedBackground(inspector: ViewInspector, color: Color) =
  let view = inspector.selectedView()
  if view.isNil:
    inspector.xCommandStatus.text = "No selected view."
    return
  view.background = color
  inspector.refresh()

proc configureInspectorActions(inspector: ViewInspector) =
  let
    hiddenAction = actionSelector("viewInspectorToggleHidden")
    rootAction = actionSelector("viewInspectorSelectRoot")
    colorAction = actionSelector("viewInspectorSetColor")

  inspector.xHiddenButton.target = newActionTarget(
    hiddenAction,
    proc(sender: DynamicAgent) =
      let view = inspector.selectedView()
      if view.isNil:
        inspector.xCommandStatus.text = "No selected view."
      elif view == inspector.inspectedRoot():
        inspector.xCommandStatus.text = "Root stays visible."
      else:
        view.hidden = not view.hidden
        inspector.refresh(),
  )
  inspector.xHiddenButton.action = hiddenAction

  inspector.xRootButton.target = newActionTarget(
    rootAction,
    proc(sender: DynamicAgent) =
      inspector.selectView(inspector.inspectedRoot()),
  )
  inspector.xRootButton.action = rootAction

  inspector.xColorChoice.target = newActionTarget(
    colorAction,
    proc(sender: DynamicAgent) =
      case inspector.xColorChoice.selectedIndex
      of 1:
        inspector.setSelectedBackground(color(0.82, 0.91, 0.99))
      of 2:
        inspector.setSelectedBackground(color(0.82, 0.94, 0.87))
      of 3:
        inspector.setSelectedBackground(color(1.0, 0.78, 0.48))
      of 4:
        inspector.setSelectedBackground(color(0.96, 0.82, 0.90))
      else:
        inspector.setSelectedBackground(color(0.86, 0.88, 0.91)),
  )
  inspector.xColorChoice.action = colorAction

proc configureInspectorStyle(inspector: ViewInspector) =
  inspector.background = color(0.94, 0.95, 0.97)
  for label in [inspector.xSelection, inspector.xCommandStatus]:
    label.background = color(0.92, 0.98, 0.93, 1.0)
    label.accessibilityElement = true
  inspector.xDetails.background = color(0.99, 0.99, 1.0)
  inspector.xHierarchy.background = color(0.99, 0.99, 1.0)

proc newViewInspector*(root: View = nil, frame: Rect = AutoRect): ViewInspector =
  result = ViewInspector()
  initViewFields(result, frame)
  result.xSelectionRingStyle = initSelectionRingStyle()
  result.xShowsSelectionRing = true
  result.xSelectsViewsOnMouseDown = true
  result.identifier = "viewInspector"
  result.accessibilityRole = arGroup
  result.accessibilityLabel = "View inspector"

  result.xTitle = newTitleLabel("Inspector")
  result.xSelection = newStatusLabel("")
  result.xDetailsTitle = newHeadingLabel("Selection")
  result.xDetails = newStatusLabel("")
  result.xHierarchyTitle = newHeadingLabel("Hierarchy")
  result.xHierarchy = newStatusLabel("")
  result.xCommandsTitle = newHeadingLabel("Commands")
  result.xHiddenButton = newButton("Toggle Hidden")
  result.xRootButton = newButton("Select Root")
  result.xColorChoice = newComboBox(["Graphite", "Sky", "Mint", "Amber", "Rose"])
  result.xCommandStatus = newStatusLabel("")
  result.xColorChoice.selectedIndex = 0

  result.addSubviews(
    autoNames(
      result.xTitle, result.xSelection, result.xDetailsTitle, result.xDetails,
      result.xHierarchyTitle, result.xHierarchy, result.xCommandsTitle,
      result.xHiddenButton, result.xRootButton, result.xColorChoice,
      result.xCommandStatus,
    )
  )

  activateConstraints:
    result.xTitle[atTop] == result[atTop] + 18.0
    result.xTitle[atLeft] == result[atLeft] + 18.0
    result.xTitle[atRight] == result[atRight] - 18.0
    result.xTitle[atHeight] == 30.0
    result.xSelection[atTop] == result.xTitle[atBottom] + 8.0
    result.xSelection[atLeft] == result.xTitle[atLeft]
    result.xSelection[atRight] == result.xTitle[atRight]
    result.xSelection[atHeight] == 24.0
    result.xDetailsTitle[atTop] == result.xSelection[atBottom] + 16.0
    result.xDetailsTitle[atLeft] == result.xSelection[atLeft]
    result.xDetailsTitle[atRight] == result.xSelection[atRight]
    result.xDetailsTitle[atHeight] == 24.0
    result.xDetails[atTop] == result.xDetailsTitle[atBottom] + 6.0
    result.xDetails[atLeft] == result.xSelection[atLeft]
    result.xDetails[atRight] == result.xSelection[atRight]
    result.xDetails[atHeight] == 174.0
    result.xHierarchyTitle[atTop] == result.xDetails[atBottom] + 14.0
    result.xHierarchyTitle[atLeft] == result.xSelection[atLeft]
    result.xHierarchyTitle[atRight] == result.xSelection[atRight]
    result.xHierarchyTitle[atHeight] == 24.0
    result.xHierarchy[atTop] == result.xHierarchyTitle[atBottom] + 6.0
    result.xHierarchy[atLeft] == result.xSelection[atLeft]
    result.xHierarchy[atRight] == result.xSelection[atRight]
    result.xHierarchy[atHeight] == 112.0
    result.xCommandsTitle[atTop] == result.xHierarchy[atBottom] + 12.0
    result.xCommandsTitle[atLeft] == result.xSelection[atLeft]
    result.xCommandsTitle[atRight] == result.xSelection[atRight]
    result.xCommandsTitle[atHeight] == 22.0
    result.xHiddenButton[atTop] == result.xCommandsTitle[atBottom] + 8.0
    result.xHiddenButton[atLeft] == result.xSelection[atLeft]
    result.xHiddenButton[atWidth] == 118.0
    result.xRootButton[atTop] == result.xHiddenButton[atTop]
    result.xRootButton[atLeft] == result.xHiddenButton[atRight] + 8.0
    result.xRootButton[atWidth] == 104.0
    result.xColorChoice[atTop] == result.xHiddenButton[atTop]
    result.xColorChoice[atLeft] == result.xRootButton[atRight] + 8.0
    result.xColorChoice[atRight] == result.xSelection[atRight]
    result.xCommandStatus[atTop] == result.xHiddenButton[atBottom] + 10.0
    result.xCommandStatus[atLeft] == result.xSelection[atLeft]
    result.xCommandStatus[atRight] == result.xSelection[atRight]
    result.xCommandStatus[atHeight] == 24.0

  result.configureInspectorStyle()
  result.configureInspectorActions()
  result.inspectedRoot = root

proc newViewInspectorPanel*(
    inspector: ViewInspector,
    title = "Inspector",
    frame: Rect = rect(1010.0, 140.0, 360.0, 580.0),
): ViewInspectorPanel =
  result.inspector =
    if inspector.isNil:
      newViewInspector()
    else:
      inspector
  result.window = newPanel(title, frame)
  result.window.setContentView(result.inspector)
  result.inspector.observeProtocol(result.window, ViewInspectorWindowLifecycleSlots)

proc newViewInspectorPanel*(
    root: View = nil,
    title = "Inspector",
    frame: Rect = rect(1010.0, 140.0, 360.0, 580.0),
): ViewInspectorPanel =
  result.inspector = newViewInspector(root)
  result.window = newPanel(title, frame)
  result.window.setContentView(result.inspector)
  result.inspector.observeProtocol(result.window, ViewInspectorWindowLifecycleSlots)

proc showViewInspector*(
    inspector: ViewInspector,
    app: Application = sharedApplication(),
    title = "Inspector",
    frame: Rect = rect(1010.0, 140.0, 360.0, 580.0),
): ViewInspectorPanel =
  result = newViewInspectorPanel(inspector, title, frame)
  if not app.isNil:
    app.addWindow(result.window)
  result.window.orderFront()

proc showViewInspector*(
    root: View,
    app: Application = sharedApplication(),
    title = "Inspector",
    frame: Rect = rect(1010.0, 140.0, 360.0, 580.0),
): ViewInspectorPanel =
  result = newViewInspectorPanel(root, title, frame)
  if not app.isNil:
    app.addWindow(result.window)
  result.window.orderFront()
