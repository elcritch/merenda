import std/[strutils, unittest]

import merenda/nimkit

import ../../examples/treeview_demo

suite "NimKit tree view demo":
  test "resource hierarchy selects paths and expands or collapses every group":
    let demo = newTreeViewDemo()

    check demo.tree.outlineItemIdentifiers().len == 16
    check demo.tree.rowCount() == 10
    check demo.tree.selectedItemIdentifier() == "view.preview"
    check demo.selectionLabel.text().contains("Preview Surface")
    check demo.pathLabel.text() ==
      "Resource Bundle › Windows › Main Window › Root View › " &
      "Editor Split View › Preview Surface"

    check demo.collapseButton.sendAction()
    check demo.tree.rowCount() == 1
    check demo.activityLabel.text() == "Collapsed every container"

    check demo.expandButton.sendAction()
    check demo.tree.rowCount() == 16
    check demo.activityLabel.text() == "Expanded every container"
