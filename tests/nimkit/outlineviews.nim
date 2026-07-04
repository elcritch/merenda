import std/[unicode, unittest]

import figdraw/fignodes
import sigils/core

import merenda/nimkit

type OutlineSourceSpy = ref object of Responder
  items: seq[OutlineItem]

type OutlineDelegateSpy = ref object of Responder
  deniedExpand: seq[string]
  expanded: seq[string]
  collapsed: seq[string]

proc containsValue(values: openArray[string], value: string): bool =
  for item in values:
    if item == value:
      return true
  false

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add rune

proc countRenderedText(view: View, text: string): int =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return 0
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkText and node.renderedText() == text:
      inc result

func rectsClose(left, right: Rect): bool =
  abs(left.origin.x - right.origin.x) <= 0.01'f32 and
    abs(left.origin.y - right.origin.y) <= 0.01'f32 and
    abs(left.size.width - right.size.width) <= 0.01'f32 and
    abs(left.size.height - right.size.height) <= 0.01'f32

proc renderedRect(node: Fig): Rect =
  rect(
    node.screenBox.x.float32, node.screenBox.y.float32, node.screenBox.w.float32,
    node.screenBox.h.float32,
  )

protocol OutlineSourceSpyMethods of OutlineViewDataSource:
  method numberOfChildren(
      source: OutlineSourceSpy, outlineView: OutlineView, parentIdentifier: string
  ): int =
    for item in source.items:
      if item.parentIdentifier == parentIdentifier:
        inc result

  method childIdentifier(
      source: OutlineSourceSpy,
      outlineView: OutlineView,
      parentIdentifier: string,
      index: int,
  ): string =
    var current = 0
    for item in source.items:
      if item.parentIdentifier == parentIdentifier:
        if current == index:
          return item.identifier
        inc current

  method outlineItem(
      source: OutlineSourceSpy, outlineView: OutlineView, identifier: string
  ): OutlineItem =
    for item in source.items:
      if item.identifier == identifier:
        return item

protocol OutlineDelegateSpyMethods of OutlineViewDelegate:
  method shouldExpandItem(
      delegate: OutlineDelegateSpy, outlineView: OutlineView, identifier: string
  ): bool =
    not delegate.deniedExpand.containsValue(identifier)

  method didExpandItem(
      delegate: OutlineDelegateSpy, outlineView: OutlineView, identifier: string
  ) =
    delegate.expanded.add identifier

  method didCollapseItem(
      delegate: OutlineDelegateSpy, outlineView: OutlineView, identifier: string
  ) =
    delegate.collapsed.add identifier

proc newOutlineSourceSpy(items: openArray[OutlineItem]): OutlineSourceSpy =
  result = OutlineSourceSpy(items: @items)
  initResponder(result)
  discard result.withProtocol(OutlineSourceSpyMethods)

proc newOutlineDelegateSpy(): OutlineDelegateSpy =
  result = OutlineDelegateSpy()
  initResponder(result)
  discard result.withProtocol(OutlineDelegateSpyMethods)

