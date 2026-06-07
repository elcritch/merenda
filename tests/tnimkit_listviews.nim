import std/[options, unicode, unittest, sequtils]

import figdraw/fignodes except Rect
import sigils/core
import sigils/selectors

import merenda/nimkit

type
  ListDataSourceSpy = ref object of Responder
    rows: seq[string]

  ListDelegateSpy = ref object of Responder
    changingCount: int
    changedCount: int
    activatedCount: int
    lastSender: DynamicAgent

  ListRowRendererSpy = ref object of Responder
    views: seq[ListView]
    rows: seq[ListRowState]
    rects: seq[Rect]
    emptyViews: seq[ListView]
    emptyRects: seq[Rect]

  ListPolicyDelegateSpy = ref object of Responder
    disabledRows: seq[int]
    nonselectableRows: seq[int]
    rowHeights: seq[float32]
    styledRow: int
    style: ListRowStyle
    rows: seq[ListRowState]

proc containsIndex(indexes: openArray[int], index: int): bool =
  for value in indexes:
    if value == index:
      return true
  false

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add(rune)

protocol ListDataSourceSpyMethods of ListViewDataSource:
  method rowCount(source: ListDataSourceSpy, listView: ListView): int =
    source.rows.len

  method objectValueForRow(
      source: ListDataSourceSpy, listView: ListView, row: int
  ): string =
    if row < 0 or row >= source.rows.len:
      return ""
    source.rows[row]

protocol ListDelegateSpyEvents from ListDelegateSpy:
  includes ListViewEvents

  proc selectionIsChanging(delegate: ListDelegateSpy, sender: DynamicAgent) {.slot.} =
    inc delegate.changingCount
    delegate.lastSender = sender

  proc selectionDidChange(delegate: ListDelegateSpy, sender: DynamicAgent) {.slot.} =
    inc delegate.changedCount
    delegate.lastSender = sender

  proc rowWasActivated(delegate: ListDelegateSpy, sender: DynamicAgent) {.slot.} =
    inc delegate.activatedCount
    delegate.lastSender = sender

protocol ListRowRendererSpyMethods of ListViewDelegate:
  method drawRow(
      renderer: ListRowRendererSpy,
      listView: ListView,
      context: DrawContext,
      rect: Rect,
      row: ListRowState,
  ) =
    renderer.views.add listView
    renderer.rows.add row
    renderer.rects.add rect
    listView.drawListRow(context, rect, row)

  method drawEmptyState(
      renderer: ListRowRendererSpy, listView: ListView, context: DrawContext, rect: Rect
  ) =
    renderer.emptyViews.add listView
    renderer.emptyRects.add rect

protocol ListPolicyDelegateSpyMethods of ListViewDelegate:
  method rowIsEnabled(
      policy: ListPolicyDelegateSpy, listView: ListView, row: int
  ): bool =
    not policy.disabledRows.containsIndex(row)

  method shouldSelectRow(
      policy: ListPolicyDelegateSpy, listView: ListView, row: int
  ): bool =
    not policy.nonselectableRows.containsIndex(row)

  method heightOfRow(
      policy: ListPolicyDelegateSpy, listView: ListView, row: int
  ): float32 =
    if row < 0 or row >= policy.rowHeights.len:
      return listView.rowHeight()
    policy.rowHeights[row]

  method styleForRow(
      policy: ListPolicyDelegateSpy, listView: ListView, row: ListRowState
  ): ListRowStyle =
    if row.index == policy.styledRow:
      policy.style
    else:
      initListRowStyle()

  method drawRow(
      policy: ListPolicyDelegateSpy,
      listView: ListView,
      context: DrawContext,
      rect: Rect,
      row: ListRowState,
  ) =
    policy.rows.add row
    listView.drawListRow(context, rect, row)

proc newListDataSourceSpy(rows: openArray[string]): ListDataSourceSpy =
  result = ListDataSourceSpy(rows: @rows)
  initResponder(result)
  discard result.withProtocol(ListDataSourceSpyMethods)

