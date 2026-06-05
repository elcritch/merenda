from figdraw/figbasics import ZLevel
from figdraw/fignodes import FigIdx

import std/math

import ./controls
import ./scrollviews
import ./selectors
import ./theme
import ./types

type ListViewport* = object
  rows: ScrollViewport

type
  ListSelectionMode* = enum
    lsmNone
    lsmSingle

  ListRowState* = object
    index*: int
    text*: string
    selected*: bool
    highlighted*: bool
    enabled*: bool
    focused*: bool

  PopupListCountProc* = proc(): int {.closure.}
  PopupListMetricProc* = proc(): float32 {.closure.}
  PopupListBoolProc* = proc(): bool {.closure.}
  PopupListStringProc* = proc(): string {.closure.}
  PopupListClassesProc* = proc(): seq[string] {.closure.}
  PopupListItemTextProc* = proc(index: int): string {.closure.}
  PopupListItemProc* = proc(index: int) {.closure.}
  PopupListScrollProc* = proc(delta: int) {.closure.}
  PopupListKeyProc* = proc(event: KeyEvent) {.closure.}
  PopupListActionProc* = proc() {.closure.}

  PopupListData* = object
    itemCount*: PopupListCountProc
    visibleCount*: PopupListCountProc
    firstIndex*: PopupListCountProc
    selectedIndex*: PopupListCountProc
    highlightedIndex*: PopupListCountProc
    rowHeight*: PopupListMetricProc
    itemText*: PopupListItemTextProc
    enabled*: PopupListBoolProc
    focused*: PopupListBoolProc
    opened*: PopupListBoolProc
    styleId*: PopupListStringProc
    styleClasses*: PopupListClassesProc

  PopupListActions* = object
    highlight*: PopupListItemProc
    activate*: PopupListItemProc
    close*: PopupListActionProc
    scroll*: PopupListScrollProc
    keyDown*: PopupListKeyProc

  PopupListView* = ref object of View
    xData: PopupListData
    xActions: PopupListActions
    xTrackingItem: bool
    xPopupRole: StyleRole
    xItemRole: StyleRole

  ListContentView* = ref object of View
    xListView: ListView

  ListView* = ref object of Control
    xItems: seq[string]
    xSelectedIndex: int
    xHighlightedIndex: int
    xViewport: ListViewport
    xClipView: ClipView
    xContentView: ListContentView
    xRowHeight: float32
    xVisibleRows: int
    xSelectionMode: ListSelectionMode
    xTrackingItem: bool
    xListRole: StyleRole
    xItemRole: StyleRole

proc itemCount*(popupList: PopupListView): int
proc visibleItemCount*(popupList: PopupListView): int
proc firstIndex*(popupList: PopupListView): int
proc selectedIndex*(popupList: PopupListView): int
proc highlightedIndex*(popupList: PopupListView): int
proc rowHeight*(popupList: PopupListView): float32
proc itemText*(popupList: PopupListView, index: int): string
proc isEnabled*(popupList: PopupListView): bool
proc isFocused*(popupList: PopupListView): bool
proc isOpened*(popupList: PopupListView): bool
proc popupListScrollRows*(event: ScrollEvent): int
proc popupListItemRect*(
  popupList: PopupListView, popupBounds: Rect, itemIndex: int
): Rect

proc popupListItemIndexAtPoint*(
  popupList: PopupListView, popupBounds: Rect, point: Point
): int

proc popupListScrollIndicatorRect*(popupList: PopupListView, popupBounds: Rect): Rect
proc canScrollRows*(popupList: PopupListView, delta: int): bool
proc drawPopupList*(
  popupList: PopupListView,
  context: DrawContext,
  popupBounds: Rect,
  layer: ZLevel = DefaultDrawLevel,
  parent: FigIdx = (-1).FigIdx,
)

proc beginPopupListTracking*(popupList: PopupListView, popupBounds: Rect, point: Point)
proc trackPopupListPoint*(popupList: PopupListView, popupBounds: Rect, point: Point)
proc finishPopupListTracking*(
  popupList: PopupListView, popupBounds: Rect, point: Point, closeWhenDone = true
)

proc resetPopupListTracking*(popupList: PopupListView)
proc highlightItemAtPoint(popupList: PopupListView, popupBounds: Rect, point: Point)
proc activateItem(popupList: PopupListView, index: int)
proc close(popupList: PopupListView)
proc scrollBy(popupList: PopupListView, delta: int)
proc dispatchKeyDown(popupList: PopupListView, event: KeyEvent)

func normalizedRowHeight*(rowHeight: float32): float32
func visibleListItemCount*(itemCount, maxVisibleItems: int): int
func listScrollViewport*(firstIndex, itemCount, visibleCount: int): ScrollViewport
func clampFirstIndex*(firstIndex, itemCount, visibleCount: int): int
func firstIndex*(viewport: ListViewport): int
proc setFirstIndex*(viewport: var ListViewport, firstIndex: int)
proc `firstIndex=`*(viewport: var ListViewport, firstIndex: int)
proc normalize*(viewport: var ListViewport, itemCount, visibleCount: int)
proc reset*(viewport: var ListViewport, firstIndex = 0)
func canScrollBy*(viewport: ListViewport, delta, itemCount, visibleCount: int): bool
proc scrollToVisible*(
  viewport: var ListViewport, itemIndex, itemCount, visibleCount: int
)

proc scrollBy*(viewport: var ListViewport, delta, itemCount, visibleCount: int)

proc listView*(contentView: ListContentView): ListView
proc clipView*(listView: ListView): ClipView
proc contentView*(listView: ListView): ListContentView
proc listViewportSize(listView: ListView): Size
proc listViewportRect(listView: ListView): Rect
proc listContentOffset(listView: ListView): Point
proc setListContentOffset(listView: ListView, offset: Point, invalidate: bool)
proc listContentSize*(listView: ListView): Size
proc listContentItemRect*(contentView: ListContentView, itemIndex: int): Rect
proc listContentItemIndexAtPoint*(contentView: ListContentView, point: Point): int
proc tileListContent(listView: ListView)
proc drawListContent(contentView: ListContentView, context: DrawContext)
proc invalidateListRows(listView: ListView)
proc len*(listView: ListView): int
proc rowHeight*(listView: ListView): float32
proc itemAtIndex(listView: ListView, index: int): string
proc selectItemAtIndex(listView: ListView, index: int)
proc deselectItem(listView: ListView)
proc reloadData*(listView: ListView)
proc visibleItemCount*(listView: ListView): int
proc highlightedIndex*(listView: ListView): int
proc listItemRect*(listView: ListView, itemIndex: int): Rect
proc listItemIndexAtPoint*(listView: ListView, point: Point): int
proc listScrollIndicatorRect*(listView: ListView): Rect
proc scrollItemToVisible*(listView: ListView, itemIndex: int)
proc canScrollRows*(listView: ListView, delta: int): bool
proc scrollRows*(listView: ListView, delta: int)
proc setHighlightedIndex*(listView: ListView, index: int)
proc activateItemAtIndex*(listView: ListView, index: int)
proc handleListKeyDown(listView: ListView, event: KeyEvent)
proc listNaturalSize(listView: ListView): Size
proc drawListView(listView: ListView, context: DrawContext)
proc drawListRow(
  context: DrawContext,
  layer: ZLevel,
  parent: FigIdx,
  rect: Rect,
  row: ListRowState,
  itemRole: StyleRole,
  id = "",
  classes: seq[string] = @[],
)

