import std/[unicode, unittest]

import sigils/core

import figdraw/fignodes

import merenda/nimkit
import merenda/nimkit/foundation/types as nimkitTypes

type
  DocumentTabDelegateSpy = ref object of Responder
    denySelect: string
    denyClose: string
    denyMoveTo: int
    shouldSelectCount: int
    didSelectCount: int
    shouldCloseCount: int
    didCloseCount: int
    shouldMoveCount: int
    didMoveCount: int
    lastItem: DocumentTabItem
    lastIndex: int
    lastFromIndex: int
    lastToIndex: int

  DocumentTabSignalSpy = ref object of Responder
    changingCount: int
    changedCount: int
    willCloseCount: int
    didCloseCount: int
    willMoveCount: int
    didMoveCount: int
    scrollCount: int
    lastItem: DocumentTabItem
    lastIndex: int
    lastFromIndex: int
    lastToIndex: int
    lastOffset: float32

protocol DocumentTabDelegateSpyMethods of DocumentTabsDelegate:
  method shouldSelectDocumentTab(
      spy: DocumentTabDelegateSpy, tabs: DocumentTabs, item: DocumentTabItem
  ): bool =
    discard tabs
    inc spy.shouldSelectCount
    item.identifier != spy.denySelect

  method didSelectDocumentTab(
      spy: DocumentTabDelegateSpy, tabs: DocumentTabs, item: DocumentTabItem
  ) =
    discard tabs
    inc spy.didSelectCount
    spy.lastItem = item

  method shouldCloseDocumentTab(
      spy: DocumentTabDelegateSpy, tabs: DocumentTabs, item: DocumentTabItem, index: int
  ): bool =
    discard tabs
    discard index
    inc spy.shouldCloseCount
    item.identifier != spy.denyClose

  method didCloseDocumentTab(
      spy: DocumentTabDelegateSpy, tabs: DocumentTabs, item: DocumentTabItem, index: int
  ) =
    discard tabs
    inc spy.didCloseCount
    spy.lastItem = item
    spy.lastIndex = index

  method shouldMoveDocumentTab(
      spy: DocumentTabDelegateSpy,
      tabs: DocumentTabs,
      item: DocumentTabItem,
      fromIndex: int,
      toIndex: int,
  ): bool =
    discard tabs
    discard item
    discard fromIndex
    inc spy.shouldMoveCount
    toIndex != spy.denyMoveTo

  method didMoveDocumentTab(
      spy: DocumentTabDelegateSpy,
      tabs: DocumentTabs,
      item: DocumentTabItem,
      fromIndex: int,
      toIndex: int,
  ) =
    discard tabs
    inc spy.didMoveCount
    spy.lastItem = item
    spy.lastFromIndex = fromIndex
    spy.lastToIndex = toIndex

protocol DocumentTabSignalSpyEvents from DocumentTabSignalSpy:
  includes DocumentTabsEvents

  proc documentTabSelectionIsChanging(
      spy: DocumentTabSignalSpy, sender: DynamicAgent
  ) {.slot.} =
    discard sender
    inc spy.changingCount

  proc documentTabSelectionDidChange(
      spy: DocumentTabSignalSpy, sender: DynamicAgent
  ) {.slot.} =
    discard sender
    inc spy.changedCount

  proc documentTabWillClose(
      spy: DocumentTabSignalSpy, item: DocumentTabItem, index: int
  ) {.slot.} =
    inc spy.willCloseCount
    spy.lastItem = item
    spy.lastIndex = index

  proc documentTabDidClose(
      spy: DocumentTabSignalSpy, item: DocumentTabItem, index: int
  ) {.slot.} =
    inc spy.didCloseCount
    spy.lastItem = item
    spy.lastIndex = index

  proc documentTabWillMove(
      spy: DocumentTabSignalSpy, item: DocumentTabItem, fromIndex: int, toIndex: int
  ) {.slot.} =
    inc spy.willMoveCount
    spy.lastItem = item
    spy.lastFromIndex = fromIndex
    spy.lastToIndex = toIndex

  proc documentTabDidMove(
      spy: DocumentTabSignalSpy, item: DocumentTabItem, fromIndex: int, toIndex: int
  ) {.slot.} =
    inc spy.didMoveCount
    spy.lastItem = item
    spy.lastFromIndex = fromIndex
    spy.lastToIndex = toIndex

  proc documentTabsDidScroll(spy: DocumentTabSignalSpy, offset: float32) {.slot.} =
    inc spy.scrollCount
    spy.lastOffset = offset

proc newDelegateSpy(): DocumentTabDelegateSpy =
  result = DocumentTabDelegateSpy(denyMoveTo: -1)
  initResponder(result)
  discard result.withProtocol(DocumentTabDelegateSpyMethods)

proc newSignalSpy(): DocumentTabSignalSpy =
  result = DocumentTabSignalSpy()
  initResponder(result)
  result = result.withProto()

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add rune

func center(rect: nimkitTypes.Rect): nimkitTypes.Point =
  initPoint(
    rect.origin.x + rect.size.width / 2.0'f32,
    rect.origin.y + rect.size.height / 2.0'f32,
  )

