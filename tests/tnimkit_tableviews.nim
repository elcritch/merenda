import std/unittest

import sigils/core

import merenda/nimkit

type TableDataSourceSpy = ref object of Responder
  rows: int

type TableColumnUserInfo = ref object of Responder
  label: string

protocol TableDataSourceSpyMethods of TableViewDataSource:
  method numberOfRows(source: TableDataSourceSpy, tableView: TableView): int =
    source.rows

proc newTableDataSourceSpy(rows: int): TableDataSourceSpy =
  result = TableDataSourceSpy(rows: rows)
  initResponder(result)
  discard result.withProtocol(TableDataSourceSpyMethods)

suite "NimKit TableView":
  test "table columns expose stable identifiers and mutable display properties":
    let column = newTableColumn(
      "name",
      title = "Name",
      width = 160.0,
      minWidth = 40.0,
      maxWidth = 240.0,
      alignment = taCenter,
      resizePolicy = tcrResizable,
    )

    check column.identifier == "name"
    check column.title == "Name"
    check column.width == 160.0'f32
    check column.minWidth == 40.0'f32
    check column.maxWidth == 240.0'f32
    check column.alignment == taCenter
    check column.resizePolicy == tcrResizable

    column.width = 500.0
    check column.width == 240.0'f32
    column.minWidth = 180.0
    check column.width == 240.0'f32
    column.maxWidth = 190.0
    check column.width == 190.0'f32

    column.title = "Full Name"
    column.alignment = taRight
    column.resizePolicy = tcrFixed
    column.styleId = "primary-name"
    column.styleClasses = ["primary", "text"]
    let userInfo = TableColumnUserInfo(label: "metadata")
    initResponder(userInfo)
    column.userInfo = userInfo

    check column.title == "Full Name"
    check column.alignment == taRight
    check column.resizePolicy == tcrFixed
    check column.styleId == "primary-name"
    check column.styleClasses == @["primary", "text"]
    check column.userInfo == DynamicAgent(userInfo)

  test "table view maintains ordered unique columns":
    let
      tableView = newTableView()
      name = newTableColumn("name", "Name")
      age = newTableColumn("age", "Age")
      email = newTableColumn("email", "Email")

    tableView.addColumn(name)
    tableView.addColumn(email)
    tableView.insertColumn(age, 1)

    check tableView.columnCount == 3
    check tableView.columnAt(0) == name
    check tableView.columnAt(1) == age
    check tableView.columnAt(2) == email
    check tableView.columnIndex("age") == 1
    check tableView.columnWithIdentifier("email") == email
    check tableView.containsColumn("name")
    check name.tableView == tableView

    tableView.addColumn(newTableColumn("age", "Duplicate Age"))
    check tableView.columnCount == 3

    var identifiers: seq[string]
    for column in tableView.columns:
      identifiers.add column.identifier
    check identifiers == @["name", "age", "email"]

    tableView.removeColumn("age")
    check tableView.columnCount == 2
    check age.tableView.isNil
    check tableView.columnIndex("age") == -1

    tableView.removeColumn(email)
    check tableView.columnCount == 1
    check email.tableView.isNil

  test "table columns move cleanly between table views":
    let
      first = newTableView()
      second = newTableView()
      column = newTableColumn("name", "Name")

    first.addColumn(column)
    check first.columnCount == 1
    check column.tableView == first

    second.addColumn(column)
    check first.columnCount == 0
    check second.columnCount == 1
    check second.columnAt(0) == column
    check column.tableView == second

  test "table view row count can be local or data-source backed":
    let tableView = newTableView()

    tableView.rowCount = 4
    check tableView.rowCount == 4
    check len(tableView) == 4

    let source = newTableDataSourceSpy(7)
    tableView.dataSource = source
    check tableView.dataSource == DynamicAgent(source)
    check tableView.rowCount == 7
    check len(tableView) == 7

  test "table view keeps inherited row selection behavior":
    let tableView = newTableView()

    tableView.rowCount = 5
    tableView.selectionMode = lsmExtended
    ListView(tableView).selectedRange = 1 .. 3

    check tableView.selectedIndexes == @[1, 2, 3]
    check ListView(tableView).selectedRange == 1 .. 3
