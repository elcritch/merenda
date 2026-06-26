import std/[unittest]

import sigils/core

import merenda/nimkit

type
  MillerColumnSourceSpy = ref object of Responder
    items: seq[MillerColumnItem]

  MillerColumnDelegateSpy = ref object of Responder
    denied: seq[string]
    selected: seq[string]
    activated: seq[string]
    heights: seq[float32]

  MillerColumnSignalSpy = ref object of Responder
    changing: int
    changed: int
    activated: int
    lastSender: DynamicAgent

proc containsValue(values: openArray[string], value: string): bool =
  for item in values:
    if item == value:
      return true
  false

protocol MillerColumnSourceSpyMethods of MillerColumnDataSource:
  method millerColumnNumberOfChildren(
      source: MillerColumnSourceSpy, view: MillerColumnView, parentIdentifier: string
  ): int =
    for item in source.items:
      if item.parentIdentifier == parentIdentifier:
        inc result

  method millerColumnChildIdentifier(
      source: MillerColumnSourceSpy,
      view: MillerColumnView,
      parentIdentifier: string,
      index: int,
  ): string =
    var current = 0
    for item in source.items:
      if item.parentIdentifier == parentIdentifier:
        if current == index:
          return item.identifier
        inc current

  method millerColumnItem(
      source: MillerColumnSourceSpy, view: MillerColumnView, identifier: string
  ): MillerColumnItem =
    for item in source.items:
      if item.identifier == identifier:
        return item

protocol MillerColumnDelegateSpyMethods of MillerColumnDelegate:
  method shouldSelectMillerColumnItem(
      delegate: MillerColumnDelegateSpy,
      view: MillerColumnView,
      column: int,
      row: int,
      identifier: string,
  ): bool =
    discard view
    discard column
    discard row
    not delegate.denied.containsValue(identifier)

  method didSelectMillerColumnItem(
      delegate: MillerColumnDelegateSpy,
      view: MillerColumnView,
      column: int,
      row: int,
      identifier: string,
  ) =
    discard view
    delegate.selected.add $column & ":" & $row & ":" & identifier

  method didActivateMillerColumnItem(
      delegate: MillerColumnDelegateSpy,
      view: MillerColumnView,
      column: int,
      row: int,
      identifier: string,
  ) =
    discard view
    delegate.activated.add $column & ":" & $row & ":" & identifier

  method rowHeightForMillerColumn(
      delegate: MillerColumnDelegateSpy, view: MillerColumnView, column: int
  ): float32 =
    discard view
    if column in 0 ..< delegate.heights.len:
      delegate.heights[column]
    else:
      18.0'f32

protocol MillerColumnSignalSpyEvents from MillerColumnSignalSpy:
  includes MillerColumnEvents

  proc selectionIsChanging(spy: MillerColumnSignalSpy, sender: DynamicAgent) {.slot.} =
    inc spy.changing
    spy.lastSender = sender

  proc selectionDidChange(spy: MillerColumnSignalSpy, sender: DynamicAgent) {.slot.} =
    inc spy.changed
    spy.lastSender = sender

  proc itemWasActivated(spy: MillerColumnSignalSpy, sender: DynamicAgent) {.slot.} =
    inc spy.activated
    spy.lastSender = sender

proc newMillerColumnSourceSpy(
    items: openArray[MillerColumnItem]
): MillerColumnSourceSpy =
  result = MillerColumnSourceSpy(items: @items)
  initResponder(result)
  discard result.withProtocol(MillerColumnSourceSpyMethods)

proc newMillerColumnDelegateSpy(): MillerColumnDelegateSpy =
  result = MillerColumnDelegateSpy()
  initResponder(result)
  discard result.withProtocol(MillerColumnDelegateSpyMethods)

proc newMillerColumnSignalSpy(): MillerColumnSignalSpy =
  result = MillerColumnSignalSpy()
  initResponder(result)
  result = result.withProto()

suite "NimKit MillerColumnView":
  test "view flattens path selections into Miller columns":
    let view = newMillerColumnView(frame = initRect(0, 0, 360, 160))
    view.millerColumnItems = [
      initMillerColumnItem("project", "Project"),
      initMillerColumnItem("notes", "Notes", leaf = true),
      initMillerColumnItem("src", "src", parentIdentifier = "project"),
      initMillerColumnItem("tests", "tests", parentIdentifier = "project", leaf = true),
      initMillerColumnItem("main", "main.nim", parentIdentifier = "src", leaf = true),
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
      view = newMillerColumnView(frame = initRect(0, 0, 360, 160))
      source = newMillerColumnSourceSpy(
        [
          initMillerColumnItem("root", "Root"),
          initMillerColumnItem("blocked", "Blocked", leaf = true),
          initMillerColumnItem("child", "Child", parentIdentifier = "root", leaf = true),
        ]
      )
      delegate = newMillerColumnDelegateSpy()
      signals = newMillerColumnSignalSpy()

    delegate.denied = @["blocked"]
    delegate.heights = @[22.0'f32, 24.0'f32]
    view.dataSource = source
    view.delegate = delegate
    signals.observeProtocol(view, MillerColumnEvents)

    check view.conformsTo(MillerColumnSelectionProtocol)
    check view.conformsTo(MillerColumnReloadProtocol)
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
