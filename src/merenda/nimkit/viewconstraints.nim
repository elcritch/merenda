import std/options

import ./types
import ./viewgeometry
import ./viewbase

export viewbase

type
  LayoutMetricKind = enum
    lmkMin
    lmkMax
    lmkCenter
    lmkSize

  LayoutMetric = object
    axis: LayoutAxis
    kind: LayoutMetricKind

  AxisLayoutInput = object
    lower: Option[float32]
    upper: Option[float32]
    center: Option[float32]
    size: Option[float32]
    minSize: Option[float32]
    maxSize: Option[float32]

  LayoutInput = object
    item: View
    axes: array[LayoutAxis, AxisLayoutInput]

const LayoutAxes = [laHorizontal, laVertical]

proc newLayoutConstraint*(
    firstItem: View,
    firstAttribute: LayoutAttribute,
    relation = lrEqual,
    secondItem: View = nil,
    secondAttribute = latNotAnAttribute,
    multiplier = 1.0'f32,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  result = LayoutConstraint(
    xFirstItem: firstItem,
    xFirstAttribute: firstAttribute,
    xRelation: relation,
    xSecondItem: secondItem,
    xSecondAttribute: if secondItem.isNil: latNotAnAttribute else: secondAttribute,
    xMultiplier: multiplier,
    xConstant: constant,
    xPriority: priority,
  )

proc firstItem*(constraint: LayoutConstraint): View =
  if constraint.isNil: nil else: constraint.xFirstItem

proc firstAttribute*(constraint: LayoutConstraint): LayoutAttribute =
  if constraint.isNil: latNotAnAttribute else: constraint.xFirstAttribute

proc relation*(constraint: LayoutConstraint): LayoutRelation =
  if constraint.isNil: lrEqual else: constraint.xRelation

proc secondItem*(constraint: LayoutConstraint): View =
  if constraint.isNil: nil else: constraint.xSecondItem

proc secondAttribute*(constraint: LayoutConstraint): LayoutAttribute =
  if constraint.isNil: latNotAnAttribute else: constraint.xSecondAttribute

proc multiplier*(constraint: LayoutConstraint): float32 =
  if constraint.isNil: 1.0'f32 else: constraint.xMultiplier

proc constant*(constraint: LayoutConstraint): float32 =
  if constraint.isNil: 0.0'f32 else: constraint.xConstant

proc priority*(constraint: LayoutConstraint): LayoutPriority =
  if constraint.isNil: LayoutPriorityRequired else: constraint.xPriority

proc isActive*(constraint: LayoutConstraint): bool =
  (not constraint.isNil) and constraint.xActive

proc owningView*(constraint: LayoutConstraint): View =
  if constraint.isNil: nil else: constraint.xOwningView

proc invalidateActiveConstraint(constraint: LayoutConstraint) =
  if constraint.isNil or not constraint.xActive:
    return
  constraint.xOwningView.markConstraintStorageChanged()

proc setConstant*(constraint: LayoutConstraint, constant: float32) =
  if constraint.isNil or constraint.xConstant == constant:
    return
  constraint.xConstant = constant
  constraint.invalidateActiveConstraint()

proc setPriority*(constraint: LayoutConstraint, priority: LayoutPriority) =
  if constraint.isNil or constraint.xPriority == priority:
    return
  constraint.xPriority = priority
  constraint.invalidateActiveConstraint()

proc indexOfConstraint(view: View, constraint: LayoutConstraint): int =
  if view.isNil or constraint.isNil:
    return -1
  for index, stored in view.xConstraints:
    if stored == constraint:
      return index
  -1

proc removeStoredConstraint(view: View, constraint: LayoutConstraint) =
  if view.isNil or constraint.isNil:
    return
  let index = view.indexOfConstraint(constraint)
  if index < 0:
    return
  view.xConstraints.delete(index)
  if constraint.xOwningView == view:
    constraint.xOwningView = nil
    constraint.xActive = false
  view.markConstraintStorageChanged()

proc constraints*(view: View): seq[LayoutConstraint] =
  if view.isNil:
    @[]
  else:
    view.xConstraints

proc addConstraint*(view: View, constraint: LayoutConstraint) =
  if view.isNil or constraint.isNil:
    return
  if constraint.xOwningView == view and view.indexOfConstraint(constraint) >= 0:
    if not constraint.xActive:
      constraint.xActive = true
      view.markConstraintStorageChanged()
    return

  let oldOwner = constraint.xOwningView
  if not oldOwner.isNil:
    oldOwner.removeStoredConstraint(constraint)

  view.xConstraints.add constraint
  constraint.xOwningView = view
  constraint.xActive = true
  view.markConstraintStorageChanged()

proc addConstraints*(view: View, constraints: openArray[LayoutConstraint]) =
  for constraint in constraints:
    view.addConstraint(constraint)

proc removeConstraint*(view: View, constraint: LayoutConstraint) =
  view.removeStoredConstraint(constraint)

