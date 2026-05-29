import pkg/chroma

type
  Point* = object
    x*: float32
    y*: float32

  Size* = object
    width*: float32
    height*: float32

  Rect* = object
    origin*: Point
    size*: Size

  Color* = chroma.Color

  MouseButton* = enum
    mbPrimary
    mbSecondary
    mbOther

  MouseEvent* = object
    location*: Point
    button*: MouseButton
    clickCount*: int

  KeyModifier* = enum
    kmShift
    kmControl
    kmOption
    kmCommand

  KeyEvent* = object
    text*: string
    keyCode*: int
    modifiers*: set[KeyModifier]

  TextAlignment* = enum
    taLeft
    taCenter
    taRight

  ButtonState* = enum
    bsOff
    bsOn
    bsMixed

  ButtonType* = enum
    btMomentary
    btToggle

proc initPoint*(x, y: float32): Point =
  Point(x: x, y: y)

proc initSize*(width, height: float32): Size =
  Size(width: max(width, 0.0'f32), height: max(height, 0.0'f32))

proc initRect*(x, y, width, height: float32): Rect =
  Rect(origin: initPoint(x, y), size: initSize(width, height))

proc initRect*(origin: Point, size: Size): Rect =
  Rect(origin: origin, size: initSize(size.width, size.height))

proc initColor*(r, g, b: float32, a = 1.0'f32): Color =
  chroma.color(r, g, b, a)

proc minX*(rect: Rect): float32 =
  rect.origin.x

proc minY*(rect: Rect): float32 =
  rect.origin.y

proc maxX*(rect: Rect): float32 =
  rect.origin.x + rect.size.width

proc maxY*(rect: Rect): float32 =
  rect.origin.y + rect.size.height

proc contains*(rect: Rect, point: Point): bool =
  point.x >= rect.minX and point.y >= rect.minY and point.x < rect.maxX and
    point.y < rect.maxY

proc offset*(point: Point, dx, dy: float32): Point =
  initPoint(point.x + dx, point.y + dy)

proc localPoint*(point: Point, frame: Rect): Point =
  initPoint(point.x - frame.origin.x, point.y - frame.origin.y)

proc isEmpty*(rect: Rect): bool =
  rect.size.width <= 0.0'f32 or rect.size.height <= 0.0'f32

proc intersection*(a, b: Rect): Rect =
  let
    x1 = max(a.minX, b.minX)
    y1 = max(a.minY, b.minY)
    x2 = min(a.maxX, b.maxX)
    y2 = min(a.maxY, b.maxY)
  if x2 <= x1 or y2 <= y1:
    return initRect(x1, y1, 0.0, 0.0)
  initRect(x1, y1, x2 - x1, y2 - y1)

proc union*(a, b: Rect): Rect =
  if a.isEmpty:
    return b
  if b.isEmpty:
    return a
  let
    x1 = min(a.minX, b.minX)
    y1 = min(a.minY, b.minY)
    x2 = max(a.maxX, b.maxX)
    y2 = max(a.maxY, b.maxY)
  initRect(x1, y1, x2 - x1, y2 - y1)
