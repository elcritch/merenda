import merenda/nimkit

import sigils/selectors

type
  PaneController = ref object of ViewController
    title: string
    detail: string

  WorkspaceController = ref object of ViewController
    sidebar: PaneController
    editor: PaneController
    inspector: PaneController
    status: TextField

const ShowPanelAction = "viewControllerDemoShowPanel"

proc newPaneController(title, detail: string): PaneController

protocol PaneControllerLoading of ViewControllerLoading:
  method makeView(controller: PaneController): View =
    let
      box = newGroupBox(controller.title)
      stack = newStackView(laVertical)
    stack.spacing = 8.0
    stack.alignment = svaFill
    stack.addArrangedSubview(View(newHeadingLabel(controller.title)))
    stack.addArrangedSubview(View(newStatusLabel(controller.detail)))
    box.contentView = stack
    View(box)

protocol WorkspaceControllerLoading of ViewControllerLoading:
  method makeView(controller: WorkspaceController): View =
    let
      root = newView()
      contentGuide = root.contentLayoutGuide(insets(18.0))
      split = newSplitView(laHorizontal)
      detail = newSplitView(laVertical)
      bottomRow = newStackView(laHorizontal)
      showPanel = newButton("Panel Content")

    controller.addChildViewController(controller.sidebar)
    controller.addChildViewController(controller.editor)
    controller.addChildViewController(controller.inspector)

    showPanel.action = actionSelector(ShowPanelAction)
    showPanel.target = newActionTarget(showPanel.action) do(sender: DynamicAgent):
      discard sender
      let accessory = newPaneController(
        "Reusable Accessory", "This panel content comes from a ViewController."
      )
      let alert = newAlert(
        "ViewController Panel",
        "The accessory view is built lazily and then embedded in the panel.",
      )
      alert.setAccessoryView(accessory.view())
      discard sharedApplication().runModal(alert)
      accessory.teardown()
      controller.status.text = "Panel accessory controller was torn down"

    controller.status = newStatusLabel("Ready")
    controller.status.setHuggingPriority(LayoutPriorityLow, laHorizontal)
    showPanel.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
    bottomRow.spacing = 12.0
    bottomRow.addArrangedSubview(View(showPanel), View(controller.status))

    detail.addPane(controller.editor.view(), minSize = 180.0)
    detail.addPane(controller.inspector.view(), minSize = 120.0, collapsible = true)
    detail.setPositionOfDivider(0, 290.0)

    split.addPane(controller.sidebar.view(), minSize = 140.0, maxSize = 260.0)
    split.addPane(detail, minSize = 300.0)
    split.setPositionOfDivider(0, 180.0)

    root.addSubview(split)
    root.addSubview(bottomRow)
    split.pinEdges(toGuide = contentGuide, edges = {leLeft, leTop, leRight})
    activateConstraints:
      split[atBottom] == bottomRow[atTop] - 12.0
      bottomRow[atLeft] == contentGuide[atLeft]
      bottomRow[atRight] == contentGuide[atRight]
      bottomRow[atBottom] == contentGuide[atBottom]
      bottomRow[atHeight] == 28.0
    root

proc newPaneController(title, detail: string): PaneController =
  result = PaneController(title: title, detail: detail)
  result.initViewController()
  discard result.withProtocol(PaneControllerLoading)

proc newWorkspaceController(): WorkspaceController =
  result = WorkspaceController(
    sidebar: newPaneController("Sidebar", "Navigation and filters"),
    editor: newPaneController("Document", "Document-backed content controller"),
    inspector: newPaneController("Inspector", "Reusable child controller"),
  )
  result.initViewController()
  discard result.withProtocol(WorkspaceControllerLoading)

let
  app = sharedApplication()
  workspace = newWorkspaceController()
  windowController = newWindowController()

windowController.windowTitle = "NimKit ViewController Demo"
windowController.viewController = workspace
discard windowController.showWindow(app)
app.run()
