import std/unittest

import figdraw/debugtools
import figdraw/fignodes

import merenda/nimkit
import merenda/nimkit/foundation/types as nimkitTypes

type ScrollResizeFixture = object
  root: View
  title: View
  status: View
  scrollView: ScrollView
  controls: View

type NestedScrollFixture = object
  window: Window
  root: View
  parent: ScrollView
  document: View

type OverlayDrawView = ref object of View

const GeometryTolerance = 0.01'f32
const OverlayDrawLevel = 75.ZLevel

protocol OverlayDrawing of ViewDrawingProtocol:
  method drawLevel(view: OverlayDrawView): ZLevel =
    OverlayDrawLevel

proc newOverlayDrawView(frame: nimkitTypes.Rect): OverlayDrawView =
  result = OverlayDrawView()
  initViewFields(result, frame)
  discard result.withProtocol(OverlayDrawing)

func nearlyEqual(a, b: float32): bool =
  abs(a - b) <= GeometryTolerance

func insideAxis(track, bounds: nimkitTypes.Rect, axis: LayoutAxis): bool =
  track.axisOrigin(axis) >= bounds.axisOrigin(axis) - GeometryTolerance and
    track.axisMax(axis) <= bounds.axisMax(axis) + GeometryTolerance

proc checkRectNearlyEqual(actual, expected: nimkitTypes.Rect) =
  check actual.origin.x.nearlyEqual(expected.origin.x)
  check actual.origin.y.nearlyEqual(expected.origin.y)
  check actual.size.width.nearlyEqual(expected.size.width)
  check actual.size.height.nearlyEqual(expected.size.height)

proc hasAncestor(list: RenderList, nodeIndex, ancestorIndex: int): bool =
  var current = list.nodes[nodeIndex].parent.int
  while current >= 0:
    if current == ancestorIndex:
      return true
    current = list.nodes[current].parent.int

proc renderedRect(node: Fig): nimkitTypes.Rect =
  initRect(
    node.screenBox.x.float32, node.screenBox.y.float32, node.screenBox.w.float32,
    node.screenBox.h.float32,
  )

proc rectsClose(left, right: nimkitTypes.Rect): bool =
  left.origin.x.nearlyEqual(right.origin.x) and left.origin.y.nearlyEqual(
    right.origin.y
  ) and left.size.width.nearlyEqual(right.size.width) and
    left.size.height.nearlyEqual(right.size.height)

proc childIndexOf(list: RenderList, parentIndex, childIndex: int): int =
  if parentIndex < 0 or childIndex < 0:
    return -1
  result = -1
  var order = 0
  for idx in childIndex(list.nodes, parentIndex.FigIdx):
    if idx.int == childIndex:
      return order
    inc order

proc findClippedNode(list: RenderList, rect: nimkitTypes.Rect): int =
  result = -1
  for idx, node in list.nodes:
    if node.kind == nkRectangle and NfClipContent in node.flags and
        node.renderedRect().rectsClose(rect):
      return idx

proc findChildRectNode(
    list: RenderList, parentIndex: int, rect: nimkitTypes.Rect
): int =
  if parentIndex < 0:
    return -1
  result = -1
  for idx, node in list.nodes:
    if node.parent.int == parentIndex and node.kind == nkRectangle and
        node.renderedRect().rectsClose(rect):
      return idx

proc findRectNode(list: RenderList, rect: nimkitTypes.Rect, fillValue: Fill): int =
  result = -1
  for idx, node in list.nodes:
    if node.kind == nkRectangle and node.fill == fillValue and
        node.renderedRect().rectsClose(rect):
      return idx

proc checkScrollerRectInside(scrollView: ScrollView, rect: nimkitTypes.Rect) =
  check not rect.isEmpty
  check rect.insideAxis(scrollView.bounds(), laHorizontal)
  check rect.insideAxis(scrollView.bounds(), laVertical)

proc scrollViewScrollerKnobRect(
    scrollView: ScrollView, axis: LayoutAxis
): nimkitTypes.Rect =
  let
    track =
      case axis
      of laHorizontal:
        scrollView.horizontalScrollerRect()
      of laVertical:
        scrollView.verticalScrollerRect()
    viewport = scrollView.viewportSize()
    document = scrollView.documentSize()
    offset = scrollView.contentOffset()
  if track.isEmpty:
    return track
  case axis
  of laHorizontal:
    scrollerKnobRect(
      track, axis, initScrollViewport(offset.x, viewport.width, document.width)
    )
  of laVertical:
    scrollerKnobRect(
      track, axis, initScrollViewport(offset.y, viewport.height, document.height)
    )

proc listViewScrollerKnobRect(listView: ListView): nimkitTypes.Rect =
  let scrollView = listView.scrollView()
  if scrollView.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  scrollerKnobRect(
    scrollView.verticalScrollerRect(),
    laVertical,
    initScrollViewport(
      scrollView.contentOffset().y,
      scrollView.viewportSize().height,
      scrollView.documentSize().height,
    ),
  )

