when defined(useNativeDynlib):
  from figdraw/dynlib import FigIdx
else:
  import figdraw

import sigils/core

import ../accessibility/accessibilityprotocols
import ../drawing
import ../foundation/events
import ../foundation/objectvalues
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
    xObjectValue: ObjectValue
    xRepresentedObject: DynamicAgent
    xToolTip: string
    xStyleId: string
    xStyleClasses: seq[string]
    xUserInfo: DynamicAgent

  DocumentTabModel* = object
    identifier*: string
    title*: string
    objectValue*: ObjectValue
    enabled*: bool
    hidden*: bool
    closeable*: bool
    modified*: bool
    style*: DocumentTabStyle
    accentColor*: Color
    styleId*: string
    styleClasses*: seq[string]
    tooltip*: string
    representedObject*: DynamicAgent
    userInfo*: DynamicAgent

  DocumentTabsState* = object
    selectedIdentifier*: string
    orderedIdentifiers*: seq[string]

  DocumentTabHitPart = enum
    dthNone
    dthTab
    dthClose
    dthPreviousButton
    dthNextButton

  DocumentTabs* = ref object of View
    xItems: seq[DocumentTabItem]
    xTabModels: seq[DocumentTabModel]
    xUsesTabModels: bool
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
    xDataSource: DynamicAgent
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
  DocumentTabAccentWidth = 2.0'f32
  DocumentTabAccentInset = 7.0'f32
  DocumentTabAccentLeadingInset = 2.0'f32
  DocumentTabAccentAlpha = 0.72'f32
  DocumentTabModifiedAccentAlpha = 0.52'f32
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

protocol DocumentTabsDataSource {.selectorScope: protocol.}:
  method documentTabCount*(tabs: DocumentTabs): int

  method documentTabModelAtIndex*(tabs: DocumentTabs, index: int): DocumentTabModel

  method indexOfDocumentTabModelIdentifier*(tabs: DocumentTabs, identifier: string): int

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
proc reloadData*(tabs: DocumentTabs)
proc clampScrollOffset(tabs: DocumentTabs, offset: float32): float32
proc maximumScrollOffset*(tabs: DocumentTabs): float32
proc tabViewportRect*(tabs: DocumentTabs): Rect
proc documentTabRect*(tabs: DocumentTabs, index: int): Rect
proc documentTabIndexAtPoint*(tabs: DocumentTabs, point: Point): int
proc insertDocumentTabItem*(
  tabs: DocumentTabs, item: DocumentTabItem, index: Natural
): DocumentTabItem {.discardable.}

proc documentTabModels*(tabs: DocumentTabs): seq[DocumentTabModel]
proc `documentTabModels=`*(tabs: DocumentTabs, models: openArray[DocumentTabModel])
proc removeDocumentTabAtIndex*(tabs: DocumentTabs, index: int): bool {.discardable.}
proc moveDocumentTabItem*(
  tabs: DocumentTabs, fromIndex, toIndex: int
): bool {.discardable.}

proc selectDocumentTabAtIndex*(tabs: DocumentTabs, index: int): bool {.discardable.}
proc selectedDocumentTabItem*(tabs: DocumentTabs): DocumentTabItem
proc indexOfDocumentTabIdentifier*(tabs: DocumentTabs, identifier: string): int
proc selectDocumentTabWithIdentifier*(
  tabs: DocumentTabs, identifier: string
): bool {.discardable.}

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
  item.xAccentColor = color(0.20, 0.45, 0.92, 1.0)
  item.xObjectValue = emptyObjectValue()

proc initDocumentTabItem*(
    title = "Untitled", identifier = "", closeable = true, style = dtsAutomatic
): DocumentTabItem =
  result = DocumentTabItem()
  result.initDocumentTabItemFields(title, identifier, closeable, style)

proc newDocumentTabItem*(
    title = "Untitled", identifier = "", closeable = true, style = dtsAutomatic
): DocumentTabItem =
  initDocumentTabItem(title, identifier, closeable, style)

proc initDocumentTabModel*(
    identifier = "",
    title = "Untitled",
    objectValue = emptyObjectValue(),
    enabled = true,
    hidden = false,
    closeable = true,
    modified = false,
    style = dtsAutomatic,
    accentColor = color(0.20, 0.45, 0.92, 1.0),
    styleId = "",
    styleClasses: openArray[string] = [],
    tooltip = "",
    representedObject: DynamicAgent = nil,
    userInfo: DynamicAgent = nil,
): DocumentTabModel =
  DocumentTabModel(
    identifier: identifier,
    title: title,
    objectValue: objectValue,
    enabled: enabled,
    hidden: hidden,
    closeable: closeable,
    modified: modified,
    style: style,
    accentColor: accentColor,
    styleId: styleId,
    styleClasses: @styleClasses,
    tooltip: tooltip,
    representedObject: representedObject,
    userInfo: userInfo,
  )

