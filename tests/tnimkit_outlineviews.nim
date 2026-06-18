import std/[strutils, unittest]

import merenda/nimkit

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
    check outlineView.tableCellText(0, outlineView.outlineColumn()).startsWith("> ")
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
