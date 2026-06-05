import ./types
import ./viewgeometry

type ScrollerTrackingState* = object
  draggingKnob: bool
  dragGripOffset: float32

func isDraggingKnob*(tracking: ScrollerTrackingState): bool =
  tracking.draggingKnob

func dragGripOffset*(tracking: ScrollerTrackingState): float32 =
  tracking.dragGripOffset

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
