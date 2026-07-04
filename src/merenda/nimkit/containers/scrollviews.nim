import sigils/core

import ../app/animations
import ../accessibility/accessibilityprotocols
import ../drawing
import ./scrollergeometry
import ../foundation/selectors
import ../themes
import ../foundation/events
import ../foundation/types
import ../view/viewgeometry
import ../view/views

export views

type
  ScrollViewBorderType* = enum
    svbNoBorder
    svbLineBorder
    svbBezelBorder

  ScrollerAutohidePolicy* = enum
    sapNever
    sapWhenNeeded
    sapAlways

  RulerPlaceholder* = object
    visible*: bool
    thickness*: float32

  ClipView* = ref object of View
    xScrollView: ScrollView
    xDocumentView: View
    xDocumentCursor: string
    xDrawsBackground: bool

  Scroller* = ref object of View
    xScrollView: ScrollView
    xAxis: LayoutAxis
    xTracking: ScrollerTrackingState

  ScrollView* = ref object of View
    xClipView: ClipView
    xDocumentView: View
    xScroller: array[LayoutAxis, Scroller]
    xHasScroller: array[LayoutAxis, bool]
    xAutohidePolicy: ScrollerAutohidePolicy
    xScrollerThickness: float32
    xLineScroll: array[LayoutAxis, float32]
    xPageScroll: array[LayoutAxis, float32]
    xBorderType: ScrollViewBorderType
    xDrawsBackground: bool
    xScrollViewRole: StyleRole
    xScrollerRole: StyleRole
    xScrollerInsets: EdgeInsets
    xHeaderView: array[LayoutAxis, View]
    xCornerView: View
    xRuler: array[LayoutAxis, RulerPlaceholder]
    xDynamicScrolling: bool

