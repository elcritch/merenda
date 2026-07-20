## Retained, browser-style 2D canvas drawing backed by FigDraw operations.

import std/[math, strformat, strutils]

import pkg/bumpy as bumpy
import pkg/vmath as vmath
import sigils/core

when defined(useNativeDynlib):
  import figdraw/dynlib as fd
else:
  import figdraw as fd

import ../accessibility/accessibilityprotocols
import ../drawing
import ../foundation/selectors
import ../foundation/types
import ./views

type
  CanvasContextError* = object of CatchableError
  CanvasPathError* = object of CatchableError

  CanvasLineCap* = enum
    clcButt
    clcRound
    clcSquare

  CanvasLineJoin* = enum
    cljMiter
    cljRound
    cljBevel

  CanvasFillRule* = enum
    cfrNonZero
    cfrEvenOdd

  CanvasOperationKind* = enum
    cokDrawable
    cokMtsdf
    cokImage

  CanvasOperation* = object
    target*: Rect
    case kind*: CanvasOperationKind
    of cokDrawable:
      drawOps*: seq[fd.DrawableOp]
      drawableFill*: Color
      drawableStroke*: Color
      drawableLineWidth*: float32
      drawableLineCap*: CanvasLineCap
      drawableLineJoin*: CanvasLineJoin
    of cokMtsdf:
      mtsdf*: SvgMtsdfResource
    of cokImage:
      image*: ImageResource
      imageTint*: Color

  CanvasView* = ref object of View
    xContext: CanvasRenderingContext2D

  CanvasRenderingContext2D* = ref object
    xCanvas: CanvasView
    xOperations: seq[CanvasOperation]
    xState: CanvasState
    xStateStack: seq[CanvasState]
    xPath: seq[CanvasPathCommand]
    xCurrentPoint: Point
    xSubpathStart: Point
    xHasCurrentPoint: bool

  CanvasState = object
    fillStyle: Color
    strokeStyle: Color
    globalAlpha: float32
    lineWidth: float32
    lineCap: CanvasLineCap
    lineJoin: CanvasLineJoin

  CanvasPathCommandKind = enum
    cpcMove
    cpcLine
    cpcQuadratic
    cpcBezier
    cpcArc
    cpcRectangle
    cpcEllipse
    cpcClose

  CanvasPathCommand = object
    case kind: CanvasPathCommandKind
    of cpcMove, cpcLine:
      point: Point
    of cpcQuadratic:
      quadraticControl: Point
      quadraticEnd: Point
    of cpcBezier:
      bezierControl1: Point
      bezierControl2: Point
      bezierEnd: Point
    of cpcArc:
      arcCenter: Point
      arcRadius: float32
      arcStartAngle: float32
      arcSweepAngle: float32
    of cpcRectangle:
      rectangle: Rect
      cornerRadius: float32
    of cpcEllipse:
      ellipseCenter: Point
      ellipseRadiusX: float32
      ellipseRadiusY: float32
      ellipseRotation: float32
      ellipseStartAngle: float32
      ellipseSweepAngle: float32
    of cpcClose:
      discard

  CanvasPathBounds = object
    valid: bool
    minX, minY, maxX, maxY: float32

  CanvasCubicSegment = object
    start, control1, control2, stop: Point

const
  CanvasTransparent = color(0.0, 0.0, 0.0, 0.0)
  CanvasBlack = color(0.0, 0.0, 0.0, 1.0)
  CanvasTwoPi = PI.float32 * 2.0'f32
  CanvasPathEpsilon = 0.0001'f32

proc initCanvasViewFields*(canvas: CanvasView, frame = AutoRect)

func initCanvasState(): CanvasState =
  CanvasState(
    fillStyle: CanvasBlack,
    strokeStyle: CanvasBlack,
    globalAlpha: 1.0'f32,
    lineWidth: 1.0'f32,
    lineCap: clcButt,
    lineJoin: cljMiter,
  )

func pointClose(a, b: Point): bool =
  abs(a.x - b.x) <= CanvasPathEpsilon and abs(a.y - b.y) <= CanvasPathEpsilon

