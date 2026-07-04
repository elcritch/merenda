import std/unittest

import sigils/core

import merenda/nimkit

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
    2

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
    let view = newView(frame = rect(10, 20, 80, 24))

    check not view.isAccessibilityElement()

    view.name = "main.container"
    check view.accessibilityLabel() == "main.container"
    check view.accessibilityIdentifier() == "main.container"

    view.accessibilityRole = arGroup
    view.accessibilityLabel = "Container"
    view.accessibilityHelp = "Contains controls"
    view.accessibilityIdentifier = "main.container.explicit"

    check view.isAccessibilityElement()
    check view.accessibilityRole() == arGroup
    check view.accessibilityLabel() == "Container"
    check view.accessibilityHelp() == "Contains controls"
    check view.accessibilityIdentifier() == "main.container.explicit"

    let labelValue = view.accessibilityAttributeValue(AccessibilityAttributeLabel)
    check labelValue.kind == avString
    check labelValue.stringValue == "Container"

    let frameValue = view.accessibilityAttributeValue(AccessibilityAttributeFrame)
    check frameValue.kind == avRect
    check frameValue.rectValue == rect(10, 20, 80, 24)

  test "accessibility children flatten non-element containers":
    let
      root = newView(frame = rect(0, 0, 200, 120))
      group = newView(frame = rect(10, 10, 180, 80))
      button = newButton("Apply", frame = rect(4, 4, 80, 28))

    group.addSubview(button)
    root.addSubview(group)

    check root.accessibilityChildren() == @[View(button)]

    group.accessibilityLabel = "Group"
    check root.accessibilityChildren() == @[group]
    check group.accessibilityChildren() == @[View(button)]

  test "accessibility traversal orders descendants and hit-tests semantic elements":
    let
      root = newView(frame = rect(0, 0, 240, 160))
      group = newView(frame = rect(10, 10, 120, 80))
      button = newButton("Apply", frame = rect(4, 4, 80, 28))
      checkbox = newCheckBox("Include", frame = rect(150, 12, 80, 24))

    group.addSubview(button)
    root.addSubview(group)
    root.addSubview(checkbox)

    check root.orderedAccessibilityDescendants() == @[View(button), View(checkbox)]

    group.accessibilityLabel = "Group"
    check root.orderedAccessibilityDescendants() ==
      @[group, View(button), View(checkbox)]

    var iterated: seq[View]
    for element in root.accessibilityDescendants():
      iterated.add element
    check iterated == @[group, View(button), View(checkbox)]

    check root.accessibilityElementAtPoint(initPoint(16, 16)) == View(button)
    check root.accessibilityElementAtPoint(initPoint(112, 72)) == group
    check root.accessibilityElementAtPoint(initPoint(154, 16)) == View(checkbox)
    check root.accessibilityElementAtPoint(initPoint(230, 150)).isNil

  test "accessibility validation helpers cover roles actions and trees":
    let
      root = newView(frame = rect(0, 0, 160, 80))
      button = newButton("Run", frame = rect(10, 10, 80, 28))

    button.identifier = "run"
    root.addSubview(button)

    check button.accessibilityHasRole(arButton)
    check button.accessibilityHasRole([arButton, arCheckBox])
    check button.accessibilitySupportsAction(AccessibilityActionPress)
    check button.validateAccessibilityElement().passed()
    check button.validateAccessibilityRole(arButton).passed()
    check button.validateAccessibilityActions([AccessibilityActionPress]).passed()
    check root.validateAccessibilityTree().passed()

    let wrongRole = button.validateAccessibilityRole(arCheckBox)
    check not wrongRole.passed()
    check wrongRole.errors.len == 1

    let missingAction =
      button.validateAccessibilityActions([AccessibilityActionIncrement])
    check not missingAction.passed()
    check missingAction.errors.len == 1

  test "buttons provide role label value traits and press action":
    var actionCount = 0
    let
      button = newCheckBox("Enabled", frame = rect(0, 0, 120, 24))
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
      field = newTextField("abc", frame = rect(0, 0, 120, 24))
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

  test "text accessibility exposes ranges insertion points and geometry":
    let
      field = newTextField("abcdef", frame = rect(0, 0, 180, 28))
      textView = newTextView("one\ntwo", frame = rect(0, 40, 220, 90))
      monoText = newMonoTextEditor("ab\ncd", frame = rect(0, 150, 220, 90))

    field.selectedRange = initTextRange(1, 2)
    check field.accessibilityTextLength() == 6
    check field.accessibilitySelectedTextRange() == initAccessibilityTextRange(1, 2)
    check field.accessibilityInsertionPoint() == 3
    check atEditable in field.accessibilityTraits()
    check atSelectable in field.accessibilityTraits()

    let fieldRange =
      field.accessibilityAttributeValue(AccessibilityAttributeSelectedTextRange)
    check fieldRange.kind == avTextRange
    check fieldRange.textRangeValue == initAccessibilityTextRange(1, 2)

    check field.accessibilitySetAttributeValue(
      AccessibilityAttributeSelectedTextRange,
      initAccessibilityValue(initAccessibilityTextRange(0, 1)),
    )
    check field.selectedRange == initTextRange(0, 1)
    check field.accessibilitySetAttributeValue(
      AccessibilityAttributeInsertionPoint, initAccessibilityValue(2)
    )
    check field.accessibilityInsertionPoint() == 2

    let fieldCharRect = field.accessibilityBoundsForCharacter(1)
    check not fieldCharRect.isEmpty
    check field.accessibilityBoundsForTextRange(initAccessibilityTextRange(0, 2)).len > 0
    check field.accessibilityCharacterIndexAtPoint(
      initPoint(fieldCharRect.origin.x + 0.5'f32, fieldCharRect.origin.y + 0.5'f32)
    ) >= 0

    textView.selectedRange = initTextRange(2, 3)
    check textView.accessibilityTextLength() == 7
    check textView.accessibilitySelectedTextRange() == initAccessibilityTextRange(2, 3)
    check textView.accessibilityLineRange(1) == initAccessibilityTextRange(4, 3)
    check textView.accessibilityLineForCharacter(5) == 1
    check not textView.accessibilityBoundsForCharacter(1).isEmpty
    check not textView.accessibilityBoundsForLine(1).isEmpty

    monoText.setCursorPosition(1, 1)
    check monoText.accessibilityTextLength() == 5
    check monoText.accessibilitySelectedTextRange() == initAccessibilityTextRange(4, 0)
    check monoText.accessibilityInsertionPoint() == 4
    check monoText.accessibilityLineRange(1) == initAccessibilityTextRange(3, 2)
    check monoText.accessibilityLineForCharacter(4) == 1
    check atEditable in monoText.accessibilityTraits()
    check atSelectable in monoText.accessibilityTraits()
    let monoCharRect = monoText.accessibilityBoundsForCharacter(4)
    check not monoCharRect.isEmpty
    check monoText.accessibilityCharacterIndexAtPoint(
      initPoint(monoCharRect.origin.x + 0.5'f32, monoCharRect.origin.y + 0.5'f32)
    ) == 4

  test "accessibility value changes emit notifications":
    let
      view = newView()
      spy = AccessibilitySpy()

    view.connect(
      accessibilityNotificationPosted, spy, rememberAccessibilityNotification
    )

    view.accessibilityValue = "ready"
    check spy.notifications == @[anValueChanged]

  test "focus changes post after responder state changes":
    let
      window = newWindow("Focus Accessibility", frame = rect(0, 0, 160, 100))
      root = newView(frame = rect(0, 0, 160, 100))
      button = newButton("Focus", frame = rect(10, 10, 80, 28))
      spy = AccessibilitySpy()

    root.addSubview(button)
    window.setContentView(root)
    button.connect(
      accessibilityNotificationPosted, spy, rememberAccessibilityNotification
    )

    check window.makeFirstResponder(button)
    check button.focused()
    check spy.notifications == @[anFocusedUIElementChanged]

    check window.makeFirstResponder(button)
    discard buildRenders(root)
    check spy.notifications == @[anFocusedUIElementChanged]

  test "enabled mutations update attributes without notification":
    let
      button = newButton("Run")
      spy = AccessibilitySpy()

    button.connect(
      accessibilityNotificationPosted, spy, rememberAccessibilityNotification
    )

    let enabledBefore =
      button.accessibilityAttributeValue(AccessibilityAttributeEnabled)
    check enabledBefore.kind == avBool
    check enabledBefore.boolValue

    button.enabled = false

    let enabledAfter = button.accessibilityAttributeValue(AccessibilityAttributeEnabled)
    check enabledAfter.kind == avBool
    check not enabledAfter.boolValue
    discard buildRenders(button)
    check spy.notifications == newSeq[AccessibilityNotification]()

  test "selection model mutations post accessibility notifications":
    let
      tableView = newTableView()
      tabView = newTabView()
      comboBox = newComboBox(["Low", "High"])
      tableSpy = AccessibilitySpy()
      tabSpy = AccessibilitySpy()
      comboSpy = AccessibilitySpy()

    tableView.selectionMode = tsmSingle
    tableView.rowCount = 3
    tableView.connect(
      accessibilityNotificationPosted, tableSpy, rememberAccessibilityNotification
    )
    tableView.selectedIndex = 1
    tableView.selectedIndex = 1
    discard buildRenders(tableView)
    check tableSpy.notifications == @[anSelectionChanged]
    check tableView.selectedIndex == 1

    discard tabView.addTabViewItem(newTabViewItem("General", newView()))
    discard tabView.addTabViewItem(newTabViewItem("Advanced", newView()))
    tabView.connect(
      accessibilityNotificationPosted, tabSpy, rememberAccessibilityNotification
    )
    discard tabView.selectTabViewItemAtIndex(1)
    discard tabView.selectTabViewItemAtIndex(1)
    discard buildRenders(tabView)
    check tabSpy.notifications == @[anSelectionChanged]
    check tabView.accessibilityValue() == "Advanced"

    comboBox.connect(
      accessibilityNotificationPosted, comboSpy, rememberAccessibilityNotification
    )
    comboBox.selectedIndex = 1
    comboBox.selectedIndex = 1
    comboBox.selectedIndex = -1
    check comboSpy.notifications == @[anSelectionChanged, anSelectionChanged]
    check comboBox.selectedIndex == -1

  test "text selection mutations post accessibility notifications":
    let
      field = newTextField("abc")
      textView = newTextView("abc")
      monoText = newMonoTextEditor("abc")
      fieldSpy = AccessibilitySpy()
      textViewSpy = AccessibilitySpy()
      monoTextSpy = AccessibilitySpy()

    field.connect(
      accessibilityNotificationPosted, fieldSpy, rememberAccessibilityNotification
    )
    textView.connect(
      accessibilityNotificationPosted, textViewSpy, rememberAccessibilityNotification
    )
    monoText.connect(
      accessibilityNotificationPosted, monoTextSpy, rememberAccessibilityNotification
    )

    field.selectedRange = initTextRange(1, 1)
    field.selectedRange = initTextRange(1, 1)
    textView.selectedRange = initTextRange(1, 1)
    textView.selectedRange = initTextRange(1, 1)
    monoText.setCursorPosition(0, 1)
    monoText.setCursorPosition(0, 1)

    check fieldSpy.notifications == @[anSelectionChanged]
    check textViewSpy.notifications == @[anSelectionChanged]
    check monoTextSpy.notifications == @[anSelectionChanged]

  test "expanded and collapsed mutations post accessibility notifications":
    let
      outlineView = newOutlineView()
      splitView = newSplitView(laHorizontal, rect(0, 0, 200, 80))
      leftPane = newView()
      rightPane = newView()
      outlineSpy = AccessibilitySpy()
      splitSpy = AccessibilitySpy()

    outlineView.outlineItems = [
      initOutlineItem("project", "Project", expandable = true),
      initOutlineItem("src", "src", parentIdentifier = "project"),
    ]
    outlineView.connect(
      accessibilityNotificationPosted, outlineSpy, rememberAccessibilityNotification
    )
    outlineView.expandItem("project")
    outlineView.expandItem("project")
    outlineView.collapseItem("project")
    discard buildRenders(outlineView)
    check outlineSpy.notifications == @[anExpandedChanged, anExpandedChanged]

    splitView.addPane(leftPane, collapsible = true)
    splitView.addPane(rightPane)
    splitView.connect(
      accessibilityNotificationPosted, splitSpy, rememberAccessibilityNotification
    )
    splitView.setPaneCollapsed(0, true)
    splitView.setPaneCollapsed(0, true)
    splitView.setPaneCollapsed(0, false)
    discard buildRenders(splitView)
    check splitSpy.notifications == @[anExpandedChanged, anExpandedChanged]

  test "text value setters post accessibility value notifications":
    let
      field = newTextField("A")
      textView = newTextView("A")
      monoText = newMonoTextEditor("A")
      fieldSpy = AccessibilitySpy()
      textViewSpy = AccessibilitySpy()
      monoTextSpy = AccessibilitySpy()

    field.connect(
      accessibilityNotificationPosted, fieldSpy, rememberAccessibilityNotification
    )
    textView.connect(
      accessibilityNotificationPosted, textViewSpy, rememberAccessibilityNotification
    )
    monoText.connect(
      accessibilityNotificationPosted, monoTextSpy, rememberAccessibilityNotification
    )

    field.text = "B"
    field.text = "B"
    textView.stringValue = "B"
    textView.stringValue = "B"
    monoText.stringValue = "B"
    monoText.stringValue = "B"

    check fieldSpy.notifications == @[anValueChanged]
    check textViewSpy.notifications == @[anValueChanged]
    check monoTextSpy.notifications == @[anValueChanged]

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
        frame = rect(0, 0, 120, 80),
        documentView = newView(frame = rect(0, 0, 240, 160)),
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

  test "tabs tables and hosted table cells expose collection semantics":
    let
      tabView = newTabView(frame = rect(0, 0, 200, 120))
      tableListView = newTableView(frame = rect(0, 0, 120, 60))
      tableView = newTableView(frame = rect(0, 0, 160, 80))
      source = newAccessibilityTableSource()
      delegate = newAccessibilityTableDelegate()

    discard tabView.addTabViewItem(newTabViewItem("General", newView()))
    discard tabView.addTabViewItem(newTabViewItem("Advanced", newView()))
    discard tabView.selectTabViewItemAtIndex(1)

    tableListView.rowCount = 2
    tableListView.addColumn(newTableColumn("name", "Name", width = 120.0))
    tableListView.dataSource = source
    tableListView.delegate = delegate
    tableListView.showsHeader = false
    tableListView.selectedIndex = 1

    tableView.addColumn(newTableColumn("name", "Name", width = 120.0))
    tableView.dataSource = source
    tableView.delegate = delegate
    discard buildRenders(tableView)

    check tabView.accessibilityRole() == arTabGroup
    check tabView.accessibilityValue() == "Advanced"
    check atSelectable in tabView.accessibilityTraits()

    check tableListView.accessibilityRole() == arTable
    check tableListView.accessibilityValue() == "2"
    check atSelectable in tableListView.accessibilityTraits()

    var foundSelectedRow = false
    for (index, rowView, rect) in tableListView.visibleRowViews():
      if index == 1:
        check rowView.accessibilityRole() == arListItem
        check rowView.accessibilityLabel() == "Name 1"
        check atSelected in rowView.accessibilityTraits()
        foundSelectedRow = true
    check foundSelectedRow

    check tableView.accessibilityRole() == arTable
    check tableView.accessibilityValue() == "2"

    var foundCell = false
    for (index, rowView, rect) in tableView.visibleRowViews():
      if index == 0 and rowView.subviews().len > 0:
        let cell = rowView.subviews()[0]
        check cell.accessibilityRole() == arCell
        check cell.accessibilityLabel() == "Name 0"
        check atSelectable in cell.accessibilityTraits()
        foundCell = true
    check foundCell
