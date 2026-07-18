import std/[math, os]

import pkg/pixie
import pkg/sdfy/msdfgen

import ./images
import ./private/svgpathloader

const
  DefaultSvgMtsdfLongEdge* = 192
  DefaultSvgMtsdfMinimumShortEdge* = 48
  DefaultSvgMtsdfPixelRange* = 6.0

type
  SvgMtsdfError* = object of CatchableError
    ## Raised when SVG path loading or MTSDF generation fails.

  SvgMtsdfResource* = object
    ## A reusable MTSDF image generated from the visible paths in an SVG.
    image*: ImageResource
    elementCount*: Natural
    pixelRange*: float32

proc fieldDimensions(
    path: Path, longEdge, minimumShortEdge: Positive
): tuple[width, height: int] =
  let bounds = path.computeBounds()
  if bounds.w <= 0.0'f32 or bounds.h <= 0.0'f32:
    raise newException(PixieError, "SVG path has empty bounds")

  let
    aspect = bounds.w / bounds.h
    shortest = min(minimumShortEdge.int, longEdge.int)
  if aspect >= 1.0'f32:
    result.width = longEdge
    result.height = max(shortest, int(round(longEdge.float32 / aspect)))
  else:
    result.width = max(shortest, int(round(longEdge.float32 * aspect)))
    result.height = longEdge

proc raiseSvgMtsdfError(message: string) {.noinline, noreturn.} =
  raise newException(SvgMtsdfError, message)

proc newSvgMtsdfResource*(
    svgData: string,
    name = "",
    longEdge: Positive = DefaultSvgMtsdfLongEdge,
    minimumShortEdge: Positive = DefaultSvgMtsdfMinimumShortEdge,
    pixelRange = DefaultSvgMtsdfPixelRange,
    cachePolicy = icpDefault,
): SvgMtsdfResource =
  ## Parses visible SVG paths and generates an MTSDF-backed image resource.
  ##
  ## SVG paint is intentionally ignored: callers choose fill and stroke while drawing.
  if pixelRange <= 0.0:
    raiseSvgMtsdfError("SVG MTSDF pixel range must be positive")

  try:
    let parsed = parseSvgPath(svgData)
    if parsed.elements == 0:
      raiseSvgMtsdfError("SVG contains no visible path elements")

    let
      dimensions = parsed.path.fieldDimensions(longEdge, minimumShortEdge)
      field =
        generateMtsdfPath(parsed.path, dimensions.width, dimensions.height, pixelRange)
    result = SvgMtsdfResource(
      image: newImageResource(field.image, name, cachePolicy),
      elementCount: parsed.elements.Natural,
      pixelRange: (field.range * field.scale).float32,
    )
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
  ## Reads an SVG file and generates an MTSDF-backed image resource.
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
