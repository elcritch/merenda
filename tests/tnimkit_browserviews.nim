import std/[unittest]

import sigils/core

import merenda/nimkit

type
  BrowserSourceSpy = ref object of Responder
    items: seq[BrowserItem]

  BrowserDelegateSpy = ref object of Responder
    denied: seq[string]
    selected: seq[string]
    activated: seq[string]
    heights: seq[float32]

  BrowserSignalSpy = ref object of Responder
    changing: int
    changed: int
    activated: int
    lastSender: DynamicAgent

proc containsValue(values: openArray[string], value: string): bool =
  for item in values:
    if item == value:
      return true
  false

protocol BrowserSourceSpyMethods of BrowserDataSource:
  method browserNumberOfChildren(
      source: BrowserSourceSpy, browser: Browser, parentIdentifier: string
  ): int =
    for item in source.items:
      if item.parentIdentifier == parentIdentifier:
        inc result

  method browserChildIdentifier(
      source: BrowserSourceSpy, browser: Browser, parentIdentifier: string, index: int
  ): string =
    var current = 0
    for item in source.items:
      if item.parentIdentifier == parentIdentifier:
        if current == index:
          return item.identifier
        inc current

  method browserItem(
      source: BrowserSourceSpy, browser: Browser, identifier: string
  ): BrowserItem =
    for item in source.items:
      if item.identifier == identifier:
        return item

protocol BrowserDelegateSpyMethods of BrowserDelegate:
  method shouldSelectBrowserItem(
      delegate: BrowserDelegateSpy,
      browser: Browser,
      column: int,
      row: int,
      identifier: string,
  ): bool =
    discard browser
    discard column
    discard row
    not delegate.denied.containsValue(identifier)

  method didSelectBrowserItem(
      delegate: BrowserDelegateSpy,
      browser: Browser,
      column: int,
      row: int,
      identifier: string,
  ) =
    discard browser
    delegate.selected.add $column & ":" & $row & ":" & identifier

  method didActivateBrowserItem(
      delegate: BrowserDelegateSpy,
      browser: Browser,
      column: int,
      row: int,
      identifier: string,
  ) =
    discard browser
    delegate.activated.add $column & ":" & $row & ":" & identifier

  method rowHeightForBrowserColumn(
      delegate: BrowserDelegateSpy, browser: Browser, column: int
  ): float32 =
    discard browser
    if column in 0 ..< delegate.heights.len:
      delegate.heights[column]
    else:
      18.0'f32

protocol BrowserSignalSpyEvents from BrowserSignalSpy:
  includes BrowserEvents

  proc selectionIsChanging(spy: BrowserSignalSpy, sender: DynamicAgent) {.slot.} =
    inc spy.changing
    spy.lastSender = sender

  proc selectionDidChange(spy: BrowserSignalSpy, sender: DynamicAgent) {.slot.} =
    inc spy.changed
    spy.lastSender = sender

  proc itemWasActivated(spy: BrowserSignalSpy, sender: DynamicAgent) {.slot.} =
    inc spy.activated
    spy.lastSender = sender

proc newBrowserSourceSpy(items: openArray[BrowserItem]): BrowserSourceSpy =
  result = BrowserSourceSpy(items: @items)
  initResponder(result)
  discard result.withProtocol(BrowserSourceSpyMethods)

proc newBrowserDelegateSpy(): BrowserDelegateSpy =
  result = BrowserDelegateSpy()
  initResponder(result)
  discard result.withProtocol(BrowserDelegateSpyMethods)

proc newBrowserSignalSpy(): BrowserSignalSpy =
  result = BrowserSignalSpy()
  initResponder(result)
  result = result.withProto()

suite "NimKit Browser":
  test "browser flattens path selections into Miller columns":
    let browser = newBrowser(frame = initRect(0, 0, 360, 160))
    browser.browserItems = [
      initBrowserItem("project", "Project"),
      initBrowserItem("notes", "Notes", leaf = true),
      initBrowserItem("src", "src", parentIdentifier = "project"),
      initBrowserItem("tests", "tests", parentIdentifier = "project", leaf = true),
      initBrowserItem("main", "main.nim", parentIdentifier = "src", leaf = true),
    ]

    check browser.columnCount == 1
    check browser.tableViewForColumn(0).rowCount == 2
    check browser.tableViewForColumn(0).tableCellText(
      0, browser.tableViewForColumn(0).columnAt(0)
    ) == "Project"

    browser.selectItem(0, 0)
    check browser.selectedPath == @["project"]
    check browser.selectedItem.identifier == "project"
    check browser.selectedItem.leaf == false
    check browser.columnCount == 2
    check browser.tableViewForColumn(1).rowCount == 2

    browser.tableViewForColumn(0).selectedIndex = 1
    check browser.selectedPath == @["notes"]
    check browser.selectedItem.identifier == "notes"
    check browser.columnCount == 1

    browser.selectItem(0, 0)
    check browser.selectedPath == @["project"]
    check browser.columnCount == 2

    browser.selectItem(1, 0)
    check browser.selectedPath == @["project", "src"]
    check browser.columnCount == 3
    check browser.tableViewForColumn(2).rowCount == 1

    browser.selectItem(2, 0)
    check browser.selectedPath == @["project", "src", "main"]
    check browser.selectedItem.title == "main.nim"
    check browser.selectedItem.leaf
    check browser.columnCount == 3

  test "browser data source delegate events and reload protocols":
    let
      browser = newBrowser(frame = initRect(0, 0, 360, 160))
      source = newBrowserSourceSpy(
        [
          initBrowserItem("root", "Root"),
          initBrowserItem("blocked", "Blocked", leaf = true),
          initBrowserItem("child", "Child", parentIdentifier = "root", leaf = true),
        ]
      )
      delegate = newBrowserDelegateSpy()
      signals = newBrowserSignalSpy()

    delegate.denied = @["blocked"]
    delegate.heights = @[22.0'f32, 24.0'f32]
    browser.dataSource = source
    browser.delegate = delegate
    signals.observeProtocol(browser, BrowserEvents)

    check browser.conformsTo(BrowserSelectionProtocol)
    check browser.conformsTo(BrowserReloadProtocol)
    check browser.childrenForParent("").len == 2
    check browser.tableViewForColumn(0).rowHeightForRow(0) == 22.0'f32

    browser.selectItem(0, 1)
    check browser.selectedPath == newSeq[string]()
    check delegate.selected.len == 0

    browser.selectItem(0, 0)
    check browser.selectedPath == @["root"]
    check delegate.selected == @["0:0:root"]
    check signals.changing == 1
    check signals.changed == 1
    check signals.lastSender == DynamicAgent(browser)

    browser.tableViewForColumn(1).activateItemAtIndex(0)
    check browser.selectedPath == @["root", "child"]
    check delegate.activated == @["1:0:child"]
    check signals.activated == 1

    source.items.setLen(2)
    browser.reloadData()
    check browser.selectedPath == @["root"]
    check browser.columnCount == 1

    browser.selectedPath = @["root", "missing"]
    check browser.selectedPath == @["root"]
