import std/[math, os]

import pkg/pixie
import pkg/sdfy/msdfgen

import ./images
import ./private/svgpathloader
import ../foundation/types

const
  DefaultSvgMtsdfLongEdge* = 192
  DefaultSvgMtsdfMinimumShortEdge* = 48
  DefaultSvgMtsdfPixelRange* = 6.0

type
  SvgMtsdfError* = object of CatchableError
    ## Raised when SVG path loading or MTSDF generation fails.

  SvgLayerKind* = enum
    slkMtsdfFill
    slkMtsdfStroke
    slkStrokePath
    slkCircle

  SvgPathSegmentKind* = enum
    spsLine
    spsQuadratic
    spsCubic

  SvgStrokeCap* = enum
    svcButt
    svcRound
    svcSquare

  SvgStrokeJoin* = enum
    svjMiter
    svjRound
    svjBevel

  SvgPathSegment* = object ## One stroked path segment in SVG document coordinates.
    kind*: SvgPathSegmentKind
    start*, control1*, control2*, stop*: Point

  SvgAffineTransform* = object ## A 2D affine transform in SVG document coordinates.
    a*, b*, c*, d*, tx*, ty*: float32

  SvgLayer* = object ## One ordered SVG paint operation.
    paint*: Color
    case kind*: SvgLayerKind
    of slkMtsdfFill, slkMtsdfStroke:
      image*: ImageResource
      frame*: Rect
      pixelRange*: float32
      mtsdfStrokeWidth*: float32
    of slkStrokePath:
      segments*: seq[SvgPathSegment]
      strokeWidth*: float32
      strokeCap*: SvgStrokeCap
      strokeJoin*: SvgStrokeJoin
    of slkCircle:
      transform*: SvgAffineTransform
      drawsFill*, drawsStroke*: bool
      strokePaint*: Color
      localStrokeWidth*: float32

  SvgMtsdfResource* = object
    ## Reusable ordered vector and MTSDF layers generated from an SVG.
    layers*: seq[SvgLayer]
    elementCount*: Natural
    size*: Size

proc fieldDimensions(
    width, height: float32, longEdge, minimumShortEdge: Positive
): tuple[width, height: int] =
  if width <= 0.0'f32 or height <= 0.0'f32:
    raise newException(PixieError, "SVG has empty bounds")

  let
    aspect = width / height
    shortest = min(minimumShortEdge.int, longEdge.int)
  if aspect >= 1.0'f32:
    result.width = longEdge
    result.height = max(shortest, int(round(longEdge.float32 / aspect)))
  else:
    result.width = max(shortest, int(round(longEdge.float32 * aspect)))
    result.height = longEdge

proc raiseSvgMtsdfError(message: string) {.noinline, noreturn.} =
  raise newException(SvgMtsdfError, message)

proc layerName(name: string, index, count: int): string =
  if name.len == 0:
    return ""
  if count == 1:
    return name
  name & ":" & $index

proc hasArea(path: Path): bool =
  if path.isNil:
    return
  let bounds = path.computeBounds()
  bounds.w > 0.0'f32 and bounds.h > 0.0'f32

proc toPoint(value: Vec2): Point =
  initPoint(value.x, value.y)

proc toSegment(segment: svgpathloader.SvgStrokeSegment): SvgPathSegment =
  let kind =
    case segment.kind
    of sskLine: spsLine
    of sskQuadratic: spsQuadratic
    of sskCubic: spsCubic
  SvgPathSegment(
    kind: kind,
    start: segment.start.toPoint(),
    control1: segment.control1.toPoint(),
    control2: segment.control2.toPoint(),
    stop: segment.stop.toPoint(),
  )

proc toStrokeCap(value: svgpathloader.SvgStrokeCap): SvgStrokeCap =
  case value
  of sscButt: svcButt
  of sscRound: svcRound
  of sscSquare: svcSquare

proc toStrokeJoin(value: svgpathloader.SvgStrokeJoin): SvgStrokeJoin =
  case value
  of ssjMiter: svjMiter
  of ssjRound: svjRound
  of ssjBevel: svjBevel

proc toAffine(value: SvgAffine): SvgAffineTransform =
  SvgAffineTransform(
    a: value.a, b: value.b, c: value.c, d: value.d, tx: value.tx, ty: value.ty
  )

proc newMtsdfLayer(
    path: Path,
    paint: Color,
    name: string,
    imageIndex, imageCount: int,
    documentScale, pixelRange: float64,
    cachePolicy: ImageCachePolicy,
): SvgLayer =
  let bounds = path.computeBounds()
  if bounds.w <= 0.0'f32 or bounds.h <= 0.0'f32:
    raise newException(PixieError, "SVG path has empty bounds")

  let
    minimumDimension = int(ceil(pixelRange + 1.0))
    width =
      max(minimumDimension, int(ceil(bounds.w.float64 * documentScale + pixelRange)))
    height =
      max(minimumDimension, int(ceil(bounds.h.float64 * documentScale + pixelRange)))
    field = generateMtsdfPath(path, width, height, pixelRange)
    fieldScale = field.scale.float32
  field.image.flipVertical()

  SvgLayer(
    kind: slkMtsdfFill,
    paint: paint,
    image: newImageResource(
      field.image, layerName(name, imageIndex, imageCount), cachePolicy
    ),
    frame: rect(
      (-field.translate.x).float32,
      (-field.translate.y).float32,
      width.float32 / fieldScale,
      height.float32 / fieldScale,
    ),
    pixelRange: (field.range * field.scale).float32,
  )

