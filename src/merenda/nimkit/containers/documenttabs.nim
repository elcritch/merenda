from figdraw/fignodes import FigIdx

import sigils/core

import ../accessibility/accessibilityprotocols
import ../drawing
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../foundation/undomanagers
import ../responder/responders
import ../themes
import ../view/views

export views

type
  DocumentTabStyle* = enum
    dtsAutomatic
    dtsRounded
    dtsPill
    dtsUnderline
    dtsCompact

  DocumentTabScrollButton* = enum
    dtsbPrevious
    dtsbNext

  DocumentTabItem* = ref object
    xIdentifier: string
    xTitle: string
    xEnabled: bool
    xCloseable: bool
    xModified: bool
    xStyle: DocumentTabStyle
    xAccentColor: Color
    xStyleId: string
    xStyleClasses: seq[string]
    xUserInfo: DynamicAgent

  DocumentTabHitPart = enum
    dthNone
    dthTab
    dthClose
    dthPreviousButton
    dthNextButton

  DocumentTabs* = ref object of View
    xItems: seq[DocumentTabItem]
    xSelectedIndex: int
    xPressedIndex: int
    xPressedPart: DocumentTabHitPart
    xDraggingTab: bool
    xDragStartPoint: Point
    xAllowsClosing: bool
    xAllowsTabReordering: bool
    xShowsScrollButtons: bool
    xShowsHorizontalScroller: bool
    xDefaultTabStyle: DocumentTabStyle
    xScrollOffset: float32
    xLineScroll: float32
    xDelegate: DynamicAgent

const
  DocumentTabHeight = 30.0'f32
  DocumentTabCompactHeight = 24.0'f32
  DocumentTabBarHeight = 34.0'f32
  DocumentTabButtonWidth = 24.0'f32
  DocumentTabMinWidth = 86.0'f32
  DocumentTabMaxWidth = 190.0'f32
  DocumentTabCompactMinWidth = 62.0'f32
  DocumentTabCompactMaxWidth = 140.0'f32
  DocumentTabHorizontalInset = 12.0'f32
  DocumentTabCloseWidth = 16.0'f32
  DocumentTabDragThreshold = 3.0'f32
  DocumentTabScrollerHeight = 3.0'f32
  DocumentTabDefaultLineScroll = 18.0'f32

protocol DocumentTabsDelegate {.selectorScope: protocol.}:
  method shouldSelectDocumentTab*(
    tabs: DocumentTabs, item: DocumentTabItem
  ): bool {.optional.}

  method didSelectDocumentTab*(tabs: DocumentTabs, item: DocumentTabItem) {.optional.}

  method shouldCloseDocumentTab*(
    tabs: DocumentTabs, item: DocumentTabItem, index: int
  ): bool {.optional.}

  method didCloseDocumentTab*(
    tabs: DocumentTabs, item: DocumentTabItem, index: int
  ) {.optional.}

  method shouldMoveDocumentTab*(
    tabs: DocumentTabs, item: DocumentTabItem, fromIndex: int, toIndex: int
  ): bool {.optional.}

  method didMoveDocumentTab*(
    tabs: DocumentTabs, item: DocumentTabItem, fromIndex: int, toIndex: int
  ) {.optional.}

protocol DocumentTabsEvents:
  proc documentTabSelectionIsChanging*(
    tabs: DocumentTabs, sender: DynamicAgent
  ) {.signal.}

  proc documentTabSelectionDidChange*(
    tabs: DocumentTabs, sender: DynamicAgent
  ) {.signal.}

  proc documentTabWillClose*(
    tabs: DocumentTabs, item: DocumentTabItem, index: int
  ) {.signal.}

  proc documentTabDidClose*(
    tabs: DocumentTabs, item: DocumentTabItem, index: int
  ) {.signal.}

  proc documentTabWillMove*(
    tabs: DocumentTabs, item: DocumentTabItem, fromIndex: int, toIndex: int
  ) {.signal.}

  proc documentTabDidMove*(
    tabs: DocumentTabs, item: DocumentTabItem, fromIndex: int, toIndex: int
  ) {.signal.}

  proc documentTabsDidScroll*(tabs: DocumentTabs, offset: float32) {.signal.}

proc reloadDocumentTabs*(tabs: DocumentTabs)
proc clampScrollOffset(tabs: DocumentTabs, offset: float32): float32
proc maximumScrollOffset*(tabs: DocumentTabs): float32
proc tabViewportRect*(tabs: DocumentTabs): Rect
proc documentTabRect*(tabs: DocumentTabs, index: int): Rect
proc documentTabIndexAtPoint*(tabs: DocumentTabs, point: Point): int
proc insertDocumentTabItem*(
  tabs: DocumentTabs, item: DocumentTabItem, index: Natural
): DocumentTabItem {.discardable.}

proc removeDocumentTabAtIndex*(tabs: DocumentTabs, index: int): bool {.discardable.}
proc moveDocumentTabItem*(
  tabs: DocumentTabs, fromIndex, toIndex: int
): bool {.discardable.}

proc selectDocumentTabAtIndex*(tabs: DocumentTabs, index: int): bool {.discardable.}
proc drawDocumentTab(
  tabs: DocumentTabs, context: DrawContext, parent: FigIdx, index: int
)

proc initDocumentTabItemFields*(
    item: DocumentTabItem,
    title = "Untitled",
    identifier = "",
    closeable = true,
    style = dtsAutomatic,
) =
  item.xIdentifier = identifier
  item.xTitle = title
  item.xEnabled = true
  item.xCloseable = closeable
  item.xStyle = style
  item.xAccentColor = initColor(0.20, 0.45, 0.92, 1.0)

proc initDocumentTabItem*(
    title = "Untitled", identifier = "", closeable = true, style = dtsAutomatic
): DocumentTabItem =
  result = DocumentTabItem()
  result.initDocumentTabItemFields(title, identifier, closeable, style)

proc newDocumentTabItem*(
    title = "Untitled", identifier = "", closeable = true, style = dtsAutomatic
): DocumentTabItem =
  initDocumentTabItem(title, identifier, closeable, style)

proc identifier*(item: DocumentTabItem): string =
  if item.isNil: "" else: item.xIdentifier

proc `identifier=`*(item: DocumentTabItem, identifier: string) =
  if not item.isNil:
    item.xIdentifier = identifier

proc title*(item: DocumentTabItem): string =
  if item.isNil: "" else: item.xTitle

proc `title=`*(item: DocumentTabItem, title: string) =
  if not item.isNil:
    item.xTitle = title

proc enabled*(item: DocumentTabItem): bool =
  not item.isNil and item.xEnabled

proc `enabled=`*(item: DocumentTabItem, enabled: bool) =
  if not item.isNil:
    item.xEnabled = enabled

proc closeable*(item: DocumentTabItem): bool =
  not item.isNil and item.xCloseable

