import std/strutils

import merenda/nimkit

import sigils/selectors

const
  TodoDoneColumn = "done"
  TodoTitleColumn = "title"
  TodoTaskColumn = "task"

type TodoTableController = ref object of Responder
  model: TableModel
  table: TableView
  input: TextField
  status: TextField
  nextId: int

proc updateStatus(controller: TodoTableController) =
  if controller.isNil or controller.status.isNil or controller.model.isNil:
    return

  var completed = 0
  for row in controller.model.rows():
    if row.value(TodoDoneColumn).requireBool():
      inc completed

  let total = controller.model.sourceLen()
  if total == 0:
    controller.status.text = "0 items"
  elif completed == 1:
    controller.status.text = "1 of " & $total & " done"
  else:
    controller.status.text = $completed & " of " & $total & " done"

proc toggleTodo(controller: TodoTableController, identifier: string) =
  if controller.isNil or controller.model.isNil or controller.table.isNil:
    return
  let done = controller.model.valueForRow(identifier, TodoDoneColumn).requireBool()
  controller.model.setValue(identifier, TodoDoneColumn, toObj(not done))
  controller.table.reloadData()
  controller.updateStatus()

proc newTodoRow(controller: TodoTableController, title: string): TableRowValue =
  let identifier = "todo-" & $controller.nextId
  inc controller.nextId
  tableRow(
    identifier,
    objectValue = toObj(title),
    cells = [tableCell(TodoDoneColumn, false), tableCell(TodoTitleColumn, title)],
  )

proc focusInput(controller: TodoTableController) =
  if controller.isNil or controller.input.isNil:
    return
  let owner = controller.input.window()
  if owner of Window:
    discard Window(owner).makeFirstResponder(controller.input)

proc addTodo(controller: TodoTableController, title: string) =
  if controller.isNil or controller.model.isNil or controller.table.isNil:
    return
  let trimmed = title.strip()
  if trimmed.len > 0:
    controller.model.addRow(controller.newTodoRow(trimmed))
    controller.table.reloadData()
    controller.input.text = ""
    controller.updateStatus()

proc addTodoFromInput(controller: TodoTableController) =
  if controller.isNil or controller.input.isNil:
    return
  controller.addTodo(controller.input.stringValue)
  controller.focusInput()

proc clearDone(controller: TodoTableController) =
  if controller.isNil or controller.model.isNil or controller.table.isNil:
    return

  var remaining: seq[TableRowValue]
  for row in controller.model.rows():
    if not row.value(TodoDoneColumn).requireBool():
      remaining.add row
  controller.model.rows = remaining
  controller.table.reloadData()
  controller.updateStatus()

protocol TodoTableDelegate of TableViewDelegate:
  method viewForCell(
      controller: TodoTableController,
      tableView: TableView,
      row: int,
      column: TableColumn,
  ): View =
    if controller.isNil or controller.model.isNil or column.identifier != TodoTaskColumn:
      return nil

    let
      rowValue = controller.model.rowAt(row)
      checkBox = newCheckBox(rowValue.value(TodoTitleColumn).requireString())
      done = rowValue.value(TodoDoneColumn).requireBool()
    checkBox.state = if done: bsOn else: bsOff
    checkBox.setAcceptsFirstResponder(false)
    checkBox

  method hitPolicyForCell(
      controller: TodoTableController,
      tableView: TableView,
      row: int,
      column: TableColumn,
      target: View,
      event: MouseEvent,
  ): CellHitPolicy =
    discard controller
    discard tableView
    discard row
    discard target
    discard event
    if column.identifier == TodoTaskColumn: chpSelectRow else: chpDefault

  method didActivateRow(
      controller: TodoTableController, tableView: TableView, row: int
  ) =
    discard tableView
    if not controller.isNil and row in 0 ..< controller.model.len():
      controller.toggleTodo(controller.model.rowAt(row).identifier)

proc newTodoTableController(
    model: TableModel, table: TableView, input, status: TextField
): TodoTableController =
  result = TodoTableController(model: model, table: table, input: input, status: status)
  initResponder(result)
  discard result.withProtocol(TodoTableDelegate)

let
  app = sharedApplication()
  window = newWindow("Nimkit Todo Table", frame = rect(120, 120, 460, 420))
  root = newView()
  layout = newStackView(laVertical)
  inputRow = newStackView(laHorizontal)
  buttonRow = newStackView(laHorizontal)
  title = newTitleLabel("Todo List")
  input = newTextField("")
  addButton = newButton("Add")
  clearButton = newButton("Clear Done")
  status = newStatusLabel("0 items")
  table = newTableView()
  model = newTableModel(
    [], [initTableModelColumn(TodoTaskColumn, "Task", TodoTitleColumn, 360.0)]
  )
  controller = newTodoTableController(model, table, input, status)
  addAction = actionSelector("todoTableAddItem")
  clearAction = actionSelector("todoTableClearDone")

let addTarget = newActionTarget(addAction) do(sender: DynamicAgent):
  discard sender
  controller.addTodoFromInput()

input.target = addTarget
input.action = addAction
addButton.target = addTarget
addButton.action = addAction
clearButton.target = newActionTarget(clearAction) do(sender: DynamicAgent):
  discard sender
  controller.clearDone()
  controller.focusInput()
clearButton.action = clearAction

table.bindTableModel(model)
table.delegate = controller
table.showsHeader = false
table.visibleRows = 8
table.rowHeight = 28.0
table.selectionMode = tsmSingle
table.allowsRowReordering = true
table.usesAlternatingRowBackgrounds = true

layout.spacing = 14.0
layout.alignment = svaFill

inputRow.spacing = 8.0
inputRow.alignment = svaFill
inputRow.distribution = svdFill
input.setHuggingPriority(LayoutPriorityLow, laHorizontal)
addButton.setHuggingPriority(LayoutPriorityRequired, laHorizontal)

buttonRow.spacing = 8.0
buttonRow.alignment = svaFill
buttonRow.distribution = svdFillEqually

inputRow.addArrangedSubview(input, addButton)
buttonRow.addArrangedSubview(clearButton)

layout.addArrangedSubview(title, inputRow, table, flexibleSpacer(), buttonRow, status)

inputRow.setHuggingPriority(LayoutPriorityHigh, laVertical)
buttonRow.setHuggingPriority(LayoutPriorityHigh, laVertical)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(28.0, 28.0, 28.0, 28.0)),
  edges = {leLeft, leTop, leRight, leBottom},
)

for item in ["Write release notes", "Tag v0.4.0", "Try the demo"]:
  controller.addTodo(item)

window.setContentView(root)
discard window.makeFirstResponder(input)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
