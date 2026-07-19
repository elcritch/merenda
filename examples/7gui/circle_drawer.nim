import std/math

import merenda/nimkit

import sigils/selectors

const
  DefaultDiameter = 36.0'f32
  MinDiameter = 12.0'f32
  MaxDiameter = 120.0'f32

type
  Circle = object
    center: Point
    diameter: float32

  CircleActionKind = enum
    cakCreate
    cakResize

  CircleAction = object
    kind: CircleActionKind
    index: int
    circle: Circle
    beforeDiameter: float32
    afterDiameter: float32

  CircleCanvas = ref object of View
    undoButton: Button
    redoButton: Button
    adjustItem: MenuItem
    circles: seq[Circle]
    selectedIndex: int
    undoStack: seq[CircleAction]
    redoStack: seq[CircleAction]

proc updateHistoryButtons(canvas: CircleCanvas)
proc selectedCircleAt(canvas: CircleCanvas, point: Point): int
proc openDiameterEditor(canvas: CircleCanvas)
proc pushHistory(canvas: CircleCanvas, action: CircleAction)
proc undoLast(canvas: CircleCanvas)
proc redoLast(canvas: CircleCanvas)

protocol CircleCanvasDrawing of ViewDrawingProtocol:
  method draw(canvas: CircleCanvas, context: DrawContext) =
    let bounds = canvas.bounds()
    discard context.addRenderRectangle(
      context.renderRectFor(bounds),
      fill(color(0.98, 0.99, 1.0, 1.0)),
      color(0.64, 0.72, 0.82, 1.0),
      1.0,
      6.0,
    )

    for index, circle in canvas.circles:
      let
        radius = circle.diameter * 0.5'f32
        outlineColor =
          if index == canvas.selectedIndex:
            color(0.26, 0.50, 0.84, 1.0)
          else:
            color(0.36, 0.42, 0.50, 1.0)
        innerColor =
          if index == canvas.selectedIndex:
            color(0.72, 0.75, 0.78, 1.0)
          else:
            color(0.98, 0.99, 1.0, 1.0)
      discard context.addRenderCircle(circle.center, fill(outlineColor), radius)
      discard context.addRenderCircle(
        circle.center, fill(innerColor), max(radius - 2.0'f32, 0.0'f32)
      )

