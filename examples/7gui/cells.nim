import std/[math, parseutils, sets, strutils, tables]

import merenda/nimkit

const
  RowCount = 100
  ColumnCount = 26

type
  SpreadsheetFormulaError = object of ValueError

  CellAddress = object
    row: int
    column: int

  FormulaResult = object
    display: string
    number: float
    error: bool
    deps: seq[CellAddress]

  SpreadsheetCell = object
    formula: string
    display: string
    number: float
    error: bool
    deps: seq[CellAddress]

  CellsController = ref object of Responder
    table: TableView
    cells: array[RowCount, array[ColumnCount, SpreadsheetCell]]
    dependents: Table[string, HashSet[string]]

  FormulaParser = object
    controller: CellsController
    text: string
    position: int
    deps: seq[CellAddress]

func columnTitle(column: int): string =
  $(char(ord('A') + column))

func addressKey(address: CellAddress): string =
  $address.row & ":" & $address.column

proc parseAddressKey(key: string): CellAddress =
  let parts = key.split(":")
  if parts.len == 2:
    result.row = parts[0].parseInt()
    result.column = parts[1].parseInt()

func formatCellNumber(value: float): string =
  if abs(value - round(value)) < 0.000001:
    return $int(round(value))
  result = value.formatFloat(ffDecimal, 4)
  while result.len > 0 and result[^1] == '0':
    result.setLen(result.len - 1)
  if result.endsWith("."):
    result.setLen(result.len - 1)

proc failFormula(message: string) {.noReturn.} =
  raise newException(SpreadsheetFormulaError, message)

proc skipSpaces(parser: var FormulaParser) =
  while parser.position < parser.text.len and parser.text[parser.position].isSpaceAscii:
    inc parser.position

proc parseExpression(parser: var FormulaParser): float

proc addDependency(parser: var FormulaParser, address: CellAddress) =
  for dependency in parser.deps:
    if dependency == address:
      return
  parser.deps.add address

proc cellNumber(controller: CellsController, address: CellAddress): float =
  if address.row notin 0 ..< RowCount or address.column notin 0 ..< ColumnCount:
    failFormula("cell address out of bounds")
  let cell = controller.cells[address.row][address.column]
  if cell.error:
    failFormula("referenced cell contains an error")
  cell.number

proc parseCellReference(parser: var FormulaParser): float =
  if parser.position >= parser.text.len:
    failFormula("expected cell reference")
  let columnChar = parser.text[parser.position].toUpperAscii()
  if columnChar notin 'A' .. 'Z':
    failFormula("expected cell reference")
  inc parser.position

  var row = 0
  let consumed = parseInt(parser.text, row, parser.position)
  if consumed <= 0:
    failFormula("expected row number")
  parser.position += consumed

  let address = CellAddress(row: row, column: ord(columnChar) - ord('A'))
  if address.row notin 0 ..< RowCount or address.column notin 0 ..< ColumnCount:
    failFormula("cell address out of bounds")
  parser.addDependency(address)
  parser.controller.cellNumber(address)

proc parseNumber(parser: var FormulaParser): float =
  var value = 0.0
  let consumed = parseFloat(parser.text, value, parser.position)
  if consumed <= 0:
    failFormula("expected number")
  parser.position += consumed
  value

proc parseFactor(parser: var FormulaParser): float =
  parser.skipSpaces()
  if parser.position >= parser.text.len:
    failFormula("expected expression")

  let ch = parser.text[parser.position]
  case ch
  of '-':
    inc parser.position
    result = -parser.parseFactor()
  of '+':
    inc parser.position
    result = parser.parseFactor()
  of '(':
    inc parser.position
    result = parser.parseExpression()
    parser.skipSpaces()
    if parser.position >= parser.text.len or parser.text[parser.position] != ')':
      failFormula("expected ')'")
    inc parser.position
  of '0' .. '9', '.':
    result = parser.parseNumber()
  of 'A' .. 'Z', 'a' .. 'z':
    result = parser.parseCellReference()
  else:
    failFormula("expected expression")

proc parseTerm(parser: var FormulaParser): float =
  result = parser.parseFactor()
  while true:
    parser.skipSpaces()
    if parser.position >= parser.text.len or
        parser.text[parser.position] notin {'*', '/'}:
      break
    let op = parser.text[parser.position]
    inc parser.position
    let rhs = parser.parseFactor()
    case op
    of '*':
      result *= rhs
    of '/':
      if abs(rhs) < 0.000001:
        failFormula("division by zero")
      result /= rhs
    else:
      discard

proc parseExpression(parser: var FormulaParser): float =
  result = parser.parseTerm()
  while true:
    parser.skipSpaces()
    if parser.position >= parser.text.len or
        parser.text[parser.position] notin {'+', '-'}:
      break
    let op = parser.text[parser.position]
    inc parser.position
    let rhs = parser.parseTerm()
    case op
    of '+':
      result += rhs
    of '-':
      result -= rhs
    else:
      discard

proc evaluateFormula(controller: CellsController, formula: string): FormulaResult =
  let text = formula.strip()
  if text.len == 0:
    return FormulaResult(display: "", number: 0.0, error: false)

  if text[0] != '=':
    var value = 0.0
    let consumed = parseFloat(text, value, 0)
    if consumed == text.len:
      return
        FormulaResult(display: value.formatCellNumber(), number: value, error: false)
    return FormulaResult(display: text, number: 0.0, error: false)

  var parser = FormulaParser(controller: controller, text: text[1 .. ^1])
  try:
    let value = parser.parseExpression()
    parser.skipSpaces()
    if parser.position != parser.text.len:
      failFormula("unexpected input")
    FormulaResult(
      display: value.formatCellNumber(), number: value, error: false, deps: parser.deps
    )
  except SpreadsheetFormulaError:
    FormulaResult(display: "#ERR", number: 0.0, error: true, deps: parser.deps)

