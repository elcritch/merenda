import std/unittest

import sigils/core

import merenda/nimkit

type MatrixSelectionSpy = ref object of Agent
  changeCount: int
  lastSender: DynamicAgent

proc rememberMatrixSelectionDidChange(
    spy: MatrixSelectionSpy, sender: DynamicAgent
) {.slot.} =
  inc spy.changeCount
  spy.lastSender = sender

proc center(rect: Rect): Point =
  initPoint(
    rect.origin.x + rect.size.width / 2.0, rect.origin.y + rect.size.height / 2.0
  )

proc clickCell(window: Window, matrix: Matrix, row, column: int): bool =
  let point = matrix.pointToWindow(matrix.cellFrameAt(row, column).center())
  window.mouseDownAt(point) and window.mouseUpAt(point)

suite "nimkit matrix":
  test "radio matrix selects one cell and dispatches from the matrix":
    let
      window = newWindow("Matrix radio", frame = initRect(0, 0, 240, 180))
      root = newView(frame = initRect(0, 0, 240, 180))
      matrix =
        newRadioMatrix(["Small", "Medium", "Large"], frame = initRect(10, 10, 160, 90))
      action = actionSelector("matrixRadioAction")
      spy = MatrixSelectionSpy()

    var actionCount = 0
    proc onRadioAction(sender: DynamicAgent) =
      check sender == DynamicAgent(matrix)
      inc actionCount

    matrix.connect(selectionDidChange, spy, rememberMatrixSelectionDidChange)
    matrix.target = newActionTarget(action, onRadioAction)
    matrix.action = action
    root.addSubview(matrix)
    window.setContentView(root)

    check matrix.selectionMode == msmRadio
    check matrix.selectedRow == 0
    check matrix.selectedColumn == 0
    check matrix.cellAt(0, 0).state == bsOn
    check matrix.cellAt(1, 0).state == bsOff

    let point = matrix.pointToWindow(matrix.cellFrameAt(1, 0).center())
    check window.mouseDownAt(point)
    check matrix.cellAt(1, 0).isHighlighted()
    check window.mouseUpAt(point)

    check matrix.selectedRow == 1
    check matrix.selectedColumn == 0
    check matrix.selectedCell().title == "Medium"
    check matrix.cellAt(0, 0).state == bsOff
    check matrix.cellAt(1, 0).state == bsOn
    check not matrix.cellAt(1, 0).isHighlighted()
    check spy.changeCount == 1
    check spy.lastSender == DynamicAgent(matrix)
    check actionCount == 1

  test "check matrix moves the lead cell with keys and toggles with space":
    let
      window = newWindow("Matrix keys", frame = initRect(0, 0, 240, 160))
      root = newView(frame = initRect(0, 0, 240, 160))
      matrix = newCheckMatrix(
        ["A", "B", "C", "D"], columns = 2, frame = initRect(10, 10, 180, 60)
      )
      action = actionSelector("matrixCheckAction")

    var actionCount = 0
    proc onCheckAction(sender: DynamicAgent) =
      check sender == DynamicAgent(matrix)
      inc actionCount

    matrix.target = newActionTarget(action, onCheckAction)
    matrix.action = action
    root.addSubview(matrix)
    window.setContentView(root)

    check window.makeFirstResponder(matrix)
    check matrix.leadIndex == 0
    check matrix.selectedIndexes() == newSeq[int]()

    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord)
    )
    check matrix.leadIndex == 1
    check matrix.selectedIndexes() == newSeq[int]()
    check actionCount == 0

    check window.dispatchKeyDown(KeyEvent(key: keySpace, keyCode: keySpace.ord))
    check matrix.leadIndex == 1
    check matrix.selectedIndexes() == @[1]
    check actionCount == 1

    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check matrix.leadIndex == 3
    check matrix.selectedIndexes() == @[1]
    check actionCount == 1

    check window.dispatchKeyDown(KeyEvent(key: keySpace, keyCode: keySpace.ord))
    check matrix.selectedIndexes() == @[1, 3]
    check actionCount == 2

    check window.dispatchKeyDown(KeyEvent(key: keyHome, keyCode: keyHome.ord))
    check matrix.leadIndex == 0
    check matrix.selectedIndexes() == @[1, 3]
    check actionCount == 2

    check window.dispatchKeyDown(KeyEvent(key: keyEnd, keyCode: keyEnd.ord))
    check matrix.leadIndex == 3
    check matrix.selectedIndexes() == @[1, 3]
    check actionCount == 2

  test "matrix clones prototypes, reuses cells, and isolates cell view state":
    let prototype = newButtonCell("Prototype")
    prototype.setButtonType(btCheckBox)
    prototype.setAllowsMixedState(true)
    prototype.setState(bsMixed)

    let matrix = newMatrix(2, 2, prototype)
    let
      reused = matrix.cellAt(0, 0)
      detached = matrix.cellAt(1, 1)

    check matrix.len == 4
    check reused != prototype
    check reused != matrix.cellAt(0, 1)
    check reused.title == "Prototype"
    check reused.buttonType == btCheckBox
    check reused.allowsMixedState
    check reused.state == bsMixed
    check reused.controlView() == View(matrix)

    reused.setTitle("Changed")
    check matrix.cellAt(0, 1).title == "Prototype"

    matrix.renewRowsColumns(3, 2)
    check matrix.len == 6
    check matrix.cellAt(0, 0) == reused
    check matrix.cellAt(2, 0).buttonType == btCheckBox
    check matrix.cellAt(2, 0).title == "Prototype"

    matrix.renewRowsColumns(1, 1)
    check matrix.len == 1
    check matrix.cellAt(0, 0) == reused
    check detached.controlView().isNil

    let custom = newButtonCell("Custom")
    custom.setButtonType(btCheckBox)
    matrix[0, 0] = custom

    custom.setEnabled(false)
    custom.setHighlighted(true)
    check matrix.isEnabled()
    check not Cell(custom).isEnabled()
    check custom.isHighlighted()
    check ssDisabled notin matrix.widgetStateSet()
    check ssHighlighted notin matrix.widgetStateSet()

  test "momentary button matrix uses the lead cell for per-cell actions":
    let
      window = newWindow("Matrix buttons", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      matrix = newButtonMatrix(
        ["Apply", "Reset"], columns = 2, frame = initRect(10, 10, 180, 30)
      )
      resetAction = actionSelector("matrixResetAction")

    var resetCount = 0
    proc onReset(sender: DynamicAgent) =
      check sender == DynamicAgent(matrix)
      inc resetCount

    matrix.cellAtIndex(1).setTarget(newActionTarget(resetAction, onReset))
    matrix.cellAtIndex(1).setAction(resetAction)
    root.addSubview(matrix)
    window.setContentView(root)

    check window.clickCell(matrix, 0, 1)
    check matrix.selectionMode == msmNone
    check matrix.leadIndex == 1
    check matrix.selectedIndex == -1
    check resetCount == 1

  test "demo stack leaves intrinsic matrix rows inside the content bounds":
    let
      root = newView(frame = initRect(0, 0, 520, 420))
      layout = newStackView(laVertical)
      title = newTitleLabel("Matrix")
      status = newStatusLabel("Package: Standard / Features: None / Last command: None")
      packageLabel = newHeadingLabel("Package")
      featureLabel = newHeadingLabel("Features")
      commandLabel = newHeadingLabel("Commands")
      packageMatrix = newRadioMatrix(["Standard", "Pro", "Enterprise"])
      featureMatrix = newCheckMatrix(
        ["Autosave", "Diagnostics", "Cloud Sync", "Beta Tools"], columns = 2
      )
      commandMatrix = newButtonMatrix(["Apply", "Reset", "Inspect"], columns = 3)

    packageMatrix.cellSize = initSize(180.0, 24.0)
    featureMatrix.cellSize = initSize(140.0, 24.0)
    commandMatrix.cellSize = initSize(90.0, 28.0)

    layout.spacing = 9.0
    layout.alignment = svaFill
    layout.addArrangedSubview(
      title, status, packageLabel, packageMatrix, featureLabel, featureMatrix,
      commandLabel, commandMatrix,
    )
    root.addSubview(layout)
    layout.pinEdges(
      toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 24.0, 28.0)),
      edges = {leLeft, leTop, leRight},
    )

    root.layoutSubtreeIfNeeded()

    let
      intrinsic = layout.intrinsicContentSize()
      contentBottom = root.bounds().maxY - 24.0

    check intrinsic.hasHeight
    check layout.frame().origin == initPoint(28.0, 24.0)
    check layout.frame().size.width == 464.0
    check abs(layout.frame().size.height - intrinsic.height) <= 0.001'f32
    check layout.frame().maxY <= contentBottom + 0.001'f32
    check commandMatrix.frame().maxY <= layout.bounds().maxY + 0.001'f32
    check commandMatrix.frame().size.height >= 28.0
    check layout.frame().origin.y + commandMatrix.frame().maxY <=
      contentBottom + 0.001'f32
    check commandMatrix.cellFrameAt(0, 0).maxY <= commandMatrix.bounds().maxY