protocol CircleCanvasEvents of ResponderEventProtocol:
  method mouseDown(canvas: CircleCanvas, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false

    let hit = canvas.selectedCircleAt(event.location)
    if hit >= 0:
      canvas.selectedIndex = hit
      canvas.needsDisplay = true
      return true

    let circle = Circle(center: event.location, diameter: DefaultDiameter)
    canvas.circles.add circle
    canvas.selectedIndex = canvas.circles.high
    canvas.pushHistory(
      CircleAction(kind: cakCreate, index: canvas.selectedIndex, circle: circle)
    )
    canvas.needsDisplay = true
    true

  method mouseMoved(canvas: CircleCanvas, event: MouseEvent): bool =
    let hit = canvas.selectedCircleAt(event.location)
    if hit != canvas.selectedIndex:
      canvas.selectedIndex = hit
      canvas.needsDisplay = true
    true

  method rightMouseDown(canvas: CircleCanvas, event: MouseEvent): bool =
    let hit = canvas.selectedCircleAt(event.location)
    canvas.selectedIndex = hit
    canvas.needsDisplay = true
    if not canvas.adjustItem.isNil:
      canvas.adjustItem.enabled = hit >= 0
    if hit >= 0 and not canvas.menu().isNil:
      discard canvas.menu().popUpContextMenu(canvas, event)
      return true
    false

proc newCircleCanvas(): CircleCanvas =
  result = CircleCanvas(selectedIndex: -1)
  initViewFields(result)
  result.accessibilityRole = arGroup
  result.accessibilityLabel = "Circle canvas"
  result.acceptsFirstResponder = true
  discard result.withProtocol(CircleCanvasDrawing)
  discard result.withProtocol(CircleCanvasEvents)

proc distanceFrom(point, center: Point): float32 =
  let
    dx = point.x - center.x
    dy = point.y - center.y
  sqrt(dx * dx + dy * dy)

proc selectedCircleAt(canvas: CircleCanvas, point: Point): int =
  result = -1
  var bestDistance = float32.high
  for index, circle in canvas.circles:
    let distance = point.distanceFrom(circle.center)
    if distance <= circle.diameter * 0.5'f32 and distance < bestDistance:
      result = index
      bestDistance = distance

proc updateHistoryButtons(canvas: CircleCanvas) =
  if canvas.isNil:
    return
  if not canvas.undoButton.isNil:
    canvas.undoButton.enabled = canvas.undoStack.len > 0
  if not canvas.redoButton.isNil:
    canvas.redoButton.enabled = canvas.redoStack.len > 0

proc pushHistory(canvas: CircleCanvas, action: CircleAction) =
  canvas.undoStack.add action
  canvas.redoStack.setLen(0)
  canvas.updateHistoryButtons()

proc undoLast(canvas: CircleCanvas) =
  if canvas.undoStack.len == 0:
    return
  let action = canvas.undoStack.pop()
  case action.kind
  of cakCreate:
    if action.index in 0 ..< canvas.circles.len:
      canvas.circles.delete(action.index)
      canvas.selectedIndex = -1
  of cakResize:
    if action.index in 0 ..< canvas.circles.len:
      canvas.circles[action.index].diameter = action.beforeDiameter
      canvas.selectedIndex = action.index
  canvas.redoStack.add action
  canvas.updateHistoryButtons()
  canvas.needsDisplay = true

proc redoLast(canvas: CircleCanvas) =
  if canvas.redoStack.len == 0:
    return
  let action = canvas.redoStack.pop()
  case action.kind
  of cakCreate:
    let index = max(0, min(action.index, canvas.circles.len))
    canvas.circles.insert(action.circle, index)
    canvas.selectedIndex = index
  of cakResize:
    if action.index in 0 ..< canvas.circles.len:
      canvas.circles[action.index].diameter = action.afterDiameter
      canvas.selectedIndex = action.index
  canvas.undoStack.add action
  canvas.updateHistoryButtons()
  canvas.needsDisplay = true

proc openDiameterEditor(canvas: CircleCanvas) =
  let index = canvas.selectedIndex
  if index notin 0 ..< canvas.circles.len:
    return

  let
    app = sharedApplication()
    adjustWindow = newWindow("Adjust Diameter", frame = rect(180, 180, 320, 160))
    root = newView()
    layout = newStackView(laVertical)
    valueLabel = newStatusLabel("")
    slider = newSlider(MinDiameter, MaxDiameter, canvas.circles[index].diameter)
    doneButton = newButton("Done")
    startDiameter = canvas.circles[index].diameter
    changeAction = actionSelector("sevenGuiCircleDiameterChanged")
    doneAction = actionSelector("sevenGuiCircleDiameterDone")

  proc updateLabel() =
    valueLabel.text = "Diameter: " & $int(round(slider.value))

  proc updateDiameter(sender: DynamicAgent) =
    discard sender
    if index in 0 ..< canvas.circles.len:
      canvas.circles[index].diameter = slider.value
      canvas.needsDisplay = true
      updateLabel()

  proc finishDiameterEdit(sender: DynamicAgent) =
    discard sender
    if index in 0 ..< canvas.circles.len:
      let finishDiameter = canvas.circles[index].diameter
      if abs(finishDiameter - startDiameter) > 0.01'f32:
        canvas.pushHistory(
          CircleAction(
            kind: cakResize,
            index: index,
            beforeDiameter: startDiameter,
            afterDiameter: finishDiameter,
          )
        )
    adjustWindow.close()

  slider.target = newActionTarget(changeAction, updateDiameter)
  slider.action = changeAction
  doneButton.target = newActionTarget(doneAction, finishDiameterEdit)
  doneButton.action = doneAction

  layout.spacing = 14.0
  layout.alignment = svaFill
  layout.addArrangedSubview(valueLabel, slider, doneButton)
  root.addSubview(layout)
  layout.pinEdges(
    toGuide = root.contentLayoutGuide(insets(24.0, 28.0, 0.0, 28.0)),
    edges = {leLeft, leTop, leRight},
  )

  updateLabel()
  discard app.showWindow(adjustWindow, root, slider)

let
  app = sharedApplication()
  window = newWindow("7GUIs Circle Drawer", frame = rect(140, 140, 560, 420))
  root = newView()
  title = newTitleLabel("Circle Drawer")
  toolbar = newStackView(laHorizontal)
  undoButton = newButton("Undo")
  redoButton = newButton("Redo")
  canvas = newCircleCanvas()
  status = newStatusLabel(
    "Left-click to add a circle. Right-click a selected circle to adjust it."
  )
  undoAction = actionSelector("sevenGuiCircleUndo")
  redoAction = actionSelector("sevenGuiCircleRedo")
  adjustAction = actionSelector("sevenGuiCircleAdjust")
  contextMenu = newMenu("Circle")
  adjustItem = newMenuItem("Adjust diameter..", adjustAction)

canvas.undoButton = undoButton
canvas.redoButton = redoButton
canvas.adjustItem = adjustItem
adjustItem.target = newActionTarget(
  adjustAction,
  proc(sender: DynamicAgent) =
    canvas.openDiameterEditor(),
)
discard contextMenu.addItem(adjustItem)
canvas.menu = contextMenu
undoButton.target = newActionTarget(
  undoAction,
  proc(sender: DynamicAgent) =
    canvas.undoLast(),
)
undoButton.action = undoAction
redoButton.target = newActionTarget(
  redoAction,
  proc(sender: DynamicAgent) =
    canvas.redoLast(),
)
redoButton.action = redoAction
canvas.updateHistoryButtons()

toolbar.spacing = 8.0
toolbar.alignment = svaFill
toolbar.addArrangedSubview(undoButton, redoButton)

root.addSubviews(autoNames(title, toolbar, canvas, status))
activateConstraints:
  title[atTop] == root[atTop] + 22.0
  title[atLeft] == root[atLeft] + 28.0
  title[atRight] == root[atRight] - 28.0
  title[atHeight] == 30.0
  toolbar[atTop] == title[atBottom] + 12.0
  toolbar[atLeft] == title[atLeft]
  toolbar[atWidth] == 180.0
  toolbar[atHeight] == 34.0
  canvas[atTop] == toolbar[atBottom] + 12.0
  canvas[atLeft] == title[atLeft]
  canvas[atRight] == title[atRight]
  canvas[atBottom] == status[atTop] - 12.0
  status[atLeft] == title[atLeft]
  status[atRight] == title[atRight]
  status[atHeight] == 28.0
  status[atBottom] == root[atBottom] - 22.0

app.runWindow(window, root, canvas)
