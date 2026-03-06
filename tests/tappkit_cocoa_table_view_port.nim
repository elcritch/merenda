{.define: knutellaNoExampleMain.}

import std/[algorithm, unittest]

import figdraw/fignodes
import knutella/appkit
import knutella/objc

include ../examples/appkit_cocoa_table_view_port

proc clickControl(control: NSControl) =
  var sender = NSResponder.new()
  control.performClick(sender)
  sender.value = nil

proc tableValueAsString(
    controller: TableViewController, table: NSTableView, column: NSTableColumn, row: int
): NSString =
  let value = controller.tableView(table, tableColumn = column, row = row)
  if value.isNil:
    return @ns""
  NSString(value)

suite "appkit cocoa table view port":
  test "add and remove buttons preserve and use selected row":
    var table = NSTableView.new()
    var nameColumn = NSTableColumn.new(@ns"name")
    var foundationYearColumn = NSTableColumn.new(@ns"foundationYear")
    table.addTableColumn(nameColumn)
    table.addTableColumn(foundationYearColumn)

    var status = newTextField(0.0, 0.0, 320.0, 24.0, "")
    var controller = TableViewController.new()
    controller.setTableView(table)
    controller.setStatusLabel(status)
    controller.fillTestData()
    table.setDataSource(ID(value: controller.value))
    table.setDelegate(ID(value: controller.value))
    table.reloadData()
    table.selectRow(1)

    var addButton = newButton(0.0, 0.0, 80.0, 24.0, "Add")
    addButton.setOnClick(
      proc(sender: NSButton) =
        controller.addClub(sender.NSObject)
    )
    var removeButton = newButton(0.0, 0.0, 80.0, 24.0, "Remove")
    removeButton.setOnClick(
      proc(sender: NSButton) =
        controller.removeClub(sender.NSObject)
    )

    check(table.numberOfRows() == 4)
    check(controller.numberOfRowsInTableView(table) == 4)
    check(tableValueAsString(controller, table, nameColumn, 3) == @ns"Barcelona")
    check(table.selectedRow() == 1)
    check(tableValueAsString(controller, table, nameColumn, 1) == @ns"Liverpool")

    clickControl(addButton)

    check(table.numberOfRows() == 5)
    check(controller.numberOfRowsInTableView(table) == 5)
    check(table.selectedRow() == 1)
    check(tableValueAsString(controller, table, nameColumn, 1) == @ns"Liverpool")
    check(tableValueAsString(controller, table, nameColumn, 4) == @ns"FC Generic")
    check(tableValueAsString(controller, table, foundationYearColumn, 4) == @ns"2020")

    clickControl(addButton)

    check(table.numberOfRows() == 6)
    check(controller.numberOfRowsInTableView(table) == 6)
    check(table.selectedRow() == 1)
    check(tableValueAsString(controller, table, nameColumn, 1) == @ns"Liverpool")
    check(tableValueAsString(controller, table, nameColumn, 5) == @ns"FC Generic")
    check(tableValueAsString(controller, table, foundationYearColumn, 5) == @ns"2020")

    clickControl(removeButton)

    check(table.numberOfRows() == 5)
    check(controller.numberOfRowsInTableView(table) == 5)
    check(table.selectedRow() == 1)
    check(tableValueAsString(controller, table, nameColumn, 1) == @ns"Real Madrid")
    check(tableValueAsString(controller, table, nameColumn, 2) == @ns"Barcelona")
    check(tableValueAsString(controller, table, nameColumn, 4) == @ns"FC Generic")

    removeButton.value = nil
    addButton.value = nil
    controller.value = nil
    status.value = nil
    foundationYearColumn.value = nil
    nameColumn.value = nil
    table.value = nil

  test "row render node positions follow table geometry without vertical offset drift":
    var window = newWindow(0.0, 0.0, 320.0, 200.0, "table highlight geometry")
    var root = newView(0.0, 0.0, 320.0, 200.0)

    var table = NSTableView.new()
    table.setFrame(nsRect(20.0, 20.0, 220.0, 120.0))
    table.setRowHeight(24.0)
    table.setIntercellSpacing(nsSize(3.0, 2.0))

    var nameColumn = NSTableColumn.new(@ns"name")
    nameColumn.setWidth(120.0)
    table.addTableColumn(nameColumn)

    var controller = TableViewController.new()
    controller.setTableView(table)
    controller.fillTestData()
    table.setDataSource(ID(value: controller.value))
    table.reloadData()
    table.selectRow(1)

    root.addSubview(table)
    window.setContentView(root)

    let renders = debugBuildWindowRenders(window)
    check(not renders.isNil)

    var rowY: seq[float32] = @[]
    if renders.contains(0.ZLevel):
      for node in renders[0.ZLevel].nodes:
        if node.kind == nkRectangle and node.screenBox.x == 22.0 and
            node.screenBox.w == 120.0 and node.screenBox.h == 23.0:
          rowY.add(node.screenBox.y)

    rowY.sort()
    check(rowY.len == 4)
    check(rowY[0] == 62.0)
    check(rowY[1] == 88.0)
    check(rowY[2] == 114.0)
    check(rowY[3] == 140.0)

    controller.value = nil
    nameColumn.value = nil
    table.value = nil
    root.value = nil
    window.value = nil

  test "row text layout aligns to top of data cell rect":
    var window = newWindow(0.0, 0.0, 320.0, 200.0, "table text geometry")
    var root = newView(0.0, 0.0, 320.0, 200.0)

    var table = NSTableView.new()
    table.setFrame(nsRect(20.0, 20.0, 220.0, 120.0))
    table.setRowHeight(24.0)
    table.setIntercellSpacing(nsSize(3.0, 2.0))

    var nameColumn = NSTableColumn.new(@ns"name")
    nameColumn.setWidth(120.0)
    table.addTableColumn(nameColumn)

    var controller = TableViewController.new()
    controller.setTableView(table)
    controller.fillTestData()
    table.setDataSource(ID(value: controller.value))
    table.reloadData()

    root.addSubview(table)
    window.setContentView(root)

    let renders = debugBuildWindowRenders(window)
    check(not renders.isNil)

    var textNodeCount = 0
    if renders.contains(0.ZLevel):
      for node in renders[0.ZLevel].nodes:
        if node.kind == nkText and node.screenBox.x == 2.0 and node.screenBox.y == 0.0 and
            node.screenBox.w == 116.0 and node.screenBox.h == 23.0:
          inc textNodeCount
          var minY = high(float32)
          var maxY = low(float32)
          for selection in node.textLayout.selectionRects:
            minY = min(minY, selection.y)
            maxY = max(maxY, selection.y + selection.h)
          check(minY == 0.0)
          check(maxY == 15.0)

    check(textNodeCount == 4)

    controller.value = nil
    nameColumn.value = nil
    table.value = nil
    root.value = nil
    window.value = nil
