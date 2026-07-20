import std/[math, os]

import merenda/nimkit

import sigils/selectors

const
  CanvasDemoWidth = 960.0'f32
  CanvasDemoHeight = 680.0'f32
  MinimumGestureSize = 2.0'f32
  StampSize = 56.0'f32

type
  CanvasTool* = enum
    ctFreehand
    ctLine
    ctRectangle
    ctEllipse
    ctStar
    ctImageStamp

  CanvasDrawingView* = ref object of CanvasView
    xSelectedTool: CanvasTool
    xFillColor: Color
    xLineWidth: float32
    xStampImage: ImageResource
    xDragging: bool
    xStartPoint: Point
    xPoints: seq[Point]
    xOperationStart: int
    xUndoCheckpoints: seq[int]
    xStatusLabel: Label
    xUndoButton: Button

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
    clearButton*: Button
    toolButtons*: array[CanvasTool, Button]

func toolName*(tool: CanvasTool): string =
  case tool
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

proc selectedTool*(canvas: CanvasDrawingView): CanvasTool =
  canvas.xSelectedTool

proc `selectedTool=`*(canvas: CanvasDrawingView, tool: CanvasTool) =
  if canvas.xSelectedTool == tool:
    return
  if canvas.xDragging:
    canvas.getContext2D().truncateOperations(canvas.xOperationStart)
    canvas.xDragging = false
  canvas.xSelectedTool = tool
  if not canvas.xStatusLabel.isNil:
    canvas.xStatusLabel.text = tool.toolName & " selected"

proc fillColor*(canvas: CanvasDrawingView): Color =
  canvas.xFillColor

proc `fillColor=`*(canvas: CanvasDrawingView, value: Color) =
  canvas.xFillColor = value

proc drawingLineWidth*(canvas: CanvasDrawingView): float32 =
  canvas.xLineWidth

