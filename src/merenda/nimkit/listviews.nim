from figdraw/figbasics import ZLevel
from figdraw/fignodes import FigIdx

import ./selectors
import ./theme
import ./types
import ./views

type ListViewport* = object
  firstIndex*: int

type
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

  method scrollWheel(popupList: PopupListView, event: ScrollEvent) =
    if popupList.isOpened():
      popupList.scrollBy(popupListScrollRows(event))

  method keyDown(popupList: PopupListView, event: KeyEvent) =
    popupList.dispatchKeyDown(event)

func initListViewport*(firstIndex = 0): ListViewport =
  ListViewport(firstIndex: max(firstIndex, 0))

func normalizedRowHeight*(rowHeight: float32): float32 =
  max(rowHeight, 1.0'f32)

func visibleListItemCount*(itemCount, maxVisibleItems: int): int =
  if itemCount <= 0:
    return 0
  min(itemCount, max(maxVisibleItems, 1))

func maxFirstIndex*(itemCount, visibleCount: int): int =
  max(itemCount - max(visibleCount, 0), 0)

func clampFirstIndex*(firstIndex, itemCount, visibleCount: int): int =
  max(0, min(firstIndex, maxFirstIndex(itemCount, visibleCount)))

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
    clampedFirst = clampFirstIndex(firstIndex, itemCount, visibleCount)
    lastFirst = maxFirstIndex(itemCount, visibleCount)
    thumbHeight = min(
      max(trackHeight * visibleCount.float32 / itemCount.float32, 8.0'f32), trackHeight
    )
    travel = max(trackHeight - thumbHeight, 0.0'f32)
    progress =
      if lastFirst <= 0:
        0.0'f32
      else:
        clampedFirst.float32 / lastFirst.float32

  initRect(
    popup.maxX - trackInset - trackWidth,
    popup.origin.y + trackInset + travel * progress,
    trackWidth,
    thumbHeight,
  )

proc normalize*(viewport: var ListViewport, itemCount, visibleCount: int) =
  viewport.firstIndex = clampFirstIndex(viewport.firstIndex, itemCount, visibleCount)

proc reset*(viewport: var ListViewport, firstIndex = 0) =
  viewport.firstIndex = max(firstIndex, 0)

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
  viewport.firstIndex += delta
  viewport.normalize(itemCount, visibleCount)

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
      itemStyle = appearance.resolveTextFieldStyle(
        initControlStyleContext(
          popupList.xItemRole,
          enabled = popupList.isEnabled(),
          hovered = itemIndex == popupList.highlightedIndex(),
          selected = itemIndex == popupList.selectedIndex(),
          id = popupList.styleId(),
          classes = classes,
        )
      )
    discard context.addWindowRectangle(
      layer,
      popupRoot,
      context.localRectToWindow(itemRect),
      itemStyle.box.fill,
      itemStyle.box.borderColor,
      itemStyle.box.borderWidth,
      itemStyle.box.cornerRadius,
    )
    context.addText(
      layer,
      popupRoot,
      itemStyle.textFieldTextRect(itemRect),
      popupList.itemText(itemIndex),
      itemStyle.text.color,
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