proc checkScrollViewResizeInvariants(scrollView: ScrollView) =
  let
    viewport = scrollView.viewportRect()
    contentView = scrollView.contentView()
    bounds = scrollView.bounds()
    offset = scrollView.contentOffset()
    maximumOffset = scrollView.maximumContentOffset()

  checkRectNearlyEqual(contentView.frame(), viewport)
  checkRectNearlyEqual(contentView.bounds(), initRect(offset, viewport.size))
  check offset.x >= 0.0'f32
  check offset.y >= 0.0'f32
  check offset.x <= maximumOffset.x + GeometryTolerance
  check offset.y <= maximumOffset.y + GeometryTolerance
  check viewport.size.width >= 0.0'f32
  check viewport.size.height >= 0.0'f32
  check viewport.insideAxis(bounds, laHorizontal)
  check viewport.insideAxis(bounds, laVertical)

  let horizontalScroller = scrollView.horizontalScrollerRect()
  if not horizontalScroller.isEmpty:
    checkScrollerRectInside(scrollView, horizontalScroller)
    checkScrollerRectInside(
      scrollView, scrollView.scrollViewScrollerKnobRect(laHorizontal)
    )
  else:
    check horizontalScroller.isEmpty
    check scrollView.scrollViewScrollerKnobRect(laHorizontal).isEmpty

  let verticalScroller = scrollView.verticalScrollerRect()
  if not verticalScroller.isEmpty:
    checkScrollerRectInside(scrollView, verticalScroller)
    checkScrollerRectInside(
      scrollView, scrollView.scrollViewScrollerKnobRect(laVertical)
    )
  else:
    check verticalScroller.isEmpty
    check scrollView.scrollViewScrollerKnobRect(laVertical).isEmpty

proc newScrollResizeFixture(frame: nimkitTypes.Rect): ScrollResizeFixture =
  result.root = newView(frame = frame)
  result.title = newTitleLabel("Scroll View")
  result.status = newStatusLabel("")
  result.scrollView =
    newScrollView(documentView = newView(frame = initRect(0, 0, 620, 620)))
  result.controls = newStackView(laHorizontal)

  let
    guide = result.root.contentLayoutGuide(initEdgeInsets(22.0, 24.0, 22.0, 24.0))
    topButton = newButton("Top")
    middleButton = newButton("Middle")
    bottomButton = newButton("Bottom")

  result.scrollView.hasHorizontalScroller = true
  result.scrollView.hasVerticalScroller = true
  result.scrollView.autohidesScrollers = true

  StackView(result.controls).spacing = 8.0
  StackView(result.controls).alignment = svaCenter
  StackView(result.controls).distribution = svdFill
  StackView(result.controls).addArrangedSubview(topButton, middleButton, bottomButton)
  result.root.addSubviews(
    autoNames(result.title, result.status, result.scrollView, result.controls)
  )

  result.title.pinEdges(toGuide = guide, edges = {leLeft, leTop, leRight})
  activate(
    result.status[atTop].equalTo(result.title[atBottom], constant = 8.0),
    result.status[atLeft].equalTo(result.title[atLeft]),
    result.status[atRight].equalTo(result.title[atRight]),
    result.scrollView[atTop].equalTo(result.status[atBottom], constant = 12.0),
    result.scrollView[atLeft].equalTo(result.title[atLeft]),
    result.scrollView[atRight].equalTo(result.title[atRight]),
    result.controls[atTop].equalTo(result.scrollView[atBottom], constant = 12.0),
    result.controls[atLeft].equalTo(result.title[atLeft]),
    result.controls[atRight].equalTo(result.title[atRight]),
    result.controls[atBottom].equalTo(guide[atBottom]),
  )

proc checkHeaderVisible(fixture: ScrollResizeFixture) =
  let
    rootBounds = fixture.root.bounds()
    titleFrame = fixture.title.frame()
    statusFrame = fixture.status.frame()
    scrollFrame = fixture.scrollView.frame()
    controlsFrame = fixture.controls.frame()

  check titleFrame.origin.x >= 0.0'f32
  check titleFrame.origin.y >= 0.0'f32
  check titleFrame.maxX <= rootBounds.size.width + GeometryTolerance
  check titleFrame.maxY <= rootBounds.size.height + GeometryTolerance
  check statusFrame.origin.y >= titleFrame.maxY - GeometryTolerance
  check scrollFrame.origin.y >= statusFrame.maxY - GeometryTolerance
  check controlsFrame.origin.y >= scrollFrame.maxY - GeometryTolerance
  check controlsFrame.maxY <= rootBounds.size.height + GeometryTolerance
  check scrollFrame.size.width > 0.0'f32
  check scrollFrame.size.height > 0.0'f32

