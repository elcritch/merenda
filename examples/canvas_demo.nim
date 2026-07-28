import std/[math, os]

import merenda/nimkit

import sigils/selectors

const
  CanvasDemoWidth = 960.0'f32
  CanvasDemoHeight = 680.0'f32
  HitTolerance = 6.0'f32
  MinimumGestureSize = 2.0'f32
  SelectionPadding = 5.0'f32
  StampSize = 56.0'f32

type
  CanvasTool* = enum
    ctSelect
    ctFreehand
    ctLine
    ctRectangle
    ctEllipse
    ctStar
    ctImageStamp

  CanvasItem = object
    tool: CanvasTool
    fillColor: Color
    lineWidth: float32
    startPoint: Point
    stopPoint: Point
    points: seq[Point]

  CanvasDrawingView* = ref object of CanvasView
    xSelectedTool: CanvasTool
    xFillColor: Color
    xLineWidth: float32
    xStampImage: ImageResource
    xItems: seq[CanvasItem]
    xSelectedItem: int
    xDragging: bool
    xStartPoint: Point
    xPoints: seq[Point]
    xDragOriginal: CanvasItem
    xGestureStartItems: seq[CanvasItem]
    xSelectionStart: int
    xUndoStates: seq[seq[CanvasItem]]
    xStatusLabel: Label
    xUndoButton: Button
    xDeleteButton: Button
    xFillWell: ColorWell
    xWidthSlider: Slider
    xWidthLabel: Label

  CanvasDemo* = ref object of Responder
    app*: Application
    window*: Window
    root*: View
    canvas*: CanvasDrawingView
    statusLabel*: Label
    fillWell*: ColorWell
    widthSlider*: Slider
    widthLabel*: Label
    undoButton*: Button
    deleteButton*: Button
    clearButton*: Button
    toolButtons*: array[CanvasTool, Button]

func toolName*(tool: CanvasTool): string =
  case tool
  of ctSelect: "Select"
  of ctFreehand: "Pencil"
  of ctLine: "Line"
  of ctRectangle: "Rectangle"
  of ctEllipse: "Ellipse"
  of ctStar: "Star"
  of ctImageStamp: "Image"

func normalizedDrawingRect(start, stop: Point): Rect =
  rect(
    min(start.x, stop.x),
    min(start.y, stop.y),
    abs(stop.x - start.x),
    abs(stop.y - start.y),
  )

func pointDistance(left, right: Point): float32 =
  let
    deltaX = right.x - left.x
    deltaY = right.y - left.y
  sqrt(deltaX * deltaX + deltaY * deltaY)

func cloneItem(item: CanvasItem): CanvasItem =
  result = item
  result.points = newSeqOfCap[Point](item.points.len)
  for point in item.points:
    result.points.add point

func cloneItems(items: openArray[CanvasItem]): seq[CanvasItem] =
  result = newSeqOfCap[CanvasItem](items.len)
  for item in items:
    result.add item.cloneItem()

func validItemIndex(canvas: CanvasDrawingView, index: int): bool =
  index in 0 ..< canvas.xItems.len

func itemBounds(item: CanvasItem): Rect =
  if item.tool == ctImageStamp:
    return rect(
      item.startPoint.x - StampSize * 0.5'f32,
      item.startPoint.y - StampSize * 0.5'f32,
      StampSize,
      StampSize,
    )
  if item.tool == ctFreehand:
    if item.points.len == 0:
      return rect(0, 0, 0, 0)
    var
      minX = item.points[0].x
      minY = item.points[0].y
      maxX = minX
      maxY = minY
    for point in item.points:
      minX = min(minX, point.x)
      minY = min(minY, point.y)
      maxX = max(maxX, point.x)
      maxY = max(maxY, point.y)
    return rect(minX, minY, maxX - minX, maxY - minY)
  normalizedDrawingRect(item.startPoint, item.stopPoint)

func expanded(value: Rect, amount: float32): Rect =
  rect(
    value.origin.x - amount,
    value.origin.y - amount,
    value.size.width + amount * 2.0'f32,
    value.size.height + amount * 2.0'f32,
  )

