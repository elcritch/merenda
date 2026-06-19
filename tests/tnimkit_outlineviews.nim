import std/[strutils, unittest]

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
    check outlineView.tableCellText(0, outlineView.outlineColumn()).startsWith("v ")
    check outlineView.tableCellText(2, outlineView.outlineColumn()).startsWith("      ")

    outlineView.collapseItem("project")
    check outlineView.rowCount == 2
    check outlineView.isItemExpanded("src")
    check outlineView.rowForItem("main") == -1

  test "outline column can be replaced and remains a table column":
    let
      outlineView = newOutlineView()
      customColumn = newTableColumn("name", "Name", width = 180.0)

    outlineView.outlineColumn = customColumn
    check outlineView.outlineColumn == customColumn
    check customColumn.tableView == TableView(outlineView)
    check outlineView.columnWithIdentifier("name") == customColumn

  test "outline data source delegate disclosure keyboard persistence and dragging":
    let
      outlineView = newOutlineView(frame = initRect(0, 0, 320, 180))
      source = newOutlineSourceSpy([
        initOutlineItem("root", "Root", expandable = true),
        initOutlineItem("child", "Child", parentIdentifier = "root"),
        initOutlineItem("blocked", "Blocked", expandable = true),
      ])
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
    check outlineView.toggleItemAtPoint(initPoint(disclosure.origin.x + 1.0, disclosure.origin.y + 1.0))
    check not outlineView.isItemExpanded("root")
    check delegate.collapsed == @["root"]

    outlineView.selectedIndex = 0
    check outlineView.handleOutlineKey(KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord))
    check outlineView.isItemExpanded("root")

    let state = outlineView.expansionPersistenceString()
    outlineView.collapseItem("root")
    outlineView.restoreExpansionPersistenceString(state)
    check outlineView.isItemExpanded("root")

    let drag = outlineView.beginDraggingItems(["child"], operation = tdoCopy)
    check drag.rows == @[1]
    check drag.operation == tdoCopy