proc newDocumentTabItem*(model: DocumentTabModel): DocumentTabItem =
  result =
    newDocumentTabItem(model.title, model.identifier, model.closeable, model.style)
  result.xEnabled = model.enabled
  result.xModified = model.modified
  result.xAccentColor = model.accentColor
  result.xObjectValue = model.objectValue
  result.xRepresentedObject = model.representedObject
  result.xToolTip = model.tooltip
  result.xStyleId = model.styleId
  result.xStyleClasses = model.styleClasses
  result.xUserInfo = model.userInfo

proc documentTabModel*(item: DocumentTabItem): DocumentTabModel =
  initDocumentTabModel(
    identifier = item.xIdentifier,
    title = item.xTitle,
    objectValue = item.xObjectValue,
    enabled = item.xEnabled,
    closeable = item.xCloseable,
    modified = item.xModified,
    style = item.xStyle,
    accentColor = item.xAccentColor,
    styleId = item.xStyleId,
    styleClasses = item.xStyleClasses,
    tooltip = item.xToolTip,
    representedObject = item.xRepresentedObject,
    userInfo = item.xUserInfo,
  )

proc identifier*(item: DocumentTabItem): string =
  item.xIdentifier

proc `identifier=`*(item: DocumentTabItem, identifier: string) =
  item.xIdentifier = identifier

proc title*(item: DocumentTabItem): string =
  item.xTitle

proc `title=`*(item: DocumentTabItem, title: string) =
  item.xTitle = title

proc enabled*(item: DocumentTabItem): bool =
  item.xEnabled

proc `enabled=`*(item: DocumentTabItem, enabled: bool) =
  item.xEnabled = enabled

proc closeable*(item: DocumentTabItem): bool =
  item.xCloseable

proc `closeable=`*(item: DocumentTabItem, closeable: bool) =
  item.xCloseable = closeable

proc modified*(item: DocumentTabItem): bool =
  item.xModified

proc `modified=`*(item: DocumentTabItem, modified: bool) =
  item.xModified = modified

proc style*(item: DocumentTabItem): DocumentTabStyle =
  item.xStyle

proc `style=`*(item: DocumentTabItem, style: DocumentTabStyle) =
  item.xStyle = style

proc accentColor*(item: DocumentTabItem): Color =
  item.xAccentColor

proc `accentColor=`*(item: DocumentTabItem, color: Color) =
  item.xAccentColor = color

proc objectValue*(item: DocumentTabItem): ObjectValue =
  item.xObjectValue

proc `objectValue=`*(item: DocumentTabItem, value: ObjectValue) =
  item.xObjectValue = value

proc representedObject*(item: DocumentTabItem): DynamicAgent =
  item.xRepresentedObject

proc `representedObject=`*(item: DocumentTabItem, representedObject: DynamicAgent) =
  item.xRepresentedObject = representedObject

proc `representedObject=`*(item: DocumentTabItem, representedObject: Responder) =
  item.representedObject = DynamicAgent(representedObject)

proc toolTip*(item: DocumentTabItem): string =
  item.xToolTip

proc `toolTip=`*(item: DocumentTabItem, tooltip: string) =
  item.xToolTip = tooltip

proc styleId*(item: DocumentTabItem): string =
  item.xStyleId

proc `styleId=`*(item: DocumentTabItem, id: string) =
  item.xStyleId = id

proc styleClasses*(item: DocumentTabItem): seq[string] =
  item.xStyleClasses

proc `styleClasses=`*(item: DocumentTabItem, classes: openArray[string]) =
  item.xStyleClasses = @classes

proc userInfo*(item: DocumentTabItem): DynamicAgent =
  item.xUserInfo

proc `userInfo=`*(item: DocumentTabItem, userInfo: DynamicAgent) =
  item.xUserInfo = userInfo

proc len*(tabs: DocumentTabs): int =
  tabs.xItems.len

proc items*(tabs: DocumentTabs): lent seq[DocumentTabItem] =
  tabs.xItems

proc `[]`*(tabs: DocumentTabs, index: Natural): DocumentTabItem =
  tabs.xItems[index]

proc delegate*(tabs: DocumentTabs): DynamicAgent =
  tabs.xDelegate

proc `delegate=`*(tabs: DocumentTabs, delegate: DynamicAgent) =
  tabs.xDelegate = delegate

