import std/[unicode, unittest]

import sigils/core

import figdraw

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

  DocumentTabModelDataSourceSpy = ref object of Responder
    models: seq[DocumentTabModel]

  DocumentTabChromeSpy = ref object of Chrome

const DocumentTabChromeName = "document-tabs-test-chrome"

let
  DocumentTabChromeFill = fill(color(0.18, 0.62, 0.92, 1.0))
  DocumentTabBarChromeFill = fill(color(0.12, 0.16, 0.24, 1.0))
  DocumentTabButtonChromeFill = fill(color(0.72, 0.20, 0.50, 1.0))
  DocumentTabButtonThemeFill = fill(color(0.22, 0.48, 0.74, 1.0))
  SpecialDocumentTabFill = fill(color(0.92, 0.80, 0.22, 1.0))

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

protocol DocumentTabModelDataSourceSpyMethods of DocumentTabsDataSource:
  method documentTabCount(spy: DocumentTabModelDataSourceSpy, tabs: DocumentTabs): int =
    discard tabs
    spy.models.len

  method documentTabModelAtIndex(
      spy: DocumentTabModelDataSourceSpy, tabs: DocumentTabs, index: int
  ): DocumentTabModel =
    discard tabs
    spy.models[index]

  method indexOfDocumentTabModelIdentifier(
      spy: DocumentTabModelDataSourceSpy, tabs: DocumentTabs, identifier: string
  ): int =
    discard tabs
    var visibleIndex = 0
    for model in spy.models:
      if not model.hidden:
        if model.identifier == identifier:
          return visibleIndex
        inc visibleIndex
    -1

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

protocol DocumentTabChromeSpyMethods of ChromeProtocol:
  method chromeFillFor(chrome: DocumentTabChromeSpy, context: ChromeContext): Fill =
    discard chrome
    case context.role
    of crDocumentTab:
      if ssSelected in context.states: DocumentTabChromeFill else: context.baseFill
    of crDocumentTabBar:
      DocumentTabBarChromeFill
    of crDocumentTabButton:
      DocumentTabButtonChromeFill
    else:
      context.baseFill

proc newDelegateSpy(): DocumentTabDelegateSpy =
  result = DocumentTabDelegateSpy(denyMoveTo: -1)
  initResponder(result)
  discard result.withProtocol(DocumentTabDelegateSpyMethods)

proc newSignalSpy(): DocumentTabSignalSpy =
  result = DocumentTabSignalSpy()
  initResponder(result)
  result = result.withProto()

proc newModelDataSourceSpy(
    models: openArray[DocumentTabModel]
): DocumentTabModelDataSourceSpy =
  result = DocumentTabModelDataSourceSpy(models: @models)
  initResponder(result)
  discard result.withProtocol(DocumentTabModelDataSourceSpyMethods)

proc newDocumentTabChromeSpy(): Chrome =
  let chrome = DocumentTabChromeSpy()
  discard chrome.withProtocol(DocumentTabChromeSpyMethods)
  Chrome(chrome)

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add rune

proc renderedRect(node: Fig): nimkitTypes.Rect =
  nimkitTypes.rect(
    node.screenBox.x.float32, node.screenBox.y.float32, node.screenBox.w.float32,
    node.screenBox.h.float32,
  )

proc rectsClose(left, right: nimkitTypes.Rect): bool =
  abs(left.origin.x - right.origin.x) <= 0.01'f32 and
    abs(left.origin.y - right.origin.y) <= 0.01'f32 and
    abs(left.size.width - right.size.width) <= 0.01'f32 and
    abs(left.size.height - right.size.height) <= 0.01'f32

func center(rect: nimkitTypes.Rect): nimkitTypes.Point =
  initPoint(
    rect.origin.x + rect.size.width / 2.0'f32,
    rect.origin.y + rect.size.height / 2.0'f32,
  )

