import std/[options, unittest]

import sigils/core

import merenda/nimkit

type ObjectTableSpy = ref object of Responder
  values: seq[int]
  commits: seq[int]

protocol ObjectTableSpyDataSource of TableViewDataSource:
  method numberOfRows(spy: ObjectTableSpy, tableView: TableView): int =
    spy.values.len

  method objectValueForCell(
      spy: ObjectTableSpy, tableView: TableView, row: int, column: TableColumn
  ): ObjectValue =
    if row in 0 ..< spy.values.len:
      toObj(spy.values[row])
    else:
      nilObjectValue()

protocol ObjectTableSpyDelegate of TableViewDelegate:
  method parseObjectValueForCell(
      spy: ObjectTableSpy,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ): ObjectParseResult =
    parseObjectValue(
      value, initObjectParseContext(expectedKind = ovInt, role = ovrTableCell)
    )

  method didCommitEditingObjectValue(
      spy: ObjectTableSpy,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: ObjectValue,
  ) =
    let number = value.requireInt()
    if row in 0 ..< spy.values.len:
      spy.values[row] = number
    spy.commits.add number

proc newObjectTableSpy(values: openArray[int]): ObjectTableSpy =
  result = ObjectTableSpy(values: @values)
  initResponder(result)
  discard result.withProtocol(ObjectTableSpyDataSource)
  discard result.withProtocol(ObjectTableSpyDelegate)

suite "nimkit object values":
  test "object values require typed access explicitly":
    let text = toObj("abc")

    check text.kind == ovString
    check text.requireString() == "abc"
    check text.getString().get() == "abc"
    check text.getInt().isNone
    check toObj(ImageResource(nil)).kind == ovNil
    check toObj(TextStorage(nil)).kind == ovNil

    expect ObjectValueError:
      discard text.requireInt()

  test "object value converters coerce native values":
    let
      text: ObjectValue = "abc"
      number: ObjectValue = 42
      ratio: ObjectValue = 2.5
      enabled: ObjectValue = true
      cell = tableCell("score", 31)
      parsed = initObjectParseResult(7)

    check text.requireString() == "abc"
    check number.requireInt() == 42
    check ratio.requireFloat() == 2.5
    check enabled.requireBool()
    check cell.value.requireInt() == 31
    check parsed.value.requireInt() == 7

  test "default parser returns typed values and structured errors":
    let parsedInt = parseObjectValue("42", initObjectParseContext(expectedKind = ovInt))
    check parsedInt.valid()
    check parsedInt.value.requireInt() == 42

    let badInt =
      parseObjectValue("forty-two", initObjectParseContext(expectedKind = ovInt))
    check badInt.failed()
    check badInt.error.kind == oveParseFailed
    check badInt.error.expectedKind == ovInt

    let emptyAsNil = parseObjectValue(
      "", initObjectParseContext(expectedKind = ovString, emptyPolicy = oepNilValue)
    )
    check emptyAsNil.valid()
    check emptyAsNil.value.kind == ovNil

  test "text field invalid typed edits do not overwrite object value":
    let
      window = newWindow("Typed text field", frame = rect(0, 0, 240, 120))
      root = newView(frame = rect(0, 0, 240, 120))
      field = newTextField("", frame = rect(10, 10, 140, 24))

    field.objectParseContext =
      initObjectParseContext(expectedKind = ovInt, emptyPolicy = oepInvalid)
    field.objectValue = toObj(12)
    root.addSubview(field)
    window.setContentView(root)

    check field.stringValue == "12"
    check field.objectValue.requireInt() == 12
    check window.makeFirstResponder(field)

    TextView(window.fieldEditor()).stringValue = "bad"
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check field.currentEditor() == window.fieldEditor()
    check Control(field).hasValidationError()
    check field.objectValue.requireInt() == 12
    check window.fieldEditor().hasValidationError()

    TextView(window.fieldEditor()).stringValue = "34"
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check field.currentEditor().isNil
    check not Control(field).hasValidationError()
    check field.objectValue.requireInt() == 34
    check field.stringValue == "34"

  test "combo boxes and menu items format object values":
    let comboBox = newComboBox()
    comboBox.addItem(toObj(42))
    check comboBox.itemAtIndex(0) == "42"
    comboBox.selectedIndex = 0
    check comboBox.objectValue.requireInt() == 42

    let item = newMenuItem(toObj(initObjectLinkValue("https://example.test", "Docs")))
    check item.title == "Docs"
    check item.objectValue.requireLink().url == "https://example.test"

  test "table cells display parse and commit typed object values":
    let
      tableView = newTableView()
      column = newTableColumn("count", width = 80.0)
      source = newObjectTableSpy([3])

    tableView.addColumn(column)
    tableView.dataSource = source
    tableView.delegate = source

    check tableView.tableCellText(0, column) == "3"
    check tableView.tableCellObjectValue(0, column).requireInt() == 3

    check tableView.beginEditingCell(0, column)
    check not tableView.commitEditingCell("bad")
    check tableView.editingState.active
    check tableView.editingValidation().kind == oveParseFailed
    check tableView.editingValidationError().len > 0
    check Control(tableView).hasValidationError()

    check tableView.commitEditingCell("7")
    check not tableView.editingState.active
    check source.values == @[7]
    check source.commits == @[7]
    check not Control(tableView).hasValidationError()
