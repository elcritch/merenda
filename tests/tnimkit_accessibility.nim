import std/unittest

import sigils/core

import merenda/nimkit
import merenda/nimkit/containers/listviews

type AccessibilitySpy = ref object of Agent
  notifications: seq[AccessibilityNotification]

type AccessibilityTableSource = ref object of Responder

type AccessibilityTableDelegate = ref object of Responder

proc rememberAccessibilityNotification(
    spy: AccessibilitySpy, notification: AccessibilityNotification
) {.slot.} =
  spy.notifications.add notification

protocol AccessibilityTableSourceMethods of TableViewDataSource:
  method numberOfRows(source: AccessibilityTableSource, tableView: TableView): int =
    1

  method textForCell(
      source: AccessibilityTableSource,
      tableView: TableView,
      row: int,
      column: TableColumn,
  ): string =
    column.title() & " " & $row

protocol AccessibilityTableDelegateMethods of TableViewDelegate:
  method viewForCell(
      delegate: AccessibilityTableDelegate,
      tableView: TableView,
      row: int,
      column: TableColumn,
  ): View =
    newView()

proc newAccessibilityTableSource(): AccessibilityTableSource =
  result = AccessibilityTableSource()
  initResponder(result)
  discard result.withProtocol(AccessibilityTableSourceMethods)

proc newAccessibilityTableDelegate(): AccessibilityTableDelegate =
  result = AccessibilityTableDelegate()
  initResponder(result)
  discard result.withProtocol(AccessibilityTableDelegateMethods)