func pointAt(center: Point, radius, angle: float32): Point =
  initPoint(center.x + cos(angle) * radius, center.y + sin(angle) * radius)

func normalizedRect(x, y, width, height: float32): Rect =
  rect(min(x, x + width), min(y, y + height), abs(width), abs(height))

func withGlobalAlpha(value: Color, alpha: float32): Color =
  color(value.r, value.g, value.b, value.a * alpha)

func normalizedSweep(startAngle, endAngle: float32, anticlockwise: bool): float32 =
  let rawSweep = endAngle - startAngle
  if abs(rawSweep) >= CanvasTwoPi:
    return
      if anticlockwise:
        -CanvasTwoPi
      else:
        CanvasTwoPi
  result = rawSweep
  if anticlockwise:
    while result > 0.0'f32:
      result -= CanvasTwoPi
  else:
    while result < 0.0'f32:
      result += CanvasTwoPi

func drawableLine(start, stop: Point): fd.DrawableOp =
  fd.DrawableOp(
    kind: fd.dkLine, a: vmath.vec2(start.x, start.y), b: vmath.vec2(stop.x, stop.y)
  )

func drawableCircle(center: Point, radius: float32): fd.DrawableOp =
  fd.DrawableOp(
    kind: fd.dkCircle, center: vmath.vec2(center.x, center.y), radius: radius
  )