proc removeReverseDependencies(controller: CellsController, address: CellAddress) =
  let dependentKey = address.addressKey()
  for dependency in controller.cells[address.row][address.column].deps:
    let sourceKey = dependency.addressKey()
    if sourceKey in controller.dependents:
      controller.dependents[sourceKey].excl dependentKey

proc addReverseDependencies(controller: CellsController, address: CellAddress) =
  let dependentKey = address.addressKey()
  for dependency in controller.cells[address.row][address.column].deps:
    let sourceKey = dependency.addressKey()
    if sourceKey notin controller.dependents:
      controller.dependents[sourceKey] = initHashSet[string]()
    controller.dependents[sourceKey].incl dependentKey

proc applyFormulaResult(
    controller: CellsController,
    address: CellAddress,
    formula: string,
    value: FormulaResult,
): bool =
  let previous = controller.cells[address.row][address.column]
  controller.cells[address.row][address.column] = SpreadsheetCell(
    formula: formula,
    display: value.display,
    number: value.number,
    error: value.error,
    deps: value.deps,
  )
  previous.display != value.display or previous.error != value.error or
    abs(previous.number - value.number) > 0.000001

proc reevaluateCell(controller: CellsController, address: CellAddress): bool =
  let formula = controller.cells[address.row][address.column].formula
  let value = controller.evaluateFormula(formula)
  controller.applyFormulaResult(address, formula, value)

proc propagateFrom(controller: CellsController, address: CellAddress) =
  var
    queue: seq[string]
    visited = initHashSet[string]()
  let sourceKey = address.addressKey()
  if sourceKey in controller.dependents:
    for key in controller.dependents[sourceKey]:
      queue.add key

  while queue.len > 0:
    let key = queue[0]
    queue.delete(0)
    if key in visited:
      continue
    visited.incl key

    let dependent = key.parseAddressKey()
    if controller.reevaluateCell(dependent) and key in controller.dependents:
      for next in controller.dependents[key]:
        queue.add next

proc setCellFormula(
    controller: CellsController, address: CellAddress, formula: string, reload = true
) =
  if address.row notin 0 ..< RowCount or address.column notin 0 ..< ColumnCount:
    return
  controller.removeReverseDependencies(address)
  let value = controller.evaluateFormula(formula)
  discard controller.applyFormulaResult(address, formula, value)
  controller.addReverseDependencies(address)
  controller.propagateFrom(address)
  if reload:
    controller.table.reloadData()

protocol CellsDataSource of TableViewDataSource:
  method numberOfRows(controller: CellsController, tableView: TableView): int =
    discard controller
    discard tableView
    RowCount

  method textForCell(
      controller: CellsController, tableView: TableView, row: int, column: TableColumn
  ): string =
    discard tableView
    if column.identifier == "row":
      return $row
    let col = ord(column.identifier[0]) - ord('A')
    if row in 0 ..< RowCount and col in 0 ..< ColumnCount:
      controller.cells[row][col].display
    else:
      ""

  method identifierForRow(
      controller: CellsController, tableView: TableView, row: int
  ): string =
    discard controller
    discard tableView
    $row

protocol CellsDelegate of TableViewDelegate:
  method shouldEditCell(
      controller: CellsController, tableView: TableView, row: int, column: TableColumn
  ): bool =
    discard controller
    discard tableView
    discard row
    column.identifier != "row"

  method didCommitEditingCell(
      controller: CellsController,
      tableView: TableView,
      row: int,
      column: TableColumn,
      value: string,
  ) =
    discard tableView
    if column.identifier == "row":
      return
    let address = CellAddress(row: row, column: ord(column.identifier[0]) - ord('A'))
    controller.setCellFormula(address, value)

  method tableRowHeight(
      controller: CellsController, tableView: TableView, row: int
  ): float32 =
    discard controller
    discard tableView
    discard row
    24.0

proc newCellsController(table: TableView): CellsController =
  result = CellsController(table: table)
  initResponder(result)
  discard result.withProtocol(CellsDataSource)
  discard result.withProtocol(CellsDelegate)

let
  app = sharedApplication()
  window = newWindow("7GUIs Cells", frame = rect(120, 120, 900, 540))
  root = newView()
  layout = newStackView(laVertical)
  title = newTitleLabel("Cells")
  status =
    newStatusLabel("Double-click a cell and enter values or formulas like =A0+B0*2.")
  table = newTableView()
  controller = newCellsController(table)

table.addColumn(
  newTableColumn("row", "", width = 42.0, resizePolicy = tcrFixed, alignment = taRight)
)
for column in 0 ..< ColumnCount:
  table.addColumn(
    newTableColumn(column.columnTitle(), column.columnTitle(), width = 72.0)
  )

table.dataSource = controller
table.delegate = controller
table.tableHeaderHeight = 24.0
table.rowHeight = 24.0
table.visibleRows = 18
table.selectionMode = tsmSingle
table.usesAlternatingRowBackgrounds = true
table.showsRowSeparators = true
table.selectCell(0, table.columnWithIdentifier("A"))

controller.setCellFormula(CellAddress(row: 0, column: 0), "1", reload = false)
controller.setCellFormula(CellAddress(row: 0, column: 1), "2", reload = false)
controller.setCellFormula(CellAddress(row: 0, column: 2), "=A0+B0", reload = false)
controller.setCellFormula(CellAddress(row: 1, column: 0), "=C0*10", reload = false)

layout.spacing = 14.0
layout.alignment = svaFill
layout.addArrangedSubview(title, status, table)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

app.runWindow(window, root, table)
