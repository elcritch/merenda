import std/strutils

import merenda/nimkit

import sigils/selectors

let
  app = sharedApplication()
  window = newWindow("Nimkit Todo Basic", frame = rect(120, 120, 420, 420))
  root = newView()
  layout = newStackView(laVertical)
  inputRow = newStackView(laHorizontal)
  buttonRow = newStackView(laHorizontal)
  todoList = newStackView(laVertical)
  title = newTitleLabel("Todo List")
  input = newTextField("")
  addButton = newButton("Add")
  clearButton = newButton("Clear Done")
  status = newStatusLabel("0 items")
  addAction = actionSelector("todoBasicAddItem")
  clearAction = actionSelector("todoBasicClearDone")
  toggleAction = actionSelector("todoBasicToggleItem")

var todos: seq[Button]

proc updateStatus() =
  var completed = 0
  for todo in todos:
    if todo.state == bsOn:
      inc completed

  let total = todos.len
  if total == 0:
    status.text = "0 items"
  elif completed == 1:
    status.text = "1 of " & $total & " done"
  else:
    status.text = $completed & " of " & $total & " done"

proc onToggleTodo(sender: DynamicAgent) =
  if not sender.isNil:
    updateStatus()

proc addTodo(title: string) =
  let trimmed = title.strip()
  if trimmed.len > 0:
    let todo = newCheckBox(trimmed)
    todo.target = newActionTarget(toggleAction, onToggleTodo)
    todo.action = toggleAction
    todos.add(todo)
    todoList.addArrangedSubview(todo)
    input.text = ""
    updateStatus()

proc onAddTodo(sender: DynamicAgent) =
  if sender.isNil:
    return
  addTodo(input.stringValue)
  discard window.makeFirstResponder(input)

proc onClearDone(sender: DynamicAgent) =
  if sender.isNil:
    return

  var remaining: seq[Button]
  for todo in todos:
    if todo.state == bsOn:
      todo.removeFromSuperview()
    else:
      remaining.add(todo)

  todos = remaining
  updateStatus()

let addTarget = newActionTarget(addAction, onAddTodo)

input.target = addTarget
input.action = addAction
addButton.target = addTarget
addButton.action = addAction
clearButton.target = newActionTarget(clearAction, onClearDone)
clearButton.action = clearAction

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

todoList.spacing = 8.0
todoList.alignment = svaFill

inputRow.addArrangedSubview(input, addButton)
buttonRow.addArrangedSubview(clearButton)
layout.addArrangedSubview(title, inputRow, todoList, buttonRow, status)

root.addSubview(layout)
layout.pinEdges(
  toGuide = root.contentLayoutGuide(insets(28.0, 28.0, 0.0, 28.0)),
  edges = {leLeft, leTop, leRight},
)

for item in ["Write release notes", "Tag v0.4.0", "Try the demo"]:
  addTodo(item)

window.setContentView(root)
discard window.makeFirstResponder(input)
app.addWindow(window)

window.makeKeyAndOrderFront()
app.run()
