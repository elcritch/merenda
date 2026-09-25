import std/[strutils, unittest]
import figdraw
import merenda/nimkit
import ./fixtures/[rendergeometry, widgetflows]
import ../../examples/treeview_demo

suite "NimKit tree view demo":
  test "resource hierarchy selects paths and expands or collapses every group":
    let demo = newTreeViewDemo()
    defer:
      demo.window.close()
    let totalItems = demo.tree.outlineItemIdentifiers().len
    require totalItems > 1
    check demo.tree.rowCount() < totalItems

    require demo.window.clickView(demo.expandButton)
    check demo.tree.rowCount() == totalItems

    let selected = "button.add"
    let row = demo.tree.rowForItem(selected)
    require row >= 0
    discard demo.window.buildRenders()
    require demo.window.clickRect(demo.tree, demo.tree.rowItemRect(row))
    check demo.tree.selectedItemIdentifier() == selected
    check demo.selectionLabel.text().contains("Add Widget")
    check demo.pathLabel.text().endsWith("Toolbar › Add Widget")
    check "Add Widget" in demo.window.buildRenders()[DefaultDrawLevel].renderedText()

    require demo.window.clickView(demo.collapseButton)
    check demo.tree.rowCount() < totalItems
    check demo.tree.rowForItem(selected) == -1

    require demo.window.clickView(demo.expandButton)
    check demo.tree.rowCount() == totalItems
    check demo.tree.rowForItem(selected) >= 0
