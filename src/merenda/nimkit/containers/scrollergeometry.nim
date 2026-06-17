import ../foundation/types
import ../view/viewgeometry

type ScrollViewport* = object
  offset*: float32
  visibleExtent*: float32
  contentExtent*: float32

type ScrollerTrackingState* = object
  draggingKnob: bool
  dragGripOffset: float32

func initScrollViewport*(
    offset, visibleExtent, contentExtent: float32
): ScrollViewport =
  ScrollViewport(
    offset: max(offset, 0.0'f32),
    visibleExtent: max(visibleExtent, 0.0'f32),
    contentExtent: max(contentExtent, 0.0'f32),
  )

func maxScrollOffset*(viewport: ScrollViewport): float32 =
  max(viewport.contentExtent - viewport.visibleExtent, 0.0'f32)

func clampScrollOffset*(viewport: ScrollViewport, offset: float32): float32 =
  min(max(offset, 0.0'f32), viewport.maxScrollOffset())

func canScrollBy*(viewport: ScrollViewport, delta: float32): bool =
  viewport.clampScrollOffset(viewport.offset + delta) !=
    viewport.clampScrollOffset(viewport.offset)

func scrolledBy*(viewport: ScrollViewport, delta: float32): float32 =
  viewport.clampScrollOffset(viewport.offset + delta)

func isDraggingKnob*(tracking: ScrollerTrackingState): bool =
  tracking.draggingKnob

proc beginScrollerTracking*(
    tracking: var ScrollerTrackingState,
    track, knob: Rect,
    axis: LayoutAxis,
    point: Point,
): bool =
  tracking.draggingKnob = false
  tracking.dragGripOffset = 0.0'f32
  if track.isEmpty or knob.isEmpty or not knob.contains(point):
    return false
  tracking.draggingKnob = true
  tracking.dragGripOffset = point.axisOffset(axis) - knob.axisOrigin(axis)
  true

func knobOriginForPoint*(
    tracking: ScrollerTrackingState, axis: LayoutAxis, point: Point
): float32 =
  point.axisOffset(axis) - tracking.dragGripOffset

proc endScrollerTracking*(tracking: var ScrollerTrackingState) =
  tracking.draggingKnob = false
  tracking.dragGripOffset = 0.0'f32

func scrollerTrackRect*(
    container: Rect, axis: LayoutAxis, thickness, inset: float32
): Rect =
  let
    safeInset = max(inset, 0.0'f32)
    safeThickness = max(thickness, 0.0'f32)
  if container.isEmpty or safeThickness <= 0.0'f32:
    return initRect(container.origin.x, container.origin.y, 0.0, 0.0)

  case axis
  of laHorizontal:
    let
      width = max(container.size.width - safeInset * 2.0'f32, 0.0'f32)
      height =
        min(safeThickness, max(container.size.height - safeInset * 2.0'f32, 0.0'f32))
    if width <= 0.0'f32 or height <= 0.0'f32:
      return initRect(container.origin.x, container.origin.y, 0.0, 0.0)
    initRect(
      container.origin.x + safeInset, container.maxY - safeInset - height, width, height
    )
  of laVertical:
    let
      width =
        min(safeThickness, max(container.size.width - safeInset * 2.0'f32, 0.0'f32))
      height = max(container.size.height - safeInset * 2.0'f32, 0.0'f32)
    if width <= 0.0'f32 or height <= 0.0'f32:
      return initRect(container.origin.x, container.origin.y, 0.0, 0.0)
    initRect(
      container.maxX - safeInset - width, container.origin.y + safeInset, width, height
    )

func scrollerKnobRect*(track: Rect, axis: LayoutAxis, viewport: ScrollViewport): Rect =
  if track.isEmpty:
    return track
  let
    trackExtent = track.axisSize(axis)
    length =
      if viewport.visibleExtent <= 0.0'f32 or
          viewport.contentExtent <= viewport.visibleExtent:
        0.0'f32
      else:
        max(trackExtent * viewport.visibleExtent / viewport.contentExtent, 12.0'f32)
    offset =
      if length <= 0.0'f32 or viewport.contentExtent <= viewport.visibleExtent:
        0.0'f32
      else:
        viewport.offset / (viewport.contentExtent - viewport.visibleExtent) *
          max(trackExtent - length, 0.0'f32)
  case axis
  of laHorizontal:
    initRect(track.origin.x + offset, track.origin.y, length, track.size.height)
  of laVertical:
    initRect(track.origin.x, track.origin.y + offset, track.size.width, length)

func contentOffsetForScrollerKnobOrigin*(
    track: Rect, knob: Rect, axis: LayoutAxis, maxOffset, knobOrigin: float32
): float32 =
  let travel = max(track.axisSize(axis) - knob.axisSize(axis), 0.0)
  if travel <= 0.0'f32 or maxOffset <= 0.0'f32:
    return 0.0'f32
  maxOffset * min(max(knobOrigin, 0.0'f32), travel) / travel
