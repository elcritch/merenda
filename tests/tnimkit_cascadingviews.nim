import std/[unittest]

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

    view.selectItem(0, 0)
    check view.selectedPath == @["project"]
    check view.selectedItem.identifier == "project"
    check view.selectedItem.leaf == false
    check view.columnCount == 2
    check view.tableViewForColumn(1).rowCount == 2

    view.tableViewForColumn(0).selectedIndex = 1
    check view.selectedPath == @["notes"]
    check view.selectedItem.identifier == "notes"
    check view.columnCount == 1

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
