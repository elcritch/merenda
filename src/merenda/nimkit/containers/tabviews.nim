import std/options

when defined(useNativeDynlib):
  from figdraw/dynlib import
    DirectionCorners, dcBottomLeft, dcBottomRight, dcTopLeft, dcTopRight
else:
  import figdraw

import sigils/core

import ../accessibility/accessibilityprotocols
import ../drawing
import ../foundation/events
import ../foundation/selectors
import ../themes
import ../foundation/types
import ../view/views

export views

type
  TabPosition* = enum
    tpTop
    tpBottom

  TabViewMode* = enum
    tvmInset
    tvmTraditional

  TabBarView = ref object of View
    xTabView: TabView

  TabViewItemChangeKind = enum
    tvickMetrics
    tvickView
    tvickDisplay

  TabViewItem* = ref object of DynamicAgent
    xIdentifier: string
    xLabel: string
    xView: View
    xEnabled: bool
    xToolTip: string
    xUserInfo: DynamicAgent

  TabView* = ref object of View
    xItems: seq[TabViewItem]
    xSelectedIndex: int
    xPressedIndex: int
    xAllowsTabDragging: bool
    xDraggingTab: bool
    xTabDragStartPoint: Point
    xTabPosition: TabPosition
    xTabMode: TabViewMode
    xDelegate: DynamicAgent
    xTabBar: TabBarView
    xObservedItems: seq[TabViewItem]
    xObservedContentViews: seq[View]

protocol TabViewItemEvents:
  proc tabViewItemDidChange(
    item: TabViewItem,
    changedItem: TabViewItem,
    kind: TabViewItemChangeKind,
    oldView: View,
  ) {.signal.}

proc syncSelectedContent(tabView: TabView)
proc selectTabViewItemAtIndex*(tabView: TabView, index: int): bool {.discardable.}
proc tabIndexAtBarPoint(tabView: TabView, point: Point): int
proc tabDragDestinationIndex(tabView: TabView, point: Point): int
proc moveTabViewItem(tabView: TabView, fromIndex, toIndex: int): bool {.discardable.}
proc drawTab(tabView: TabView, context: DrawContext, index: int)
proc syncTabBarFrame(tabView: TabView)
proc canHandleTabKeyNavigation(tabView: TabView): bool

proc tabStyle(tabView: TabView): TabViewStyle =
  tabView.effectiveAppearance().resolveTabViewStyle(controlStyle(srTab))

protocol TabViewDelegate {.selectorScope: protocol.}:
  method shouldSelectTabViewItem*(
    tabView: TabView, item: TabViewItem
  ): bool {.optional.}

  method didSelectTabViewItem*(tabView: TabView, item: TabViewItem) {.optional.}

proc initTabViewItemFields*(
    item: TabViewItem, label = "Tab", view: View = nil, identifier = ""
) =
  item.xIdentifier = identifier
  item.xLabel = label
  item.xView = view
  item.xEnabled = true

proc newTabViewItem*(label = "Tab", view: View = nil, identifier = ""): TabViewItem =
  result = TabViewItem()
  initTabViewItemFields(result, label, view, identifier)

proc identifier*(item: TabViewItem): string =
  item.xIdentifier

proc `identifier=`*(item: TabViewItem, identifier: string) =
  item.xIdentifier = identifier

proc label*(item: TabViewItem): string =
  item.xLabel

proc `label=`*(item: TabViewItem, label: string) =
  if item.xLabel == label:
    return
  item.xLabel = label
  emit item.tabViewItemDidChange(item, tvickMetrics, nil)

proc view*(item: TabViewItem): View =
  item.xView

proc `view=`*(item: TabViewItem, view: View) =
  if item.xView == view:
    return
  let oldView = item.xView
  item.xView = view
  emit item.tabViewItemDidChange(item, tvickView, oldView)

proc enabled*(item: TabViewItem): bool =
  item.xEnabled

proc `enabled=`*(item: TabViewItem, enabled: bool) =
  if item.xEnabled == enabled:
    return
  item.xEnabled = enabled
  emit item.tabViewItemDidChange(item, tvickDisplay, nil)

proc toolTip*(item: TabViewItem): string =
  item.xToolTip

proc `toolTip=`*(item: TabViewItem, toolTip: string) =
  item.xToolTip = toolTip

proc userInfo*(item: TabViewItem): DynamicAgent =
  item.xUserInfo

proc `userInfo=`*(item: TabViewItem, userInfo: DynamicAgent) =
  item.xUserInfo = userInfo