protocol DefaultListContentViewDrawing of ViewDrawingProtocol:
  method draw(contentView: ListContentView, context: DrawContext) =
    contentView.drawListContent(context)

protocol DefaultListContentViewHitTesting of ViewProtocol:
  method pointInside(contentView: ListContentView, point: Point): bool =
    false

protocol DefaultListClipViewHitTesting of ViewProtocol:
  method pointInside(clipView: ClipView, point: Point): bool =
    false

protocol DefaultPopupListDrawing of ViewDrawingProtocol:
  method draw(popupList: PopupListView, context: DrawContext) =
    if popupList.isOpened():
      popupList.drawPopupList(context, popupList.bounds)

protocol DefaultPopupListEvents of ResponderEventProtocol:
  method mouseDown(popupList: PopupListView, event: MouseEvent) =
    if not popupList.isEnabled() or event.button != mbPrimary:
      return
    popupList.beginPopupListTracking(popupList.bounds, event.location)

  method mouseDragged(popupList: PopupListView, event: MouseEvent) =
    if popupList.isOpened():
      popupList.trackPopupListPoint(popupList.bounds, event.location)

  method mouseMoved(popupList: PopupListView, event: MouseEvent) =
    if popupList.isOpened():
      popupList.trackPopupListPoint(popupList.bounds, event.location)

  method mouseUp(popupList: PopupListView, event: MouseEvent) =
    if not popupList.isEnabled() or event.button != mbPrimary:
      return
    popupList.finishPopupListTracking(popupList.bounds, event.location)

  method wantsForwardedScrollEvents(
      popupList: PopupListView, event: ScrollEvent
  ): bool =
    not popupList.isOpened() or not popupList.canScrollRows(popupListScrollRows(event))

  method scrollWheel(popupList: PopupListView, event: ScrollEvent) =
    let delta = popupListScrollRows(event)
    if popupList.isOpened() and popupList.canScrollRows(delta):
      popupList.scrollBy(delta)

  method keyDown(popupList: PopupListView, event: KeyEvent) =
    popupList.dispatchKeyDown(event)

protocol DefaultListViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(listView: ListView): IntrinsicSize =
    initIntrinsicSize(listView.listNaturalSize())

  method layoutSubviews(listView: ListView) =
    listView.tileListContent()

protocol DefaultListViewDrawing of ViewDrawingProtocol:
  method draw(listView: ListView, context: DrawContext) =
    if listView.isNil:
      return
    listView.drawListView(context)

protocol DefaultListViewEvents of ResponderEventProtocol:
  method mouseDown(listView: ListView, event: MouseEvent) =
    if listView.isNil or not listView.isEnabled() or event.button != mbPrimary:
      return
    listView.xTrackingItem = true
    listView.setHighlightedIndex(listView.listItemIndexAtPoint(event.location))

  method mouseDragged(listView: ListView, event: MouseEvent) =
    if not listView.isNil and listView.isEnabled():
      listView.setHighlightedIndex(listView.listItemIndexAtPoint(event.location))

  method mouseMoved(listView: ListView, event: MouseEvent) =
    if not listView.isNil and listView.isEnabled():
      listView.setHighlightedIndex(listView.listItemIndexAtPoint(event.location))

  method mouseUp(listView: ListView, event: MouseEvent) =
    if listView.isNil or not listView.isEnabled() or event.button != mbPrimary:
      return
    let index =
      if listView.xTrackingItem:
        listView.listItemIndexAtPoint(event.location)
      else:
        -1
    listView.xTrackingItem = false
    if index >= 0:
      listView.activateItemAtIndex(index)
    listView.setNeedsDisplay(true)

  method wantsForwardedScrollEvents(listView: ListView, event: ScrollEvent): bool =
    listView.isNil or not listView.isEnabled() or
      not listView.canScrollRows(popupListScrollRows(event))

  method scrollWheel(listView: ListView, event: ScrollEvent) =
    let delta = popupListScrollRows(event)
    if not listView.isNil and listView.isEnabled() and listView.canScrollRows(delta):
      listView.scrollRows(delta)

  method keyDown(listView: ListView, event: KeyEvent) =
    listView.handleListKeyDown(event)