func drawableRectangle(value: Rect, radius: float32): fd.DrawableOp =
  let corner = min(max(radius, 0.0'f32), high(uint16).float32).round().uint16
  fd.DrawableOp(
    kind: fd.dkRectangle,
    box: bumpy.rect(value.origin.x, value.origin.y, value.size.width, value.size.height),
    corners: [corner, corner, corner, corner],
  )

func drawableArc(
    center: Point, radius, startAngle, sweepAngle: float32
): fd.DrawableOp =
  fd.DrawableOp(
    kind: fd.dkArc,
    arcCenter: vmath.vec2(center.x, center.y),
    arcRadius: radius,
    startAngle: startAngle,
    sweepAngle: sweepAngle,
  )

proc drawableBezier(segment: CanvasCubicSegment): fd.DrawableOp =
  fd.drawableBezier(
    [
      vmath.vec2(segment.start.x, segment.start.y),
      vmath.vec2(segment.control1.x, segment.control1.y),
      vmath.vec2(segment.control2.x, segment.control2.y),
      vmath.vec2(segment.stop.x, segment.stop.y),
    ]
  )

func ellipsePoint(center: Point, radiusX, radiusY, rotation, angle: float32): Point =
  let
    cosine = cos(rotation)
    sine = sin(rotation)
    x = radiusX * cos(angle)
    y = radiusY * sin(angle)
  initPoint(center.x + x * cosine - y * sine, center.y + x * sine + y * cosine)

func ellipseDerivative(radiusX, radiusY, rotation, angle: float32): Point =
  let
    cosine = cos(rotation)
    sine = sin(rotation)
    x = -radiusX * sin(angle)
    y = radiusY * cos(angle)
  initPoint(x * cosine - y * sine, x * sine + y * cosine)

func ellipseSegments(command: CanvasPathCommand): seq[CanvasCubicSegment] =
  if abs(command.ellipseSweepAngle) <= CanvasPathEpsilon:
    return
  let segmentCount =
    max(1, int(ceil(abs(command.ellipseSweepAngle) / (PI.float32 * 0.5'f32))))
  for index in 0 ..< segmentCount:
    let
      startAngle =
        command.ellipseStartAngle +
        command.ellipseSweepAngle * index.float32 / segmentCount.float32
      endAngle =
        command.ellipseStartAngle +
        command.ellipseSweepAngle * (index + 1).float32 / segmentCount.float32
      angleDelta = endAngle - startAngle
      controlScale = 4.0'f32 / 3.0'f32 * tan(angleDelta * 0.25'f32)
      start = ellipsePoint(
        command.ellipseCenter, command.ellipseRadiusX, command.ellipseRadiusY,
        command.ellipseRotation, startAngle,
      )
      stop = ellipsePoint(
        command.ellipseCenter, command.ellipseRadiusX, command.ellipseRadiusY,
        command.ellipseRotation, endAngle,
      )
      startDerivative = ellipseDerivative(
        command.ellipseRadiusX, command.ellipseRadiusY, command.ellipseRotation,
        startAngle,
      )
      stopDerivative = ellipseDerivative(
        command.ellipseRadiusX, command.ellipseRadiusY, command.ellipseRotation,
        endAngle,
      )
    result.add CanvasCubicSegment(
      start: start,
      control1: initPoint(
        start.x + startDerivative.x * controlScale,
        start.y + startDerivative.y * controlScale,
      ),
      control2: initPoint(
        stop.x - stopDerivative.x * controlScale,
        stop.y - stopDerivative.y * controlScale,
      ),
      stop: stop,
    )

proc expandBounds(bounds: var CanvasPathBounds, point: Point) =
  if not bounds.valid:
    bounds = CanvasPathBounds(
      valid: true, minX: point.x, minY: point.y, maxX: point.x, maxY: point.y
    )
  else:
    bounds.minX = min(bounds.minX, point.x)
    bounds.minY = min(bounds.minY, point.y)
    bounds.maxX = max(bounds.maxX, point.x)
    bounds.maxY = max(bounds.maxY, point.y)

proc expandBounds(bounds: var CanvasPathBounds, value: Rect) =
  bounds.expandBounds(value.origin)
  bounds.expandBounds(initPoint(value.maxX, value.maxY))

proc pathBounds(path: openArray[CanvasPathCommand]): Rect =
  var bounds: CanvasPathBounds
  for command in path:
    case command.kind
    of cpcMove, cpcLine:
      bounds.expandBounds(command.point)
    of cpcQuadratic:
      bounds.expandBounds(command.quadraticControl)
      bounds.expandBounds(command.quadraticEnd)
    of cpcBezier:
      bounds.expandBounds(command.bezierControl1)
      bounds.expandBounds(command.bezierControl2)
      bounds.expandBounds(command.bezierEnd)
    of cpcArc:
      bounds.expandBounds(
        rect(
          command.arcCenter.x - command.arcRadius,
          command.arcCenter.y - command.arcRadius,
          command.arcRadius * 2.0'f32,
          command.arcRadius * 2.0'f32,
        )
      )
    of cpcRectangle:
      bounds.expandBounds(command.rectangle)
    of cpcEllipse:
      let extent = max(command.ellipseRadiusX, command.ellipseRadiusY)
      bounds.expandBounds(
        rect(
          command.ellipseCenter.x - extent,
          command.ellipseCenter.y - extent,
          extent * 2.0'f32,
          extent * 2.0'f32,
        )
      )
    of cpcClose:
      discard
  if bounds.valid:
    rect(bounds.minX, bounds.minY, bounds.maxX - bounds.minX, bounds.maxY - bounds.minY)
  else:
    rect(0.0, 0.0, 0.0, 0.0)

proc canvasTarget(context: CanvasRenderingContext2D): Rect =
  let size = context.xCanvas.bounds().size
  rect(0.0, 0.0, size.width, size.height)

proc appendOperation(
    context: CanvasRenderingContext2D, operation: sink CanvasOperation
) =
  context.xOperations.add operation
  context.xCanvas.needsDisplay = true

proc addDrawable(
    context: CanvasRenderingContext2D,
    drawOps: sink seq[fd.DrawableOp],
    fillStyle, strokeStyle: Color,
    lineWidth: float32,
) =
  if drawOps.len == 0:
    return
  context.appendOperation(
    CanvasOperation(
      kind: cokDrawable,
      target: context.canvasTarget(),
      drawOps: drawOps,
      drawableFill: fillStyle,
      drawableStroke: strokeStyle,
      drawableLineWidth: lineWidth,
      drawableLineCap: context.xState.lineCap,
      drawableLineJoin: context.xState.lineJoin,
    )
  )

proc addLineIfNeeded(
    operations: var seq[fd.DrawableOp], hasCurrent: bool, current, stop: Point
) =
  if hasCurrent and not pointClose(current, stop):
    operations.add drawableLine(current, stop)

proc pathDrawables(path: openArray[CanvasPathCommand]): seq[fd.DrawableOp] =
  var
    current: Point
    subpathStart: Point
    hasCurrent = false
  for command in path:
    case command.kind
    of cpcMove:
      current = command.point
      subpathStart = command.point
      hasCurrent = true
    of cpcLine:
      if hasCurrent:
        result.add drawableLine(current, command.point)
      current = command.point
      if not hasCurrent:
        subpathStart = command.point
      hasCurrent = true
    of cpcQuadratic:
      if hasCurrent:
        result.add fd.drawableBezier(
          [
            vmath.vec2(current.x, current.y),
            vmath.vec2(command.quadraticControl.x, command.quadraticControl.y),
            vmath.vec2(command.quadraticEnd.x, command.quadraticEnd.y),
          ]
        )
      current = command.quadraticEnd
      if not hasCurrent:
        subpathStart = current
      hasCurrent = true
    of cpcBezier:
      if hasCurrent:
        result.add fd.drawableBezier(
          [
            vmath.vec2(current.x, current.y),
            vmath.vec2(command.bezierControl1.x, command.bezierControl1.y),
            vmath.vec2(command.bezierControl2.x, command.bezierControl2.y),
            vmath.vec2(command.bezierEnd.x, command.bezierEnd.y),
          ]
        )
      current = command.bezierEnd
      if not hasCurrent:
        subpathStart = current
      hasCurrent = true
    of cpcArc:
      let
        start = pointAt(command.arcCenter, command.arcRadius, command.arcStartAngle)
        stop = pointAt(
          command.arcCenter,
          command.arcRadius,
          command.arcStartAngle + command.arcSweepAngle,
        )
      result.addLineIfNeeded(hasCurrent, current, start)
      result.add drawableArc(
        command.arcCenter, command.arcRadius, command.arcStartAngle,
        command.arcSweepAngle,
      )
      if not hasCurrent:
        subpathStart = start
      current = stop
      hasCurrent = true
    of cpcRectangle:
      result.add drawableRectangle(command.rectangle, command.cornerRadius)
      current = command.rectangle.origin
      subpathStart = current
      hasCurrent = true
    of cpcEllipse:
      let segments = command.ellipseSegments()
      if segments.len > 0:
        result.addLineIfNeeded(hasCurrent, current, segments[0].start)
        for segment in segments:
          result.add segment.drawableBezier()
        if not hasCurrent:
          subpathStart = segments[0].start
        current = segments[^1].stop
        hasCurrent = true
    of cpcClose:
      if hasCurrent and not pointClose(current, subpathStart):
        result.add drawableLine(current, subpathStart)
      current = subpathStart

func svgNumber(value: float32): string =
  value.formatFloat(ffDecimal, 4)

func svgPoint(value, origin: Point): string =
  (value.x - origin.x).svgNumber() & " " & (value.y - origin.y).svgNumber()

proc appendSvgArc(
    data: var string,
    center: Point,
    radius, startAngle, sweepAngle: float32,
    origin: Point,
) =
  if abs(sweepAngle) <= CanvasPathEpsilon:
    return
  let
    sweepFlag = if sweepAngle >= 0.0'f32: "1" else: "0"
    segmentCount = if abs(sweepAngle) >= CanvasTwoPi - CanvasPathEpsilon: 2 else: 1
  for index in 0 ..< segmentCount:
    let
      segmentStart = startAngle + sweepAngle * index.float32 / segmentCount.float32
      segmentStop = startAngle + sweepAngle * (index + 1).float32 / segmentCount.float32
      largeArc = if abs(segmentStop - segmentStart) > PI.float32: "1" else: "0"
      stop = pointAt(center, radius, segmentStop)
    data.add " A " & radius.svgNumber() & " " & radius.svgNumber() & " 0 " & largeArc &
      " " & sweepFlag & " " & stop.svgPoint(origin)

proc svgPathData(path: openArray[CanvasPathCommand], origin: Point): string =
  var
    current: Point
    subpathStart: Point
    hasCurrent = false
  for command in path:
    case command.kind
    of cpcMove:
      result.add " M " & command.point.svgPoint(origin)
      current = command.point
      subpathStart = command.point
      hasCurrent = true
    of cpcLine:
      result.add (if hasCurrent: " L " else: " M ") & command.point.svgPoint(origin)
      current = command.point
      if not hasCurrent:
        subpathStart = current
      hasCurrent = true
    of cpcQuadratic:
      if hasCurrent:
        result.add " Q " & command.quadraticControl.svgPoint(origin) & " " &
          command.quadraticEnd.svgPoint(origin)
      else:
        result.add " M " & command.quadraticEnd.svgPoint(origin)
        subpathStart = command.quadraticEnd
      current = command.quadraticEnd
      hasCurrent = true
    of cpcBezier:
      if hasCurrent:
        result.add " C " & command.bezierControl1.svgPoint(origin) & " " &
          command.bezierControl2.svgPoint(origin) & " " &
          command.bezierEnd.svgPoint(origin)
      else:
        result.add " M " & command.bezierEnd.svgPoint(origin)
        subpathStart = command.bezierEnd
      current = command.bezierEnd
      hasCurrent = true
    of cpcArc:
      let
        start = pointAt(command.arcCenter, command.arcRadius, command.arcStartAngle)
        stop = pointAt(
          command.arcCenter,
          command.arcRadius,
          command.arcStartAngle + command.arcSweepAngle,
        )
      if not hasCurrent:
        result.add " M " & start.svgPoint(origin)
        subpathStart = start
      elif not pointClose(current, start):
        result.add " L " & start.svgPoint(origin)
      result.appendSvgArc(
        command.arcCenter, command.arcRadius, command.arcStartAngle,
        command.arcSweepAngle, origin,
      )
      current = stop
      hasCurrent = true
    of cpcRectangle:
      let
        value = command.rectangle
        topLeft = value.origin
        topRight = initPoint(value.maxX, value.origin.y)
        bottomRight = initPoint(value.maxX, value.maxY)
        bottomLeft = initPoint(value.origin.x, value.maxY)
      result.add " M " & topLeft.svgPoint(origin)
      result.add " L " & topRight.svgPoint(origin)
      result.add " L " & bottomRight.svgPoint(origin)
      result.add " L " & bottomLeft.svgPoint(origin) & " Z"
      current = topLeft
      subpathStart = topLeft
      hasCurrent = true
    of cpcEllipse:
      let segments = command.ellipseSegments()
      if segments.len > 0:
        if not hasCurrent:
          result.add " M " & segments[0].start.svgPoint(origin)
          subpathStart = segments[0].start
        elif not pointClose(current, segments[0].start):
          result.add " L " & segments[0].start.svgPoint(origin)
        for segment in segments:
          result.add " C " & segment.control1.svgPoint(origin) & " " &
            segment.control2.svgPoint(origin) & " " & segment.stop.svgPoint(origin)
        current = segments[^1].stop
        hasCurrent = true
    of cpcClose:
      if hasCurrent:
        result.add " Z"
        current = subpathStart
  result = result.strip()

func toStrokeCap(value: CanvasLineCap): fd.StrokeCap =
  case value
  of clcButt: fd.scButt
  of clcRound: fd.scRound
  of clcSquare: fd.scSquare

func toStrokeJoin(value: CanvasLineJoin): fd.StrokeJoin =
  case value
  of cljMiter: fd.sjMiter
  of cljRound: fd.sjRound
  of cljBevel: fd.sjBevel

proc renderOperation(context: DrawContext, operation: CanvasOperation) =
  case operation.kind
  of cokDrawable:
    discard context.addRenderDrawable(
      operation.target,
      operation.drawOps,
      fill(operation.drawableFill.rgba),
      fd.RenderStroke(
        weight: operation.drawableLineWidth,
        fill: fill(operation.drawableStroke.rgba),
        cap: operation.drawableLineCap.toStrokeCap(),
        join: operation.drawableLineJoin.toStrokeJoin(),
      ),
    )
  of cokMtsdf:
    discard context.addSvgMtsdf(operation.target, operation.mtsdf)
  of cokImage:
    discard context.addImage(operation.target, operation.image, operation.imageTint)

protocol CanvasViewDrawing of ViewDrawingProtocol:
  method draw(canvas: CanvasView, context: DrawContext) =
    discard canvas.performNext(draw, context)
    for operation in canvas.xContext.xOperations:
      context.renderOperation(operation)

proc initCanvasViewFields*(canvas: CanvasView, frame = AutoRect) =
  initViewFields(canvas, frame)
  canvas.xContext = CanvasRenderingContext2D(xCanvas: canvas, xState: initCanvasState())
  canvas.backgroundColor = color(1.0, 1.0, 1.0, 1.0)
  canvas.clipsToBounds = true
  canvas.accessibilityRole = arImage
  canvas.accessibilityLabel = "Drawing canvas"
  discard canvas.withProtocol(CanvasViewDrawing)

proc newCanvasView*(frame = AutoRect): CanvasView =
  result = CanvasView()
  result.initCanvasViewFields(frame)

proc getContext2D*(canvas: CanvasView): CanvasRenderingContext2D =
  canvas.xContext

proc getContext*(canvas: CanvasView, contextType: string): CanvasRenderingContext2D =
  if contextType.toLowerAscii() != "2d":
    raise newException(
      CanvasContextError, "unsupported canvas context type: " & contextType
    )
  canvas.getContext2D()

proc canvas*(context: CanvasRenderingContext2D): CanvasView =
  context.xCanvas

proc len*(context: CanvasRenderingContext2D): int =
  context.xOperations.len

proc `[]`*(context: CanvasRenderingContext2D, index: int): CanvasOperation =
  context.xOperations[index]

iterator items*(context: CanvasRenderingContext2D): CanvasOperation =
  for operation in context.xOperations:
    yield operation

proc clear*(context: CanvasRenderingContext2D) =
  if context.xOperations.len > 0:
    context.xOperations.setLen(0)
    context.xCanvas.needsDisplay = true

proc truncateOperations*(context: CanvasRenderingContext2D, count: Natural) =
  if count < context.xOperations.len:
    context.xOperations.setLen(count)
    context.xCanvas.needsDisplay = true

proc fillStyle*(context: CanvasRenderingContext2D): Color =
  context.xState.fillStyle

proc `fillStyle=`*(context: CanvasRenderingContext2D, value: Color) =
  context.xState.fillStyle = value

proc `fillStyle=`*(context: CanvasRenderingContext2D, value: string) =
  context.fillStyle = parseHtmlColor(value)

proc strokeStyle*(context: CanvasRenderingContext2D): Color =
  context.xState.strokeStyle

proc `strokeStyle=`*(context: CanvasRenderingContext2D, value: Color) =
  context.xState.strokeStyle = value

proc `strokeStyle=`*(context: CanvasRenderingContext2D, value: string) =
  context.strokeStyle = parseHtmlColor(value)

proc globalAlpha*(context: CanvasRenderingContext2D): float32 =
  context.xState.globalAlpha

proc `globalAlpha=`*(context: CanvasRenderingContext2D, value: float32) =
  context.xState.globalAlpha = min(max(value, 0.0'f32), 1.0'f32)

proc lineWidth*(context: CanvasRenderingContext2D): float32 =
  context.xState.lineWidth

proc `lineWidth=`*(context: CanvasRenderingContext2D, value: float32) =
  if value > 0.0'f32:
    context.xState.lineWidth = value

proc lineCap*(context: CanvasRenderingContext2D): CanvasLineCap =
  context.xState.lineCap

proc `lineCap=`*(context: CanvasRenderingContext2D, value: CanvasLineCap) =
  context.xState.lineCap = value

proc lineJoin*(context: CanvasRenderingContext2D): CanvasLineJoin =
  context.xState.lineJoin

proc `lineJoin=`*(context: CanvasRenderingContext2D, value: CanvasLineJoin) =
  context.xState.lineJoin = value

proc save*(context: CanvasRenderingContext2D) =
  context.xStateStack.add context.xState

proc restore*(context: CanvasRenderingContext2D) =
  if context.xStateStack.len > 0:
    context.xState = context.xStateStack.pop()

proc beginPath*(context: CanvasRenderingContext2D) =
  context.xPath.setLen(0)
  context.xHasCurrentPoint = false

proc closePath*(context: CanvasRenderingContext2D) =
  if context.xHasCurrentPoint:
    context.xPath.add CanvasPathCommand(kind: cpcClose)
    context.xCurrentPoint = context.xSubpathStart

proc moveTo*(context: CanvasRenderingContext2D, x, y: float32) =
  let point = initPoint(x, y)
  context.xPath.add CanvasPathCommand(kind: cpcMove, point: point)
  context.xCurrentPoint = point
  context.xSubpathStart = point
  context.xHasCurrentPoint = true

proc lineTo*(context: CanvasRenderingContext2D, x, y: float32) =
  let point = initPoint(x, y)
  if context.xHasCurrentPoint:
    context.xPath.add CanvasPathCommand(kind: cpcLine, point: point)
    context.xCurrentPoint = point
  else:
    context.moveTo(x, y)

proc quadraticCurveTo*(
    context: CanvasRenderingContext2D, controlX, controlY, x, y: float32
) =
  let stop = initPoint(x, y)
  if context.xHasCurrentPoint:
    context.xPath.add CanvasPathCommand(
      kind: cpcQuadratic,
      quadraticControl: initPoint(controlX, controlY),
      quadraticEnd: stop,
    )
    context.xCurrentPoint = stop
  else:
    context.moveTo(x, y)

proc bezierCurveTo*(
    context: CanvasRenderingContext2D,
    control1X, control1Y, control2X, control2Y, x, y: float32,
) =
  let stop = initPoint(x, y)
  if context.xHasCurrentPoint:
    context.xPath.add CanvasPathCommand(
      kind: cpcBezier,
      bezierControl1: initPoint(control1X, control1Y),
      bezierControl2: initPoint(control2X, control2Y),
      bezierEnd: stop,
    )
    context.xCurrentPoint = stop
  else:
    context.moveTo(x, y)

proc arc*(
    context: CanvasRenderingContext2D,
    x, y, radius, startAngle, endAngle: float32,
    anticlockwise = false,
) =
  if radius < 0.0'f32:
    raise newException(CanvasPathError, "canvas arc radius cannot be negative")
  let
    center = initPoint(x, y)
    sweep = normalizedSweep(startAngle, endAngle, anticlockwise)
    start = pointAt(center, radius, startAngle)
  context.xPath.add CanvasPathCommand(
    kind: cpcArc,
    arcCenter: center,
    arcRadius: radius,
    arcStartAngle: startAngle,
    arcSweepAngle: sweep,
  )
  if not context.xHasCurrentPoint:
    context.xSubpathStart = start
  context.xCurrentPoint = pointAt(center, radius, startAngle + sweep)
  context.xHasCurrentPoint = true

proc ellipse*(
    context: CanvasRenderingContext2D,
    x, y, radiusX, radiusY, rotation, startAngle, endAngle: float32,
    anticlockwise = false,
) =
  if radiusX < 0.0'f32 or radiusY < 0.0'f32:
    raise newException(CanvasPathError, "canvas ellipse radii cannot be negative")
  let
    center = initPoint(x, y)
    sweep = normalizedSweep(startAngle, endAngle, anticlockwise)
    start = ellipsePoint(center, radiusX, radiusY, rotation, startAngle)
  context.xPath.add CanvasPathCommand(
    kind: cpcEllipse,
    ellipseCenter: center,
    ellipseRadiusX: radiusX,
    ellipseRadiusY: radiusY,
    ellipseRotation: rotation,
    ellipseStartAngle: startAngle,
    ellipseSweepAngle: sweep,
  )
  if not context.xHasCurrentPoint:
    context.xSubpathStart = start
  context.xCurrentPoint =
    ellipsePoint(center, radiusX, radiusY, rotation, startAngle + sweep)
  context.xHasCurrentPoint = true

proc roundRect*(
    context: CanvasRenderingContext2D, x, y, width, height, radius: float32
) =
  let value = normalizedRect(x, y, width, height)
  context.xPath.add CanvasPathCommand(
    kind: cpcRectangle, rectangle: value, cornerRadius: max(radius, 0.0'f32)
  )
  context.xCurrentPoint = value.origin
  context.xSubpathStart = value.origin
  context.xHasCurrentPoint = true

proc rect*(context: CanvasRenderingContext2D, x, y, width, height: float32) =
  context.roundRect(x, y, width, height, 0.0'f32)

proc fillRect*(context: CanvasRenderingContext2D, x, y, width, height: float32) =
  let value = normalizedRect(x, y, width, height)
  context.addDrawable(
    @[drawableRectangle(value, 0.0'f32)],
    context.xState.fillStyle.withGlobalAlpha(context.xState.globalAlpha),
    CanvasTransparent,
    0.0'f32,
  )

proc strokeRect*(context: CanvasRenderingContext2D, x, y, width, height: float32) =
  let value = normalizedRect(x, y, width, height)
  context.addDrawable(
    @[drawableRectangle(value, 0.0'f32)],
    CanvasTransparent,
    context.xState.strokeStyle.withGlobalAlpha(context.xState.globalAlpha),
    context.xState.lineWidth,
  )

proc fill*(context: CanvasRenderingContext2D, fillRule = cfrNonZero) =
  if context.xPath.len == 0:
    return
  let fillColor = context.xState.fillStyle.withGlobalAlpha(context.xState.globalAlpha)
  if context.xPath.len == 1 and context.xPath[0].kind == cpcRectangle:
    let command = context.xPath[0]
    context.addDrawable(
      @[drawableRectangle(command.rectangle, command.cornerRadius)],
      fillColor,
      CanvasTransparent,
      0.0'f32,
    )
    return
  if context.xPath.len == 1 and context.xPath[0].kind == cpcArc and
      abs(context.xPath[0].arcSweepAngle) >= CanvasTwoPi - CanvasPathEpsilon:
    let command = context.xPath[0]
    context.addDrawable(
      @[drawableCircle(command.arcCenter, command.arcRadius)],
      fillColor,
      CanvasTransparent,
      0.0'f32,
    )
    return

  let target = context.xPath.pathBounds()
  if target.size.width <= CanvasPathEpsilon or target.size.height <= CanvasPathEpsilon:
    return
  let
    pathData = context.xPath.svgPathData(target.origin)
    rule = if fillRule == cfrEvenOdd: "evenodd" else: "nonzero"
    svg =
      fmt"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {target.size.width} {target.size.height}">
  <path d="{pathData}" fill="{fillColor.toHtmlHex()}" fill-opacity="{fillColor.a}" fill-rule="{rule}"/>
</svg>
"""
  try:
    let resource = newSvgMtsdfResource(svg)
    context.appendOperation(
      CanvasOperation(kind: cokMtsdf, target: target, mtsdf: resource)
    )
  except CatchableError as error:
    raise newException(CanvasPathError, "unable to fill canvas path: " & error.msg)

proc stroke*(context: CanvasRenderingContext2D) =
  context.addDrawable(
    context.xPath.pathDrawables(),
    CanvasTransparent,
    context.xState.strokeStyle.withGlobalAlpha(context.xState.globalAlpha),
    context.xState.lineWidth,
  )

proc drawImage*(
    context: CanvasRenderingContext2D,
    image: ImageResource,
    x, y, width, height: float32,
) =
  if image.isNil:
    return
  context.appendOperation(
    CanvasOperation(
      kind: cokImage,
      target: normalizedRect(x, y, width, height),
      image: image,
      imageTint: color(1.0, 1.0, 1.0, context.xState.globalAlpha),
    )
  )

proc drawImage*(
    context: CanvasRenderingContext2D, image: ImageResource, x, y: float32
) =
  if not image.isNil:
    let size = image.size()
    context.drawImage(image, x, y, size.width, size.height)