suite "nimkit document tabs":
  test "document tabs expose dynamic items and selectable styles":
    let
      tabs = newDocumentTabs(frame = initRect(0, 0, 360, 34))
      item = newDocumentTabItem(
        "A very long document title that needs clipping", "long", style = dtsRounded
      )

    discard tabs.addDocumentTabItem(item)
    let roundedWidth = tabs.documentTabRect(0).size.width

    item.style = dtsCompact
    item.modified = true
    item.title = "Compact changed title"
    tabs.reloadDocumentTabs()

    check tabs.len == 1
    check tabs[0] == item
    check tabs.selectedDocumentTabItem == item
    check tabs.documentTabRect(0).size.width < roundedWidth
    check item.modified

    discard tabs.addDocumentTabItem(
      newDocumentTabItem("Underline", "underline", style = dtsUnderline)
    )
    check tabs.contentWidth() > tabs.documentTabRect(0).size.width

  test "document tabs can move an item all the way to the front":
    let
      tabs = newDocumentTabs(frame = initRect(0, 0, 420, 34))
      first = newDocumentTabItem("First", "first")
      second = newDocumentTabItem("Second", "second")
      third = newDocumentTabItem("Third", "third")

    discard tabs.addDocumentTabItem(first)
    discard tabs.addDocumentTabItem(second)
    discard tabs.addDocumentTabItem(third)
    discard tabs.selectDocumentTab(third)

    check tabs.moveDocumentTabItem(2, 0)
    check tabs[0] == third
    check tabs[1] == first
    check tabs.selectedDocumentTabItem == third
    check tabs.selectedIndex() == 0

  test "delegates can veto selection closing and moving while signals fire":
    let
      tabs = newDocumentTabs(frame = initRect(0, 0, 420, 34))
      first = newDocumentTabItem("First", "first")
      second = newDocumentTabItem("Second", "second")
      third = newDocumentTabItem("Third", "third")
      delegate = newDelegateSpy()
      signals = newSignalSpy()

    tabs.delegate = delegate
    signals.observeProtocol(tabs, DocumentTabsEvents)
    discard tabs.addDocumentTabItem(first)
    discard tabs.addDocumentTabItem(second)
    discard tabs.addDocumentTabItem(third)

    delegate.denySelect = "second"
    check not tabs.selectDocumentTab(second)
    check tabs.selectedDocumentTabItem == first
    check delegate.shouldSelectCount == 1
    check signals.changedCount == 0

    delegate.denySelect = ""
    check tabs.selectDocumentTab(second)
    check tabs.selectedDocumentTabItem == second
    check delegate.didSelectCount == 1
    check signals.changingCount == 1
    check signals.changedCount == 1

    delegate.denyMoveTo = 0
    check not tabs.moveDocumentTabItem(1, 0)
    check delegate.shouldMoveCount == 1
    check signals.didMoveCount == 0

    delegate.denyMoveTo = -1
    check tabs.moveDocumentTabItem(1, 2)
    check tabs[2] == second
    check delegate.didMoveCount == 1
    check signals.willMoveCount == 1
    check signals.didMoveCount == 1
    check signals.lastFromIndex == 1
    check signals.lastToIndex == 2

    delegate.denyClose = "second"
    check not tabs.closeDocumentTab(second)
    check tabs.len == 3
    check signals.didCloseCount == 0

    delegate.denyClose = ""
    check tabs.closeDocumentTab(second)
    check tabs.len == 2
    check delegate.didCloseCount == 1
    check signals.willCloseCount == 1
    check signals.didCloseCount == 1
    check signals.lastItem == second

  test "overflow tabs scroll with buttons and mouse wheel without visible scrollbar":
    let
      window = newWindow("Document tabs overflow", frame = initRect(0, 0, 260, 80))
      root = newView(frame = initRect(0, 0, 260, 80))
      tabs = newDocumentTabs(frame = initRect(10, 10, 220, 34))
      signals = newSignalSpy()

    for index in 0 .. 7:
      discard tabs.addDocumentTabItem(
        newDocumentTabItem("Document " & $index, "doc-" & $index)
      )
    signals.observeProtocol(tabs, DocumentTabsEvents)
    root.addSubview(tabs)
    window.setContentView(root)

    check tabs.hasOverflow()
    check not tabs.showsHorizontalScroller()
    check not tabs.scrollButtonRect(dtsbNext).isEmpty

    let nextPoint = tabs.pointToWindow(tabs.scrollButtonRect(dtsbNext).center())
    check window.clickAt(nextPoint)
    check tabs.scrollOffset() > 0.0'f32
    check signals.scrollCount == 1

    let beforeWheel = tabs.scrollOffset()
    check window.scrollWheelAt(tabs.pointToWindow(initPoint(100, 16)), deltaX = 3.0)
    check tabs.scrollOffset() > beforeWheel
    check signals.lastOffset == tabs.scrollOffset()

    tabs.scrollDocumentTabsToEnd()
    let maxOffset = tabs.maximumScrollOffset()
    check tabs.scrollOffset() == maxOffset

    let previousPoint = tabs.pointToWindow(tabs.scrollButtonRect(dtsbPrevious).center())
    check window.clickAt(previousPoint)
    check tabs.scrollOffset() < maxOffset

  test "document tab rendering includes visible labels and clipped overflow":
    let tabs = newDocumentTabs(frame = initRect(0, 0, 210, 34))
    discard
      tabs.addDocumentTabItem(newDocumentTabItem("Plan", "plan", style = dtsRounded))
    discard
      tabs.addDocumentTabItem(newDocumentTabItem("Budget", "budget", style = dtsPill))
    discard tabs.addDocumentTabItem(
      newDocumentTabItem("Long Research Notes", "notes", style = dtsUnderline)
    )

    let renders = buildRenders(tabs)
    var
      planFound = false
      budgetFound = false
      nextFound = false
      closeSymbolFound = false
      closeTextFound = false

    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkText:
        let text = node.renderedText()
        if text == "Plan":
          planFound = true
        elif text == "Budget":
          budgetFound = true
        elif text == ">":
          nextFound = true
        elif text == "×":
          closeSymbolFound = true
        elif text == "x":
          closeTextFound = true

    check planFound
    check budgetFound
    check nextFound
    check closeSymbolFound
    check not closeTextFound
