{.define: merendaNoExampleMain.}

import std/[algorithm, unittest]

import figdraw/fignodes
import merenda/appkit
import merenda/objc

include ../examples/appkit_cocoa_table_view_port

proc clickControl(control: NSControl) =
  var sender = NSResponder.new()
  control.performClick(sender)
  sender.value = nil

proc clickTableRow(table: NSTableView, row: int) =
  let rowStride = table.rowHeight() + table.intercellSpacing().height
  let localPoint = nsPoint(4.0, row.float32 * rowStride + rowStride / 2.0)
  let windowPoint = table.NSView.convertPointToView(localPoint, NSView(value: nil))
  var event = newMouseEvent(NSLeftMouseDown, windowPoint, {}, 0.0, 0, 1)
  table.mouseDown(event)
  event.value = nil

proc clickOutsideTableBounds(table: NSTableView, y: float32) =
  let localPoint = nsPoint(table.bounds().size.width + 20.0, y)
  let windowPoint = table.NSView.convertPointToView(localPoint, NSView(value: nil))
  var event = newMouseEvent(NSLeftMouseDown, windowPoint, {}, 0.0, 0, 1)
  table.mouseDown(event)
  event.value = nil

proc tableValueAsString(
    controller: TableViewController, table: NSTableView, column: NSTableColumn, row: int
): NSString =
  let value = controller.tableView(table, tableColumn = column, row = row)
  if value.isNil:
    return @ns""
  NSString(value)

suite "appkit cocoa table view port":
  test "window event dispatch selects rows instead of row text fields":
    var window = newWindow(0.0, 0.0, 320.0, 200.0, "table hit test")
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

    let rowStride = table.rowHeight() + table.intercellSpacing().height
    let localPoint = nsPoint(4.0, rowStride + rowStride / 2.0)
    let windowPoint = table.NSView.convertPointToView(localPoint, NSView(value: nil))
    var event = newMouseEvent(NSLeftMouseDown, windowPoint, {}, 0.0, 0, 1)
    window.sendEvent(event)

    check(table.selectedRow() == 1)

    event.value = nil
    controller.value = nil
    nameColumn.value = nil
    table.value = nil
    root.value = nil
    window.value = nil

  test "table selection uses NSIndexSet semantics":
    var table = NSTableView.new()
    var nameColumn = NSTableColumn.new(@ns"name")
    table.addTableColumn(nameColumn)

    var controller = TableViewController.new()
    controller.setTableView(table)
    controller.fillTestData()
    table.setDataSource(ID(value: controller.value))
    table.setDelegate(ID(value: controller.value))
    table.reloadData()

    table.selectRowIndexes(nsIndexSet([1.NSUInteger]), false)
    check(table.selectedRow() == 1)
    check(table.isRowSelected(1))
    check(table.selectedRowIndexes().toSeq() == @[1.NSUInteger])

    table.selectRowIndexes(nsIndexSet([3.NSUInteger]), true)
    check(table.selectedRow() == 1)
    check(table.isRowSelected(1))
    check(table.isRowSelected(3))
    check(table.selectedRowIndexes().toSeq() == @[1.NSUInteger, 3.NSUInteger])

    table.selectRowIndexes(nsIndexSet([99.NSUInteger]), false)
    check(table.selectedRowIndexes().toSeq() == @[1.NSUInteger, 3.NSUInteger])

    var selected = table.selectedRowIndexes()
    selected.incl(2.NSUInteger)
    check(not table.isRowSelected(2))

    table.selectRowIndexes(nsIndexSet(), false)
    check(table.selectedRow() == -1)
    check(table.selectedRowIndexes().isEmpty)

    controller.value = nil
    nameColumn.value = nil
    table.value = nil

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
    clickTableRow(table, 1)

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

    clickOutsideTableBounds(table, 12.0)
    check(table.selectedRow() == 1)

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
        if node.kind != nkText or node.textLayout.runes.len == 0:
          continue
        if node.screenBox.x != 2.0 or node.screenBox.w != 116.0:
          continue
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
