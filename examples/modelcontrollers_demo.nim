import merenda/nimkit

let
  app = sharedApplication()
  window = newWindow("NimKit Model Controllers", frame = initRect(120, 120, 820, 620))
  root = newView(frame = initRect(0, 0, 820, 620))

proc field(key: string, value: ObjectValue): ModelField =
  initModelField(key, value)

let
  title = newTitleLabel("Model Controllers", frame = initRect(24, 20, 360, 28))
  tableHeading =
    newHeadingLabel("Array-backed table", frame = initRect(24, 58, 240, 22))
  treeHeading =
    newHeadingLabel("Tree-backed browser", frame = initRect(420, 58, 240, 22))
  tabsHeading = newHeadingLabel("Document tabs", frame = initRect(24, 282, 240, 22))
  choicesHeading =
    newHeadingLabel("Choice controls", frame = initRect(24, 374, 240, 22))
  status = newStatusLabel(
    "Tables, browsers, tabs, menus, combos, and matrices share ModelItem values.",
    frame = initRect(390, 22, 390, 22),
  )

let
  buildController = newArrayController(
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
  tableView = newTableView(frame = initRect(24, 86, 360, 170))

bindTableView(tableView, buildController)

let
  treeController = newTreeController(
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
  browser = newCascadingView(frame = initRect(420, 86, 360, 170))

bindCascadingView(browser, treeController)

let
  tabController = newArrayController(
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
  tabs = newDocumentTabs(frame = initRect(24, 312, 756, 34))

syncDocumentTabs(tabs, tabController)
discard tabs.selectDocumentTabAtIndex(0)

let
  choiceController = newArrayController(
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
  comboBox = newComboBox(frame = initRect(24, 404, 180, 26))
  menu = newMenu("Priority")
  popup = newPopupMenuButton("Priority", menu, frame = initRect(224, 404, 150, 26))
  matrix = newButtonMatrix([], columns = 3, frame = initRect(404, 398, 310, 62))

bindComboBox(comboBox, choiceController)
comboBox.selectedIndex = 1
syncMenu(menu, choiceController)
syncMatrix(matrix, choiceController, columns = 3)

root.addSubview(title)
root.addSubview(status)
root.addSubview(tableHeading)
root.addSubview(treeHeading)
root.addSubview(tabsHeading)
root.addSubview(choicesHeading)
root.addSubview(tableView)
root.addSubview(browser)
root.addSubview(tabs)
root.addSubview(comboBox)
root.addSubview(popup)
root.addSubview(matrix)

window.setContentView(root)
discard window.selectNextKeyView()
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
