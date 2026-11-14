## Dragology's discrete model-driven dragging, adapted to native NimKit stacks.
import merenda/nimkit

type Board = array[2, seq[string]]

proc buildBoard(model: Board, env: DragEnvironment): View =
  let board = newStackView(
    laHorizontal, frame = rect(0, 0, env.bounds.size.width, env.bounds.size.height)
  )
  board.spacing = 20
  board.edgeInsets = insets(20, 20, 20, 20)
  board.alignment = svaLeading
  board.distribution = svdFillEqually
  for lane, items in model:
    let column = newStackView(laVertical)
    column.spacing = 12
    column.alignment = svaFill
    column.addArrangedSubview(newTitleLabel(if lane == 0: "To do" else: "Done"))
    for item in items:
      let card = newStackView(laVertical)
      card.identifier = item
      card[vpDraggable] = true
      card.spacing = 8
      card.edgeInsets = insets(14, 14, 14, 14)
      card.backgroundColor =
        if lane == 0:
          color(0.16, 0.28, 0.43, 1)
        else:
          color(0.16, 0.37, 0.30, 1)
      let title = newLabel(item)
      title.textColor = color(0.96, 0.97, 1, 1)
      card.addArrangedSubview(title)
      if item == "Explore possible futures":
        let detail = newLabel("Each destination comes from a layout.")
        detail.textColor = color(0.75, 0.83, 0.94, 1)
        card.addArrangedSubview(detail)
      column.addArrangedSubview(card)
    board.addArrangedSubview(column)
  board

proc nextBoards(model: Board, id: string): seq[Board] =
  var remaining = model
  for lane in 0 .. 1:
    let index = remaining[lane].find(id)
    if index >= 0:
      remaining[lane].delete(index)
  for lane in 0 .. 1:
    for index in 0 .. remaining[lane].len:
      var next = remaining
      next[lane].insert(id, index)
      result.add next

proc runDeclarativeDragDemo*() =
  let
    app = sharedApplication()
    window =
      newWindow("Declarative Dragging · NimKit", frame = rect(120, 120, 820, 520))
    root = newStackView(laVertical)
    undoManager = newUndoManager()
    heading = newTitleLabel("Drag a card to explore its possible futures")
    hint = newLabel(
      "Move within or between columns. Escape cancels. Release commits one undo step."
    )
    undoButton = newButton("Undo")
    redoButton = newButton("Redo")
    actions = newStackView(laHorizontal)
  var host: DeclarativeDragView[Board]
  defer:
    undoManager.clearAll()
    host = nil
  proc applyBoard(model: Board) =
    undoManager.registerValueChange(applyBoard, host.model, "Move card")
    host.model = model

  host = newDeclarativeDragView(
    [
      @["Explore possible futures", "Keep the model unchanged", "Release to commit"],
      @["Build a native preview"],
    ],
    buildBoard,
    nextBoards,
    commit = proc(previous, next: Board): bool =
      undoManager.registerValueChange(applyBoard, previous, "Move card")
      true,
    frame = rect(0, 0, 780, 350),
  )
  let undoAction = actionSelector("declarativeDragUndo")
  let redoAction = actionSelector("declarativeDragRedo")
  undoButton.target = newActionTarget(
    undoAction,
    proc(sender: DynamicAgent) =
      discard undoManager.performUndo(),
  )
  undoButton.action = undoAction
  redoButton.target = newActionTarget(
    redoAction,
    proc(sender: DynamicAgent) =
      discard undoManager.performRedo(),
  )
  redoButton.action = redoAction
  actions.spacing = 10
  actions.addArrangedSubview(undoButton, redoButton)
  root.edgeInsets = insets(20, 20, 20, 20)
  root.spacing = 12
  root.alignment = svaFill
  host.setHuggingPriority(LayoutPriorityLow, laVertical)
  root.addArrangedSubview(heading, hint, host, actions)
  app.runWindow(window, root, host)

when isMainModule:
  runDeclarativeDragDemo()
