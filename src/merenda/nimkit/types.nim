import std/math

import pkg/chroma

type
  Point* = object
    x*: float32
    y*: float32

  Size* = object
    width*: float32
    height*: float32

  IntrinsicSize* = object
    width*: float32
    height*: float32

  FittingSize* = object
    width*: float32
    height*: float32

  Rect* = object
    origin*: Point
    size*: Size

  Color* = chroma.Color

  LayoutAxis* = enum
    laHorizontal
    laVertical

  SpacingDirection* = enum
    drow
    dcol

  AutoresizingMaskOption* = enum
    cxMinXMargin
    cxWidthSizable
    cxMaxXMargin
    cxMinYMargin
    cxHeightSizable
    cxMaxYMargin

  AutoresizingMask* = set[AutoresizingMaskOption]

  LayoutAttribute* = enum
    latNotAnAttribute = 0
    latLeft = 1
    latRight
    latTop
    latBottom
    latLeading
    latTrailing
    latWidth
    latHeight
    latCenterX
    latCenterY
    latLastBaseline
    latFirstBaseline

  LayoutRelation* = enum
    lrLessThanOrEqual = -1
    lrEqual = 0
    lrGreaterThanOrEqual = 1

  LayoutPriority* = distinct float32

  MouseButton* = enum
    mbPrimary
    mbSecondary
    mbOther

  KeyModifier* = enum
    kmShift
    kmControl
    kmOption
    kmCommand

  Key* = enum
    keyUnknown = 0
    keyA
    keyB
    keyC
    keyD
    keyE
    keyF
    keyG
    keyH
    keyI
    keyJ
    keyK
    keyL
    keyM
    keyN
    keyO
    keyP
    keyQ
    keyR
    keyS
    keyT
    keyU
    keyV
    keyW
    keyX
    keyY
    keyZ
    keyTilde
    key1
    key2
    key3
    key4
    key5
    key6
    key7
    key8
    key9
    key0
    keyMinus
    keyEqual
    keyF1
    keyF2
    keyF3
    keyF4
    keyF5
    keyF6
    keyF7
    keyF8
    keyF9
    keyF10
    keyF11
    keyF12
    keyF13
    keyF14
    keyF15
    keyLeftControl
    keyRightControl
    keyLeftShift
    keyRightShift
    keyLeftOption
    keyRightOption
    keyLeftCommand
    keyRightCommand
    keyLeftBracket
    keyRightBracket
    keySpace
    keyEscape
    keyEnter
    keyTab
    keyBackspace
    keyMenu
    keySlash
    keyDot
    keyComma
    keySemicolon
    keyQuote
    keyBackslash
    keyPageUp
    keyPageDown
    keyHome
    keyEnd
    keyInsert
    keyDelete
    keyArrowLeft
    keyArrowRight
    keyArrowUp
    keyArrowDown
    keyNumpad0
    keyNumpad1
    keyNumpad2
    keyNumpad3
    keyNumpad4
    keyNumpad5
    keyNumpad6
    keyNumpad7
    keyNumpad8
    keyNumpad9
    keyNumpadDot
    keyAdd
    keySubtract
    keyMultiply
    keyDivide
    keyCapsLock
    keyNumLock
    keyScrollLock
    keyPrintScreen
    keyPause
    keyLevel3Shift
    keyLevel5Shift

  MouseEvent* = object
    location*: Point
    button*: MouseButton
    clickCount*: int
    modifiers*: set[KeyModifier]
    timestamp*: float

  ScrollEvent* = object
    location*: Point
    deltaX*: float32
    deltaY*: float32
    modifiers*: set[KeyModifier]
    timestamp*: float

  KeyEvent* = object
    text*: string
    key*: Key
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
    btCheckBox
    btRadio

  PopupPresentation* = enum
    ppAutomatic ## Use popup windows when available and inline rendering otherwise.
    ppWindow ## Use a separate popup window only.
    ppInline ## Draw the popup inline in the owner window.

