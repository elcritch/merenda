import std/[algorithm, strutils]

import merenda/nimkit

import sigils/selectors

type TodoItemView = ref object of View
  checkBox: Button
  mouseDownPoint: Point
  dragging: bool

const TodoDragThreshold = 4.0'f32

proc clearDragState(item: TodoItemView)
proc reorderTodoForPoint(item: TodoItemView, point: Point)
proc toggleTodo(item: TodoItemView)

protocol TodoItemLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(item: TodoItemView): IntrinsicSize =
    if item.isNil or item.checkBox.isNil:
      return initIntrinsicSize(0.0, 24.0)

    let size = item.checkBox.sizeThatFits()
    initIntrinsicSize(size.width, max(size.height, 24.0'f32))

  method layoutSubviews(item: TodoItemView) =
    if not item.isNil and not item.checkBox.isNil:
      item.checkBox.frame = item.bounds()

protocol TodoItemMouseHitPolicy of MouseHitPolicyProtocol:
  method mouseHitPolicy(item: TodoItemView, args: MouseHitPolicyArgs): CellHitPolicy =
    if item.isNil or item.checkBox.isNil or not item.checkBox.enabled or
        args.event.button != mbPrimary:
      return chpDefault
    chpSelectRow

protocol TodoItemEvents of ResponderEventProtocol:
  method mouseDown(item: TodoItemView, event: MouseEvent): bool =
    if item.isNil or item.checkBox.isNil or not item.checkBox.enabled or
        event.button != mbPrimary:
      return false

    let owner = item.window()
    if owner of Window:
      discard Window(owner).makeFirstResponder(item.checkBox, focusVisible = false)
    item.mouseDownPoint = event.location
    item.dragging = false
    item.checkBox.highlighted = true
    true

  method mouseDragged(item: TodoItemView, event: MouseEvent): bool =
    if item.isNil or item.checkBox.isNil or not item.checkBox.enabled or
        event.button != mbPrimary:
      return false

    let distance = max(
      abs(event.location.x - item.mouseDownPoint.x),
      abs(event.location.y - item.mouseDownPoint.y),
    )
    if not item.dragging and distance >= TodoDragThreshold:
      item.dragging = true
      item.checkBox.highlighted = false
      item.alphaValue = 0.72'f32

    if item.dragging:
      item.reorderTodoForPoint(event.location)
    else:
      item.checkBox.highlighted = item.bounds().contains(event.location)
    true

  method mouseUp(item: TodoItemView, event: MouseEvent): bool =
    if item.isNil or item.checkBox.isNil or not item.checkBox.enabled or
        event.button != mbPrimary:
      return false

    let
      wasDragging = item.dragging
      clicked = item.bounds().contains(event.location)
    item.clearDragState()
    if not wasDragging and clicked:
      item.toggleTodo()
    true

proc newTodoItem(title: string): TodoItemView =
  result = TodoItemView(checkBox: newCheckBox(title))
  initViewFields(result)
  result.setHuggingPriority(LayoutPriorityLow, laHorizontal)
  result.setHuggingPriority(LayoutPriorityRequired, laVertical)
  result.setCompressionPriority(LayoutPriorityHigh, laHorizontal)
  result.setCompressionPriority(LayoutPriorityRequired, laVertical)
  discard result.withProtocol(TodoItemLayout)
  discard result.withProtocol(TodoItemMouseHitPolicy)
  discard result.withProtocol(TodoItemEvents)
  result.addSubview(result.checkBox)

let
  app = sharedApplication()
  window = newWindow("Nimkit Todo Stack Drag", frame = rect(120, 120, 420, 420))
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
  addAction = actionSelector("todoStackDragAddItem")
  clearAction = actionSelector("todoStackDragClearDone")
  toggleAction = actionSelector("todoStackDragToggleItem")

var todos: seq[TodoItemView]

proc todoIndex(item: TodoItemView): int =
  todos.find(item)

proc clearDragState(item: TodoItemView) =
  if item.isNil:
    return
  item.dragging = false
  item.alphaValue = 1.0'f32
  if not item.checkBox.isNil:
    item.checkBox.highlighted = false

proc dropIndexForPoint(item: TodoItemView, point: Point): int =
  if item.isNil or todoList.isNil:
    return item.todoIndex()

  let listPoint = todoList.pointFromView(point, item)
  for todo in todos:
    if todo != item and
        listPoint.y > todo.frame().origin.y + todo.frame().size.height / 2.0'f32:
      inc result

proc moveTodo(item: TodoItemView, index: int) =
  let oldIndex = item.todoIndex()
  if oldIndex < 0:
    return

  let nextIndex = max(0, min(index, todos.len - 1))
  if nextIndex == oldIndex:
    return

  todos.delete(oldIndex)
  todos.insert(item, nextIndex)
  todoList.insertArrangedSubview(item, nextIndex)
  todoList.layoutSubtreeIfNeeded()

proc reorderTodoForPoint(item: TodoItemView, point: Point) =
  item.moveTodo(item.dropIndexForPoint(point))

proc toggleTodo(item: TodoItemView) =
  if not item.isNil and not item.checkBox.isNil:
    discard item.checkBox.tryToPerform(performClick(), DynamicAgent(item.checkBox))

proc updateStatus() =
  var completed = 0
  for todo in todos:
    if todo.checkBox.state == bsOn:
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
    let todo = newTodoItem(trimmed)
    todo.checkBox.target = newActionTarget(toggleAction, onToggleTodo)
    todo.checkBox.action = toggleAction
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

  var remaining: seq[TodoItemView]
  for todo in todos:
    if todo.checkBox.state == bsOn:
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

app.runWindow(window, root, input)
