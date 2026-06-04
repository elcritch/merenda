import std/unittest

import sigils/selectors

import merenda/nimkit

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
    check not listView.listScrollIndicatorRect().isEmpty

    listView.scrollRows(-1)
    check listView.firstVisibleIndex == 1

    listView.removeItemAtIndex(3)
    check listView.len == 3
    check listView.selectedIndex == 2

    listView.selectionMode = lsmNone
    check listView.selectedIndex == -1
    listView.selectedIndex = 1
    check listView.selectedIndex == -1

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
