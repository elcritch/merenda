import std/math

import ./controls
import ./listbasics
import ./scrollergeometry
import ./scrollviews
import ./selectors
import ./theme
import ./types

export listbasics

const ListScrollerThickness = 12.0'f32

type
  ListSelectionMode* = enum
    lsmNone
    lsmSingle

  ListContentView* = ref object of View
    xListView: ListView

  ListScroller* = ref object of View
    xListView: ListView
    xTracking: ScrollerTrackingState

  ListView* = ref object of Control
    xItems: seq[string]
    xSelectedIndex: int
    xHighlightedIndex: int
    xViewport: ListViewport
    xClipView: ClipView
    xContentView: ListContentView
    xVerticalScroller: ListScroller
    xRowHeight: float32
    xVisibleRows: int
    xSelectionMode: ListSelectionMode
    xTrackingItem: bool
    xListRole: StyleRole
    xItemRole: StyleRole

proc listView*(contentView: ListContentView): ListView
proc listView*(scroller: ListScroller): ListView
proc clipView*(listView: ListView): ClipView
proc contentView*(listView: ListView): ListContentView
proc verticalScroller*(listView: ListView): ListScroller
proc listContentSize*(listView: ListView): Size
proc listContentItemRect*(contentView: ListContentView, itemIndex: int): Rect
proc listContentItemIndexAtPoint*(contentView: ListContentView, point: Point): int
proc len*(listView: ListView): int
proc rowHeight*(listView: ListView): float32
proc reloadData*(listView: ListView)
proc visibleItemCount*(listView: ListView): int
proc highlightedIndex*(listView: ListView): int
proc listItemRect*(listView: ListView, itemIndex: int): Rect
proc listItemIndexAtPoint*(listView: ListView, point: Point): int
proc showsVerticalScroller*(listView: ListView): bool
proc verticalScrollerRect*(listView: ListView): Rect
proc verticalScrollerKnobRect*(listView: ListView): Rect
proc scrollItemToVisible*(listView: ListView, itemIndex: int)
proc canScrollRows*(listView: ListView, delta: int): bool
proc scrollRows*(listView: ListView, delta: int)
proc setHighlightedIndex*(listView: ListView, index: int)
proc activateItemAtIndex*(listView: ListView, index: int)

proc listView*(contentView: ListContentView): ListView =
  if contentView.isNil: nil else: contentView.xListView

proc listView*(scroller: ListScroller): ListView =
  if scroller.isNil: nil else: scroller.xListView

proc clipView*(listView: ListView): ClipView =
  if listView.isNil: nil else: listView.xClipView

proc contentView*(listView: ListView): ListContentView =
  if listView.isNil: nil else: listView.xContentView

proc verticalScroller*(listView: ListView): ListScroller =
  if listView.isNil: nil else: listView.xVerticalScroller

proc invalidateListRows(listView: ListView) =
  if listView.isNil:
    return
  if not listView.xClipView.isNil:
    listView.xClipView.setNeedsDisplay(true)
  if not listView.xContentView.isNil:
    listView.xContentView.setNeedsDisplay(true)
  if not listView.xVerticalScroller.isNil:
    listView.xVerticalScroller.setNeedsDisplay(true)
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

proc `items=`*(listView: ListView, values: openArray[string]) =
  if listView.isNil:
    return
  var nextItems: seq[string]
  for value in values:
    nextItems.add value
  if listView.xItems == nextItems:
    return
  listView.xItems = nextItems
  listView.reloadData()

proc `[]`*(listView: ListView, index: int): string =
  if listView.isNil or index < 0 or index >= listView.xItems.len:
    ""
  else:
    listView.xItems[index]

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

proc showsVerticalScroller*(listView: ListView): bool =
  if listView.isNil or listView.len() <= 0:
    return false
  let
    rowHeight = listView.rowHeight()
    contentHeight = max(listView.bounds().size.height - 2.0'f32, 0.0'f32)
    visibleRows =
      if rowHeight <= 0.0'f32:
        0
      else:
        int(contentHeight / rowHeight)
  hasHiddenListItems(listView.len(), visibleListItemCount(listView.len(), visibleRows))

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