suite "nimkit document tabs":
  test "document tab models back metadata identity selection and ordering":
    let
      tabs = newDocumentTabs(frame = rect(0, 0, 420, 34))
      represented = newResponder()
      accent = color(0.80, 0.12, 0.36, 1.0)

    tabs.documentTabModels = [
      initDocumentTabModel(
        "doc-a",
        "Alpha",
        objectValue = toObj("alpha"),
        modified = true,
        style = dtsUnderline,
        accentColor = accent,
        tooltip = "Alpha document",
        representedObject = DynamicAgent(represented),
      ),
      initDocumentTabModel("hidden", "Hidden", hidden = true),
      initDocumentTabModel("doc-b", "Beta", enabled = false, closeable = false),
    ]

    check tabs.len == 2
    check tabs.documentTabModels.len == 3
    check tabs.documentTabIdentifiers() == @["doc-a", "doc-b"]
    check tabs[0.Natural].identifier == "doc-a"
    check tabs[0.Natural].objectValue.requireString() == "alpha"
    check tabs[0.Natural].modified
    check tabs[0.Natural].style == dtsUnderline
    check tabs[0.Natural].accentColor == accent
    check tabs[0.Natural].toolTip == "Alpha document"
    check tabs[0.Natural].representedObject == DynamicAgent(represented)
    check tabs.documentTabItemWithIdentifier("hidden").isNil
    check tabs.indexOfDocumentTabIdentifier("doc-b") == 1
    check tabs.selectedDocumentTabIdentifier == "doc-a"
    check not tabs.selectDocumentTabWithIdentifier("doc-b")

    discard tabs.addDocumentTabItem(initDocumentTabModel("doc-c", "Gamma"))
    check tabs.selectDocumentTabWithIdentifier("doc-c")
    let state = tabs.captureState()
    check state.selectedIdentifier == "doc-c"
    check state.orderedIdentifiers == @["doc-a", "doc-b", "doc-c"]

    check tabs.moveDocumentTabItem(2, 0)
    check tabs.documentTabIdentifiers() == @["doc-c", "doc-a", "doc-b"]
    check tabs.documentTabModels[0].identifier == "doc-c"

    tabs.restoreState(state)
    check tabs.documentTabIdentifiers() == @["doc-a", "doc-b", "doc-c"]
    check tabs.selectedDocumentTabIdentifier == "doc-c"

    check tabs.removeDocumentTabWithIdentifier("doc-a")
    check tabs.documentTabItemWithIdentifier("doc-a").isNil
    for model in tabs.documentTabModels:
      check model.identifier != "doc-a"

  test "document tab data sources reload and preserve selected identifiers":
    let
      tabs = newDocumentTabs(frame = rect(0, 0, 420, 34))
      source = newModelDataSourceSpy(
        [
          initDocumentTabModel("draft", "Draft"),
          initDocumentTabModel("published", "Published"),
          initDocumentTabModel("archived", "Archived", hidden = true),
        ]
      )

    tabs.dataSource = source
    check tabs.len == 2
    check tabs.documentTabIdentifiers() == @["draft", "published"]
    check tabs.indexOfDocumentTabIdentifier("published") == 1
    check tabs.selectDocumentTabWithIdentifier("published")

    source.models =
      @[
        initDocumentTabModel("published", "Published Updated"),
        initDocumentTabModel("draft", "Draft"),
        initDocumentTabModel("archived", "Archived", hidden = true),
      ]
    tabs.reloadData()

    check tabs.len == 2
    check tabs[0.Natural].title == "Published Updated"
    check tabs.selectedDocumentTabIdentifier == "published"
    check tabs.selectedIndex == 0

  test "document tabs expose dynamic items and selectable styles":
    let
      tabs = newDocumentTabs(frame = rect(0, 0, 360, 34))
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
      tabs = newDocumentTabs(frame = rect(0, 0, 420, 34))
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

  test "document tab selection accent stays inside the tab":
    let
      tabs = newDocumentTabs(frame = rect(0, 0, 360, 34))
      selectedAccent = color(0.84, 0.12, 0.28, 1.0)
      modifiedAccent = color(0.12, 0.68, 0.34, 1.0)
      selected = newDocumentTabItem("Selected", "selected")
      modified = newDocumentTabItem("Modified", "modified")

    selected.accentColor = selectedAccent
    modified.accentColor = modifiedAccent
    modified.modified = true
    discard tabs.addDocumentTabItem(selected)
    discard tabs.addDocumentTabItem(modified)

    let
      renders = buildRenders(tabs)
      selectedRect = tabs.documentTabRect(0)
      selectedAccentFill =
        fill(color(selectedAccent.r, selectedAccent.g, selectedAccent.b, 0.72))
    var
      selectedAccentRect: nimkitTypes.Rect
      modifiedDotFound = false
      modifiedAccentRectFound = false

    for node in renders[DefaultDrawLevel].nodes:
      if node.fill == selectedAccentFill and node.kind == nkRectangle:
        selectedAccentRect = node.renderedRect()
      elif node.fill == fill(modifiedAccent):
        if node.kind == nkRectangle:
          modifiedAccentRectFound = true
        elif node.kind == nkDrawable:
          for op in node.drawOps:
            if op.kind == dkCircle:
              modifiedDotFound = true

    check not selectedAccentRect.isEmpty
    check selectedAccentRect.minX > selectedRect.minX
    check selectedAccentRect.minY > selectedRect.minY
    check selectedAccentRect.maxX < selectedRect.maxX
    check selectedAccentRect.maxY < selectedRect.maxY
    check selectedAccentRect.size.width > selectedAccentRect.size.height
    check selectedAccentRect.size.width < selectedRect.size.width
    check selectedAccentRect.size.height == 2.0'f32
    check modifiedDotFound
    check not modifiedAccentRectFound

    check tabs.selectDocumentTab(modified)
    let
      modifiedRenders = buildRenders(tabs)
      softenedModifiedAccent =
        fill(color(modifiedAccent.r, modifiedAccent.g, modifiedAccent.b, 0.52))
    var softenedModifiedAccentFound = false
    for node in modifiedRenders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill == softenedModifiedAccent:
        softenedModifiedAccentFound = true
        break
    check softenedModifiedAccentFound

  test "document tab default accents resolve from the theme palette":
    let
      tabs = newDocumentTabs(frame = rect(0, 0, 360, 34))
      selected = newDocumentTabItem("Selected", "selected")
      modified = newDocumentTabItem("Modified", "modified")
      themeAccent = color(0.90, 0.28, 0.54, 0.94)

    modified.modified = true
    discard tabs.addDocumentTabItem(selected)
    discard tabs.addDocumentTabItem(modified)

    var theme = initTheme()
    theme["accent"] = themeAccent
    let
      renders = buildRenders(tabs, initAppearance(theme))
      selectedAccentFill = fill(
        color(themeAccent.r, themeAccent.g, themeAccent.b, themeAccent.a * 0.72'f32)
      )
      modifiedDotFill = fill(themeAccent)
    var
      selectedAccentFound = false
      modifiedDotFound = false

    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill == selectedAccentFill:
        selectedAccentFound = true
      elif node.kind == nkDrawable and node.fill == modifiedDotFill:
        for op in node.drawOps:
          if op.kind == dkCircle:
            modifiedDotFound = true

    check selected.accentColor.a == 0.0'f32
    check modified.accentColor.a == 0.0'f32
    check selectedAccentFound
    check modifiedDotFound

  test "document tab themes control every selection indicator edge":
    let
      tabs = newDocumentTabs(frame = rect(0, 0, 360, 34))
      selected = newDocumentTabItem("Selected", "selected")
      indicatorFill = fill(color(0.76, 0.16, 0.58, 1.0))
      indicatorInsets = insets(4.0, 9.0, 5.0, 11.0)
      indicatorSize = 3.0'f32

    discard tabs.addDocumentTabItem(selected)

    for position in [dtipTop, dtipBottom, dtipLeft, dtipRight, dtipNone]:
      var theme = initTheme()
      theme[srDocumentTab, StyleSelectionIndicatorPosition] = styleKeyword(position)
      theme[srDocumentTab, StyleSelectionIndicatorFill] = indicatorFill
      theme[srDocumentTab, StyleSelectionIndicatorInsets] = indicatorInsets
      theme[srDocumentTab, StyleSelectionIndicatorSize] = indicatorSize
      theme[srDocumentTab, StyleSelectionIndicatorCornerRadius] = 0.5

      let
        renders = buildRenders(tabs, initAppearance(theme))
        tabRect = tabs.documentTabRect(0)
        available = tabRect.inset(indicatorInsets)
      var indicatorRect: nimkitTypes.Rect
      for node in renders[DefaultDrawLevel].nodes:
        if node.kind == nkRectangle and node.fill == indicatorFill:
          indicatorRect = node.renderedRect()
          break

      case position
      of dtipNone:
        check indicatorRect.isEmpty
      of dtipTop:
        check indicatorRect.rectsClose(
          rect(available.minX, available.minY, available.size.width, indicatorSize)
        )
      of dtipBottom:
        check indicatorRect.rectsClose(
          rect(
            available.minX,
            available.maxY - indicatorSize,
            available.size.width,
            indicatorSize,
          )
        )
      of dtipLeft:
        check indicatorRect.rectsClose(
          rect(available.minX, available.minY, indicatorSize, available.size.height)
        )
      of dtipRight:
        check indicatorRect.rectsClose(
          rect(
            available.maxX - indicatorSize,
            available.minY,
            indicatorSize,
            available.size.height,
          )
        )

  test "document tab themes control the close button side":
    let
      tabs = newDocumentTabs(frame = rect(0, 0, 360, 34))
      selected = newDocumentTabItem("Selected", "selected")

    discard tabs.addDocumentTabItem(selected)

    proc closeSymbolRect(theme: Theme): nimkitTypes.Rect =
      let renders = buildRenders(tabs, initAppearance(theme))
      for node in renders[DefaultDrawLevel].nodes:
        if node.kind == nkText and node.renderedText() == "×":
          return node.renderedRect()

    let tabRect = tabs.documentTabRect(0)
    for theme in [initTheme(), initMacOSTheme()]:
      check closeSymbolRect(theme).center().x < tabRect.center().x

    var rightTheme = initTheme()
    rightTheme[srDocumentTab, StyleCloseButtonPosition] = styleKeyword(dtcbRight)
    check closeSymbolRect(rightTheme).center().x > tabRect.center().x

  test "delegates can veto selection closing and moving while signals fire":
    let
      tabs = newDocumentTabs(frame = rect(0, 0, 420, 34))
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
      window = newWindow("Document tabs overflow", frame = rect(0, 0, 260, 80))
      root = newView(frame = rect(0, 0, 260, 80))
      tabs = newDocumentTabs(frame = rect(10, 10, 220, 34))
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
    let tabs = newDocumentTabs(frame = rect(0, 0, 210, 34))
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

  test "document tab scroll buttons resolve document tab button theme fill":
    let tabs = newDocumentTabs(frame = rect(0, 0, 210, 34))
    for index in 0 .. 4:
      discard tabs.addDocumentTabItem(newDocumentTabItem("Document " & $index))
    tabs.scrollOffset = 10.0'f32

    var theme = initTheme()
    theme[srDocumentTabButton, StyleChrome] = styleKeyword(DefaultChromeName)
    theme[srDocumentTabButton, StyleFill] = DocumentTabButtonThemeFill

    let
      renders = buildRenders(tabs, initAppearance(theme))
      previousRect = tabs.scrollButtonRect(dtsbPrevious)
      nextRect = tabs.scrollButtonRect(dtsbNext)
    var
      previousButtonFound = false
      nextButtonFound = false

    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill == DocumentTabButtonThemeFill:
        if node.renderedRect().rectsClose(previousRect):
          previousButtonFound = true
        elif node.renderedRect().rectsClose(nextRect):
          nextButtonFound = true

    check previousButtonFound
    check nextButtonFound

  test "document tabs resolve document tab theme roles and chrome":
    let
      tabs = newDocumentTabs(frame = rect(0, 0, 360, 34))
      first = newDocumentTabItem("Primary", "primary")
      special = newDocumentTabItem("Special", "special")
      defaultAppearance = initAppearance()

    check defaultAppearance.resolveChromeName(controlStyle(srDocumentTab)) ==
      defaultAppearance.resolveChromeName(controlStyle(srTab))
    check defaultAppearance.resolveChromeName(controlStyle(srDocumentTabBar)) ==
      defaultAppearance.resolveChromeName(controlStyle(srTabPanel))
    check defaultAppearance.resolveLength(
      controlStyle(srDocumentTab), StyleCornerRadius, 0.0
    ) == 10.0'f32
    check defaultAppearance.resolveLength(
      controlStyle(srDocumentTab), StyleItemGap, 0.0
    ) == 2.0'f32
    check defaultAppearance
    .resolveFill(controlStyle(srDocumentTabBar), fill(color(1.0, 0.0, 0.0, 1.0)))
    .centerColor().a < 0.5'f32

    special.styleId = "special-doc"
    discard tabs.addDocumentTabItem(first)
    discard tabs.addDocumentTabItem(special)

    var theme = initTheme()
    theme.installChrome(DocumentTabChromeName, newDocumentTabChromeSpy())
    theme[srDocumentTab, StyleChrome] = styleKeyword(DocumentTabChromeName)
    theme[srDocumentTabBar, StyleChrome] = styleKeyword(DocumentTabChromeName)
    theme[srDocumentTabButton, StyleChrome] = styleKeyword(DocumentTabChromeName)
    theme[initStyleSelector(srDocumentTab, id = "special-doc"), StyleFill] =
      SpecialDocumentTabFill

    let renders = buildRenders(tabs, initAppearance(theme))
    var
      selectedChromeFound = false
      specialFillFound = false
      barChromeFound = false
      buttonChromeFound = false

    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle:
        if node.fill == DocumentTabChromeFill:
          selectedChromeFound = true
        elif node.fill == SpecialDocumentTabFill:
          specialFillFound = true
        elif node.fill == DocumentTabBarChromeFill:
          barChromeFound = true
        elif node.fill == DocumentTabButtonChromeFill:
          buttonChromeFound = true

    check selectedChromeFound
    check specialFillFound
    check barChromeFound
    check buttonChromeFound
