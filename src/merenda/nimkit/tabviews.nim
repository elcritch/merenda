import std/options

import sigils/core

import ./drawing
import ./events
import ./selectors
import ./theme
import ./types
import ./views

export views

const
  DefaultTabHeight = 28.0'f32
  DefaultTabMinWidth = 72.0'f32
  DefaultTabMaxWidth = 180.0'f32
  TabHorizontalPadding = 14.0'f32
  TabInset = 8.0'f32
  TabGap = 1.0'f32
  ContentBorderWidth = 1.0'f32

type
  TabPosition* = enum
    tpTop
    tpBottom

  TabBarView = ref object of View
    xTabView: TabView

  TabViewItem* = ref object
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
    xTabPosition: TabPosition
    xDelegate: DynamicAgent
    xTabBar: TabBarView

proc syncSelectedContent(tabView: TabView)
proc selectTabViewItemAtIndex*(tabView: TabView, index: int): bool {.discardable.}
proc tabIndexAtBarPoint(tabView: TabView, point: Point): int
proc drawTab(tabView: TabView, context: DrawContext, index: int)
proc syncTabBarFrame(tabView: TabView)

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
  if item.isNil: "" else: item.xIdentifier

proc `identifier=`*(item: TabViewItem, identifier: string) =
  if not item.isNil:
    item.xIdentifier = identifier

proc label*(item: TabViewItem): string =
  if item.isNil: "" else: item.xLabel

proc `label=`*(item: TabViewItem, label: string) =
  if not item.isNil:
    item.xLabel = label

proc view*(item: TabViewItem): View =
  if item.isNil: nil else: item.xView

proc `view=`*(item: TabViewItem, view: View) =
  if not item.isNil:
    item.xView = view

proc enabled*(item: TabViewItem): bool =
  item.isNil or item.xEnabled

proc `enabled=`*(item: TabViewItem, enabled: bool) =
  if not item.isNil:
    item.xEnabled = enabled

proc toolTip*(item: TabViewItem): string =
  if item.isNil: "" else: item.xToolTip

proc `toolTip=`*(item: TabViewItem, toolTip: string) =
  if not item.isNil:
    item.xToolTip = toolTip

proc userInfo*(item: TabViewItem): DynamicAgent =
  if item.isNil: nil else: item.xUserInfo

proc `userInfo=`*(item: TabViewItem, userInfo: DynamicAgent) =
  if not item.isNil:
    item.xUserInfo = userInfo

proc len*(tabView: TabView): int =
  if tabView.isNil: 0 else: tabView.xItems.len

proc items*(tabView: TabView): lent seq[TabViewItem] =
  tabView.xItems

proc `[]`*(tabView: TabView, index: Natural): TabViewItem =
  tabView.xItems[index]

proc delegate*(tabView: TabView): DynamicAgent =
  if tabView.isNil: nil else: tabView.xDelegate

proc `delegate=`*(tabView: TabView, delegate: DynamicAgent) =
  if not tabView.isNil:
    tabView.xDelegate = delegate

proc `delegate=`*(tabView: TabView, delegate: Responder) =
  tabView.delegate = DynamicAgent(delegate)

proc selectedIndex*(tabView: TabView): int =
  if tabView.isNil: -1 else: tabView.xSelectedIndex

proc selectedTabViewItem*(tabView: TabView): TabViewItem =
  if tabView.isNil:
    return nil
  let index = tabView.xSelectedIndex
  if index < 0 or index >= tabView.xItems.len:
    return nil
  tabView.xItems[index]

proc tabPosition*(tabView: TabView): TabPosition =
  if tabView.isNil: tpTop else: tabView.xTabPosition

proc `tabPosition=`*(tabView: TabView, position: TabPosition) =
  if tabView.isNil or tabView.xTabPosition == position:
    return
  tabView.xTabPosition = position
  tabView.syncTabBarFrame()
  tabView.setNeedsLayout()
  tabView.setNeedsDisplay(true)

