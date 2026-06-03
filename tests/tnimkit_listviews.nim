import std/unittest

import merenda/nimkit/listviews
import merenda/nimkit/types

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