func distanceFromSegment(point, start, stop: Point): float32 =
  let
    dx = stop.x - start.x
    dy = stop.y - start.y
    lengthSquared = dx * dx + dy * dy
  if lengthSquared == 0.0'f32:
    return point.pointDistance(start)
  let position = min(
    max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0.0), 1.0
  )
  point.pointDistance(initPoint(start.x + dx * position, start.y + dy * position))

func contains(item: CanvasItem, point: Point): bool =
  let tolerance = max(HitTolerance, item.lineWidth * 0.5'f32)
  case item.tool
  of ctSelect:
    false
  of ctFreehand:
    for index in 1 ..< item.points.len:
      if point.distanceFromSegment(item.points[index - 1], item.points[index]) <=
          tolerance:
        return true
    false
  of ctLine:
    point.distanceFromSegment(item.startPoint, item.stopPoint) <= tolerance
  of ctRectangle, ctStar, ctImageStamp:
    item.itemBounds().expanded(tolerance).contains(point)
  of ctEllipse:
    let bounds = item.itemBounds().expanded(tolerance)
    if bounds.size.width <= 0.0'f32 or bounds.size.height <= 0.0'f32:
      return false
    let
      radiusX = bounds.size.width * 0.5'f32
      radiusY = bounds.size.height * 0.5'f32
      centerX = bounds.origin.x + radiusX
      centerY = bounds.origin.y + radiusY
      normalizedX = (point.x - centerX) / radiusX
      normalizedY = (point.y - centerY) / radiusY
    normalizedX * normalizedX + normalizedY * normalizedY <= 1.0'f32

func translated(item: CanvasItem, dx, dy: float32): CanvasItem =
  result = item.cloneItem()
  result.startPoint = result.startPoint.offset(dx, dy)
  result.stopPoint = result.stopPoint.offset(dx, dy)
  for point in result.points.mitems:
    point = point.offset(dx, dy)

proc cancelGesture(canvas: CanvasDrawingView)
proc pushUndo(canvas: CanvasDrawingView, state: openArray[CanvasItem])
proc redrawCanvas(canvas: CanvasDrawingView)
proc reportStatus(canvas: CanvasDrawingView, message: string)
proc syncSelectionControls(canvas: CanvasDrawingView)
proc updateEditingButtons(canvas: CanvasDrawingView)

proc selectedTool*(canvas: CanvasDrawingView): CanvasTool =
  canvas.xSelectedTool

proc `selectedTool=`*(canvas: CanvasDrawingView, tool: CanvasTool) =
  if canvas.xSelectedTool == tool:
    return
  if canvas.xDragging:
    canvas.cancelGesture()
  canvas.xSelectedTool = tool
  if tool != ctSelect:
    canvas.xSelectedItem = -1
    canvas.redrawCanvas()
    canvas.syncSelectionControls()
    canvas.updateEditingButtons()
  if not canvas.xStatusLabel.isNil:
    canvas.xStatusLabel.text = tool.toolName & " selected"

proc fillColor*(canvas: CanvasDrawingView): Color =
  canvas.xFillColor

proc `fillColor=`*(canvas: CanvasDrawingView, value: Color) =
  canvas.xFillColor = value
  if canvas.validItemIndex(canvas.xSelectedItem) and
      canvas.xItems[canvas.xSelectedItem].fillColor != value:
    let before = canvas.xItems.cloneItems()
    canvas.xItems[canvas.xSelectedItem].fillColor = value
    canvas.pushUndo(before)
    canvas.redrawCanvas()
    canvas.reportStatus("Selected item recolored")

proc drawingLineWidth*(canvas: CanvasDrawingView): float32 =
  canvas.xLineWidth

proc `drawingLineWidth=`*(canvas: CanvasDrawingView, value: float32) =
  let lineWidth = max(value, 1.0'f32)
  canvas.xLineWidth = lineWidth
  if canvas.validItemIndex(canvas.xSelectedItem) and
      canvas.xItems[canvas.xSelectedItem].lineWidth != lineWidth:
    let before = canvas.xItems.cloneItems()
    canvas.xItems[canvas.xSelectedItem].lineWidth = lineWidth
    canvas.pushUndo(before)
    canvas.redrawCanvas()
    canvas.reportStatus("Selected stroke changed")

proc operationCount*(canvas: CanvasDrawingView): int =
  canvas.getContext2D().len

proc itemCount*(canvas: CanvasDrawingView): int =
  canvas.xItems.len

proc selectedItemIndex*(canvas: CanvasDrawingView): int =
  canvas.xSelectedItem

proc selectedItemBounds*(canvas: CanvasDrawingView): Rect =
  if canvas.validItemIndex(canvas.xSelectedItem):
    canvas.xItems[canvas.xSelectedItem].itemBounds()
  else:
    rect(0, 0, 0, 0)

proc updateEditingButtons(canvas: CanvasDrawingView) =
  if not canvas.xUndoButton.isNil:
    canvas.xUndoButton.enabled = canvas.xUndoStates.len > 0
  if not canvas.xDeleteButton.isNil:
    canvas.xDeleteButton.enabled = canvas.validItemIndex(canvas.xSelectedItem)

proc reportStatus(canvas: CanvasDrawingView, message: string) =
  if not canvas.xStatusLabel.isNil:
    canvas.xStatusLabel.text =
      message & " · " & $canvas.itemCount & " item" &
      (if canvas.itemCount == 1: "" else: "s") & " · " & $canvas.operationCount &
      " retained operation" & (if canvas.operationCount == 1: "" else: "s")

proc configureContext(canvas: CanvasDrawingView, item: CanvasItem) =
  let context = canvas.getContext2D()
  context.fillStyle = item.fillColor
  context.strokeStyle = color(
    item.fillColor.r * 0.45'f32,
    item.fillColor.g * 0.45'f32,
    item.fillColor.b * 0.45'f32,
    1.0,
  )
  context.lineWidth = item.lineWidth
  context.lineCap = clcRound
  context.lineJoin = cljRound

proc appendStarPath(context: CanvasRenderingContext2D, bounds: Rect) =
  let
    center = initPoint(
      bounds.origin.x + bounds.size.width * 0.5'f32,
      bounds.origin.y + bounds.size.height * 0.5'f32,
    )
    outerRadius = min(bounds.size.width, bounds.size.height) * 0.5'f32
    innerRadius = outerRadius * 0.43'f32
  for index in 0 ..< 10:
    let
      radius = if index mod 2 == 0: outerRadius else: innerRadius
      angle = -PI.float32 * 0.5'f32 + index.float32 * PI.float32 / 5.0'f32
      point = initPoint(center.x + cos(angle) * radius, center.y + sin(angle) * radius)
    if index == 0:
      context.moveTo(point.x, point.y)
    else:
      context.lineTo(point.x, point.y)
  context.closePath()

func isValid(item: CanvasItem): bool =
  case item.tool
  of ctSelect:
    false
  of ctFreehand:
    item.points.len >= 2
  of ctLine:
    item.startPoint.pointDistance(item.stopPoint) >= MinimumGestureSize
  of ctRectangle, ctEllipse, ctStar:
    let bounds = item.itemBounds()
    bounds.size.width >= MinimumGestureSize and bounds.size.height >= MinimumGestureSize
  of ctImageStamp:
    true

proc drawItem(canvas: CanvasDrawingView, item: CanvasItem, committed = true) =
  let
    context = canvas.getContext2D()
    bounds = item.itemBounds()
  canvas.configureContext(item)

  case item.tool
  of ctSelect:
    discard
  of ctFreehand:
    if item.points.len < 2:
      return
    context.beginPath()
    context.moveTo(item.points[0].x, item.points[0].y)
    for index in 1 ..< item.points.len:
      context.lineTo(item.points[index].x, item.points[index].y)
    context.stroke()
  of ctLine:
    if not item.isValid():
      return
    context.beginPath()
    context.moveTo(item.startPoint.x, item.startPoint.y)
    context.lineTo(item.stopPoint.x, item.stopPoint.y)
    context.stroke()
  of ctRectangle:
    if not item.isValid():
      return
    context.beginPath()
    context.roundRect(
      bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height, 5.0
    )
    if committed:
      context.fill()
    context.stroke()
  of ctEllipse:
    if not item.isValid():
      return
    context.beginPath()
    context.ellipse(
      bounds.origin.x + bounds.size.width * 0.5'f32,
      bounds.origin.y + bounds.size.height * 0.5'f32,
      bounds.size.width * 0.5'f32,
      bounds.size.height * 0.5'f32,
      0.0,
      0.0,
      PI.float32 * 2.0'f32,
    )
    if committed:
      context.fill()
    context.stroke()
  of ctStar:
    if not item.isValid():
      return
    context.beginPath()
    context.appendStarPath(bounds)
    if committed:
      context.fill(cfrEvenOdd)
    context.stroke()
  of ctImageStamp:
    if not canvas.xStampImage.isNil:
      context.drawImage(
        canvas.xStampImage, bounds.origin.x, bounds.origin.y, bounds.size.width,
        bounds.size.height,
      )

proc drawSelection(canvas: CanvasDrawingView) =
  if not canvas.validItemIndex(canvas.xSelectedItem):
    return
  let
    context = canvas.getContext2D()
    bounds = canvas.xItems[canvas.xSelectedItem].itemBounds().expanded(SelectionPadding)
  context.strokeStyle = color(0.20, 0.48, 0.92, 1.0)
  context.lineWidth = 1.5'f32
  context.beginPath()
  context.roundRect(
    bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height, 3.0
  )
  context.stroke()

proc redrawCanvas(canvas: CanvasDrawingView) =
  canvas.getContext2D().clear()
  for item in canvas.xItems:
    canvas.drawItem(item)
  canvas.drawSelection()

proc redrawCanvas(canvas: CanvasDrawingView, preview: CanvasItem, committed: bool) =
  canvas.getContext2D().clear()
  for item in canvas.xItems:
    canvas.drawItem(item)
  canvas.drawItem(preview, committed)

proc currentItem(canvas: CanvasDrawingView, stop: Point): CanvasItem =
  CanvasItem(
    tool: canvas.xSelectedTool,
    fillColor: canvas.xFillColor,
    lineWidth: canvas.xLineWidth,
    startPoint: canvas.xStartPoint,
    stopPoint: stop,
    points: canvas.xPoints,
  )

proc pushUndo(canvas: CanvasDrawingView, state: openArray[CanvasItem]) =
  canvas.xUndoStates.add state.cloneItems()
  canvas.updateEditingButtons()

proc syncSelectionControls(canvas: CanvasDrawingView) =
  if canvas.validItemIndex(canvas.xSelectedItem):
    let item = canvas.xItems[canvas.xSelectedItem]
    canvas.xFillColor = item.fillColor
    canvas.xLineWidth = item.lineWidth
    if not canvas.xFillWell.isNil:
      canvas.xFillWell.color = item.fillColor
    if not canvas.xWidthSlider.isNil:
      canvas.xWidthSlider.value = item.lineWidth
    if not canvas.xWidthLabel.isNil:
      canvas.xWidthLabel.text = $int(round(item.lineWidth)) & " px"

proc itemAt(canvas: CanvasDrawingView, point: Point): int =
  if canvas.xItems.len > 0:
    for index in countdown(canvas.xItems.high, 0):
      if canvas.xItems[index].contains(point):
        return index
  -1

proc selectItem(canvas: CanvasDrawingView, index: int) =
  canvas.xSelectedItem = if canvas.validItemIndex(index): index else: -1
  canvas.syncSelectionControls()
  canvas.updateEditingButtons()
  canvas.redrawCanvas()
  if canvas.xSelectedItem >= 0:
    canvas.reportStatus(canvas.xItems[canvas.xSelectedItem].tool.toolName & " selected")
  else:
    canvas.reportStatus("Selection cleared")

proc placeImage(canvas: CanvasDrawingView, point: Point) =
  if canvas.xStampImage.isNil:
    canvas.reportStatus("Image stamp is unavailable")
    return
  let item = CanvasItem(
    tool: ctImageStamp,
    fillColor: canvas.xFillColor,
    lineWidth: canvas.xLineWidth,
    startPoint: point,
  )
  canvas.pushUndo(canvas.xItems)
  canvas.xItems.add item
  canvas.redrawCanvas()
  canvas.reportStatus("Image added")

proc undoLast*(canvas: CanvasDrawingView) =
  if canvas.xDragging:
    canvas.cancelGesture()
  if canvas.xUndoStates.len == 0:
    return
  canvas.xItems = canvas.xUndoStates.pop()
  canvas.xSelectedItem = -1
  canvas.syncSelectionControls()
  canvas.updateEditingButtons()
  canvas.redrawCanvas()
  canvas.reportStatus("Undid last edit")

proc deleteSelection*(canvas: CanvasDrawingView) =
  if canvas.xDragging:
    canvas.cancelGesture()
  if not canvas.validItemIndex(canvas.xSelectedItem):
    return
  let deletedName = canvas.xItems[canvas.xSelectedItem].tool.toolName
  canvas.pushUndo(canvas.xItems)
  canvas.xItems.delete(canvas.xSelectedItem)
  canvas.xSelectedItem = -1
  canvas.updateEditingButtons()
  canvas.redrawCanvas()
  canvas.reportStatus(deletedName & " deleted")

proc clearCanvas*(canvas: CanvasDrawingView) =
  if canvas.xDragging:
    canvas.cancelGesture()
  if canvas.xItems.len == 0:
    return
  canvas.pushUndo(canvas.xItems)
  canvas.xItems.setLen(0)
  canvas.xSelectedItem = -1
  canvas.updateEditingButtons()
  canvas.redrawCanvas()
  canvas.reportStatus("Canvas cleared")

proc cancelGesture(canvas: CanvasDrawingView) =
  if not canvas.xDragging:
    return
  canvas.xItems = canvas.xGestureStartItems.cloneItems()
  canvas.xSelectedItem = canvas.xSelectionStart
  canvas.xDragging = false
  canvas.syncSelectionControls()
  canvas.updateEditingButtons()
  canvas.redrawCanvas()
  canvas.reportStatus("Edit cancelled")

protocol CanvasDrawingEvents of ResponderEventProtocol:
  method mouseDown(canvas: CanvasDrawingView, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false

    if canvas.xSelectedTool == ctSelect:
      canvas.selectItem(canvas.itemAt(event.location))
      if canvas.validItemIndex(canvas.xSelectedItem):
        canvas.xGestureStartItems = canvas.xItems.cloneItems()
        canvas.xSelectionStart = canvas.xSelectedItem
        canvas.xDragOriginal = canvas.xItems[canvas.xSelectedItem].cloneItem()
        canvas.xStartPoint = event.location
        canvas.xDragging = true
      return true

    canvas.xSelectedItem = -1
    canvas.updateEditingButtons()
    canvas.xGestureStartItems = canvas.xItems.cloneItems()
    canvas.xSelectionStart = -1
    canvas.xStartPoint = event.location
    canvas.xPoints = @[event.location]
    canvas.xDragging = canvas.xSelectedTool != ctImageStamp
    if canvas.xSelectedTool == ctImageStamp:
      canvas.placeImage(event.location)
    true

  method mouseDragged(canvas: CanvasDrawingView, event: MouseEvent): bool =
    if event.button != mbPrimary or not canvas.xDragging:
      return false
    if canvas.xSelectedTool == ctSelect:
      let
        dx = event.location.x - canvas.xStartPoint.x
        dy = event.location.y - canvas.xStartPoint.y
      canvas.xItems[canvas.xSelectedItem] = canvas.xDragOriginal.translated(dx, dy)
      canvas.redrawCanvas()
      canvas.reportStatus("Moving selected item")
      return true
    if canvas.xSelectedTool == ctFreehand and
        canvas.xPoints[^1].pointDistance(event.location) >= 1.0'f32:
      canvas.xPoints.add event.location
    canvas.redrawCanvas(canvas.currentItem(event.location), committed = false)
    true

  method mouseUp(canvas: CanvasDrawingView, event: MouseEvent): bool =
    if event.button != mbPrimary or not canvas.xDragging:
      return false
    if canvas.xSelectedTool == ctSelect:
      let
        moved = canvas.xStartPoint.pointDistance(event.location) >= MinimumGestureSize
        dx = event.location.x - canvas.xStartPoint.x
        dy = event.location.y - canvas.xStartPoint.y
      canvas.xItems[canvas.xSelectedItem] = canvas.xDragOriginal.translated(dx, dy)
      canvas.xDragging = false
      if moved:
        canvas.redrawCanvas()
        canvas.pushUndo(canvas.xGestureStartItems)
        canvas.reportStatus("Selected item moved")
      else:
        canvas.xItems[canvas.xSelectedItem] = canvas.xDragOriginal.cloneItem()
        canvas.redrawCanvas()
        canvas.reportStatus(
          canvas.xItems[canvas.xSelectedItem].tool.toolName & " selected"
        )
      return true
    if canvas.xSelectedTool == ctFreehand and
        canvas.xPoints[^1].pointDistance(event.location) >= 1.0'f32:
      canvas.xPoints.add event.location
    let item = canvas.currentItem(event.location)
    canvas.xDragging = false
    if item.isValid():
      canvas.pushUndo(canvas.xGestureStartItems)
      canvas.xItems.add item
      canvas.redrawCanvas()
      canvas.reportStatus(canvas.xSelectedTool.toolName & " added")
    else:
      canvas.redrawCanvas()
      canvas.reportStatus("Gesture was too small")
    true

  method keyDown(canvas: CanvasDrawingView, event: KeyEvent): bool =
    if event.key == keyEscape and canvas.xDragging:
      canvas.cancelGesture()
      return true
    if event.key == keyZ and event.modifiers * {kmCommand, kmControl} != {}:
      canvas.undoLast()
      return true
    if event.key in {keyBackspace, keyDelete} and
        canvas.validItemIndex(canvas.xSelectedItem):
      canvas.deleteSelection()
      return true
    false

proc newCanvasDrawingView*(stampImage: ImageResource): CanvasDrawingView =
  result = CanvasDrawingView(
    xFillColor: color(0.22, 0.56, 0.88, 0.78),
    xLineWidth: 3.0'f32,
    xStampImage: stampImage,
    xSelectedItem: -1,
  )
  result.initCanvasViewFields()
  result.backgroundColor = color(0.985, 0.99, 1.0, 1.0)
  result.accessibilityLabel = "Interactive drawing canvas"
  result.acceptsFirstResponder = true
  discard result.withProtocol(CanvasDrawingEvents)

proc selectTool(demo: CanvasDemo, tool: CanvasTool) =
  demo.canvas.selectedTool = tool
  for candidate, button in demo.toolButtons.mpairs:
    button.state = if candidate == tool: bsOn else: bsOff

proc updateLineWidth(demo: CanvasDemo) =
  demo.canvas.drawingLineWidth = demo.widthSlider.value
  demo.widthLabel.text = $int(round(demo.widthSlider.value)) & " px"

proc toolDidSend(demo: CanvasDemo, sender: DynamicAgent) =
  for tool, button in demo.toolButtons:
    if sender == DynamicAgent(button):
      demo.selectTool(tool)
      return

proc newCanvasDemo*(app = newApplication()): CanvasDemo =
  result = CanvasDemo(app: app)
  initResponder(result)

  let imagePath = currentSourcePath.parentDir.parentDir / "data" / "img1.png"
  var stampImage: ImageResource
  try:
    stampImage = newImageResourceFromFile(
      imagePath, name = "Canvas image stamp", cachePolicy = icpAlways
    )
  except CatchableError:
    discard

  result.window = newWindow(
    "NimKit Canvas 2D", frame = rect(120, 90, CanvasDemoWidth, CanvasDemoHeight)
  )
  result.root = newView(frame = rect(0, 0, CanvasDemoWidth, CanvasDemoHeight))
  result.canvas = newCanvasDrawingView(stampImage)
  result.statusLabel = newStatusLabel("Pencil selected · drag on the canvas to draw")
  result.fillWell = newColorWell(result.canvas.fillColor)
  result.widthSlider = newSlider(1.0, 14.0, result.canvas.drawingLineWidth)
  result.widthLabel = newStatusLabel("3 px")
  result.undoButton = newButton("Undo")
  result.deleteButton = newButton("Delete")
  result.clearButton = newButton("Clear")

  let
    title = newTitleLabel("Editable Retained Canvas 2D")
    subtitle = newStatusLabel(
      "Draw items, then use Select to move, recolor, change stroke width, or delete them."
    )
    toolRow = newStackView(laHorizontal)
    optionRow = newStackView(laHorizontal)
    fillLabel = newStatusLabel("Color")
    widthTitle = newStatusLabel("Stroke")
    toolAction = actionSelector("canvasDemoSelectTool")
    fillAction = actionSelector("canvasDemoFillColor")
    widthAction = actionSelector("canvasDemoLineWidth")
    undoAction = actionSelector("canvasDemoUndo")
    deleteAction = actionSelector("canvasDemoDelete")
    clearAction = actionSelector("canvasDemoClear")
    demo = result

  for tool in CanvasTool:
    let button = newRadioButton(tool.toolName)
    button.target = newActionTarget(
      toolAction,
      proc(sender: DynamicAgent) =
        demo.toolDidSend(sender),
    )
    button.action = toolAction
    result.toolButtons[tool] = button
    toolRow.addArrangedSubview(button)

  result.fillWell.target = newActionTarget(
    fillAction,
    proc(sender: DynamicAgent) =
      discard sender
      demo.canvas.fillColor = demo.fillWell.color,
  )
  result.fillWell.action = fillAction
  result.widthSlider.target = newActionTarget(
    widthAction,
    proc(sender: DynamicAgent) =
      discard sender
      demo.updateLineWidth(),
  )
  result.widthSlider.action = widthAction
  result.widthSlider.stepValue = 1.0
  result.undoButton.target = newActionTarget(
    undoAction,
    proc(sender: DynamicAgent) =
      discard sender
      demo.canvas.undoLast(),
  )
  result.undoButton.action = undoAction
  result.deleteButton.target = newActionTarget(
    deleteAction,
    proc(sender: DynamicAgent) =
      discard sender
      demo.canvas.deleteSelection(),
  )
  result.deleteButton.action = deleteAction
  result.clearButton.target = newActionTarget(
    clearAction,
    proc(sender: DynamicAgent) =
      discard sender
      demo.canvas.clearCanvas(),
  )
  result.clearButton.action = clearAction

  toolRow.spacing = 8.0
  toolRow.alignment = svaCenter
  optionRow.spacing = 10.0
  optionRow.alignment = svaCenter
  optionRow.addArrangedSubview(
    fillLabel, result.fillWell, widthTitle, result.widthSlider, result.widthLabel,
    result.undoButton, result.deleteButton, result.clearButton,
  )

  for view in [
    fillLabel, widthTitle, result.widthLabel, result.undoButton, result.deleteButton,
    result.clearButton,
  ]:
    view.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
  result.fillWell.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
  result.widthSlider.setHuggingPriority(LayoutPriorityLow, laHorizontal)

  result.root.addSubviews(
    autoNames(title, subtitle, toolRow, optionRow, result.canvas, result.statusLabel)
  )
  activateConstraints:
    title[atTop] == result.root[atTop] + 18.0
    title[atLeft] == result.root[atLeft] + 24.0
    title[atRight] == result.root[atRight] - 24.0
    title[atHeight] == 30.0

    subtitle[atTop] == title[atBottom] + 4.0
    subtitle[atLeft] == title[atLeft]
    subtitle[atRight] == title[atRight]
    subtitle[atHeight] == 24.0

    toolRow[atTop] == subtitle[atBottom] + 10.0
    toolRow[atLeft] == title[atLeft]
    toolRow[atRight] == title[atRight]
    toolRow[atHeight] == 34.0

    optionRow[atTop] == toolRow[atBottom] + 8.0
    optionRow[atLeft] == title[atLeft]
    optionRow[atRight] == title[atRight]
    optionRow[atHeight] == 34.0

    result.canvas[atTop] == optionRow[atBottom] + 12.0
    result.canvas[atLeft] == title[atLeft]
    result.canvas[atRight] == title[atRight]
    result.canvas[atBottom] == result.statusLabel[atTop] - 10.0

    result.statusLabel[atLeft] == title[atLeft]
    result.statusLabel[atRight] == title[atRight]
    result.statusLabel[atHeight] == 24.0
    result.statusLabel[atBottom] == result.root[atBottom] - 18.0

  result.canvas.xStatusLabel = result.statusLabel
  result.canvas.xUndoButton = result.undoButton
  result.canvas.xDeleteButton = result.deleteButton
  result.canvas.xFillWell = result.fillWell
  result.canvas.xWidthSlider = result.widthSlider
  result.canvas.xWidthLabel = result.widthLabel
  result.window.setContentView(result.root)
  result.selectTool(ctFreehand)
  result.updateLineWidth()
  result.canvas.updateEditingButtons()

proc showCanvasDemo*(demo: CanvasDemo) =
  if not demo.isNil:
    discard demo.app.showWindow(demo.window, demo.root, demo.canvas)

when isMainModule:
  let demo = newCanvasDemo(sharedApplication())
  demo.app.runWindow(demo.window, demo.root, demo.canvas)
