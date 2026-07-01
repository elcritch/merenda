import merenda/nimkit

import sigils/selectors

type ModelControllersDemo* = ref object
  app*: Application
  window*: Window
  root*: View
  status*: Label
  buildController*: ArrayController
  tableView*: TableView
  treeController*: TreeController
  browser*: CascadingView
  tabController*: ArrayController
  tabs*: DocumentTabs
  choiceController*: ArrayController
  comboBox*: ComboBox
  menu*: Menu
  popup*: PopupMenuButton
  matrix*: Matrix

proc field(key: string, value: ObjectValue): ModelField =
  initModelField(key, value)

proc updateStatus*(demo: ModelControllersDemo, message: string) =
  if not demo.isNil and not demo.status.isNil:
    demo.status.text = message

proc choiceTitle(demo: ModelControllersDemo, sender: DynamicAgent): string =
  if sender == DynamicAgent(demo.comboBox):
    return demo.comboBox.stringValue()
  if sender == DynamicAgent(demo.matrix):
    let cell = demo.matrix.cellAtIndex(demo.matrix.leadIndex())
    if not cell.isNil:
      return cell.title()
  if sender == DynamicAgent(demo.popup):
    let index = demo.popup.highlightedIndex()
    if index >= 0 and index < demo.menu.len:
      return demo.menu[index.Natural].title()
  if not sender.isNil and sender of MenuItem:
    return MenuItem(sender).title()
  ""

proc configureChoiceActions(demo: ModelControllersDemo) =
  let action = actionSelector("modelControllerChoiceChanged")
  let target = newActionTarget(action) do(sender: DynamicAgent):
    let title = demo.choiceTitle(sender)
    if title.len > 0:
      demo.updateStatus("Choice: " & title)
  demo.comboBox.target = target
  demo.comboBox.action = action
  demo.matrix.target = target
  demo.matrix.action = action
  for item in demo.menu.items():
    if not item.isSeparatorItem():
      item.target = target
      item.action = action

proc newBuildController(): ArrayController =
  newArrayController(
    [
      initModelItem(
        "renderer",
        objectValue = toObjectValue("Renderer"),
        fields = [
          field("project", toObjectValue("Renderer")),
          field("state", toObjectValue("Running")),
          field("owner", toObjectValue("Mara")),
        ],
      ),
      initModelItem(
        "sync",
        objectValue = toObjectValue("Sync Engine"),
        fields = [
          field("project", toObjectValue("Sync Engine")),
          field("state", toObjectValue("Queued")),
          field("owner", toObjectValue("Ren")),
        ],
      ),
      initModelItem(
        "docs",
        objectValue = toObjectValue("Documentation"),
        fields = [
          field("project", toObjectValue("Documentation")),
          field("state", toObjectValue("Done")),
          field("owner", toObjectValue("Iris")),
        ],
      ),
    ],
    [
      initModelColumn("project", "Project", "project", 170.0),
      initModelColumn("state", "State", "state", 92.0),
      initModelColumn("owner", "Owner", "owner", 82.0),
    ],
  )

proc newTreeControllerForDemo(): TreeController =
  newTreeController(
    [
      initModelTreeItem(initModelItem("apps", objectValue = toObjectValue("Apps"))),
      initModelTreeItem(
        initModelItem("framework", objectValue = toObjectValue("Framework"))
      ),
      initModelTreeItem(
        initModelItem("workspace", objectValue = toObjectValue("Workspace")),
        parentIdentifier = "apps",
        leaf = true,
      ),
      initModelTreeItem(
        initModelItem("preferences", objectValue = toObjectValue("Preferences")),
        parentIdentifier = "apps",
        leaf = true,
      ),
      initModelTreeItem(
        initModelItem("tables", objectValue = toObjectValue("Tables")),
        parentIdentifier = "framework",
        leaf = true,
      ),
      initModelTreeItem(
        initModelItem("text", objectValue = toObjectValue("Text")),
        parentIdentifier = "framework",
        leaf = true,
      ),
    ]
  )

