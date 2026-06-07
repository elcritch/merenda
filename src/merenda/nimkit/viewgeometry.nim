import std/options

import sigils/core

import ./selectors
import ./theme
import ./types
import ./viewbase

type
  ViewLayoutPriorityKind = enum
    vlpkHugging
    vlpkCompression

  ViewLayoutPriority* = object
    xView: View
    xKind: ViewLayoutPriorityKind

proc pointFromView*(view: View, point: Point, fromView: View): Point
proc pointToView*(view: View, point: Point, toView: View): Point
proc rectFromView*(view: View, rect: Rect, fromView: View): Rect
proc rectToView*(view: View, rect: Rect, toView: View): Rect
proc pointFromWindow*(view: View, point: Point): Point
proc pointToWindow*(view: View, point: Point): Point
proc rectFromWindow*(view: View, rect: Rect): Rect
proc rectToWindow*(view: View, rect: Rect): Rect
proc alignmentRect*(view: View): Rect
proc resetAutoresizingState*(view: View)
proc refreshAutoresizingReference*(view: View)
proc observeSuperviewGeometry*(view: View)
proc unobserveSuperviewGeometry*(view: View)
proc applyLayoutFrame*(view: View, frame: Rect, origin = lfoContainer)

protocol ViewLayoutInputEvents:
  proc layoutInputChanged*(view: View, reason: LayoutInvalidationReason) {.signal.}

protocol ViewGeometryEvents:
  proc geometryDidChange*(view: View) {.signal.}

proc sourceFor(reason: LayoutInvalidationReason): LayoutInputSource =
  case reason
  of lirConstraints:
    lisUser
  of lirIntrinsic, lirDescendantIntrinsic, lirAppearanceMetrics, lirContainerMetrics:
    lisIntrinsic
  of lirHidden, lirHierarchy:
    lisContainer
  of lirFrame, lirBounds, lirSuperview, lirSuperviewGeometry, lirSubviews,
      lirDescendantGeometry, lirAutoresizingMask:
    lisAutoresizingMask

func isStructureDirtyReason(reason: LayoutInvalidationReason): bool =
  reason in {lirSuperview, lirSubviews, lirHierarchy, lirHidden}

proc markConstraintStorageChangedRaw(view: View) =
  view.xNeedsUpdateConstraints = true
  view.xNeedsLayout = true

proc markAggregateLayoutInputDirty(
    view: View, source: LayoutInputSource, structureDirty: bool
) =
  var current = view
  while not current.isNil:
    current.xLayoutInputCache.aggregateDirtySources.incl source
    if structureDirty:
      current.xLayoutInputCache.aggregateStructureDirty = true
    current.markConstraintStorageChangedRaw()
    current = current.xSuperview

protocol ViewLayoutInputSlots of ViewLayoutInputEvents:
  proc markLayoutInputDirty(
      view: View, reason: LayoutInvalidationReason
  ) {.slotFor: layoutInputChanged.} =
    let
      source = reason.sourceFor()
      structureDirty = reason.isStructureDirtyReason()
    view.xLayoutInputCache.dirtySources.incl source
    if structureDirty:
      view.xLayoutInputCache.structureDirty = true
    case reason
    of lirFrame, lirSuperview, lirAutoresizingMask:
      view.xAutoresizingState.referenceDirty = true
      view.xAutoresizingState.inputsDirty = true
    of lirBounds, lirSuperviewGeometry, lirSubviews:
      view.xAutoresizingState.inputsDirty = true
    else:
      discard
    view.markAggregateLayoutInputDirty(source, structureDirty)

protocol ViewSuperviewGeometrySlots of ViewGeometryEvents:
  proc markSuperviewGeometryDirty(view: View) {.slotFor: geometryDidChange.} =
    if not view.isNil and view.xAutoresizingMaskConstraints:
      emit view.layoutInputChanged(lirSuperviewGeometry)