proc mtsdfStrokeLayer(
    fillLayer: SvgLayer, strokeWidth: float32, paint: Color
): SvgLayer =
  SvgLayer(
    kind: slkMtsdfStroke,
    paint: paint,
    image: fillLayer.image,
    frame: fillLayer.frame,
    pixelRange: fillLayer.pixelRange,
    mtsdfStrokeWidth: strokeWidth,
  )

proc newSvgMtsdfResource*(
    svgData: string,
    name = "",
    longEdge: Positive = DefaultSvgMtsdfLongEdge,
    minimumShortEdge: Positive = DefaultSvgMtsdfMinimumShortEdge,
    pixelRange = DefaultSvgMtsdfPixelRange,
    cachePolicy = icpDefault,
): SvgMtsdfResource =
  ## Parses an SVG into ordered FigDraw vector strokes and MTSDF fill layers.
  ##
  ## Circles, lines, and Bezier strokes remain vector drawables. Ellipses and
  ## independently filled complex elements receive separate compact MTSDFs.
  ## Solid SVG fill and stroke colors, including inherited colors and opacity,
  ## are kept. Gradient fills are not yet supported.
  if pixelRange <= 0.0:
    raiseSvgMtsdfError("SVG MTSDF pixel range must be positive")

  try:
    let parsed = parseSvgDocument(svgData)
    result.size = initSize(parsed.width.float32, parsed.height.float32)
    let
      imageCount = block:
        var count = 0
        for element in parsed.elements:
          if element.kind != sekCircle and element.fillPath.hasArea():
            inc count
        count
      dimensions = fieldDimensions(
        result.size.width, result.size.height, longEdge, minimumShortEdge
      )
      usableWidth = dimensions.width.float64 - pixelRange
      usableHeight = dimensions.height.float64 - pixelRange
    if imageCount > 0 and (usableWidth <= 0.0 or usableHeight <= 0.0):
      raiseSvgMtsdfError("SVG MTSDF dimensions must exceed the pixel range")

    let documentScale =
      if imageCount > 0:
        min(
          usableWidth / result.size.width.float64,
          usableHeight / result.size.height.float64,
        )
      else:
        0.0
    var imageIndex = 0

    for element in parsed.elements:
      let firstLayer = result.layers.len
      if element.kind == sekCircle:
        result.layers.add SvgLayer(
          kind: slkCircle,
          paint: element.fillColor,
          transform: element.primitiveTransform.toAffine(),
          drawsFill: element.hasFill,
          drawsStroke: element.hasStroke,
          strokePaint: element.strokeColor,
          localStrokeWidth: element.primitiveStrokeWidth,
        )
      elif element.kind == sekEllipse:
        if element.fillPath.hasArea():
          let mtsdfLayer = newMtsdfLayer(
            element.fillPath, element.fillColor, name, imageIndex, imageCount,
            documentScale, pixelRange, cachePolicy,
          )
          inc imageIndex
          if element.hasFill:
            result.layers.add mtsdfLayer
          if element.hasStroke:
            result.layers.add mtsdfLayer.mtsdfStrokeLayer(
              element.strokeWidth, element.strokeColor
            )
      else:
        if element.hasFill and element.fillPath.hasArea():
          result.layers.add newMtsdfLayer(
            element.fillPath, element.fillColor, name, imageIndex, imageCount,
            documentScale, pixelRange, cachePolicy,
          )
          inc imageIndex
        if element.hasStroke and element.strokeSegments.len > 0:
          var segments = newSeqOfCap[SvgPathSegment](element.strokeSegments.len)
          for segment in element.strokeSegments:
            segments.add segment.toSegment()
          result.layers.add SvgLayer(
            kind: slkStrokePath,
            paint: element.strokeColor,
            segments: segments,
            strokeWidth: element.strokeWidth,
            strokeCap: element.strokeCap.toStrokeCap(),
            strokeJoin: element.strokeJoin.toStrokeJoin(),
          )
      if result.layers.len > firstLayer:
        inc result.elementCount

    if result.layers.len == 0:
      raiseSvgMtsdfError("SVG contains no supported visible painted elements")
  except PixieError as error:
    raiseSvgMtsdfError(error.msg)

proc newSvgMtsdfResourceFromFile*(
    filePath: string,
    name = "",
    longEdge: Positive = DefaultSvgMtsdfLongEdge,
    minimumShortEdge: Positive = DefaultSvgMtsdfMinimumShortEdge,
    pixelRange = DefaultSvgMtsdfPixelRange,
    cachePolicy = icpDefault,
): SvgMtsdfResource =
  ## Reads an SVG file and creates its ordered vector and MTSDF layers.
  let data =
    try:
      readFile(filePath)
    except IOError as error:
      raiseSvgMtsdfError("Failed to read SVG: " & error.msg)
  let resolvedName =
    if name.len > 0:
      name
    else:
      splitFile(filePath).name
  newSvgMtsdfResource(
    data, resolvedName, longEdge, minimumShortEdge, pixelRange, cachePolicy
  )

proc len*(resource: SvgMtsdfResource): int =
  ## Returns the number of ordered paint layers.
  resource.layers.len

proc image*(resource: SvgMtsdfResource): ImageResource =
  ## Returns the first MTSDF image, retained for single-image compatibility.
  for layer in resource.layers:
    if layer.kind in {slkMtsdfFill, slkMtsdfStroke}:
      return layer.image

proc pixelRange*(resource: SvgMtsdfResource): float32 =
  ## Returns the first MTSDF layer's pixel range, or zero for vector-only SVGs.
  for layer in resource.layers:
    if layer.kind in {slkMtsdfFill, slkMtsdfStroke}:
      return layer.pixelRange