proc listViewportSize(listView: ListView): Size =
  if listView.isNil:
    return initSize(0.0, 0.0)
  initSize(
    max(
      listView.bounds().size.width - 2.0'f32 -
        (if listView.showsVerticalScroller(): ListScrollerThickness else: 0.0'f32),
      0.0'f32,
    ),
    max(listView.bounds().size.height - 2.0'f32, 0.0'f32),
  )

proc listContentSize*(listView: ListView): Size =
  if listView.isNil:
    return initSize(0.0, 0.0)
  initSize(
    listView.listViewportSize().width, listView.rowHeight() * listView.len().float32
  )

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

proc firstVisibleIndex*(listView: ListView): int =
  if listView.isNil:
    return 0
  let rowHeight = listView.rowHeight()
  if rowHeight <= 0.0'f32:
    return 0
  floor(listView.listContentOffset().y / rowHeight).int.clampFirstIndex(
    listView.len(), listView.visibleItemCount()
  )

proc listScrollerKnobRect(listView: ListView, track: Rect): Rect =
  if listView.isNil or track.isEmpty:
    return initRect(0.0, 0.0, 0.0, 0.0)
  scrollerKnobRect(
    track,
    laVertical,
    listScrollViewport(
      listView.firstVisibleIndex(), listView.len(), listView.visibleItemCount()
    ),
  )

proc verticalScrollerRect*(listView: ListView): Rect =
  if not listView.showsVerticalScroller():
    return initRect(0.0, 0.0, 0.0, 0.0)
  scrollerTrackRect(listView.bounds(), laVertical, ListScrollerThickness, 1.0'f32)

proc verticalScrollerKnobRect*(listView: ListView): Rect =
  listView.listScrollerKnobRect(listView.verticalScrollerRect())

proc tileListContent(listView: ListView) =
  if listView.isNil or listView.xClipView.isNil or listView.xContentView.isNil:
    return
  let
    offset = listView.listContentOffset()
    viewport = initRect(initPoint(1.0'f32, 1.0'f32), listView.listViewportSize())
    size = listView.listContentSize()
  listView.xClipView.frame = viewport
  listView.xContentView.frame = initRect(0.0'f32, 0.0'f32, size.width, size.height)
  if not listView.xVerticalScroller.isNil:
    listView.xVerticalScroller.frame = listView.verticalScrollerRect()
    listView.xVerticalScroller.hidden = not listView.showsVerticalScroller()
  listView.setListContentOffset(offset, false)

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
  if listView.isNil or not contentView.bounds().contains(point):
    return -1
  let index = int(point.y / listView.rowHeight())
  if index < 0 or index >= listView.len():
    return -1
  index

proc listItemRect*(listView: ListView, itemIndex: int): Rect =
  if listView.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  listView.tileListContent()
  let
    contentView = listView.contentView()
    contentRect = contentView.listContentItemRect(itemIndex)
  if contentRect.isEmpty:
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

proc selectedIndex*(listView: ListView): int =
  if listView.isNil:
    return -1
  listView.xSelectedIndex

proc setSelectedIndex*(listView: ListView, index: int) =
  if listView.isNil:
    return
  if index < 0:
    if listView.xSelectedIndex >= 0:
      listView.xSelectedIndex = -1
      listView.invalidateListRows()
  else:
    listView.selectItemAtIndex(index)

proc `selectedIndex=`*(listView: ListView, index: int) =
  listView.setSelectedIndex(index)

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

proc visibleContentRows(contentView: ListContentView): tuple[first, last: int] =
  let listView = contentView.listView()
  if listView.isNil or listView.len() <= 0:
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
  if listView.isNil:
    return
  let
    classes = listView.styleClasses()
    rows = contentView.visibleContentRows()

  for itemIndex in rows.first ..< rows.last:
    let row = initListRowState(
      itemIndex,
      listView[itemIndex],
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

proc scrollListKnobTo(scroller: ListScroller, point: Point) =
  let listView = scroller.listView()
  if scroller.isNil or listView.isNil:
    return
  let
    track = scroller.bounds()
    maxFirst = maxFirstIndex(listView.len(), listView.visibleItemCount())
    next = contentOffsetForScrollerKnobOrigin(
      track,
      listView.listScrollerKnobRect(track),
      laVertical,
      maxFirst.float32,
      scroller.xTracking.knobOriginForPoint(laVertical, point),
    )
  listView.firstVisibleIndex =
    clampFirstIndex(round(next).int, listView.len(), listView.visibleItemCount())

proc scrollListPageToward(scroller: ListScroller, point: Point) =
  let listView = scroller.listView()
  if scroller.isNil or listView.isNil:
    return
  let knob = listView.listScrollerKnobRect(scroller.bounds())
  if knob.isEmpty or (point.y >= knob.minY and point.y < knob.maxY):
    return
  let direction = if point.y < knob.minY: -1 else: 1
  listView.scrollRows(direction * max(listView.visibleItemCount(), 1))

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

protocol DefaultListContentViewDrawing of ViewDrawingProtocol:
  method draw(contentView: ListContentView, context: DrawContext) =
    contentView.drawListContent(context)

protocol DefaultListContentViewHitTesting of ViewProtocol:
  method pointInside(contentView: ListContentView, point: Point): bool =
    false

protocol DefaultListClipViewHitTesting of ViewProtocol:
  method pointInside(clipView: ClipView, point: Point): bool =
    false

protocol DefaultListScrollerDrawing of ViewDrawingProtocol:
  method draw(scroller: ListScroller, context: DrawContext) =
    if scroller.isNil or scroller.hidden:
      return
    let track = scroller.bounds()
    context.drawScroller(track, scroller.listView().listScrollerKnobRect(track))

protocol DefaultListScrollerEvents of ResponderEventProtocol:
  method mouseDown(scroller: ListScroller, event: MouseEvent) =
    if event.button == mbPrimary:
      if scroller.isNil:
        return
      let
        track = scroller.bounds()
        knob = scroller.listView().listScrollerKnobRect(track)
      if scroller.xTracking.beginScrollerTracking(
        track, knob, laVertical, event.location
      ):
        return
      if track.contains(event.location):
        scroller.scrollListPageToward(event.location)

  method mouseDragged(scroller: ListScroller, event: MouseEvent) =
    if event.button == mbPrimary and not scroller.isNil and
        scroller.xTracking.isDraggingKnob():
      scroller.scrollListKnobTo(event.location)

  method mouseUp(scroller: ListScroller, event: MouseEvent) =
    if event.button == mbPrimary:
      if scroller.isNil:
        return
      if scroller.xTracking.isDraggingKnob():
        scroller.scrollListKnobTo(event.location)
      scroller.xTracking.endScrollerTracking()

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
      not listView.canScrollRows(listScrollRows(event))

  method scrollWheel(listView: ListView, event: ScrollEvent) =
    let delta = listScrollRows(event)
    if not listView.isNil and listView.isEnabled() and listView.canScrollRows(delta):
      listView.scrollRows(delta)

  method keyDown(listView: ListView, event: KeyEvent) =
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

proc initListScroller(listView: ListView): ListScroller =
  result = ListScroller()
  initViewFields(result, initRect(0.0, 0.0, 0.0, 0.0))
  result.xListView = listView
  result.background = initColor(0.0, 0.0, 0.0, 0.0)
  result.autoresizingMaskConstraints = false
  result.hidden = true
  result.setAcceptsFirstResponder(false)
  discard result.withProtocol(DefaultListScrollerDrawing)
  discard result.withProtocol(DefaultListScrollerEvents)

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
  listView.xVerticalScroller = initListScroller(listView)
  listView.setAcceptsFirstResponder(true)
  listView.clipsToBounds = true
  listView.addSubview(listView.xClipView)
  listView.xClipView.addSubview(listView.xContentView)
  listView.addSubview(listView.xVerticalScroller)
  discard listView.withProtocol(DefaultListViewLayout)
  discard listView.withProtocol(DefaultListViewDrawing)
  discard listView.withProtocol(DefaultListViewEvents)
  listView.addItems(items)
  listView.applyInitialFrame(frame)

proc newListView*(items: openArray[string] = [], frame: Rect = AutoRect): ListView =
  result = ListView()
  initListViewFields(result, items, frame)
