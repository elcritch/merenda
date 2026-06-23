from figdraw/fignodes import FigIdx
import std/options

import ../drawing
import ./scrollergeometry
import ../themes
import ../foundation/events
import ../foundation/types

type
  RowViewport* = object
    rows: ScrollViewport

  RowState* = object
    index*: int
    text*: string
    states*: set[WidgetState]

  RowStyle* = object
    fill*: Option[Fill]
    textColor*: Option[Color]

func normalizedRowHeight*(rowHeight: float32): float32 =
  max(rowHeight, 1.0'f32)

func visibleRowItemCount*(itemCount, maxVisibleItems: int): int =
  if itemCount <= 0:
    return 0
  min(itemCount, max(maxVisibleItems, 1))

func rowScrollViewport*(firstIndex, itemCount, visibleCount: int): ScrollViewport =
  result = initScrollViewport(
    firstIndex.float32, max(visibleCount, 0).float32, max(itemCount, 0).float32
  )
  result.offset = result.clampScrollOffset(result.offset)

func clampFirstIndex*(firstIndex, itemCount, visibleCount: int): int =
  rowScrollViewport(firstIndex, itemCount, visibleCount).offset.int

func maxFirstIndex*(itemCount, visibleCount: int): int =
  rowScrollViewport(0, itemCount, visibleCount).maxScrollOffset().int

func initRowViewport*(firstIndex = 0): RowViewport =
  RowViewport(rows: initScrollViewport(firstIndex.float32, 0.0, 0.0))

func firstIndex*(viewport: RowViewport): int =
  max(viewport.rows.offset.int, 0)

proc `firstIndex=`*(viewport: var RowViewport, firstIndex: int) =
  viewport.rows.offset = max(firstIndex, 0).float32

proc updateRows(viewport: var RowViewport, itemCount, visibleCount: int) =
  viewport.rows.visibleExtent = max(visibleCount, 0).float32
  viewport.rows.contentExtent = max(itemCount, 0).float32
  viewport.rows.offset = viewport.rows.clampScrollOffset(viewport.rows.offset)

func canScrollBy*(viewport: RowViewport, delta, itemCount, visibleCount: int): bool =
  if delta == 0:
    return false
  rowScrollViewport(viewport.firstIndex, itemCount, visibleCount).canScrollBy(
    delta.float32
  )

proc rowScrollRows*(event: ScrollEvent): int =
  if event.deltaY < 0.0'f32:
    1
  elif event.deltaY > 0.0'f32:
    -1
  else:
    0

func rowScrollerKnobRect*(
    container: Rect,
    firstIndex, visibleCount, itemCount: int,
    thickness = 3.0'f32,
    inset = 3.0'f32,
): Rect =
  if container.isEmpty or visibleCount <= 0 or not itemCount > visibleCount.max(0):
    return initRect(container.origin.x, container.origin.y, 0.0, 0.0)

  let track = scrollerTrackRect(container, laVertical, thickness, inset)
  if track.isEmpty:
    return initRect(container.origin.x, container.origin.y, 0.0, 0.0)

  scrollerKnobRect(
    track, laVertical, rowScrollViewport(firstIndex, itemCount, visibleCount)
  )

proc normalize*(viewport: var RowViewport, itemCount, visibleCount: int) =
  viewport.updateRows(itemCount, visibleCount)

proc reset*(viewport: var RowViewport, firstIndex = 0) =
  viewport.firstIndex = firstIndex

proc scrollToVisible*(
    viewport: var RowViewport, itemIndex, itemCount, visibleCount: int
) =
  viewport.normalize(itemCount, visibleCount)
  if itemIndex < 0 or visibleCount <= 0:
    return
  if itemIndex < viewport.firstIndex:
    viewport.firstIndex = itemIndex
  elif itemIndex >= viewport.firstIndex + visibleCount:
    viewport.firstIndex = itemIndex - visibleCount + 1
  viewport.normalize(itemCount, visibleCount)

proc scrollBy*(viewport: var RowViewport, delta, itemCount, visibleCount: int) =
  if delta == 0:
    return
  viewport.updateRows(itemCount, visibleCount)
  viewport.rows.offset = viewport.rows.scrolledBy(delta.float32)

func rowPopupRect*(
    bounds: Rect, itemCount, maxVisibleItems: int, rowHeight: float32
): Rect =
  let visible = visibleRowItemCount(itemCount, maxVisibleItems)
  if visible <= 0:
    return initRect(bounds.origin.x, bounds.maxY, 0.0, 0.0)
  initRect(
    bounds.origin.x,
    bounds.maxY,
    bounds.size.width,
    rowHeight.normalizedRowHeight() * visible.float32 + 2.0'f32,
  )

func rowItemRect*(
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

func rowItemIndexAtPoint*(
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

func initRowState*(index: int, text: string, states: set[WidgetState] = {}): RowState =
  RowState(index: index, text: text, states: states)

func initRowStyle*(fill = none(Fill), textColor = none(Color)): RowStyle =
  RowStyle(fill: fill, textColor: textColor)

proc drawRowItem*(
    context: DrawContext,
    rect: Rect,
    row: RowState,
    style: RowStyle,
    itemRole: StyleRole,
    id = "",
    classes: seq[string] = @[],
    layer = DefaultDrawLevel,
    parent = (-1).FigIdx,
) =
  if rect.isEmpty:
    return
  let currentParent = int16(parent) < 0
  var itemStyle = context.appearance.resolveRowItemStyle(
    initControlStyleContext(itemRole, row.states, id = id, classes = classes)
  )
  if style.fill.isSome:
    itemStyle.box.fill = style.fill.get()
  if style.textColor.isSome:
    itemStyle.text.color = style.textColor.get()

  if currentParent:
    discard context.addRenderRectangle(
      context.renderRectFor(rect),
      itemStyle.box.fill,
      itemStyle.box.borderColor,
      itemStyle.box.borderWidth,
      itemStyle.box.cornerRadius,
      itemStyle.box.shadows,
    )
    context.addText(itemStyle.rowItemTextRect(rect), row.text, itemStyle.text.color)
  else:
    discard context.addRenderRectangle(
      layer,
      parent,
      context.renderRectFor(rect),
      itemStyle.box.fill,
      itemStyle.box.borderColor,
      itemStyle.box.borderWidth,
      itemStyle.box.cornerRadius,
      itemStyle.box.shadows,
    )
    context.addText(
      layer, parent, itemStyle.rowItemTextRect(rect), row.text, itemStyle.text.color
    )

proc drawRowItem*(
    context: DrawContext,
    rect: Rect,
    row: RowState,
    itemRole: StyleRole,
    id = "",
    classes: seq[string] = @[],
    layer = DefaultDrawLevel,
    parent = (-1).FigIdx,
) =
  context.drawRowItem(rect, row, initRowStyle(), itemRole, id, classes, layer, parent)
