import ./drawing
import ./selectors
import ./theme
import ./types
import ./viewgeometry
import ./views

export views

type
  ScrollContentView = ref object of View

  ScrollView* = ref object of View
    xContentView: ScrollContentView
    xDocumentView: View
    xContentOffset: Point
    xHasScroller: array[LayoutAxis, bool]
    xAutohidesScrollers: bool
    xScrollerThickness: float32
    xLineScroll: float32

func normalizedScrollerThickness(value: float32): float32 =
  max(value, 0.0'f32)

func normalizedLineScroll(value: float32): float32 =
  max(value, 1.0'f32)

func visibleScrollerAxes(
    boundsSize, documentSize: Size,
    hasHorizontal, hasVertical, autohides: bool,
    thickness: float32,
): set[LayoutAxis] =
  var
    visible: set[LayoutAxis] = {}
    viewport = boundsSize

  for _ in 0 ..< 3:
    let
      nextHorizontal =
        hasHorizontal and (not autohides or documentSize.width > viewport.width)
      nextVertical =
        hasVertical and (not autohides or documentSize.height > viewport.height)
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
  if scrollView.isNil or scrollView.xDocumentView.isNil:
    initSize(0.0, 0.0)
  else:
    scrollView.xDocumentView.frame().size

proc contentSize*(scrollView: ScrollView): Size =
  scrollView.documentSize()

proc visibleScrollerAxes(scrollView: ScrollView): set[LayoutAxis] =
  if scrollView.isNil:
    return {}
  visibleScrollerAxes(
    scrollView.bounds().size,
    scrollView.documentSize(),
    scrollView.xHasScroller[laHorizontal],
    scrollView.xHasScroller[laVertical],
    scrollView.xAutohidesScrollers,
    scrollView.xScrollerThickness,
  )

proc viewportSize*(scrollView: ScrollView): Size =
  if scrollView.isNil:
    return initSize(0.0, 0.0)
  let visible = scrollView.visibleScrollerAxes()
  initSize(
    max(
      scrollView.bounds().size.width -
        (if laVertical in visible: scrollView.xScrollerThickness else: 0.0'f32),
      0.0'f32,
    ),
    max(
      scrollView.bounds().size.height -
        (if laHorizontal in visible: scrollView.xScrollerThickness else: 0.0'f32),
      0.0'f32,
    ),
  )

proc viewportRect*(scrollView: ScrollView): Rect =
  if scrollView.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  initRect(initPoint(0.0, 0.0), scrollView.viewportSize())

proc maximumContentOffset*(scrollView: ScrollView): Point =
  if scrollView.isNil:
    return initPoint(0.0, 0.0)
  let
    documentSize = scrollView.documentSize()
    viewportSize = scrollView.viewportSize()
  initPoint(
    max(documentSize.width - viewportSize.width, 0.0'f32),
    max(documentSize.height - viewportSize.height, 0.0'f32),
  )

proc clampContentOffset(scrollView: ScrollView, offset: Point): Point =
  if scrollView.isNil:
    return initPoint(0.0, 0.0)
  let maximum = scrollView.maximumContentOffset()
  initPoint(
    min(max(offset.x, 0.0'f32), maximum.x), min(max(offset.y, 0.0'f32), maximum.y)
  )

proc applyContentOffset(scrollView: ScrollView, offset: Point) =
  if scrollView.isNil or scrollView.xContentView.isNil:
    return
  let
    nextOffset = scrollView.clampContentOffset(offset)
    nextBounds = initRect(nextOffset, scrollView.viewportSize())
  scrollView.xContentOffset = nextOffset
  if scrollView.xContentView.bounds() != nextBounds:
    scrollView.xContentView.bounds = nextBounds
  scrollView.setNeedsDisplay(true)

proc tile*(scrollView: ScrollView) =
  if scrollView.isNil or scrollView.xContentView.isNil:
    return
  scrollView.xContentView.frame = scrollView.viewportRect()
  scrollView.applyContentOffset(scrollView.xContentOffset)

proc contentView*(scrollView: ScrollView): View =
  if scrollView.isNil: nil else: scrollView.xContentView

proc documentView*(scrollView: ScrollView): View =
  if scrollView.isNil: nil else: scrollView.xDocumentView

proc setDocumentView*(scrollView: ScrollView, documentView: View) =
  if scrollView.isNil or scrollView.xDocumentView == documentView:
    return
  if not scrollView.xDocumentView.isNil:
    scrollView.xDocumentView.removeFromSuperview()
  scrollView.xDocumentView = documentView
  if not documentView.isNil:
    scrollView.xContentView.addSubview(documentView)
  scrollView.tile()
  scrollView.invalidateContainerMetrics()
  scrollView.setNeedsDisplay(true)

proc `documentView=`*(scrollView: ScrollView, documentView: View) =
  scrollView.setDocumentView(documentView)

proc contentOffset*(scrollView: ScrollView): Point =
  if scrollView.isNil:
    initPoint(0.0, 0.0)
  else:
    scrollView.clampContentOffset(scrollView.xContentOffset)

proc setContentOffset*(scrollView: ScrollView, offset: Point) =
  if scrollView.isNil:
    return
  scrollView.tile()
  let nextOffset = scrollView.clampContentOffset(offset)
  if scrollView.xContentOffset == nextOffset and
      scrollView.xContentView.bounds().origin == nextOffset:
    return
  scrollView.applyContentOffset(nextOffset)

proc `contentOffset=`*(scrollView: ScrollView, offset: Point) =
  scrollView.setContentOffset(offset)

proc scrollTo*(scrollView: ScrollView, offset: Point) =
  scrollView.setContentOffset(offset)

proc scrollBy*(scrollView: ScrollView, delta: Point) =
  if scrollView.isNil:
    return
  scrollView.setContentOffset(
    initPoint(
      scrollView.xContentOffset.x + delta.x, scrollView.xContentOffset.y + delta.y
    )
  )

proc scrollRectToVisible*(scrollView: ScrollView, rect: Rect): bool =
  if scrollView.isNil:
    return false
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
    scrollView.setContentOffset(nextOffset)

proc scrollWheelDelta*(scrollView: ScrollView, event: ScrollEvent): Point =
  if scrollView.isNil:
    return initPoint(0.0, 0.0)
  initPoint(
    event.deltaX * scrollView.xLineScroll, -event.deltaY * scrollView.xLineScroll
  )

proc hasHorizontalScroller*(scrollView: ScrollView): bool =
  not scrollView.isNil and scrollView.xHasScroller[laHorizontal]

proc `hasHorizontalScroller=`*(scrollView: ScrollView, value: bool) =
  if scrollView.isNil or scrollView.xHasScroller[laHorizontal] == value:
    return
  scrollView.xHasScroller[laHorizontal] = value
  scrollView.tile()
  scrollView.invalidateContainerMetrics()
  scrollView.setNeedsDisplay(true)

proc hasVerticalScroller*(scrollView: ScrollView): bool =
  not scrollView.isNil and scrollView.xHasScroller[laVertical]

proc `hasVerticalScroller=`*(scrollView: ScrollView, value: bool) =
  if scrollView.isNil or scrollView.xHasScroller[laVertical] == value:
    return
  scrollView.xHasScroller[laVertical] = value
  scrollView.tile()
  scrollView.invalidateContainerMetrics()
  scrollView.setNeedsDisplay(true)

proc autohidesScrollers*(scrollView: ScrollView): bool =
  not scrollView.isNil and scrollView.xAutohidesScrollers

proc `autohidesScrollers=`*(scrollView: ScrollView, value: bool) =
  if scrollView.isNil or scrollView.xAutohidesScrollers == value:
    return
  scrollView.xAutohidesScrollers = value
  scrollView.tile()
  scrollView.invalidateContainerMetrics()
  scrollView.setNeedsDisplay(true)

proc scrollerThickness*(scrollView: ScrollView): float32 =
  if scrollView.isNil: 0.0'f32 else: scrollView.xScrollerThickness

proc `scrollerThickness=`*(scrollView: ScrollView, value: float32) =
  if scrollView.isNil:
    return
  let nextValue = value.normalizedScrollerThickness()
  if scrollView.xScrollerThickness == nextValue:
    return
  scrollView.xScrollerThickness = nextValue
  scrollView.tile()
  scrollView.invalidateContainerMetrics()
  scrollView.setNeedsDisplay(true)

proc lineScroll*(scrollView: ScrollView): float32 =
  if scrollView.isNil: 0.0'f32 else: scrollView.xLineScroll

proc `lineScroll=`*(scrollView: ScrollView, value: float32) =
  if scrollView.isNil:
    return
  scrollView.xLineScroll = value.normalizedLineScroll()

proc showsHorizontalScroller*(scrollView: ScrollView): bool =
  not scrollView.isNil and laHorizontal in scrollView.visibleScrollerAxes()

proc showsVerticalScroller*(scrollView: ScrollView): bool =
  not scrollView.isNil and laVertical in scrollView.visibleScrollerAxes()

proc horizontalScrollerRect*(scrollView: ScrollView): Rect =
  if scrollView.isNil or not scrollView.showsHorizontalScroller():
    return initRect(0.0, 0.0, 0.0, 0.0)
  let viewport = scrollView.viewportRect()
  initRect(
    0.0, viewport.size.height, viewport.size.width, scrollView.xScrollerThickness
  )

proc verticalScrollerRect*(scrollView: ScrollView): Rect =
  if scrollView.isNil or not scrollView.showsVerticalScroller():
    return initRect(0.0, 0.0, 0.0, 0.0)
  let viewport = scrollView.viewportRect()
  initRect(
    viewport.size.width, 0.0, scrollView.xScrollerThickness, viewport.size.height
  )

func scrollerKnobLength(viewport, document: float32): float32 =
  if viewport <= 0.0'f32 or document <= viewport:
    return 0.0'f32
  max(viewport * viewport / document, 12.0'f32)

func scrollerKnobOffset(viewport, document, offset: float32): float32 =
  let knob = scrollerKnobLength(viewport, document)
  if knob <= 0.0'f32 or document <= viewport:
    return 0.0'f32
  offset / (document - viewport) * max(viewport - knob, 0.0'f32)

proc horizontalScrollerKnobRect*(scrollView: ScrollView): Rect =
  let track = scrollView.horizontalScrollerRect()
  if track.isEmpty:
    return track
  let
    viewport = scrollView.viewportSize().width
    document = scrollView.documentSize().width
    length = scrollerKnobLength(viewport, document)
    x = scrollerKnobOffset(viewport, document, scrollView.contentOffset().x)
  initRect(track.origin.x + x, track.origin.y, length, track.size.height)

proc verticalScrollerKnobRect*(scrollView: ScrollView): Rect =
  let track = scrollView.verticalScrollerRect()
  if track.isEmpty:
    return track
  let
    viewport = scrollView.viewportSize().height
    document = scrollView.documentSize().height
    length = scrollerKnobLength(viewport, document)
    y = scrollerKnobOffset(viewport, document, scrollView.contentOffset().y)
  initRect(track.origin.x, track.origin.y + y, track.size.width, length)

proc drawScroller(context: DrawContext, track, knob: Rect) =
  if track.isEmpty:
    return
  discard context.addWindowRectangle(
    context.localRectToWindow(track),
    fill(initColor(0.88, 0.90, 0.94, 0.70)),
    initColor(0.67, 0.71, 0.78, 0.80),
    1.0'f32,
    3.0'f32,
  )
  if not knob.isEmpty:
    discard context.addWindowRectangle(
      context.localRectToWindow(knob.inset(initEdgeInsets(2.0))),
      fill(initColor(0.36, 0.42, 0.50, 0.65)),
      initColor(0.24, 0.29, 0.36, 0.50),
      1.0'f32,
      3.0'f32,
    )

proc drawScrollers(scrollView: ScrollView, context: DrawContext) =
  if scrollView.isNil:
    return
  context.drawScroller(
    scrollView.horizontalScrollerRect(), scrollView.horizontalScrollerKnobRect()
  )
  context.drawScroller(
    scrollView.verticalScrollerRect(), scrollView.verticalScrollerKnobRect()
  )

protocol DefaultScrollViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(scrollView: ScrollView): IntrinsicSize =
    NoIntrinsicContentSize

  method layoutSubviews(scrollView: ScrollView) =
    scrollView.tile()

protocol DefaultScrollViewDrawing of ViewDrawingProtocol:
  method draw(scrollView: ScrollView, context: DrawContext) =
    scrollView.drawScrollers(context)

protocol DefaultScrollViewEvents of ResponderEventProtocol:
  method scrollWheel(scrollView: ScrollView, event: ScrollEvent) =
    scrollView.scrollBy(scrollView.scrollWheelDelta(event))

proc initScrollContentView(frame: Rect): ScrollContentView =
  result = ScrollContentView()
  initViewFields(result, frame)
  result.background = initColor(0.0, 0.0, 0.0, 0.0)
  result.clipsToBounds = true

proc initScrollViewFields*(scrollView: ScrollView, frame: Rect = AutoRect) =
  initViewFields(scrollView, frame)
  scrollView.background = initColor(0.98, 0.985, 0.995, 1.0)
  scrollView.clipsToBounds = true
  scrollView.xHasScroller[laHorizontal] = false
  scrollView.xHasScroller[laVertical] = false
  scrollView.xAutohidesScrollers = true
  scrollView.xScrollerThickness = 12.0'f32
  scrollView.xLineScroll = 16.0'f32
  scrollView.xContentView = initScrollContentView(scrollView.viewportRect())
  scrollView.addSubview(scrollView.xContentView)
  discard scrollView.withProtocol(DefaultScrollViewLayout)
  discard scrollView.withProtocol(DefaultScrollViewDrawing)
  discard scrollView.withProtocol(DefaultScrollViewEvents)

proc newScrollView*(frame: Rect = AutoRect, documentView: View = nil): ScrollView =
  result = ScrollView()
  result.initScrollViewFields(frame)
  result.setDocumentView(documentView)