proc `delegate=`*(tabs: DocumentTabs, delegate: Responder) =
  tabs.delegate = DynamicAgent(delegate)

proc dataSource*(tabs: DocumentTabs): DynamicAgent =
  tabs.xDataSource

proc `dataSource=`*(tabs: DocumentTabs, dataSource: DynamicAgent) =
  if tabs.xDataSource == dataSource:
    return
  if not dataSource.isNil:
    discard dataSource.adopt(DocumentTabsDataSource)
  tabs.xDataSource = dataSource
  tabs.reloadData()

proc `dataSource=`*(tabs: DocumentTabs, dataSource: Responder) =
  tabs.dataSource = DynamicAgent(dataSource)

proc selectedIndex*(tabs: DocumentTabs): int =
  tabs.xSelectedIndex

proc `selectedIndex=`*(tabs: DocumentTabs, index: int) =
  discard tabs.selectDocumentTabAtIndex(index)

proc selectedDocumentTabIdentifier*(tabs: DocumentTabs): string =
  let item = tabs.selectedDocumentTabItem()
  if item.isNil:
    ""
  else:
    item.identifier()

proc `selectedDocumentTabIdentifier=`*(tabs: DocumentTabs, identifier: string) =
  discard tabs.selectDocumentTabWithIdentifier(identifier)

proc selectedDocumentTabItem*(tabs: DocumentTabs): DocumentTabItem =
  if tabs.xSelectedIndex < 0 or tabs.xSelectedIndex >= tabs.xItems.len:
    nil
  else:
    tabs.xItems[tabs.xSelectedIndex]

proc allowsClosing*(tabs: DocumentTabs): bool =
  tabs.xAllowsClosing

proc `allowsClosing=`*(tabs: DocumentTabs, allowed: bool) =
  if tabs.xAllowsClosing == allowed:
    return
  tabs.xAllowsClosing = allowed
  tabs.reloadDocumentTabs()

proc allowsTabReordering*(tabs: DocumentTabs): bool =
  tabs.xAllowsTabReordering

proc `allowsTabReordering=`*(tabs: DocumentTabs, allowed: bool) =
  if tabs.xAllowsTabReordering == allowed:
    return
  tabs.xAllowsTabReordering = allowed
  tabs.xDraggingTab = false
  tabs.xPressedPart = dthNone
  tabs.setNeedsDisplay(true)

proc showsScrollButtons*(tabs: DocumentTabs): bool =
  tabs.xShowsScrollButtons

proc `showsScrollButtons=`*(tabs: DocumentTabs, shows: bool) =
  if tabs.xShowsScrollButtons == shows:
    return
  tabs.xShowsScrollButtons = shows
  tabs.reloadDocumentTabs()

proc showsHorizontalScroller*(tabs: DocumentTabs): bool =
  tabs.xShowsHorizontalScroller

proc `showsHorizontalScroller=`*(tabs: DocumentTabs, shows: bool) =
  if tabs.xShowsHorizontalScroller == shows:
    return
  tabs.xShowsHorizontalScroller = shows
  tabs.setNeedsDisplay(true)

proc defaultTabStyle*(tabs: DocumentTabs): DocumentTabStyle =
  tabs.xDefaultTabStyle

proc `defaultTabStyle=`*(tabs: DocumentTabs, style: DocumentTabStyle) =
  if tabs.xDefaultTabStyle == style:
    return
  tabs.xDefaultTabStyle = if style == dtsAutomatic: dtsRounded else: style
  tabs.reloadDocumentTabs()

proc scrollOffset*(tabs: DocumentTabs): float32 =
  tabs.xScrollOffset

proc `scrollOffset=`*(tabs: DocumentTabs, offset: float32) =
  let clamped = tabs.clampScrollOffset(offset)
  if abs(tabs.xScrollOffset - clamped) <= 0.01'f32:
    return
  tabs.xScrollOffset = clamped
  tabs.setNeedsDisplay(true)
  emit tabs.documentTabsDidScroll(clamped)

proc lineScroll*(tabs: DocumentTabs): float32 =
  tabs.xLineScroll

