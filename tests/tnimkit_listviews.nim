import std/unittest

import sigils/selectors

import merenda/nimkit

proc listViewScrollerKnobRect(listView: ListView): Rect =
  scrollerKnobRect(
    listView.verticalScrollerRect(),
    laVertical,
    listScrollViewport(
      listView.firstVisibleIndex(), listView.len(), listView.visibleItemCount()
    ),
  )

suite "nimkit list views":
  test "popup list view tracks highlight activation and close callbacks":
    let
      items = @["One", "Two", "Three", "Four"]
      popupBounds = initRect(0, 0, 120, 62)
    var
      highlighted = -1
      activated = -1
      closed = 0

    proc itemCount(): int =
      items.len

    proc visibleCount(): int =
      3

    proc firstIndex(): int =
      0

    proc selectedIndex(): int =
      -1

    proc highlightedIndex(): int =
      highlighted

    proc rowHeight(): float32 =
      20.0'f32

    proc itemText(index: int): string =
      items[index]

    proc highlight(index: int) =
      highlighted = index

    proc activate(index: int) =
      activated = index

    proc close() =
      inc closed

    let popupList = newPopupListView(
      PopupListData(
        itemCount: itemCount,
        visibleCount: visibleCount,
        firstIndex: firstIndex,
        selectedIndex: selectedIndex,
        highlightedIndex: highlightedIndex,
        rowHeight: rowHeight,
        itemText: itemText,
      ),
      PopupListActions(highlight: highlight, activate: activate, close: close),
      frame = popupBounds,
    )

    check popupList.itemCount() == 4
    check popupList.visibleItemCount() == 3
    check popupList.itemText(1) == "Two"
    check popupList.popupListItemIndexAtPoint(popupBounds, initPoint(6, 25)) == 1
    check popupList.popupListItemIndexAtPoint(popupBounds, initPoint(6, 61)) == -1

    popupList.beginPopupListTracking(popupBounds, initPoint(6, 25))
    check highlighted == 1

    popupList.finishPopupListTracking(popupBounds, initPoint(6, 45))
    check activated == 2
    check closed == 1

    popupList.beginPopupListTracking(popupBounds, initPoint(6, 5))
    popupList.finishPopupListTracking(
      popupBounds, initPoint(6, 25), closeWhenDone = false
    )
    check activated == 1
    check closed == 1

  test "popup list scroll rows follows wheel direction":
    check popupListScrollRows(ScrollEvent(deltaY: -1.0'f32)) == 1
    check popupListScrollRows(ScrollEvent(deltaY: 1.0'f32)) == -1
    check popupListScrollRows(ScrollEvent(deltaY: 0.0'f32)) == 0

  test "list viewport uses shared scroll viewport row mechanics":
    var viewport = initListViewport(2)

    check viewport.firstIndex == 2
    check maxFirstIndex(6, 3) == 3
    check clampFirstIndex(-2, 6, 3) == 0
    check clampFirstIndex(8, 6, 3) == 3

    viewport.normalize(6, 3)
    check viewport.firstIndex == 2
    check viewport.canScrollBy(1, 6, 3)

    viewport.scrollBy(10, 6, 3)
    check viewport.firstIndex == 3
    check not viewport.canScrollBy(1, 6, 3)

    viewport.scrollToVisible(1, 6, 3)
    check viewport.firstIndex == 1

    viewport.firstIndex = 20
    viewport.normalize(6, 3)
    check viewport.firstIndex == 3

  test "list view stores local items and clamps selection viewport":
    let listView =
      newListView(["One", "Two", "Three", "Four"], frame = initRect(0, 0, 120, 46))

    listView.rowHeight = 20.0

    check listView.len == 4
    check listView.items == @["One", "Two", "Three", "Four"]
    check listView[1] == "Two"
    check listView.visibleItemCount() == 2
    check listView.listItemIndexAtPoint(initPoint(6, 25)) == 1

    listView.selectedIndex = 3
    check listView.selectedIndex == 3
    check listView.firstVisibleIndex == 2
    check not listView.listViewScrollerKnobRect().isEmpty

    listView.scrollRows(-1)
    check listView.firstVisibleIndex == 1

    listView.removeItemAtIndex(3)
    check listView.len == 3
    check listView.selectedIndex == 2

    listView.selectionMode = lsmNone
    check listView.selectedIndex == -1
    listView.selectedIndex = 1
    check listView.selectedIndex == -1

  test "list view owns a row content document view":
    let listView =
      newListView(["One", "Two", "Three", "Four"], frame = initRect(0, 0, 120, 46))

    listView.rowHeight = 20.0
    let
      clip = listView.clipView()
      content = listView.contentView()
      scroller = listView.verticalScroller()

    check clip != nil
    check clip.superview == listView
    check not clip.acceptsFirstResponder
    check not clip.autoresizingMaskConstraints
    check clip.clipsToBounds
    check clip.frame == initRect(1.0'f32, 1.0'f32, 106.0'f32, 44.0'f32)
    check clip.bounds == initRect(0.0'f32, 0.0'f32, 106.0'f32, 44.0'f32)
    check scroller != nil
    check scroller.superview == listView
    check not scroller.hidden
    check not scroller.acceptsFirstResponder
    check listView.verticalScrollerRect() ==
      initRect(107.0'f32, 1.0'f32, 12.0'f32, 44.0'f32)
    check listView.listViewScrollerKnobRect() ==
      initRect(107.0'f32, 1.0'f32, 12.0'f32, 22.0'f32)
    check content != nil
    check content.listView == listView
    check content.superview == View(clip)
    check not content.acceptsFirstResponder
    check not content.autoresizingMaskConstraints
    check content.frame == initRect(0.0'f32, 0.0'f32, 106.0'f32, 80.0'f32)
    check content.bounds.size == initSize(106.0'f32, 80.0'f32)
    check listView.listContentSize() == initSize(106.0'f32, 80.0'f32)
    check content.listContentItemRect(2) ==
      initRect(0.0'f32, 40.0'f32, 106.0'f32, 20.0'f32)

    check listView.listItemRect(0) == initRect(1.0'f32, 1.0'f32, 106.0'f32, 20.0'f32)
    check listView.listItemRect(2).isEmpty
    check content.listContentItemIndexAtPoint(initPoint(6.0'f32, 45.0'f32)) == 2

    listView.firstVisibleIndex = 2
    check content.frame == initRect(0.0'f32, 0.0'f32, 106.0'f32, 80.0'f32)
    check clip.bounds.origin == initPoint(0.0'f32, 40.0'f32)
    check listView.listViewScrollerKnobRect() ==
      initRect(107.0'f32, 23.0'f32, 12.0'f32, 22.0'f32)
    check listView.listItemRect(2) == initRect(1.0'f32, 1.0'f32, 106.0'f32, 20.0'f32)
    check listView.listItemIndexAtPoint(initPoint(6.0'f32, 25.0'f32)) == 3

  test "list view scroller pages and drags row viewport":
    let
      window = newWindow("List scroller", frame = initRect(0, 0, 220, 160))
      root = newView(frame = initRect(0, 0, 220, 160))
      listView = newListView(
        ["One", "Two", "Three", "Four", "Five", "Six"],
        frame = initRect(10, 10, 120, 46),
      )

    listView.rowHeight = 20.0
    root.addSubview(listView)
    window.setContentView(root)

    let
      track = listView.verticalScrollerRect()
      knob = listView.listViewScrollerKnobRect()
      scroller = listView.verticalScroller()

    check not scroller.isNil
    check not scroller.hidden
    let trackX = track.origin.x + track.size.width * 0.5'f32
    check window.mouseDownAt(listView.pointToWindow(initPoint(trackX, knob.maxY + 2.0)))
    check listView.firstVisibleIndex == 2

    let nextKnob = listView.listViewScrollerKnobRect()
    check window.mouseDownAt(
      listView.pointToWindow(
        initPoint(trackX, nextKnob.origin.y + nextKnob.size.height * 0.5'f32)
      )
    )
    check window.mouseDraggedAt(listView.pointToWindow(initPoint(trackX, track.maxY)))
    check window.mouseUpAt(listView.pointToWindow(initPoint(trackX, track.maxY)))
    check listView.firstVisibleIndex == 4

  test "list view mouse selection sends control action":
    let
      window = newWindow("List mouse", frame = initRect(0, 0, 220, 140))
      root = newView(frame = initRect(0, 0, 220, 140))
      listView = newListView(["One", "Two", "Three"], frame = initRect(10, 10, 120, 46))
      action = actionSelector("listSelectionAction")

    var
      actionCount = 0
      selectedText = ""

    proc onSelect(sender: DynamicAgent) =
      check sender == DynamicAgent(listView)
      inc actionCount
      selectedText = listView[listView.selectedIndex()]

    listView.rowHeight = 20.0
    listView.target = newActionTarget(action, onSelect)
    listView.action = action
    root.addSubview(listView)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(16, 36))
    check window.firstResponder == listView
    check listView.highlightedIndex == 1
    check window.mouseUpAt(initPoint(16, 36))
    check listView.selectedIndex == 1
    check actionCount == 1
    check selectedText == "Two"

  test "list view keyboard navigation scrolls and activates selection":
    let
      window = newWindow("List keyboard", frame = initRect(0, 0, 220, 160))
      root = newView(frame = initRect(0, 0, 220, 160))
      listView = newListView(
        ["One", "Two", "Three", "Four", "Five", "Six"],
        frame = initRect(10, 10, 120, 62),
      )
      action = actionSelector("listKeyboardAction")

    var actionCount = 0

    proc onActivate(sender: DynamicAgent) =
      check sender == DynamicAgent(listView)
      inc actionCount

    listView.rowHeight = 20.0
    listView.target = newActionTarget(action, onActivate)
    listView.action = action
    root.addSubview(listView)
    window.setContentView(root)

    check window.makeFirstResponder(listView)
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check listView.selectedIndex == 0
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check listView.selectedIndex == 1
    check window.dispatchKeyDown(KeyEvent(key: keyPageDown, keyCode: keyPageDown.ord))
    check listView.selectedIndex == 4
    check listView.firstVisibleIndex == 2
    check window.dispatchKeyDown(KeyEvent(key: keyHome, keyCode: keyHome.ord))
    check listView.selectedIndex == 0
    check window.dispatchKeyDown(KeyEvent(key: keyEnd, keyCode: keyEnd.ord))
    check listView.selectedIndex == 5
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check actionCount == 1