proc len*(tabView: TabView): int =
  tabView.xItems.len

proc items*(tabView: TabView): lent seq[TabViewItem] =
  tabView.xItems

proc `[]`*(tabView: TabView, index: Natural): TabViewItem =
  tabView.xItems[index]

proc delegate*(tabView: TabView): DynamicAgent =
  tabView.xDelegate

proc `delegate=`*(tabView: TabView, delegate: DynamicAgent) =
  tabView.xDelegate = delegate

proc `delegate=`*(tabView: TabView, delegate: Responder) =
  tabView.delegate = DynamicAgent(delegate)

proc selectedIndex*(tabView: TabView): int =
  tabView.xSelectedIndex

proc allowsTabDragging*(tabView: TabView): bool =
  tabView.xAllowsTabDragging

proc `allowsTabDragging=`*(tabView: TabView, allowed: bool) =
  if tabView.xAllowsTabDragging == allowed:
    return
  tabView.xAllowsTabDragging = allowed
  if not allowed:
    tabView.xDraggingTab = false
    tabView.xPressedIndex = -1
  tabView.xTabBar.setNeedsDisplay(true)

proc selectedTabViewItem*(tabView: TabView): TabViewItem =
  let index = tabView.xSelectedIndex
  if index < 0 or index >= tabView.xItems.len:
    return nil
  tabView.xItems[index]

proc tabPosition*(tabView: TabView): TabPosition =
  tabView.xTabPosition

proc `tabPosition=`*(tabView: TabView, position: TabPosition) =
  if tabView.xTabPosition == position:
    return
  tabView.xTabPosition = position
  tabView.syncTabBarFrame()
  tabView.setNeedsLayout()
  tabView.setNeedsDisplay(true)

proc tabMode*(tabView: TabView): TabViewMode =
  tabView.xTabMode

proc `tabMode=`*(tabView: TabView, mode: TabViewMode) =
  if tabView.xTabMode == mode:
    return
  tabView.xTabMode = mode
  tabView.invalidateIntrinsicContentSize()
  tabView.syncTabBarFrame()
  tabView.setNeedsLayout()
  tabView.setNeedsDisplay(true)
  tabView.xTabBar.setNeedsDisplay(true)

func tabPanelOffset(mode: TabViewMode, style: TabViewStyle): float32 =
  case mode
  of tvmInset:
    style.panelOverlap
  of tvmTraditional:
    style.tabHeight - style.contentBorderWidth

func tabBarOverlap(mode: TabViewMode, style: TabViewStyle): float32 =
  case mode
  of tvmInset: style.panelOverlap
  of tvmTraditional: style.contentBorderWidth

