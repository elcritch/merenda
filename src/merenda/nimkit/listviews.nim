import std/[algorithm, math, options, strutils, times]

import sigils/core

import selectors, theme, types
import controls, listbasics, scrollergeometry, scrollviews

export listbasics

const
  ListScrollerThickness = 12.0'f32
  ListTypeSelectTimeout = 1.0

type
  ListSelectionMode* = enum
    lsmNone
    lsmSingle
    lsmMultiple
    lsmExtended

  ListVisibleRowSummary* = object
    index*: int
    text*: string
    rect*: Rect
    selected*: bool
    highlighted*: bool
    enabled*: bool
    focused*: bool

  ListSelectionSummary* = object
    mode*: ListSelectionMode
    selectedIndex*: int
    selectedIndexes*: seq[int]
    anchorIndex*: int
    leadIndex*: int
    hasSelection*: bool

  ListRowView = ref object of View
    xListView: ListView
    xRow: ListRowState

  ListContentView* = ref object of View
    xListView: ListView
    xRowViews: seq[ListRowView]

  ListScroller* = ref object of View
    xListView: ListView
    xTracking: ScrollerTrackingState

  ListView* = ref object of Control
    xItems: seq[string]
    xDataSource: DynamicAgent
    xDelegate: DynamicAgent
    xSelectedIndex: int
    xSelectedIndexes: seq[int]
    xSelectionAnchor: int
    xSelectionLead: int
    xHighlightedIndex: int
    xViewport: ListViewport
    xClipView: ClipView
    xContentView: ListContentView
    xVerticalScroller: ListScroller
    xRowHeight: float32
    xVisibleRows: int
    xRowHeights: seq[float32]
    xRowOffsets: seq[float32]
    xRowHeightCacheValid: bool
    xComputingRowHeights: bool
    xSelectionMode: ListSelectionMode
    xTrackingItem: bool
    xPressedIndex: int
    xTypeSelectBuffer: string
    xTypeSelectLastTime: float
    xUsesAlternatingRowBackgrounds: bool
    xShowsRowSeparators: bool
    xListRole: StyleRole
    xItemRole: StyleRole

proc listView(rowView: ListRowView): ListView
proc listView*(contentView: ListContentView): ListView
proc listView*(scroller: ListScroller): ListView
proc initListRowView(listView: ListView): ListRowView
proc syncVisibleRowViews(contentView: ListContentView)
proc clipView*(listView: ListView): ClipView
proc contentView*(listView: ListView): ListContentView
proc verticalScroller*(listView: ListView): ListScroller
proc viewportSize(listView: ListView): Size
proc contentSize*(listView: ListView): Size
proc listContentItemRect*(contentView: ListContentView, itemIndex: int): Rect
proc listContentItemIndexAtPoint*(contentView: ListContentView, point: Point): int
proc len*(listView: ListView): int
proc rowHeight*(listView: ListView): float32
proc rowHeightForRow*(listView: ListView, index: int): float32
proc noteRowHeightsChanged*(listView: ListView)
proc noteHeightOfRowsChanged*(listView: ListView, rows: openArray[int])
proc noteHeightOfRowChanged*(listView: ListView, row: int)
proc reloadData*(listView: ListView)
proc visibleItemCount*(listView: ListView): int
proc firstVisibleIndex*(listView: ListView): int
proc highlightedIndex*(listView: ListView): int
proc usesAlternatingRowBackgrounds*(listView: ListView): bool
proc showsRowSeparators*(listView: ListView): bool
proc rowEnabled*(listView: ListView, index: int): bool
proc rowSelectable*(listView: ListView, index: int): bool
proc rowStyle*(listView: ListView, row: ListRowState): ListRowStyle
proc drawListRow*(
  listView: ListView, context: DrawContext, rect: Rect, row: ListRowState
)

proc drawCustomEmptyState(listView: ListView, context: DrawContext, rect: Rect): bool

proc listItemRect*(listView: ListView, itemIndex: int): Rect
proc listItemIndexAtPoint*(listView: ListView, point: Point): int
proc showsVerticalScroller*(listView: ListView): bool
proc verticalScrollerRect*(listView: ListView): Rect
proc tileListContent(listView: ListView)
proc setListContentOffset(listView: ListView, offset: Point, invalidate: bool)
proc scrollItemToVisible*(listView: ListView, itemIndex: int)
proc scrollSelectedItemToVisible*(listView: ListView)
proc scrollSelectionToVisible*(listView: ListView)
proc canScrollRows*(listView: ListView, delta: int): bool
proc scrollRows*(listView: ListView, delta: int)
proc activateItemAtIndex*(listView: ListView, index: int)
proc selectedIndex*(listView: ListView): int
proc selectionLeadIndex(listView: ListView): int
proc selectionSummary*(listView: ListView): ListSelectionSummary
proc visibleRowSummaries*(listView: ListView): seq[ListVisibleRowSummary]
proc selectedRange*(listView: ListView): Slice[int]
proc selectedRanges*(listView: ListView): seq[Slice[int]]
proc dataSource*(listView: ListView): DynamicAgent
proc delegate*(listView: ListView): DynamicAgent
proc selectedIndexes*(listView: ListView): seq[int]

protocol ListViewDataSource {.selectorScope: protocol.}:
  method rowCount*(listView: ListView): int {.optional.}
  method objectValueForRow*(listView: ListView, row: int): string {.optional.}

protocol ListViewEvents:
  proc selectionIsChanging*(listView: ListView, sender: DynamicAgent) {.signal.}
  proc selectionDidChange*(listView: ListView, sender: DynamicAgent) {.signal.}
  proc rowWasActivated*(listView: ListView, sender: DynamicAgent) {.signal.}

protocol ListViewDelegate {.selectorScope: protocol.}:
  method rowIsEnabled*(listView: ListView, row: int): bool {.optional.}
  method shouldSelectRow*(listView: ListView, row: int): bool {.optional.}
  method heightOfRow*(listView: ListView, row: int): float32 {.optional.}
  method heightForRow*(listView: ListView, row: int): float32 {.optional.}
  method styleForRow*(listView: ListView, row: ListRowState): ListRowStyle {.optional.}
  method drawRow*(
    listView: ListView, context: DrawContext, rect: Rect, row: ListRowState
  ) {.optional.}

  method drawEmptyState*(
    listView: ListView, context: DrawContext, rect: Rect
  ) {.optional.}