const
  AutoMetric* = NaN.float32
  AutoPoint* = Point(x: AutoMetric, y: AutoMetric)
  AutoSize* = Size(width: AutoMetric, height: AutoMetric)
  AutoRect* = Rect(origin: AutoPoint, size: AutoSize)
  LayoutAttributeBaseline* = latLastBaseline
  NoIntrinsicMetric* = -1.0'f32
  NoIntrinsicContentSize* =
    IntrinsicSize(width: NoIntrinsicMetric, height: NoIntrinsicMetric)
  UnconstrainedFittingSize* =
    FittingSize(width: NoIntrinsicMetric, height: NoIntrinsicMetric)
  LayoutPriorityFittingSizeLevel* = LayoutPriority(50.0'f32)
  LayoutPriorityDefaultLow* = LayoutPriority(250.0'f32)
  LayoutPriorityDefaultHigh* = LayoutPriority(750.0'f32)
  LayoutPriorityRequired* = LayoutPriority(1000.0'f32)

func `==`*(a, b: LayoutPriority): bool {.borrow.}
func `<`*(a, b: LayoutPriority): bool {.borrow.}
func `<=`*(a, b: LayoutPriority): bool {.borrow.}

func layoutAxis*(direction: SpacingDirection): LayoutAxis =
  case direction
  of dcol: laHorizontal
  of drow: laVertical

func spacingDirection*(axis: LayoutAxis): SpacingDirection =
  case axis
  of laHorizontal: dcol
  of laVertical: drow

func isAutoMetric*(value: float32): bool =
  value.isNaN

func normalizeOptionalMetric(value: float32): float32 =
  if value.isAutoMetric or value < 0.0'f32: NoIntrinsicMetric else: value

func normalizeSizeMetric(value: float32): float32 =
  if value.isAutoMetric:
    AutoMetric
  else:
    max(value, 0.0'f32)

proc initPoint*(x = AutoMetric, y = AutoMetric): Point =
  Point(x: x, y: y)

proc initSize*(width = AutoMetric, height = AutoMetric): Size =
  Size(width: width.normalizeSizeMetric, height: height.normalizeSizeMetric)

func hasAutoMetric*(point: Point): bool =
  point.x.isAutoMetric or point.y.isAutoMetric

func hasAutoMetric*(size: Size): bool =
  size.width.isAutoMetric or size.height.isAutoMetric

func hasAutoMetric*(rect: Rect): bool =
  rect.origin.hasAutoMetric or rect.size.hasAutoMetric

func hasWidth*(size: Size): bool =
  not size.width.isAutoMetric

func hasHeight*(size: Size): bool =
  not size.height.isAutoMetric

func resolveAutoPoint*(point, fallback: Point): Point =
  initPoint(
    if point.x.isAutoMetric: fallback.x else: point.x,
    if point.y.isAutoMetric: fallback.y else: point.y,
  )

func resolveAutoSize*(size, fallback: Size): Size =
  initSize(
    if size.hasWidth: size.width else: fallback.width,
    if size.hasHeight: size.height else: fallback.height,
  )

func resolveAutoRect*(rect, fallback: Rect): Rect =
  Rect(
    origin: rect.origin.resolveAutoPoint(fallback.origin),
    size: rect.size.resolveAutoSize(fallback.size),
  )

func initIntrinsicSize*(
    width = NoIntrinsicMetric, height = NoIntrinsicMetric
): IntrinsicSize =
  IntrinsicSize(
    width: width.normalizeOptionalMetric, height: height.normalizeOptionalMetric
  )

func initIntrinsicSize*(size: Size): IntrinsicSize =
  initIntrinsicSize(size.width, size.height)

func initFittingSize*(
    width = NoIntrinsicMetric, height = NoIntrinsicMetric
): FittingSize =
  FittingSize(
    width: width.normalizeOptionalMetric, height: height.normalizeOptionalMetric
  )

func initFittingSize*(size: Size): FittingSize =
  initFittingSize(size.width, size.height)

func hasWidth*(size: IntrinsicSize): bool =
  size.width >= 0.0'f32

func hasHeight*(size: IntrinsicSize): bool =
  size.height >= 0.0'f32

func hasWidth*(size: FittingSize): bool =
  size.width >= 0.0'f32

func hasHeight*(size: FittingSize): bool =
  size.height >= 0.0'f32

func resolveIntrinsicSize*(size: IntrinsicSize, fallback: Size): Size =
  initSize(
    if size.hasWidth: size.width else: fallback.width,
    if size.hasHeight: size.height else: fallback.height,
  )

func constrainSize*(size: Size, fittingSize: FittingSize): Size =
  initSize(
    if fittingSize.hasWidth:
      min(size.width, fittingSize.width)
    else:
      size.width,
    if fittingSize.hasHeight:
      min(size.height, fittingSize.height)
    else:
      size.height,
  )

func initLayoutPriority*(value: float32): LayoutPriority =
  LayoutPriority(max(value, 0.0'f32))

func priorityValue*(priority: LayoutPriority): float32 =
  float32(priority)

proc initRect*(
    x = AutoMetric, y = AutoMetric, width = AutoMetric, height = AutoMetric
): Rect =
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