proc contentRect*(tabView: TabView): Rect =
  if tabView.isNil:
    return
  let bounds = tabView.bounds()
  case tabView.xTabPosition
  of tpTop:
    initRect(
      0.0,
      DefaultTabHeight - ContentBorderWidth,
      bounds.size.width,
      max(bounds.size.height - DefaultTabHeight + ContentBorderWidth, 0.0'f32),
    )
  of tpBottom:
    initRect(
      0.0,
      0.0,
      bounds.size.width,
      max(bounds.size.height - DefaultTabHeight + ContentBorderWidth, 0.0'f32),
    )

proc contentViewRect*(tabView: TabView): Rect =
  let rect = tabView.contentRect()
  case tabView.tabPosition()
  of tpTop:
    rect.inset(initEdgeInsets(18.0'f32, 16.0'f32, 14.0'f32, 16.0'f32))
  of tpBottom:
    rect.inset(initEdgeInsets(14.0'f32, 16.0'f32, 18.0'f32, 16.0'f32))

proc tabBarFrame(tabView: TabView): Rect =
  if tabView.isNil:
    return
  let bounds = tabView.bounds()
  case tabView.xTabPosition
  of tpTop:
    initRect(0.0, 0.0, bounds.size.width, DefaultTabHeight + ContentBorderWidth)
  of tpBottom:
    initRect(
      0.0,
      tabView.contentRect().maxY - ContentBorderWidth,
      bounds.size.width,
      DefaultTabHeight + ContentBorderWidth,
    )

proc tabWidth(item: TabViewItem): float32 =
  let textSize = textNaturalSize(
    if item.isNil:
      ""
    else:
      item.label()
  )
  min(
    max(textSize.width + TabHorizontalPadding * 2.0'f32, DefaultTabMinWidth),
    DefaultTabMaxWidth,
  )

proc tabRectInBar(tabView: TabView, index: int): Rect =
  if tabView.isNil or index < 0 or index >= tabView.xItems.len:
    return
  var x = TabInset
  for itemIndex in 0 ..< index:
    x += tabView.xItems[itemIndex].tabWidth() + TabGap

  let
    selected = index == tabView.xSelectedIndex
    width = tabView.xItems[index].tabWidth()
    height =
      if selected:
        DefaultTabHeight + ContentBorderWidth
      else:
        DefaultTabHeight - 4.0'f32
    y = if selected: 0.0'f32 else: 4.0'f32
  initRect(x, y, width, height)

proc tabRect*(tabView: TabView, index: int): Rect =
  let
    barFrame = tabView.tabBarFrame()
    localRect = tabView.tabRectInBar(index)
  initRect(
    barFrame.origin.x + localRect.origin.x,
    barFrame.origin.y + localRect.origin.y,
    localRect.size.width,
    localRect.size.height,
  )

proc tabIndexAtPoint*(tabView: TabView, point: Point): int =
  if tabView.isNil:
    return -1
  let
    barFrame = tabView.tabBarFrame()
    barPoint = point.localPoint(barFrame)
  tabView.tabIndexAtBarPoint(barPoint)

proc tabIndexAtBarPoint(tabView: TabView, point: Point): int =
  if tabView.isNil:
    return -1
  for index in 0 ..< tabView.xItems.len:
    if tabView.tabRectInBar(index).contains(point):
      return index
  -1

proc indexOfTabViewItem*(tabView: TabView, item: TabViewItem): int =
  if tabView.isNil or item.isNil:
    return -1
  tabView.xItems.find(item)

proc selectedContentView(tabView: TabView): View =
  let item = tabView.selectedTabViewItem()
  if item.isNil:
    nil
  else:
    item.view()

proc detachItemView(tabView: TabView, item: TabViewItem) =
  if tabView.isNil or item.isNil or item.xView.isNil:
    return
  if item.xView.superview() == View(tabView):
    item.xView.removeFromSuperview()

proc syncSelectedContent(tabView: TabView) =
  if tabView.isNil:
    return
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
  if not tabView.xTabBar.isNil:
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
  if tabView.isNil or index < 0 or index >= tabView.xItems.len:
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
  true

proc `selectedIndex=`*(tabView: TabView, index: int) =
  discard tabView.selectTabViewItemAtIndex(index)

proc selectTabViewItem*(tabView: TabView, item: TabViewItem): bool {.discardable.} =
  tabView.selectTabViewItemAtIndex(tabView.indexOfTabViewItem(item))

proc selectableIndexFrom(tabView: TabView, start, delta: int): int =
  if tabView.isNil or tabView.xItems.len == 0 or delta == 0:
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
  if tabView.isNil:
    return -1
  for index, item in tabView.xItems:
    if item.enabled():
      return index
  -1

proc lastSelectableIndex(tabView: TabView): int =
  if tabView.isNil:
    return -1
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
  if tabView.isNil or item.isNil:
    return nil
  tabView.xItems.add item
  if tabView.xSelectedIndex < 0 and item.enabled():
    tabView.xSelectedIndex = tabView.xItems.high
    tabView.syncSelectedContent()
  else:
    tabView.setNeedsDisplay(true)
  item

proc insertTabViewItem*(
    tabView: TabView, item: TabViewItem, index: Natural
): TabViewItem {.discardable.} =
  if tabView.isNil or item.isNil:
    return nil
  let boundedIndex = min(index.int, tabView.xItems.len)
  tabView.xItems.insert(item, boundedIndex)
  if tabView.xSelectedIndex >= boundedIndex:
    inc tabView.xSelectedIndex
  elif tabView.xSelectedIndex < 0 and item.enabled():
    tabView.xSelectedIndex = boundedIndex
    tabView.syncSelectedContent()
  tabView.setNeedsDisplay(true)
  item

proc removeTabViewItemAtIndex*(tabView: TabView, index: int): bool {.discardable.} =
  if tabView.isNil or index < 0 or index >= tabView.xItems.len:
    return
  let removingSelected = index == tabView.xSelectedIndex
  tabView.detachItemView(tabView.xItems[index])
  tabView.xItems.delete(index)
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

proc tabTextRect(rect: Rect): Rect =
  initRect(
    rect.origin.x + 8.0'f32,
    rect.origin.y + 2.0'f32,
    max(rect.size.width - 16.0'f32, 0.0'f32),
    max(rect.size.height - 4.0'f32, 0.0'f32),
  )

proc drawTab(tabView: TabView, context: DrawContext, index: int) =
  let
    item = tabView.xItems[index]
    selected = index == tabView.xSelectedIndex
    pressed = index == tabView.xPressedIndex
    enabled = item.enabled()
    rect = tabView.tabRectInBar(index)
    fillColor =
      if selected:
        initColor(0.98, 0.98, 0.96)
      elif pressed:
        initColor(0.78, 0.80, 0.84)
      else:
        initColor(0.86, 0.87, 0.89)
    borderColor =
      if selected:
        initColor(0.42, 0.44, 0.48)
      else:
        initColor(0.56, 0.58, 0.62)
    textColor =
      if enabled:
        initColor(0.08, 0.09, 0.11)
      else:
        initColor(0.50, 0.52, 0.56)

  discard context.addWindowRectangle(
    tabView.xTabBar.rectToWindow(rect), fillColor, borderColor, 1.0'f32, 5.0'f32
  )
  context.addText(rect.tabTextRect(), item.label(), textColor, alignment = taCenter)
  if selected and tabView.isFocusVisible:
    discard context.addWindowRectangle(
      tabView.xTabBar.rectToWindow(rect.inset(initEdgeInsets(3.0'f32))),
      initColor(0.0, 0.0, 0.0, 0.0),
      initColor(0.25, 0.45, 0.90),
      1.0'f32,
      3.0'f32,
    )

protocol TabBarDrawing of ViewDrawingProtocol:
  method draw(tabBar: TabBarView, context: DrawContext) =
    let tabView = tabBar.xTabView
    if tabView.isNil:
      return
    for index in 0 ..< tabView.xItems.len:
      if index != tabView.xSelectedIndex:
        tabView.drawTab(context, index)
    if tabView.xSelectedIndex >= 0 and tabView.xSelectedIndex < tabView.xItems.len:
      tabView.drawTab(context, tabView.xSelectedIndex)

protocol TabBarEvents of ResponderEventProtocol:
  method mouseDown(tabBar: TabBarView, event: MouseEvent): bool =
    let tabView = tabBar.xTabView
    if tabView.isNil or event.button != mbPrimary:
      return false
    let index = tabView.tabIndexAtBarPoint(event.location)
    if index >= 0 and tabView.xItems[index].enabled():
      tabView.xPressedIndex = index
      tabBar.setNeedsDisplay(true)
      return true
    false

  method mouseDragged(tabBar: TabBarView, event: MouseEvent): bool =
    let tabView = tabBar.xTabView
    if tabView.isNil or tabView.xPressedIndex < 0:
      return false
    let index = tabView.tabIndexAtBarPoint(event.location)
    let nextPressed = if index == tabView.xPressedIndex: index else: -1
    if nextPressed != tabView.xPressedIndex:
      tabView.xPressedIndex = nextPressed
      tabBar.setNeedsDisplay(true)
    true

  method mouseUp(tabBar: TabBarView, event: MouseEvent): bool =
    let tabView = tabBar.xTabView
    if tabView.isNil:
      return false
    let pressed = tabView.xPressedIndex
    if pressed < 0:
      return false
    tabView.xPressedIndex = -1
    if pressed == tabView.tabIndexAtBarPoint(event.location):
      discard tabView.selectTabViewItemAtIndex(pressed)
    else:
      tabBar.setNeedsDisplay(true)
    true

protocol TabViewDrawing of ViewDrawingProtocol:
  method draw(tabView: TabView, context: DrawContext) =
    let
      content = tabView.contentRect()
      panelFill = initColor(0.98, 0.98, 0.96)
      panelBorder = initColor(0.42, 0.44, 0.48)
    discard context.addWindowRectangle(
      tabView.rectToWindow(content), panelFill, panelBorder, ContentBorderWidth, 4.0'f32
    )

protocol TabViewLayout of ViewLayoutProtocol:
  method layoutSubviews(tabView: TabView) =
    tabView.syncTabBarFrame()
    tabView.syncSelectedContent()

  method layoutIntrinsicContentSize(tabView: TabView): IntrinsicSize =
    var tabWidthSum = TabInset * 2.0'f32
    for item in tabView.xItems:
      tabWidthSum += item.tabWidth() + TabGap
    initIntrinsicSize(max(tabWidthSum, 160.0'f32), 120.0'f32)

protocol TabViewEvents of ResponderEventProtocol:
  method keyDown(tabView: TabView, event: KeyEvent): bool =
    case event.key
    of keyArrowRight, keyArrowDown:
      return tabView.selectNextTabViewItem()
    of keyArrowLeft, keyArrowUp:
      return tabView.selectPreviousTabViewItem()
    of keyHome:
      return tabView.selectTabViewItemAtIndex(tabView.firstSelectableIndex())
    of keyEnd:
      return tabView.selectTabViewItemAtIndex(tabView.lastSelectableIndex())
    else:
      false

proc newTabBarView(tabView: TabView): TabBarView =
  result = TabBarView(xTabView: tabView)
  initViewFields(result)
  result.background = initColor(0.0, 0.0, 0.0, 0.0)
  discard result.withProtocol(TabBarDrawing)
  discard result.withProtocol(TabBarEvents)

proc syncTabBarFrame(tabView: TabView) =
  if not tabView.isNil and not tabView.xTabBar.isNil:
    tabView.xTabBar.frame = tabView.tabBarFrame()

proc initTabViewFields*(tabView: TabView, frame: Rect = AutoRect) =
  initViewFields(tabView, frame)
  tabView.xSelectedIndex = -1
  tabView.xPressedIndex = -1
  tabView.xTabPosition = tpTop
  tabView.xTabBar = newTabBarView(tabView)
  tabView.background = initColor(0.94, 0.95, 0.97, 0.0)
  tabView.clipsToBounds = true
  tabView.setAcceptsFirstResponder(true)
  discard tabView.withProto()
  discard tabView.withProtocol(TabViewDrawing)
  discard tabView.withProtocol(TabViewLayout)
  discard tabView.withProtocol(TabViewEvents)
  tabView.addSubview(tabView.xTabBar)
  tabView.syncTabBarFrame()
  tabView.applyInitialFrame(frame)
  tabView.syncTabBarFrame()

proc newTabView*(frame: Rect = AutoRect): TabView =
  result = TabView()
  initTabViewFields(result, frame)