func normalizedRowHeight*(rowHeight: float32): float32 =
  max(rowHeight, 1.0'f32)

func visibleListItemCount*(itemCount, maxVisibleItems: int): int =
  if itemCount <= 0:
    return 0
  min(itemCount, max(maxVisibleItems, 1))

func maxFirstIndex*(itemCount, visibleCount: int): int =
  listScrollViewport(0, itemCount, visibleCount).maxScrollOffset().int

func listScrollViewport*(firstIndex, itemCount, visibleCount: int): ScrollViewport =
  result = initScrollViewport(
    firstIndex.float32, max(visibleCount, 0).float32, max(itemCount, 0).float32
  )
  result.offset = result.clampScrollOffset(result.offset)

func clampFirstIndex*(firstIndex, itemCount, visibleCount: int): int =
  listScrollViewport(firstIndex, itemCount, visibleCount).offset.int

func initListViewport*(firstIndex = 0): ListViewport =
  ListViewport(rows: initScrollViewport(firstIndex.float32, 0.0, 0.0))

func firstIndex*(viewport: ListViewport): int =
  max(viewport.rows.offset.int, 0)

proc setFirstIndex*(viewport: var ListViewport, firstIndex: int) =
  viewport.rows.offset = max(firstIndex, 0).float32

proc `firstIndex=`*(viewport: var ListViewport, firstIndex: int) =
  viewport.setFirstIndex(firstIndex)

proc updateRows(viewport: var ListViewport, itemCount, visibleCount: int) =
  viewport.rows.visibleExtent = max(visibleCount, 0).float32
  viewport.rows.contentExtent = max(itemCount, 0).float32
  viewport.rows.offset = viewport.rows.clampScrollOffset(viewport.rows.offset)

func canScrollBy*(viewport: ListViewport, delta, itemCount, visibleCount: int): bool =
  if delta == 0:
    return false
  listScrollViewport(viewport.firstIndex, itemCount, visibleCount).canScrollBy(
    delta.float32
  )

func hasHiddenListItems*(itemCount, visibleCount: int): bool =
  itemCount > max(visibleCount, 0)

func listScrollIndicatorRect*(
    popup: Rect, firstIndex, visibleCount, itemCount: int
): Rect =
  if popup.isEmpty or visibleCount <= 0 or
      not hasHiddenListItems(itemCount, visibleCount):
    return initRect(popup.origin.x, popup.origin.y, 0.0, 0.0)

  let
    trackInset = 3.0'f32
    trackWidth = 3.0'f32
    trackHeight = max(popup.size.height - trackInset * 2.0'f32, 0.0'f32)
  if trackHeight <= 0.0'f32:
    return initRect(popup.origin.x, popup.origin.y, 0.0, 0.0)

  let
    rowViewport = listScrollViewport(firstIndex, itemCount, visibleCount)
    lastFirst = rowViewport.maxScrollOffset()
    thumbHeight = min(
      max(trackHeight * visibleCount.float32 / itemCount.float32, 8.0'f32), trackHeight
    )
    travel = max(trackHeight - thumbHeight, 0.0'f32)
    progress =
      if lastFirst <= 0.0'f32:
        0.0'f32
      else:
        rowViewport.offset / lastFirst

  initRect(
    popup.maxX - trackInset - trackWidth,
    popup.origin.y + trackInset + travel * progress,
    trackWidth,
    thumbHeight,
  )

proc normalize*(viewport: var ListViewport, itemCount, visibleCount: int) =
  viewport.updateRows(itemCount, visibleCount)

proc reset*(viewport: var ListViewport, firstIndex = 0) =
  viewport.firstIndex = firstIndex

proc scrollToVisible*(
    viewport: var ListViewport, itemIndex, itemCount, visibleCount: int
) =
  viewport.normalize(itemCount, visibleCount)
  if itemIndex < 0 or visibleCount <= 0:
    return
  if itemIndex < viewport.firstIndex:
    viewport.firstIndex = itemIndex
  elif itemIndex >= viewport.firstIndex + visibleCount:
    viewport.firstIndex = itemIndex - visibleCount + 1
  viewport.normalize(itemCount, visibleCount)

proc scrollBy*(viewport: var ListViewport, delta, itemCount, visibleCount: int) =
  if delta == 0:
    return
  viewport.updateRows(itemCount, visibleCount)
  viewport.rows.offset = viewport.rows.scrolledBy(delta.float32)

func listPopupRect*(
    bounds: Rect, itemCount, maxVisibleItems: int, rowHeight: float32
): Rect =
  let visible = visibleListItemCount(itemCount, maxVisibleItems)
  if visible <= 0:
    return initRect(bounds.origin.x, bounds.maxY, 0.0, 0.0)
  initRect(
    bounds.origin.x,
    bounds.maxY,
    bounds.size.width,
    rowHeight.normalizedRowHeight() * visible.float32 + 2.0'f32,
  )

func listItemRect*(
    popup: Rect, firstIndex, visibleCount, itemIndex: int, rowHeight: float32
): Rect =
  let visibleIndex = itemIndex - firstIndex
  if visibleIndex < 0 or visibleIndex >= visibleCount:
    return initRect(popup.origin.x, popup.origin.y, 0.0, 0.0)
  let height = rowHeight.normalizedRowHeight()
  initRect(
    popup.origin.x + 1.0'f32,
    popup.origin.y + 1.0'f32 + visibleIndex.float32 * height,
    max(popup.size.width - 2.0'f32, 0.0'f32),
    height,
  )

func listItemIndexAtPoint*(
    popup: Rect,
    point: Point,
    firstIndex, visibleCount, itemCount: int,
    rowHeight: float32,
): int =
  let content = initRect(
    popup.origin.x + 1.0'f32,
    popup.origin.y + 1.0'f32,
    max(popup.size.width - 2.0'f32, 0.0'f32),
    max(popup.size.height - 2.0'f32, 0.0'f32),
  )
  if content.isEmpty or not content.contains(point):
    return -1
  let
    height = rowHeight.normalizedRowHeight()
    visibleIndex = int((point.y - content.origin.y) / height)
  if visibleIndex < 0 or visibleIndex >= visibleCount:
    return -1
  let index = firstIndex + visibleIndex
  if index < 0 or index >= itemCount:
    return -1
  index

func initListRowState*(
    index: int,
    text: string,
    selected = false,
    highlighted = false,
    enabled = true,
    focused = false,
): ListRowState =
  ListRowState(
    index: index,
    text: text,
    selected: selected,
    highlighted: highlighted,
    enabled: enabled,
    focused: focused,
  )

proc itemCount*(popupList: PopupListView): int =
  if popupList.isNil or popupList.xData.itemCount.isNil:
    return 0
  max(popupList.xData.itemCount(), 0)

proc visibleItemCount*(popupList: PopupListView): int =
  if popupList.isNil:
    return 0
  if not popupList.xData.visibleCount.isNil:
    return max(popupList.xData.visibleCount(), 0)
  popupList.itemCount()

proc firstIndex*(popupList: PopupListView): int =
  if popupList.isNil or popupList.xData.firstIndex.isNil:
    return 0
  popupList.xData.firstIndex().clampFirstIndex(
    popupList.itemCount(), popupList.visibleItemCount()
  )

proc selectedIndex*(popupList: PopupListView): int =
  if popupList.isNil or popupList.xData.selectedIndex.isNil:
    return -1
  popupList.xData.selectedIndex()

proc highlightedIndex*(popupList: PopupListView): int =
  if popupList.isNil or popupList.xData.highlightedIndex.isNil:
    return -1
  popupList.xData.highlightedIndex()

proc rowHeight*(popupList: PopupListView): float32 =
  if popupList.isNil or popupList.xData.rowHeight.isNil:
    return 18.0'f32.normalizedRowHeight()
  popupList.xData.rowHeight().normalizedRowHeight()

proc itemText*(popupList: PopupListView, index: int): string =
  if popupList.isNil or popupList.xData.itemText.isNil:
    return ""
  popupList.xData.itemText(index)

proc isEnabled*(popupList: PopupListView): bool =
  popupList.isNil or popupList.xData.enabled.isNil or popupList.xData.enabled()

proc isFocused*(popupList: PopupListView): bool =
  not popupList.isNil and not popupList.xData.focused.isNil and popupList.xData.focused()

proc isOpened*(popupList: PopupListView): bool =
  popupList.isNil or popupList.xData.opened.isNil or popupList.xData.opened()

proc styleId(popupList: PopupListView): string =
  if popupList.isNil or popupList.xData.styleId.isNil:
    return ""
  popupList.xData.styleId()

proc styleClasses(popupList: PopupListView): seq[string] =
  if popupList.isNil or popupList.xData.styleClasses.isNil:
    return @[]
  popupList.xData.styleClasses()

proc popupListScrollRows*(event: ScrollEvent): int =
  if event.deltaY < 0.0'f32:
    1
  elif event.deltaY > 0.0'f32:
    -1
  else:
    0

proc popupListItemRect*(
    popupList: PopupListView, popupBounds: Rect, itemIndex: int
): Rect =
  if popupList.isNil:
    return initRect(popupBounds.origin.x, popupBounds.origin.y, 0.0, 0.0)
  listItemRect(
    popupBounds,
    popupList.firstIndex(),
    popupList.visibleItemCount(),
    itemIndex,
    popupList.rowHeight(),
  )

proc popupListItemIndexAtPoint*(
    popupList: PopupListView, popupBounds: Rect, point: Point
): int =
  if popupList.isNil:
    return -1
  listItemIndexAtPoint(
    popupBounds,
    point,
    popupList.firstIndex(),
    popupList.visibleItemCount(),
    popupList.itemCount(),
    popupList.rowHeight(),
  )

proc popupListScrollIndicatorRect*(popupList: PopupListView, popupBounds: Rect): Rect =
  if popupList.isNil:
    return initRect(popupBounds.origin.x, popupBounds.origin.y, 0.0, 0.0)
  listScrollIndicatorRect(
    popupBounds,
    popupList.firstIndex(),
    popupList.visibleItemCount(),
    popupList.itemCount(),
  )

proc drawListRow(
    context: DrawContext,
    layer: ZLevel,
    parent: FigIdx,
    rect: Rect,
    row: ListRowState,
    itemRole: StyleRole,
    id = "",
    classes: seq[string] = @[],
) =
  if rect.isEmpty:
    return
  let itemStyle = context.appearance.resolveListItemStyle(
    initControlStyleContext(
      itemRole,
      enabled = row.enabled,
      hovered = row.highlighted,
      focused = row.focused,
      selected = row.selected,
      id = id,
      classes = classes,
    )
  )
  discard context.addWindowRectangle(
    layer,
    parent,
    context.localRectToWindow(rect),
    itemStyle.box.fill,
    itemStyle.box.borderColor,
    itemStyle.box.borderWidth,
    itemStyle.box.cornerRadius,
    itemStyle.box.shadows,
  )
  context.addText(
    layer, parent, itemStyle.listItemTextRect(rect), row.text, itemStyle.text.color
  )

proc drawListRow(
    context: DrawContext,
    rect: Rect,
    row: ListRowState,
    itemRole: StyleRole,
    id = "",
    classes: seq[string] = @[],
) =
  if rect.isEmpty:
    return
  let itemStyle = context.appearance.resolveListItemStyle(
    initControlStyleContext(
      itemRole,
      enabled = row.enabled,
      hovered = row.highlighted,
      focused = row.focused,
      selected = row.selected,
      id = id,
      classes = classes,
    )
  )
  discard context.addWindowRectangle(
    context.localRectToWindow(rect),
    itemStyle.box.fill,
    itemStyle.box.borderColor,
    itemStyle.box.borderWidth,
    itemStyle.box.cornerRadius,
    itemStyle.box.shadows,
  )
  context.addText(itemStyle.listItemTextRect(rect), row.text, itemStyle.text.color)

proc drawPopupList*(
    popupList: PopupListView,
    context: DrawContext,
    popupBounds: Rect,
    layer: ZLevel = DefaultDrawLevel,
    parent: FigIdx = (-1).FigIdx,
) =
  if popupList.isNil or popupBounds.isEmpty:
    return
  let
    classes = popupList.styleClasses()
    appearance = context.appearance()
    popupStyle = appearance.resolveComboBoxStyle(
      initControlStyleContext(
        popupList.xPopupRole,
        enabled = popupList.isEnabled(),
        focused = popupList.isFocused(),
        opened = popupList.isOpened(),
        id = popupList.styleId(),
        classes = classes,
      )
    )
    popupRoot = context.addWindowRectangle(
      layer,
      parent,
      context.localRectToWindow(popupBounds),
      initColor(1.0, 1.0, 1.0, 1.0),
      popupStyle.box.borderColor,
      popupStyle.box.borderWidth,
      2.0'f32,
    )
    first = popupList.firstIndex()
    visible = popupList.visibleItemCount()
    total = popupList.itemCount()

  for visibleIndex in 0 ..< visible:
    let itemIndex = first + visibleIndex
    if itemIndex < 0 or itemIndex >= total:
      continue
    let
      itemRect = popupList.popupListItemRect(popupBounds, itemIndex)
      row = initListRowState(
        itemIndex,
        popupList.itemText(itemIndex),
        selected = itemIndex == popupList.selectedIndex(),
        highlighted = itemIndex == popupList.highlightedIndex(),
        enabled = popupList.isEnabled(),
        focused = popupList.isFocused(),
      )
    context.drawListRow(
      layer, popupRoot, itemRect, row, popupList.xItemRole, popupList.styleId(), classes
    )

  let indicatorRect = popupList.popupListScrollIndicatorRect(popupBounds)
  if not indicatorRect.isEmpty:
    discard context.addWindowRectangle(
      layer,
      popupRoot,
      context.localRectToWindow(indicatorRect),
      fill(initColor(0.10, 0.18, 0.30, 0.34)),
      initColor(0.0, 0.0, 0.0, 0.0),
      0.0'f32,
      2.0'f32,
    )

proc highlightItemAtPoint(popupList: PopupListView, popupBounds: Rect, point: Point) =
  let itemIndex = popupList.popupListItemIndexAtPoint(popupBounds, point)
  if itemIndex >= 0 and not popupList.xActions.highlight.isNil:
    popupList.xActions.highlight(itemIndex)

proc beginPopupListTracking*(
    popupList: PopupListView, popupBounds: Rect, point: Point
) =
  if popupList.isNil:
    return
  popupList.xTrackingItem = true
  popupList.highlightItemAtPoint(popupBounds, point)

proc trackPopupListPoint*(popupList: PopupListView, popupBounds: Rect, point: Point) =
  if popupList.isNil:
    return
  popupList.highlightItemAtPoint(popupBounds, point)

proc finishPopupListTracking*(
    popupList: PopupListView, popupBounds: Rect, point: Point, closeWhenDone = true
) =
  if popupList.isNil:
    return
  let itemIndex =
    if popupList.isOpened() and popupList.xTrackingItem:
      popupList.popupListItemIndexAtPoint(popupBounds, point)
    else:
      -1
  popupList.xTrackingItem = false
  if itemIndex >= 0:
    popupList.activateItem(itemIndex)
  if closeWhenDone:
    popupList.close()

proc resetPopupListTracking*(popupList: PopupListView) =
  if not popupList.isNil:
    popupList.xTrackingItem = false

proc activateItem(popupList: PopupListView, index: int) =
  if not popupList.isNil and not popupList.xActions.activate.isNil:
    popupList.xActions.activate(index)

proc close(popupList: PopupListView) =
  if not popupList.isNil and not popupList.xActions.close.isNil:
    popupList.xActions.close()

proc scrollBy(popupList: PopupListView, delta: int) =
  if delta != 0 and not popupList.isNil and not popupList.xActions.scroll.isNil:
    popupList.xActions.scroll(delta)

proc canScrollRows*(popupList: PopupListView, delta: int): bool =
  if popupList.isNil:
    return false
  initListViewport(popupList.firstIndex()).canScrollBy(
    delta, popupList.itemCount(), popupList.visibleItemCount()
  )

proc dispatchKeyDown(popupList: PopupListView, event: KeyEvent) =
  if not popupList.isNil and not popupList.xActions.keyDown.isNil:
    popupList.xActions.keyDown(event)

proc configure*(
    popupList: PopupListView, data: PopupListData, actions: PopupListActions
) =
  if popupList.isNil:
    return
  popupList.xData = data
  popupList.xActions = actions

proc setPopupListRoles*(
    popupList: PopupListView,
    popupRole: StyleRole = srComboBox,
    itemRole: StyleRole = srComboBoxItem,
) =
  if popupList.isNil:
    return
  popupList.xPopupRole = popupRole
  popupList.xItemRole = itemRole
  popupList.setNeedsDisplay(true)

proc initPopupListViewFields*(
    popupList: PopupListView,
    data = PopupListData(),
    actions = PopupListActions(),
    frame: Rect = AutoRect,
) =
  initViewFields(popupList, frame)
  popupList.xPopupRole = srComboBox
  popupList.xItemRole = srComboBoxItem
  popupList.configure(data, actions)
  popupList.setBackgroundColor(initColor(1.0, 1.0, 1.0, 1.0))
  popupList.setAcceptsFirstResponder(true)
  discard popupList.withProtocol(DefaultPopupListDrawing)
  discard popupList.withProtocol(DefaultPopupListEvents)

proc newPopupListView*(
    data = PopupListData(), actions = PopupListActions(), frame: Rect = AutoRect
): PopupListView =
  result = PopupListView()
  initPopupListViewFields(result, data, actions, frame)

proc initListClipView(): ClipView =
  result = ClipView()
  initViewFields(result, initRect(0.0, 0.0, 0.0, 0.0))
  result.background = initColor(0.0, 0.0, 0.0, 0.0)
  result.clipsToBounds = true
  result.autoresizingMaskConstraints = false
  result.setAcceptsFirstResponder(false)
  discard result.withProtocol(DefaultListClipViewHitTesting)

proc initListContentView(listView: ListView): ListContentView =
  result = ListContentView()
  initViewFields(result, initRect(0.0, 0.0, 0.0, 0.0))
  result.xListView = listView
  result.background = initColor(0.0, 0.0, 0.0, 0.0)
  result.clipsToBounds = false
  result.autoresizingMaskConstraints = false
  result.setAcceptsFirstResponder(false)
  discard result.withProtocol(DefaultListContentViewDrawing)
  discard result.withProtocol(DefaultListContentViewHitTesting)

proc listView*(contentView: ListContentView): ListView =
  if contentView.isNil: nil else: contentView.xListView

proc clipView*(listView: ListView): ClipView =
  if listView.isNil: nil else: listView.xClipView

proc contentView*(listView: ListView): ListContentView =
  if listView.isNil: nil else: listView.xContentView

proc invalidateListRows(listView: ListView) =
  if listView.isNil:
    return
  if not listView.xClipView.isNil:
    listView.xClipView.setNeedsDisplay(true)
  if not listView.xContentView.isNil:
    listView.xContentView.setNeedsDisplay(true)
  listView.setNeedsDisplay(true)

proc len*(listView: ListView): int =
  if listView.isNil:
    return 0
  listView.xItems.len

proc items*(listView: ListView): seq[string] =
  if listView.isNil:
    @[]
  else:
    listView.xItems

proc itemAtIndex(listView: ListView, index: int): string =
  if listView.isNil or index < 0 or index >= listView.xItems.len:
    ""
  else:
    listView.xItems[index]

proc setItems*(listView: ListView, values: openArray[string]) =
  if listView.isNil:
    return
  var nextItems: seq[string]
  for value in values:
    nextItems.add value
  if listView.xItems == nextItems:
    return
  listView.xItems = nextItems
  listView.reloadData()

proc `items=`*(listView: ListView, values: openArray[string]) =
  listView.setItems(values)

proc `[]`*(listView: ListView, index: int): string =
  listView.itemAtIndex(index)

proc addItem*(listView: ListView, value: string) =
  if listView.isNil:
    return
  listView.xItems.add value
  listView.reloadData()

proc addItems*(listView: ListView, values: openArray[string]) =
  if listView.isNil or values.len == 0:
    return
  for value in values:
    listView.xItems.add value
  listView.reloadData()

proc insertItem*(listView: ListView, value: string, index: int) =
  if listView.isNil:
    return
  let boundedIndex = max(0, min(index, listView.xItems.len))
  listView.xItems.insert(value, boundedIndex)
  if listView.xSelectedIndex >= boundedIndex:
    inc listView.xSelectedIndex
  if listView.xHighlightedIndex >= boundedIndex:
    inc listView.xHighlightedIndex
  listView.reloadData()

proc removeItemAtIndex*(listView: ListView, index: int) =
  if listView.isNil or index < 0 or index >= listView.xItems.len:
    return
  listView.xItems.delete(index)
  if listView.xSelectedIndex == index:
    listView.xSelectedIndex =
      if listView.xItems.len == 0:
        -1
      else:
        min(index, listView.xItems.len - 1)
  elif index < listView.xSelectedIndex:
    dec listView.xSelectedIndex
  if listView.xHighlightedIndex == index:
    listView.xHighlightedIndex = -1
  elif index < listView.xHighlightedIndex:
    dec listView.xHighlightedIndex
  listView.reloadData()

proc removeAllItems*(listView: ListView) =
  if listView.isNil or listView.xItems.len == 0:
    return
  listView.xItems.setLen(0)
  listView.xSelectedIndex = -1
  listView.xHighlightedIndex = -1
  listView.xViewport.reset()
  listView.reloadData()

proc highlightedIndex*(listView: ListView): int =
  if listView.isNil:
    return -1
  listView.xHighlightedIndex

proc setHighlightedIndex*(listView: ListView, index: int) =
  if listView.isNil:
    return
  let boundedIndex = if index < 0 or index >= listView.len(): -1 else: index
  if listView.xHighlightedIndex == boundedIndex:
    return
  listView.xHighlightedIndex = boundedIndex
  listView.invalidateListRows()

proc `highlightedIndex=`*(listView: ListView, index: int) =
  listView.setHighlightedIndex(index)

proc selectItemAtIndex(listView: ListView, index: int) =
  if listView.isNil or listView.xSelectionMode == lsmNone:
    return
  let boundedIndex = if index < 0 or index >= listView.len(): -1 else: index
  if listView.xSelectedIndex == boundedIndex:
    if boundedIndex >= 0:
      listView.scrollItemToVisible(boundedIndex)
    return
  listView.xSelectedIndex = boundedIndex
  if boundedIndex >= 0:
    listView.scrollItemToVisible(boundedIndex)
  listView.invalidateListRows()

proc deselectItem(listView: ListView) =
  if listView.isNil or listView.xSelectedIndex < 0:
    return
  listView.xSelectedIndex = -1
  listView.invalidateListRows()

proc selectedIndex*(listView: ListView): int =
  if listView.isNil:
    return -1
  listView.xSelectedIndex

proc setSelectedIndex*(listView: ListView, index: int) =
  if listView.isNil:
    return
  if index < 0:
    listView.deselectItem()
  else:
    listView.selectItemAtIndex(index)

proc `selectedIndex=`*(listView: ListView, index: int) =
  listView.setSelectedIndex(index)

proc firstVisibleIndex*(listView: ListView): int =
  if listView.isNil:
    return 0
  let rowHeight = listView.rowHeight()
  if rowHeight <= 0.0'f32:
    return 0
  floor(listView.listContentOffset().y / rowHeight).int.clampFirstIndex(
    listView.len(), listView.visibleItemCount()
  )

proc setFirstVisibleIndex*(listView: ListView, index: int) =
  if listView.isNil:
    return
  let oldFirst = listView.firstVisibleIndex()
  listView.tileListContent()
  listView.setListContentOffset(
    initPoint(
      0.0'f32,
      index.clampFirstIndex(listView.len(), listView.visibleItemCount()).float32 *
        listView.rowHeight(),
    ),
    false,
  )
  if listView.firstVisibleIndex() != oldFirst:
    listView.invalidateListRows()

proc `firstVisibleIndex=`*(listView: ListView, index: int) =
  listView.setFirstVisibleIndex(index)

proc rowHeight*(listView: ListView): float32 =
  if listView.isNil:
    return 0.0'f32
  listView.xRowHeight.normalizedRowHeight()

proc setRowHeight*(listView: ListView, height: float32) =
  if listView.isNil:
    return
  let normalized = height.normalizedRowHeight()
  if listView.xRowHeight == normalized:
    return
  listView.xRowHeight = normalized
  listView.reloadData()

proc `rowHeight=`*(listView: ListView, height: float32) =
  listView.setRowHeight(height)

proc visibleRows*(listView: ListView): int =
  if listView.isNil:
    return 0
  listView.xVisibleRows

proc setVisibleRows*(listView: ListView, rows: int) =
  if listView.isNil:
    return
  let normalized = max(rows, 1)
  if listView.xVisibleRows == normalized:
    return
  listView.xVisibleRows = normalized
  listView.reloadData()

proc `visibleRows=`*(listView: ListView, rows: int) =
  listView.setVisibleRows(rows)

proc selectionMode*(listView: ListView): ListSelectionMode =
  if listView.isNil:
    return lsmSingle
  listView.xSelectionMode

proc setSelectionMode*(listView: ListView, mode: ListSelectionMode) =
  if listView.isNil or listView.xSelectionMode == mode:
    return
  listView.xSelectionMode = mode
  if mode == lsmNone:
    listView.xSelectedIndex = -1
  listView.reloadData()

proc `selectionMode=`*(listView: ListView, mode: ListSelectionMode) =
  listView.setSelectionMode(mode)

proc reloadData*(listView: ListView) =
  if listView.isNil:
    return
  if listView.xSelectionMode == lsmNone or listView.len() == 0:
    listView.xSelectedIndex = -1
  elif listView.xSelectedIndex >= listView.len():
    listView.xSelectedIndex = listView.len() - 1
  elif listView.xSelectedIndex < -1:
    listView.xSelectedIndex = -1

  if listView.xHighlightedIndex < 0 or listView.xHighlightedIndex >= listView.len():
    listView.xHighlightedIndex = -1
  var viewport = initListViewport(listView.firstVisibleIndex())
  if listView.xSelectedIndex >= 0:
    viewport.scrollToVisible(
      listView.xSelectedIndex, listView.len(), listView.visibleItemCount()
    )
  else:
    viewport.normalize(listView.len(), listView.visibleItemCount())
  listView.tileListContent()
  listView.setListContentOffset(
    initPoint(0.0'f32, viewport.firstIndex.float32 * listView.rowHeight()), false
  )
  listView.invalidateIntrinsicContentSize()
  listView.invalidateListRows()

proc visibleItemCount*(listView: ListView): int =
  if listView.isNil or listView.len() <= 0:
    return 0
  let
    rowHeight = listView.rowHeight()
    contentHeight = listView.listViewportSize().height
    visibleFromBounds =
      if rowHeight <= 0.0'f32:
        0
      else:
        int(contentHeight / rowHeight)
    preferredRows =
      if visibleFromBounds > 0:
        visibleFromBounds
      else:
        listView.visibleRows()
  visibleListItemCount(listView.len(), preferredRows)

proc listItemRect*(listView: ListView, itemIndex: int): Rect =
  if listView.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  listView.tileListContent()
  let
    contentView = listView.contentView()
    contentRect = contentView.listContentItemRect(itemIndex)
  if contentView.isNil or contentRect.isEmpty:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let visibleRect =
    contentView.rectToView(contentRect, listView).intersection(listView.bounds())
  if visibleRect.size.height < listView.rowHeight() or visibleRect.isEmpty:
    initRect(0.0, 0.0, 0.0, 0.0)
  else:
    visibleRect

proc listItemIndexAtPoint*(listView: ListView, point: Point): int =
  if listView.isNil:
    return -1
  listView.tileListContent()
  let contentView = listView.contentView()
  if contentView.isNil:
    return -1
  contentView.listContentItemIndexAtPoint(contentView.pointFromView(point, listView))

proc listScrollIndicatorRect*(listView: ListView): Rect =
  if listView.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  listScrollIndicatorRect(
    listView.bounds(),
    listView.firstVisibleIndex(),
    listView.visibleItemCount(),
    listView.len(),
  )

proc scrollItemToVisible*(listView: ListView, itemIndex: int) =
  if listView.isNil:
    return
  let oldFirst = listView.firstVisibleIndex()
  var viewport = initListViewport(oldFirst)
  viewport.scrollToVisible(itemIndex, listView.len(), listView.visibleItemCount())
  listView.setListContentOffset(
    initPoint(0.0'f32, viewport.firstIndex.float32 * listView.rowHeight()), false
  )
  if listView.firstVisibleIndex() != oldFirst:
    listView.invalidateListRows()

proc canScrollRows*(listView: ListView, delta: int): bool =
  if listView.isNil:
    return false
  initListViewport(listView.firstVisibleIndex()).canScrollBy(
    delta, listView.len(), listView.visibleItemCount()
  )

proc scrollRows*(listView: ListView, delta: int) =
  if listView.isNil or delta == 0:
    return
  let oldFirst = listView.firstVisibleIndex()
  var viewport = initListViewport(oldFirst)
  viewport.scrollBy(delta, listView.len(), listView.visibleItemCount())
  listView.setListContentOffset(
    initPoint(0.0'f32, viewport.firstIndex.float32 * listView.rowHeight()), false
  )
  if listView.firstVisibleIndex() != oldFirst:
    listView.invalidateListRows()

proc activateItemAtIndex*(listView: ListView, index: int) =
  if listView.isNil or index < 0 or index >= listView.len():
    return
  if listView.selectionMode() != lsmNone:
    listView.selectItemAtIndex(index)
  discard listView.sendAction()

proc moveSelectionTo(listView: ListView, index: int) =
  if listView.isNil or listView.len() == 0 or listView.selectionMode() == lsmNone:
    return
  listView.selectItemAtIndex(max(0, min(index, listView.len() - 1)))

proc moveSelection(listView: ListView, delta: int) =
  if listView.isNil:
    return
  let start =
    if listView.selectedIndex() >= 0:
      listView.selectedIndex()
    elif delta > 0:
      listView.firstVisibleIndex() - 1
    elif delta < 0:
      listView.firstVisibleIndex() + listView.visibleItemCount()
    else:
      listView.firstVisibleIndex()
  listView.moveSelectionTo(start + delta)

proc pageSelection(listView: ListView, deltaPages: int) =
  if listView.isNil:
    return
  listView.moveSelection(deltaPages * max(listView.visibleItemCount(), 1))

proc handleListKeyDown(listView: ListView, event: KeyEvent) =
  if listView.isNil or not listView.isEnabled():
    return
  case event.key
  of keyArrowDown:
    listView.moveSelection(1)
  of keyArrowUp:
    listView.moveSelection(-1)
  of keyPageDown:
    listView.pageSelection(1)
  of keyPageUp:
    listView.pageSelection(-1)
  of keyHome:
    listView.moveSelectionTo(0)
  of keyEnd:
    listView.moveSelectionTo(listView.len() - 1)
  of keyEnter, keySpace:
    if listView.selectedIndex() >= 0:
      discard listView.sendAction()
  else:
    discard

proc setListViewRoles*(
    listView: ListView,
    listRole: StyleRole = srListView,
    itemRole: StyleRole = srListItem,
) =
  if listView.isNil:
    return
  if listView.xListRole == listRole and listView.xItemRole == itemRole:
    return
  listView.xListRole = listRole
  listView.xItemRole = itemRole
  listView.reloadData()

proc drawListView(listView: ListView, context: DrawContext) =
  if listView.isNil or listView.bounds().isEmpty:
    return
  listView.tileListContent()
  let
    classes = listView.styleClasses()
    listStyle = context.appearance.resolveListViewStyle(
      initControlStyleContext(
        listView.xListRole,
        enabled = listView.isEnabled(),
        focused = listView.isFocused(),
        focusVisible = listView.isFocusVisible(),
        id = listView.styleId(),
        classes = classes,
      )
    )
  discard context.addWindowRectangle(
    context.localRectToWindow(listView.bounds()),
    listStyle.box.fill,
    listStyle.box.borderColor,
    listStyle.box.borderWidth,
    listStyle.box.cornerRadius,
    listStyle.box.shadows,
    clips = true,
  )

  if listView.isFocusVisible:
    context.addFocusRing(listView.rectToWindow(listView.bounds), listStyle.box)

proc listViewportSize(listView: ListView): Size =
  if listView.isNil:
    return initSize(0.0, 0.0)
  initSize(
    max(listView.bounds().size.width - 2.0'f32, 0.0'f32),
    max(listView.bounds().size.height - 2.0'f32, 0.0'f32),
  )

proc listViewportRect(listView: ListView): Rect =
  if listView.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  initRect(initPoint(1.0'f32, 1.0'f32), listView.listViewportSize())

proc listContentSize*(listView: ListView): Size =
  if listView.isNil:
    return initSize(0.0, 0.0)
  initSize(
    listView.listViewportSize().width, listView.rowHeight() * listView.len().float32
  )

proc clampListContentOffset(listView: ListView, offset: Point): Point =
  if listView.isNil:
    return initPoint(0.0, 0.0)
  let
    viewportSize = listView.listViewportSize()
    contentSize = listView.listContentSize()
    horizontal = initScrollViewport(0.0, viewportSize.width, contentSize.width)
    maxFirst = maxFirstIndex(listView.len(), listView.visibleItemCount()).float32
    maxY = maxFirst * listView.rowHeight()
  initPoint(
    horizontal.clampScrollOffset(offset.x),
    min(max(offset.y, 0.0'f32), max(maxY, 0.0'f32)),
  )

proc syncListViewport(listView: ListView, offset: Point) =
  if listView.isNil:
    return
  let rowHeight = listView.rowHeight()
  listView.xViewport.reset(
    if rowHeight <= 0.0'f32:
      0
    else:
      floor(offset.y / rowHeight).int
  )
  listView.xViewport.normalize(listView.len(), listView.visibleItemCount())

proc listContentOffset(listView: ListView): Point =
  if listView.isNil or listView.xClipView.isNil:
    return initPoint(0.0, 0.0)
  listView.clampListContentOffset(listView.xClipView.bounds().origin)

proc setListContentOffset(listView: ListView, offset: Point, invalidate: bool) =
  if listView.isNil or listView.xClipView.isNil:
    return
  let
    nextOffset = listView.clampListContentOffset(offset)
    nextBounds = initRect(nextOffset, listView.listViewportSize())
  if listView.xClipView.bounds() != nextBounds:
    listView.xClipView.bounds = nextBounds
    if invalidate:
      listView.invalidateListRows()
  listView.syncListViewport(nextOffset)

proc tileListContent(listView: ListView) =
  if listView.isNil or listView.xClipView.isNil or listView.xContentView.isNil:
    return
  let
    offset = listView.listContentOffset()
    viewport = listView.listViewportRect()
    size = listView.listContentSize()
  listView.xClipView.frame = viewport
  listView.xContentView.frame = initRect(0.0'f32, 0.0'f32, size.width, size.height)
  listView.setListContentOffset(offset, false)

proc listContentItemRect*(contentView: ListContentView, itemIndex: int): Rect =
  let listView = contentView.listView()
  if listView.isNil or itemIndex < 0 or itemIndex >= listView.len():
    return initRect(0.0, 0.0, 0.0, 0.0)
  initRect(
    0.0'f32,
    itemIndex.float32 * listView.rowHeight(),
    max(contentView.bounds().size.width, 0.0'f32),
    listView.rowHeight(),
  )

proc listContentItemIndexAtPoint*(contentView: ListContentView, point: Point): int =
  let listView = contentView.listView()
  if contentView.isNil or listView.isNil or not contentView.bounds().contains(point):
    return -1
  let index = int(point.y / listView.rowHeight())
  if index < 0 or index >= listView.len():
    return -1
  index

proc visibleContentRows(contentView: ListContentView): tuple[first, last: int] =
  let listView = contentView.listView()
  if contentView.isNil or listView.isNil or listView.len() <= 0:
    return (0, 0)
  let
    rowHeight = listView.rowHeight()
    visible = contentView.visibleRect()
  if rowHeight <= 0.0'f32 or visible.isEmpty:
    return (0, 0)
  result.first = max(floor(max(visible.minY, 0.0'f32) / rowHeight).int, 0)
  result.last = min(ceil(max(visible.maxY, 0.0'f32) / rowHeight).int, listView.len())
  if result.last < result.first:
    result.last = result.first

proc drawListContent(contentView: ListContentView, context: DrawContext) =
  let listView = contentView.listView()
  if contentView.isNil or listView.isNil:
    return
  let
    classes = listView.styleClasses()
    rows = contentView.visibleContentRows()

  for itemIndex in rows.first ..< rows.last:
    let row = initListRowState(
      itemIndex,
      listView.itemAtIndex(itemIndex),
      selected = itemIndex == listView.selectedIndex(),
      highlighted = itemIndex == listView.highlightedIndex(),
      enabled = listView.isEnabled(),
      focused = listView.isFocused(),
    )
    context.drawListRow(
      contentView.listContentItemRect(itemIndex),
      row,
      listView.xItemRole,
      listView.styleId(),
      classes,
    )

  let indicatorRect = listView.listScrollIndicatorRect()
  if not indicatorRect.isEmpty:
    discard context.addWindowRectangle(
      context.localRectToWindow(contentView.rectFromView(indicatorRect, listView)),
      fill(initColor(0.10, 0.18, 0.30, 0.34)),
      initColor(0.0, 0.0, 0.0, 0.0),
      0.0'f32,
      2.0'f32,
    )

proc listNaturalSize(listView: ListView): Size =
  if listView.isNil:
    return initSize(0.0, 0.0)

  let
    appearance = listView.effectiveAppearance()
    listStyle = appearance.resolveListViewStyle(
      initControlStyleContext(
        listView.xListRole,
        enabled = listView.isEnabled(),
        id = listView.styleId(),
        classes = listView.styleClasses(),
      )
    )
    itemStyle = appearance.resolveListItemStyle(
      initControlStyleContext(
        listView.xItemRole,
        enabled = listView.isEnabled(),
        id = listView.styleId(),
        classes = listView.styleClasses(),
      )
    )
    rowCount =
      if listView.len() == 0:
        max(listView.visibleRows(), 1)
      else:
        visibleListItemCount(listView.len(), listView.visibleRows())

  var maxTextWidth = 0.0'f32
  for item in listView.xItems:
    maxTextWidth = max(maxTextWidth, textNaturalSize(item).width)

  initSize(
    max(
      listStyle.minSize.width,
      max(
        itemStyle.minSize.width,
        maxTextWidth + itemStyle.text.insets.horizontal + 2.0'f32,
      ),
    ),
    max(listStyle.minSize.height, listView.rowHeight() * rowCount.float32 + 2.0'f32),
  )

proc initListViewFields*(
    listView: ListView, items: openArray[string] = [], frame: Rect = AutoRect
) =
  initControlFields(listView, frame)
  listView.xSelectedIndex = -1
  listView.xHighlightedIndex = -1
  listView.xRowHeight = 22.0'f32
  listView.xVisibleRows = 5
  listView.xSelectionMode = lsmSingle
  listView.xListRole = srListView
  listView.xItemRole = srListItem
  listView.xClipView = initListClipView()
  listView.xContentView = initListContentView(listView)
  listView.setAcceptsFirstResponder(true)
  listView.clipsToBounds = true
  listView.addSubview(listView.xClipView)
  listView.xClipView.addSubview(listView.xContentView)
  discard listView.withProtocol(DefaultListViewLayout)
  discard listView.withProtocol(DefaultListViewDrawing)
  discard listView.withProtocol(DefaultListViewEvents)
  listView.addItems(items)
  listView.applyInitialFrame(frame)

proc newListView*(items: openArray[string] = [], frame: Rect = AutoRect): ListView =
  result = ListView()
  initListViewFields(result, items, frame)
