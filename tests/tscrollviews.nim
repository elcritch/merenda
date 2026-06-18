import std/unittest

import merenda/nimkit

proc newScrollFixture(): tuple[scrollView: ScrollView, document: View] =
  let
    document = newView(frame = initRect(0, 0, 320, 240))
    scrollView = newScrollView(frame = initRect(0, 0, 120, 80), documentView = document)
  scrollView.hasHorizontalScroller = true
  scrollView.hasVerticalScroller = true
  scrollView.autohidePolicy = sapNever
  scrollView.tile()
  (scrollView, document)

suite "nimkit scroll views":
  test "clip views expose document geometry and constrain scroll points":
    let
      fixture = newScrollFixture()
      scrollView = fixture.scrollView
      clipView = scrollView.clipView()

    check clipView.documentView() == fixture.document
    check clipView.documentRect() == initRect(0, 0, 320, 240)
    check clipView.documentVisibleRect().origin == initPoint(0, 0)

    check clipView.constrainScrollPoint(initPoint(-20, -10)) == initPoint(0, 0)
    check clipView.constrainScrollPoint(initPoint(500, 500)) == initPoint(212, 172)

    clipView.scrollToPoint(initPoint(40, 50))
    check scrollView.contentOffset() == initPoint(40, 50)
    check clipView.documentVisibleRect().origin == initPoint(40, 50)

  test "clip view autoscroll uses scroll view line increments":
    let
      fixture = newScrollFixture()
      scrollView = fixture.scrollView
      clipView = scrollView.clipView()

    scrollView.horizontalLineScroll = 7
    scrollView.verticalLineScroll = 11
    clipView.scrollToPoint(initPoint(20, 20))

    check clipView.autoscroll(MouseEvent(location: initPoint(118, 78), button: mbPrimary))
    check scrollView.contentOffset() == initPoint(27, 31)

  test "scroll view exposes scroll increments and chrome policy":
    let
      fixture = newScrollFixture()
      scrollView = fixture.scrollView
      horizontalHeader = newView(frame = initRect(0, 0, 50, 16))
      verticalHeader = newView(frame = initRect(0, 0, 16, 50))
      corner = newView(frame = initRect(0, 0, 16, 16))

    scrollView.horizontalLineScroll = 3
    scrollView.verticalLineScroll = 9
    scrollView.horizontalPageScroll = 30
    scrollView.verticalPageScroll = 60
    scrollView.borderType = svbLineBorder
    scrollView.drawsBackground = false
    scrollView.scrollerInsets = initEdgeInsets(2, 3, 4, 5)
    scrollView.horizontalHeaderView = horizontalHeader
    scrollView.verticalHeaderView = verticalHeader
    scrollView.cornerView = corner
    scrollView.setRulerPlaceholder(laHorizontal, initRulerPlaceholder(true, 18))
    scrollView.dynamicScrolling = false
    scrollView.autohidePolicy = sapAlways
    scrollView.tile()

    check scrollView.horizontalLineScroll() == 3
    check scrollView.verticalLineScroll() == 9
    check scrollView.horizontalPageScroll() == 30
    check scrollView.verticalPageScroll() == 60
    check scrollView.borderType() == svbLineBorder
    check not scrollView.drawsBackground()
    check scrollView.scrollerInsets() == initEdgeInsets(2, 3, 4, 5)
    check scrollView.horizontalHeaderView() == horizontalHeader
    check scrollView.verticalHeaderView() == verticalHeader
    check scrollView.cornerView() == corner
    check scrollView.rulerPlaceholder(laHorizontal) == initRulerPlaceholder(true, 18)
    check not scrollView.dynamicScrolling()
    check scrollView.autohidePolicy() == sapAlways
    check scrollView.horizontalScroller().hidden
    check scrollView.verticalScroller().hidden

  test "compatibility autohides bool maps to policy":
    let fixture = newScrollFixture()
    fixture.scrollView.autohidesScrollers = false
    check fixture.scrollView.autohidePolicy() == sapNever
    check not fixture.scrollView.autohidesScrollers()

    fixture.scrollView.autohidesScrollers = true
    check fixture.scrollView.autohidePolicy() == sapWhenNeeded
    check fixture.scrollView.autohidesScrollers()