suite "nimkit accessibility":
  test "views expose explicit accessibility metadata and attributes":
    let view = newView(frame = initRect(10, 20, 80, 24))

    check not view.isAccessibilityElement()

    view.accessibilityRole = arGroup
    view.accessibilityLabel = "Container"
    view.accessibilityHelp = "Contains controls"
    view.accessibilityIdentifier = "main.container"

    check view.isAccessibilityElement()
    check view.accessibilityRole() == arGroup
    check view.accessibilityLabel() == "Container"
    check view.accessibilityHelp() == "Contains controls"
    check view.accessibilityIdentifier() == "main.container"

    let labelValue = view.accessibilityAttributeValue(AccessibilityAttributeLabel)
    check labelValue.kind == avString
    check labelValue.stringValue == "Container"

    let frameValue = view.accessibilityAttributeValue(AccessibilityAttributeFrame)
    check frameValue.kind == avRect
    check frameValue.rectValue == initRect(10, 20, 80, 24)

  test "accessibility children flatten non-element containers":
    let
      root = newView(frame = initRect(0, 0, 200, 120))
      group = newView(frame = initRect(10, 10, 180, 80))
      button = newButton("Apply", frame = initRect(4, 4, 80, 28))

    group.addSubview(button)
    root.addSubview(group)

    check root.accessibilityChildren() == @[View(button)]

    group.accessibilityLabel = "Group"
    check root.accessibilityChildren() == @[group]
    check group.accessibilityChildren() == @[View(button)]

  test "buttons provide role label value traits and press action":
    var actionCount = 0
    let
      button = newCheckBox("Enabled", frame = initRect(0, 0, 120, 24))
      action = actionSelector("accessibilityPress")

    proc onPress(sender: DynamicAgent) =
      check sender == DynamicAgent(button)
      inc actionCount

    button.target = newActionTarget(action, onPress)
    button.action = action

    check button.isAccessibilityElement()
    check button.accessibilityRole() == arCheckBox
    check button.accessibilityLabel() == "Enabled"
    check button.accessibilityValue() == "off"
    check button.accessibilityActionNames() == @[AccessibilityActionPress]

    check button.accessibilityPerformAction(AccessibilityActionPress)
    check button.accessibilityValue() == "on"
    check atSelected in button.accessibilityTraits()
    check actionCount == 1

  test "text fields and labels expose text semantics":
    let
      field = newTextField("abc", frame = initRect(0, 0, 120, 24))
      label = newHeadingLabel("Title")

    field.identifier = "name"

    check field.accessibilityRole() == arTextField
    check field.accessibilityLabel() == "name"
    check field.accessibilityValue() == "abc"
    check atEditable in field.accessibilityTraits()
    check atSelectable in field.accessibilityTraits()

    check label.accessibilityRole() == arStaticText
    check label.accessibilityLabel() == "Title"
    check label.accessibilityValue() == ""
    check atHeader in label.accessibilityTraits()

  test "accessibility value changes emit notifications":
    let
      view = newView()
      spy = AccessibilitySpy()

    view.connect(
      accessibilityNotificationPosted, spy, rememberAccessibilityNotification
    )

    view.accessibilityValue = "ready"
    check spy.notifications == @[anValueChanged]

  test "menus and popup controls expose accessibility semantics":
    let
      menu = newMenu("Actions")
      item = newMenuItem("Run")
      button = newPopupMenuButton("Actions", menu)

    discard menu.addItem(item)

    check menu.accessibilityRole() == arMenu
    check menu.accessibilityLabel() == "Actions"
    check item.accessibilityRole() == arMenuItem
    check item.accessibilityLabel() == "Run"
    check item.accessibilityActionNames() == @[AccessibilityActionPress]

    check button.accessibilityRole() == arPopupButton
    check button.accessibilityLabel() == "Actions"
    check button.accessibilityActionNames() == @[AccessibilityActionShowMenu]

  test "combo boxes popup lists and scroll areas expose roles and traits":
    let
      combo = newComboBox(["Low", "High"])
      popup = newPopupListView(
        PopupListData(
          itemCount: proc(): int =
            2,
          itemText: proc(index: int): string =
            if index == 0: "Low" else: "High",
        )
      )
      scroll = newScrollView(
        frame = initRect(0, 0, 120, 80),
        documentView = newView(frame = initRect(0, 0, 240, 160)),
      )

    combo.identifier = "priority"
    combo.selectedIndex = 1

    check combo.accessibilityRole() == arComboBox
    check combo.accessibilityLabel() == "priority"
    check combo.accessibilityValue() == "High"
    check atSelectable in combo.accessibilityTraits()
    check combo.accessibilityPerformAction(AccessibilityActionShowMenu)

    check popup.accessibilityRole() == arList
    check popup.accessibilityValue() == "2"
    check atSelectable in popup.accessibilityTraits()

    check scroll.accessibilityRole() == arScrollArea
    check scroll.accessibilityValue() == "0.0,0.0"

  test "tabs lists tables and hosted table cells expose collection semantics":
    let
      tabView = newTabView(frame = initRect(0, 0, 200, 120))
      listView = newListView(["One", "Two"], frame = initRect(0, 0, 120, 60))
      tableView = newTableView(frame = initRect(0, 0, 160, 80))
      source = newAccessibilityTableSource()
      delegate = newAccessibilityTableDelegate()

    discard tabView.addTabViewItem(newTabViewItem("General", newView()))
    discard tabView.addTabViewItem(newTabViewItem("Advanced", newView()))
    discard tabView.selectTabViewItemAtIndex(1)

    listView.selectedIndex = 1

    tableView.addColumn(newTableColumn("name", "Name", width = 120.0))
    tableView.dataSource = source
    tableView.delegate = delegate
    discard buildRenders(tableView)

    check tabView.accessibilityRole() == arTabGroup
    check tabView.accessibilityValue() == "Advanced"
    check atSelectable in tabView.accessibilityTraits()

    check listView.accessibilityRole() == arList
    check listView.accessibilityValue() == "2"
    check atSelectable in listView.accessibilityTraits()

    var foundSelectedRow = false
    for (index, rowView, rect) in listView.visibleRowViews():
      if index == 1:
        check rowView.accessibilityRole() == arListItem
        check rowView.accessibilityLabel() == "Two"
        check atSelected in rowView.accessibilityTraits()
        foundSelectedRow = true
    check foundSelectedRow

    check tableView.accessibilityRole() == arTable
    check tableView.accessibilityValue() == "1"

    var foundCell = false
    for (index, rowView, rect) in tableView.visibleRowViews():
      if index == 0 and rowView.subviews().len > 0:
        let cell = rowView.subviews()[0]
        check cell.accessibilityRole() == arCell
        check cell.accessibilityLabel() == "Name 0"
        check atSelectable in cell.accessibilityTraits()
        foundCell = true
    check foundCell