proc contentRect*(tabView: TabView): Rect =
  let
    bounds = tabView.bounds()
    style = tabView.tabStyle()
    panelOffset = tabView.xTabMode.tabPanelOffset(style)
  case tabView.xTabPosition
  of tpTop:
    rect(
      0.0,
      panelOffset,
      bounds.size.width,
      max(bounds.size.height - panelOffset, 0.0'f32),
    )
  of tpBottom:
    rect(0.0, 0.0, bounds.size.width, max(bounds.size.height - panelOffset, 0.0'f32))

func contentViewInsets(position: TabPosition): EdgeInsets =
  case position
  of tpTop:
    insets(18.0'f32, 16.0'f32, 14.0'f32, 16.0'f32)
  of tpBottom:
    insets(14.0'f32, 16.0'f32, 18.0'f32, 16.0'f32)

func contentChromeHeight(
    position: TabPosition, mode: TabViewMode, style: TabViewStyle
): float32 =
  mode.tabPanelOffset(style) + position.contentViewInsets().vertical

proc contentViewRect*(tabView: TabView): Rect =
  tabView.contentRect().inset(tabView.tabPosition().contentViewInsets())

proc tabBarFrame(tabView: TabView): Rect =
  let
    bounds = tabView.bounds()
    style = tabView.tabStyle()
    overlap = tabView.xTabMode.tabBarOverlap(style)
  case tabView.xTabPosition
  of tpTop:
    rect(0.0, 0.0, bounds.size.width, style.tabHeight + style.contentBorderWidth)
  of tpBottom:
    rect(
      0.0,
      tabView.contentRect().maxY - overlap,
      bounds.size.width,
      style.tabHeight + style.contentBorderWidth,
    )

func tabTextColor(enabled, selected: bool): Color =
  if not enabled:
    color(0.48, 0.50, 0.54)
  elif selected:
    color(0.07, 0.08, 0.10)
  else:
    color(0.14, 0.15, 0.18)

proc tabWidth(item: TabViewItem, style: TabViewStyle, textStyle: TextStyle): float32 =
  let textSize = textNaturalSize(item.label(), textStyle)
  min(
    max(textSize.width + style.tabHorizontalPadding * 2.0'f32, style.tabMinWidth),
    style.tabMaxWidth,
  )

proc tabGroupWidth(tabView: TabView, style: TabViewStyle): float32 =
  let textStyle = tabView.effectiveAppearance().resolveTextStyle(
      controlStyle(srTab), tabTextColor(enabled = true, selected = false), insets(0.0)
    )
  for item in tabView.xItems:
    result += item.tabWidth(style, textStyle)
  if tabView.xTabMode == tvmTraditional and tabView.xItems.len > 1:
    result += style.tabGap * float32(tabView.xItems.len - 1)

proc tabGroupWidth(tabView: TabView): float32 =
  tabView.tabGroupWidth(tabView.tabStyle())

proc tabRectInBar(tabView: TabView, index: int): Rect =
  if index < 0 or index >= tabView.xItems.len:
    return
  let
    style = tabView.tabStyle()
    textStyle = tabView.effectiveAppearance().resolveTextStyle(
        controlStyle(srTab), tabTextColor(enabled = true, selected = false), insets(0.0)
      )
    groupWidth = tabView.tabGroupWidth(style)
  var x =
    case tabView.xTabMode
    of tvmInset:
      max((tabView.tabBarFrame().size.width - groupWidth) / 2.0'f32, style.tabInset)
    of tvmTraditional:
      style.tabInset
  for itemIndex in 0 ..< index:
    x += tabView.xItems[itemIndex].tabWidth(style, textStyle)
    if tabView.xTabMode == tvmTraditional:
      x += style.tabGap

  let
    width = tabView.xItems[index].tabWidth(style, textStyle)
    selected = index == tabView.xSelectedIndex
    traditionalRise = max(style.tabHeight - style.tabSegmentHeight, 0.0'f32)
  case tabView.xTabMode
  of tvmInset:
    let y = traditionalRise / 2.0'f32
    rect(x, y, width, style.tabSegmentHeight)
  of tvmTraditional:
    let
      height =
        if selected:
          style.tabHeight + style.contentBorderWidth
        else:
          style.tabSegmentHeight
      y =
        case tabView.xTabPosition
        of tpTop:
          if selected: 0.0'f32 else: traditionalRise
        of tpBottom:
          0.0'f32
    rect(x, y, width, height)

proc tabRect*(tabView: TabView, index: int): Rect =
  let
    barFrame = tabView.tabBarFrame()
    localRect = tabView.tabRectInBar(index)
  rect(
    barFrame.origin.x + localRect.origin.x,
    barFrame.origin.y + localRect.origin.y,
    localRect.size.width,
    localRect.size.height,
  )

proc tabIndexAtPoint*(tabView: TabView, point: Point): int =
  let
    barFrame = tabView.tabBarFrame()
    barPoint = point.localPoint(barFrame)
  tabView.tabIndexAtBarPoint(barPoint)

proc tabIndexAtBarPoint(tabView: TabView, point: Point): int =
  for index in 0 ..< tabView.xItems.len:
    if tabView.tabRectInBar(index).contains(point):
      return index
  -1

proc tabDragDestinationIndex(tabView: TabView, point: Point): int =
  if tabView.xItems.len == 0:
    return -1
  for index in 0 ..< tabView.xItems.len:
    let rect = tabView.tabRectInBar(index)
    if point.x < rect.origin.x + rect.size.width * 0.5'f32:
      return index
  tabView.xItems.high

proc indexOfTabViewItem*(tabView: TabView, item: TabViewItem): int =
  if item.isNil:
    return -1
  tabView.xItems.find(item)

proc moveTabViewItem(tabView: TabView, fromIndex, toIndex: int): bool =
  if fromIndex notin 0 ..< tabView.xItems.len:
    return false
  let boundedIndex = max(0, min(toIndex, tabView.xItems.high))
  if fromIndex == boundedIndex:
    return false
  let
    selectedItem = tabView.selectedTabViewItem()
    item = tabView.xItems[fromIndex]
  tabView.xItems.delete(fromIndex)
  tabView.xItems.insert(item, boundedIndex)
  tabView.xPressedIndex = boundedIndex
  tabView.xSelectedIndex = tabView.indexOfTabViewItem(selectedItem)
  tabView.syncSelectedContent()
  tabView.setNeedsLayout()
  tabView.setNeedsDisplay(true)
  tabView.xTabBar.setNeedsDisplay(true)
  true

proc selectedContentView(tabView: TabView): View =
  let item = tabView.selectedTabViewItem()
  if item.isNil:
    nil
  else:
    item.view()

proc contentFittingSize(tabView: TabView): Size =
  for item in tabView.xItems:
    let content = item.view()
    if not content.isNil:
      let measured = content.fittingSize()
      result.width = max(result.width, measured.width)
      result.height = max(result.height, measured.height)

proc observesItem(tabView: TabView, item: TabViewItem): bool =
  for observed in tabView.xObservedItems:
    if observed == item:
      return true

proc observesContentView(tabView: TabView, content: View): bool =
  for observed in tabView.xObservedContentViews:
    if observed == content:
      return true

proc usesContentView(tabView: TabView, content: View): bool =
  if content.isNil:
    return false
  for item in tabView.xItems:
    if item.view() == content:
      return true

proc observeItem(tabView: TabView, item: TabViewItem)
proc unobserveItem(tabView: TabView, item: TabViewItem)

protocol TabViewContentLayoutSlots of ViewLayoutInputEvents:
  proc handleTabViewContentLayoutChange(
      tabView: TabView, reason: LayoutInvalidationReason
  ) {.slotFor: layoutInputChanged.} =
    if reason in {
      lirSubviews, lirHierarchy, lirDescendantIntrinsic, lirHidden, lirConstraints,
      lirIntrinsic, lirAppearanceMetrics, lirContainerMetrics,
    }:
      tabView.invalidateIntrinsicContentSize()

protocol TabViewItemChangeSlots of TabViewItemEvents:
  proc handleTabViewItemChange(
      tabView: TabView, item: TabViewItem, kind: TabViewItemChangeKind, oldView: View
  ) {.slotFor: tabViewItemDidChange.} =
    case kind
    of tvickMetrics:
      tabView.invalidateIntrinsicContentSize()
      tabView.setNeedsDisplay(true)
      tabView.xTabBar.setNeedsDisplay(true)
    of tvickView:
      if not oldView.isNil:
        if oldView.superview() == View(tabView):
          oldView.removeFromSuperview()
        if tabView.observesContentView(oldView) and not tabView.usesContentView(oldView):
          tabView.unobserveProtocol(oldView, TabViewContentLayoutSlots)
          let index = tabView.xObservedContentViews.find(oldView)
          if index >= 0:
            tabView.xObservedContentViews.delete(index)
      if not item.view().isNil and not tabView.observesContentView(item.view()):
        tabView.observeProtocol(item.view(), TabViewContentLayoutSlots)
        tabView.xObservedContentViews.add item.view()
      tabView.invalidateIntrinsicContentSize()
      tabView.syncSelectedContent()
      tabView.setNeedsLayout()
    of tvickDisplay:
      tabView.setNeedsDisplay(true)
      tabView.xTabBar.setNeedsDisplay(true)

proc observeItem(tabView: TabView, item: TabViewItem) =
  if item.isNil:
    return
  if not tabView.observesItem(item):
    tabView.observeProtocol(item, TabViewItemChangeSlots)
    tabView.xObservedItems.add item
  let content = item.view()
  if not content.isNil and not tabView.observesContentView(content):
    tabView.observeProtocol(content, TabViewContentLayoutSlots)
    tabView.xObservedContentViews.add content

proc unobserveItem(tabView: TabView, item: TabViewItem) =
  if item.isNil:
    return
  let itemIndex = tabView.xObservedItems.find(item)
  if itemIndex >= 0:
    tabView.unobserveProtocol(item, TabViewItemChangeSlots)
    tabView.xObservedItems.delete(itemIndex)
  let
    content = item.view()
    contentIndex = tabView.xObservedContentViews.find(content)
  if contentIndex >= 0 and not tabView.usesContentView(content):
    tabView.unobserveProtocol(content, TabViewContentLayoutSlots)
    tabView.xObservedContentViews.delete(contentIndex)

proc detachItemView(tabView: TabView, item: TabViewItem) =
  if item.isNil or item.xView.isNil:
    return
  if item.xView.superview() == View(tabView):
    item.xView.removeFromSuperview()

proc syncSelectedContent(tabView: TabView) =
  let selectedView = tabView.selectedContentView()
  for item in tabView.xItems:
    let content = item.view()
    if content.isNil:
      discard
    elif content == selectedView:
      if content.superview() != View(tabView):
        tabView.addSubview(content, positioned = svpBelow, relativeTo = tabView.xTabBar)
      content.hidden = false
      content.frame = tabView.contentViewRect()
    elif content.superview() == View(tabView):
      content.removeFromSuperview()
  tabView.setNeedsDisplay(true)
  tabView.xTabBar.setNeedsDisplay(true)

proc shouldSelect(tabView: TabView, item: TabViewItem): bool =
  if item.isNil or not item.enabled():
    return false
  let delegate = tabView.delegate()
  if delegate.isNil:
    return true

  delegate.trySendLocal(shouldSelectTabViewItem(), (tabView: tabView, item: item)).get(
    true
  )

proc didSelect(tabView: TabView, item: TabViewItem) =
  let delegate = tabView.delegate()
  if not delegate.isNil:
    discard delegate.sendLocalIfHandled(
      didSelectTabViewItem(), (tabView: tabView, item: item)
    )

proc selectTabViewItemAtIndex*(tabView: TabView, index: int): bool {.discardable.} =
  if index < 0 or index >= tabView.xItems.len:
    return
  if index == tabView.xSelectedIndex:
    return true
  let item = tabView.xItems[index]
  if not tabView.shouldSelect(item):
    return
  let oldItem = tabView.selectedTabViewItem()
  tabView.detachItemView(oldItem)
  tabView.xSelectedIndex = index
  tabView.syncSelectedContent()
  tabView.didSelect(item)
  tabView.postAccessibilityNotification(anSelectionChanged)
  true

proc `selectedIndex=`*(tabView: TabView, index: int) =
  discard tabView.selectTabViewItemAtIndex(index)

proc selectTabViewItem*(tabView: TabView, item: TabViewItem): bool {.discardable.} =
  tabView.selectTabViewItemAtIndex(tabView.indexOfTabViewItem(item))

proc selectableIndexFrom(tabView: TabView, start, delta: int): int =
  if tabView.xItems.len == 0 or delta == 0:
    return -1
  var index = start
  for _ in 0 ..< tabView.xItems.len:
    index += delta
    if index < 0:
      index = tabView.xItems.high
    elif index >= tabView.xItems.len:
      index = 0
    if tabView.xItems[index].enabled():
      return index
  -1

proc firstSelectableIndex(tabView: TabView): int =
  for index, item in tabView.xItems:
    if item.enabled():
      return index
  -1

proc lastSelectableIndex(tabView: TabView): int =
  for index in countdown(tabView.xItems.high, 0):
    if tabView.xItems[index].enabled():
      return index
  -1

proc selectNextTabViewItem*(tabView: TabView): bool {.discardable.} =
  let next = tabView.selectableIndexFrom(tabView.selectedIndex(), 1)
  tabView.selectTabViewItemAtIndex(next)

proc selectPreviousTabViewItem*(tabView: TabView): bool {.discardable.} =
  let previous = tabView.selectableIndexFrom(tabView.selectedIndex(), -1)
  tabView.selectTabViewItemAtIndex(previous)

proc addTabViewItem*(tabView: TabView, item: TabViewItem): TabViewItem {.discardable.} =
  if item.isNil:
    return nil
  tabView.xItems.add item
  tabView.observeItem(item)
  tabView.invalidateIntrinsicContentSize()
  if tabView.xSelectedIndex < 0 and item.enabled():
    tabView.xSelectedIndex = tabView.xItems.high
    tabView.syncSelectedContent()
  else:
    tabView.setNeedsDisplay(true)
  item

proc insertTabViewItem*(
    tabView: TabView, item: TabViewItem, index: Natural
): TabViewItem {.discardable.} =
  if item.isNil:
    return nil
  let boundedIndex = min(index.int, tabView.xItems.len)
  tabView.xItems.insert(item, boundedIndex)
  tabView.observeItem(item)
  tabView.invalidateIntrinsicContentSize()
  if tabView.xSelectedIndex >= boundedIndex:
    inc tabView.xSelectedIndex
  elif tabView.xSelectedIndex < 0 and item.enabled():
    tabView.xSelectedIndex = boundedIndex
    tabView.syncSelectedContent()
  tabView.setNeedsDisplay(true)
  item

proc removeTabViewItemAtIndex*(tabView: TabView, index: int): bool {.discardable.} =
  if index < 0 or index >= tabView.xItems.len:
    return
  let removingSelected = index == tabView.xSelectedIndex
  let removedItem = tabView.xItems[index]
  tabView.detachItemView(removedItem)
  tabView.xItems.delete(index)
  if tabView.indexOfTabViewItem(removedItem) < 0:
    tabView.unobserveItem(removedItem)
  tabView.invalidateIntrinsicContentSize()
  if tabView.xItems.len == 0:
    tabView.xSelectedIndex = -1
  elif removingSelected:
    tabView.xSelectedIndex = min(index, tabView.xItems.high)
    if not tabView.xItems[tabView.xSelectedIndex].enabled():
      tabView.xSelectedIndex = tabView.firstSelectableIndex()
  elif tabView.xSelectedIndex > index:
    dec tabView.xSelectedIndex
  tabView.syncSelectedContent()
  true

proc removeTabViewItem*(tabView: TabView, item: TabViewItem): bool {.discardable.} =
  tabView.removeTabViewItemAtIndex(tabView.indexOfTabViewItem(item))

proc tabTextRect(rect: Rect, insets: EdgeInsets): Rect =
  rect.inset(insets)

func panelFillColor(): Color =
  color(0.98, 0.98, 0.96)

func panelFill(): Fill =
  fill(panelFillColor())

func panelBorderColor(): Color =
  color(0.42, 0.44, 0.48)

func tabBorderColor(selected, enabled: bool): Color =
  if selected:
    panelBorderColor()
  elif enabled:
    color(0.55, 0.57, 0.62)
  else:
    color(0.65, 0.67, 0.70)

func tabHighlightFill(enabled: bool): Fill =
  fill(color(1.0, 1.0, 1.0, if enabled: 0.68 else: 0.30))

func chromeEdge(position: TabPosition): ChromeEdge =
  case position
  of tpTop: ceTop
  of tpBottom: ceBottom

func tabRoundedCorners(
    mode: TabViewMode, position: TabPosition, index, lastIndex: int
): set[DirectionCorners] =
  case mode
  of tvmInset:
    if index == 0:
      result.incl dcTopLeft
      result.incl dcBottomLeft
    if index == lastIndex:
      result.incl dcTopRight
      result.incl dcBottomRight
  of tvmTraditional:
    case position
    of tpTop:
      result = {dcTopLeft, dcTopRight}
    of tpBottom:
      result = {dcBottomLeft, dcBottomRight}

proc drawTab(tabView: TabView, context: DrawContext, index: int) =
  let
    item = tabView.xItems[index]
    selected = index == tabView.xSelectedIndex
    pressed = index == tabView.xPressedIndex
    enabled = item.enabled()
    rect = tabView.tabRectInBar(index)
    renderRect = context.renderRectFor(rect)

  var states: set[WidgetState]
  if selected:
    states.incl ssSelected
  if pressed:
    states.incl ssHighlighted
  if not enabled:
    states.incl ssDisabled

  let
    panelStyleContext = controlStyle(srTabPanel)
    panelFillValue = context.appearance.resolveFill(panelStyleContext, panelFill())
    tabStyleContext = controlStyle(srTab, states)
    tabFillValue = context.appearance.resolveFill(tabStyleContext, panelFillValue)
    tabBorderValue = context.appearance.resolveColor(
      tabStyleContext, StyleBorderColor, tabBorderColor(selected, enabled)
    )
    tabBorderWidth =
      context.appearance.resolveLength(tabStyleContext, StyleBorderWidth, 1.0'f32)
    tabViewStyle = context.appearance.resolveTabViewStyle(tabStyleContext)
    tabCornerRadius = tabViewStyle.tabCornerRadius
    tabTextInsets = context.appearance.resolveInsets(
      tabStyleContext, StyleTextInsets, insets(1.0'f32, 8.0'f32)
    )
    tabTextValue = context.appearance.resolveColor(
      tabStyleContext, StyleTextColor, tabTextColor(enabled, selected)
    )
    tabTextStyle =
      context.appearance.resolveTextStyle(tabStyleContext, tabTextValue, tabTextInsets)
    tabHighlightFillValue = context.appearance.resolveFill(
      tabStyleContext, tabHighlightFill(enabled), StyleHighlightFill
    )
    tabChrome = chromeContext(
      context.appearance.resolveChromeName(tabStyleContext),
      crTab,
      cpFace,
      tabFillValue,
      states,
    )

  let tabRoot = context.addRenderRectangle(
    renderRect,
    context.appearance.chromeFill(tabChrome),
    tabBorderValue,
    tabBorderWidth,
    tabCornerRadius,
    maskContent = true,
    roundedCorners = tabRoundedCorners(
      tabView.xTabMode, tabView.xTabPosition, index, tabView.xItems.high
    ),
  )
  let chromeEdge =
    if tabView.xTabMode == tvmTraditional:
      tabView.tabPosition.chromeEdge()
    else:
      ceNone
  context.drawChromeExtras(
    tabChrome,
    initChromeExtras(
      tabRoot,
      renderRect,
      cornerRadius = tabCornerRadius,
      edge = chromeEdge,
      seamFill = panelFillValue,
      highlightFill = tabHighlightFillValue,
    ),
  )
  context.addText(
    rect.tabTextRect(tabTextInsets), item.label(), tabTextStyle, alignment = taCenter
  )
  if selected and tabView.isFocusVisible:
    let focusRingColor = context.appearance.resolveColor(
      tabStyleContext, StyleFocusRingColor, color(0.25, 0.45, 0.90)
    )
    discard context.addRenderRectangle(
      context.renderRectFor(rect.inset(insets(3.0'f32))),
      color(0.0, 0.0, 0.0, 0.0),
      focusRingColor,
      1.0'f32,
      3.0'f32,
    )

protocol TabBarDrawing of ViewDrawingProtocol:
  method draw(tabBar: TabBarView, context: DrawContext) =
    let tabView = tabBar.xTabView
    for index in 0 ..< tabView.xItems.len:
      if index != tabView.xSelectedIndex:
        tabView.drawTab(context, index)
    if tabView.xSelectedIndex >= 0 and tabView.xSelectedIndex < tabView.xItems.len:
      tabView.drawTab(context, tabView.xSelectedIndex)

protocol TabBarEvents of ResponderEventProtocol:
  method mouseDown(tabBar: TabBarView, event: MouseEvent): bool =
    let tabView = tabBar.xTabView
    if event.button != mbPrimary:
      return false
    let index = tabView.tabIndexAtBarPoint(event.location)
    if index >= 0 and tabView.xItems[index].enabled():
      tabView.xPressedIndex = index
      tabView.xDraggingTab = false
      tabView.xTabDragStartPoint = event.location
      tabBar.setNeedsDisplay(true)
      return true
    false

  method mouseDragged(tabBar: TabBarView, event: MouseEvent): bool =
    let tabView = tabBar.xTabView
    if tabView.xPressedIndex < 0:
      return false
    if tabView.allowsTabDragging():
      let
        deltaX = abs(event.location.x - tabView.xTabDragStartPoint.x)
        deltaY = abs(event.location.y - tabView.xTabDragStartPoint.y)
      if not tabView.xDraggingTab and max(deltaX, deltaY) >= 3.0'f32:
        tabView.xDraggingTab = true
      if tabView.xDraggingTab:
        discard tabView.moveTabViewItem(
          tabView.xPressedIndex, tabView.tabDragDestinationIndex(event.location)
        )
        tabBar.setNeedsDisplay(true)
        return true
    let index = tabView.tabIndexAtBarPoint(event.location)
    let nextPressed = if index == tabView.xPressedIndex: index else: -1
    if nextPressed != tabView.xPressedIndex:
      tabView.xPressedIndex = nextPressed
      tabBar.setNeedsDisplay(true)
    true

  method mouseUp(tabBar: TabBarView, event: MouseEvent): bool =
    let tabView = tabBar.xTabView
    let pressed = tabView.xPressedIndex
    let wasDragging = tabView.xDraggingTab
    tabView.xDraggingTab = false
    if pressed < 0:
      return false
    tabView.xPressedIndex = -1
    if wasDragging:
      tabBar.setNeedsDisplay(true)
      return true
    if pressed == tabView.tabIndexAtBarPoint(event.location):
      discard tabView.selectTabViewItemAtIndex(pressed)
    else:
      tabBar.setNeedsDisplay(true)
    true

protocol TabViewDrawing of ViewDrawingProtocol:
  method draw(tabView: TabView, context: DrawContext) =
    let
      content = tabView.contentRect()
      panelStyleContext = controlStyle(srTabPanel)
      fillValue = context.appearance.resolveFill(panelStyleContext, panelFill())
      borderColor = context.appearance.resolveColor(
        panelStyleContext, StyleBorderColor, panelBorderColor()
      )
      borderWidth = context.appearance.resolveLength(
        panelStyleContext, StyleBorderWidth, tabView.tabStyle().contentBorderWidth
      )
      cornerRadius = tabView.tabStyle().panelCornerRadius
      panelChrome = chromeContext(
        context.appearance.resolveChromeName(panelStyleContext),
        crTabPanel,
        cpFace,
        fillValue,
      )
      renderRect = context.renderRectFor(content)
      panelRoot = context.addRenderRectangle(
        renderRect,
        context.appearance.chromeFill(panelChrome),
        borderColor,
        borderWidth,
        cornerRadius,
      )
    context.drawChromeExtras(
      panelChrome, initChromeExtras(panelRoot, renderRect, cornerRadius = cornerRadius)
    )

protocol TabViewLayout of ViewLayoutProtocol:
  method layoutSubviews(tabView: TabView) =
    tabView.syncTabBarFrame()
    tabView.syncSelectedContent()

  method layoutIntrinsicContentSize(tabView: TabView): IntrinsicSize =
    let
      style = tabView.tabStyle()
      tabWidthSum = tabView.tabGroupWidth(style) + style.tabInset * 2.0'f32
      contentSize = tabView.contentFittingSize()
      contentInsets = tabView.tabPosition.contentViewInsets()
    initIntrinsicSize(
      max(max(tabWidthSum, contentSize.width + contentInsets.horizontal), 160.0'f32),
      max(
        120.0'f32,
        contentSize.height +
          contentChromeHeight(tabView.tabPosition, tabView.xTabMode, style),
      ),
    )

protocol TabViewEvents of ResponderEventProtocol:
  method keyDown(tabView: TabView, event: KeyEvent): bool =
    case event.key
    of keyArrowRight, keyArrowDown:
      if not tabView.canHandleTabKeyNavigation():
        return false
      return tabView.selectNextTabViewItem()
    of keyArrowLeft, keyArrowUp:
      if not tabView.canHandleTabKeyNavigation():
        return false
      return tabView.selectPreviousTabViewItem()
    of keyHome:
      if not tabView.canHandleTabKeyNavigation():
        return false
      return tabView.selectTabViewItemAtIndex(tabView.firstSelectableIndex())
    of keyEnd:
      if not tabView.canHandleTabKeyNavigation():
        return false
      return tabView.selectTabViewItemAtIndex(tabView.lastSelectableIndex())
    else:
      false

protocol TabViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(tabView: TabView): AccessibilityRole =
    arTabGroup

  method accessibilityValue(tabView: TabView): string =
    let item = tabView.selectedTabViewItem()
    if item.isNil:
      ""
    else:
      item.label()

  method accessibilityTraits(tabView: TabView): AccessibilityTraits =
    result = tabView.xAccessibilityTraits + {atSelectable}
    if ssDisabled in tabView.xWidgetStates:
      result.incl atDisabled
    if tabView.isFocused():
      result.incl atFocused

  method isAccessibilityElement(tabView: TabView): bool =
    true

proc canHandleTabKeyNavigation(tabView: TabView): bool =
  tabView.window().isNil or tabView.isFocused()

proc newTabBarView(tabView: TabView): TabBarView =
  result = TabBarView(xTabView: tabView)
  initViewFields(result)
  result.background = color(0.0, 0.0, 0.0, 0.0)
  discard result.withProtocol(TabBarDrawing)
  discard result.withProtocol(TabBarEvents)

proc syncTabBarFrame(tabView: TabView) =
  tabView.xTabBar.frame = tabView.tabBarFrame()

proc initTabViewFields*(tabView: TabView, frame: Rect = AutoRect) =
  initViewFields(tabView, frame)
  tabView.xSelectedIndex = -1
  tabView.xPressedIndex = -1
  tabView.xTabPosition = tpTop
  tabView.xTabMode = tvmInset
  tabView.xTabBar = newTabBarView(tabView)
  tabView.background = color(0.94, 0.95, 0.97, 0.0)
  tabView.clipsToBounds = true
  tabView.setAcceptsFirstResponder(true)
  discard tabView.withProto()
  discard tabView.withProtocol(TabViewDrawing)
  discard tabView.withProtocol(TabViewLayout)
  discard tabView.withProtocol(TabViewEvents)
  discard tabView.withProtocol(TabViewAccessibility)
  tabView.addSubview(tabView.xTabBar)
  tabView.syncTabBarFrame()
  tabView.applyInitialFrame(frame)
  tabView.syncTabBarFrame()

proc newTabView*(frame: Rect = AutoRect): TabView =
  result = TabView()
  initTabViewFields(result, frame)
