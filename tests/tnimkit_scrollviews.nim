import std/unittest

import figdraw/fignodes

import merenda/nimkit
import merenda/nimkit/types as nimkitTypes

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

const GeometryTolerance = 0.01'f32

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

proc checkScrollerRectInside(scrollView: ScrollView, rect: nimkitTypes.Rect) =
  check not rect.isEmpty
  check rect.insideAxis(scrollView.bounds(), laHorizontal)
  check rect.insideAxis(scrollView.bounds(), laVertical)

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

  if scrollView.showsHorizontalScroller():
    checkScrollerRectInside(scrollView, scrollView.horizontalScrollerRect())
    checkScrollerRectInside(scrollView, scrollView.horizontalScrollerKnobRect())
  else:
    check scrollView.horizontalScrollerRect().isEmpty
    check scrollView.horizontalScrollerKnobRect().isEmpty

  if scrollView.showsVerticalScroller():
    checkScrollerRectInside(scrollView, scrollView.verticalScrollerRect())
    checkScrollerRectInside(scrollView, scrollView.verticalScrollerKnobRect())
  else:
    check scrollView.verticalScrollerRect().isEmpty
    check scrollView.verticalScrollerKnobRect().isEmpty

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
  result.root.addSubview(
    result.title, result.status, result.scrollView, result.controls
  )

  result.title.pinEdges(toGuide = guide, edges = {leLeft, leTop, leRight})
  activate(
    result.status.topAnchor.constraintEqualTo(result.title.bottomAnchor, constant = 8.0),
    result.status.leftAnchor.constraintEqualTo(result.title.leftAnchor),
    result.status.rightAnchor.constraintEqualTo(result.title.rightAnchor),
    result.scrollView.topAnchor.constraintEqualTo(
      result.status.bottomAnchor, constant = 12.0
    ),
    result.scrollView.leftAnchor.constraintEqualTo(result.title.leftAnchor),
    result.scrollView.rightAnchor.constraintEqualTo(result.title.rightAnchor),
    result.controls.topAnchor.constraintEqualTo(
      result.scrollView.bottomAnchor, constant = 12.0
    ),
    result.controls.leftAnchor.constraintEqualTo(result.title.leftAnchor),
    result.controls.rightAnchor.constraintEqualTo(result.title.rightAnchor),
    result.controls.bottomAnchor.constraintEqualTo(guide.bottomAnchor),
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
    check fixture.scrollView.showsHorizontalScroller()
  if documentSize.height > maxViewportHeight + GeometryTolerance:
    check fixture.scrollView.showsVerticalScroller()

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

  test "wheel over non-scrollable list view bubbles to parent scroll view":
    let
      listView = newListView(["One", "Two"], frame = initRect(20, 20, 120, 68))
      fixture = newNestedScrollFixture(listView)

    listView.rowHeight = 20.0

    check listView.visibleItemCount() == listView.len()
    check listView.listScrollIndicatorRect().isEmpty
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

    check not scrollView.showsHorizontalScroller()
    check not scrollView.showsVerticalScroller()

    document.frame = initRect(0, 0, 160, 120)
    scrollView.tile()

    check scrollView.showsHorizontalScroller()
    check scrollView.showsVerticalScroller()
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
    check scrollView.showsHorizontalScroller()
    check scrollView.showsVerticalScroller()

    scrollView.frame = initRect(0, 0, 760, 680)
    scrollView.layoutSubtreeIfNeeded()
    checkScrollViewResizeInvariants(scrollView)
    check scrollView.contentOffset() == initPoint(0, 0)
    check not scrollView.showsHorizontalScroller()
    check not scrollView.showsVerticalScroller()

    scrollView.frame = initRect(0, 0, 260, 180)
    scrollView.layoutSubtreeIfNeeded()
    checkScrollViewResizeInvariants(scrollView)
    check scrollView.showsHorizontalScroller()
    check scrollView.showsVerticalScroller()

  test "scroll view resizes with constraint layout":
    let
      root = newView(frame = initRect(0, 0, 260, 180))
      guide = root.contentLayoutGuide(initEdgeInsets(12.0))
      document = newView(frame = initRect(0, 0, 420, 360))
      scrollView = newScrollView(documentView = document)
      footer = newButton("Done")

    root.addSubview(scrollView, footer)
    activate(
      scrollView.topAnchor.constraintEqualTo(guide.topAnchor),
      scrollView.leftAnchor.constraintEqualTo(guide.leftAnchor),
      scrollView.rightAnchor.constraintEqualTo(guide.rightAnchor),
      footer.topAnchor.constraintEqualTo(scrollView.bottomAnchor, constant = 8.0),
      footer.leftAnchor.constraintEqualTo(guide.leftAnchor),
      footer.rightAnchor.constraintEqualTo(guide.rightAnchor),
      footer.bottomAnchor.constraintEqualTo(guide.bottomAnchor),
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
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == initColor(0.2, 0.4, 0.7, 1.0).rgba:
        childNodeFound = true
        childNodeIndex = idx
        check node.screenBox.x == 40.0
        check node.screenBox.y == 50.0
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
    check childNodeFound
    check verticalScrollerIndex >= 0
    check horizontalScrollerIndex >= 0
    check nodes.nodes[clipViewNodeIndex].parent.int == scrollViewNodeIndex
    check nodes.nodes[verticalScrollerIndex].parent.int == scrollViewNodeIndex
    check nodes.nodes[horizontalScrollerIndex].parent.int == scrollViewNodeIndex
    check nodes.hasAncestor(childNodeIndex, clipViewNodeIndex)

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
    row.addSubview(headingLabel, bodyLabel)
    document.addSubview(row)
    window.setContentView(fixture.root)
    fixture.root.layoutSubtreeIfNeeded()

    let scrollPoint = fixture.scrollView.frame().origin.offset(30.0, 30.0)
    check window.scrollWheelAt(scrollPoint, deltaX = 3.0)
    check fixture.scrollView.contentOffset().x > 0.0'f32
    check fixture.scrollView.showsHorizontalScroller()
    check fixture.scrollView.showsVerticalScroller()

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