proc initLayoutSignalBus*(view: View) =
  view.observeProtocol(view, ViewLayoutInputSlots)

proc markConstraintStorageChanged*(view: View) =
  emit view.layoutInputChanged(lirConstraints)

proc observeSuperviewGeometry*(view: View) =
  let parent = view.xSuperview
  if not parent.isNil:
    view.observeProtocol(parent, ViewSuperviewGeometrySlots)

proc unobserveSuperviewGeometry*(view: View) =
  let parent = view.xSuperview
  if not parent.isNil:
    view.unobserveProtocol(parent, ViewSuperviewGeometrySlots)

proc invalidateLayoutItemGeometry*(
    view: View, reason = lirFrame, ancestorReason = lirDescendantGeometry
) =
  var current = view
  var isOrigin = true
  while not current.isNil:
    emit current.layoutInputChanged(if isOrigin: reason else: ancestorReason)
    isOrigin = false
    current = current.xSuperview

proc autoresizingMask*(view: View): AutoresizingMask =
  view.xAutoresizingMask

proc `autoresizingMask=`*(view: View, mask: AutoresizingMask) =
  if view.isNil or view.xAutoresizingMask == mask:
    return
  view.xAutoresizingMask = mask
  view.invalidateLayoutItemGeometry(lirAutoresizingMask)
  if view.xAutoresizingMaskConstraints:
    view.refreshAutoresizingReference()
  else:
    view.resetAutoresizingState()

proc autoresizingMaskConstraints*(view: View): bool =
  (not view.isNil) and view.xAutoresizingMaskConstraints

proc `autoresizingMaskConstraints=`*(view: View, value: bool) =
  if view.isNil or view.xAutoresizingMaskConstraints == value:
    return
  view.xAutoresizingMaskConstraints = value
  if value:
    view.invalidateLayoutItemGeometry(lirAutoresizingMask)
    view.refreshAutoresizingReference()
  else:
    view.invalidateLayoutItemGeometry(lirAutoresizingMask)
    view.resetAutoresizingState()

proc translatesAutoresizingMaskIntoConstraints*(view: View): bool =
  view.autoresizingMaskConstraints()

proc `translatesAutoresizingMaskIntoConstraints=`*(view: View, value: bool) =
  view.autoresizingMaskConstraints = value

proc alignmentInsets*(view: View): EdgeInsets =
  view.xAlignmentInsets

proc `alignmentInsets=`*(view: View, insets: EdgeInsets) =
  if view.isNil or view.xAlignmentInsets == insets:
    return
  view.xAlignmentInsets = insets
  view.invalidateLayoutItemGeometry(lirFrame)

proc alignmentRectForFrame*(view: View, frame: Rect): Rect =
  frame.inset(view.alignmentInsets())

proc frameForAlignmentRect*(view: View, alignmentRect: Rect): Rect =
  let insets = view.alignmentInsets()
  initRect(
    alignmentRect.origin.x - insets.left,
    alignmentRect.origin.y - insets.top,
    alignmentRect.size.width + insets.horizontal,
    alignmentRect.size.height + insets.vertical,
  )

proc alignmentRect*(view: View): Rect =
  view.alignmentRectForFrame(view.xFrame)

proc resetAutoresizingState*(view: View) =
  view.xAutoresizingState = AutoresizingState()

proc refreshAutoresizingReference*(view: View) =
  if view.isNil or view.xSuperview.isNil or not view.xAutoresizingMaskConstraints:
    view.resetAutoresizingState()
    return
  view.xAutoresizingState = AutoresizingState(
    referenceRect: view.alignmentRect(),
    referenceSuperviewRect: view.xSuperview.alignmentRect(),
    hasReference: true,
    referenceDirty: false,
    inputsDirty: false,
  )

proc refreshAutoresizingReferenceIfNeeded*(view: View) =
  if not view.xAutoresizingState.hasReference or view.xAutoresizingState.referenceDirty:
    view.refreshAutoresizingReference()

