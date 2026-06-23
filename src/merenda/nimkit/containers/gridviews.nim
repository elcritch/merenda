import sigils/core

import ../foundation/selectors
import ../themes
import ../foundation/types
import ../view/viewgeometry
import ../view/views

export views

type
  GridAlignment* = enum
    gaFill
    gaLeading
    gaCenter
    gaTrailing

  GridItem* = object
    view*: View
    row*: Natural
    col*: Natural
    rowSpan*: Natural
    colSpan*: Natural

  GridSpacing* = object
    xGridView: GridView

  GridAlignmentValues* = object
    xGridView: GridView

  GridView* = ref object of View
    xItems: seq[GridItem]
    xSpacing: array[Direction, float32]
    xEdgeInsets: EdgeInsets
    xAlignment: array[Direction, GridAlignment]

  GridMetrics = object
    colWidths: seq[float32]
    rowHeights: seq[float32]

const LayoutEpsilon = 0.001'f32

func normalizedSpacing(value: float32): float32 =
  max(value, 0.0'f32)

func normalizedInsets(insets: EdgeInsets): EdgeInsets =
  initEdgeInsets(
    max(insets.top, 0.0'f32),
    max(insets.left, 0.0'f32),
    max(insets.bottom, 0.0'f32),
    max(insets.right, 0.0'f32),
  )

func totalSpacing(spacing: float32, count: int): float32 =
  if count <= 1:
    0.0'f32
  else:
    spacing * float32(count - 1)

func shouldAdjust(delta: float32): bool =
  delta < -LayoutEpsilon or delta > LayoutEpsilon

proc fittingSize(view: View): Size =
  if view.isNil:
    initSize(0.0, 0.0)
  else:
    view.sizeThatFits(UnconstrainedFittingSize)

proc invalidateGridLayout(gridView: GridView) =
  gridView.invalidateContainerMetrics()
  gridView.setNeedsDisplay(true)

proc visibleGridItems(gridView: GridView): seq[GridItem] =
  for item in gridView.xItems:
    if not item.view.isNil and item.view.superview == gridView and not item.view.isHidden:
      result.add item

proc gridItemIndex(gridView: GridView, child: View): int =
  if gridView.isNil or child.isNil:
    return -1
  for index, item in gridView.xItems:
    if item.view == child:
      return index
  -1

func startIndex(item: GridItem, direction: Direction): int =
  case direction
  of drow: item.row.int
  of dcol: item.col.int

func spanCount(item: GridItem, direction: Direction): int =
  let span =
    case direction
    of drow: item.rowSpan.int
    of dcol: item.colSpan.int
  max(span, 1)

func itemMetric(size: Size, direction: Direction): float32 =
  case direction
  of drow: size.height
  of dcol: size.width

proc trackCount(items: openArray[GridItem], direction: Direction): int =
  for item in items:
    result = max(result, item.startIndex(direction) + item.spanCount(direction))

proc growTracks(tracks: var seq[float32], start, span: int, needed, spacing: float32) =
  if span <= 0:
    return

  var current = spacing.totalSpacing(span)
  for index in start ..< min(start + span, tracks.len):
    current += tracks[index]

  let delta = needed - current
  if delta <= LayoutEpsilon:
    return

  let share = delta / float32(span)
  for index in start ..< min(start + span, tracks.len):
    tracks[index] += share

proc gridMetrics(gridView: GridView): GridMetrics =
  let items = gridView.visibleGridItems()
  result.colWidths.setLen(items.trackCount(dcol))
  result.rowHeights.setLen(items.trackCount(drow))

  for item in items:
    let size = item.view.fittingSize()
    if item.spanCount(dcol) == 1:
      result.colWidths.growTracks(
        item.startIndex(dcol), 1, size.itemMetric(dcol), gridView.xSpacing[dcol]
      )
    if item.spanCount(drow) == 1:
      result.rowHeights.growTracks(
        item.startIndex(drow), 1, size.itemMetric(drow), gridView.xSpacing[drow]
      )

  for item in items:
    let size = item.view.fittingSize()
    if item.spanCount(dcol) > 1:
      result.colWidths.growTracks(
        item.startIndex(dcol),
        item.spanCount(dcol),
        size.itemMetric(dcol),
        gridView.xSpacing[dcol],
      )
    if item.spanCount(drow) > 1:
      result.rowHeights.growTracks(
        item.startIndex(drow),
        item.spanCount(drow),
        size.itemMetric(drow),
        gridView.xSpacing[drow],
      )

func trackSum(tracks: openArray[float32]): float32 =
  for track in tracks:
    result += track

func naturalLength(tracks: openArray[float32], spacing: float32): float32 =
  tracks.trackSum() + spacing.totalSpacing(tracks.len)

proc naturalSize(gridView: GridView): Size =
  let metrics = gridView.gridMetrics()
  initSize(
    gridView.xEdgeInsets.horizontal +
      metrics.colWidths.naturalLength(gridView.xSpacing[dcol]),
    gridView.xEdgeInsets.vertical +
      metrics.rowHeights.naturalLength(gridView.xSpacing[drow]),
  )

proc contentRect(gridView: GridView): Rect =
  let
    bounds = gridView.bounds()
    insets = gridView.xEdgeInsets
  initRect(
    insets.left,
    insets.top,
    bounds.size.width - insets.horizontal,
    bounds.size.height - insets.vertical,
  )

func adjustedTracks(
    tracks: openArray[float32], availableLength, spacing: float32
): seq[float32] =
  for track in tracks:
    result.add track

  if result.len == 0:
    return

  let delta = availableLength - result.naturalLength(spacing)
  if not delta.shouldAdjust():
    return

  let share = delta / float32(result.len)
  for index in 0 ..< result.len:
    result[index] = max(result[index] + share, 0.0'f32)

func trackOrigins(tracks: openArray[float32], origin, spacing: float32): seq[float32] =
  var cursor = origin
  for track in tracks:
    result.add cursor
    cursor += track + spacing

func spannedLength(
    tracks: openArray[float32], start, span: int, spacing: float32
): float32 =
  if span <= 0:
    return 0.0'f32
  result = spacing.totalSpacing(span)
  for index in start ..< min(start + span, tracks.len):
    result += tracks[index]

proc setFrameFromGridLayout(view: View, frame: Rect) =
  view.applyLayoutFrame(frame, lfoContainer)

func alignedLength(
    cellOrigin, cellLength, naturalLength: float32, alignment: GridAlignment
): tuple[origin, length: float32] =
  case alignment
  of gaFill:
    (cellOrigin, cellLength)
  of gaLeading:
    (cellOrigin, min(naturalLength, cellLength))
  of gaCenter:
    let length = min(naturalLength, cellLength)
    (cellOrigin + (cellLength - length) / 2.0'f32, length)
  of gaTrailing:
    let length = min(naturalLength, cellLength)
    (cellOrigin + cellLength - length, length)

proc itemCell(
    gridView: GridView,
    item: GridItem,
    colWidths, rowHeights: openArray[float32],
    colOrigins, rowOrigins: openArray[float32],
): Rect =
  let
    col = item.startIndex(dcol)
    row = item.startIndex(drow)
  if col >= colOrigins.len or row >= rowOrigins.len:
    return initRect(0.0, 0.0, 0.0, 0.0)

  initRect(
    colOrigins[col],
    rowOrigins[row],
    colWidths.spannedLength(col, item.spanCount(dcol), gridView.xSpacing[dcol]),
    rowHeights.spannedLength(row, item.spanCount(drow), gridView.xSpacing[drow]),
  )

proc layoutGridSubviews(gridView: GridView) =
  let
    items = gridView.visibleGridItems()
    metrics = gridView.gridMetrics()
    content = gridView.contentRect()
    colWidths =
      metrics.colWidths.adjustedTracks(content.size.width, gridView.xSpacing[dcol])
    rowHeights =
      metrics.rowHeights.adjustedTracks(content.size.height, gridView.xSpacing[drow])
    colOrigins = colWidths.trackOrigins(content.origin.x, gridView.xSpacing[dcol])
    rowOrigins = rowHeights.trackOrigins(content.origin.y, gridView.xSpacing[drow])

  for item in items:
    let
      cell = gridView.itemCell(item, colWidths, rowHeights, colOrigins, rowOrigins)
      natural = item.view.fittingSize()
      colFrame = alignedLength(
        cell.origin.x, cell.size.width, natural.width, gridView.xAlignment[dcol]
      )
      rowFrame = alignedLength(
        cell.origin.y, cell.size.height, natural.height, gridView.xAlignment[drow]
      )
    item.view.setFrameFromGridLayout(
      initRect(colFrame.origin, rowFrame.origin, colFrame.length, rowFrame.length)
    )

proc spacing*(gridView: GridView): GridSpacing =
  GridSpacing(xGridView: gridView)

proc setSpacing*(gridView: GridView, direction: Direction, spacing: float32) =
  let normalized = spacing.normalizedSpacing()
  if gridView.isNil or gridView.xSpacing[direction] == normalized:
    return
  gridView.xSpacing[direction] = normalized
  gridView.invalidateGridLayout()

proc `[]`*(spacing: GridSpacing, direction: Direction): float32 =
  let gridView = spacing.xGridView
  if gridView.isNil:
    return 0.0'f32
  gridView.xSpacing[direction]

proc `[]=`*(spacing: GridSpacing, direction: Direction, value: float32) =
  spacing.xGridView.setSpacing(direction, value)

proc edgeInsets*(gridView: GridView): EdgeInsets =
  if gridView.isNil:
    initEdgeInsets(0.0)
  else:
    gridView.xEdgeInsets

proc `edgeInsets=`*(gridView: GridView, insets: EdgeInsets) =
  let normalized = insets.normalizedInsets()
  if gridView.isNil or gridView.xEdgeInsets == normalized:
    return
  gridView.xEdgeInsets = normalized
  gridView.invalidateGridLayout()

proc alignment*(gridView: GridView): GridAlignmentValues =
  GridAlignmentValues(xGridView: gridView)

proc setAlignment*(gridView: GridView, direction: Direction, alignment: GridAlignment) =
  if gridView.isNil or gridView.xAlignment[direction] == alignment:
    return
  gridView.xAlignment[direction] = alignment
  gridView.invalidateGridLayout()

proc `[]`*(alignment: GridAlignmentValues, direction: Direction): GridAlignment =
  let gridView = alignment.xGridView
  if gridView.isNil:
    return gaFill
  gridView.xAlignment[direction]

proc `[]=`*(
    alignment: GridAlignmentValues, direction: Direction, value: GridAlignment
) =
  alignment.xGridView.setAlignment(direction, value)

proc intrinsicContentSize*(gridView: GridView): IntrinsicSize =
  if gridView.isNil:
    NoIntrinsicContentSize
  else:
    initIntrinsicSize(gridView.naturalSize())

proc gridItems*(gridView: GridView): seq[GridItem] =
  if gridView.isNil:
    @[]
  else:
    gridView.xItems

proc setGridSubview*(
    gridView: GridView,
    child: View,
    row, col: Natural,
    rowSpan: Positive = 1,
    colSpan: Positive = 1,
) =
  if gridView.isNil or child.isNil:
    return

  if child.superview != gridView:
    gridView.addSubview(child)

  let
    item = GridItem(view: child, row: row, col: col, rowSpan: rowSpan, colSpan: colSpan)
    index = gridView.gridItemIndex(child)
  if index >= 0:
    gridView.xItems[index] = item
  else:
    gridView.xItems.add item
  gridView.invalidateGridLayout()

proc addGridSubview*(
    gridView: GridView,
    child: View,
    row, col: Natural,
    rowSpan: Positive = 1,
    colSpan: Positive = 1,
) =
  gridView.setGridSubview(child, row, col, rowSpan, colSpan)

proc addSubview*(
    gridView: GridView,
    child: View,
    row, col: Natural,
    rowSpan: Positive = 1,
    colSpan: Positive = 1,
) =
  gridView.setGridSubview(child, row, col, rowSpan, colSpan)

proc removeGridSubview*(gridView: GridView, child: View) =
  let index = gridView.gridItemIndex(child)
  if index < 0:
    return
  gridView.xItems.delete(index)
  gridView.invalidateGridLayout()

protocol GridViewLifecycleSlots of ViewLifecycleProtocol:
  proc willRemoveSubview(gridView: GridView, child: View) {.slot.} =
    gridView.removeGridSubview(child)

protocol DefaultGridViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(gridView: GridView): IntrinsicSize =
    initIntrinsicSize(gridView.naturalSize())

  method layoutSubviews(gridView: GridView) =
    gridView.layoutGridSubviews()

proc initGridViewFields*(gridView: GridView, frame: Rect = AutoRect) =
  initViewFields(gridView, frame)
  gridView.xSpacing[drow] = 8.0'f32
  gridView.xSpacing[dcol] = 8.0'f32
  gridView.xAlignment[drow] = gaFill
  gridView.xAlignment[dcol] = gaFill
  discard gridView.withProtocol(DefaultGridViewLayout)
  discard gridView.withProtocol(GridViewLifecycleSlots)
  gridView.observeProtocol(gridView, GridViewLifecycleSlots)
  gridView.applyInitialFrame(frame)

proc newGridView*(frame: Rect = AutoRect): GridView =
  result = GridView()
  initGridViewFields(result, frame)
