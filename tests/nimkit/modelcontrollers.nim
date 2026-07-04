import std/[options, unittest]

import merenda/nimkit

import ../../examples/modelcontrollers_demo

func center(rect: Rect): Point =
  initPoint(
    rect.origin.x + rect.size.width / 2.0'f32,
    rect.origin.y + rect.size.height / 2.0'f32,
  )

func keyForChar(ch: char): Key =
  let normalized =
    if ch in 'A' .. 'Z':
      char(ch.ord - 'A'.ord + 'a'.ord)
    else:
      ch
  if normalized in 'a' .. 'z':
    Key(keyA.ord + normalized.ord - 'a'.ord)
  else:
    keyUnknown

proc typeText(window: Window, text: string): bool =
  for ch in text:
    let key = keyForChar(ch)
    if not window.dispatchKeyDown(KeyEvent(text: $ch, key: key, keyCode: key.ord)):
      return false
  true

proc clickTableHeader(window: Window, tableView: TableView, column: TableColumn): bool =
  let rect = tableView.tableHeaderColumnRect(column)
  if rect.isEmpty:
    return false
  window.clickAt(tableView.pointToWindow(rect.center()))

proc tableCellPoint(tableView: TableView, row: int, column: TableColumn): Point =
  let
    rowRect = tableView.rowItemRect(row)
    columnRect = tableView.tableColumnRect(column)
  tableView.pointToWindow(
    initPoint(
      columnRect.origin.x + columnRect.size.width / 2.0'f32,
      rowRect.origin.y + rowRect.size.height / 2.0'f32,
    )
  )

proc clickTableCell(
    window: Window, tableView: TableView, row: int, column: TableColumn
): bool =
  window.clickAt(tableView.tableCellPoint(row, column))

proc doubleClickTableCell(
    window: Window, tableView: TableView, row: int, column: TableColumn
): bool =
  let point = tableView.tableCellPoint(row, column)
  window.mouseDownAt(point, clickCount = 2) and window.mouseUpAt(point, clickCount = 2)

proc clickDocumentTab(window: Window, tabs: DocumentTabs, index: int): bool =
  let rect = tabs.documentTabRect(index)
  if rect.isEmpty:
    return false
  window.clickAt(tabs.pointToWindow(rect.center()))

proc clickComboItem(window: Window, comboBox: ComboBox, index: int): bool =
  discard window.buildRenders()
  if not window.clickAt(comboBox.pointToWindow(comboBox.bounds().center())):
    return false
  if not comboBox.popupOpen():
    return false
  let itemRect = comboBox.popupItemRect(comboBox.bounds(), index)
  window.clickAt(comboBox.pointToWindow(itemRect.center()))

proc popupListIn(root: View): PopupListView =
  for child in root.subviews():
    if child of PopupListView:
      return PopupListView(child)

proc clickPopupMenuItem(
    window: Window, root: View, button: PopupMenuButton, index: int
): bool =
  discard window.buildRenders()
  if not window.clickAt(button.pointToWindow(button.bounds().center())):
    return false
  if not button.popupOpen():
    return false
  let popupList = root.popupListIn()
  if popupList.isNil:
    return false
  let itemRect = popupList.popupListItemRect(popupList.bounds(), index)
  window.clickAt(popupList.pointToWindow(itemRect.center()))

proc clickMatrixCell(window: Window, matrix: Matrix, index: int): bool =
  let rect = matrix.cellFrameAtIndex(index)
  if rect.isEmpty:
    return false
  window.clickAt(matrix.pointToWindow(rect.center()))

proc personItems(): seq[ModelItem] =
  @[
    initModelItem(
      "ada",
      objectValue = toObj("Ada"),
      fields = [
        initModelField("name", toObj("Ada")),
        initModelField("score", toObj(31)),
        initModelField("active", toObj(true)),
      ],
    ),
    initModelItem(
      "grace",
      objectValue = toObj("Grace"),
      fields = [
        initModelField("name", toObj("Grace")),
        initModelField("score", toObj(45)),
        initModelField("active", toObj(true)),
      ],
    ),
    initModelItem(
      "alan",
      objectValue = toObj("Alan"),
      fields = [
        initModelField("name", toObj("Alan")),
        initModelField("score", toObj(27)),
        initModelField("active", toObj(false)),
      ],
    ),
  ]