proc removeConstraints*(view: View, constraints: openArray[LayoutConstraint]) =
  for constraint in constraints:
    view.removeConstraint(constraint)

proc nearestCommonSuperview(first, second: View): View =
  var candidate = first
  while not candidate.isNil:
    var other = second
    while not other.isNil:
      if candidate == other:
        return candidate
      other = other.xSuperview
    candidate = candidate.xSuperview

proc activationOwner(constraint: LayoutConstraint): View =
  if constraint.isNil or constraint.xFirstItem.isNil:
    return nil
  if constraint.xSecondItem.isNil:
    return constraint.xFirstItem
  let common = constraint.xFirstItem.nearestCommonSuperview(constraint.xSecondItem)
  if common.isNil: constraint.xFirstItem else: common

proc setActive*(constraint: LayoutConstraint, active: bool) =
  if constraint.isNil or constraint.xActive == active:
    return
  if active:
    let owner = constraint.activationOwner()
    if owner.isNil:
      return
    owner.addConstraint(constraint)
  elif not constraint.xOwningView.isNil:
    constraint.xOwningView.removeConstraint(constraint)
  else:
    constraint.xActive = false

proc activateConstraints*(constraints: openArray[LayoutConstraint]) =
  for constraint in constraints:
    constraint.setActive(true)

proc deactivateConstraints*(constraints: openArray[LayoutConstraint]) =
  for constraint in constraints:
    constraint.setActive(false)

proc setFrameFromLayout(view: View, frame: Rect) =
  if view.isNil or view.xFrame == frame:
    return
  view.xFrame = frame
  view.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
  view.xNeedsLayout = true
  view.xNeedsDisplay = true
  view.xInvalidRects.setLen(0)

proc layoutMetric(attribute: LayoutAttribute, metric: var LayoutMetric): bool =
  case attribute
  of latLeft, latLeading:
    metric = LayoutMetric(axis: laHorizontal, kind: lmkMin)
  of latRight, latTrailing:
    metric = LayoutMetric(axis: laHorizontal, kind: lmkMax)
  of latTop:
    metric = LayoutMetric(axis: laVertical, kind: lmkMin)
  of latBottom:
    metric = LayoutMetric(axis: laVertical, kind: lmkMax)
  of latWidth:
    metric = LayoutMetric(axis: laHorizontal, kind: lmkSize)
  of latHeight:
    metric = LayoutMetric(axis: laVertical, kind: lmkSize)
  of latCenterX:
    metric = LayoutMetric(axis: laHorizontal, kind: lmkCenter)
  of latCenterY:
    metric = LayoutMetric(axis: laVertical, kind: lmkCenter)
  of latNotAnAttribute, latFirstBaseline, latLastBaseline:
    return false
  true

func layoutMetricValue(rect: Rect, metric: LayoutMetric): float32 =
  case metric.kind
  of lmkMin:
    rect.axisOrigin(metric.axis)
  of lmkMax:
    rect.axisMax(metric.axis)
  of lmkCenter:
    rect.axisCenter(metric.axis)
  of lmkSize:
    rect.axisSize(metric.axis)

proc layoutReferenceValue(
    item, reference: View, attribute: LayoutAttribute, value: var float32
): bool =
  if reference.isNil or reference != item.xSuperview:
    return false

  var metric: LayoutMetric
  if not attribute.layoutMetric(metric):
    return false
  let rect = reference.alignmentRectForFrame(reference.xBounds)
  value = rect.layoutMetricValue(metric)
  true

proc resolvedLayoutTarget(constraint: LayoutConstraint, value: var float32): bool =
  if constraint.isNil or not constraint.xActive or constraint.xFirstItem.isNil:
    return false
  if constraint.xSecondItem.isNil:
    if constraint.xSecondAttribute != latNotAnAttribute:
      return false
    value = constraint.xConstant
    return true

  var referenceValue: float32
  if not constraint.xFirstItem.layoutReferenceValue(
    constraint.xSecondItem, constraint.xSecondAttribute, referenceValue
  ):
    return false
  value = referenceValue * constraint.xMultiplier + constraint.xConstant
  true

proc ensureLayoutInput(inputs: var seq[LayoutInput], item: View): int =
  for index, input in inputs:
    if input.item == item:
      return index
  inputs.add LayoutInput(item: item)
  inputs.high

proc keepLargest(slot: var Option[float32], value: float32) =
  if slot.isNone or value > slot.get():
    slot = some(value)

proc keepSmallest(slot: var Option[float32], value: float32) =
  if slot.isNone or value < slot.get():
    slot = some(value)

proc addSizeInput(
    input: var AxisLayoutInput, relation: LayoutRelation, value: float32
) =
  case relation
  of lrEqual:
    input.size = some(value)
  of lrGreaterThanOrEqual:
    input.minSize.keepLargest(value)
  of lrLessThanOrEqual:
    input.maxSize.keepSmallest(value)