func normalizedScrollerThickness(value: float32): float32 =
  max(value, 0.0'f32)

func normalizedLineScroll(value: float32): float32 =
  max(value, 1.0'f32)

func normalizedPageScroll(value: float32): float32 =
  max(value, 1.0'f32)

func normalizedRulerThickness(value: float32): float32 =
  max(value, 0.0'f32)

func normalizedInsets(insets: EdgeInsets): EdgeInsets =
  insets(
    max(insets.top, 0.0'f32),
    max(insets.left, 0.0'f32),
    max(insets.bottom, 0.0'f32),
    max(insets.right, 0.0'f32),
  )

proc contentOffset*(scrollView: ScrollView): Point
proc `contentOffset=`*(scrollView: ScrollView, offset: Point)
proc horizontalScrollerRect*(scrollView: ScrollView): Rect
proc verticalScrollerRect*(scrollView: ScrollView): Rect
proc drawScroller*(context: DrawContext, track, knob: Rect, style: ScrollViewStyle)
proc scrollViewRole*(scrollView: ScrollView): StyleRole
proc scrollerRole*(scrollView: ScrollView): StyleRole

proc documentRect*(clipView: ClipView): Rect
proc lineScroll*(scrollView: ScrollView, axis: LayoutAxis): float32
proc reflectScrolledClipView*(scrollView: ScrollView, clipView: ClipView)

proc scrollViewStyleContext(scrollView: ScrollView): StyleContext =
  controlStyle(
    scrollView.scrollViewRole(),
    scrollView.widgetStateSet(),
    id = scrollView.styleId(),
    classes = scrollView.styleClasses(),
  )

proc scrollerStyleContext(scroller: Scroller): StyleContext =
  if scroller.isNil or scroller.xScrollView.isNil:
    controlStyle(srScroller)
  else:
    controlStyle(
      scroller.xScrollView.scrollerRole(),
      scroller.widgetStateSet(),
      id = scroller.xScrollView.styleId(),
      classes = scroller.xScrollView.styleClasses(),
    )

protocol ScrollTransactionAnimProtocol:
  method animContentOffset*(offset: Point)

protocol ScrollTransactionAnim of ScrollTransactionAnimProtocol:
  method animContentOffset(scrollView: ScrollView, offset: Point) =
    scrollView.contentOffset = offset

protocol DefaultScrollViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(scrollView: ScrollView): AccessibilityRole =
    arScrollArea

  method accessibilityValue(scrollView: ScrollView): string =
    let offset = scrollView.contentOffset()
    $offset.x & "," & $offset.y

  method accessibilityTraits(scrollView: ScrollView): AccessibilityTraits =
    result = scrollView.xAccessibilityTraits
    if ssDisabled in scrollView.xWidgetStates:
      result.incl atDisabled
    if ssFocused in scrollView.xWidgetStates:
      result.incl atFocused

  method isAccessibilityElement(scrollView: ScrollView): bool =
    true

proc initRulerPlaceholder*(visible = false, thickness = 0.0'f32): RulerPlaceholder =
  RulerPlaceholder(visible: visible, thickness: normalizedRulerThickness(thickness))

func visibleScrollerAxes(
    boundsSize, documentSize: Size,
    hasHorizontal, hasVertical: bool,
    autohidePolicy: ScrollerAutohidePolicy,
    thickness: float32,
): set[LayoutAxis] =
  var
    visible: set[LayoutAxis] = {}
    viewport = boundsSize

  for _ in 0 ..< 3:
    let
      nextHorizontal =
        hasHorizontal and autohidePolicy != sapAlways and
        (autohidePolicy == sapNever or documentSize.width > viewport.width)
      nextVertical =
        hasVertical and autohidePolicy != sapAlways and
        (autohidePolicy == sapNever or documentSize.height > viewport.height)
      nextVisible =
        (if nextHorizontal: {laHorizontal} else: {}) +
        (if nextVertical: {laVertical} else: {})
    if nextVisible == visible:
      return visible
    visible = nextVisible
    viewport = initSize(
      max(boundsSize.width - (if laVertical in visible: thickness else: 0.0'f32), 0.0),
      max(
        boundsSize.height - (if laHorizontal in visible: thickness else: 0.0'f32), 0.0
      ),
    )

  visible

proc documentSize*(scrollView: ScrollView): Size =
  scrollView.xClipView.documentRect().size

proc contentSize*(scrollView: ScrollView): Size =
  scrollView.documentSize()

proc headerChromeThickness(scrollView: ScrollView, axis: LayoutAxis): float32 =
  if scrollView.isNil:
    return 0.0'f32
  let header = scrollView.xHeaderView[axis]
  if not header.isNil:
    case axis
    of laHorizontal:
      result = max(result, header.frame.size.height)
    of laVertical:
      result = max(result, header.frame.size.width)
  if scrollView.xRuler[axis].visible:
    result = max(result, scrollView.xRuler[axis].thickness)

proc chromeContentSize(scrollView: ScrollView): Size =
  if scrollView.isNil:
    return initSize(0.0, 0.0)
  initSize(
    max(
      scrollView.bounds().size.width - scrollView.xScrollerInsets.left -
        scrollView.xScrollerInsets.right - scrollView.headerChromeThickness(laVertical),
      0.0'f32,
    ),
    max(
      scrollView.bounds().size.height - scrollView.xScrollerInsets.top -
        scrollView.xScrollerInsets.bottom -
        scrollView.headerChromeThickness(laHorizontal),
      0.0'f32,
    ),
  )

proc visibleScrollerAxes(scrollView: ScrollView): set[LayoutAxis] =
  visibleScrollerAxes(
    scrollView.chromeContentSize(),
    scrollView.documentSize(),
    scrollView.xHasScroller[laHorizontal],
    scrollView.xHasScroller[laVertical],
    scrollView.xAutohidePolicy,
    scrollView.xScrollerThickness,
  )

proc viewportSize*(scrollView: ScrollView): Size =
  let visible = scrollView.visibleScrollerAxes()
  let
    contentSize = scrollView.chromeContentSize()
    scrollerWidth =
      if laVertical in visible: scrollView.xScrollerThickness else: 0.0'f32
    scrollerHeight =
      if laHorizontal in visible: scrollView.xScrollerThickness else: 0.0'f32
    width = max(contentSize.width - scrollerWidth, 0.0'f32)
    height = max(contentSize.height - scrollerHeight, 0.0'f32)
  initSize(width, height)

proc viewportRect*(scrollView: ScrollView): Rect =
  initRect(
    initPoint(
      scrollView.xScrollerInsets.left + scrollView.headerChromeThickness(laVertical),
      scrollView.xScrollerInsets.top + scrollView.headerChromeThickness(laHorizontal),
    ),
    scrollView.viewportSize(),
  )

proc maximumContentOffset*(scrollView: ScrollView): Point =
  let
    documentSize = scrollView.documentSize()
    viewportSize = scrollView.viewportSize()
  initPoint(
    max(documentSize.width - viewportSize.width, 0.0'f32),
    max(documentSize.height - viewportSize.height, 0.0'f32),
  )

func clampedScrollFraction(value: float32): float32 =
  min(max(value, 0.0'f32), 1.0'f32)

proc contentOffsetForFraction*(
    scrollView: ScrollView, x = AutoMetric, y = AutoMetric
): Point =
  let maximumOffset = scrollView.maximumContentOffset()
  result = scrollView.contentOffset()
  if not x.isAutoMetric:
    result.x = maximumOffset.x * clampedScrollFraction(x)
  if not y.isAutoMetric:
    result.y = maximumOffset.y * clampedScrollFraction(y)

proc contentOffsetForFraction*(scrollView: ScrollView, fraction: Point): Point =
  scrollView.contentOffsetForFraction(fraction.x, fraction.y)

proc clampContentOffset(scrollView: ScrollView, offset: Point): Point =
  let
    viewportSize = scrollView.viewportSize()
    documentSize = scrollView.documentSize()
    horizontal = initScrollViewport(0.0, viewportSize.width, documentSize.width)
    vertical = initScrollViewport(0.0, viewportSize.height, documentSize.height)
  initPoint(
    horizontal.clampScrollOffset(offset.x), vertical.clampScrollOffset(offset.y)
  )

proc documentView*(clipView: ClipView): View =
  clipView.xDocumentView

proc documentRect*(clipView: ClipView): Rect =
  let document = clipView.documentView()
  if document.isNil:
    initRect(0.0, 0.0, 0.0, 0.0)
  else:
    document.frame()

proc documentVisibleRect*(clipView: ClipView): Rect =
  clipView.bounds()

proc visibleRect*(clipView: ClipView): Rect =
  clipView.documentVisibleRect()

proc documentCursor*(clipView: ClipView): string =
  clipView.xDocumentCursor

proc `documentCursor=`*(clipView: ClipView, cursor: string) =
  if clipView.isNil or clipView.xDocumentCursor == cursor:
    return
  clipView.xDocumentCursor = cursor

proc drawsBackground*(clipView: ClipView): bool =
  clipView.xDrawsBackground

proc `drawsBackground=`*(clipView: ClipView, value: bool) =
  if clipView.isNil or clipView.xDrawsBackground == value:
    return
  clipView.xDrawsBackground = value
  clipView.setNeedsDisplay(true)

proc constrainScrollPoint*(clipView: ClipView, point: Point): Point =
  if clipView.isNil or clipView.xScrollView.isNil:
    return point
  clipView.xScrollView.clampContentOffset(point)

proc scrollToPoint*(clipView: ClipView, point: Point) =
  if clipView.isNil:
    return
  let
    nextPoint = clipView.constrainScrollPoint(point)
    nextBounds = initRect(nextPoint, clipView.bounds().size)
  if clipView.bounds() == nextBounds:
    return
  clipView.bounds = nextBounds
  if not clipView.xScrollView.isNil:
    clipView.xScrollView.reflectScrolledClipView(clipView)

proc autoscroll*(clipView: ClipView, event: MouseEvent): bool =
  if clipView.isNil or clipView.xScrollView.isNil:
    return false
  let
    bounds = clipView.bounds()
    edge = min(24.0'f32, min(bounds.size.width, bounds.size.height) / 4.0'f32)
  var delta = initPoint(0.0, 0.0)
  if event.location.x < bounds.minX + edge:
    delta.x = -clipView.xScrollView.lineScroll(laHorizontal)
  elif event.location.x >= bounds.maxX - edge:
    delta.x = clipView.xScrollView.lineScroll(laHorizontal)
  if event.location.y < bounds.minY + edge:
    delta.y = -clipView.xScrollView.lineScroll(laVertical)
  elif event.location.y >= bounds.maxY - edge:
    delta.y = clipView.xScrollView.lineScroll(laVertical)
  if delta.x == 0.0'f32 and delta.y == 0.0'f32:
    return false
  let nextPoint = clipView.constrainScrollPoint(bounds.origin.offset(delta.x, delta.y))
  result = nextPoint != bounds.origin
  if result:
    clipView.scrollToPoint(nextPoint)

protocol DefaultClipViewDrawing of ViewDrawingProtocol:
  method draw(clipView: ClipView, context: DrawContext) =
    if clipView.drawsBackground():
      discard context.addRenderRectangle(
        context.renderRectFor(context.bounds),
        fill(clipView.backgroundColor()),
        initColor(0.0, 0.0, 0.0, 0.0),
        0.0'f32,
        0.0'f32,
      )

protocol DefaultClipViewGeometry of ViewProtocol:
  method setBounds(clipView: ClipView, bounds: Rect) =
    let constrained =
      initRect(clipView.constrainScrollPoint(bounds.origin), bounds.size)
    if clipView.xBounds == constrained:
      return
    clipView.xBounds = initRect(constrained.origin, constrained.size)
    emit clipView.layoutInputChanged(lirBounds)
    emit clipView.geometryDidChange()
    clipView.setNeedsDisplay(true)
    if not clipView.xScrollView.isNil:
      clipView.xScrollView.reflectScrolledClipView(clipView)

proc setClipViewBoundsOrigin(scrollView: ScrollView, offset: Point) =
  if scrollView.isNil or scrollView.xClipView.isNil:
    return
  scrollView.xClipView.scrollToPoint(offset)

proc horizontalHeaderRect(scrollView: ScrollView): Rect =
  if scrollView.isNil or scrollView.xHeaderView[laHorizontal].isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let
    viewport = scrollView.viewportRect()
    height = scrollView.headerChromeThickness(laHorizontal)
  if height <= 0.0'f32:
    return initRect(0.0, 0.0, 0.0, 0.0)
  initRect(
    viewport.origin.x, scrollView.xScrollerInsets.top, viewport.size.width, height
  )

proc verticalHeaderRect(scrollView: ScrollView): Rect =
  if scrollView.isNil or scrollView.xHeaderView[laVertical].isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let
    viewport = scrollView.viewportRect()
    width = scrollView.headerChromeThickness(laVertical)
  if width <= 0.0'f32:
    return initRect(0.0, 0.0, 0.0, 0.0)
  initRect(
    scrollView.xScrollerInsets.left, viewport.origin.y, width, viewport.size.height
  )

proc cornerViewRect(scrollView: ScrollView): Rect =
  if scrollView.isNil or scrollView.xCornerView.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let
    visibleAxes = scrollView.visibleScrollerAxes()
    viewport = scrollView.viewportRect()
    horizontalHeaderHeight = scrollView.headerChromeThickness(laHorizontal)
    verticalHeaderWidth = scrollView.headerChromeThickness(laVertical)
    scrollerWidth =
      if laVertical in visibleAxes: scrollView.xScrollerThickness else: 0.0'f32
    scrollerHeight =
      if laHorizontal in visibleAxes: scrollView.xScrollerThickness else: 0.0'f32

  if horizontalHeaderHeight > 0.0'f32 and scrollerWidth > 0.0'f32:
    return initRect(
      viewport.origin.x + viewport.size.width,
      scrollView.xScrollerInsets.top,
      scrollerWidth,
      horizontalHeaderHeight,
    )
  if verticalHeaderWidth > 0.0'f32 and scrollerHeight > 0.0'f32:
    return initRect(
      scrollView.xScrollerInsets.left,
      viewport.origin.y + viewport.size.height,
      verticalHeaderWidth,
      scrollerHeight,
    )
  if scrollerWidth > 0.0'f32 and scrollerHeight > 0.0'f32:
    return initRect(
      viewport.origin.x + viewport.size.width,
      viewport.origin.y + viewport.size.height,
      scrollerWidth,
      scrollerHeight,
    )
  initRect(0.0, 0.0, 0.0, 0.0)

proc applyChromeFrame(view: View, frame: Rect) =
  if view.isNil:
    return
  view.frame = frame
  view.hidden = frame.size.width <= 0.0'f32 or frame.size.height <= 0.0'f32

proc tile*(scrollView: ScrollView) =
  if scrollView.isNil or scrollView.xClipView.isNil:
    return
  let visibleAxes = scrollView.visibleScrollerAxes()
  scrollView.xClipView.frame = scrollView.viewportRect()
  scrollView.setClipViewBoundsOrigin(scrollView.contentOffset())
  applyChromeFrame(
    scrollView.xHeaderView[laHorizontal], scrollView.horizontalHeaderRect()
  )
  applyChromeFrame(scrollView.xHeaderView[laVertical], scrollView.verticalHeaderRect())
  applyChromeFrame(scrollView.xCornerView, scrollView.cornerViewRect())
  if not scrollView.xScroller[laHorizontal].isNil:
    scrollView.xScroller[laHorizontal].frame = scrollView.horizontalScrollerRect()
    scrollView.xScroller[laHorizontal].hidden = laHorizontal notin visibleAxes
  if not scrollView.xScroller[laVertical].isNil:
    scrollView.xScroller[laVertical].frame = scrollView.verticalScrollerRect()
    scrollView.xScroller[laVertical].hidden = laVertical notin visibleAxes

proc clipView*(scrollView: ScrollView): ClipView =
  scrollView.xClipView

proc contentView*(scrollView: ScrollView): View =
  scrollView.clipView()

proc horizontalScroller*(scrollView: ScrollView): Scroller =
  scrollView.xScroller[laHorizontal]

proc verticalScroller*(scrollView: ScrollView): Scroller =
  scrollView.xScroller[laVertical]

proc documentView*(scrollView: ScrollView): View =
  scrollView.xDocumentView

proc `documentView=`*(scrollView: ScrollView, documentView: View) =
  if scrollView.isNil or scrollView.xDocumentView == documentView:
    return
  if not scrollView.xDocumentView.isNil:
    scrollView.xDocumentView.removeFromSuperview()
  scrollView.xDocumentView = documentView
  scrollView.xClipView.xDocumentView = documentView
  if not documentView.isNil:
    scrollView.xClipView.addSubview(documentView)
  scrollView.tile()
  scrollView.invalidateContainerMetrics()
  scrollView.setNeedsDisplay(true)

proc contentOffset*(scrollView: ScrollView): Point =
  scrollView.xClipView.constrainScrollPoint(scrollView.xClipView.bounds().origin)

proc `contentOffset=`*(scrollView: ScrollView, offset: Point) =
  scrollView.tile()
  let nextOffset = scrollView.clampContentOffset(offset)
  let oldOffset = scrollView.contentOffset()
  if oldOffset == nextOffset:
    return
  discard scrollView.withProtocol(ScrollTransactionAnim)
  discard recordPropertyAnimation(
    DynamicAgent(scrollView), animContentOffset(), oldOffset, nextOffset
  )
  scrollView.xClipView.scrollToPoint(nextOffset)

proc scrollTo*(scrollView: ScrollView, offset: Point) =
  scrollView.contentOffset = offset

proc scrollToFraction*(scrollView: ScrollView, x = AutoMetric, y = AutoMetric) =
  scrollView.scrollTo(scrollView.contentOffsetForFraction(x, y))

proc scrollToFraction*(scrollView: ScrollView, fraction: Point) =
  scrollView.scrollToFraction(fraction.x, fraction.y)

proc scrollBy*(scrollView: ScrollView, delta: Point) =
  let current = scrollView.contentOffset()
  scrollView.contentOffset = initPoint(current.x + delta.x, current.y + delta.y)

proc scrollRectToVisible*(scrollView: ScrollView, rect: Rect): bool =
  let
    currentOffset = scrollView.contentOffset()
    viewportSize = scrollView.viewportSize()
    viewport = initRect(currentOffset, viewportSize)
  var nextOffset = currentOffset

  if rect.minX < viewport.minX:
    nextOffset.x = rect.minX
  elif rect.maxX > viewport.maxX:
    nextOffset.x = rect.maxX - viewport.size.width

  if rect.minY < viewport.minY:
    nextOffset.y = rect.minY
  elif rect.maxY > viewport.maxY:
    nextOffset.y = rect.maxY - viewport.size.height

  nextOffset = scrollView.clampContentOffset(nextOffset)
  result = nextOffset != currentOffset
  if result:
    scrollView.contentOffset = nextOffset

proc scrollWheelDelta*(scrollView: ScrollView, event: ScrollEvent): Point =
  if kmShift in event.modifiers and event.deltaY != 0.0'f32:
    return initPoint(
      (if event.deltaX != 0.0'f32: event.deltaX
      else: -event.deltaY) * scrollView.xLineScroll[laHorizontal],
      0.0'f32,
    )
  initPoint(
    event.deltaX * scrollView.xLineScroll[laHorizontal],
    -event.deltaY * scrollView.xLineScroll[laVertical],
  )

proc scrollWheelWouldMove(scrollView: ScrollView, event: ScrollEvent): bool =
  let
    delta = scrollView.scrollWheelDelta(event)
    currentOffset = scrollView.contentOffset()
    nextOffset = scrollView.clampContentOffset(
      initPoint(currentOffset.x + delta.x, currentOffset.y + delta.y)
    )
  nextOffset != currentOffset

proc scrollerMetricsChanged(scrollView: ScrollView) =
  scrollView.tile()
  scrollView.invalidateContainerMetrics()
  scrollView.setNeedsDisplay(true)

proc reflectScrolledClipView*(scrollView: ScrollView, clipView: ClipView) =
  if scrollView.isNil or clipView.isNil or clipView != scrollView.xClipView:
    return
  scrollView.tile()
  scrollView.setNeedsDisplay(true)

proc hasScroller*(scrollView: ScrollView, axis: LayoutAxis): bool =
  scrollView.xHasScroller[axis]

proc setHasScroller*(scrollView: ScrollView, axis: LayoutAxis, value: bool) =
  if scrollView.isNil or scrollView.xHasScroller[axis] == value:
    return
  scrollView.xHasScroller[axis] = value
  scrollView.scrollerMetricsChanged()

proc hasHorizontalScroller*(scrollView: ScrollView): bool =
  scrollView.hasScroller(laHorizontal)

proc `hasHorizontalScroller=`*(scrollView: ScrollView, value: bool) =
  scrollView.setHasScroller(laHorizontal, value)

proc hasVerticalScroller*(scrollView: ScrollView): bool =
  scrollView.hasScroller(laVertical)

proc `hasVerticalScroller=`*(scrollView: ScrollView, value: bool) =
  scrollView.setHasScroller(laVertical, value)

proc autohidesScrollers*(scrollView: ScrollView): bool =
  scrollView.xAutohidePolicy == sapWhenNeeded

proc `autohidesScrollers=`*(scrollView: ScrollView, value: bool) =
  if scrollView.isNil:
    return
  let policy = if value: sapWhenNeeded else: sapNever
  if scrollView.xAutohidePolicy == policy:
    return
  scrollView.xAutohidePolicy = policy
  scrollView.scrollerMetricsChanged()

proc autohidePolicy*(scrollView: ScrollView): ScrollerAutohidePolicy =
  scrollView.xAutohidePolicy

proc `autohidePolicy=`*(scrollView: ScrollView, policy: ScrollerAutohidePolicy) =
  if scrollView.isNil or scrollView.xAutohidePolicy == policy:
    return
  scrollView.xAutohidePolicy = policy
  scrollView.scrollerMetricsChanged()

proc scrollerThickness*(scrollView: ScrollView): float32 =
  scrollView.xScrollerThickness

proc `scrollerThickness=`*(scrollView: ScrollView, value: float32) =
  let nextValue = value.normalizedScrollerThickness()
  if scrollView.xScrollerThickness == nextValue:
    return
  scrollView.xScrollerThickness = nextValue
  scrollView.scrollerMetricsChanged()

proc lineScroll*(scrollView: ScrollView): float32 =
  scrollView.xLineScroll[laVertical]

proc lineScroll*(scrollView: ScrollView, axis: LayoutAxis): float32 =
  scrollView.xLineScroll[axis]

proc `lineScroll=`*(scrollView: ScrollView, value: float32) =
  if scrollView.isNil:
    return
  let normalized = value.normalizedLineScroll()
  scrollView.xLineScroll[laHorizontal] = normalized
  scrollView.xLineScroll[laVertical] = normalized

proc setLineScroll*(scrollView: ScrollView, axis: LayoutAxis, value: float32) =
  if scrollView.isNil:
    return
  scrollView.xLineScroll[axis] = value.normalizedLineScroll()

proc horizontalLineScroll*(scrollView: ScrollView): float32 =
  scrollView.lineScroll(laHorizontal)

proc `horizontalLineScroll=`*(scrollView: ScrollView, value: float32) =
  scrollView.setLineScroll(laHorizontal, value)

proc verticalLineScroll*(scrollView: ScrollView): float32 =
  scrollView.lineScroll(laVertical)

proc `verticalLineScroll=`*(scrollView: ScrollView, value: float32) =
  scrollView.setLineScroll(laVertical, value)

proc pageScroll*(scrollView: ScrollView, axis: LayoutAxis): float32 =
  if scrollView.isNil:
    return 0.0'f32
  if scrollView.xPageScroll[axis] <= 0.0'f32:
    return scrollView.viewportSize().axisSize(axis)
  scrollView.xPageScroll[axis]

proc pageScroll*(scrollView: ScrollView): float32 =
  scrollView.pageScroll(laVertical)

proc `pageScroll=`*(scrollView: ScrollView, value: float32) =
  if scrollView.isNil:
    return
  let normalized = value.normalizedPageScroll()
  scrollView.xPageScroll[laHorizontal] = normalized
  scrollView.xPageScroll[laVertical] = normalized

proc setPageScroll*(scrollView: ScrollView, axis: LayoutAxis, value: float32) =
  if scrollView.isNil:
    return
  scrollView.xPageScroll[axis] = value.normalizedPageScroll()

proc horizontalPageScroll*(scrollView: ScrollView): float32 =
  scrollView.pageScroll(laHorizontal)

proc `horizontalPageScroll=`*(scrollView: ScrollView, value: float32) =
  scrollView.setPageScroll(laHorizontal, value)

proc verticalPageScroll*(scrollView: ScrollView): float32 =
  scrollView.pageScroll(laVertical)

proc `verticalPageScroll=`*(scrollView: ScrollView, value: float32) =
  scrollView.setPageScroll(laVertical, value)

proc borderType*(scrollView: ScrollView): ScrollViewBorderType =
  scrollView.xBorderType

proc `borderType=`*(scrollView: ScrollView, borderType: ScrollViewBorderType) =
  if scrollView.isNil or scrollView.xBorderType == borderType:
    return
  scrollView.xBorderType = borderType
  scrollView.setNeedsDisplay(true)

proc drawsBackground*(scrollView: ScrollView): bool =
  scrollView.xDrawsBackground

proc `drawsBackground=`*(scrollView: ScrollView, value: bool) =
  if scrollView.isNil or scrollView.xDrawsBackground == value:
    return
  scrollView.xDrawsBackground = value
  scrollView.setNeedsDisplay(true)

proc scrollViewRole*(scrollView: ScrollView): StyleRole =
  if scrollView.isNil: srScrollView else: scrollView.xScrollViewRole

proc `scrollViewRole=`*(scrollView: ScrollView, role: StyleRole) =
  if scrollView.isNil or scrollView.xScrollViewRole == role:
    return
  scrollView.xScrollViewRole = role
  scrollView.setNeedsDisplay(true)

proc scrollerRole*(scrollView: ScrollView): StyleRole =
  if scrollView.isNil: srScroller else: scrollView.xScrollerRole

proc `scrollerRole=`*(scrollView: ScrollView, role: StyleRole) =
  if scrollView.isNil or scrollView.xScrollerRole == role:
    return
  scrollView.xScrollerRole = role
  scrollView.setNeedsDisplay(true)
  for scroller in scrollView.xScroller:
    if not scroller.isNil:
      scroller.setNeedsDisplay(true)

proc scrollerInsets*(scrollView: ScrollView): EdgeInsets =
  scrollView.xScrollerInsets

proc `scrollerInsets=`*(scrollView: ScrollView, insets: EdgeInsets) =
  if scrollView.isNil:
    return
  let normalized = insets.normalizedInsets()
  if scrollView.xScrollerInsets == normalized:
    return
  scrollView.xScrollerInsets = normalized
  scrollView.scrollerMetricsChanged()

proc headerView*(scrollView: ScrollView, axis: LayoutAxis): View =
  scrollView.xHeaderView[axis]

proc setHeaderView*(scrollView: ScrollView, axis: LayoutAxis, view: View) =
  if scrollView.isNil or scrollView.xHeaderView[axis] == view:
    return
  if not scrollView.xHeaderView[axis].isNil:
    scrollView.xHeaderView[axis].removeFromSuperview()
  scrollView.xHeaderView[axis] = view
  if not view.isNil:
    scrollView.addSubview(view)
  scrollView.scrollerMetricsChanged()

proc horizontalHeaderView*(scrollView: ScrollView): View =
  scrollView.headerView(laHorizontal)

proc `horizontalHeaderView=`*(scrollView: ScrollView, view: View) =
  scrollView.setHeaderView(laHorizontal, view)

proc verticalHeaderView*(scrollView: ScrollView): View =
  scrollView.headerView(laVertical)

proc `verticalHeaderView=`*(scrollView: ScrollView, view: View) =
  scrollView.setHeaderView(laVertical, view)

proc cornerView*(scrollView: ScrollView): View =
  scrollView.xCornerView

proc `cornerView=`*(scrollView: ScrollView, view: View) =
  if scrollView.isNil or scrollView.xCornerView == view:
    return
  if not scrollView.xCornerView.isNil:
    scrollView.xCornerView.removeFromSuperview()
  scrollView.xCornerView = view
  if not view.isNil:
    scrollView.addSubview(view)
  scrollView.scrollerMetricsChanged()

proc rulerPlaceholder*(scrollView: ScrollView, axis: LayoutAxis): RulerPlaceholder =
  scrollView.xRuler[axis]

proc setRulerPlaceholder*(
    scrollView: ScrollView, axis: LayoutAxis, ruler: RulerPlaceholder
) =
  if scrollView.isNil:
    return
  let normalized = initRulerPlaceholder(ruler.visible, ruler.thickness)
  if scrollView.xRuler[axis] == normalized:
    return
  scrollView.xRuler[axis] = normalized
  scrollView.scrollerMetricsChanged()

proc dynamicScrolling*(scrollView: ScrollView): bool =
  scrollView.xDynamicScrolling

proc `dynamicScrolling=`*(scrollView: ScrollView, value: bool) =
  if scrollView.isNil or scrollView.xDynamicScrolling == value:
    return
  scrollView.xDynamicScrolling = value

proc horizontalScrollerRect*(scrollView: ScrollView): Rect =
  if scrollView.isNil or laHorizontal notin scrollView.visibleScrollerAxes():
    return initRect(0.0, 0.0, 0.0, 0.0)
  let viewport = scrollView.viewportRect()
  initRect(
    viewport.origin.x,
    viewport.origin.y + viewport.size.height,
    viewport.size.width,
    scrollView.xScrollerThickness,
  )

proc verticalScrollerRect*(scrollView: ScrollView): Rect =
  if scrollView.isNil or laVertical notin scrollView.visibleScrollerAxes():
    return initRect(0.0, 0.0, 0.0, 0.0)
  let viewport = scrollView.viewportRect()
  initRect(
    viewport.origin.x + viewport.size.width,
    viewport.origin.y,
    scrollView.xScrollerThickness,
    viewport.size.height,
  )

proc scrollerTrackRect*(scroller: Scroller): Rect =
  scroller.bounds()

proc scrollerKnobRect*(scroller: Scroller): Rect =
  if scroller.isNil or scroller.xScrollView.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let
    track = scroller.scrollerTrackRect()
    scrollView = scroller.xScrollView
    viewport = scrollView.viewportSize()
    document = scrollView.documentSize()
    offset = scrollView.contentOffset()

  case scroller.xAxis
  of laHorizontal:
    scrollerKnobRect(
      track, laHorizontal, initScrollViewport(offset.x, viewport.width, document.width)
    )
  of laVertical:
    scrollerKnobRect(
      track, laVertical, initScrollViewport(offset.y, viewport.height, document.height)
    )

proc drawScroller*(context: DrawContext, track, knob: Rect, style: ScrollViewStyle) =
  if track.isEmpty:
    return
  let trackBox = style.scrollerTrack
  discard context.addRenderRectangle(
    context.renderRectFor(track),
    trackBox.fill,
    trackBox.borderColor,
    trackBox.borderWidth,
    trackBox.cornerRadius,
    trackBox.shadows,
    cornerRadii = trackBox.cornerRadii,
  )
  if not knob.isEmpty:
    let knobBox = style.scrollerKnob
    discard context.addRenderRectangle(
      context.renderRectFor(knob.inset(insets(2.0))),
      knobBox.fill,
      knobBox.borderColor,
      knobBox.borderWidth,
      knobBox.cornerRadius,
      knobBox.shadows,
      cornerRadii = knobBox.cornerRadii.inset(2.0),
    )

proc setContentOffset(scrollView: ScrollView, axis: LayoutAxis, offset: float32) =
  var nextOffset = scrollView.contentOffset()
  case axis
  of laHorizontal:
    nextOffset.x = offset
  of laVertical:
    nextOffset.y = offset
  scrollView.contentOffset = nextOffset

proc scrollKnobTo(scroller: Scroller, point: Point) =
  if scroller.isNil or scroller.xScrollView.isNil:
    return
  let
    knobOrigin = scroller.xTracking.knobOriginForPoint(scroller.xAxis, point)
    track = scroller.scrollerTrackRect()
    knob = scroller.scrollerKnobRect()
    maxOffset = scroller.xScrollView.maximumContentOffset().axisOffset(scroller.xAxis)
  scroller.xScrollView.setContentOffset(
    scroller.xAxis,
    contentOffsetForScrollerKnobOrigin(
      track, knob, scroller.xAxis, maxOffset, knobOrigin
    ),
  )

proc scrollPageToward(scroller: Scroller, point: Point) =
  if scroller.isNil or scroller.xScrollView.isNil:
    return
  let
    knob = scroller.scrollerKnobRect()
    pointOnAxis = point.axisOffset(scroller.xAxis)
  if knob.isEmpty or (
    pointOnAxis >= knob.axisOrigin(scroller.xAxis) and
    pointOnAxis < knob.axisMax(scroller.xAxis)
  ):
    return

  let
    direction = if pointOnAxis < knob.axisOrigin(scroller.xAxis): -1.0'f32 else: 1.0'f32
    scrollView = scroller.xScrollView
    currentOffset = scrollView.contentOffset().axisOffset(scroller.xAxis)
    page = scrollView.pageScroll(scroller.xAxis)
  scrollView.setContentOffset(scroller.xAxis, currentOffset + direction * page)

protocol DefaultScrollViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(scrollView: ScrollView): IntrinsicSize =
    NoIntrinsicContentSize

  method layoutSubviews(scrollView: ScrollView) =
    scrollView.tile()

protocol DefaultScrollViewDrawing of ViewDrawingProtocol:
  method draw(scrollView: ScrollView, context: DrawContext) =
    let
      style =
        context.appearance.resolveScrollViewStyle(scrollView.scrollViewStyleContext())
      borderWidth =
        case scrollView.borderType()
        of svbNoBorder: 0.0'f32
        of svbLineBorder, svbBezelBorder: style.box.borderWidth
      borderColor =
        if borderWidth > 0.0'f32:
          style.box.borderColor
        else:
          initColor(0.0, 0.0, 0.0, 0.0)
      fillStyle =
        if scrollView.drawsBackground():
          style.box.fill
        else:
          fill(initColor(0.0, 0.0, 0.0, 0.0))

    if scrollView.drawsBackground() or borderWidth > 0.0'f32:
      discard context.addRenderRectangle(
        context.renderRectFor(context.bounds),
        fillStyle,
        borderColor,
        borderWidth,
        style.box.cornerRadius,
        style.box.shadows,
        cornerRadii = style.box.cornerRadii,
      )

protocol DefaultScrollerDrawing of ViewDrawingProtocol:
  method draw(scroller: Scroller, context: DrawContext) =
    let style =
      context.appearance.resolveScrollViewStyle(scroller.scrollerStyleContext())
    context.drawScroller(
      scroller.scrollerTrackRect(), scroller.scrollerKnobRect(), style
    )

protocol DefaultScrollerEvents of ResponderEventProtocol:
  method mouseDown(scroller: Scroller, event: MouseEvent): bool =
    if event.button != mbPrimary or scroller.isNil or scroller.xScrollView.isNil:
      return false
    let
      track = scroller.scrollerTrackRect()
      knob = scroller.scrollerKnobRect()
    if scroller.xTracking.beginScrollerTracking(
      track, knob, scroller.xAxis, event.location
    ):
      return true
    if track.contains(event.location):
      scroller.scrollPageToward(event.location)
      return true
    false

  method mouseDragged(scroller: Scroller, event: MouseEvent): bool =
    if event.button == mbPrimary and not scroller.isNil and
        scroller.xTracking.isDraggingKnob():
      scroller.scrollKnobTo(event.location)
      return true
    false

  method mouseUp(scroller: Scroller, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false
    if scroller.xTracking.isDraggingKnob():
      scroller.scrollKnobTo(event.location)
    scroller.xTracking.endScrollerTracking()
    true

protocol DefaultScrollViewEvents of ResponderEventProtocol:
  method wantsForwardedScrollEvents(scrollView: ScrollView, event: ScrollEvent): bool =
    not scrollView.scrollWheelWouldMove(event)

  method scrollWheel(scrollView: ScrollView, event: ScrollEvent): bool =
    if scrollView.scrollWheelWouldMove(event):
      scrollView.scrollBy(scrollView.scrollWheelDelta(event))
      return true

proc initScroller(scrollView: ScrollView, axis: LayoutAxis): Scroller =
  result = Scroller()
  initViewFields(result, initRect(0.0, 0.0, 0.0, 0.0))
  result.background = initColor(0.0, 0.0, 0.0, 0.0)
  result.hidden = true
  result.xScrollView = scrollView
  result.xAxis = axis
  discard result.withProtocol(DefaultScrollerDrawing)
  discard result.withProtocol(DefaultScrollerEvents)

proc initClipView(scrollView: ScrollView, frame: Rect): ClipView =
  result = ClipView()
  initViewFields(result, frame)
  result.background = initColor(0.0, 0.0, 0.0, 0.0)
  result.clipsToBounds = true
  result.xScrollView = scrollView
  result.xDrawsBackground = false
  discard result.withProtocol(DefaultClipViewDrawing)
  discard result.withProtocol(DefaultClipViewGeometry)

proc initScrollViewFields*(scrollView: ScrollView, frame: Rect = AutoRect) =
  initViewFields(scrollView, frame)
  scrollView.background = initColor(0.0, 0.0, 0.0, 0.0)
  scrollView.clipsToBounds = true
  scrollView.xDrawsBackground = true
  scrollView.xHasScroller[laHorizontal] = false
  scrollView.xHasScroller[laVertical] = false
  scrollView.xAutohidePolicy = sapWhenNeeded
  scrollView.xScrollerThickness = 12.0'f32
  scrollView.xLineScroll[laHorizontal] = 16.0'f32
  scrollView.xLineScroll[laVertical] = 16.0'f32
  scrollView.xPageScroll[laHorizontal] = 0.0'f32
  scrollView.xPageScroll[laVertical] = 0.0'f32
  scrollView.xBorderType = svbNoBorder
  scrollView.xScrollViewRole = srScrollView
  scrollView.xScrollerRole = srScroller
  scrollView.xScrollerInsets = insets(0.0)
  scrollView.xDynamicScrolling = true
  scrollView.xClipView = initClipView(scrollView, scrollView.bounds())
  scrollView.xScroller[laHorizontal] = initScroller(scrollView, laHorizontal)
  scrollView.xScroller[laVertical] = initScroller(scrollView, laVertical)
  scrollView.addSubview(scrollView.xClipView)
  scrollView.addSubview(scrollView.xScroller[laHorizontal])
  scrollView.addSubview(scrollView.xScroller[laVertical])
  discard scrollView.withProtocol(DefaultScrollViewLayout)
  discard scrollView.withProtocol(DefaultScrollViewDrawing)
  discard scrollView.withProtocol(DefaultScrollViewEvents)
  discard scrollView.withProtocol(DefaultScrollViewAccessibility)

proc newScrollView*(frame: Rect = AutoRect, documentView: View = nil): ScrollView =
  result = ScrollView()
  result.initScrollViewFields(frame)
  result.documentView = documentView