proc newTabController(): ArrayController =
  newArrayController(
    [
      initModelItem("plan", title = "Project Plan", objectValue = toObjectValue("Plan")),
      initModelItem(
        "budget", title = "Budget.xlsx", objectValue = toObjectValue("Budget")
      ),
      initModelItem(
        "notes", title = "Research Notes", objectValue = toObjectValue("Notes")
      ),
    ]
  )

proc newChoiceController(): ArrayController =
  newArrayController(
    [
      initModelItem("low", objectValue = toObjectValue("Low")),
      initModelItem("medium", objectValue = toObjectValue("Medium")),
      initModelItem("high", objectValue = toObjectValue("High")),
      initModelItem("separator", separator = true),
      initModelItem(
        "custom", title = "Custom...", objectValue = toObjectValue("Custom")
      ),
    ]
  )

proc newModelControllersDemo*(app = newApplication()): ModelControllersDemo =
  result = ModelControllersDemo(app: app)
  result.window =
    newWindow("NimKit Model Controllers", frame = initRect(120, 120, 820, 620))
  result.root = newView(frame = initRect(0, 0, 820, 620))
  result.status = newStatusLabel(
    "Tables, browsers, tabs, menus, combos, and matrices share ModelItem values.",
    frame = initRect(390, 22, 390, 22),
  )
  result.buildController = newBuildController()
  result.tableView = newTableView(frame = initRect(24, 86, 360, 170))
  result.treeController = newTreeControllerForDemo()
  result.browser = newCascadingView(frame = initRect(420, 86, 360, 170))
  result.tabController = newTabController()
  result.tabs = newDocumentTabs(frame = initRect(24, 312, 756, 34))
  result.choiceController = newChoiceController()
  result.comboBox = newComboBox(frame = initRect(24, 404, 180, 26))
  result.menu = newMenu("Priority")
  result.popup =
    newPopupMenuButton("Priority", result.menu, frame = initRect(224, 404, 150, 26))
  result.matrix = newButtonMatrix([], columns = 3, frame = initRect(404, 398, 310, 62))

  bindTableView(result.tableView, result.buildController)
  bindCascadingView(result.browser, result.treeController)
  syncDocumentTabs(result.tabs, result.tabController)
  discard result.tabs.selectDocumentTabAtIndex(0)
  bindComboBox(result.comboBox, result.choiceController)
  result.comboBox.selectedIndex = 1
  syncMenu(result.menu, result.choiceController)
  syncMatrix(result.matrix, result.choiceController, columns = 3)
  result.configureChoiceActions()

  result.root.addSubview(
    newTitleLabel("Model Controllers", frame = initRect(24, 20, 360, 28))
  )
  result.root.addSubview(result.status)
  result.root.addSubview(
    newHeadingLabel("Array-backed table", frame = initRect(24, 58, 240, 22))
  )
  result.root.addSubview(
    newHeadingLabel("Tree-backed browser", frame = initRect(420, 58, 240, 22))
  )
  result.root.addSubview(
    newHeadingLabel("Document tabs", frame = initRect(24, 282, 240, 22))
  )
  result.root.addSubview(
    newHeadingLabel("Choice controls", frame = initRect(24, 374, 240, 22))
  )
  result.root.addSubview(result.tableView)
  result.root.addSubview(result.browser)
  result.root.addSubview(result.tabs)
  result.root.addSubview(result.comboBox)
  result.root.addSubview(result.popup)
  result.root.addSubview(result.matrix)

  result.window.setContentView(result.root)
  discard result.window.selectNextKeyView()

proc showModelControllersDemo*(demo: ModelControllersDemo) =
  if demo.isNil:
    return
  demo.app.addWindow(demo.window)
  demo.window.makeKeyAndOrderFront()

when isMainModule:
  let demo = newModelControllersDemo(sharedApplication())
  demo.showModelControllersDemo()
  demo.app.run()