proc checkDemoScrollerVisibility(fixture: ScrollResizeFixture) =
  let
    rootSize = fixture.root.bounds().size
    documentSize = fixture.scrollView.documentSize()
    maxViewportWidth = max(rootSize.width - 48.0'f32, 0.0'f32)
    maxViewportHeight = max(rootSize.height - 44.0'f32, 0.0'f32)

  if documentSize.width > maxViewportWidth + GeometryTolerance:
    check not fixture.scrollView.horizontalScrollerRect().isEmpty
  if documentSize.height > maxViewportHeight + GeometryTolerance:
    check not fixture.scrollView.verticalScrollerRect().isEmpty

proc newNestedScrollFixture(child: View): NestedScrollFixture =
  result.window = newWindow("Nested scroll", frame = initRect(0, 0, 260, 200))
  result.root = newView(frame = initRect(0, 0, 260, 200))
  result.document = newView(frame = initRect(0, 0, 420, 420))
  result.parent =
    newScrollView(frame = initRect(10, 10, 160, 120), documentView = result.document)

  result.parent.hasVerticalScroller = true
  result.parent.autohidesScrollers = true
  result.parent.lineScroll = 10.0
  result.document.addSubview(child)
  result.root.addSubview(result.parent)
  result.window.setContentView(result.root)
  result.root.layoutSubtreeIfNeeded()

proc windowPointForDocumentChild(fixture: NestedScrollFixture, child: View): Point =
  initPoint(
    fixture.parent.frame().origin.x + child.frame().origin.x + 10.0'f32,
    fixture.parent.frame().origin.y + child.frame().origin.y + 10.0'f32,
  )