suite "NimKit OutlineView":
  test "outline view flattens expandable items into table rows":
    let outlineView = newOutlineView()

    outlineView.outlineItems = [
      initOutlineItem("project", "Project", expandable = true),
      initOutlineItem("src", "src", parentIdentifier = "project", expandable = true),
      initOutlineItem("main", "main.nim", parentIdentifier = "src"),
      initOutlineItem("tests", "tests", parentIdentifier = "project"),
      initOutlineItem("notes", "Notes"),
    ]

    check outlineView.rowCount == 2
    check outlineView.visibleOutlineItems()[0].identifier == "project"
    check outlineView.visibleOutlineItems()[1].identifier == "notes"
    check outlineView.rowForItem("main") == -1

    outlineView.expandItem("project")
    check outlineView.rowCount == 4
    check outlineView.itemAtRow(1).identifier == "src"
    check outlineView.levelForRow(1) == 1
    check outlineView.rowForItem("tests") == 2

    outlineView.expandItem("src")
    check outlineView.rowCount == 5
    check outlineView.itemAtRow(2).identifier == "main"
    check outlineView.levelForRow(2) == 2
    check outlineView.tableCellText(0, outlineView.outlineColumn()) == "Project"
    check outlineView.tableCellText(2, outlineView.outlineColumn()) == "main.nim"
    check outlineView.outlineItemIdentity("src").level == 1
    check outlineView.childIdentifiersForItem("project") == @["src", "tests"]

    outlineView.collapseItem("project")
    check outlineView.rowCount == 2
    check outlineView.isItemExpanded("src")
    check outlineView.rowForItem("main") == -1

  test "left and right arrow keys expand and collapse selected outline rows":
    let outlineView = newOutlineView()

    outlineView.outlineItems = [
      initOutlineItem("root", "Root", expandable = true),
      initOutlineItem("child", "Child", parentIdentifier = "root"),
    ]
    outlineView.selectedIndex = 0

    check outlineView.keyDown(KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord))
    check outlineView.isItemExpanded("root")
    check outlineView.rowCount == 2

    check outlineView.keyDown(KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord))
    check not outlineView.isItemExpanded("root")
    check outlineView.rowCount == 1

  test "outline view renders the table view theme surface":
    let
      outlineView = newOutlineView(frame = rect(0, 0, 180, 72))
      surfaceFill = fill(color(0.18, 0.08, 0.28, 1.0))
      borderColor = color(0.82, 0.36, 0.92, 1.0)

    outlineView.styleClasses = @["project-outline"]

    var theme = initTheme()
    theme[initStyleSelector(srTableView, classes = @["project-outline"]), StyleFill] =
      surfaceFill

    theme[
      initStyleSelector(srTableView, classes = @["project-outline"]), StyleBorderColor
    ] = borderColor

    theme[
      initStyleSelector(srTableView, classes = @["project-outline"]), StyleBorderWidth
    ] = 2.0'f32

    theme[
      initStyleSelector(srTableView, classes = @["project-outline"]), StyleCornerRadius
    ] = 5.0'f32

    let renders = buildRenders(outlineView, initAppearance(theme))
    check DefaultDrawLevel in renders

    var surfaceFound = false
    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill == surfaceFill and
          node.renderedRect().rectsClose(outlineView.bounds()):
        surfaceFound = true
        check node.stroke.weight == 2.0'f32
        check node.stroke.fill.kind == flColor
        check node.stroke.fill.color == borderColor.rgba
        check node.corners[dcTopLeft] == 5'u16

    check surfaceFound

  test "outline column can be replaced and remains a table column":
    let
      outlineView = newOutlineView()
      customColumn = newTableColumn("name", "Name", width = 180.0)

    outlineView.outlineColumn = customColumn
    check outlineView.outlineColumn == customColumn
    check customColumn.tableView == TableView(outlineView)
    check outlineView.columnWithIdentifier("name") == customColumn

  test "outline items expose model values metadata identity and mutation":
    let
      outlineView = newOutlineView()
      statusColumn = newTableColumn("status", "Status", width = 90.0)
      represented = newResponder()

    outlineView.addColumn(statusColumn)
    outlineView.outlineItems = [
      initOutlineItem(
        "root",
        "Root",
        expandable = true,
        objectValue = toObj("root-value"),
        cells = [tableCell("status", toObj("open"))],
        representedObject = DynamicAgent(represented),
      ),
      initOutlineItem("hidden", "Hidden", parentIdentifier = "root", hidden = true),
      initOutlineItem(
        "disabled", "Disabled", parentIdentifier = "root", enabled = false
      ),
      initOutlineItem(
        "child",
        "Child",
        parentIdentifier = "root",
        cells = [tableCell("status", toObj(2))],
      ),
    ]

    check outlineView.rowCount == 1
    check outlineView.objectValueForItem("root").requireString() == "root-value"
    check outlineView.valueForItem("root", "status").requireString() == "open"
    check outlineView.representedObjectForItem("root") == DynamicAgent(represented)
    check outlineView.outlineItemIdentifiers() ==
      @["root", "hidden", "disabled", "child"]

    outlineView.expandItem("root")
    check outlineView.childIdentifiersForItem("root") == @["disabled", "child"]
    check outlineView.rowCount == 3
    check outlineView.tableRowIdentifier(2) == "child"
    check outlineView.tableRowIndexForIdentifier("child") == 2
    check outlineView.tableCellText(0, outlineView.outlineColumn()) == "Root"
    check outlineView.tableCellObjectValue(2, statusColumn).requireInt() == 2
    check outlineView.tableCellText(2, statusColumn) == "2"
    check not outlineView.rowEnabled(1)

    outlineView.selectedItemIdentifier = "child"
    let state = outlineView.captureState()
    check state.selectedRowIdentifiers == @["child"]
    check outlineView.selectedItemIdentifier == "child"

    check outlineView.insertOutlineChild(initOutlineItem("first", "First"), "root", 0)
    check outlineView.childIdentifiersForItem("root") == @["first", "disabled", "child"]
    check outlineView.selectedItemIdentifier == "child"
    check outlineView.rowForItem("child") == 3

    check outlineView.writeTableCellObjectValue(3, statusColumn, toObj(3))
    check outlineView.valueForItem("child", "status").requireInt() == 3

    outlineView.selectedItemIdentifier = ""
    outlineView.restoreState(state)
    check outlineView.selectedItemIdentifier == "child"

    check outlineView.removeOutlineItemWithIdentifier("disabled")
    check outlineView.childIdentifiersForItem("root") == @["first", "child"]
    check outlineView.moveOutlineItem("child", "", 1)
    check outlineView.parentIdentifierForItem("child") == ""
    check outlineView.rowForItem("child") == 2

  test "outline data source delegate disclosure keyboard persistence and dragging":
    let
      outlineView = newOutlineView(frame = rect(0, 0, 320, 180))
      source = newOutlineSourceSpy(
        [
          initOutlineItem("root", "Root", expandable = true),
          initOutlineItem("child", "Child", parentIdentifier = "root"),
          initOutlineItem("blocked", "Blocked", expandable = true),
        ]
      )
      delegate = newOutlineDelegateSpy()

    delegate.deniedExpand = @["blocked"]
    outlineView.outlineDataSource = source
    outlineView.outlineDelegate = delegate

    check outlineView.rowCount == 2
    outlineView.expandItem("blocked")
    check not outlineView.isItemExpanded("blocked")
    check delegate.expanded.len == 0

    outlineView.expandItem("root")
    check outlineView.rowCount == 3
    check delegate.expanded == @["root"]
    check outlineView.disclosureRectForRow(0).size.width > 0.0'f32

    let disclosure = outlineView.disclosureRectForRow(0)
    let disclosurePoint =
      initPoint(disclosure.origin.x + 1.0, disclosure.origin.y + 1.0)
    check outlineView.mouseDown(
      MouseEvent(button: mbPrimary, location: disclosurePoint)
    )
    check outlineView.isItemExpanded("root")
    check outlineView.mouseUp(MouseEvent(button: mbPrimary, location: disclosurePoint))
    check not outlineView.isItemExpanded("root")
    check delegate.collapsed == @["root"]

    outlineView.expandItem("root")
    check outlineView.toggleItemAtPoint(disclosurePoint)
    check not outlineView.isItemExpanded("root")
    check delegate.collapsed == @["root", "root"]

    outlineView.selectedIndex = 0
    check outlineView.handleOutlineKey(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord)
    )
    check outlineView.isItemExpanded("root")

    let state = outlineView.expansionPersistenceString()
    outlineView.collapseItem("root")
    outlineView.restoreExpansionPersistenceString(state)
    check outlineView.isItemExpanded("root")
    let tableState = outlineView.captureState()
    check tableState.expandedItems == @["root"]
    outlineView.collapseItem("root")
    outlineView.restoreState(tableState)
    check outlineView.isItemExpanded("root")

    let rowElement = outlineView.outlineAccessibilityElementForRow(0)
    check rowElement.role == arOutlineRow
    check rowElement.identifier == "root"
    let disclosureElement = outlineView.disclosureAccessibilityElementForRow(0)
    check disclosureElement.role == arDisclosureButton
    check disclosureElement.action == AccessibilityActionCollapse

    let drag = outlineView.beginDraggingItems(["child"], operations = {dgoCopy})
    let info = drag.draggingInfo()
    check info.tableDraggingRows() == @[1]
    check info.selectedOperations == {dgoCopy}

  test "outline drawn cell field editor aligns with indented row text":
    let
      window = newWindow("Outline field editor", frame = rect(0, 0, 380, 160))
      root = newView(frame = rect(0, 0, 380, 160))
      outlineView = newOutlineView(frame = rect(10, 10, 320, 96))
      statusColumn = newTableColumn("status", "Status", width = 90.0)

    outlineView.showsHeader = false
    outlineView.rowHeight = 28.0
    outlineView.outlineColumn().title = "Name"
    outlineView.outlineColumn().width = 180.0
    outlineView.addColumn(statusColumn)
    outlineView.outlineItems = [
      initOutlineItem("root", "Root", expandable = true),
      initOutlineItem(
        "child",
        "Child",
        parentIdentifier = "root",
        cells = [tableCell("status", toObj("Active"))],
      ),
    ]
    outlineView.expandItem("root")

    root.addSubview(outlineView)
    window.setContentView(root)
    discard buildRenders(root)

    let childRow = outlineView.rowForItem("child")
    check childRow == 1
    check outlineView.beginEditingCell(childRow, outlineView.outlineColumn())
    check window.fieldEditor().superview() != nil

    let
      indent = outlineView.levelForRow(childRow).float32 * 16.0'f32 + 24.0'f32
      expectedFrame = rect(
        indent,
        0.0'f32,
        outlineView.outlineColumn().width() - indent - 6.0'f32,
        28.0'f32,
      )
    check window.fieldEditor().frame().rectsClose(expectedFrame)
    check root.countRenderedText("Child") == 1
