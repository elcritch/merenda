import std/[tables, unicode, unittest]

from figdraw/fignodes import Fig, RenderList, NfClipContent, nkRectangle, nkText
import sigils/core

import merenda/nimkit

type
  CascadingSourceSpy = ref object of Responder
    items: seq[CascadingItem]

  CascadingDelegateSpy = ref object of Responder
    denied: seq[string]
    selected: seq[string]
    activated: seq[string]
    heights: seq[float32]

  CascadingSignalSpy = ref object of Responder
    changing: int
    changed: int
    activated: int
    lastSender: DynamicAgent

proc containsValue(values: openArray[string], value: string): bool =
  for item in values:
    if item == value:
      return true
  false

proc pressKey(window: Window, key: Key, modifiers: set[KeyModifier] = {}): bool =
  window.dispatchKeyDown(KeyEvent(key: key, keyCode: key.ord, modifiers: modifiers))

func nearlyEqual(a, b: float32): bool =
  abs(a - b) <= 0.01'f32

func screenBoxClose(node: Fig, rect: Rect): bool =
  abs(node.screenBox.x.float32 - rect.origin.x) <= 0.01'f32 and
    abs(node.screenBox.y.float32 - rect.origin.y) <= 0.01'f32 and
    abs(node.screenBox.w.float32 - rect.size.width) <= 0.01'f32 and
    abs(node.screenBox.h.float32 - rect.size.height) <= 0.01'f32

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add(rune)

proc clippedRectX(list: RenderList, rect: Rect): float32 =
  result = -1.0'f32
  for node in list.nodes:
    if node.kind == nkRectangle and NfClipContent in node.flags and
        node.screenBoxClose(rect):
      return node.screenBox.x.float32

proc textNodeX(list: RenderList, text: string): float32 =
  result = -1.0'f32
  for node in list.nodes:
    if node.kind == nkText and node.renderedText() == text:
      return node.screenBox.x.float32

protocol CascadingSourceSpyMethods of CascadingDataSource:
  method cascadingNumberOfChildren(
      source: CascadingSourceSpy, view: CascadingView, parentIdentifier: string
  ): int =
    for item in source.items:
      if item.parentIdentifier == parentIdentifier:
        inc result

  method cascadingChildIdentifier(
      source: CascadingSourceSpy,
      view: CascadingView,
      parentIdentifier: string,
      index: int,
  ): string =
    var current = 0
    for item in source.items:
      if item.parentIdentifier == parentIdentifier:
        if current == index:
          return item.identifier
        inc current

  method cascadingItem(
      source: CascadingSourceSpy, view: CascadingView, identifier: string
  ): CascadingItem =
    for item in source.items:
      if item.identifier == identifier:
        return item

protocol CascadingDelegateSpyMethods of CascadingDelegate:
  method shouldSelectCascadingItem(
      delegate: CascadingDelegateSpy,
      view: CascadingView,
      column: int,
      row: int,
      identifier: string,
  ): bool =
    discard view
    discard column
    discard row
    not delegate.denied.containsValue(identifier)

  method didSelectCascadingItem(
      delegate: CascadingDelegateSpy,
      view: CascadingView,
      column: int,
      row: int,
      identifier: string,
  ) =
    discard view
    delegate.selected.add $column & ":" & $row & ":" & identifier

  method didActivateCascadingItem(
      delegate: CascadingDelegateSpy,
      view: CascadingView,
      column: int,
      row: int,
      identifier: string,
  ) =
    discard view
    delegate.activated.add $column & ":" & $row & ":" & identifier

  method rowHeightForCascadingColumn(
      delegate: CascadingDelegateSpy, view: CascadingView, column: int
  ): float32 =
    discard view
    if column in 0 ..< delegate.heights.len:
      delegate.heights[column]
    else:
      18.0'f32

protocol CascadingSignalSpyEvents from CascadingSignalSpy:
  includes CascadingEvents

  proc selectionIsChanging(spy: CascadingSignalSpy, sender: DynamicAgent) {.slot.} =
    inc spy.changing
    spy.lastSender = sender

  proc selectionDidChange(spy: CascadingSignalSpy, sender: DynamicAgent) {.slot.} =
    inc spy.changed
    spy.lastSender = sender

  proc itemWasActivated(spy: CascadingSignalSpy, sender: DynamicAgent) {.slot.} =
    inc spy.activated
    spy.lastSender = sender