proc `closeable=`*(item: DocumentTabItem, closeable: bool) =
  if not item.isNil:
    item.xCloseable = closeable

proc modified*(item: DocumentTabItem): bool =
  not item.isNil and item.xModified

proc `modified=`*(item: DocumentTabItem, modified: bool) =
  if not item.isNil:
    item.xModified = modified

proc style*(item: DocumentTabItem): DocumentTabStyle =
  if item.isNil: dtsAutomatic else: item.xStyle

proc `style=`*(item: DocumentTabItem, style: DocumentTabStyle) =
  if not item.isNil:
    item.xStyle = style

proc accentColor*(item: DocumentTabItem): Color =
  if item.isNil:
    initColor(0.20, 0.45, 0.92, 1.0)
  else:
    item.xAccentColor

proc `accentColor=`*(item: DocumentTabItem, color: Color) =
  if not item.isNil:
    item.xAccentColor = color

proc styleId*(item: DocumentTabItem): string =
  if item.isNil: "" else: item.xStyleId

proc `styleId=`*(item: DocumentTabItem, id: string) =
  if not item.isNil:
    item.xStyleId = id

proc styleClasses*(item: DocumentTabItem): seq[string] =
  if item.isNil:
    @[]
  else:
    item.xStyleClasses

proc `styleClasses=`*(item: DocumentTabItem, classes: openArray[string]) =
  if not item.isNil:
    item.xStyleClasses = @classes

proc userInfo*(item: DocumentTabItem): DynamicAgent =
  if item.isNil: nil else: item.xUserInfo

proc `userInfo=`*(item: DocumentTabItem, userInfo: DynamicAgent) =
  if not item.isNil:
    item.xUserInfo = userInfo

proc len*(tabs: DocumentTabs): int =
  if tabs.isNil: 0 else: tabs.xItems.len

proc items*(tabs: DocumentTabs): lent seq[DocumentTabItem] =
  tabs.xItems

proc `[]`*(tabs: DocumentTabs, index: Natural): DocumentTabItem =
  tabs.xItems[index]

proc delegate*(tabs: DocumentTabs): DynamicAgent =
  if tabs.isNil: nil else: tabs.xDelegate

proc `delegate=`*(tabs: DocumentTabs, delegate: DynamicAgent) =
  if not tabs.isNil:
    tabs.xDelegate = delegate

proc `delegate=`*(tabs: DocumentTabs, delegate: Responder) =
  tabs.delegate = DynamicAgent(delegate)

proc selectedIndex*(tabs: DocumentTabs): int =
  if tabs.isNil: -1 else: tabs.xSelectedIndex

proc `selectedIndex=`*(tabs: DocumentTabs, index: int) =
  discard tabs.selectDocumentTabAtIndex(index)

proc selectedDocumentTabItem*(tabs: DocumentTabs): DocumentTabItem =
  if tabs.isNil or tabs.xSelectedIndex < 0 or tabs.xSelectedIndex >= tabs.xItems.len:
    nil
  else:
    tabs.xItems[tabs.xSelectedIndex]

proc allowsClosing*(tabs: DocumentTabs): bool =
  not tabs.isNil and tabs.xAllowsClosing

proc `allowsClosing=`*(tabs: DocumentTabs, allowed: bool) =
  if tabs.isNil or tabs.xAllowsClosing == allowed:
    return
  tabs.xAllowsClosing = allowed
  tabs.reloadDocumentTabs()

proc allowsTabReordering*(tabs: DocumentTabs): bool =
  not tabs.isNil and tabs.xAllowsTabReordering

proc `allowsTabReordering=`*(tabs: DocumentTabs, allowed: bool) =
  if tabs.isNil or tabs.xAllowsTabReordering == allowed:
    return
  tabs.xAllowsTabReordering = allowed
  tabs.xDraggingTab = false
  tabs.xPressedPart = dthNone
  tabs.setNeedsDisplay(true)

proc showsScrollButtons*(tabs: DocumentTabs): bool =
  not tabs.isNil and tabs.xShowsScrollButtons

proc `showsScrollButtons=`*(tabs: DocumentTabs, shows: bool) =
  if tabs.isNil or tabs.xShowsScrollButtons == shows:
    return
  tabs.xShowsScrollButtons = shows
  tabs.reloadDocumentTabs()

proc showsHorizontalScroller*(tabs: DocumentTabs): bool =
  not tabs.isNil and tabs.xShowsHorizontalScroller

proc `showsHorizontalScroller=`*(tabs: DocumentTabs, shows: bool) =
  if tabs.isNil or tabs.xShowsHorizontalScroller == shows:
    return
  tabs.xShowsHorizontalScroller = shows
  tabs.setNeedsDisplay(true)

proc defaultTabStyle*(tabs: DocumentTabs): DocumentTabStyle =
  if tabs.isNil: dtsRounded else: tabs.xDefaultTabStyle

proc `defaultTabStyle=`*(tabs: DocumentTabs, style: DocumentTabStyle) =
  if tabs.isNil or tabs.xDefaultTabStyle == style:
    return
  tabs.xDefaultTabStyle = if style == dtsAutomatic: dtsRounded else: style
  tabs.reloadDocumentTabs()

proc scrollOffset*(tabs: DocumentTabs): float32 =
  if tabs.isNil: 0.0'f32 else: tabs.xScrollOffset

proc `scrollOffset=`*(tabs: DocumentTabs, offset: float32) =
  if tabs.isNil:
    return
  let clamped = tabs.clampScrollOffset(offset)
  if abs(tabs.xScrollOffset - clamped) <= 0.01'f32:
    return
  tabs.xScrollOffset = clamped
  tabs.setNeedsDisplay(true)
  emit tabs.documentTabsDidScroll(clamped)

proc lineScroll*(tabs: DocumentTabs): float32 =
  if tabs.isNil: DocumentTabDefaultLineScroll else: tabs.xLineScroll