proc newListDelegateSpy(): ListDelegateSpy =
  result = ListDelegateSpy()
  initResponder(result)
  result = result.withProto()

proc newListRowRendererSpy(): ListRowRendererSpy =
  result = ListRowRendererSpy()
  initResponder(result)
  discard result.withProtocol(ListRowRendererSpyMethods)

proc newListPolicyDelegateSpy(
    disabledRows: openArray[int] = [],
    nonselectableRows: openArray[int] = [],
    rowHeights: openArray[float32] = [],
    styledRow = -1,
    style = initListRowStyle(),
): ListPolicyDelegateSpy =
  result = ListPolicyDelegateSpy(
    disabledRows: @disabledRows,
    nonselectableRows: @nonselectableRows,
    rowHeights: @rowHeights,
    styledRow: styledRow,
    style: style,
  )
  initResponder(result)
  discard result.withProtocol(ListPolicyDelegateSpyMethods)

proc clear(spy: ListRowRendererSpy) =
  spy.views.setLen(0)
  spy.rows.setLen(0)
  spy.rects.setLen(0)
  spy.emptyViews.setLen(0)
  spy.emptyRects.setLen(0)

proc clear(spy: ListPolicyDelegateSpy) =
  spy.rows.setLen(0)

proc listViewScrollerKnobRect(listView: ListView): Rect =
  scrollerKnobRect(
    listView.verticalScrollerRect(),
    laVertical,
    listScrollViewport(
      listView.firstVisibleIndex(), listView.len(), listView.visibleItemCount()
    ),
  )