proc listView(rowView: ListRowView): ListView =
  if rowView.isNil: nil else: rowView.xListView

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
  if not listView.xContentView.isNil:
    listView.xContentView.syncVisibleRowViews()
  if not listView.xClipView.isNil:
    listView.xClipView.setNeedsDisplay(true)
  if not listView.xContentView.isNil:
    listView.xContentView.setNeedsDisplay(true)
  if not listView.xVerticalScroller.isNil:
    listView.xVerticalScroller.setNeedsDisplay(true)
  listView.setNeedsDisplay(true)

proc len*(listView: ListView): int =
  let source = listView.dataSource()
  if not source.isNil:
    let count = source.trySendLocal(rowCount(), listView)
    if count.isSome:
      return max(count.get(), 0)
  listView.xItems.len

iterator items*(listView: ListView): string =
  for item in listView.xItems:
    yield item

proc `items=`*(listView: ListView, values: openArray[string]) =
  let nextItems = @values
  if listView.xItems == nextItems:
    return
  listView.xItems = nextItems
  listView.reloadData()

proc `[]`*(listView: ListView, index: int): string =
  if index in 0 ..< listView.len():
    let source = listView.dataSource()
    if not source.isNil:
      let item =
        source.trySendLocal(objectValueForRow(), (listView: listView, row: index))
      if item.isSome:
        return item.get()
    if index < listView.xItems.len:
      return listView.xItems[index]

proc addItems*(listView: ListView, values: openArray[string]) =
  if values.len == 0:
    return
  for value in values:
    listView.xItems.add value
  listView.reloadData()

proc insertItem*(listView: ListView, value: string, index: int) =
  let boundedIndex = max(0, min(index, listView.xItems.len))
  listView.xItems.insert(value, boundedIndex)
  if listView.xSelectedIndex >= boundedIndex:
    inc listView.xSelectedIndex
  for selectedIndex in listView.xSelectedIndexes.mitems:
    if selectedIndex >= boundedIndex:
      inc selectedIndex
  if listView.xSelectionAnchor >= boundedIndex:
    inc listView.xSelectionAnchor
  if listView.xSelectionLead >= boundedIndex:
    inc listView.xSelectionLead
  if listView.xHighlightedIndex >= boundedIndex:
    inc listView.xHighlightedIndex
  listView.reloadData()

proc removeItemAtIndex*(listView: ListView, index: int) =
  if index notin 0 ..< listView.xItems.len:
    return
  listView.xItems.delete(index)
  var nextSelected: seq[int]
  for selectedIndex in listView.xSelectedIndexes:
    if selectedIndex == index:
      discard
    elif selectedIndex > index:
      nextSelected.add selectedIndex - 1
    else:
      nextSelected.add selectedIndex
  if listView.xSelectedIndex == index:
    listView.xSelectedIndex =
      if listView.xItems.len == 0:
        -1
      else:
        min(index, listView.xItems.len - 1)
    if nextSelected.len == 0 and listView.xSelectedIndex >= 0:
      nextSelected.add listView.xSelectedIndex
  elif index < listView.xSelectedIndex:
    dec listView.xSelectedIndex
  listView.xSelectedIndexes = nextSelected
  if listView.xSelectionAnchor == index:
    listView.xSelectionAnchor = -1
  elif index < listView.xSelectionAnchor:
    dec listView.xSelectionAnchor
  if listView.xSelectionLead == index:
    listView.xSelectionLead = -1
  elif index < listView.xSelectionLead:
    dec listView.xSelectionLead
  if listView.xHighlightedIndex == index:
    listView.xHighlightedIndex = -1
  elif index < listView.xHighlightedIndex:
    dec listView.xHighlightedIndex
  if listView.xPressedIndex == index:
    listView.xPressedIndex = -1
  elif index < listView.xPressedIndex:
    dec listView.xPressedIndex
  listView.reloadData()

proc removeAllItems*(listView: ListView) =
  if listView.xItems.len == 0:
    return
  listView.xItems.setLen(0)
  listView.xSelectedIndex = -1
  listView.xSelectedIndexes.setLen(0)
  listView.xSelectionAnchor = -1
  listView.xSelectionLead = -1
  listView.xHighlightedIndex = -1
  listView.xPressedIndex = -1
  listView.xViewport.reset()
  listView.reloadData()

proc dataSource*(listView: ListView): DynamicAgent =
  listView.xDataSource

proc `dataSource=`*(listView: ListView, dataSource: DynamicAgent) =
  if listView.xDataSource == dataSource:
    return
  listView.xDataSource = dataSource
  listView.reloadData()

proc `dataSource=`*(listView: ListView, dataSource: Responder) =
  listView.dataSource = DynamicAgent(dataSource)

proc delegate*(listView: ListView): DynamicAgent =
  return listView.xDelegate

proc `delegate=`*(listView: ListView, delegate: DynamicAgent) =
  if listView.setProtocolDelegate(
    listView.xDelegate, delegate, ListViewDelegate, ListViewEvents
  ):
    listView.reloadData()

proc `delegate=`*(listView: ListView, delegate: Responder) =
  listView.delegate = DynamicAgent(delegate)

proc highlightedIndex*(listView: ListView): int =
  listView.xHighlightedIndex

proc `highlightedIndex=`*(listView: ListView, index: int) =
  let boundedIndex = if listView.rowEnabled(index): index else: -1
  if listView.xHighlightedIndex == boundedIndex:
    return
  listView.xHighlightedIndex = boundedIndex
  listView.invalidateListRows()

proc usesAlternatingRowBackgrounds*(listView: ListView): bool =
  listView.xUsesAlternatingRowBackgrounds

proc `usesAlternatingRowBackgrounds=`*(listView: ListView, value: bool) =
  if listView.xUsesAlternatingRowBackgrounds == value:
    return
  listView.xUsesAlternatingRowBackgrounds = value
  listView.invalidateListRows()

proc showsRowSeparators*(listView: ListView): bool =
  listView.xShowsRowSeparators

proc `showsRowSeparators=`*(listView: ListView, value: bool) =
  if listView.xShowsRowSeparators == value:
    return
  listView.xShowsRowSeparators = value
  listView.invalidateListRows()

proc rowHeight*(listView: ListView): float32 =
  listView.xRowHeight.normalizedRowHeight()

proc `rowHeight=`*(listView: ListView, height: float32) =
  let normalized = height.normalizedRowHeight()
  if listView.xRowHeight == normalized:
    return
  listView.xRowHeight = normalized
  listView.xRowHeightCacheValid = false
  listView.reloadData()

proc uncachedRowHeightForRow(listView: ListView, index: int): float32 =
  if index notin 0 ..< listView.len():
    return 0.0'f32
  if not listView.xDelegate.isNil:
    let cocoaHeight =
      listView.xDelegate.trySendLocal(heightOfRow(), (listView: listView, row: index))
    if cocoaHeight.isSome:
      return cocoaHeight.get().normalizedRowHeight()
    let height =
      listView.xDelegate.trySendLocal(heightForRow(), (listView: listView, row: index))
    if height.isSome:
      return height.get().normalizedRowHeight()
  listView.rowHeight()