proc `drawingLineWidth=`*(canvas: CanvasDrawingView, value: float32) =
  canvas.xLineWidth = max(value, 1.0'f32)

proc operationCount*(canvas: CanvasDrawingView): int =
  canvas.getContext2D().len

proc updateUndoButton(canvas: CanvasDrawingView) =
  if not canvas.xUndoButton.isNil:
    canvas.xUndoButton.enabled = canvas.xUndoCheckpoints.len > 0

proc reportStatus(canvas: CanvasDrawingView, message: string) =
  if not canvas.xStatusLabel.isNil:
    canvas.xStatusLabel.text =
      message & " · " & $canvas.operationCount & " retained operation" &
      (if canvas.operationCount == 1: "" else: "s")

proc configureContext(canvas: CanvasDrawingView) =
  let context = canvas.getContext2D()
  context.fillStyle = canvas.xFillColor
  context.strokeStyle = color(0.10, 0.14, 0.20, 1.0)
  context.lineWidth = canvas.xLineWidth
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

proc drawGesture(canvas: CanvasDrawingView, stop: Point, committed: bool) =
  let
    context = canvas.getContext2D()
    bounds = normalizedDrawingRect(canvas.xStartPoint, stop)
  context.truncateOperations(canvas.xOperationStart)
  canvas.configureContext()

  case canvas.xSelectedTool
  of ctFreehand:
    if canvas.xPoints.len < 2:
      return
    context.beginPath()
    context.moveTo(canvas.xPoints[0].x, canvas.xPoints[0].y)
    for index in 1 ..< canvas.xPoints.len:
      context.lineTo(canvas.xPoints[index].x, canvas.xPoints[index].y)
    context.stroke()
  of ctLine:
    if canvas.xStartPoint.pointDistance(stop) < MinimumGestureSize:
      return
    context.beginPath()
    context.moveTo(canvas.xStartPoint.x, canvas.xStartPoint.y)
    context.lineTo(stop.x, stop.y)
    context.stroke()
  of ctRectangle:
    if bounds.size.width < MinimumGestureSize or bounds.size.height < MinimumGestureSize:
      return
    context.beginPath()
    context.roundRect(
      bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height, 5.0
    )
    if committed:
      context.fill()
    context.stroke()
  of ctEllipse:
    if bounds.size.width < MinimumGestureSize or bounds.size.height < MinimumGestureSize:
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
    if bounds.size.width < MinimumGestureSize or bounds.size.height < MinimumGestureSize:
      return
    context.beginPath()
    context.appendStarPath(bounds)
    if committed:
      context.fill(cfrEvenOdd)
    context.stroke()
  of ctImageStamp:
    discard

proc commitGesture(canvas: CanvasDrawingView, name: string) =
  if canvas.operationCount <= canvas.xOperationStart:
    canvas.reportStatus("Gesture was too small")
    return
  canvas.xUndoCheckpoints.add canvas.xOperationStart
  canvas.updateUndoButton()
  canvas.reportStatus(name & " added")

proc placeImage(canvas: CanvasDrawingView, point: Point) =
  if canvas.xStampImage.isNil:
    canvas.reportStatus("Image stamp is unavailable")
    return
  canvas.configureContext()
  canvas.getContext2D().drawImage(
    canvas.xStampImage,
    point.x - StampSize * 0.5'f32,
    point.y - StampSize * 0.5'f32,
    StampSize,
    StampSize,
  )
  canvas.commitGesture("Image")

proc undoLast*(canvas: CanvasDrawingView) =
  if canvas.xDragging:
    canvas.getContext2D().truncateOperations(canvas.xOperationStart)
    canvas.xDragging = false
  if canvas.xUndoCheckpoints.len == 0:
    return
  canvas.getContext2D().truncateOperations(canvas.xUndoCheckpoints.pop())
  canvas.updateUndoButton()
  canvas.reportStatus("Undid last mark")

proc clearCanvas*(canvas: CanvasDrawingView) =
  canvas.xDragging = false
  canvas.xUndoCheckpoints.setLen(0)
  canvas.getContext2D().clear()
  canvas.updateUndoButton()
  canvas.reportStatus("Canvas cleared")

protocol CanvasDrawingEvents of ResponderEventProtocol:
  method mouseDown(canvas: CanvasDrawingView, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false
    canvas.xOperationStart = canvas.operationCount
    canvas.xStartPoint = event.location
    canvas.xPoints = @[event.location]
    canvas.xDragging = canvas.xSelectedTool != ctImageStamp
    if canvas.xSelectedTool == ctImageStamp:
      canvas.placeImage(event.location)
    true

  method mouseDragged(canvas: CanvasDrawingView, event: MouseEvent): bool =
    if event.button != mbPrimary or not canvas.xDragging:
      return false
    if canvas.xSelectedTool == ctFreehand and
        canvas.xPoints[^1].pointDistance(event.location) >= 1.0'f32:
      canvas.xPoints.add event.location
    canvas.drawGesture(event.location, committed = false)
    true

  method mouseUp(canvas: CanvasDrawingView, event: MouseEvent): bool =
    if event.button != mbPrimary or not canvas.xDragging:
      return false
    if canvas.xSelectedTool == ctFreehand and
        canvas.xPoints[^1].pointDistance(event.location) >= 1.0'f32:
      canvas.xPoints.add event.location
    canvas.drawGesture(event.location, committed = true)
    canvas.xDragging = false
    canvas.commitGesture(canvas.xSelectedTool.toolName)
    true

  method keyDown(canvas: CanvasDrawingView, event: KeyEvent): bool =
    if event.key == keyEscape and canvas.xDragging:
      canvas.getContext2D().truncateOperations(canvas.xOperationStart)
      canvas.xDragging = false
      canvas.reportStatus("Gesture cancelled")
      return true
    if event.key == keyZ and event.modifiers * {kmCommand, kmControl} != {}:
      canvas.undoLast()
      return true
    false

proc newCanvasDrawingView*(stampImage: ImageResource): CanvasDrawingView =
  result = CanvasDrawingView(
    xFillColor: color(0.22, 0.56, 0.88, 0.78),
    xLineWidth: 3.0'f32,
    xStampImage: stampImage,
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
  result.clearButton = newButton("Clear")

  let
    title = newTitleLabel("Retained Canvas 2D")
    subtitle = newStatusLabel(
      "Choose a tool, then drag. Primitives stay FigDraw drawables; filled paths become MTSDFs."
    )
    toolRow = newStackView(laHorizontal)
    optionRow = newStackView(laHorizontal)
    fillLabel = newStatusLabel("Fill")
    widthTitle = newStatusLabel("Stroke")
    toolAction = actionSelector("canvasDemoSelectTool")
    fillAction = actionSelector("canvasDemoFillColor")
    widthAction = actionSelector("canvasDemoLineWidth")
    undoAction = actionSelector("canvasDemoUndo")
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
    result.undoButton, result.clearButton,
  )

  for view in [
    fillLabel, widthTitle, result.widthLabel, result.undoButton, result.clearButton
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
  result.window.setContentView(result.root)
  result.selectTool(ctFreehand)
  result.updateLineWidth()
  result.canvas.updateUndoButton()

proc showCanvasDemo*(demo: CanvasDemo) =
  if not demo.isNil:
    discard demo.app.showWindow(demo.window, demo.root, demo.canvas)

when isMainModule:
  let demo = newCanvasDemo(sharedApplication())
  demo.app.runWindow(demo.window, demo.root, demo.canvas)