proc addPositionInput(
    input: var AxisLayoutInput, kind: LayoutMetricKind, value: float32
) =
  case kind
  of lmkMin:
    input.lower = some(value)
  of lmkMax:
    input.upper = some(value)
  of lmkCenter:
    input.center = some(value)
  of lmkSize:
    discard

proc addConstraintInput(
    inputs: var seq[LayoutInput], constraint: LayoutConstraint, value: float32
) =
  var metric: LayoutMetric
  if constraint.xFirstItem.isNil or not constraint.xFirstAttribute.layoutMetric(metric):
    return

  let index = inputs.ensureLayoutInput(constraint.xFirstItem)
  if metric.kind == lmkSize:
    inputs[index].axes[metric.axis].addSizeInput(constraint.xRelation, value)
  elif constraint.xRelation == lrEqual:
    inputs[index].axes[metric.axis].addPositionInput(metric.kind, value)

proc constrainLayoutSize(value: float32, input: AxisLayoutInput): float32 =
  result = value
  if input.minSize.isSome:
    result = max(result, input.minSize.get())
  if input.maxSize.isSome:
    result = min(result, input.maxSize.get())
  result = max(result, 0.0'f32)

proc applyLayoutSize(input: LayoutInput) =
  let item = input.item
  if item.isNil:
    return

  var rect = item.alignmentRect()
  var sizes: array[LayoutAxis, float32]

  for axis in LayoutAxes:
    let axisInput = input.axes[axis]
    sizes[axis] = rect.axisSize(axis)

    if axisInput.size.isSome:
      sizes[axis] = axisInput.size.get()
    elif axisInput.lower.isSome and axisInput.upper.isSome:
      sizes[axis] = axisInput.upper.get() - axisInput.lower.get()
    sizes[axis] = sizes[axis].constrainLayoutSize(axisInput)

  let nextRect =
    initRect(rect.origin.x, rect.origin.y, sizes[laHorizontal], sizes[laVertical])
  if rect == nextRect:
    return
  item.setFrameFromLayout(item.frameForAlignmentRect(nextRect))

proc applyLayoutPosition(input: LayoutInput) =
  let item = input.item
  if item.isNil:
    return

  let rect = item.alignmentRect()
  var origins: array[LayoutAxis, float32]

  for axis in LayoutAxes:
    let axisInput = input.axes[axis]
    origins[axis] = rect.axisOrigin(axis)
    if axisInput.lower.isSome:
      origins[axis] = axisInput.lower.get()
    elif axisInput.upper.isSome:
      origins[axis] = axisInput.upper.get() - rect.axisSize(axis)
    elif axisInput.center.isSome:
      origins[axis] = axisInput.center.get() - rect.axisSize(axis) / 2.0'f32

  let nextRect = initRect(
    origins[laHorizontal], origins[laVertical], rect.size.width, rect.size.height
  )
  if rect == nextRect:
    return
  item.setFrameFromLayout(item.frameForAlignmentRect(nextRect))

proc collectOwnedLayoutInputs(owner: View): seq[LayoutInput] =
  if owner.isNil:
    return
  for constraint in owner.xConstraints:
    var value: float32
    if constraint.resolvedLayoutTarget(value):
      result.addConstraintInput(constraint, value)

proc intrinsicLayoutInput(view: View): LayoutInput =
  result.item = view
  if view.isNil or view.xTranslatesAutoresizingMaskIntoConstraints:
    return

  let intrinsicSize = view.resolvedIntrinsicContentSize()
  if intrinsicSize.hasWidth:
    result.axes[laHorizontal].minSize = some(intrinsicSize.width)
    result.axes[laHorizontal].maxSize = some(intrinsicSize.width)
  if intrinsicSize.hasHeight:
    result.axes[laVertical].minSize = some(intrinsicSize.height)
    result.axes[laVertical].maxSize = some(intrinsicSize.height)

proc applyIntrinsicSizePass(view: View) =
  if view.isNil:
    return
  view.intrinsicLayoutInput().applyLayoutSize()
  for child in view.xSubviews:
    child.applyIntrinsicSizePass()

proc applyOwnedConstraintSizePass(owner: View) =
  if owner.isNil:
    return
  for input in owner.collectOwnedLayoutInputs():
    input.applyLayoutSize()
  for child in owner.xSubviews:
    child.applyOwnedConstraintSizePass()

proc applyOwnedConstraintPositionPass(owner: View) =
  if owner.isNil:
    return
  for input in owner.collectOwnedLayoutInputs():
    input.applyLayoutPosition()
  for child in owner.xSubviews:
    child.applyOwnedConstraintPositionPass()

proc applyConstraintsForSubtree*(view: View) =
  if view.isNil:
    return
  view.applyIntrinsicSizePass()
  view.applyOwnedConstraintSizePass()
  view.applyOwnedConstraintPositionPass()
