import ./types

type ListViewport* = object
  firstIndex*: int

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
