import std/[math, parseutils]

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

  Direction* = enum
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
    atNotAnAttribute = 0
    atLeft = 1
    atRight
    atTop
    atBottom
    atLeading
    atTrailing
    atWidth
    atHeight
    atCenterX
    atCenterY
    atLastBaseline
    atFirstBaseline

  LayoutRelation* = enum
    lrLessThanOrEqual = -1
    lrEqual = 0
    lrGreaterThanOrEqual = 1

  LayoutPriority* = distinct float32

  LayoutLengthKind* = enum
    llPoints
    llEm

  LayoutLength* = object
    kind*: LayoutLengthKind
    value*: float32

  TextAlignment* = enum
    taLeft
    taCenter
    taRight

  ButtonState* = enum
    bsOff
    bsOn
    bsMixed

  WidgetState* = enum
    ssDisabled
    ssHidden
    ssHighlighted
    ssHovered
    ssActive
    ssFocused
    ssFocusVisible
    ssFocusWithin
    ssSelected
    ssOpen
    ssAlternating
    ssPressed
    ssAccent

  ButtonType* = enum
    btMomentary
    btToggle
    btCheckBox
    btRadio

  AccessibilityRole* = enum
    arUnknown = "unknown"
    arApplication = "application"
    arWindow = "window"
    arGroup = "group"
    arStaticText = "staticText"
    arButton = "button"
    arCheckBox = "checkBox"
    arRadioButton = "radioButton"
    arTextField = "textField"
    arList = "list"
    arListItem = "listItem"
    arTable = "table"
    arCell = "cell"
    arOutline = "outline"
    arOutlineRow = "outlineRow"
    arDisclosureButton = "disclosureButton"
    arImage = "image"
    arLink = "link"
    arMenu = "menu"
    arMenuItem = "menuItem"
    arPopupButton = "popupButton"
    arComboBox = "comboBox"
    arSlider = "slider"
    arScrollArea = "scrollArea"
    arTabGroup = "tabGroup"
    arTab = "tab"

  AccessibilityTrait* = enum
    atButton = "button"
    atImage = "image"
    atLink = "link"
    atHeader = "header"
    atSelected = "selected"
    atFocused = "focused"
    atDisabled = "disabled"
    atAdjustable = "adjustable"
    atEditable = "editable"
    atSelectable = "selectable"
    atModal = "modal"
    atUpdatesFrequently = "updatesFrequently"

  AccessibilityTraits* = set[AccessibilityTrait]

  AccessibilityNotification* = enum
    anCreated = "created"
    anDestroyed = "destroyed"
    anLayoutChanged = "layoutChanged"
    anFocusedUIElementChanged = "focusedUIElementChanged"
    anValueChanged = "valueChanged"
    anSelectionChanged = "selectionChanged"
    anExpandedChanged = "expandedChanged"
    anLiveRegionChanged = "liveRegionChanged"

  PopupPresentation* = enum
    ppAutomatic ## Use popup windows when available and inline rendering otherwise.
    ppWindow ## Use a separate popup window only.
    ppInline ## Draw the popup inline in the owner window.

  CellHitPolicy* = enum
    chpDefault ## Use normal responder dispatch and bubbling.
    chpSelectRow ## Route tracking to the owning row control.
    chpTrackCell ## Let the hit cell/control handle the mouse event.
    chpSelectAndTrack ## Select the owning row, then let the cell/control track.
    chpIgnore ## Consume the event without row or cell handling.

const
  AutoMetric* = NaN.float32
  AutoPoint* = Point(x: AutoMetric, y: AutoMetric)
  AutoSize* = Size(width: AutoMetric, height: AutoMetric)
  AutoRect* = Rect(origin: AutoPoint, size: AutoSize)
  LayoutAttributeBaseline* = atLastBaseline
  NoIntrinsicMetric* = -1.0'f32
  NoIntrinsicContentSize* =
    IntrinsicSize(width: NoIntrinsicMetric, height: NoIntrinsicMetric)
  UnconstrainedFittingSize* =
    FittingSize(width: NoIntrinsicMetric, height: NoIntrinsicMetric)
  LayoutPriorityFittingSizeLevel* = LayoutPriority(50.0'f32)
  LayoutPriorityLow* = LayoutPriority(250.0'f32)
  LayoutPriorityHigh* = LayoutPriority(750.0'f32)
  LayoutPriorityRequired* = LayoutPriority(1000.0'f32)
  DefaultFontSize* = 13.0'f32

func `==`*(a, b: LayoutPriority): bool {.borrow.}
func `<`*(a, b: LayoutPriority): bool {.borrow.}
func `<=`*(a, b: LayoutPriority): bool {.borrow.}

func layoutAxis*(direction: Direction): LayoutAxis =
  case direction
  of dcol: laHorizontal
  of drow: laVertical

func direction*(axis: LayoutAxis): Direction =
  case axis
  of laHorizontal: dcol
  of laVertical: drow

func initLayoutLength*(kind: LayoutLengthKind, value: float32): LayoutLength =
  LayoutLength(kind: kind, value: value)

func points*(value: float32): LayoutLength =
  initLayoutLength(llPoints, value)

func em*(value: float32): LayoutLength =
  initLayoutLength(llEm, value)

proc `'em`*(raw: string): LayoutLength =
  var value: float
  if parseFloat(raw, value) == 0:
    return em(0.0'f32)
  em(value.float32)

func resolveLayoutLength*(length: LayoutLength, fontSize = DefaultFontSize): float32 =
  case length.kind
  of llPoints:
    length.value
  of llEm:
    length.value * fontSize

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