proc applyLayoutFrame*(view: View, frame: Rect, origin = lfoContainer) =
  if view.isNil or view.xFrame == frame:
    return
  view.xFrame = frame
  view.xBounds = initRect(view.xBounds.origin, frame.size)
  view.xNeedsLayout = true
  view.xNeedsDisplay = true
  view.xInvalidRects.setLen(0)
  case origin
  of lfoAuthored:
    view.invalidateLayoutItemGeometry(lirFrame)
    view.refreshAutoresizingReference()
    emit view.geometryDidChange()
  of lfoContainer:
    view.refreshAutoresizingReference()
    emit view.geometryDidChange()
  of lfoSolver:
    discard

proc setFrameFromLayout*(view: View, frame: Rect) =
  view.applyLayoutFrame(frame, lfoContainer)

proc setFrameFromAlignmentRect*(view: View, alignmentRect: Rect) =
  view.applyLayoutFrame(view.frameForAlignmentRect(alignmentRect), lfoAuthored)

proc `alignmentRect=`*(view: View, alignmentRect: Rect) =
  view.setFrameFromAlignmentRect(alignmentRect)

proc lastBaselineOffset*(view: View): float32 =
  if view.isNil: 0.0'f32 else: view.xLastBaselineOffset

proc `lastBaselineOffset=`*(view: View, offset: float32) =
  let normalized = max(offset, 0.0'f32)
  if view.isNil or view.xLastBaselineOffset == normalized:
    return
  view.xLastBaselineOffset = normalized
  view.invalidateLayoutItemGeometry(
    lirIntrinsic, ancestorReason = lirDescendantIntrinsic
  )

proc firstBaselineOffset*(view: View): float32 =
  if view.isNil: 0.0'f32 else: view.xFirstBaselineOffset

proc `firstBaselineOffset=`*(view: View, offset: float32) =
  let normalized = max(offset, 0.0'f32)
  if view.isNil or view.xFirstBaselineOffset == normalized:
    return
  view.xFirstBaselineOffset = normalized
  view.invalidateLayoutItemGeometry(
    lirIntrinsic, ancestorReason = lirDescendantIntrinsic
  )

proc layoutValue*(view: View, attribute: LayoutAttribute): float32 =
  let rect = view.alignmentRect()
  case attribute
  of latLeft, latLeading:
    rect.minX
  of latRight, latTrailing:
    rect.maxX
  of latTop:
    rect.minY
  of latBottom:
    rect.maxY
  of latWidth:
    rect.size.width
  of latHeight:
    rect.size.height
  of latCenterX:
    rect.minX + rect.size.width / 2.0'f32
  of latCenterY:
    rect.minY + rect.size.height / 2.0'f32
  of latLastBaseline:
    rect.maxY - view.lastBaselineOffset()
  of latFirstBaseline:
    rect.minY + view.firstBaselineOffset()
  of latNotAnAttribute:
    0.0'f32

proc intrinsicContentSize*(view: View): IntrinsicSize =
  NoIntrinsicContentSize

proc resolvedIntrinsicContentSize*(view: View): IntrinsicSize =
  let measured = view.performOptional(layoutIntrinsicContentSize(), ())
  if measured.isSome:
    return measured.get()
  view.intrinsicContentSize()

proc sizeThatFits*(view: View, proposedSize: FittingSize): Size =
  let
    intrinsicSize = view.resolvedIntrinsicContentSize()
    fallbackSize = initSize(
      if proposedSize.hasWidth: proposedSize.width else: view.xBounds.size.width,
      if proposedSize.hasHeight: proposedSize.height else: view.xBounds.size.height,
    )
  intrinsicSize.resolveIntrinsicSize(fallbackSize).constrainSize(proposedSize)

proc sizeThatFits*(view: View): Size =
  view.sizeThatFits(UnconstrainedFittingSize)

proc sizeThatFits*(view: View, proposedSize: Size): Size =
  view.sizeThatFits(initFittingSize(proposedSize))

proc resolvedFrame*(view: View, frame: Rect): Rect =

  let
    fallbackSize =
      if frame.size.hasAutoMetric:
        view.sizeThatFits(UnconstrainedFittingSize)
      else:
        view.xFrame.size
    fallback = initRect(view.xFrame.origin, fallbackSize)
  frame.resolveAutoRect(fallback)

proc applyInitialFrame*(view: View, frame: Rect) =
  if view.isNil or not frame.hasAutoMetric:
    return

  let nextFrame = view.resolvedFrame(frame)
  view.applyLayoutFrame(nextFrame, lfoAuthored)

proc sizeToFit*(view: View) =
  let
    frame = view.xFrame
    fittingSize = view.sizeThatFits(UnconstrainedFittingSize)
    nextFrame = initRect(frame.origin, fittingSize)
  view.applyLayoutFrame(nextFrame, lfoAuthored)

proc invalidateIntrinsicContentSize*(view: View) =
  view.invalidateLayoutItemGeometry(
    lirIntrinsic, ancestorReason = lirDescendantIntrinsic
  )

proc invalidateContainerMetrics*(view: View) =
  view.invalidateLayoutItemGeometry(
    lirContainerMetrics, ancestorReason = lirDescendantIntrinsic
  )

proc invalidateIntrinsicContentSizeSubtree*(view: View) =
  view.invalidateIntrinsicContentSize()
  for child in view.xSubviews:
    child.invalidateIntrinsicContentSizeSubtree()

proc layoutPriority(
    view: View, kind: ViewLayoutPriorityKind, axis: LayoutAxis
): LayoutPriority =
  if view.isNil:
    case kind
    of vlpkHugging:
      return LayoutPriorityLow
    of vlpkCompression:
      return LayoutPriorityHigh
  case kind
  of vlpkHugging:
    view.xHuggingPriority[axis]
  of vlpkCompression:
    view.xCompressionPriority[axis]

proc setLayoutPriority(
    view: View, kind: ViewLayoutPriorityKind, priority: LayoutPriority, axis: LayoutAxis
) =
  case kind
  of vlpkHugging:
    if view.xHuggingPriority[axis] == priority:
      return
    view.xHuggingPriority[axis] = priority
  of vlpkCompression:
    if view.xCompressionPriority[axis] == priority:
      return
    view.xCompressionPriority[axis] = priority
  view.invalidateIntrinsicContentSize()

proc huggingPriority*(view: View, axis: LayoutAxis): LayoutPriority =
  view.layoutPriority(vlpkHugging, axis)

proc huggingPriority*(view: View): ViewLayoutPriority =
  ViewLayoutPriority(xView: view, xKind: vlpkHugging)

proc setHuggingPriority*(view: View, priority: LayoutPriority, axis: LayoutAxis) =
  view.setLayoutPriority(vlpkHugging, priority, axis)

proc compressionPriority*(view: View, axis: LayoutAxis): LayoutPriority =
  view.layoutPriority(vlpkCompression, axis)

proc compressionPriority*(view: View): ViewLayoutPriority =
  ViewLayoutPriority(xView: view, xKind: vlpkCompression)

proc setCompressionPriority*(view: View, priority: LayoutPriority, axis: LayoutAxis) =
  view.setLayoutPriority(vlpkCompression, priority, axis)

proc `[]`*(priority: ViewLayoutPriority, direction: Direction): LayoutPriority =
  priority.xView.layoutPriority(priority.xKind, direction.layoutAxis)

proc `[]=`*(priority: ViewLayoutPriority, direction: Direction, value: LayoutPriority) =
  priority.xView.setLayoutPriority(priority.xKind, value, direction.layoutAxis)

func axisOrigin*(rect: Rect, axis: LayoutAxis): float32 =
  case axis
  of laHorizontal: rect.origin.x
  of laVertical: rect.origin.y

func axisOrigin*(point: Point, axis: LayoutAxis): float32 =
  case axis
  of laHorizontal: point.x
  of laVertical: point.y

func axisOffset*(point: Point, axis: LayoutAxis): float32 =
  point.axisOrigin(axis)

func axisSize*(size: Size, axis: LayoutAxis): float32 =
  case axis
  of laHorizontal: size.width
  of laVertical: size.height

func axisSize*(rect: Rect, axis: LayoutAxis): float32 =
  case axis
  of laHorizontal: rect.size.width
  of laVertical: rect.size.height

func axisMax*(rect: Rect, axis: LayoutAxis): float32 =
  rect.axisOrigin(axis) + rect.axisSize(axis)

func axisCenter*(rect: Rect, axis: LayoutAxis): float32 =
  rect.axisOrigin(axis) + rect.axisSize(axis) / 2.0'f32

proc pointToSuperview(view: View, point: Point): Point =
  let
    frame = view.xFrame
    bounds = view.xBounds
  initPoint(
    frame.origin.x + point.x - bounds.origin.x,
    frame.origin.y + point.y - bounds.origin.y,
  )

proc pointFromSuperview(view: View, point: Point): Point =
  let
    frame = view.xFrame
    bounds = view.xBounds
  initPoint(
    bounds.origin.x + point.x - frame.origin.x,
    bounds.origin.y + point.y - frame.origin.y,
  )

proc pointToWindow*(view: View, point: Point): Point =
  var resultPoint = point
  var current = view
  while not current.isNil:
    resultPoint = current.pointToSuperview(resultPoint)
    current = current.xSuperview
  resultPoint

proc pointFromWindow*(view: View, point: Point): Point =
  var chain: seq[View] = @[]
  var current = view
  while not current.isNil:
    chain.add(current)
    current = current.xSuperview
  var resultPoint = point
  for idx in countdown(chain.high, 0):
    resultPoint = chain[idx].pointFromSuperview(resultPoint)
  resultPoint

proc pointToView*(view: View, point: Point, toView: View): Point =
  if view.isNil:
    if toView.isNil:
      return point
    return toView.pointFromWindow(point)
  if view == toView:
    return point
  let windowPoint = view.pointToWindow(point)
  if toView.isNil:
    windowPoint
  else:
    toView.pointFromWindow(windowPoint)

proc pointFromView*(view: View, point: Point, fromView: View): Point =
  if view.isNil:
    if fromView.isNil:
      return point
    return fromView.pointToWindow(point)
  if view == fromView:
    return point
  if fromView.isNil:
    return view.pointFromWindow(point)
  view.pointFromWindow(fromView.pointToWindow(point))

proc rectFromCorners(p0, p1: Point): Rect =
  initRect(min(p0.x, p1.x), min(p0.y, p1.y), abs(p1.x - p0.x), abs(p1.y - p0.y))

proc rectToWindow*(view: View, rect: Rect): Rect =
  let
    p0 = view.pointToWindow(rect.origin)
    p1 = view.pointToWindow(initPoint(rect.maxX, rect.maxY))
  rectFromCorners(p0, p1)

proc rectFromWindow*(view: View, rect: Rect): Rect =
  let
    p0 = view.pointFromWindow(rect.origin)
    p1 = view.pointFromWindow(initPoint(rect.maxX, rect.maxY))
  rectFromCorners(p0, p1)

proc rectToView*(view: View, rect: Rect, toView: View): Rect =
  let
    p0 = view.pointToView(rect.origin, toView)
    p1 = view.pointToView(initPoint(rect.maxX, rect.maxY), toView)
  rectFromCorners(p0, p1)

proc rectFromView*(view: View, rect: Rect, fromView: View): Rect =
  let
    p0 = view.pointFromView(rect.origin, fromView)
    p1 = view.pointFromView(initPoint(rect.maxX, rect.maxY), fromView)
  rectFromCorners(p0, p1)