proc personColumns(): seq[ModelColumn] =
  @[
    initModelColumn("person", "Person", "name", 120.0),
    initModelColumn("rank", "Score", "score", 64.0),
  ]

suite "nimkit model controllers":
  test "selection controller normalizes by mode":
    let selection = newSelectionController(mselMultiple)

    selection.selectIdentifier("ada")
    selection.selectIdentifier("grace")
    check selection.selectedIdentifiers == @["ada", "grace"]
    check selection.anchorIdentifier == "ada"
    check selection.leadIdentifier == "grace"

    selection.toggleIdentifier("ada")
    check selection.selectedIdentifiers == @["grace"]

    selection.mode = mselSingle
    selection.setSelectedIdentifiers(["ada", "grace"])
    check selection.selectedIdentifiers == @["ada"]

    selection.mode = mselNone
    selection.selectIdentifier("grace")
    check selection.selectedIdentifiers == newSeq[string]()

  test "array controller sorts filters and exposes required lookups":
    let controller = newArrayController(personItems(), personColumns())

    check controller.sourceLen == 3
    check controller.len == 3
    check controller.itemWithIdentifier("ada").value("name").requireString() == "Ada"
    check controller.getItemWithIdentifier("missing").isNone

    controller.sortDescriptors = [initModelSortDescriptor("score", msdDescending)]
    check controller.itemAt(0).identifier == "grace"
    check controller.itemAt(2).identifier == "alan"

    controller.filter = proc(item: ModelItem): bool =
      item.value("active").requireBool()
    check controller.len == 2
    check controller.indexOfIdentifier("grace") == 0
    check controller.indexOfIdentifier("alan") == -1

    controller.setValue("ada", "score", toObj(32))
    check controller.valueForItem("ada", "score").requireInt() == 32

  test "array controller binds table object values and typed editing":
    let
      controller = newArrayController(personItems(), personColumns())
      tableView = newTableView()

    bindTableView(tableView, controller)
    let scoreColumn = tableView.columnWithIdentifier("rank")

    check tableView.columnCount == 2
    check tableView.rowCount == 3
    check tableView.tableCellObjectValue(0, scoreColumn).requireInt() == 31
    check tableView.tableCellText(1, tableView.columnWithIdentifier("person")) == "Grace"

    check tableView.beginEditingCell(0, scoreColumn)
    check tableView.commitEditingCell("32")
    check controller.valueForItem("ada", "score").requireInt() == 32

    check tableView.beginEditingCell(0, scoreColumn)
    check not tableView.commitEditingCell("not an int")
    check tableView.editingState.active
    check tableView.editingValidationError.len > 0
    check controller.valueForItem("ada", "score").requireInt() == 32

  test "tree controller backs outline and cascading data sources":
    let
      controller = newTreeController(
        [
          initModelTreeItem(initModelItem("root", objectValue = toObj("Root"))),
          initModelTreeItem(
            initModelItem("child", objectValue = toObj("Child")),
            parentIdentifier = "root",
            leaf = true,
          ),
        ]
      )
      outlineView = newOutlineView()
      statusColumn = newTableColumn("status", "Status", width = 80.0)
      cascadingView = newCascadingView()

    check controller.childCount() == 1
    check controller.childIdentifierAt("", 0) == "root"
    check controller.childIdentifiers("root") == @["child"]
    check not controller.isLeaf("root")
    check controller.isLeaf("child")

    outlineView.addColumn(statusColumn)
    controller.selectionController().selectIdentifier("root")
    bindOutlineView(outlineView, controller)
    check outlineView.outlineItemWithIdentifier("root").title == "Root"
    check outlineView.outlineItemWithIdentifier("root").objectValue.requireString() ==
      "Root"
    check outlineView.childIdentifiersForItem("") == @["root"]
    check outlineView.selectedItemIdentifier() == "root"

    outlineView.expandItem("root")
    outlineView.selectedItemIdentifier = "child"
    check controller.selectionController().selectedIdentifier == "child"

    controller.addItem(
      initModelTreeItem(
        initModelItem(
          "second",
          objectValue = toObj("Second"),
          fields = [initModelField("status", toObj("ready"))],
        ),
        parentIdentifier = "root",
        leaf = true,
      )
    )
    check outlineView.childIdentifiersForItem("root") == @["child", "second"]
    check outlineView.rowForItem("second") >= 0
    check outlineView
    .tableCellObjectValue(outlineView.rowForItem("second"), statusColumn)
    .requireString() == "ready"

    bindCascadingView(cascadingView, controller)
    let rootChildren = cascadingView.childrenForParent("root")
    check rootChildren.len == 2
    check rootChildren[0].identifier == "child"
    check rootChildren[0].title == "Child"

  test "array controller syncs choice style controls":
    let
      controller = newArrayController(
        [
          initModelItem("one", objectValue = toObj("One")),
          initModelItem(
            "two",
            objectValue = toObj("Two"),
            title = "Second",
            fields = [
              initModelField("modified", toObj(true)),
              initModelField("closeable", toObj(false)),
              initModelField("tooltip", toObj("Second tab")),
              initModelField("tabStyle", toObj("compact")),
            ],
            enabled = false,
          ),
          initModelItem("separator", separator = true),
        ]
      )
      comboBox = newComboBox()
      menu = newMenu("Choices")
      boundMenu = newMenu("Bound Choices")
      window = newWindow("Bound popup", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      popup = newPopupMenuButton("Bound", boundMenu, initRect(8, 8, 90, 24))
      tabs = newDocumentTabs()
      boundTabs = newDocumentTabs()
      matrix = newButtonMatrix([], columns = 2)
      boundMatrix = newRadioMatrix([], columns = 2)

    bindComboBox(comboBox, controller)
    check comboBox.numberOfItems == 3
    check comboBox.itemAtIndex(0) == "One"
    check comboBox.itemObjectValueAtIndex(1).requireString() == "Two"
    check comboBox.optionIdentifierAtIndex(0) == "one"
    check comboBox.optionIdentifierAtIndex(1) == "two"
    check not comboBox.optionIsEnabledAtIndex(1)
    check comboBox.optionIsSeparatorAtIndex(2)

    comboBox.activateItemAtIndex(0)
    check comboBox.selectedOptionIdentifier() == "one"
    check controller.selectionController().selectedIdentifier == "one"

    syncMenu(menu, controller)
    check menu.len == 3
    check menu[0.Natural].title == "One"
    check menu[0.Natural].identifier == "one"
    check menu[0.Natural].objectValue.requireString() == "One"
    check menu[1.Natural].title == "Second"
    check menu[1.Natural].identifier == "two"
    check not menu[1.Natural].enabled
    check menu[2.Natural].isSeparatorItem()
    check menu.itemModels[1].identifier == "two"
    check menu.indexOfMenuItemIdentifier("two") == 1

    bindMenu(boundMenu, controller)
    check boundMenu.len == 3
    check boundMenu[0.Natural].identifier == "one"
    controller.addItem(initModelItem("three", objectValue = toObj("Three")))
    boundMenu.reloadData()
    check boundMenu.len == 4
    check boundMenu[3.Natural].identifier == "three"
    bindPopupMenuButton(popup, controller)
    popup.popupPresentation = ppInline
    root.addSubview(popup)
    window.setContentView(root)
    check window.clickPopupMenuItem(root, popup, 3)
    check controller.selectionController().selectedIdentifier == "three"

    syncDocumentTabs(tabs, controller)
    check tabs.len == 3
    check tabs.documentTabModels.len == 4
    check tabs[0.Natural].identifier == "one"
    check tabs[1.Natural].title == "Second"
    check tabs[2.Natural].identifier == "three"
    check tabs[1.Natural].modified
    check not tabs[1.Natural].closeable
    check tabs[1.Natural].toolTip == "Second tab"
    check tabs[1.Natural].style == dtsCompact
    check not tabs[1.Natural].enabled
    check tabs.documentTabModels[2].hidden

    bindDocumentTabs(boundTabs, controller)
    check boundTabs.len == 3
    check boundTabs[2.Natural].identifier == "three"
    check boundTabs.selectDocumentTabWithIdentifier("three")
    check controller.selectionController().selectedIdentifier == "three"

    syncMatrix(matrix, controller, columns = 2)
    check matrix.len == 4
    check matrix.cellAtIndex(0).title == "One"
    check matrix.cellAtIndex(1).title == "Second"
    check not Cell(matrix.cellAtIndex(1)).isEnabled()
    check matrix.cellAtIndex(2).title == ""
    check matrix.matrixItemModels.len == 4
    check matrix.matrixItemModels[1].identifier == "two"
    check matrix.matrixItemModels[2].identifier == "separator"
    check not matrix.matrixItemModels[2].enabled
    check matrix.indexOfMatrixItemIdentifier("three") == 3

    bindMatrix(boundMatrix, controller, columns = 2)
    check boundMatrix.len == 4
    check boundMatrix.selectedItemIdentifier() == "three"
    check boundMatrix.indexOfMatrixItemIdentifier("three") == 3
    check boundMatrix.selectCellAtIndex(0)
    check controller.selectionController().selectedIdentifier == "one"

suite "nimkit model controller demo":
  test "table sorting selection and editing work through user events":
    let
      demo = newModelControllersDemo()
      project = demo.tableView.columnWithIdentifier("project")
      owner = demo.tableView.columnWithIdentifier("owner")

    discard demo.window.buildRenders()
    check demo.tableView.tableCellText(0, project) == "Renderer"

    check demo.window.clickTableHeader(demo.tableView, project)
    check project.sortDirection == tsdAscending
    check demo.buildController.sortDescriptors ==
      [initModelSortDescriptor("project", msdAscending)]
    check demo.tableView.tableCellText(0, project) == "Documentation"

    check demo.window.clickTableHeader(demo.tableView, project)
    check project.sortDirection == tsdDescending
    check demo.buildController.sortDescriptors ==
      [initModelSortDescriptor("project", msdDescending)]
    check demo.tableView.tableCellText(0, project) == "Sync Engine"

    check demo.window.clickTableCell(demo.tableView, 0, project)
    check demo.buildController.selectionController().selectedIdentifier == "sync"

    check demo.window.doubleClickTableCell(demo.tableView, 0, owner)
    check demo.window.firstResponder() == demo.window.fieldEditor()
    check demo.window.typeText("Nia")
    check demo.window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check demo.buildController.valueForItem("sync", "owner").requireString() == "Nia"
    check demo.tableView.tableCellText(0, owner) == "Nia"

  test "browser tabs choices popup menu and matrix work through user events":
    let demo = newModelControllersDemo()

    discard demo.window.buildRenders()
    let firstColumn = demo.browser.tableViewForColumn(0)
    check demo.window.clickTableCell(firstColumn, 0, firstColumn.columnAt(0))
    check demo.browser.selectedPath() == @["apps"]

    discard demo.window.buildRenders()
    let secondColumn = demo.browser.tableViewForColumn(1)
    check demo.window.clickTableCell(secondColumn, 1, secondColumn.columnAt(0))
    check demo.browser.selectedPath() == @["apps", "preferences"]

    check demo.window.clickDocumentTab(demo.tabs, 1)
    check demo.tabs.selectedDocumentTabItem().identifier == "budget"

    check demo.window.clickComboItem(demo.comboBox, 2)
    check demo.comboBox.stringValue == "High"
    check demo.comboBox.objectValue.requireString() == "High"
    check demo.status.text == "Choice: High"

    check demo.window.clickPopupMenuItem(demo.root, demo.popup, 4)
    check not demo.popup.popupOpen()
    check demo.status.text == "Choice: Custom..."

    check demo.window.clickMatrixCell(demo.matrix, 2)
    check demo.matrix.leadIndex == 2
    check demo.status.text == "Choice: High"