suite "nimkit scroll views":
  test "scroll view owns a clipped content view and document view":
    let
      document = newView(frame = initRect(0, 0, 320, 220))
      scrollView =
        newScrollView(frame = initRect(10, 12, 120, 80), documentView = document)

    check scrollView.contentView() != nil
    check View(scrollView.clipView()) == scrollView.contentView()
    check scrollView.contentView().clipsToBounds
    check scrollView.documentView() == document
    check document.superview == scrollView.contentView()
    check scrollView.horizontalScroller() != nil
    check scrollView.horizontalScroller().superview == scrollView
    check scrollView.horizontalScroller().hidden
    check scrollView.verticalScroller() != nil
    check scrollView.verticalScroller().superview == scrollView
    check scrollView.verticalScroller().hidden
    check scrollView.viewportSize() == initSize(120, 80)
    check scrollView.contentOffset() == initPoint(0, 0)

  test "axis scroller API mirrors horizontal and vertical wrappers":
    let scrollView = newScrollView(frame = initRect(0, 0, 120, 80))

    check not scrollView.hasScroller(laHorizontal)
    check not scrollView.hasScroller(laVertical)

    scrollView.setHasScroller(laHorizontal, true)
    scrollView.setHasScroller(laVertical, true)

    check scrollView.hasHorizontalScroller
    check scrollView.hasVerticalScroller
    check scrollView.hasScroller(laHorizontal)
    check scrollView.hasScroller(laVertical)

    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false

    check not scrollView.hasScroller(laHorizontal)
    check not scrollView.hasScroller(laVertical)

  test "content offset clamps to document and viewport bounds":
    let
      document = newView(frame = initRect(0, 0, 300, 210))
      scrollView =
        newScrollView(frame = initRect(0, 0, 100, 70), documentView = document)

    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = false
    scrollView.scrollerThickness = 10.0

    check scrollView.viewportSize() == initSize(90, 60)
    check scrollView.maximumContentOffset() == initPoint(210, 150)

    scrollView.contentOffset = initPoint(250, 200)
    check scrollView.contentOffset() == initPoint(210, 150)
    check scrollView.clipView().bounds.origin == initPoint(210, 150)
    check scrollView.contentView().bounds.origin == initPoint(210, 150)

    scrollView.contentOffset = initPoint(-10, -20)
    check scrollView.contentOffset() == initPoint(0, 0)
    scrollView.clipView().bounds =
      initRect(initPoint(50, 20), scrollView.viewportSize())
    check scrollView.contentOffset() == initPoint(50, 20)

  test "fraction scrolling is stable from top and bottom":
    let
      document = newView(frame = initRect(0, 0, 300, 210))
      scrollView =
        newScrollView(frame = initRect(0, 0, 100, 70), documentView = document)

    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = false
    scrollView.scrollerThickness = 10.0

    let expected = initPoint(105.0, 75.0)
    check scrollView.contentOffsetForFraction(initPoint(0.5, 0.5)) == expected
    check scrollView.contentOffsetForFraction(initPoint(-1.0, 2.0)) ==
      initPoint(0.0, 150.0)

    scrollView.scrollTo(initPoint(20.0, 40.0))
    check scrollView.contentOffsetForFraction(x = 0.5) == initPoint(105.0, 40.0)
    check scrollView.contentOffsetForFraction(y = 0.5) == initPoint(20.0, 75.0)

    scrollView.scrollTo(initPoint(0, 0))
    scrollView.scrollToFraction(0.5, 0.5)
    check scrollView.contentOffset() == expected

    scrollView.scrollTo(scrollView.maximumContentOffset())
    scrollView.scrollToFraction(initPoint(0.5, 0.5))
    check scrollView.contentOffset() == expected

    scrollView.scrollTo(initPoint(20.0, 40.0))
    scrollView.scrollToFraction(x = 0.5)
    check scrollView.contentOffset() == initPoint(105.0, 40.0)
    scrollView.scrollToFraction(y = 0.5)
    check scrollView.contentOffset() == expected

  test "scroll wheel and scroll rect update content offset":
    let
      window = newWindow("ScrollView", frame = initRect(0, 0, 220, 160))
      root = newView(frame = initRect(0, 0, 220, 160))
      document = newView(frame = initRect(0, 0, 300, 260))
      scrollView =
        newScrollView(frame = initRect(10, 10, 100, 80), documentView = document)

    scrollView.lineScroll = 10.0
    root.addSubview(scrollView)
    window.setContentView(root)

    check window.scrollWheelAt(initPoint(20, 20), deltaY = -2.0)
    check scrollView.contentOffset() == initPoint(0, 20)

    check scrollView.scrollRectToVisible(initRect(160, 150, 40, 40))
    check scrollView.contentOffset().x > 0.0
    check scrollView.contentOffset().y > 20.0

    let visible = initRect(scrollView.contentOffset(), scrollView.viewportSize())
    check visible.contains(initPoint(160, 150))
    check visible.contains(initPoint(199.99, 189.99))

  test "scroller gutter clicks page content along axis":
    let
      window = newWindow("Scroller gutter", frame = initRect(0, 0, 260, 220))
      root = newView(frame = initRect(0, 0, 260, 220))
      verticalDocument = newView(frame = initRect(0, 0, 80, 260))
      vertical = newScrollView(
        frame = initRect(10, 10, 100, 80), documentView = verticalDocument
      )
      horizontalDocument = newView(frame = initRect(0, 0, 320, 70))
      horizontal = newScrollView(
        frame = initRect(10, 120, 100, 80), documentView = horizontalDocument
      )

    vertical.hasVerticalScroller = true
    vertical.autohidesScrollers = false
    vertical.scrollerThickness = 10.0
    horizontal.hasHorizontalScroller = true
    horizontal.autohidesScrollers = false
    horizontal.scrollerThickness = 10.0
    root.addSubviews(autoNames(vertical, horizontal))
    window.setContentView(root)

    let
      verticalTrack = vertical.verticalScrollerRect()
      verticalKnob = vertical.scrollViewScrollerKnobRect(laVertical)
      verticalDownPoint = vertical.frame().origin.offset(
          verticalTrack.origin.x + verticalTrack.size.width / 2.0'f32,
          verticalKnob.maxY + 8.0'f32,
        )

    check window.mouseDownAt(verticalDownPoint)
    check window.mouseUpAt(verticalDownPoint)
    check vertical.contentOffset().y.nearlyEqual(vertical.viewportSize().height)

    let verticalUpPoint = vertical.frame().origin.offset(
        verticalTrack.origin.x + verticalTrack.size.width / 2.0'f32,
        verticalKnob.origin.y + 2.0'f32,
      )

    check window.mouseDownAt(verticalUpPoint)
    check window.mouseUpAt(verticalUpPoint)
    check vertical.contentOffset().y.nearlyEqual(0.0'f32)

    let
      horizontalTrack = horizontal.horizontalScrollerRect()
      horizontalKnob = horizontal.scrollViewScrollerKnobRect(laHorizontal)
      horizontalRightPoint = horizontal.frame().origin.offset(
          horizontalKnob.maxX + 8.0'f32,
          horizontalTrack.origin.y + horizontalTrack.size.height / 2.0'f32,
        )

    check window.mouseDownAt(horizontalRightPoint)
    check window.mouseUpAt(horizontalRightPoint)
    check horizontal.contentOffset().x.nearlyEqual(horizontal.viewportSize().width)

  test "scroller knob drag maps track movement to content offset":
    let
      window = newWindow("Scroller drag", frame = initRect(0, 0, 220, 160))
      root = newView(frame = initRect(0, 0, 220, 160))
      document = newView(frame = initRect(0, 0, 80, 260))
      scrollView =
        newScrollView(frame = initRect(10, 10, 100, 80), documentView = document)

    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = false
    scrollView.scrollerThickness = 10.0
    root.addSubview(scrollView)
    window.setContentView(root)

    let
      track = scrollView.verticalScrollerRect()
      knob = scrollView.scrollViewScrollerKnobRect(laVertical)
      grip = 5.0'f32
      dragY = 45.0'f32
      startPoint = scrollView.frame().origin.offset(
          knob.origin.x + knob.size.width / 2.0'f32, knob.origin.y + grip
        )
      dragPoint = scrollView.frame().origin.offset(
          knob.origin.x + knob.size.width / 2.0'f32, dragY
        )
      travel = track.size.height - knob.size.height
      expectedOffset = (dragY - grip) / travel * scrollView.maximumContentOffset().y

    check window.mouseDownAt(startPoint)
    check window.mouseDraggedAt(dragPoint)
    check scrollView.contentOffset().y.nearlyEqual(expectedOffset)

    let endPoint = scrollView.frame().origin.offset(
        knob.origin.x + knob.size.width / 2.0'f32, track.maxY + 120.0'f32
      )
    check window.mouseDraggedAt(endPoint)
    check scrollView.contentOffset().y.nearlyEqual(scrollView.maximumContentOffset().y)
    check window.mouseUpAt(endPoint)

  test "wheel over scrollable nested scroll view stays with child":
    let
      childDocument = newView(frame = initRect(0, 0, 100, 260))
      child =
        newScrollView(frame = initRect(20, 20, 100, 80), documentView = childDocument)
      fixture = newNestedScrollFixture(child)

    child.hasVerticalScroller = true
    child.autohidesScrollers = true
    child.lineScroll = 10.0

    check child.maximumContentOffset().y > 0.0'f32
    check fixture.parent.contentOffset() == initPoint(0, 0)
    check fixture.window.scrollWheelAt(
      fixture.windowPointForDocumentChild(child), deltaY = -2.0
    )
    check child.contentOffset().y > 0.0'f32
    check fixture.parent.contentOffset() == initPoint(0, 0)

  test "wheel over non-scrollable nested scroll view bubbles to parent":
    let
      childDocument = newView(frame = initRect(0, 0, 60, 40))
      child =
        newScrollView(frame = initRect(20, 20, 100, 80), documentView = childDocument)
      fixture = newNestedScrollFixture(child)

    child.hasVerticalScroller = true
    child.autohidesScrollers = true
    child.lineScroll = 10.0

    check child.maximumContentOffset() == initPoint(0, 0)
    check fixture.parent.contentOffset() == initPoint(0, 0)
    check fixture.window.scrollWheelAt(
      fixture.windowPointForDocumentChild(child), deltaY = -2.0
    )
    check child.contentOffset() == initPoint(0, 0)
    check fixture.parent.contentOffset().y > 0.0'f32

  test "wheel past nested scroll view end bubbles to parent":
    let
      childDocument = newView(frame = initRect(0, 0, 100, 260))
      child =
        newScrollView(frame = initRect(20, 20, 100, 80), documentView = childDocument)
      fixture = newNestedScrollFixture(child)

    child.hasVerticalScroller = true
    child.autohidesScrollers = true
    child.lineScroll = 10.0
    child.scrollTo(child.maximumContentOffset())
    let childOffset = child.contentOffset()

    check childOffset.y > 0.0'f32
    check fixture.parent.contentOffset() == initPoint(0, 0)
    check fixture.window.scrollWheelAt(
      fixture.windowPointForDocumentChild(child), deltaY = -2.0
    )
    check child.contentOffset() == childOffset
    check fixture.parent.contentOffset().y > 0.0'f32

  test "wheel over scrollable list view stays with list scroll view":
    let
      listView = newListView(
        ["One", "Two", "Three", "Four", "Five", "Six"],
        frame = initRect(20, 20, 120, 68),
      )
      fixture = newNestedScrollFixture(listView)

    listView.rowHeight = 20.0

    check listView.scrollView().maximumContentOffset().y > 0.0'f32
    check fixture.parent.contentOffset() == initPoint(0, 0)
    check fixture.window.scrollWheelAt(
      fixture.windowPointForDocumentChild(listView), deltaY = -2.0
    )
    check listView.scrollView().contentOffset().y > 0.0'f32
    check fixture.parent.contentOffset() == initPoint(0, 0)

  test "wheel over non-scrollable list view bubbles to parent scroll view":
    let
      listView = newListView(["One", "Two"], frame = initRect(20, 20, 120, 68))
      fixture = newNestedScrollFixture(listView)

    listView.rowHeight = 20.0

    check listView.visibleItemCount() == listView.len()
    check listView.listViewScrollerKnobRect().isEmpty
    check fixture.parent.contentOffset() == initPoint(0, 0)
    check fixture.window.scrollWheelAt(
      fixture.windowPointForDocumentChild(listView), deltaY = -2.0
    )
    check listView.firstVisibleIndex() == 0
    check fixture.parent.contentOffset().y > 0.0'f32

  test "autohide scroller policy follows document size":
    let
      document = newView(frame = initRect(0, 0, 80, 60))
      scrollView =
        newScrollView(frame = initRect(0, 0, 100, 80), documentView = document)

    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true

    check scrollView.horizontalScrollerRect().isEmpty
    check scrollView.verticalScrollerRect().isEmpty

    document.frame = initRect(0, 0, 160, 120)
    scrollView.tile()

    check not scrollView.horizontalScrollerRect().isEmpty
    check not scrollView.verticalScrollerRect().isEmpty

  test "direct frame resize retiles viewport and scroller geometry":
    let
      document = newView(frame = initRect(0, 0, 620, 620))
      scrollView =
        newScrollView(frame = initRect(0, 0, 240, 160), documentView = document)

    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true

    scrollView.layoutSubtreeIfNeeded()
    scrollView.scrollTo(scrollView.maximumContentOffset())
    checkScrollViewResizeInvariants(scrollView)
    check not scrollView.horizontalScrollerRect().isEmpty
    check not scrollView.verticalScrollerRect().isEmpty

    scrollView.frame = initRect(0, 0, 760, 680)
    scrollView.layoutSubtreeIfNeeded()
    checkScrollViewResizeInvariants(scrollView)
    check scrollView.contentOffset() == initPoint(0, 0)
    check scrollView.horizontalScrollerRect().isEmpty
    check scrollView.verticalScrollerRect().isEmpty

    scrollView.frame = initRect(0, 0, 260, 180)
    scrollView.layoutSubtreeIfNeeded()
    checkScrollViewResizeInvariants(scrollView)
    check not scrollView.horizontalScrollerRect().isEmpty
    check not scrollView.verticalScrollerRect().isEmpty

  test "scroll view resizes with constraint layout":
    let
      root = newView(frame = initRect(0, 0, 260, 180))
      guide = root.contentLayoutGuide(initEdgeInsets(12.0))
      document = newView(frame = initRect(0, 0, 420, 360))
      scrollView = newScrollView(documentView = document)
      footer = newButton("Done")

    root.addSubviews(autoNames(scrollView, footer))
    activate(
      scrollView[atTop].equalTo(guide[atTop]),
      scrollView[atLeft].equalTo(guide[atLeft]),
      scrollView[atRight].equalTo(guide[atRight]),
      footer[atTop].equalTo(scrollView[atBottom], constant = 8.0),
      footer[atLeft].equalTo(guide[atLeft]),
      footer[atRight].equalTo(guide[atRight]),
      footer[atBottom].equalTo(guide[atBottom]),
    )

    root.layoutSubtreeIfNeeded()
    let firstFrame = scrollView.frame()

    root.frame = initRect(0, 0, 340, 260)
    root.layoutSubtreeIfNeeded()

    check scrollView.frame().size.width > firstFrame.size.width
    check scrollView.frame().size.height > firstFrame.size.height

  test "scroll view viewport remains coherent across repeated grow shrink layout":
    let fixture = newScrollResizeFixture(initRect(0, 0, 520, 380))

    fixture.root.layoutSubtreeIfNeeded()
    fixture.scrollView.scrollTo(fixture.scrollView.maximumContentOffset())
    checkScrollViewResizeInvariants(fixture.scrollView)
    checkDemoScrollerVisibility(fixture)
    check fixture.scrollView.contentOffset().x > 0.0'f32
    check fixture.scrollView.contentOffset().y > 0.0'f32

    for size in [
      initSize(760, 620),
      initSize(360, 260),
      initSize(680, 560),
      initSize(300, 220),
      initSize(520, 380),
    ]:
      fixture.root.frame = initRect(0, 0, size.width, size.height)
      fixture.root.layoutSubtreeIfNeeded()
      checkHeaderVisible(fixture)
      checkScrollViewResizeInvariants(fixture.scrollView)
      checkDemoScrollerVisibility(fixture)

  test "large scroll document does not push header out of constrained viewport":
    let fixture = newScrollResizeFixture(initRect(0, 0, 520, 380))

    fixture.root.layoutSubtreeIfNeeded()
    checkHeaderVisible(fixture)
    checkScrollViewResizeInvariants(fixture.scrollView)
    checkDemoScrollerVisibility(fixture)

    fixture.root.frame = initRect(0, 0, 360, 260)
    fixture.root.layoutSubtreeIfNeeded()
    checkHeaderVisible(fixture)
    checkScrollViewResizeInvariants(fixture.scrollView)
    checkDemoScrollerVisibility(fixture)

  test "buildRenders clips scroll content and offsets document rendering":
    let
      root = newView(frame = initRect(0, 0, 180, 140))
      document = newView(frame = initRect(0, 0, 240, 180))
      child = newView(frame = initRect(60, 50, 30, 20))
      scrollView =
        newScrollView(frame = initRect(20, 30, 100, 70), documentView = document)

    child.background = initColor(0.2, 0.4, 0.7, 1.0)
    document.addSubview(child)
    root.addSubview(scrollView)
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true

    scrollView.contentOffset = initPoint(40, 30)
    let renders = buildRenders(root)
    let nodes = renders[DefaultDrawLevel]

    var
      scrollViewNodeIndex = -1
      clipViewNodeIndex = -1
      scrollTransformIndex = -1
      childNodeFound = false
      childNodeIndex = -1
      verticalScrollerIndex = -1
      horizontalScrollerIndex = -1

    for idx, node in nodes.nodes:
      if node.kind == nkRectangle and NfClipContent in node.flags and
          node.screenBox.x == 20.0 and node.screenBox.y == 30.0 and
          node.screenBox.w == 100.0 and node.screenBox.h == 70.0:
        scrollViewNodeIndex = idx
      if node.kind == nkRectangle and NfClipContent in node.flags and
          node.screenBox.x == 20.0 and node.screenBox.y == 30.0 and
          node.screenBox.w == 88.0 and node.screenBox.h == 58.0:
        clipViewNodeIndex = idx
      if node.kind == nkTransform and node.transform.translation.x == -40.0 and
          node.transform.translation.y == -30.0:
        scrollTransformIndex = idx
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == initColor(0.2, 0.4, 0.7, 1.0).rgba:
        childNodeFound = true
        childNodeIndex = idx
        check node.screenBox.x == 80.0
        check node.screenBox.y == 80.0
        check node.screenBox.w == 30.0
        check node.screenBox.h == 20.0
      if verticalScrollerIndex < 0 and node.kind == nkRectangle and
          node.screenBox.x == 108.0 and node.screenBox.y == 30.0 and
          node.screenBox.w == 12.0 and node.screenBox.h == 58.0:
        verticalScrollerIndex = idx
      if horizontalScrollerIndex < 0 and node.kind == nkRectangle and
          node.screenBox.x == 20.0 and node.screenBox.y == 88.0 and
          node.screenBox.w == 88.0 and node.screenBox.h == 12.0:
        horizontalScrollerIndex = idx

    check scrollViewNodeIndex >= 0
    check clipViewNodeIndex >= 0
    check scrollTransformIndex >= 0
    check childNodeFound
    check verticalScrollerIndex >= 0
    check horizontalScrollerIndex >= 0
    check nodes.nodes[clipViewNodeIndex].parent.int == scrollViewNodeIndex
    check nodes.nodes[scrollTransformIndex].parent.int == clipViewNodeIndex
    check nodes.nodes[verticalScrollerIndex].parent.int == scrollViewNodeIndex
    check nodes.nodes[horizontalScrollerIndex].parent.int == scrollViewNodeIndex
    check nodes.hasAncestor(childNodeIndex, scrollTransformIndex)
    check nodes.hasAncestor(childNodeIndex, clipViewNodeIndex)

    let childVisibility = renders.figVisibility(DefaultDrawLevel, childNodeIndex.FigIdx)
    check childVisibility.visible
    check childVisibility.bounds.x == 40.0
    check childVisibility.bounds.y == 50.0
    check childVisibility.bounds.w == 30.0
    check childVisibility.bounds.h == 20.0

  test "scrolled document controls draw chrome in render space":
    let
      root = newView(frame = initRect(0, 0, 220, 160))
      document = newView(frame = initRect(0, 0, 260, 220))
      heading = newHeadingLabel("Heading", frame = initRect(60, 50, 100, 20))
      button = newButton("Press", frame = initRect(60, 90, 100, 26))
      scrollView =
        newScrollView(frame = initRect(20, 30, 120, 80), documentView = document)

    document.addSubviews(autoNames(heading, button))
    root.addSubview(scrollView)
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.contentOffset = initPoint(40, 30)

    let
      headingStyle = heading.effectiveAppearance().resolveTextFieldStyle(
          initControlStyleContext(
            srTextField, id = heading.styleId, classes = heading.styleClasses
          ),
          heading.textColor(),
        )
      buttonStyle = button.effectiveAppearance().resolveButtonStyle(
          initControlStyleContext(
            srButton, id = button.styleId, classes = button.styleClasses
          )
        )
      renders = buildRenders(root)
      nodes = renders[DefaultDrawLevel]
      scrollWindowOffset = scrollView.contentOffset()
      expectedHeadingRenderRect = initRect(80, 80, 100, 20)
      expectedButtonRenderRect = initRect(80, 120, 100, 26)
      headingScrolledWindowRect = heading.rectToWindow(heading.bounds())
      buttonScrolledWindowRect = button.rectToWindow(button.bounds())
      headingChromeIndex =
        nodes.findRectNode(expectedHeadingRenderRect, headingStyle.box.fill)
      buttonChromeIndex =
        nodes.findRectNode(expectedButtonRenderRect, buttonStyle.box.fill)

    check scrollWindowOffset == initPoint(40, 30)
    checkRectNearlyEqual(headingScrolledWindowRect, initRect(40, 50, 100, 20))
    checkRectNearlyEqual(buttonScrolledWindowRect, initRect(40, 90, 100, 26))
    check headingChromeIndex >= 0
    check buttonChromeIndex >= 0

  test "scrolled non-default draw level descendant uses active translation":
    let
      root = newView(frame = initRect(0, 0, 220, 160))
      document = newView(frame = initRect(0, 0, 260, 220))
      overlay = newOverlayDrawView(initRect(60, 50, 30, 20))
      scrollView =
        newScrollView(frame = initRect(20, 30, 120, 80), documentView = document)

    overlay.background = initColor(0.6, 0.2, 0.8, 1.0)
    document.addSubview(overlay)
    root.addSubview(scrollView)
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.contentOffset = initPoint(40, 30)

    let
      renders = buildRenders(root)
      defaultNodes = renders[DefaultDrawLevel]
      overlayNodes = renders[OverlayDrawLevel]
      expectedOverlayRenderRect = initRect(40, 50, 30, 20)
      expectedOverlayVisibleRect = initRect(40, 50, 30, 20)
      overlayIndex = overlayNodes.findRectNode(
        expectedOverlayRenderRect, fill(initColor(0.6, 0.2, 0.8, 1.0).rgba)
      )

    var scrollTransformIndex = -1
    for idx, node in defaultNodes.nodes:
      if node.kind == nkTransform and node.transform.translation.x == -40.0 and
          node.transform.translation.y == -30.0:
        scrollTransformIndex = idx

    check scrollTransformIndex >= 0
    check OverlayDrawLevel in renders
    check overlayIndex >= 0
    if overlayIndex >= 0:
      check overlayNodes.nodes[overlayIndex].parent.int == -1
      check overlayNodes.rootIds.contains(overlayIndex.FigIdx)

      let overlayVisibility =
        renders.figVisibility(OverlayDrawLevel, overlayIndex.FigIdx)
      check overlayVisibility.visible
      check overlayVisibility.bounds.x.nearlyEqual(expectedOverlayVisibleRect.origin.x)
      check overlayVisibility.bounds.y.nearlyEqual(expectedOverlayVisibleRect.origin.y)
      check overlayVisibility.bounds.w.nearlyEqual(
        expectedOverlayVisibleRect.size.width
      )
      check overlayVisibility.bounds.h.nearlyEqual(
        expectedOverlayVisibleRect.size.height
      )

  test "horizontal scroll renders scrollers above demo document content":
    let
      window = newWindow("Scroll render", frame = initRect(0, 0, 420, 340))
      fixture = newScrollResizeFixture(initRect(0, 0, 420, 340))
      document = fixture.scrollView.documentView()
      row = newView(frame = initRect(22, 22, 540, 56))
      headingLabel =
        newHeadingLabel("Document Header", frame = initRect(12, 7, 220, 20))
      bodyLabel = newStatusLabel(
        "The document is larger than the viewport.", frame = initRect(12, 30, 500, 18)
      )

    row.background = initColor(0.92, 0.95, 0.99, 1.0)
    row.addSubviews(autoNames(headingLabel, bodyLabel))
    document.addSubview(row)
    window.setContentView(fixture.root)
    fixture.root.layoutSubtreeIfNeeded()

    let scrollPoint = fixture.scrollView.frame().origin.offset(30.0, 30.0)
    check window.scrollWheelAt(scrollPoint, deltaX = 3.0)
    check fixture.scrollView.contentOffset().x > 0.0'f32
    check not fixture.scrollView.horizontalScrollerRect().isEmpty
    check not fixture.scrollView.verticalScrollerRect().isEmpty

    let
      renders = buildRenders(fixture.root)
      nodes = renders[DefaultDrawLevel]
      scrollViewNodeIndex = nodes.findClippedNode(
        fixture.scrollView.rectToWindow(fixture.scrollView.bounds())
      )
      clipViewNodeIndex = nodes.findClippedNode(
        fixture.scrollView.clipView().rectToWindow(
          fixture.scrollView.clipView().bounds()
        )
      )
      horizontalScrollerIndex = nodes.findChildRectNode(
        scrollViewNodeIndex,
        fixture.scrollView.rectToWindow(fixture.scrollView.horizontalScrollerRect()),
      )
      verticalScrollerIndex = nodes.findChildRectNode(
        scrollViewNodeIndex,
        fixture.scrollView.rectToWindow(fixture.scrollView.verticalScrollerRect()),
      )
      clipViewOrder = nodes.childIndexOf(scrollViewNodeIndex, clipViewNodeIndex)
      horizontalScrollerOrder =
        nodes.childIndexOf(scrollViewNodeIndex, horizontalScrollerIndex)
      verticalScrollerOrder =
        nodes.childIndexOf(scrollViewNodeIndex, verticalScrollerIndex)

    check scrollViewNodeIndex >= 0
    check clipViewNodeIndex >= 0
    check horizontalScrollerIndex >= 0
    check verticalScrollerIndex >= 0
    check horizontalScrollerOrder > clipViewOrder
    check verticalScrollerOrder > clipViewOrder