proc `lineScroll=`*(tabs: DocumentTabs, value: float32) =
  if not tabs.isNil:
    tabs.xLineScroll = max(value, 1.0'f32)

proc documentTabAppearance(tabs: DocumentTabs): Appearance =
  if tabs.isNil:
    initAppearance()
  else:
    tabs.effectiveAppearance()

proc mergedStyleClasses(
    tabs: DocumentTabs, item: DocumentTabItem = nil, extra: openArray[string] = []
): seq[string] =
  if not tabs.isNil:
    result.add tabs.styleClasses()
  if not item.isNil:
    result.add item.styleClasses()
  for class in extra:
    result.add class

proc documentTabStyleContext(
    tabs: DocumentTabs, item: DocumentTabItem, states: set[WidgetState] = {}
): StyleContext =
  var effectiveStates = states
  if not tabs.isNil:
    effectiveStates = effectiveStates + tabs.widgetStateSet()
  let id =
    if not item.isNil and item.styleId().len > 0:
      item.styleId()
    elif tabs.isNil:
      ""
    else:
      tabs.styleId()
  controlStyle(
    srDocumentTab, effectiveStates, id = id, classes = tabs.mergedStyleClasses(item)
  )

proc documentTabBarStyleContext(
    tabs: DocumentTabs, states: set[WidgetState] = {}
): StyleContext =
  var effectiveStates = states
  if not tabs.isNil:
    effectiveStates = effectiveStates + tabs.widgetStateSet()
  controlStyle(
    srDocumentTabBar,
    effectiveStates,
    id =
      if tabs.isNil:
        ""
      else:
        tabs.styleId(),
    classes = tabs.mergedStyleClasses(),
  )

proc documentTabButtonStyleContext(
    tabs: DocumentTabs, states: set[WidgetState] = {}, classes: openArray[string] = []
): StyleContext =
  var effectiveStates = states
  if not tabs.isNil:
    effectiveStates = effectiveStates + tabs.widgetStateSet()
  controlStyle(
    srDocumentTabButton,
    effectiveStates,
    id =
      if tabs.isNil:
        ""
      else:
        tabs.styleId(),
    classes = tabs.mergedStyleClasses(extra = classes),
  )

proc documentTabViewStyle(tabs: DocumentTabs, appearance: Appearance): TabViewStyle =
  appearance.resolveTabViewStyle(tabs.documentTabStyleContext(nil))

proc documentTabViewStyle(tabs: DocumentTabs): TabViewStyle =
  tabs.documentTabViewStyle(tabs.documentTabAppearance())

proc documentTabGap(tabs: DocumentTabs): float32 =
  max(tabs.documentTabViewStyle().tabGap, 0.0'f32)

func effectiveStyle(tabs: DocumentTabs, item: DocumentTabItem): DocumentTabStyle =
  if not item.isNil and item.xStyle != dtsAutomatic:
    item.xStyle
  elif tabs.isNil:
    dtsRounded
  else:
    tabs.xDefaultTabStyle

func tabHeight(style: DocumentTabStyle, viewStyle: TabViewStyle): float32 =
  let themedHeight =
    if viewStyle.tabHeight > 0.0'f32: viewStyle.tabHeight else: DocumentTabHeight
  case style
  of dtsCompact:
    min(themedHeight, DocumentTabCompactHeight)
  else:
    themedHeight

func tabWidthBounds(
    style: DocumentTabStyle, viewStyle: TabViewStyle
): tuple[minWidth, maxWidth: float32] =
  let
    fallback =
      case style
      of dtsCompact:
        (minWidth: DocumentTabCompactMinWidth, maxWidth: DocumentTabCompactMaxWidth)
      else:
        (minWidth: DocumentTabMinWidth, maxWidth: DocumentTabMaxWidth)
    minWidth =
      if viewStyle.tabMinWidth > 0.0'f32: viewStyle.tabMinWidth else: fallback.minWidth
    maxWidth =
      if viewStyle.tabMaxWidth >= minWidth: viewStyle.tabMaxWidth else: fallback.maxWidth
  case style
  of dtsCompact:
    (
      minWidth: min(minWidth, DocumentTabCompactMinWidth),
      maxWidth: min(maxWidth, DocumentTabCompactMaxWidth),
    )
  else:
    (minWidth: minWidth, maxWidth: max(maxWidth, minWidth))

proc tabTextStyle(
    appearance: Appearance, styleContext: StyleContext, color: Color
): TextStyle =
  appearance.resolveTextStyle(styleContext, color, insets(0.0))

func documentTabTextColor(enabled, selected: bool): Color =
  if not enabled:
    initColor(0.50, 0.52, 0.56, 1.0)
  elif selected:
    initColor(0.07, 0.08, 0.10, 1.0)
  else:
    initColor(0.18, 0.20, 0.25, 1.0)

proc documentTabWidth(tabs: DocumentTabs, item: DocumentTabItem): float32 =
  if item.isNil:
    return DocumentTabMinWidth
  let
    appearance = tabs.documentTabAppearance()
    style = tabs.effectiveStyle(item)
    styleContext = tabs.documentTabStyleContext(item)
    viewStyle = appearance.resolveTabViewStyle(styleContext)
    bounds = style.tabWidthBounds(viewStyle)
    textStyle = appearance.tabTextStyle(
      styleContext, documentTabTextColor(item.enabled(), selected = false)
    )
    titleWidth = min(textNaturalSize(item.title(), textStyle).width, bounds.maxWidth)
    horizontalInset = max(viewStyle.tabHorizontalPadding, 0.0'f32)
    closeWidth =
      if tabs.allowsClosing() and item.closeable():
        DocumentTabCloseWidth + 6.0'f32
      else:
        0.0'f32
    modifiedWidth = if item.modified(): 9.0'f32 else: 0.0'f32
  min(
    max(
      titleWidth + horizontalInset * 2.0'f32 + closeWidth + modifiedWidth,
      bounds.minWidth,
    ),
    bounds.maxWidth,
  )

proc contentWidth*(tabs: DocumentTabs): float32 =
  if tabs.isNil:
    return 0.0'f32
  for index, item in tabs.xItems:
    if index > 0:
      result += tabs.documentTabGap()
    result += tabs.documentTabWidth(item)

proc contentOverflowsFrame(tabs: DocumentTabs): bool =
  not tabs.isNil and tabs.contentWidth() > tabs.bounds().size.width + 0.01'f32

proc hasOverflow*(tabs: DocumentTabs): bool =
  not tabs.isNil and tabs.maximumScrollOffset() > 0.01'f32

proc scrollButtonRect*(tabs: DocumentTabs, button: DocumentTabScrollButton): Rect =
  if tabs.isNil or not tabs.xShowsScrollButtons or not tabs.hasOverflow():
    return
  let bounds = tabs.bounds()
  case button
  of dtsbPrevious:
    initRect(0.0, 0.0, DocumentTabButtonWidth, bounds.size.height)
  of dtsbNext:
    initRect(
      max(bounds.size.width - DocumentTabButtonWidth, 0.0'f32),
      0.0,
      min(DocumentTabButtonWidth, bounds.size.width),
      bounds.size.height,
    )

proc tabViewportRect*(tabs: DocumentTabs): Rect =
  if tabs.isNil:
    return
  let
    bounds = tabs.bounds()
    buttonInset =
      if tabs.xShowsScrollButtons and tabs.contentOverflowsFrame():
        DocumentTabButtonWidth
      else:
        0.0'f32
  initRect(
    buttonInset,
    0.0,
    max(bounds.size.width - buttonInset * 2.0'f32, 0.0'f32),
    bounds.size.height,
  )

proc maximumScrollOffset*(tabs: DocumentTabs): float32 =
  if tabs.isNil:
    return 0.0'f32
  max(tabs.contentWidth() - tabs.tabViewportRect().size.width, 0.0'f32)

proc clampScrollOffset(tabs: DocumentTabs, offset: float32): float32 =
  if tabs.isNil:
    return 0.0'f32
  max(0.0'f32, min(offset, tabs.maximumScrollOffset()))

proc reloadDocumentTabs*(tabs: DocumentTabs) =
  if tabs.isNil:
    return
  tabs.xScrollOffset = tabs.clampScrollOffset(tabs.xScrollOffset)
  tabs.invalidateIntrinsicContentSize()
  tabs.setNeedsLayout()
  tabs.setNeedsDisplay(true)

proc contentTabRect(tabs: DocumentTabs, index: int): Rect =
  if tabs.isNil or index < 0 or index >= tabs.xItems.len:
    return
  var x = 0.0'f32
  let gap = tabs.documentTabGap()
  for itemIndex in 0 ..< index:
    x += tabs.documentTabWidth(tabs.xItems[itemIndex]) + gap
  let
    item = tabs.xItems[index]
    style = tabs.effectiveStyle(item)
    height = style.tabHeight(tabs.documentTabViewStyle())
    y = max((tabs.bounds().size.height - height) / 2.0'f32, 0.0'f32)
  initRect(x, y, tabs.documentTabWidth(item), height)

proc documentTabRect*(tabs: DocumentTabs, index: int): Rect =
  if tabs.isNil:
    return
  let
    viewport = tabs.tabViewportRect()
    contentRect = tabs.contentTabRect(index)
  initRect(
    viewport.origin.x + contentRect.origin.x - tabs.xScrollOffset,
    contentRect.origin.y,
    contentRect.size.width,
    contentRect.size.height,
  )

proc closeRect(tabs: DocumentTabs, index: int): Rect =
  if tabs.isNil or index < 0 or index >= tabs.xItems.len:
    return
  let
    item = tabs.xItems[index]
    rect = tabs.documentTabRect(index)
  if not tabs.allowsClosing() or not item.closeable() or rect.size.width < 44.0'f32:
    return
  initRect(
    rect.maxX - DocumentTabCloseWidth - 7.0'f32,
    rect.origin.y + max((rect.size.height - DocumentTabCloseWidth) / 2.0'f32, 0.0),
    DocumentTabCloseWidth,
    DocumentTabCloseWidth,
  )

proc scrollTabToVisible(tabs: DocumentTabs, index: int) =
  if tabs.isNil or index < 0 or index >= tabs.xItems.len:
    return
  let
    viewport = tabs.tabViewportRect()
    contentRect = tabs.contentTabRect(index)
    visibleStart = tabs.xScrollOffset
    visibleStop = tabs.xScrollOffset + viewport.size.width
  if contentRect.minX < visibleStart:
    tabs.scrollOffset = contentRect.minX
  elif contentRect.maxX > visibleStop:
    tabs.scrollOffset = contentRect.maxX - viewport.size.width

proc indexOfDocumentTabItem*(tabs: DocumentTabs, item: DocumentTabItem): int =
  if tabs.isNil or item.isNil:
    return -1
  tabs.xItems.find(item)

proc selectedItemAfterRemoval(tabs: DocumentTabs, removedIndex: int): int =
  if tabs.xItems.len == 0:
    return -1
  if tabs.xSelectedIndex == removedIndex:
    return min(removedIndex, tabs.xItems.high)
  if tabs.xSelectedIndex > removedIndex:
    return tabs.xSelectedIndex - 1
  tabs.xSelectedIndex

proc shouldSelect(tabs: DocumentTabs, item: DocumentTabItem): bool =
  if tabs.isNil or item.isNil or not item.enabled():
    return false
  let delegate = tabs.delegate()
  if delegate.isNil:
    return true
  delegate.trySendLocal(shouldSelectDocumentTab(), (tabs: tabs, item: item)).get(true)

proc didSelect(tabs: DocumentTabs, item: DocumentTabItem) =
  let delegate = tabs.delegate()
  if not delegate.isNil:
    discard
      delegate.sendLocalIfHandled(didSelectDocumentTab(), (tabs: tabs, item: item))

proc shouldClose(tabs: DocumentTabs, item: DocumentTabItem, index: int): bool =
  if tabs.isNil or item.isNil or not tabs.allowsClosing() or not item.closeable():
    return false
  let delegate = tabs.delegate()
  if delegate.isNil:
    return true

  delegate
  .trySendLocal(shouldCloseDocumentTab(), (tabs: tabs, item: item, index: index))
  .get(true)

proc didClose(tabs: DocumentTabs, item: DocumentTabItem, index: int) =
  let delegate = tabs.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didCloseDocumentTab(), (tabs: tabs, item: item, index: index)
    )

proc shouldMove(
    tabs: DocumentTabs, item: DocumentTabItem, fromIndex, toIndex: int
): bool =
  if tabs.isNil or item.isNil or not tabs.allowsTabReordering():
    return false
  let delegate = tabs.delegate()
  if delegate.isNil:
    return true

  delegate
  .trySendLocal(
    shouldMoveDocumentTab(),
    (tabs: tabs, item: item, fromIndex: fromIndex, toIndex: toIndex),
  )
  .get(true)

proc didMove(tabs: DocumentTabs, item: DocumentTabItem, fromIndex, toIndex: int) =
  let delegate = tabs.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didMoveDocumentTab(),
      (tabs: tabs, item: item, fromIndex: fromIndex, toIndex: toIndex),
    )

proc selectDocumentTabAtIndex*(tabs: DocumentTabs, index: int): bool {.discardable.} =
  if tabs.isNil or index < 0 or index >= tabs.xItems.len:
    return false
  if index == tabs.xSelectedIndex:
    return true
  let item = tabs.xItems[index]
  if not tabs.shouldSelect(item):
    return false
  emit tabs.documentTabSelectionIsChanging(DynamicAgent(tabs))
  tabs.xSelectedIndex = index
  tabs.scrollTabToVisible(index)
  tabs.didSelect(item)
  tabs.setNeedsDisplay(true)
  tabs.postAccessibilityNotification(anSelectionChanged)
  emit tabs.documentTabSelectionDidChange(DynamicAgent(tabs))
  true

proc selectDocumentTab*(
    tabs: DocumentTabs, item: DocumentTabItem
): bool {.discardable.} =
  tabs.selectDocumentTabAtIndex(tabs.indexOfDocumentTabItem(item))

proc addDocumentTabItem*(
    tabs: DocumentTabs, item: DocumentTabItem
): DocumentTabItem {.discardable.} =
  if tabs.isNil or item.isNil:
    return nil
  let index = tabs.xItems.len
  tabs.findUndoManager().registerCollectionInsert(
    proc(index: int) =
      discard tabs.removeDocumentTabAtIndex(index),
    index,
    "Insert Tab",
  )
  tabs.xItems.add item
  if tabs.xSelectedIndex < 0 and item.enabled():
    tabs.xSelectedIndex = tabs.xItems.high
  tabs.reloadDocumentTabs()
  if tabs.xSelectedIndex == tabs.xItems.high:
    tabs.scrollTabToVisible(tabs.xSelectedIndex)
  item

proc insertDocumentTabItem*(
    tabs: DocumentTabs, item: DocumentTabItem, index: Natural
): DocumentTabItem {.discardable.} =
  if tabs.isNil or item.isNil:
    return nil
  let boundedIndex = min(index.int, tabs.xItems.len)
  tabs.findUndoManager().registerCollectionInsert(
    proc(index: int) =
      discard tabs.removeDocumentTabAtIndex(index),
    boundedIndex,
    "Insert Tab",
  )
  tabs.xItems.insert(item, boundedIndex)
  if tabs.xSelectedIndex >= boundedIndex:
    inc tabs.xSelectedIndex
  elif tabs.xSelectedIndex < 0 and item.enabled():
    tabs.xSelectedIndex = boundedIndex
  tabs.reloadDocumentTabs()
  item

proc removeDocumentTabAtIndex*(tabs: DocumentTabs, index: int): bool {.discardable.} =
  if tabs.isNil or index < 0 or index >= tabs.xItems.len:
    return false
  let item = tabs.xItems[index]
  tabs.findUndoManager().registerCollectionRemove(
    proc(index: int, item: DocumentTabItem) =
      discard tabs.insertDocumentTabItem(item, index.Natural),
    index,
    item,
    "Remove Tab",
  )
  tabs.xItems.delete(index)
  tabs.xSelectedIndex = tabs.selectedItemAfterRemoval(index)
  tabs.xPressedIndex = -1
  tabs.xPressedPart = dthNone
  tabs.reloadDocumentTabs()
  if tabs.xSelectedIndex >= 0:
    tabs.scrollTabToVisible(tabs.xSelectedIndex)
  true

proc removeDocumentTab*(
    tabs: DocumentTabs, item: DocumentTabItem
): bool {.discardable.} =
  tabs.removeDocumentTabAtIndex(tabs.indexOfDocumentTabItem(item))

proc closeDocumentTabAtIndex*(tabs: DocumentTabs, index: int): bool {.discardable.} =
  if tabs.isNil or index < 0 or index >= tabs.xItems.len:
    return false
  let item = tabs.xItems[index]
  if not tabs.shouldClose(item, index):
    return false
  emit tabs.documentTabWillClose(item, index)
  discard tabs.removeDocumentTabAtIndex(index)
  tabs.didClose(item, index)
  emit tabs.documentTabDidClose(item, index)
  true

proc closeDocumentTab*(
    tabs: DocumentTabs, item: DocumentTabItem
): bool {.discardable.} =
  tabs.closeDocumentTabAtIndex(tabs.indexOfDocumentTabItem(item))

proc removeAllDocumentTabs*(tabs: DocumentTabs) =
  if tabs.isNil:
    return
  tabs.xItems.setLen(0)
  tabs.xSelectedIndex = -1
  tabs.xPressedIndex = -1
  tabs.xScrollOffset = 0.0
  tabs.reloadDocumentTabs()

proc moveDocumentTabItem*(tabs: DocumentTabs, fromIndex, toIndex: int): bool =
  if tabs.isNil or fromIndex < 0 or fromIndex >= tabs.xItems.len:
    return false
  let boundedIndex = max(0, min(toIndex, tabs.xItems.high))
  if boundedIndex == fromIndex:
    return false
  let item = tabs.xItems[fromIndex]
  if not tabs.shouldMove(item, fromIndex, boundedIndex):
    return false

  tabs.findUndoManager().registerCollectionMove(
    proc(fromIndex, toIndex: int) =
      discard tabs.moveDocumentTabItem(fromIndex, toIndex),
    fromIndex,
    boundedIndex,
    "Move Tab",
  )
  emit tabs.documentTabWillMove(item, fromIndex, boundedIndex)
  let selectedItem = tabs.selectedDocumentTabItem()
  tabs.xItems.delete(fromIndex)
  tabs.xItems.insert(item, boundedIndex)
  tabs.xSelectedIndex = tabs.indexOfDocumentTabItem(selectedItem)
  tabs.xPressedIndex = boundedIndex
  tabs.reloadDocumentTabs()
  tabs.scrollTabToVisible(boundedIndex)
  tabs.didMove(item, fromIndex, boundedIndex)
  emit tabs.documentTabDidMove(item, fromIndex, boundedIndex)
  true

proc scrollDocumentTabsBy*(tabs: DocumentTabs, delta: float32): bool {.discardable.} =
  if tabs.isNil or abs(delta) <= 0.01'f32:
    return false
  let before = tabs.xScrollOffset
  tabs.scrollOffset = before + delta
  abs(tabs.xScrollOffset - before) > 0.01'f32

proc scrollDocumentTabsToStart*(tabs: DocumentTabs) =
  tabs.scrollOffset = 0.0

proc scrollDocumentTabsToEnd*(tabs: DocumentTabs) =
  tabs.scrollOffset = tabs.maximumScrollOffset()

proc scrollButtonDelta(tabs: DocumentTabs, button: DocumentTabScrollButton): float32 =
  let amount = max(tabs.tabViewportRect().size.width * 0.75'f32, 48.0'f32)
  case button
  of dtsbPrevious:
    -amount
  of dtsbNext:
    amount

proc documentTabIndexAtPoint*(tabs: DocumentTabs, point: Point): int =
  if tabs.isNil or not tabs.tabViewportRect().contains(point):
    return -1
  for index in 0 ..< tabs.xItems.len:
    let rect = tabs.documentTabRect(index)
    if not rect.intersection(tabs.tabViewportRect()).isEmpty and rect.contains(point):
      return index
  -1

proc tabMoveDestinationIndex(tabs: DocumentTabs, point: Point): int =
  if tabs.isNil or tabs.xItems.len == 0:
    return -1
  let
    viewport = tabs.tabViewportRect()
    contentX = point.x - viewport.origin.x + tabs.xScrollOffset
  for index in 0 ..< tabs.xItems.len:
    let rect = tabs.contentTabRect(index)
    if contentX < rect.origin.x + rect.size.width * 0.5'f32:
      return index
  tabs.xItems.high

proc hitPart(
    tabs: DocumentTabs, point: Point
): tuple[part: DocumentTabHitPart, index: int] =
  result = (dthNone, -1)
  if tabs.isNil:
    return
  if tabs.scrollButtonRect(dtsbPrevious).contains(point):
    return (dthPreviousButton, -1)
  if tabs.scrollButtonRect(dtsbNext).contains(point):
    return (dthNextButton, -1)
  let index = tabs.documentTabIndexAtPoint(point)
  if index < 0:
    return
  if tabs.closeRect(index).contains(point):
    result = (dthClose, index)
  else:
    result = (dthTab, index)

func barFillColor(): Color =
  initColor(0.88, 0.90, 0.94, 1.0)

func selectedFillColor(style: DocumentTabStyle): Color =
  case style
  of dtsPill:
    initColor(0.98, 0.98, 0.96, 1.0)
  of dtsUnderline:
    initColor(0.0, 0.0, 0.0, 0.0)
  of dtsCompact:
    initColor(0.95, 0.96, 0.98, 1.0)
  else:
    initColor(0.98, 0.98, 0.96, 1.0)

func tabFillColor(style: DocumentTabStyle, selected, pressed: bool): Color =
  if selected:
    return style.selectedFillColor()
  if pressed:
    return initColor(0.78, 0.82, 0.88, 1.0)
  case style
  of dtsUnderline:
    initColor(0.0, 0.0, 0.0, 0.0)
  of dtsCompact:
    initColor(0.82, 0.85, 0.90, 0.95)
  else:
    initColor(0.84, 0.87, 0.92, 0.95)

func tabBorderColor(style: DocumentTabStyle, selected: bool): Color =
  if style == dtsUnderline:
    initColor(0.0, 0.0, 0.0, 0.0)
  elif selected:
    initColor(0.42, 0.46, 0.54, 1.0)
  else:
    initColor(0.62, 0.66, 0.74, 1.0)

func tabCornerRadius(style: DocumentTabStyle): float32 =
  case style
  of dtsPill: 999.0'f32
  of dtsCompact: 5.0'f32
  of dtsUnderline: 0.0'f32
  else: 7.0'f32

func tabHighlightFill(enabled: bool): Fill =
  fill(initColor(1.0, 1.0, 1.0, if enabled: 0.46 else: 0.20))

proc drawCloseButton(
    tabs: DocumentTabs,
    context: DrawContext,
    parent: FigIdx,
    rect: Rect,
    selected, pressed: bool,
) =
  if rect.isEmpty:
    return
  var states: set[WidgetState]
  if selected:
    states.incl ssSelected
  if pressed:
    states.incl ssHighlighted
    states.incl ssPressed
  let
    styleContext =
      tabs.documentTabButtonStyleContext(states, classes = ["document-tab-close"])
    fillColor =
      if pressed:
        initColor(0.52, 0.56, 0.62, 0.85)
      elif selected:
        initColor(0.72, 0.76, 0.82, 0.70)
      else:
        initColor(0.64, 0.68, 0.74, 0.50)
    textColor =
      if selected:
        initColor(0.12, 0.14, 0.18, 1.0)
      else:
        initColor(0.22, 0.24, 0.30, 1.0)
    fillValue = context.appearance.resolveFill(styleContext, fill(fillColor))
    borderColor = context.appearance.resolveColor(
      styleContext, StyleBorderColor, initColor(0.0, 0.0, 0.0, 0.0)
    )
    borderWidth =
      context.appearance.resolveLength(styleContext, StyleBorderWidth, 0.0'f32)
    radius = rect.size.width / 2.0'f32
    chrome = chromeContext(
      context.appearance.resolveChromeName(styleContext),
      crButton,
      cpFace,
      fillValue,
      states,
    )
    markColor = context.appearance.resolveColor(styleContext, StyleMarkColor, textColor)
    markStyle = context.appearance.tabTextStyle(styleContext, markColor)
    markRect = initRect(
      rect.origin.x, rect.origin.y - 0.5'f32, rect.size.width, rect.size.height
    )
    renderRect = context.renderRectFor(rect)
    buttonRoot = context.addRenderRectangle(
      DefaultDrawLevel,
      parent,
      renderRect,
      context.appearance.chromeFill(chrome),
      borderColor,
      borderWidth,
      radius,
    )
  context.drawChromeExtras(
    chrome, initChromeExtras(buttonRoot, renderRect, cornerRadius = radius)
  )
  context.addText(
    DefaultDrawLevel, parent, markRect, "×", markStyle, alignment = taCenter
  )

proc drawDocumentTab(
    tabs: DocumentTabs, context: DrawContext, parent: FigIdx, index: int
) =
  let
    item = tabs.xItems[index]
    style = tabs.effectiveStyle(item)
    rect = tabs.documentTabRect(index)
    viewport = tabs.tabViewportRect()
  if rect.intersection(viewport).isEmpty:
    return

  let
    selected = index == tabs.xSelectedIndex
    pressed = index == tabs.xPressedIndex and tabs.xPressedPart == dthTab
  var states: set[WidgetState]
  if selected:
    states.incl ssSelected
  if pressed:
    states.incl ssHighlighted
    states.incl ssPressed
  if not item.enabled():
    states.incl ssDisabled

  let
    styleContext = tabs.documentTabStyleContext(item, states)
    textColor = documentTabTextColor(item.enabled(), selected)
    tabTextStyle = context.appearance.tabTextStyle(styleContext, textColor)
    fillFallback = fill(tabFillColor(style, selected, pressed))
    fillValue = context.appearance.resolveFill(styleContext, fillFallback)
    borderColor = context.appearance.resolveColor(
      styleContext, StyleBorderColor, tabBorderColor(style, selected)
    )
    borderWidth =
      if style == dtsUnderline:
        0.0'f32
      else:
        context.appearance.resolveLength(styleContext, StyleBorderWidth, 1.0'f32)
    radius = min(
      context.appearance.resolveLength(
        styleContext, StyleCornerRadius, style.tabCornerRadius()
      ),
      rect.size.height / 2.0'f32,
    )
    highlightFill = context.appearance.resolveFill(
      styleContext, tabHighlightFill(item.enabled()), StyleHighlightFill
    )
    chrome = chromeContext(
      context.appearance.resolveChromeName(styleContext),
      crTab,
      cpFace,
      fillValue,
      states,
    )

  if style != dtsUnderline:
    let renderRect = context.renderRectFor(rect)
    let tabRoot = context.addRenderRectangle(
      DefaultDrawLevel,
      parent,
      renderRect,
      context.appearance.chromeFill(chrome),
      borderColor,
      borderWidth,
      radius,
      maskContent = true,
    )
    context.drawChromeExtras(
      chrome,
      initChromeExtras(
        tabRoot, renderRect, cornerRadius = radius, highlightFill = highlightFill
      ),
    )

  let accentRect =
    case style
    of dtsUnderline:
      initRect(
        rect.origin.x + 8.0'f32,
        rect.maxY - 3.0'f32,
        rect.size.width - 16.0'f32,
        3.0'f32,
      )
    else:
      initRect(rect.origin.x, rect.origin.y, 4.0'f32, rect.size.height)
  if selected or item.modified() or style == dtsUnderline:
    discard context.addRenderRectangle(
      DefaultDrawLevel,
      parent,
      context.renderRectFor(accentRect),
      fill(item.accentColor()),
      cornerRadius = if style == dtsUnderline: 2.0'f32 else: radius,
    )

  let
    close = tabs.closeRect(index)
    modifiedWidth = if item.modified(): 8.0'f32 else: 0.0'f32
    textInsets = tabTextStyle.insets
    textLeftInset = max(textInsets.left, DocumentTabHorizontalInset)
    textRightInset =
      if close.isEmpty:
        max(textInsets.right, DocumentTabHorizontalInset)
      else:
        DocumentTabCloseWidth + max(textInsets.right, 14.0'f32)
    textRect = initRect(
      rect.origin.x + textLeftInset + modifiedWidth,
      rect.origin.y,
      max(rect.size.width - textLeftInset - textRightInset - modifiedWidth, 0.0'f32),
      rect.size.height,
    )

  if item.modified():
    discard context.addRenderCircle(
      DefaultDrawLevel,
      parent,
      initPoint(rect.origin.x + 12.0'f32, rect.origin.y + rect.size.height / 2.0'f32),
      fill(item.accentColor()),
      3.0'f32,
    )
  context.addText(DefaultDrawLevel, parent, textRect, item.title(), tabTextStyle)
  tabs.drawCloseButton(
    context,
    parent,
    close,
    selected,
    index == tabs.xPressedIndex and tabs.xPressedPart == dthClose,
  )

proc drawScrollButton(
    tabs: DocumentTabs,
    context: DrawContext,
    button: DocumentTabScrollButton,
    pressed: bool,
) =
  let rect = tabs.scrollButtonRect(button)
  if rect.isEmpty:
    return
  let enabled =
    case button
    of dtsbPrevious:
      tabs.xScrollOffset > 0.01'f32
    of dtsbNext:
      tabs.xScrollOffset < tabs.maximumScrollOffset() - 0.01'f32
  var states: set[WidgetState]
  if pressed and enabled:
    states.incl ssHighlighted
    states.incl ssPressed
  if not enabled:
    states.incl ssDisabled
  let
    styleContext = tabs.documentTabButtonStyleContext(
      states, classes = ["document-tab-scroll-button"]
    )
    fillColor =
      if pressed and enabled:
        initColor(0.70, 0.74, 0.82, 1.0)
      else:
        initColor(0.82, 0.85, 0.90, 1.0)
    borderColor = initColor(0.58, 0.62, 0.70, 1.0)
    textColor =
      if enabled:
        initColor(0.12, 0.14, 0.18, 1.0)
      else:
        initColor(0.52, 0.55, 0.62, 1.0)
    label =
      case button
      of dtsbPrevious: "<"
      of dtsbNext: ">"
    fillValue = context.appearance.resolveFill(styleContext, fill(fillColor))
    resolvedBorderColor =
      context.appearance.resolveColor(styleContext, StyleBorderColor, borderColor)
    borderWidth =
      context.appearance.resolveLength(styleContext, StyleBorderWidth, 1.0'f32)
    radius = context.appearance.resolveLength(styleContext, StyleCornerRadius, 5.0'f32)
    markColor = context.appearance.resolveColor(styleContext, StyleMarkColor, textColor)
    markStyle = context.appearance.tabTextStyle(styleContext, markColor)
    chrome = chromeContext(
      context.appearance.resolveChromeName(styleContext),
      crButton,
      cpFace,
      fillValue,
      states,
    )
    renderRect = context.renderRectFor(rect)
    buttonRoot = context.addRenderRectangle(
      renderRect,
      context.appearance.chromeFill(chrome),
      resolvedBorderColor,
      borderWidth,
      radius,
    )
  context.drawChromeExtras(
    chrome, initChromeExtras(buttonRoot, renderRect, cornerRadius = radius)
  )
  context.addText(rect, label, markStyle, alignment = taCenter)

proc drawScroller(tabs: DocumentTabs, context: DrawContext) =
  if not tabs.xShowsHorizontalScroller or not tabs.hasOverflow():
    return
  let viewport = tabs.tabViewportRect()
  if viewport.size.width <= 0.0'f32:
    return
  let
    maxOffset = tabs.maximumScrollOffset()
    scrollStyle = context.appearance.resolveScrollViewStyle(
      controlStyle(
        srScroller,
        tabs.widgetStateSet(),
        id = tabs.styleId(),
        classes = tabs.styleClasses(),
      )
    )
    track = initRect(
      viewport.origin.x,
      tabs.bounds().maxY - DocumentTabScrollerHeight,
      viewport.size.width,
      DocumentTabScrollerHeight,
    )
    thumbWidth =
      max(viewport.size.width * viewport.size.width / tabs.contentWidth(), 18.0'f32)
    thumbX =
      if maxOffset <= 0.0'f32:
        track.origin.x
      else:
        track.origin.x + (track.size.width - thumbWidth) * tabs.xScrollOffset / maxOffset
    thumb = initRect(thumbX, track.origin.y, thumbWidth, track.size.height)
  discard context.addRenderRectangle(
    context.renderRectFor(track),
    scrollStyle.scrollerTrack.fill,
    scrollStyle.scrollerTrack.borderColor,
    scrollStyle.scrollerTrack.borderWidth,
    min(scrollStyle.scrollerTrack.cornerRadius, track.size.height / 2.0'f32),
  )
  discard context.addRenderRectangle(
    context.renderRectFor(thumb),
    scrollStyle.scrollerKnob.fill,
    scrollStyle.scrollerKnob.borderColor,
    scrollStyle.scrollerKnob.borderWidth,
    min(scrollStyle.scrollerKnob.cornerRadius, thumb.size.height / 2.0'f32),
  )

protocol DocumentTabsDrawing of ViewDrawingProtocol:
  method draw(tabs: DocumentTabs, context: DrawContext) =
    let
      bounds = tabs.bounds()
      barContext = tabs.documentTabBarStyleContext()
      barFill = context.appearance.resolveFill(barContext, fill(barFillColor()))
      barBorderColor = context.appearance.resolveColor(
        barContext, StyleBorderColor, initColor(0.58, 0.62, 0.70, 1.0)
      )
      barBorderWidth =
        context.appearance.resolveLength(barContext, StyleBorderWidth, 1.0'f32)
      barCornerRadius =
        context.appearance.resolveLength(barContext, StyleCornerRadius, 6.0'f32)
      barChrome = chromeContext(
        context.appearance.resolveChromeName(barContext), crTabPanel, cpFace, barFill
      )
      barRenderRect = context.renderRectFor(bounds)
      barRoot = context.addRenderRectangle(
        barRenderRect,
        context.appearance.chromeFill(barChrome),
        barBorderColor,
        barBorderWidth,
        barCornerRadius,
      )
    context.drawChromeExtras(
      barChrome,
      initChromeExtras(barRoot, barRenderRect, cornerRadius = barCornerRadius),
    )
    let viewport = tabs.tabViewportRect()
    let clipRoot = context.addRenderRectangle(
      context.renderRectFor(viewport),
      fill(initColor(0.0, 0.0, 0.0, 0.0)),
      maskContent = true,
    )
    for index in 0 ..< tabs.xItems.len:
      if index != tabs.xSelectedIndex:
        tabs.drawDocumentTab(context, clipRoot, index)
    if tabs.xSelectedIndex >= 0 and tabs.xSelectedIndex < tabs.xItems.len:
      tabs.drawDocumentTab(context, clipRoot, tabs.xSelectedIndex)

    tabs.drawScrollButton(context, dtsbPrevious, tabs.xPressedPart == dthPreviousButton)
    tabs.drawScrollButton(context, dtsbNext, tabs.xPressedPart == dthNextButton)
    tabs.drawScroller(context)

protocol DocumentTabsEventsProtocol of ResponderEventProtocol:
  method mouseDown(tabs: DocumentTabs, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false
    let hit = tabs.hitPart(event.location)
    case hit.part
    of dthPreviousButton:
      tabs.xPressedPart = dthPreviousButton
      discard tabs.scrollDocumentTabsBy(tabs.scrollButtonDelta(dtsbPrevious))
      tabs.setNeedsDisplay(true)
      true
    of dthNextButton:
      tabs.xPressedPart = dthNextButton
      discard tabs.scrollDocumentTabsBy(tabs.scrollButtonDelta(dtsbNext))
      tabs.setNeedsDisplay(true)
      true
    of dthTab, dthClose:
      if not tabs.xItems[hit.index].enabled():
        return false
      tabs.xPressedIndex = hit.index
      tabs.xPressedPart = hit.part
      tabs.xDraggingTab = false
      tabs.xDragStartPoint = event.location
      tabs.setNeedsDisplay(true)
      true
    else:
      false

  method mouseDragged(tabs: DocumentTabs, event: MouseEvent): bool =
    if tabs.xPressedIndex < 0:
      return false
    if tabs.xPressedPart != dthTab or not tabs.allowsTabReordering():
      return true
    let
      deltaX = abs(event.location.x - tabs.xDragStartPoint.x)
      deltaY = abs(event.location.y - tabs.xDragStartPoint.y)
    if not tabs.xDraggingTab and max(deltaX, deltaY) >= DocumentTabDragThreshold:
      tabs.xDraggingTab = true
    if tabs.xDraggingTab:
      let destination = tabs.tabMoveDestinationIndex(event.location)
      if destination >= 0:
        discard tabs.moveDocumentTabItem(tabs.xPressedIndex, destination)
      return true
    true

  method mouseUp(tabs: DocumentTabs, event: MouseEvent): bool =
    let
      pressed = tabs.xPressedIndex
      part = tabs.xPressedPart
      wasDragging = tabs.xDraggingTab
    tabs.xPressedIndex = -1
    tabs.xPressedPart = dthNone
    tabs.xDraggingTab = false

    case part
    of dthPreviousButton, dthNextButton:
      tabs.setNeedsDisplay(true)
      true
    of dthTab:
      if not wasDragging and pressed == tabs.documentTabIndexAtPoint(event.location):
        discard tabs.selectDocumentTabAtIndex(pressed)
      else:
        tabs.setNeedsDisplay(true)
      true
    of dthClose:
      let hit = tabs.hitPart(event.location)
      if not wasDragging and hit.part == dthClose and hit.index == pressed:
        discard tabs.closeDocumentTabAtIndex(pressed)
      else:
        tabs.setNeedsDisplay(true)
      true
    else:
      false

  method wantsForwardedScrollEvents(tabs: DocumentTabs, event: ScrollEvent): bool =
    if not tabs.hasOverflow():
      return true
    let
      wheelDelta =
        if event.deltaX != 0.0'f32:
          event.deltaX * tabs.lineScroll()
        elif event.deltaY != 0.0'f32:
          -event.deltaY * tabs.lineScroll()
        else:
          0.0'f32
      nextOffset = tabs.clampScrollOffset(tabs.xScrollOffset + wheelDelta)
    abs(nextOffset - tabs.xScrollOffset) <= 0.01'f32

  method scrollWheel(tabs: DocumentTabs, event: ScrollEvent): bool =
    if not tabs.hasOverflow():
      return false
    let wheelDelta =
      if event.deltaX != 0.0'f32:
        event.deltaX * tabs.lineScroll()
      elif event.deltaY != 0.0'f32:
        -event.deltaY * tabs.lineScroll()
      else:
        0.0'f32
    tabs.scrollDocumentTabsBy(wheelDelta)

  method keyDown(tabs: DocumentTabs, event: KeyEvent): bool =
    case event.key
    of keyArrowLeft:
      tabs.selectDocumentTabAtIndex(max(tabs.selectedIndex() - 1, 0))
    of keyArrowRight:
      tabs.selectDocumentTabAtIndex(min(tabs.selectedIndex() + 1, tabs.len() - 1))
    of keyHome:
      tabs.selectDocumentTabAtIndex(0)
    of keyEnd:
      tabs.selectDocumentTabAtIndex(tabs.len() - 1)
    else:
      false

protocol DocumentTabsLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(tabs: DocumentTabs): IntrinsicSize =
    let viewStyle = tabs.documentTabViewStyle()
    initIntrinsicSize(
      max(tabs.contentWidth(), 180.0'f32),
      max(DocumentTabBarHeight, viewStyle.tabHeight + 4.0'f32),
    )

protocol DocumentTabsAccessibility of AccessibilityProtocol:
  method accessibilityRole(tabs: DocumentTabs): AccessibilityRole =
    arTabGroup

  method accessibilityValue(tabs: DocumentTabs): string =
    let item = tabs.selectedDocumentTabItem()
    if item.isNil:
      ""
    else:
      item.title()

  method accessibilityTraits(tabs: DocumentTabs): AccessibilityTraits =
    result = tabs.xAccessibilityTraits + {atSelectable}
    if tabs.isFocused():
      result.incl atFocused

  method isAccessibilityElement(tabs: DocumentTabs): bool =
    true

proc initDocumentTabsFields*(tabs: DocumentTabs, frame: Rect = AutoRect) =
  initViewFields(tabs, frame)
  tabs.xSelectedIndex = -1
  tabs.xPressedIndex = -1
  tabs.xPressedPart = dthNone
  tabs.xAllowsClosing = true
  tabs.xAllowsTabReordering = true
  tabs.xShowsScrollButtons = true
  tabs.xShowsHorizontalScroller = false
  tabs.xDefaultTabStyle = dtsRounded
  tabs.xLineScroll = DocumentTabDefaultLineScroll
  tabs.background = initColor(0.0, 0.0, 0.0, 0.0)
  tabs.clipsToBounds = true
  tabs.setAcceptsFirstResponder(true)
  discard tabs.withProtocol(DocumentTabsDrawing)
  discard tabs.withProtocol(DocumentTabsEventsProtocol)
  discard tabs.withProtocol(DocumentTabsLayout)
  discard tabs.withProtocol(DocumentTabsAccessibility)
  tabs.applyInitialFrame(frame)

proc newDocumentTabs*(frame: Rect = AutoRect): DocumentTabs =
  result = DocumentTabs()
  initDocumentTabsFields(result, frame)
