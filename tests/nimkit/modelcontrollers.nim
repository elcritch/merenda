import std/[options, unittest]

import merenda/nimkit

proc personItems(): seq[ModelItem] =
  @[
    initModelItem(
      "ada",
      objectValue = toObjectValue("Ada"),
      fields = [
        initModelField("name", toObjectValue("Ada")),
        initModelField("score", toObjectValue(31)),
        initModelField("active", toObjectValue(true)),
      ],
    ),
    initModelItem(
      "grace",
      objectValue = toObjectValue("Grace"),
      fields = [
        initModelField("name", toObjectValue("Grace")),
        initModelField("score", toObjectValue(45)),
        initModelField("active", toObjectValue(true)),
      ],
    ),
    initModelItem(
      "alan",
      objectValue = toObjectValue("Alan"),
      fields = [
        initModelField("name", toObjectValue("Alan")),
        initModelField("score", toObjectValue(27)),
        initModelField("active", toObjectValue(false)),
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

    controller.setValue("ada", "score", toObjectValue(32))
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
          initModelTreeItem(initModelItem("root", objectValue = toObjectValue("Root"))),
          initModelTreeItem(
            initModelItem("child", objectValue = toObjectValue("Child")),
            parentIdentifier = "root",
            leaf = true,
          ),
        ]
      )
      outlineView = newOutlineView()
      cascadingView = newCascadingView()

    check controller.childCount() == 1
    check controller.childIdentifierAt("", 0) == "root"
    check controller.childIdentifiers("root") == @["child"]
    check not controller.isLeaf("root")
    check controller.isLeaf("child")

    bindOutlineView(outlineView, controller)
    check outlineView.outlineItemWithIdentifier("root").title == "Root"
    check outlineView.childIdentifiersForItem("") == @["root"]

    bindCascadingView(cascadingView, controller)
    let rootChildren = cascadingView.childrenForParent("root")
    check rootChildren.len == 1
    check rootChildren[0].identifier == "child"
    check rootChildren[0].title == "Child"

  test "array controller syncs choice style controls":
    let
      controller = newArrayController(
        [
          initModelItem("one", objectValue = toObjectValue("One")),
          initModelItem(
            "two", objectValue = toObjectValue("Two"), title = "Second", enabled = false
          ),
          initModelItem("separator", separator = true),
        ]
      )
      comboBox = newComboBox()
      menu = newMenu("Choices")
      tabs = newDocumentTabs()
      matrix = newButtonMatrix([], columns = 2)

    bindComboBox(comboBox, controller)
    check comboBox.numberOfItems == 3
    check comboBox.itemAtIndex(0) == "One"
    check comboBox.itemObjectValueAtIndex(1).requireString() == "Two"

    syncMenu(menu, controller)
    check menu.len == 3
    check menu[0.Natural].title == "One"
    check menu[1.Natural].title == "Second"
    check not menu[1.Natural].enabled
    check menu[2.Natural].isSeparatorItem()

    syncDocumentTabs(tabs, controller)
    check tabs.len == 2
    check tabs[0.Natural].identifier == "one"
    check tabs[1.Natural].title == "Second"
    check not tabs[1.Natural].enabled

    syncMatrix(matrix, controller, columns = 2)
    check matrix.len == 4
    check matrix.cellAtIndex(0).title == "One"
    check matrix.cellAtIndex(1).title == "Second"
    check not Cell(matrix.cellAtIndex(1)).isEnabled()
    check matrix.cellAtIndex(2).title == ""