proc clickListRow(
    window: Window, listView: ListView, row: int, modifiers: set[KeyModifier] = {}
): bool =
  let point = listView.pointToWindow(
    initPoint(
      6.0'f32, row.float32 * listView.rowHeight() + listView.rowHeight() * 0.5'f32
    )
  )
  window.mouseDownAt(point, modifiers = modifiers) and
    window.mouseUpAt(point, modifiers = modifiers)

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
    check listView.items().toSeq() == @["One", "Two", "Three", "Four"]
    check listView[1] == "Two"
    check listView.visibleItemCount() == 2
    check listView.listItemIndexAtPoint(initPoint(6, 25)) == 1

    listView.selectedIndex = 3
    check listView.selectedIndex == 3
    check listView.firstVisibleIndex == 1
    check not listView.listViewScrollerKnobRect().isEmpty

    listView.scrollRows(-1)
    check listView.firstVisibleIndex == 0

    listView.removeItemAtIndex(3)
    check listView.len == 3
    check listView.selectedIndex == 2

    listView.selectionMode = lsmNone
    check listView.selectedIndex == -1
    listView.selectedIndex = 1
    check listView.selectedIndex == -1

  test "list view scrolls selected item to visible":
    let listView = newListView(
      ["One", "Two", "Three", "Four", "Five"], frame = initRect(0, 0, 120, 46)
    )

    listView.rowHeight = 20.0
    listView.selectedIndex = 4
    check listView.firstVisibleIndex == 2

    listView.firstVisibleIndex = 0
    check listView.firstVisibleIndex == 0
    listView.scrollSelectedItemToVisible()
    check listView.firstVisibleIndex == 2

  test "list view resolves rows from data source and reload clamps selection":
    let
      listView = newListView(["Local"], frame = initRect(0, 0, 120, 46))
      source = newListDataSourceSpy(["Red", "Green", "Blue", "Indigo"])

    listView.rowHeight = 20.0
    listView.dataSource = source

    check listView.len == 4
    check listView.items.toSeq == @["Local"]
    check listView[2] == "Blue"

    listView.selectedIndex = 3
    check listView.selectedIndex == 3
    check listView.selectedIndexes == @[3]
    check listView.firstVisibleIndex == 1

    source.rows.setLen(2)
    listView.reloadData()
    check listView.len == 2
    check listView.selectedIndex == 1
    check listView.selectedIndexes == @[1]
    check listView.firstVisibleIndex == 0

  test "list view delegate receives selection and activation callbacks":
    let
      listView = newListView(["One", "Two", "Three"], frame = initRect(0, 0, 120, 46))
      delegate = newListDelegateSpy()
      action = actionSelector("listDelegateAction")

    var actionCount = 0

    proc onAction(sender: DynamicAgent) =
      check sender == DynamicAgent(listView)
      inc actionCount

    listView.rowHeight = 20.0
    listView.delegate = delegate
    listView.target = newActionTarget(action, onAction)
    listView.action = action

    listView.selectedIndex = 1
    check delegate.changingCount == 1
    check delegate.changedCount == 1
    check delegate.activatedCount == 0
    check delegate.lastSender == DynamicAgent(listView)

    listView.selectedIndex = 1
    check delegate.changingCount == 1
    check delegate.changedCount == 1

    listView.activateItemAtIndex(2)
    check listView.selectedIndex == 2
    check delegate.changingCount == 2
    check delegate.changedCount == 2
    check delegate.activatedCount == 1
    check actionCount == 1

  test "list view selected indexes normalize by selection mode":
    let listView =
      newListView(["One", "Two", "Three", "Four"], frame = initRect(0, 0, 120, 46))

    listView.selectionMode = lsmMultiple
    listView.selectedIndexes = [3, 1, 1, 8, -1, 2]
    check listView.selectedIndexes == @[1, 2, 3]
    check listView.selectedIndex == 1

    listView.selectionMode = lsmSingle
    check listView.selectedIndexes == @[1]
    check listView.selectedIndex == 1

    listView.selectionMode = lsmNone
    check listView.selectedIndexes == newSeq[int]()
    listView.selectedIndexes = [2]
    check listView.selectedIndexes == newSeq[int]()
    check listView.selectedIndex == -1

  test "list view exposes selected range convenience APIs":
    let listView = newListView(
      ["One", "Two", "Three", "Four", "Five", "Six"], frame = initRect(0, 0, 120, 46)
    )

    check listView.selectedRange == 0 .. -1
    check listView.selectedRanges == newSeq[Slice[int]]()

    listView.selectionMode = lsmExtended
    listView.selectedRange = 1 .. 3
    check listView.selectedIndexes == @[1, 2, 3]
    check listView.selectedRange == 1 .. 3
    check listView.selectedRanges == @[1 .. 3]
    check listView.selectedIndex == 1

    listView.selectedIndexes = [0, 2, 3, 5]
    check listView.selectedRange == 0 .. 0
    check listView.selectedRanges == @[0 .. 0, 2 .. 3, 5 .. 5]

    listView.selectionMode = lsmSingle
    listView.selectedRange = 2 .. 4
    check listView.selectedIndexes == @[2]
    check listView.selectedRange == 2 .. 2

  test "list view extended keyboard selection uses anchor and lead rows":
    let
      window = newWindow("List extended keyboard", frame = initRect(0, 0, 220, 160))
      root = newView(frame = initRect(0, 0, 220, 160))
      listView = newListView(
        ["One", "Two", "Three", "Four", "Five", "Six"],
        frame = initRect(10, 10, 120, 62),
      )

    listView.rowHeight = 20.0
    listView.selectionMode = lsmExtended
    root.addSubview(listView)
    window.setContentView(root)

    check window.makeFirstResponder(listView)
    listView.selectedIndex = 1
    check listView.selectedIndexes == @[1]

    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord, modifiers: {kmShift})
    )
    check listView.selectedIndexes == @[1, 2]
    check listView.selectedIndex == 1

    check window.dispatchKeyDown(
      KeyEvent(key: keyPageDown, keyCode: keyPageDown.ord, modifiers: {kmShift})
    )
    check listView.selectedIndexes == @[1, 2, 3, 4, 5]

    check window.dispatchKeyDown(KeyEvent(key: keyArrowUp, keyCode: keyArrowUp.ord))
    check listView.selectedIndexes == @[4]
    check listView.selectedIndex == 4

  test "list view mouse modifiers extend and toggle selection":
    let
      window = newWindow("List extended mouse", frame = initRect(0, 0, 220, 180))
      root = newView(frame = initRect(0, 0, 220, 180))
      listView = newListView(
        ["One", "Two", "Three", "Four", "Five"], frame = initRect(10, 10, 120, 102)
      )

    listView.rowHeight = 20.0
    listView.selectionMode = lsmExtended
    root.addSubview(listView)
    window.setContentView(root)

    check window.clickListRow(listView, 1)
    check listView.selectedIndexes == @[1]

    check window.clickListRow(listView, 3, modifiers = {kmShift})
    check listView.selectedIndexes == @[1, 2, 3]

    check window.clickListRow(listView, 2, modifiers = shortcutModifiers())
    check listView.selectedIndexes == @[1, 3]

    check window.clickListRow(listView, 4, modifiers = shortcutModifiers())
    check listView.selectedIndexes == @[1, 3, 4]

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
    check listView.contentSize() == initSize(106.0'f32, 80.0'f32)
    check content.listContentItemRect(2) ==
      initRect(0.0'f32, 40.0'f32, 106.0'f32, 20.0'f32)

    check listView.listItemRect(0) == initRect(1.0'f32, 1.0'f32, 106.0'f32, 20.0'f32)
    check listView.listItemRect(2).isEmpty
    check content.listContentItemIndexAtPoint(initPoint(6.0'f32, 45.0'f32)) == 2

    listView.firstVisibleIndex = 2
    check content.frame == initRect(0.0'f32, 0.0'f32, 106.0'f32, 80.0'f32)
    check clip.bounds.origin == initPoint(0.0'f32, 36.0'f32)
    check listView.listViewScrollerKnobRect() ==
      initRect(107.0'f32, 12.0'f32, 12.0'f32, 22.0'f32)
    check listView.listItemRect(2) == initRect(1.0'f32, 5.0'f32, 106.0'f32, 20.0'f32)
    check listView.listItemIndexAtPoint(initPoint(6.0'f32, 25.0'f32)) == 3

  test "list view reuses visible row views":
    let listView = newListView(
      ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"],
      frame = initRect(0, 0, 120, 62),
    )

    listView.rowHeight = 20.0
    discard buildRenders(listView)

    let
      content = listView.contentView()
      initialRows = content.subviews()

    check initialRows.len == 3
    check initialRows[0].frame == content.listContentItemRect(0)
    check initialRows[1].frame == content.listContentItemRect(1)
    check initialRows[2].frame == content.listContentItemRect(2)
    check listView.hitTest(initPoint(6.0'f32, 25.0'f32)) == listView

    listView.firstVisibleIndex = 4
    discard buildRenders(listView)

    let scrolledRows = content.subviews()
    check scrolledRows.len == 3
    check scrolledRows[0] == initialRows[0]
    check scrolledRows[1] == initialRows[1]
    check scrolledRows[2] == initialRows[2]
    check scrolledRows[0].frame == content.listContentItemRect(4)
    check scrolledRows[1].frame == content.listContentItemRect(5)
    check scrolledRows[2].frame == content.listContentItemRect(6)

    listView.frame = initRect(0, 0, 120, 102)
    discard buildRenders(listView)
    let expandedRows = content.subviews()
    check expandedRows.len == 5
    check expandedRows[0] == initialRows[0]
    check expandedRows[1] == initialRows[1]
    check expandedRows[2] == initialRows[2]

    listView.frame = initRect(0, 0, 120, 22)
    discard buildRenders(listView)
    let collapsedRows = content.subviews()
    check collapsedRows.len == 1
    check collapsedRows[0] == initialRows[0]

    listView.removeAllItems()
    discard buildRenders(listView)
    check content.subviews().len == 0

  test "list view exposes visible row and selection summaries":
    let
      window = newWindow("List summaries", frame = initRect(0, 0, 220, 160))
      root = newView(frame = initRect(0, 0, 220, 160))
      listView = newListView(
        ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"],
        frame = initRect(10, 10, 120, 62),
      )

    listView.rowHeight = 20.0
    listView.selectionMode = lsmExtended
    listView.selectedIndex = 5
    listView.highlightedIndex = 6
    listView.firstVisibleIndex = 4
    root.addSubview(listView)
    window.setContentView(root)
    check window.makeFirstResponder(listView)

    let rows = listView.visibleRowSummaries()
    check rows.len == 3
    check rows[0].index == 4
    check rows[0].text == "Five"
    check rows[0].rect == initRect(1.0'f32, 1.0'f32, 106.0'f32, 20.0'f32)
    check not rows[0].selected
    check rows[0].focused
    check rows[1].index == 5
    check rows[1].selected
    check rows[2].index == 6
    check rows[2].highlighted

    var selection = listView.selectionSummary()
    check selection.mode == lsmExtended
    check selection.selectedIndex == 5
    check selection.selectedIndexes == @[5]
    check selection.anchorIndex == 5
    check selection.leadIndex == 5
    check selection.hasSelection

    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord, modifiers: {kmShift})
    )
    selection = listView.selectionSummary()
    check selection.selectedIndex == 5
    check selection.selectedIndexes == @[5, 6]
    check selection.anchorIndex == 5
    check selection.leadIndex == 6

  test "list view delegate can render visible row states":
    let
      listView = newListView(
        ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"],
        frame = initRect(0, 0, 120, 62),
      )
      renderer = newListRowRendererSpy()

    listView.rowHeight = 20.0
    listView.delegate = renderer
    listView.selectedIndex = 1
    listView.highlightedIndex = 2

    discard buildRenders(listView)

    check renderer.rows.len == 3
    check renderer.views.len == 3
    check renderer.views[0] == listView
    check renderer.rows[0] == initListRowState(0, "One")
    check renderer.rows[1] == initListRowState(
      1, "Two", states = {lrsEnabled, lrsSelected}
    )
    check renderer.rows[2] == initListRowState(
      2, "Three", states = {lrsEnabled, lrsHighlighted}
    )
    check renderer.rects[0] == initRect(0.0'f32, 0.0'f32, 106.0'f32, 20.0'f32)
    check renderer.rects[1] == initRect(0.0'f32, 0.0'f32, 106.0'f32, 20.0'f32)
    check renderer.rects[2] == initRect(0.0'f32, 0.0'f32, 106.0'f32, 20.0'f32)

    listView.firstVisibleIndex = 4
    renderer.clear()
    discard buildRenders(listView)

    check renderer.rows.len == 3
    check renderer.rows[0] == initListRowState(4, "Five")
    check renderer.rows[1] == initListRowState(5, "Six")
    check renderer.rows[2] == initListRowState(6, "Seven")
    check renderer.rects[0] == initRect(0.0'f32, 0.0'f32, 106.0'f32, 20.0'f32)
    check renderer.rects[1] == initRect(0.0'f32, 0.0'f32, 106.0'f32, 20.0'f32)
    check renderer.rects[2] == initRect(0.0'f32, 0.0'f32, 106.0'f32, 20.0'f32)

  test "list view row states include alternating and pressed affordances":
    let
      window = newWindow("List affordance states", frame = initRect(0, 0, 220, 160))
      root = newView(frame = initRect(0, 0, 220, 160))
      listView =
        newListView(["One", "Two", "Three", "Four"], frame = initRect(10, 10, 120, 62))
      renderer = newListRowRendererSpy()

    listView.rowHeight = 20.0
    listView.usesAlternatingRowBackgrounds = true
    listView.delegate = renderer
    root.addSubview(listView)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(16, 56))
    discard buildRenders(listView)

    check renderer.rows.len == 3
    check not (lrsAlternating in renderer.rows[0].states)
    check lrsAlternating in renderer.rows[1].states
    check not (lrsPressed in renderer.rows[1].states)
    check lrsPressed in renderer.rows[2].states

  test "list view renders alternating rows and separators":
    let
      listView = newListView(["One", "Two", "Three"], frame = initRect(0, 0, 120, 62))
      alternatingFill = initColor(0.96, 0.97, 0.99, 1.0)
      separatorFill = initColor(0.86, 0.88, 0.91, 1.0)

    listView.rowHeight = 20.0
    listView.usesAlternatingRowBackgrounds = true
    listView.showsRowSeparators = true

    var theme = initTheme()
    theme[ListItemSeparatorColorToken] = separatorFill

    let nodes = buildRenders(listView, initAppearance(theme))[DefaultDrawLevel]
    var
      alternatingFound = false
      separatorCount = 0
    for node in nodes.nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor:
        if node.fill.color == alternatingFill.rgba and node.screenBox.x == 1.0 and
            node.screenBox.y == 21.0 and node.screenBox.w == 118.0 and
            node.screenBox.h == 20.0:
          alternatingFound = true
        if node.fill.color == separatorFill.rgba and node.screenBox.w == 118.0 and
            node.screenBox.h == 1.0:
          inc separatorCount

    check alternatingFound
    check separatorCount == 2

  test "list view delegate can render an empty state":
    let
      listView = newListView(frame = initRect(0, 0, 120, 62))
      renderer = newListRowRendererSpy()

    listView.delegate = renderer
    discard buildRenders(listView)

    check renderer.rows.len == 0
    check renderer.emptyViews.len > 0
    check renderer.emptyViews.len == renderer.emptyRects.len
    for view in renderer.emptyViews:
      check view == listView
    for rect in renderer.emptyRects:
      check rect == initRect(1.0'f32, 1.0'f32, 118.0'f32, 60.0'f32)

  test "list view row policy controls enabled state and selection":
    let
      listView = newListView(
        ["One", "Two", "Three", "Four", "Five"], frame = initRect(0, 0, 120, 102)
      )
      policy = newListPolicyDelegateSpy(disabledRows = [1], nonselectableRows = [3])

    listView.rowHeight = 20.0
    listView.delegate = policy

    check listView.rowEnabled(0)
    check not listView.rowEnabled(1)
    check listView.rowEnabled(3)
    check listView.rowSelectable(0)
    check not listView.rowSelectable(1)
    check not listView.rowSelectable(3)

    listView.selectedIndex = 1
    check listView.selectedIndex == -1
    listView.selectedIndex = 3
    check listView.selectedIndex == -1
    listView.selectedIndex = 2
    check listView.selectedIndex == 2

    listView.selectionMode = lsmMultiple
    listView.selectedIndexes = [0, 1, 2, 3, 4]
    check listView.selectedIndexes == @[0, 2, 4]

    policy.clear()
    discard buildRenders(listView)
    check policy.rows.len == 5
    check policy.rows[1] == initListRowState(1, "Two", states = {})
    check policy.rows[3] == initListRowState(3, "Four")

  test "list view delegates expose row height and optional row styling":
    let
      listView = newListView(["One", "Two", "Three"], frame = initRect(0, 0, 120, 62))
      styledFill = initColor(0.46, 0.18, 0.62, 1.0)
      styledText = initColor(0.96, 0.92, 1.0, 1.0)
      policy = newListPolicyDelegateSpy(
        rowHeights = [20.0'f32, 34.0'f32, 18.0'f32],
        styledRow = 1,
        style =
          initListRowStyle(fill = some(fill(styledFill)), textColor = some(styledText)),
      )

    listView.rowHeight = 20.0
    listView.delegate = policy

    check listView.items.toSeq == @["One", "Two", "Three"]
    check listView.rowHeight() == 20.0'f32
    check listView.rowHeightForRow(0) == 20.0'f32
    check listView.rowHeightForRow(1) == 34.0'f32
    check listView.rowHeightForRow(2) == 18.0'f32
    check listView.rowHeightForRow(3) == 0.0'f32
    check listView.resolvedIntrinsicContentSize().height == 74.0'f32
    check listView.contentSize().height == 72.0'f32
    check listView.contentView().listContentItemRect(0) ==
      initRect(0.0'f32, 0.0'f32, 106.0'f32, 20.0'f32)
    check listView.contentView().listContentItemRect(1) ==
      initRect(0.0'f32, 20.0'f32, 106.0'f32, 34.0'f32)
    check listView.contentView().listContentItemRect(2) ==
      initRect(0.0'f32, 54.0'f32, 106.0'f32, 18.0'f32)
    check listView.contentView().listContentItemIndexAtPoint(initPoint(6.0, 55.0)) == 2
    check listView.rowStyle(initListRowState(0, "One")) == initListRowStyle()
    check listView.rowStyle(initListRowState(1, "Two")) ==
      initListRowStyle(fill = some(fill(styledFill)), textColor = some(styledText))

    let nodes = buildRenders(listView)[DefaultDrawLevel]
    var
      styledFillFound = false
      styledTextFound = false
    for node in nodes.nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == styledFill.rgba and node.screenBox.h == 34.0:
        styledFillFound = true
      if node.kind == nkText and node.renderedText() == "Two" and
          node.textLayout.spanColors.len > 0 and
          node.textLayout.spanColors[0].kind == flColor and
          node.textLayout.spanColors[0].color == styledText.rgba:
        styledTextFound = true

    check styledFillFound
    check styledTextFound

    policy.rowHeights[1] = 40.0'f32
    check listView.rowHeightForRow(1) == 34.0'f32
    listView.noteHeightOfRowChanged(1)
    check listView.rowHeightForRow(1) == 40.0'f32
    check listView.contentSize().height == 78.0'f32
    check listView.contentView().listContentItemRect(2).origin.y == 60.0'f32

  test "list view row policy skips mouse and keyboard selection":
    let
      window = newWindow("List row policy", frame = initRect(0, 0, 220, 180))
      root = newView(frame = initRect(0, 0, 220, 180))
      listView = newListView(
        ["One", "Two", "Three", "Four", "Five"], frame = initRect(10, 10, 120, 102)
      )
      policy = newListPolicyDelegateSpy(disabledRows = [1], nonselectableRows = [3])
      action = actionSelector("listPolicyAction")

    var actionCount = 0

    proc onAction(sender: DynamicAgent) =
      check sender == DynamicAgent(listView)
      inc actionCount

    listView.rowHeight = 20.0
    listView.delegate = policy
    listView.target = newActionTarget(action, onAction)
    listView.action = action
    root.addSubview(listView)
    window.setContentView(root)

    check window.clickListRow(listView, 0)
    check listView.selectedIndex == 0
    check actionCount == 1

    check window.clickListRow(listView, 1)
    check listView.selectedIndex == 0
    check actionCount == 1

    check window.clickListRow(listView, 3)
    check listView.selectedIndex == 0
    check actionCount == 1

    check window.makeFirstResponder(listView)
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check listView.selectedIndex == 2
    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check listView.selectedIndex == 4
    check window.dispatchKeyDown(KeyEvent(key: keyArrowUp, keyCode: keyArrowUp.ord))
    check listView.selectedIndex == 2
    check window.dispatchKeyDown(KeyEvent(key: keyHome, keyCode: keyHome.ord))
    check listView.selectedIndex == 0
    check window.dispatchKeyDown(KeyEvent(key: keyEnd, keyCode: keyEnd.ord))
    check listView.selectedIndex == 4
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check actionCount == 2

  test "list view scrolls selection lead with variable row heights":
    let
      window = newWindow("List selection scroll", frame = initRect(0, 0, 220, 160))
      root = newView(frame = initRect(0, 0, 220, 160))
      listView = newListView(
        ["One", "Two", "Three", "Four", "Five"], frame = initRect(10, 10, 120, 42)
      )
      policy = newListPolicyDelegateSpy(rowHeights = [12.0'f32, 18.0, 44.0, 20.0, 16.0])

    listView.delegate = policy
    listView.selectionMode = lsmExtended
    root.addSubview(listView)
    window.setContentView(root)

    check window.makeFirstResponder(listView)
    listView.selectedIndex = 1
    check window.dispatchKeyDown(
      KeyEvent(key: keyPageDown, keyCode: keyPageDown.ord, modifiers: {kmShift})
    )
    check listView.selectedIndexes == @[1, 2, 3]
    check listView.selectedIndex == 1

    listView.firstVisibleIndex = 0
    listView.scrollSelectionToVisible()
    check listView.firstVisibleIndex == 2

    listView.firstVisibleIndex = 2
    listView.scrollSelectedItemToVisible()
    check listView.firstVisibleIndex == 1

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
    check listView.firstVisibleIndex == 3

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

  test "list view double-click activates selected row":
    let
      window = newWindow("List double click", frame = initRect(0, 0, 220, 140))
      root = newView(frame = initRect(0, 0, 220, 140))
      listView = newListView(["One", "Two", "Three"], frame = initRect(10, 10, 120, 62))
      action = actionSelector("listDoubleClickAction")

    var actionCount = 0

    proc onActivate(sender: DynamicAgent) =
      check sender == DynamicAgent(listView)
      inc actionCount

    listView.rowHeight = 20.0
    listView.selectedIndex = 0
    listView.target = newActionTarget(action, onActivate)
    listView.action = action
    root.addSubview(listView)
    window.setContentView(root)

    check window.mouseDownAt(initPoint(16, 56), clickCount = 2)
    check window.mouseUpAt(initPoint(16, 56), clickCount = 2)
    check listView.selectedIndex == 2
    check actionCount == 1

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

  test "list view type-select matches rows incrementally":
    let
      window = newWindow("List type select", frame = initRect(0, 0, 220, 160))
      root = newView(frame = initRect(0, 0, 220, 160))
      listView = newListView(
        ["Apple", "Banana", "Blueberry", "Cherry", "Date"],
        frame = initRect(10, 10, 120, 62),
      )

    listView.rowHeight = 20.0
    root.addSubview(listView)
    window.setContentView(root)

    check window.makeFirstResponder(listView)
    check window.dispatchKeyDown(KeyEvent(text: "b", key: keyB, keyCode: keyB.ord))
    check listView.selectedIndex == 1
    check window.dispatchKeyDown(KeyEvent(text: "l", key: keyL, keyCode: keyL.ord))
    check listView.selectedIndex == 2
    check window.dispatchKeyDown(KeyEvent(text: "c", key: keyC, keyCode: keyC.ord))
    check listView.selectedIndex == 3

    check window.dispatchKeyDown(
      KeyEvent(text: "d", key: keyD, keyCode: keyD.ord, modifiers: {kmCommand})
    )
    check listView.selectedIndex == 3

  test "list view type-select wraps and skips nonselectable rows":
    let
      window = newWindow("List type select policy", frame = initRect(0, 0, 220, 160))
      root = newView(frame = initRect(0, 0, 220, 160))
      listView = newListView(
        ["Alpha", "Beta", "Bravo", "Charlie"], frame = initRect(10, 10, 120, 62)
      )
      policy = newListPolicyDelegateSpy(nonselectableRows = [1])

    listView.rowHeight = 20.0
    listView.delegate = policy
    listView.selectedIndex = 3
    root.addSubview(listView)
    window.setContentView(root)

    check window.makeFirstResponder(listView)
    check window.dispatchKeyDown(KeyEvent(text: "b", key: keyB, keyCode: keyB.ord))
    check listView.selectedIndex == 2