proc newCascadingSourceSpy(items: openArray[CascadingItem]): CascadingSourceSpy =
  result = CascadingSourceSpy(items: @items)
  initResponder(result)
  discard result.withProtocol(CascadingSourceSpyMethods)

proc newCascadingDelegateSpy(): CascadingDelegateSpy =
  result = CascadingDelegateSpy()
  initResponder(result)
  discard result.withProtocol(CascadingDelegateSpyMethods)

proc newCascadingSignalSpy(): CascadingSignalSpy =
  result = CascadingSignalSpy()
  initResponder(result)
  result = result.withProto()

suite "NimKit CascadingView":
  test "view flattens path selections into cascading columns":
    let view = newCascadingView(frame = initRect(0, 0, 360, 160))
    view.cascadingItems = [
      initCascadingItem("project", "Project"),
      initCascadingItem("notes", "Notes", leaf = true),
      initCascadingItem("src", "src", parentIdentifier = "project"),
      initCascadingItem("tests", "tests", parentIdentifier = "project", leaf = true),
      initCascadingItem("main", "main.nim", parentIdentifier = "src", leaf = true),
    ]

    check view.columnCount == 1
    check view.tableViewForColumn(0).rowCount == 2
    check view.tableViewForColumn(0).tableCellText(
      0, view.tableViewForColumn(0).columnAt(0)
    ) == "Project"
    check view.tableViewForColumn(0).scrollView().contentOffset().x == 0.0'f32
    check not view.tableViewForColumn(0).shouldBeginEditingCell(
      0, view.tableViewForColumn(0).columnAt(0)
    )
    check not view.tableViewForColumn(0).beginEditingCell(
      0, view.tableViewForColumn(0).columnAt(0)
    )
    check not view.tableViewForColumn(0).editingState.active

    view.selectItem(0, 0)
    check view.selectedPath == @["project"]
    check view.selectedItem.identifier == "project"
    check view.selectedItem.leaf == false
    check view.columnCount == 2
    check view.tableViewForColumn(1).rowCount == 2
    check view.tableViewForColumn(0).scrollView().contentOffset().x == 0.0'f32

    view.tableViewForColumn(0).selectedIndex = 1
    check view.selectedPath == @["notes"]
    check view.selectedItem.identifier == "notes"
    check view.columnCount == 1
    check view.tableViewForColumn(0).scrollView().contentOffset().x == 0.0'f32

    view.selectItem(0, 0)
    check view.selectedPath == @["project"]
    check view.columnCount == 2

    view.selectItem(1, 0)
    check view.selectedPath == @["project", "src"]
    check view.columnCount == 3
    check view.tableViewForColumn(2).rowCount == 1

    view.selectItem(2, 0)
    check view.selectedPath == @["project", "src", "main"]
    check view.selectedItem.title == "main.nim"
    check view.selectedItem.leaf
    check view.columnCount == 3

  test "view data source delegate events and reload protocols":
    let
      view = newCascadingView(frame = initRect(0, 0, 360, 160))
      source = newCascadingSourceSpy(
        [
          initCascadingItem("root", "Root"),
          initCascadingItem("blocked", "Blocked", leaf = true),
          initCascadingItem("child", "Child", parentIdentifier = "root", leaf = true),
        ]
      )
      delegate = newCascadingDelegateSpy()
      signals = newCascadingSignalSpy()

    delegate.denied = @["blocked"]
    delegate.heights = @[22.0'f32, 24.0'f32]
    view.dataSource = source
    view.delegate = delegate
    signals.observeProtocol(view, CascadingEvents)

    check view.conformsTo(CascadingSelectionProtocol)
    check view.conformsTo(CascadingReloadProtocol)
    check view.childrenForParent("").len == 2
    check view.tableViewForColumn(0).rowHeightForRow(0) == 22.0'f32

    view.selectItem(0, 1)
    check view.selectedPath == newSeq[string]()
    check delegate.selected.len == 0

    view.selectItem(0, 0)
    check view.selectedPath == @["root"]
    check delegate.selected == @["0:0:root"]
    check signals.changing == 1
    check signals.changed == 1
    check signals.lastSender == DynamicAgent(view)

    view.tableViewForColumn(1).activateItemAtIndex(0)
    check view.selectedPath == @["root", "child"]
    check delegate.activated == @["1:0:child"]
    check signals.activated == 1

    source.items.setLen(2)
    view.reloadData()
    check view.selectedPath == @["root"]
    check view.columnCount == 1

    view.selectedPath = @["root", "missing"]
    check view.selectedPath == @["root"]

  test "columns overflow into horizontal scroll content":
    let
      root = newView(frame = initRect(0, 0, 380, 120))
      view = newCascadingView(frame = initRect(0, 0, 380, 120))

    view.columnWidth = 170.0
    view.minColumnWidth = 120.0
    view.cascadingItems = [
      initCascadingItem("root", "Root"),
      initCascadingItem("child", "Child", parentIdentifier = "root"),
      initCascadingItem(
        "grandchild", "Grandchild", parentIdentifier = "child", leaf = true
      ),
    ]
    root.addSubview(view)
    view.selectItem(0, 0)
    view.selectItem(1, 0)
    discard buildRenders(root)

    check view.columnCount == 3
    check view.scrollView().hasHorizontalScroller
    check view.scrollView().documentView().frame.size.width > view.bounds().size.width
    check view.scrollView().maximumContentOffset().x > 0.0'f32
    check view.tableViewForColumn(0).frame.size.width == view.columnWidth()
    check view.tableViewForColumn(2).frame().maxX > view.bounds().maxX

    for columnIndex in 0 ..< view.columnCount:
      let
        tableView = view.tableViewForColumn(columnIndex)
        column = tableView.columnAt(0)
        viewportWidth = tableView.scrollView().viewportSize().width

      check column.width() == viewportWidth
      check tableView.contentView().frame.size.width == viewportWidth

  test "horizontal scroll moves column chrome and row text together":
    let
      root = newView(frame = initRect(0, 0, 300, 120))
      view = newCascadingView(frame = initRect(0, 0, 300, 120))

    view.columnWidth = 170.0
    view.cascadingItems = [
      initCascadingItem("root", "Root"),
      initCascadingItem("child", "Child", parentIdentifier = "root"),
      initCascadingItem(
        "grandchild", "Grandchild", parentIdentifier = "child", leaf = true
      ),
    ]
    root.addSubview(view)
    view.selectItem(0, 0)
    view.selectItem(1, 0)
    discard buildRenders(root)

    proc renderPositions(offset: float32): tuple[columnX, textX: float32] =
      view.scrollView().contentOffset = initPoint(offset, 0.0)
      let renders = buildRenders(root)
      let
        list = renders.layers[DefaultDrawLevel]
        tableView = view.tableViewForColumn(0)
        columnRect = tableView.rectToWindow(tableView.bounds())
      result.columnX = list.clippedRectX(columnRect)
      result.textX = list.textNodeX("Root")

    let
      first = renderPositions(40.0)
      second = renderPositions(70.0)

    check first.columnX >= -1000.0'f32
    check first.textX >= -1000.0'f32
    check second.columnX >= -1000.0'f32
    check second.textX >= -1000.0'f32
    check (second.columnX - first.columnX).nearlyEqual(-30.0)
    check (second.textX - first.textX).nearlyEqual(-30.0)
    check (first.textX - first.columnX).nearlyEqual(second.textX - second.columnX)

  test "left and right arrows move focus between visible columns":
    let
      window = newWindow("Cascading keyboard", frame = initRect(0, 0, 360, 160))
      root = newView(frame = initRect(0, 0, 360, 160))
      view = newCascadingView(frame = initRect(0, 0, 360, 160))

    view.cascadingItems = [
      initCascadingItem("project", "Project"),
      initCascadingItem("src", "src", parentIdentifier = "project"),
      initCascadingItem("main", "main.nim", parentIdentifier = "src", leaf = true),
    ]
    root.addSubview(view)
    window.setContentView(root)

    view.selectItem(0, 0)
    check view.columnCount == 2
    let
      firstColumn = view.tableViewForColumn(0)
      secondColumn = view.tableViewForColumn(1)

    check window.makeFirstResponder(firstColumn)
    check window.firstResponder == firstColumn
    check window.pressKey(keyArrowRight)
    check window.firstResponder == secondColumn
    check secondColumn.selectedIndex == 0
    check view.selectedPath == @["project", "src"]
    check view.columnCount == 3
    check view.scrollView().contentOffset().x > 0.0'f32
    check window.pressKey(keyArrowLeft)
    check window.firstResponder == firstColumn
    check secondColumn.selectedIndex == -1
    check view.selectedPath == @["project"]
    check view.columnCount == 2
    check view.scrollView().contentOffset().x == 0.0'f32
    check not window.pressKey(keyArrowLeft)
    check window.firstResponder == firstColumn