proc `lineScroll=`*(tabs: DocumentTabs, value: float32) =
  tabs.xLineScroll = max(value, 1.0'f32)

proc documentTabAppearance(tabs: DocumentTabs): Appearance =
  tabs.effectiveAppearance()

proc mergedStyleClasses(
    tabs: DocumentTabs, item: DocumentTabItem = nil, extra: openArray[string] = []
): seq[string] =
  result.add tabs.styleClasses()
  if not item.isNil:
    result.add item.styleClasses()
  for class in extra:
    result.add class

proc documentTabStyleContext(
    tabs: DocumentTabs, item: DocumentTabItem, states: set[WidgetState] = {}
): StyleContext =
  var effectiveStates = states
  effectiveStates = effectiveStates + tabs.widgetStateSet()
  let id =
    if not item.isNil and item.styleId().len > 0:
      item.styleId()
    else:
      tabs.styleId()
  controlStyle(
    srDocumentTab, effectiveStates, id = id, classes = tabs.mergedStyleClasses(item)
  )

proc documentTabBarStyleContext(
    tabs: DocumentTabs, states: set[WidgetState] = {}
): StyleContext =
  var effectiveStates = states
  effectiveStates = effectiveStates + tabs.widgetStateSet()
  controlStyle(
    srDocumentTabBar,
    effectiveStates,
    id = tabs.styleId(),
    classes = tabs.mergedStyleClasses(),
  )

proc documentTabButtonStyleContext(
    tabs: DocumentTabs, states: set[WidgetState] = {}, classes: openArray[string] = []
): StyleContext =
  var effectiveStates = states
  effectiveStates = effectiveStates + tabs.widgetStateSet()
  controlStyle(
    srDocumentTabButton,
    effectiveStates,
    id = tabs.styleId(),
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
    color(0.50, 0.52, 0.56, 1.0)
  elif selected:
    color(0.07, 0.08, 0.10, 1.0)
  else:
    color(0.18, 0.20, 0.25, 1.0)

proc documentTabWidth(tabs: DocumentTabs, item: DocumentTabItem): float32 =
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
  for index, item in tabs.xItems:
    if index > 0:
      result += tabs.documentTabGap()
    result += tabs.documentTabWidth(item)

proc contentOverflowsFrame(tabs: DocumentTabs): bool =
  tabs.contentWidth() > tabs.bounds().size.width + 0.01'f32

proc hasOverflow*(tabs: DocumentTabs): bool =
  tabs.maximumScrollOffset() > 0.01'f32

proc scrollButtonRect*(tabs: DocumentTabs, button: DocumentTabScrollButton): Rect =
  if not tabs.xShowsScrollButtons or not tabs.hasOverflow():
    return
  let bounds = tabs.bounds()
  case button
  of dtsbPrevious:
    rect(0.0, 0.0, DocumentTabButtonWidth, bounds.size.height)
  of dtsbNext:
    rect(
      max(bounds.size.width - DocumentTabButtonWidth, 0.0'f32),
      0.0,
      min(DocumentTabButtonWidth, bounds.size.width),
      bounds.size.height,
    )

proc tabViewportRect*(tabs: DocumentTabs): Rect =
  let
    bounds = tabs.bounds()
    buttonInset =
      if tabs.xShowsScrollButtons and tabs.contentOverflowsFrame():
        DocumentTabButtonWidth
      else:
        0.0'f32
  rect(
    buttonInset,
    0.0,
    max(bounds.size.width - buttonInset * 2.0'f32, 0.0'f32),
    bounds.size.height,
  )

proc maximumScrollOffset*(tabs: DocumentTabs): float32 =
  max(tabs.contentWidth() - tabs.tabViewportRect().size.width, 0.0'f32)

proc clampScrollOffset(tabs: DocumentTabs, offset: float32): float32 =
  max(0.0'f32, min(offset, tabs.maximumScrollOffset()))

proc reloadDocumentTabs*(tabs: DocumentTabs) =
  tabs.xScrollOffset = tabs.clampScrollOffset(tabs.xScrollOffset)
  tabs.invalidateIntrinsicContentSize()
  tabs.setNeedsLayout()
  tabs.setNeedsDisplay(true)

proc contentTabRect(tabs: DocumentTabs, index: int): Rect =
  if index < 0 or index >= tabs.xItems.len:
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
  rect(x, y, tabs.documentTabWidth(item), height)

proc documentTabRect*(tabs: DocumentTabs, index: int): Rect =
  let
    viewport = tabs.tabViewportRect()
    contentRect = tabs.contentTabRect(index)
  rect(
    viewport.origin.x + contentRect.origin.x - tabs.xScrollOffset,
    contentRect.origin.y,
    contentRect.size.width,
    contentRect.size.height,
  )

proc closeRect(tabs: DocumentTabs, index: int): Rect =
  if index < 0 or index >= tabs.xItems.len:
    return
  let
    item = tabs.xItems[index]
    rect = tabs.documentTabRect(index)
  if not tabs.allowsClosing() or not item.closeable() or rect.size.width < 44.0'f32:
    return
  rect(
    rect.maxX - DocumentTabCloseWidth - 7.0'f32,
    rect.origin.y + max((rect.size.height - DocumentTabCloseWidth) / 2.0'f32, 0.0),
    DocumentTabCloseWidth,
    DocumentTabCloseWidth,
  )

proc scrollTabToVisible(tabs: DocumentTabs, index: int) =
  if index < 0 or index >= tabs.xItems.len:
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

proc documentTabIdentifiers*(tabs: DocumentTabs): seq[string] =
  for item in tabs.xItems:
    if item.identifier().len > 0:
      result.add item.identifier()

proc documentTabModels*(tabs: DocumentTabs): seq[DocumentTabModel] =
  if tabs.xUsesTabModels:
    return tabs.xTabModels
  for item in tabs.xItems:
    result.add item.documentTabModel()

proc clearDocumentTabItems(tabs: DocumentTabs) =
  tabs.xItems.setLen(0)

proc firstEnabledDocumentTabIndex(tabs: DocumentTabs): int =
  for index, item in tabs.xItems:
    if item.enabled():
      return index
  -1

proc restoreDocumentTabSelection(tabs: DocumentTabs, identifier: string) =
  var nextIndex = -1
  if identifier.len > 0:
    for index, item in tabs.xItems:
      if item.identifier() == identifier and item.enabled():
        nextIndex = index
        break
  if nextIndex < 0 and tabs.xSelectedIndex in 0 ..< tabs.xItems.len and
      tabs.xItems[tabs.xSelectedIndex].enabled():
    nextIndex = tabs.xSelectedIndex
  if nextIndex < 0:
    nextIndex = tabs.firstEnabledDocumentTabIndex()
  tabs.xSelectedIndex = nextIndex
  if nextIndex >= 0:
    tabs.scrollTabToVisible(nextIndex)

proc rebuildDocumentTabItemsFromModels(tabs: DocumentTabs, selectedIdentifier = "") =
  let selection =
    if selectedIdentifier.len > 0:
      selectedIdentifier
    else:
      tabs.selectedDocumentTabIdentifier()
  tabs.clearDocumentTabItems()
  for model in tabs.xTabModels:
    if not model.hidden:
      tabs.xItems.add newDocumentTabItem(model)
  tabs.restoreDocumentTabSelection(selection)
  tabs.reloadDocumentTabs()

proc `documentTabModels=`*(tabs: DocumentTabs, models: openArray[DocumentTabModel]) =
  let selected = tabs.selectedDocumentTabIdentifier()
  tabs.xTabModels = @models
  tabs.xUsesTabModels = true
  tabs.rebuildDocumentTabItemsFromModels(selected)

proc reloadData*(tabs: DocumentTabs) =
  if tabs.xDataSource.isNil:
    if tabs.xUsesTabModels:
      tabs.rebuildDocumentTabItemsFromModels()
    return

  let count = tabs.xDataSource.trySendLocal(documentTabCount(), tabs)
  if count.isNone:
    return
  let selected = tabs.selectedDocumentTabIdentifier()
  var models: seq[DocumentTabModel]
  for index in 0 ..< count.get():
    let model = tabs.xDataSource.trySendLocal(
      documentTabModelAtIndex(), (tabs: tabs, index: index)
    )
    if model.isSome:
      models.add model.get()
  tabs.xTabModels = models
  tabs.xUsesTabModels = true
  tabs.rebuildDocumentTabItemsFromModels(selected)

proc indexOfDocumentTabItem*(tabs: DocumentTabs, item: DocumentTabItem): int =
  if item.isNil:
    return -1
  tabs.xItems.find(item)

proc indexOfDocumentTabIdentifier*(tabs: DocumentTabs, identifier: string): int =
  if identifier.len == 0:
    return -1
  if not tabs.xDataSource.isNil:
    let found = tabs.xDataSource.trySendLocal(
      indexOfDocumentTabModelIdentifier(), (tabs: tabs, identifier: identifier)
    )
    if found.isSome:
      return found.get()
  for index, item in tabs.xItems:
    if item.identifier() == identifier:
      return index
  -1

proc documentTabItemWithIdentifier*(
    tabs: DocumentTabs, identifier: string
): DocumentTabItem =
  let index = tabs.indexOfDocumentTabIdentifier(identifier)
  if index >= 0 and index < tabs.xItems.len:
    tabs.xItems[index]
  else:
    nil

proc visibleModelIndex(tabs: DocumentTabs, visibleIndex: int): int =
  if visibleIndex < 0:
    return -1
  var current = 0
  for index, model in tabs.xTabModels:
    if not model.hidden:
      if current == visibleIndex:
        return index
      inc current
  -1

proc indexOfModelIdentifier(tabs: DocumentTabs, identifier: string): int =
  if identifier.len == 0:
    return -1
  for index, model in tabs.xTabModels:
    if model.identifier == identifier:
      return index
  -1

proc captureState*(tabs: DocumentTabs): DocumentTabsState =
  DocumentTabsState(
    selectedIdentifier: tabs.selectedDocumentTabIdentifier(),
    orderedIdentifiers: tabs.documentTabIdentifiers(),
  )

proc reorderDocumentTabItems(tabs: DocumentTabs, identifiers: openArray[string]) =
  if identifiers.len == 0:
    return
  var ordered: seq[DocumentTabItem]
  for identifier in identifiers:
    let index = tabs.indexOfDocumentTabIdentifier(identifier)
    if index >= 0:
      let item = tabs.xItems[index]
      if item notin ordered:
        ordered.add item
  for item in tabs.xItems:
    if item notin ordered:
      ordered.add item
  tabs.xItems = ordered

proc reorderDocumentTabModels(tabs: DocumentTabs, identifiers: openArray[string]) =
  if identifiers.len == 0:
    return
  var
    ordered: seq[DocumentTabModel]
    used: seq[int]
  for identifier in identifiers:
    let index = tabs.indexOfModelIdentifier(identifier)
    if index >= 0 and index notin used:
      ordered.add tabs.xTabModels[index]
      used.add index
  for index, model in tabs.xTabModels:
    if index notin used:
      ordered.add model
  tabs.xTabModels = ordered

proc restoreState*(tabs: DocumentTabs, state: DocumentTabsState) =
  if tabs.xUsesTabModels:
    tabs.reorderDocumentTabModels(state.orderedIdentifiers)
    tabs.rebuildDocumentTabItemsFromModels(state.selectedIdentifier)
  else:
    tabs.reorderDocumentTabItems(state.orderedIdentifiers)
    tabs.restoreDocumentTabSelection(state.selectedIdentifier)
    tabs.reloadDocumentTabs()

proc selectedItemAfterRemoval(tabs: DocumentTabs, removedIndex: int): int =
  if tabs.xItems.len == 0:
    return -1
  if tabs.xSelectedIndex == removedIndex:
    return min(removedIndex, tabs.xItems.high)
  if tabs.xSelectedIndex > removedIndex:
    return tabs.xSelectedIndex - 1
  tabs.xSelectedIndex

proc shouldSelect(tabs: DocumentTabs, item: DocumentTabItem): bool =
  if item.isNil or not item.enabled():
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
  if item.isNil or not tabs.allowsClosing() or not item.closeable():
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
  if item.isNil or not tabs.allowsTabReordering():
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
  if index < 0 or index >= tabs.xItems.len:
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

proc selectDocumentTabWithIdentifier*(
    tabs: DocumentTabs, identifier: string
): bool {.discardable.} =
  tabs.selectDocumentTabAtIndex(tabs.indexOfDocumentTabIdentifier(identifier))

proc addDocumentTabItem*(
    tabs: DocumentTabs, item: DocumentTabItem
): DocumentTabItem {.discardable.} =
  if item.isNil:
    return nil
  let index = tabs.xItems.len
  tabs.findUndoManager().registerCollectionInsert(
    proc(index: int) =
      discard tabs.removeDocumentTabAtIndex(index),
    index,
    "Insert Tab",
  )
  if tabs.xUsesTabModels:
    tabs.xTabModels.add item.documentTabModel()
  tabs.xItems.add item
  if tabs.xSelectedIndex < 0 and item.enabled():
    tabs.xSelectedIndex = tabs.xItems.high
  tabs.reloadDocumentTabs()
  if tabs.xSelectedIndex == tabs.xItems.high:
    tabs.scrollTabToVisible(tabs.xSelectedIndex)
  item

proc addDocumentTabItem*(
    tabs: DocumentTabs, model: DocumentTabModel
): DocumentTabItem {.discardable.} =
  tabs.xUsesTabModels = true
  tabs.xTabModels.add model
  tabs.rebuildDocumentTabItemsFromModels()
  if model.identifier.len > 0:
    return tabs.documentTabItemWithIdentifier(model.identifier)
  if not model.hidden:
    return tabs.xItems[^1]

proc insertDocumentTabItem*(
    tabs: DocumentTabs, item: DocumentTabItem, index: Natural
): DocumentTabItem {.discardable.} =
  if item.isNil:
    return nil
  let boundedIndex = min(index.int, tabs.xItems.len)
  tabs.findUndoManager().registerCollectionInsert(
    proc(index: int) =
      discard tabs.removeDocumentTabAtIndex(index),
    boundedIndex,
    "Insert Tab",
  )
  if tabs.xUsesTabModels:
    let visibleIndex = tabs.visibleModelIndex(boundedIndex)
    let modelIndex = if visibleIndex >= 0: visibleIndex else: tabs.xTabModels.len
    tabs.xTabModels.insert(item.documentTabModel(), modelIndex)
  tabs.xItems.insert(item, boundedIndex)
  if tabs.xSelectedIndex >= boundedIndex:
    inc tabs.xSelectedIndex
  elif tabs.xSelectedIndex < 0 and item.enabled():
    tabs.xSelectedIndex = boundedIndex
  tabs.reloadDocumentTabs()
  item

proc insertDocumentTabItem*(
    tabs: DocumentTabs, model: DocumentTabModel, index: Natural
): DocumentTabItem {.discardable.} =
  tabs.xUsesTabModels = true
  let modelIndex = max(0, min(index.int, tabs.xTabModels.len))
  tabs.xTabModels.insert(model, modelIndex)
  tabs.rebuildDocumentTabItemsFromModels()
  if model.identifier.len > 0:
    return tabs.documentTabItemWithIdentifier(model.identifier)
  if not model.hidden:
    let visibleIndex = max(0, min(index.int, tabs.xItems.high))
    return tabs.xItems[visibleIndex]

proc removeDocumentTabAtIndex*(tabs: DocumentTabs, index: int): bool {.discardable.} =
  if index < 0 or index >= tabs.xItems.len:
    return false
  let item = tabs.xItems[index]
  tabs.findUndoManager().registerCollectionRemove(
    proc(index: int, item: DocumentTabItem) =
      discard tabs.insertDocumentTabItem(item, index.Natural),
    index,
    item,
    "Remove Tab",
  )
  if tabs.xUsesTabModels:
    let modelIndex =
      if item.identifier().len > 0:
        tabs.indexOfModelIdentifier(item.identifier())
      else:
        tabs.visibleModelIndex(index)
    if modelIndex >= 0:
      tabs.xTabModels.delete(modelIndex)
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

proc removeDocumentTabWithIdentifier*(
    tabs: DocumentTabs, identifier: string
): bool {.discardable.} =
  tabs.removeDocumentTabAtIndex(tabs.indexOfDocumentTabIdentifier(identifier))

proc closeDocumentTabAtIndex*(tabs: DocumentTabs, index: int): bool {.discardable.} =
  if index < 0 or index >= tabs.xItems.len:
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
  tabs.xTabModels.setLen(0)
  tabs.xUsesTabModels = false
  tabs.xItems.setLen(0)
  tabs.xSelectedIndex = -1
  tabs.xPressedIndex = -1
  tabs.xScrollOffset = 0.0
  tabs.reloadDocumentTabs()

proc moveDocumentTabItem*(tabs: DocumentTabs, fromIndex, toIndex: int): bool =
  if fromIndex < 0 or fromIndex >= tabs.xItems.len:
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
  if tabs.xUsesTabModels:
    let
      fromModelIndex =
        if item.identifier().len > 0:
          tabs.indexOfModelIdentifier(item.identifier())
        else:
          tabs.visibleModelIndex(fromIndex)
      toModelIndex = tabs.visibleModelIndex(boundedIndex)
    if fromModelIndex >= 0 and toModelIndex >= 0:
      let model = tabs.xTabModels[fromModelIndex]
      tabs.xTabModels.delete(fromModelIndex)
      tabs.xTabModels.insert(model, max(0, min(toModelIndex, tabs.xTabModels.len)))
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
  if abs(delta) <= 0.01'f32:
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
  if not tabs.tabViewportRect().contains(point):
    return -1
  for index in 0 ..< tabs.xItems.len:
    let rect = tabs.documentTabRect(index)
    if not rect.intersection(tabs.tabViewportRect()).isEmpty and rect.contains(point):
      return index
  -1

proc tabMoveDestinationIndex(tabs: DocumentTabs, point: Point): int =
  if tabs.xItems.len == 0:
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
  color(0.88, 0.90, 0.94, 1.0)

func selectedFillColor(style: DocumentTabStyle): Color =
  case style
  of dtsPill:
    color(0.98, 0.98, 0.96, 1.0)
  of dtsUnderline:
    color(0.0, 0.0, 0.0, 0.0)
  of dtsCompact:
    color(0.95, 0.96, 0.98, 1.0)
  else:
    color(0.98, 0.98, 0.96, 1.0)

func tabFillColor(style: DocumentTabStyle, selected, pressed: bool): Color =
  if selected:
    return style.selectedFillColor()
  if pressed:
    return color(0.78, 0.82, 0.88, 1.0)
  case style
  of dtsUnderline:
    color(0.0, 0.0, 0.0, 0.0)
  of dtsCompact:
    color(0.82, 0.85, 0.90, 0.95)
  else:
    color(0.84, 0.87, 0.92, 0.95)

func tabBorderColor(style: DocumentTabStyle, selected: bool): Color =
  if style == dtsUnderline:
    color(0.0, 0.0, 0.0, 0.0)
  elif selected:
    color(0.42, 0.46, 0.54, 1.0)
  else:
    color(0.62, 0.66, 0.74, 1.0)

func tabCornerRadius(style: DocumentTabStyle): float32 =
  case style
  of dtsPill: 999.0'f32
  of dtsCompact: 5.0'f32
  of dtsUnderline: 0.0'f32
  else: 7.0'f32

func tabHighlightFill(enabled: bool): Fill =
  fill(color(1.0, 1.0, 1.0, if enabled: 0.46 else: 0.20))

func documentTabAccentColor(item: DocumentTabItem): Color =
  let
    source = item.accentColor()
    alphaScale =
      if item.modified(): DocumentTabModifiedAccentAlpha else: DocumentTabAccentAlpha
  color(source.r, source.g, source.b, source.a * alphaScale)

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
        color(0.52, 0.56, 0.62, 0.85)
      elif selected:
        color(0.72, 0.76, 0.82, 0.70)
      else:
        color(0.64, 0.68, 0.74, 0.50)
    textColor =
      if selected:
        color(0.12, 0.14, 0.18, 1.0)
      else:
        color(0.22, 0.24, 0.30, 1.0)
    fillValue = context.appearance.resolveFill(styleContext, fill(fillColor))
    borderColor = context.appearance.resolveColor(
      styleContext, StyleBorderColor, color(0.0, 0.0, 0.0, 0.0)
    )
    borderWidth =
      context.appearance.resolveLength(styleContext, StyleBorderWidth, 0.0'f32)
    radius = rect.size.width / 2.0'f32
    chrome = chromeContext(
      context.appearance.resolveChromeName(styleContext),
      crDocumentTabButton,
      cpFace,
      fillValue,
      states,
    )
    markColor = context.appearance.resolveColor(styleContext, StyleMarkColor, textColor)
    markStyle = context.appearance.tabTextStyle(styleContext, markColor)
    markRect =
      rect(rect.origin.x, rect.origin.y - 0.5'f32, rect.size.width, rect.size.height)
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
      crDocumentTab,
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

  if selected:
    let
      accentRect =
        case style
        of dtsUnderline:
          rect(
            rect.origin.x + 8.0'f32,
            rect.maxY - DocumentTabAccentWidth,
            max(rect.size.width - 16.0'f32, 0.0'f32),
            DocumentTabAccentWidth,
          )
        else:
          rect(
            rect.origin.x + max(borderWidth, 1.0'f32) + DocumentTabAccentLeadingInset,
            rect.origin.y + DocumentTabAccentInset,
            DocumentTabAccentWidth,
            max(rect.size.height - DocumentTabAccentInset * 2.0'f32, 0.0'f32),
          )
      accentRadius = DocumentTabAccentWidth / 2.0'f32
    discard context.addRenderRectangle(
      DefaultDrawLevel,
      parent,
      context.renderRectFor(accentRect),
      fill(item.documentTabAccentColor()),
      cornerRadius = accentRadius,
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
    textRect = rect(
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
        color(0.70, 0.74, 0.82, 1.0)
      else:
        color(0.82, 0.85, 0.90, 1.0)
    borderColor = color(0.58, 0.62, 0.70, 1.0)
    textColor =
      if enabled:
        color(0.12, 0.14, 0.18, 1.0)
      else:
        color(0.52, 0.55, 0.62, 1.0)
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
      crDocumentTabButton,
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
    track = rect(
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
    thumb = rect(thumbX, track.origin.y, thumbWidth, track.size.height)
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
        barContext, StyleBorderColor, color(0.58, 0.62, 0.70, 1.0)
      )
      barBorderWidth =
        context.appearance.resolveLength(barContext, StyleBorderWidth, 1.0'f32)
      barCornerRadius =
        context.appearance.resolveLength(barContext, StyleCornerRadius, 6.0'f32)
      barChrome = chromeContext(
        context.appearance.resolveChromeName(barContext),
        crDocumentTabBar,
        cpFace,
        barFill,
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
      fill(color(0.0, 0.0, 0.0, 0.0)),
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
  tabs.background = color(0.0, 0.0, 0.0, 0.0)
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