proc ensureRowHeightCache(listView: ListView) =
  if listView.xRowHeightCacheValid or listView.xComputingRowHeights:
    return
  listView.xComputingRowHeights = true
  try:
    var
      heights: seq[float32]
      offsets: seq[float32]
      offset = 0.0'f32
    for index in 0 ..< listView.len():
      offsets.add offset
      let height = listView.uncachedRowHeightForRow(index)
      heights.add height
      offset += height
    listView.xRowHeights = heights
    listView.xRowOffsets = offsets
    listView.xRowHeightCacheValid = true
  finally:
    listView.xComputingRowHeights = false

proc invalidateRowHeightCache(listView: ListView) =
  listView.xRowHeightCacheValid = false

proc rowOffset(listView: ListView, index: int): float32 =
  if index <= 0:
    return 0.0'f32
  listView.ensureRowHeightCache()
  if index >= listView.xRowHeights.len:
    result = 0.0'f32
    for height in listView.xRowHeights:
      result += height
  elif index < listView.xRowOffsets.len:
    result = listView.xRowOffsets[index]

proc rowIndexAtContentY(listView: ListView, y: float32): int =
  if listView.len() <= 0:
    return -1
  listView.ensureRowHeightCache()
  let targetY = max(y, 0.0'f32)
  for index, offset in listView.xRowOffsets:
    if targetY < offset + listView.xRowHeights[index]:
      return index
  listView.len() - 1

proc contentHeight(listView: ListView): float32 =
  listView.rowOffset(listView.len())

proc visibleRowsFrom(listView: ListView, firstIndex: int, height: float32): int =
  if listView.len() <= 0 or firstIndex < 0 or height <= 0.0'f32:
    return 0
  var
    count = 0
    consumed = 0.0'f32
    index = firstIndex
  while index < listView.len():
    let next = consumed + listView.rowHeightForRow(index)
    if count > 0 and next > height:
      break
    consumed = next
    inc count
    inc index
  max(count, 1)

proc maxFirstVisibleIndex(listView: ListView): int =
  if listView.len() <= 0:
    return 0
  listView.rowIndexAtContentY(
    max(listView.contentHeight() - listView.viewportSize().height, 0.0'f32)
  )

proc rowHeightForRow*(listView: ListView, index: int): float32 =
  if index < 0 or index >= listView.len():
    return 0.0'f32
  if listView.xComputingRowHeights:
    return listView.rowHeight()
  listView.ensureRowHeightCache()
  if index < listView.xRowHeights.len:
    listView.xRowHeights[index]
  else:
    listView.rowHeight()

proc noteRowHeightsChanged*(listView: ListView) =
  let oldFirst = listView.firstVisibleIndex()
  listView.invalidateRowHeightCache()
  listView.tileListContent()
  listView.setListContentOffset(initPoint(0.0'f32, listView.rowOffset(oldFirst)), false)
  listView.invalidateIntrinsicContentSize()
  listView.invalidateListRows()

proc noteHeightOfRowsChanged*(listView: ListView, rows: openArray[int]) =
  if rows.len == 0:
    return
  listView.noteRowHeightsChanged()

proc noteHeightOfRowChanged*(listView: ListView, row: int) =
  if row in 0 ..< listView.len():
    listView.noteHeightOfRowsChanged([row])

proc visibleRows*(listView: ListView): int =
  listView.xVisibleRows

proc `visibleRows=`*(listView: ListView, rows: int) =
  let normalized = max(rows, 1)
  if listView.xVisibleRows == normalized:
    return
  listView.xVisibleRows = normalized
  listView.reloadData()

proc selectionMode*(listView: ListView): ListSelectionMode =
  listView.xSelectionMode

proc `selectionMode=`*(listView: ListView, mode: ListSelectionMode) =
  if listView.xSelectionMode == mode:
    return
  listView.xSelectionMode = mode
  if mode == lsmNone:
    listView.xSelectedIndex = -1
    listView.xSelectedIndexes.setLen(0)
    listView.xSelectionAnchor = -1
    listView.xSelectionLead = -1
  elif mode == lsmSingle and listView.xSelectedIndexes.len > 1:
    listView.xSelectedIndexes.setLen(1)
    listView.xSelectedIndex = listView.xSelectedIndexes[0]
    listView.xSelectionAnchor = listView.xSelectedIndex
    listView.xSelectionLead = listView.xSelectedIndex
  listView.reloadData()

proc showsVerticalScroller*(listView: ListView): bool =
  if listView.len() <= 0:
    return false
  listView.contentHeight() > max(listView.bounds().size.height - 2.0'f32, 0.0'f32)

proc setListViewRoles*(
    listView: ListView,
    listRole: StyleRole = srListView,
    itemRole: StyleRole = srListItem,
) =
  if listView.xListRole == listRole and listView.xItemRole == itemRole:
    return
  listView.xListRole = listRole
  listView.xItemRole = itemRole
  listView.reloadData()

proc rowEnabled*(listView: ListView, index: int): bool =
  if index notin 0 ..< listView.len() or not listView.isEnabled():
    return false
  if not listView.xDelegate.isNil:
    let enabled =
      listView.xDelegate.trySendLocal(rowIsEnabled(), (listView: listView, row: index))
    if enabled.isSome:
      return enabled.get()
  true

proc rowSelectable*(listView: ListView, index: int): bool =
  if not listView.rowEnabled(index):
    return false
  if not listView.xDelegate.isNil:
    let selectable = listView.xDelegate.trySendLocal(
      shouldSelectRow(), (listView: listView, row: index)
    )
    if selectable.isSome:
      return selectable.get()
  true

proc rowStyle*(listView: ListView, row: ListRowState): ListRowStyle =
  if listView.xDelegate.isNil or row.index < 0:
    return initListRowStyle()
  let style =
    listView.xDelegate.trySendLocal(styleForRow(), (listView: listView, row: row))
  if style.isSome:
    style.get()
  else:
    initListRowStyle()

proc drawListRow*(
    listView: ListView, context: DrawContext, rect: Rect, row: ListRowState
) =
  if listView.isNil or context.isNil:
    return
  var style = listView.rowStyle(row)
  if row.alternating and not row.selected and style.fill.isNone:
    style.fill = some(fill(initColor(0.96, 0.97, 0.99, 1.0)))
  context.drawListRow(
    rect, row, style, listView.xItemRole, listView.styleId(), listView.styleClasses()
  )
  if listView.showsRowSeparators() and row.index >= 0 and row.index < listView.len() - 1:
    let
      itemStyle = context.appearance.resolveListItemStyle(
        initControlStyleContext(
          listView.xItemRole,
          enabled = row.enabled,
          id = listView.styleId(),
          classes = listView.styleClasses(),
        )
      )
      separatorRect = initRect(rect.origin.x, rect.maxY - 1.0'f32, rect.size.width, 1.0)
    discard context.addWindowRectangle(separatorRect, fill(itemStyle.box.borderColor))

proc drawCustomListRow(
    listView: ListView, context: DrawContext, rect: Rect, row: ListRowState
): bool =
  if listView.isNil or listView.xDelegate.isNil or context.isNil:
    return false
  listView.xDelegate.sendLocalIfHandled(
    drawRow(), (listView: listView, context: context, rect: rect, row: row)
  )

proc drawCustomEmptyState(listView: ListView, context: DrawContext, rect: Rect): bool =
  if listView.isNil or listView.xDelegate.isNil or context.isNil or rect.isEmpty:
    return false
  listView.xDelegate.sendLocalIfHandled(
    drawEmptyState(), (listView: listView, context: context, rect: rect)
  )

proc viewportSize(listView: ListView): Size =
  initSize(
    max(
      listView.bounds().size.width - 2.0'f32 -
        (if listView.showsVerticalScroller(): ListScrollerThickness else: 0.0'f32),
      0.0'f32,
    ),
    max(listView.bounds().size.height - 2.0'f32, 0.0'f32),
  )

proc contentSize*(listView: ListView): Size =
  initSize(listView.viewportSize().width, listView.contentHeight())

proc visibleItemCount*(listView: ListView): int =
  if listView.len() <= 0:
    return 0
  let
    contentHeight = listView.viewportSize().height
    visibleFromBounds =
      listView.visibleRowsFrom(listView.firstVisibleIndex(), contentHeight)
    preferredRows =
      if visibleFromBounds > 0:
        visibleFromBounds
      else:
        listView.visibleRows()
  visibleListItemCount(listView.len(), preferredRows)

proc clampListContentOffset(listView: ListView, offset: Point): Point =
  let
    viewportSize = listView.viewportSize()
    contentSize = listView.contentSize()
    horizontal = initScrollViewport(0.0, viewportSize.width, contentSize.width)
    maxY = max(contentSize.height - viewportSize.height, 0.0'f32)
  initPoint(
    horizontal.clampScrollOffset(offset.x),
    min(max(offset.y, 0.0'f32), max(maxY, 0.0'f32)),
  )

proc syncListViewport(listView: ListView, offset: Point) =
  listView.xViewport.reset(listView.rowIndexAtContentY(offset.y))
  listView.xViewport.normalize(listView.len(), listView.visibleItemCount())

proc listContentOffset(listView: ListView): Point =
  if listView.xClipView.isNil:
    return initPoint(0.0, 0.0)
  listView.clampListContentOffset(listView.xClipView.bounds().origin)

proc setListContentOffset(listView: ListView, offset: Point, invalidate: bool) =
  if listView.xClipView.isNil:
    return
  let
    nextOffset = listView.clampListContentOffset(offset)
    nextBounds = initRect(nextOffset, listView.viewportSize())
  if listView.xClipView.bounds() != nextBounds:
    listView.xClipView.bounds = nextBounds
    if invalidate:
      listView.invalidateListRows()
  listView.syncListViewport(nextOffset)
  if not listView.xContentView.isNil:
    listView.xContentView.syncVisibleRowViews()

proc firstVisibleIndex*(listView: ListView): int =
  listView.rowIndexAtContentY(listView.listContentOffset().y)

proc listScrollerKnobRect(listView: ListView, track: Rect): Rect =
  if track.isEmpty:
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

proc tileListContent(listView: ListView) =
  if listView.xClipView.isNil or listView.xContentView.isNil:
    return
  let
    offset = listView.listContentOffset()
    viewport = initRect(initPoint(1.0'f32, 1.0'f32), listView.viewportSize())
    size = listView.contentSize()
  listView.xClipView.frame = viewport
  listView.xContentView.frame = initRect(0.0'f32, 0.0'f32, size.width, size.height)
  if not listView.xVerticalScroller.isNil:
    let scrollerRect = listView.verticalScrollerRect()
    listView.xVerticalScroller.frame = scrollerRect
    listView.xVerticalScroller.hidden = scrollerRect.isEmpty
  listView.setListContentOffset(offset, false)

proc `firstVisibleIndex=`*(listView: ListView, index: int) =
  let oldFirst = listView.firstVisibleIndex()
  listView.tileListContent()
  listView.setListContentOffset(
    initPoint(0.0'f32, listView.rowOffset(max(index, 0))), false
  )
  if listView.firstVisibleIndex() != oldFirst:
    listView.invalidateListRows()

proc normalizeSelection(listView: ListView, indexes: openArray[int]): seq[int] =
  if listView.xSelectionMode == lsmNone or listView.len() == 0:
    return @[]
  for index in indexes:
    if listView.rowSelectable(index):
      result.add index
  result.sort()
  var writeIndex = 0
  for index in result:
    if writeIndex == 0 or result[writeIndex - 1] != index:
      result[writeIndex] = index
      inc writeIndex
  result.setLen(writeIndex)
  if listView.xSelectionMode == lsmSingle and result.len > 1:
    result.setLen(1)

proc validListIndex(listView: ListView, index: int): bool =
  not listView.isNil and index >= 0 and index < listView.len()

proc firstSelectedIndex(indexes: openArray[int]): int =
  if indexes.len == 0:
    -1
  else:
    indexes[0]

proc syncSelectedIndex(listView: ListView) =
  listView.xSelectedIndex = firstSelectedIndex(listView.xSelectedIndexes)

proc normalizeSelectionAnchor(listView: ListView, anchor: int): int =
  if listView.rowSelectable(anchor): anchor else: listView.xSelectedIndex

proc syncSelectionCursor(listView: ListView) =
  if listView.xSelectedIndexes.len == 0:
    listView.xSelectionAnchor = -1
    listView.xSelectionLead = -1
    return
  if listView.xSelectionMode == lsmSingle:
    listView.xSelectionAnchor = listView.xSelectedIndex
    listView.xSelectionLead = listView.xSelectedIndex
    return
  if not listView.rowSelectable(listView.xSelectionAnchor):
    listView.xSelectionAnchor = listView.xSelectedIndex
  if not listView.rowSelectable(listView.xSelectionLead):
    listView.xSelectionLead = listView.xSelectedIndex

proc firstSelectableIndex(listView: ListView): int =
  for index in 0 ..< listView.len():
    if listView.rowSelectable(index):
      return index
  -1

proc lastSelectableIndex(listView: ListView): int =
  for countdown in 0 ..< listView.len():
    let index = listView.len() - countdown - 1
    if listView.rowSelectable(index):
      return index
  -1

proc nextSelectableIndex(listView: ListView, index, delta: int): int =
  if delta == 0 or listView.len() == 0:
    return -1
  let step = if delta < 0: -1 else: 1
  var current = index
  while current >= 0 and current < listView.len():
    if listView.rowSelectable(current):
      return current
    current += step
  -1

proc reloadData*(listView: ListView) =
  let oldFirst = listView.firstVisibleIndex()
  listView.invalidateRowHeightCache()
  if listView.xSelectionMode == lsmSingle and listView.xSelectedIndexes.len > 0 and
      listView.len() > 0:
    listView.xSelectedIndexes[0] =
      min(max(listView.xSelectedIndexes[0], -1), listView.len() - 1)
  if listView.xSelectionMode == lsmSingle and listView.xSelectedIndex >= listView.len() and
      listView.len() > 0:
    listView.xSelectedIndex = listView.len() - 1
  if listView.xSelectedIndexes.len == 0 and listView.xSelectedIndex >= 0:
    listView.xSelectedIndexes.add listView.xSelectedIndex
  listView.xSelectedIndexes = listView.normalizeSelection(listView.xSelectedIndexes)
  listView.syncSelectedIndex()
  listView.syncSelectionCursor()

  if not listView.rowEnabled(listView.xHighlightedIndex):
    listView.xHighlightedIndex = -1
  if not listView.rowEnabled(listView.xPressedIndex):
    listView.xPressedIndex = -1
  listView.tileListContent()
  listView.setListContentOffset(
    initPoint(
      0.0'f32, listView.rowOffset(min(oldFirst, listView.maxFirstVisibleIndex()))
    ),
    false,
  )
  if listView.xSelectedIndex >= 0:
    listView.scrollItemToVisible(listView.xSelectedIndex)
  listView.invalidateIntrinsicContentSize()
  listView.invalidateListRows()

proc listContentItemRect*(contentView: ListContentView, itemIndex: int): Rect =
  let listView = contentView.listView()
  if itemIndex notin 0 ..< listView.len():
    return initRect(0.0, 0.0, 0.0, 0.0)
  initRect(
    0.0'f32,
    listView.rowOffset(itemIndex),
    max(contentView.bounds().size.width, 0.0'f32),
    listView.rowHeightForRow(itemIndex),
  )

proc listContentItemIndexAtPoint*(contentView: ListContentView, point: Point): int =
  let listView = contentView.listView()
  if not contentView.bounds().contains(point):
    return -1
  let index = listView.rowIndexAtContentY(point.y)
  if index < 0 or index >= listView.len():
    return -1
  index

proc listItemRect*(listView: ListView, itemIndex: int): Rect =
  listView.tileListContent()
  let
    contentView = listView.contentView()
    contentRect = contentView.listContentItemRect(itemIndex)
  if contentRect.isEmpty:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let visibleRect =
    contentView.rectToView(contentRect, listView).intersection(listView.bounds())
  if visibleRect.size.height < listView.rowHeightForRow(itemIndex) or visibleRect.isEmpty:
    initRect(0.0, 0.0, 0.0, 0.0)
  else:
    visibleRect

proc listItemIndexAtPoint*(listView: ListView, point: Point): int =
  listView.tileListContent()
  let contentView = listView.contentView()
  if contentView.isNil:
    return -1
  contentView.listContentItemIndexAtPoint(contentView.pointFromView(point, listView))

proc scrollContentRectToVisible(listView: ListView, rect: Rect) =
  let oldFirst = listView.firstVisibleIndex()
  if rect.isEmpty:
    return
  let
    visible = listView.listContentOffset()
    viewportHeight = listView.viewportSize().height
  var nextY = visible.y
  if rect.minY < visible.y:
    nextY = rect.minY
  elif rect.maxY > visible.y + viewportHeight:
    nextY = rect.maxY - viewportHeight
  listView.setListContentOffset(initPoint(0.0'f32, nextY), false)
  if listView.firstVisibleIndex() != oldFirst:
    listView.invalidateListRows()

proc scrollItemToVisible*(listView: ListView, itemIndex: int) =
  if itemIndex < 0 or itemIndex >= listView.len():
    return
  listView.scrollContentRectToVisible(
    listView.contentView().listContentItemRect(itemIndex)
  )

proc scrollSelectedItemToVisible*(listView: ListView) =
  listView.scrollItemToVisible(listView.selectedIndex())

proc scrollSelectionToVisible*(listView: ListView) =
  let lead = listView.selectionLeadIndex()
  if lead >= 0:
    listView.scrollItemToVisible(lead)

proc canScrollRows*(listView: ListView, delta: int): bool =
  let
    currentY = listView.listContentOffset().y
    nextIndex = max(listView.firstVisibleIndex() + delta, 0)
    nextY = listView.clampListContentOffset(
      initPoint(0.0'f32, listView.rowOffset(nextIndex))
    ).y
  delta != 0 and nextY != currentY

proc scrollRows*(listView: ListView, delta: int) =
  if delta == 0:
    return
  let oldFirst = listView.firstVisibleIndex()
  let nextFirst = max(oldFirst + delta, 0)
  listView.setListContentOffset(
    initPoint(0.0'f32, listView.rowOffset(nextFirst)), false
  )
  if listView.firstVisibleIndex() != oldFirst:
    listView.invalidateListRows()

proc selectionContains(listView: ListView, index: int): bool =
  for selectedIndex in listView.xSelectedIndexes:
    if selectedIndex == index:
      return true
  false

proc listRowState(listView: ListView, index: int): ListRowState =
  if index notin 0 ..< listView.len():
    initListRowState(-1, "", enabled = false)
  else:
    initListRowState(
      index,
      listView[index],
      selected = listView.selectionContains(index),
      highlighted = index == listView.highlightedIndex(),
      alternating = listView.usesAlternatingRowBackgrounds() and index mod 2 == 1,
      pressed = index == listView.xPressedIndex,
      enabled = listView.rowEnabled(index),
      focused = listView.isFocused(),
    )

proc selectedIndexes*(listView: ListView): seq[int] =
  listView.xSelectedIndexes

proc selectedRange*(listView: ListView): Slice[int] =
  let ranges = listView.selectedRanges()
  if ranges.len == 0:
    0 .. -1
  else:
    ranges[0]

proc selectedRanges*(listView: ListView): seq[Slice[int]] =
  if listView.xSelectedIndexes.len == 0:
    return @[]
  var
    firstIndex = listView.xSelectedIndexes[0]
    previousIndex = firstIndex
  for offset in 1 ..< listView.xSelectedIndexes.len:
    let index = listView.xSelectedIndexes[offset]
    if index == previousIndex + 1:
      previousIndex = index
    else:
      result.add firstIndex .. previousIndex
      firstIndex = index
      previousIndex = index
  result.add firstIndex .. previousIndex

proc indexesInRange(selectionRange: Slice[int]): seq[int] =
  if selectionRange.b < selectionRange.a:
    return @[]
  for index in selectionRange.a .. selectionRange.b:
    result.add index

proc applySelectedIndexes(
    listView: ListView, indexes: openArray[int], anchor: int, lead: int
) =
  let nextIndexes = listView.normalizeSelection(indexes)
  let
    nextSelected = firstSelectedIndex(nextIndexes)
    nextAnchor =
      if nextIndexes.len == 0:
        -1
      elif listView.rowSelectable(anchor):
        anchor
      else:
        nextSelected
    nextLead =
      if nextIndexes.len == 0:
        -1
      elif listView.rowSelectable(lead):
        lead
      else:
        nextSelected
    selectionChanged = listView.xSelectedIndexes != nextIndexes
  if not selectionChanged:
    listView.xSelectionAnchor = nextAnchor
    listView.xSelectionLead = nextLead
    if nextLead >= 0:
      listView.scrollItemToVisible(nextLead)
    return
  emit listView.selectionIsChanging(DynamicAgent(listView))
  listView.xSelectedIndexes = nextIndexes
  listView.syncSelectedIndex()
  listView.xSelectionAnchor = nextAnchor
  listView.xSelectionLead = nextLead
  if nextLead >= 0:
    listView.scrollItemToVisible(nextLead)
  listView.invalidateListRows()
  emit listView.selectionDidChange(DynamicAgent(listView))

proc `selectedIndexes=`*(listView: ListView, indexes: openArray[int]) =
  let nextIndexes = listView.normalizeSelection(indexes)
  listView.applySelectedIndexes(
    nextIndexes, firstSelectedIndex(nextIndexes), firstSelectedIndex(nextIndexes)
  )

proc `selectedRange=`*(listView: ListView, selectionRange: Slice[int]) =
  let indexes = selectionRange.indexesInRange()
  listView.selectedIndexes = indexes

proc selectItemAtIndex(listView: ListView, index: int) =
  if listView.xSelectionMode == lsmNone:
    return
  let boundedIndex = if index < 0 or index >= listView.len(): -1 else: index
  if boundedIndex >= 0 and not listView.rowSelectable(boundedIndex):
    return
  if listView.xSelectedIndex == boundedIndex and listView.xSelectedIndexes.len <= 1:
    if boundedIndex >= 0:
      listView.scrollItemToVisible(boundedIndex)
    return
  if boundedIndex < 0:
    listView.selectedIndexes = @[]
  else:
    listView.applySelectedIndexes([boundedIndex], boundedIndex, boundedIndex)

proc rangeSelectionIndexes(anchor, lead: int): seq[int] =
  if anchor < 0 or lead < 0:
    return @[]
  let
    firstIndex = min(anchor, lead)
    lastIndex = max(anchor, lead)
  for index in firstIndex .. lastIndex:
    result.add index

proc extendSelectionToIndex(listView: ListView, index: int) =
  if listView.xSelectionMode != lsmExtended:
    listView.selectItemAtIndex(index)
    return
  let boundedIndex = if listView.validListIndex(index): index else: -1
  if boundedIndex < 0 or not listView.rowSelectable(boundedIndex):
    return
  let anchor = listView.normalizeSelectionAnchor(listView.xSelectionAnchor)
  listView.applySelectedIndexes(
    rangeSelectionIndexes(anchor, boundedIndex), anchor, boundedIndex
  )

proc toggleSelectionAtIndex(listView: ListView, index: int) =
  if listView.xSelectionMode notin {lsmMultiple, lsmExtended}:
    listView.selectItemAtIndex(index)
    return
  if not listView.rowSelectable(index):
    return
  var nextIndexes: seq[int]
  if listView.selectionContains(index):
    for selectedIndex in listView.xSelectedIndexes:
      if selectedIndex != index:
        nextIndexes.add selectedIndex
  else:
    nextIndexes = listView.xSelectedIndexes
    nextIndexes.add index
  listView.applySelectedIndexes(nextIndexes, index, index)

proc usesDiscontiguousSelection(modifiers: set[KeyModifier]): bool =
  kmCommand in modifiers or kmControl in modifiers

proc selectItemAtIndex(listView: ListView, index: int, modifiers: set[KeyModifier]) =
  if listView.xSelectionMode == lsmNone:
    return
  if kmShift in modifiers and listView.xSelectionMode == lsmExtended:
    listView.extendSelectionToIndex(index)
  elif modifiers.usesDiscontiguousSelection() and
      listView.xSelectionMode in {lsmMultiple, lsmExtended}:
    listView.toggleSelectionAtIndex(index)
  else:
    listView.selectItemAtIndex(index)

proc selectedIndex*(listView: ListView): int =
  listView.xSelectedIndex

proc `selectedIndex=`*(listView: ListView, index: int) =
  if index < 0:
    listView.selectedIndexes = @[]
  else:
    listView.selectItemAtIndex(index)

proc sendListActivation(listView: ListView, index: int) =
  if not listView.rowEnabled(index):
    return
  emit listView.rowWasActivated(DynamicAgent(listView))
  discard listView.sendAction()

proc activateItemAtIndex(listView: ListView, index: int, modifiers: set[KeyModifier]) =
  if not listView.rowEnabled(index):
    return
  if listView.selectionMode() != lsmNone:
    if not listView.rowSelectable(index):
      return
    listView.selectItemAtIndex(index, modifiers)
  listView.sendListActivation(index)

proc activateItemAtIndex*(listView: ListView, index: int) =
  listView.activateItemAtIndex(index, {})

proc selectionLeadIndex(listView: ListView): int =
  if listView.validListIndex(listView.xSelectionLead):
    listView.xSelectionLead
  else:
    listView.selectedIndex()

proc selectionSummary*(listView: ListView): ListSelectionSummary =
  ListSelectionSummary(
    mode: listView.selectionMode(),
    selectedIndex: listView.selectedIndex(),
    selectedIndexes: listView.selectedIndexes(),
    anchorIndex: listView.xSelectionAnchor,
    leadIndex: listView.selectionLeadIndex(),
    hasSelection: listView.xSelectedIndexes.len > 0,
  )

proc typeSelectStartIndex(listView: ListView): int =
  if listView.selectionLeadIndex() >= 0:
    listView.selectionLeadIndex() + 1
  elif listView.selectedIndex() >= 0:
    listView.selectedIndex() + 1
  else:
    listView.firstVisibleIndex()

proc rowTextMatchesPrefix(
    listView: ListView, index: int, normalizedPrefix: string
): bool =
  listView[index].toLowerAscii().startsWith(normalizedPrefix)

proc firstRowMatchingText(listView: ListView, text: string): int =
  if text.len == 0 or listView.len() == 0:
    return -1
  let
    normalized = text.toLowerAscii()
    start = max(listView.typeSelectStartIndex(), 0)
  for offset in 0 ..< listView.len():
    let index = (start + offset) mod listView.len()
    if listView.rowSelectable(index) and listView.rowTextMatchesPrefix(
      index, normalized
    ):
      return index
  -1

proc selectItemMatchingText(listView: ListView, text: string): bool =
  if listView.selectionMode() == lsmNone:
    return false
  let index = listView.firstRowMatchingText(text)
  if index < 0:
    return false
  listView.selectItemAtIndex(index)
  true

proc isTypeSelectEvent(event: KeyEvent): bool =
  event.text.len > 0 and event.text notin [" ", "\n", "\r", "\t"] and
    event.modifiers * {kmControl, kmOption, kmCommand} == {}

proc handleTypeSelect(listView: ListView, event: KeyEvent): bool =
  if not event.isTypeSelectEvent():
    return false
  let now = epochTime()
  if now - listView.xTypeSelectLastTime > ListTypeSelectTimeout:
    listView.xTypeSelectBuffer = ""
  listView.xTypeSelectLastTime = now
  listView.xTypeSelectBuffer.add event.text
  if listView.selectItemMatchingText(listView.xTypeSelectBuffer):
    return true
  if event.text != listView.xTypeSelectBuffer:
    listView.xTypeSelectBuffer = event.text
    return listView.selectItemMatchingText(listView.xTypeSelectBuffer)
  false

proc moveSelectionTo(listView: ListView, index: int, extend = false, direction = 1) =
  if listView.len() == 0 or listView.selectionMode() == lsmNone:
    return
  let boundedIndex =
    listView.nextSelectableIndex(max(0, min(index, listView.len() - 1)), direction)
  if boundedIndex < 0:
    return
  if extend and listView.xSelectionMode == lsmExtended:
    listView.extendSelectionToIndex(boundedIndex)
  else:
    listView.selectItemAtIndex(boundedIndex)

proc moveSelection(listView: ListView, delta: int, extend = false) =
  let start =
    if listView.selectionLeadIndex() >= 0:
      listView.selectionLeadIndex()
    elif delta > 0:
      listView.firstVisibleIndex() - 1
    elif delta < 0:
      listView.firstVisibleIndex() + listView.visibleItemCount()
    else:
      listView.firstVisibleIndex()
  listView.moveSelectionTo(start + delta, extend, delta)

proc pageSelection(listView: ListView, deltaPages: int, extend = false) =
  listView.moveSelection(deltaPages * max(listView.visibleItemCount(), 1), extend)

proc visibleContentRows(contentView: ListContentView): tuple[first, last: int] =
  let listView = contentView.listView()
  if listView.len() <= 0:
    return (0, 0)
  let visible = contentView.visibleRect()
  if visible.isEmpty:
    return (0, 0)
  result.first = max(listView.rowIndexAtContentY(visible.minY), 0)
  result.last = result.first
  while result.last < listView.len() and listView.rowOffset(result.last) < visible.maxY:
    inc result.last
  if result.last < result.first:
    result.last = result.first

proc visibleRowSummaries*(listView: ListView): seq[ListVisibleRowSummary] =
  if listView.isNil:
    return @[]
  listView.tileListContent()
  let contentView = listView.contentView()
  if contentView.isNil:
    return @[]
  let rows = contentView.visibleContentRows()
  for index in rows.first ..< rows.last:
    let
      row = listView.listRowState(index)
      contentRect = contentView.listContentItemRect(index)
      rect =
        contentView.rectToView(contentRect, listView).intersection(listView.bounds())
    if not rect.isEmpty:
      result.add ListVisibleRowSummary(
        index: row.index,
        text: row.text,
        rect: rect,
        selected: row.selected,
        highlighted: row.highlighted,
        enabled: row.enabled,
        focused: row.focused,
      )

proc configureRowView(rowView: ListRowView, itemIndex: int) =
  let listView = rowView.listView()
  if listView.xContentView.isNil:
    return
  rowView.xRow = listView.listRowState(itemIndex)
  rowView.frame = listView.xContentView.listContentItemRect(itemIndex)

proc removeLastRowView(contentView: ListContentView) =
  if contentView.isNil or contentView.xRowViews.len == 0:
    return
  let rowView = contentView.xRowViews[^1]
  contentView.xRowViews.setLen(contentView.xRowViews.len - 1)
  rowView.removeFromSuperview()

proc syncVisibleRowViews(contentView: ListContentView) =
  let listView = contentView.listView()
  let
    rows = contentView.visibleContentRows()
    needed = max(rows.last - rows.first, 0)
  while contentView.xRowViews.len < needed:
    let rowView = initListRowView(listView)
    contentView.xRowViews.add rowView
    contentView.addSubview(rowView)
  while contentView.xRowViews.len > needed:
    contentView.removeLastRowView()
  for slot in 0 ..< needed:
    contentView.xRowViews[slot].configureRowView(rows.first + slot)

proc scrollListKnobTo(scroller: ListScroller, point: Point) =
  let listView = scroller.listView()
  if scroller.isNil or listView.isNil:
    return
  let
    track = scroller.bounds()
    maxFirst = listView.maxFirstVisibleIndex()
    next = contentOffsetForScrollerKnobOrigin(
      track,
      listView.listScrollerKnobRect(track),
      laVertical,
      maxFirst.float32,
      scroller.xTracking.knobOriginForPoint(laVertical, point),
    )
  listView.firstVisibleIndex = min(max(round(next).int, 0), maxFirst)

proc scrollListPageToward(scroller: ListScroller, point: Point) =
  let listView = scroller.listView()
  if scroller.isNil or listView.isNil:
    return
  let knob = listView.listScrollerKnobRect(scroller.bounds())
  if knob.isEmpty or (point.y >= knob.minY and point.y < knob.maxY):
    return
  let direction = if point.y < knob.minY: -1 else: 1
  listView.scrollRows(direction * max(listView.visibleItemCount(), 1))

proc naturalSize(listView: ListView): Size =
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

  var
    maxTextWidth = 0.0'f32
    naturalHeight = 0.0'f32
  for index in 0 ..< listView.len():
    maxTextWidth = max(maxTextWidth, textNaturalSize(listView[index]).width)
    if index < rowCount:
      naturalHeight += listView.rowHeightForRow(index)
  if listView.len() == 0:
    naturalHeight = listView.rowHeight() * rowCount.float32

  initSize(
    max(
      listStyle.minSize.width,
      max(
        itemStyle.minSize.width,
        maxTextWidth + itemStyle.text.insets.horizontal + 2.0'f32,
      ),
    ),
    max(listStyle.minSize.height, naturalHeight + 2.0'f32),
  )

protocol DefaultListRowViewDrawing of ViewDrawingProtocol:
  method draw(rowView: ListRowView, context: DrawContext) =
    let listView = rowView.listView()
    if rowView.isNil or listView.isNil:
      return
    let rect = rowView.bounds()
    if not listView.drawCustomListRow(context, rect, rowView.xRow):
      listView.drawListRow(context, rect, rowView.xRow)

protocol DefaultListRowViewHitTesting of ViewProtocol:
  method pointInside(rowView: ListRowView, point: Point): bool =
    false

protocol DefaultListContentViewDrawing of ViewDrawingProtocol:
  method draw(contentView: ListContentView, context: DrawContext) =
    contentView.syncVisibleRowViews()

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
      if scroller.xTracking.isDraggingKnob():
        scroller.scrollListKnobTo(event.location)
      scroller.xTracking.endScrollerTracking()

protocol DefaultListViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(listView: ListView): IntrinsicSize =
    initIntrinsicSize(listView.naturalSize())

  method layoutSubviews(listView: ListView) =
    listView.tileListContent()

protocol DefaultListViewDrawing of ViewDrawingProtocol:
  method draw(listView: ListView, context: DrawContext) =
    if listView.bounds().isEmpty:
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

    if listView.len() == 0 and not listView.clipView().isNil:
      discard listView.drawCustomEmptyState(context, listView.clipView().frame())

    if listView.isFocusVisible:
      context.addFocusRing(listView.rectToWindow(listView.bounds), listStyle.box)

protocol DefaultListViewEvents of ResponderEventProtocol:
  method mouseDown(listView: ListView, event: MouseEvent) =
    if not listView.isEnabled() or event.button != mbPrimary:
      return
    listView.xTrackingItem = true
    let index = listView.listItemIndexAtPoint(event.location)
    listView.highlightedIndex = index
    listView.xPressedIndex = listView.highlightedIndex()
    listView.invalidateListRows()

  method mouseDragged(listView: ListView, event: MouseEvent) =
    if listView.isEnabled() and listView.xTrackingItem:
      let index = listView.listItemIndexAtPoint(event.location)
      listView.highlightedIndex = index
      listView.xPressedIndex = listView.highlightedIndex()
      listView.invalidateListRows()

  method mouseMoved(listView: ListView, event: MouseEvent) =
    if listView.isEnabled():
      listView.highlightedIndex = listView.listItemIndexAtPoint(event.location)

  method mouseUp(listView: ListView, event: MouseEvent) =
    if not listView.isEnabled() or event.button != mbPrimary:
      return
    let index =
      if listView.xTrackingItem:
        listView.listItemIndexAtPoint(event.location)
      else:
        -1
    listView.xTrackingItem = false
    listView.xPressedIndex = -1
    if index >= 0:
      listView.activateItemAtIndex(index, event.modifiers)
    listView.setNeedsDisplay(true)

  method wantsForwardedScrollEvents(listView: ListView, event: ScrollEvent): bool =
    listView.isNil or not listView.isEnabled() or
      not listView.canScrollRows(listScrollRows(event))

  method scrollWheel(listView: ListView, event: ScrollEvent) =
    let delta = listScrollRows(event)
    if listView.isEnabled() and listView.canScrollRows(delta):
      listView.scrollRows(delta)

  method keyDown(listView: ListView, event: KeyEvent) =
    if not listView.isEnabled():
      return
    let extendSelection = kmShift in event.modifiers
    case event.key
    of keyArrowDown:
      listView.moveSelection(1, extendSelection)
    of keyArrowUp:
      listView.moveSelection(-1, extendSelection)
    of keyPageDown:
      listView.pageSelection(1, extendSelection)
    of keyPageUp:
      listView.pageSelection(-1, extendSelection)
    of keyHome:
      listView.moveSelectionTo(listView.firstSelectableIndex(), extendSelection)
    of keyEnd:
      listView.moveSelectionTo(listView.lastSelectableIndex(), extendSelection, -1)
    of keyEnter, keySpace:
      let activeIndex = listView.selectionLeadIndex()
      if activeIndex >= 0:
        listView.sendListActivation(activeIndex)
    else:
      discard listView.handleTypeSelect(event)

proc initListBaseChild(view: View, clipsToBounds: bool) =
  initViewFields(view, initRect(0.0, 0.0, 0.0, 0.0))
  view.background = initColor(0.0, 0.0, 0.0, 0.0)
  view.clipsToBounds = clipsToBounds
  view.autoresizingMaskConstraints = false
  view.setAcceptsFirstResponder(false)

proc initListClipView(): ClipView =
  result = ClipView()
  initListBaseChild(result, true)
  discard result.withProtocol(DefaultListClipViewHitTesting)

proc initListRowView(listView: ListView): ListRowView =
  result = ListRowView()
  initListBaseChild(result, false)
  result.xListView = listView
  discard result.withProtocol(DefaultListRowViewDrawing)
  discard result.withProtocol(DefaultListRowViewHitTesting)

proc initListContentView(listView: ListView): ListContentView =
  result = ListContentView()
  initListBaseChild(result, false)
  result.xListView = listView
  discard result.withProtocol(DefaultListContentViewDrawing)
  discard result.withProtocol(DefaultListContentViewHitTesting)

proc initListScroller(listView: ListView): ListScroller =
  result = ListScroller()
  initListBaseChild(result, false)
  result.xListView = listView
  result.hidden = true
  discard result.withProtocol(DefaultListScrollerDrawing)
  discard result.withProtocol(DefaultListScrollerEvents)

proc initListViewFields*(
    listView: ListView, items: openArray[string] = [], frame: Rect = AutoRect
) =
  initControlFields(listView, frame)
  listView.xSelectedIndex = -1
  listView.xSelectedIndexes = @[]
  listView.xSelectionAnchor = -1
  listView.xSelectionLead = -1
  listView.xHighlightedIndex = -1
  listView.xPressedIndex = -1
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
