import pkg/kiwiberry

import ./theme
import ./types
import ./viewgeometry
import ./viewbase

export viewbase

type
  LayoutEdge* = enum
    leLeft
    leTop
    leRight
    leBottom

  LayoutEdges* = set[LayoutEdge]

  LayoutXAxisAnchor* = object
    xItem: View
    xAttribute: LayoutAttribute
    xOffset: float32

  LayoutYAxisAnchor* = object
    xItem: View
    xAttribute: LayoutAttribute
    xOffset: float32

  LayoutDimensionAnchor* = object
    xItem: View
    xAttribute: LayoutAttribute
    xOffset: float32

  LayoutGuide* = object
    xOwningView: View
    xInsets: EdgeInsets

  SolverView = object
    item: View
    left: Variable
    top: Variable
    width: Variable
    height: Variable

  LayoutSolveState = object
    solver: Solver
    items: seq[SolverView]
    constraintItems: seq[View]

const AllLayoutEdges* = {leLeft, leTop, leRight, leBottom}

proc item*(anchor: LayoutXAxisAnchor): View =
  anchor.xItem

proc item*(anchor: LayoutYAxisAnchor): View =
  anchor.xItem

proc item*(anchor: LayoutDimensionAnchor): View =
  anchor.xItem

proc attribute*(anchor: LayoutXAxisAnchor): LayoutAttribute =
  anchor.xAttribute

proc attribute*(anchor: LayoutYAxisAnchor): LayoutAttribute =
  anchor.xAttribute

proc attribute*(anchor: LayoutDimensionAnchor): LayoutAttribute =
  anchor.xAttribute

proc offset*(anchor: LayoutXAxisAnchor): float32 =
  anchor.xOffset

proc offset*(anchor: LayoutYAxisAnchor): float32 =
  anchor.xOffset

proc offset*(anchor: LayoutDimensionAnchor): float32 =
  anchor.xOffset

proc owningView*(guide: LayoutGuide): View =
  guide.xOwningView

proc insets*(guide: LayoutGuide): EdgeInsets =
  guide.xInsets

proc initLayoutGuide*(owningView: View, insets = initEdgeInsets(0.0)): LayoutGuide =
  LayoutGuide(xOwningView: owningView, xInsets: insets)

proc contentLayoutGuide*(view: View, insets = initEdgeInsets(0.0)): LayoutGuide =
  initLayoutGuide(view, insets)

proc initXAxisAnchor(
    item: View, attribute: LayoutAttribute, offset = 0.0'f32
): LayoutXAxisAnchor =
  LayoutXAxisAnchor(xItem: item, xAttribute: attribute, xOffset: offset)

proc initYAxisAnchor(
    item: View, attribute: LayoutAttribute, offset = 0.0'f32
): LayoutYAxisAnchor =
  LayoutYAxisAnchor(xItem: item, xAttribute: attribute, xOffset: offset)

proc initDimensionAnchor(
    item: View, attribute: LayoutAttribute, offset = 0.0'f32
): LayoutDimensionAnchor =
  LayoutDimensionAnchor(xItem: item, xAttribute: attribute, xOffset: offset)

proc leftAnchor*(view: View): LayoutXAxisAnchor =
  initXAxisAnchor(view, latLeft)

proc rightAnchor*(view: View): LayoutXAxisAnchor =
  initXAxisAnchor(view, latRight)

proc leadingAnchor*(view: View): LayoutXAxisAnchor =
  initXAxisAnchor(view, latLeading)

proc trailingAnchor*(view: View): LayoutXAxisAnchor =
  initXAxisAnchor(view, latTrailing)

proc centerXAnchor*(view: View): LayoutXAxisAnchor =
  initXAxisAnchor(view, latCenterX)

proc topAnchor*(view: View): LayoutYAxisAnchor =
  initYAxisAnchor(view, latTop)

proc bottomAnchor*(view: View): LayoutYAxisAnchor =
  initYAxisAnchor(view, latBottom)

proc centerYAnchor*(view: View): LayoutYAxisAnchor =
  initYAxisAnchor(view, latCenterY)

proc widthAnchor*(view: View): LayoutDimensionAnchor =
  initDimensionAnchor(view, latWidth)

proc heightAnchor*(view: View): LayoutDimensionAnchor =
  initDimensionAnchor(view, latHeight)

proc leftAnchor*(guide: LayoutGuide): LayoutXAxisAnchor =
  initXAxisAnchor(guide.xOwningView, latLeft, guide.xInsets.left)

proc rightAnchor*(guide: LayoutGuide): LayoutXAxisAnchor =
  initXAxisAnchor(guide.xOwningView, latRight, -guide.xInsets.right)

proc leadingAnchor*(guide: LayoutGuide): LayoutXAxisAnchor =
  initXAxisAnchor(guide.xOwningView, latLeading, guide.xInsets.left)

proc trailingAnchor*(guide: LayoutGuide): LayoutXAxisAnchor =
  initXAxisAnchor(guide.xOwningView, latTrailing, -guide.xInsets.right)

proc centerXAnchor*(guide: LayoutGuide): LayoutXAxisAnchor =
  initXAxisAnchor(
    guide.xOwningView, latCenterX, (guide.xInsets.left - guide.xInsets.right) / 2.0
  )

proc topAnchor*(guide: LayoutGuide): LayoutYAxisAnchor =
  initYAxisAnchor(guide.xOwningView, latTop, guide.xInsets.top)

proc bottomAnchor*(guide: LayoutGuide): LayoutYAxisAnchor =
  initYAxisAnchor(guide.xOwningView, latBottom, -guide.xInsets.bottom)

proc centerYAnchor*(guide: LayoutGuide): LayoutYAxisAnchor =
  initYAxisAnchor(
    guide.xOwningView, latCenterY, (guide.xInsets.top - guide.xInsets.bottom) / 2.0
  )

proc widthAnchor*(guide: LayoutGuide): LayoutDimensionAnchor =
  initDimensionAnchor(guide.xOwningView, latWidth, -guide.xInsets.horizontal)

proc heightAnchor*(guide: LayoutGuide): LayoutDimensionAnchor =
  initDimensionAnchor(guide.xOwningView, latHeight, -guide.xInsets.vertical)

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

func resolvedAnchorConstant(firstOffset, secondOffset, constant: float32): float32 =
  secondOffset + constant - firstOffset

proc newAnchorConstraint(
    firstItem: View,
    firstAttribute: LayoutAttribute,
    relation: LayoutRelation,
    secondItem: View,
    secondAttribute: LayoutAttribute,
    multiplier: float32,
    constant: float32,
    priority: LayoutPriority,
): LayoutConstraint =
  newLayoutConstraint(
    firstItem,
    firstAttribute,
    relation,
    secondItem,
    secondAttribute,
    multiplier = multiplier,
    constant = constant,
    priority = priority,
  )

proc constraintWithAnchor(
    first: LayoutXAxisAnchor,
    relation: LayoutRelation,
    second: LayoutXAxisAnchor,
    constant: float32,
    priority: LayoutPriority,
): LayoutConstraint =
  newAnchorConstraint(
    first.xItem,
    first.xAttribute,
    relation,
    second.xItem,
    second.xAttribute,
    1.0'f32,
    resolvedAnchorConstant(first.xOffset, second.xOffset, constant),
    priority,
  )

proc constraintWithAnchor(
    first: LayoutYAxisAnchor,
    relation: LayoutRelation,
    second: LayoutYAxisAnchor,
    constant: float32,
    priority: LayoutPriority,
): LayoutConstraint =
  newAnchorConstraint(
    first.xItem,
    first.xAttribute,
    relation,
    second.xItem,
    second.xAttribute,
    1.0'f32,
    resolvedAnchorConstant(first.xOffset, second.xOffset, constant),
    priority,
  )

proc constraintWithAnchor(
    first: LayoutDimensionAnchor,
    relation: LayoutRelation,
    second: LayoutDimensionAnchor,
    multiplier: float32,
    constant: float32,
    priority: LayoutPriority,
): LayoutConstraint =
  newAnchorConstraint(
    first.xItem,
    first.xAttribute,
    relation,
    second.xItem,
    second.xAttribute,
    multiplier,
    resolvedAnchorConstant(first.xOffset, second.xOffset * multiplier, constant),
    priority,
  )

proc constraintWithConstant(
    first: LayoutDimensionAnchor,
    relation: LayoutRelation,
    constant: float32,
    priority: LayoutPriority,
): LayoutConstraint =
  newAnchorConstraint(
    first.xItem,
    first.xAttribute,
    relation,
    nil,
    latNotAnAttribute,
    1.0'f32,
    constant - first.xOffset,
    priority,
  )

proc constraintEqualTo*(
    first: LayoutXAxisAnchor,
    second: LayoutXAxisAnchor,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrEqual, second, constant, priority)

proc constraintGreaterThanOrEqualTo*(
    first: LayoutXAxisAnchor,
    second: LayoutXAxisAnchor,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrGreaterThanOrEqual, second, constant, priority)

proc constraintLessThanOrEqualTo*(
    first: LayoutXAxisAnchor,
    second: LayoutXAxisAnchor,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrLessThanOrEqual, second, constant, priority)

proc constraintEqualTo*(
    first: LayoutYAxisAnchor,
    second: LayoutYAxisAnchor,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrEqual, second, constant, priority)

proc constraintGreaterThanOrEqualTo*(
    first: LayoutYAxisAnchor,
    second: LayoutYAxisAnchor,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrGreaterThanOrEqual, second, constant, priority)

proc constraintLessThanOrEqualTo*(
    first: LayoutYAxisAnchor,
    second: LayoutYAxisAnchor,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrLessThanOrEqual, second, constant, priority)

proc constraintEqualTo*(
    first: LayoutDimensionAnchor,
    second: LayoutDimensionAnchor,
    multiplier = 1.0'f32,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrEqual, second, multiplier, constant, priority)

proc constraintGreaterThanOrEqualTo*(
    first: LayoutDimensionAnchor,
    second: LayoutDimensionAnchor,
    multiplier = 1.0'f32,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(
    lrGreaterThanOrEqual, second, multiplier, constant, priority
  )

proc constraintLessThanOrEqualTo*(
    first: LayoutDimensionAnchor,
    second: LayoutDimensionAnchor,
    multiplier = 1.0'f32,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrLessThanOrEqual, second, multiplier, constant, priority)

proc constraintEqualTo*(
    first: LayoutDimensionAnchor, constant: float32, priority = LayoutPriorityRequired
): LayoutConstraint =
  first.constraintWithConstant(lrEqual, constant, priority)

proc constraintGreaterThanOrEqualTo*(
    first: LayoutDimensionAnchor, constant: float32, priority = LayoutPriorityRequired
): LayoutConstraint =
  first.constraintWithConstant(lrGreaterThanOrEqual, constant, priority)

proc constraintLessThanOrEqualTo*(
    first: LayoutDimensionAnchor, constant: float32, priority = LayoutPriorityRequired
): LayoutConstraint =
  first.constraintWithConstant(lrLessThanOrEqual, constant, priority)

proc constraintEqualToConstant*(
    first: LayoutDimensionAnchor, constant: float32, priority = LayoutPriorityRequired
): LayoutConstraint =
  first.constraintEqualTo(constant, priority)

proc constraintGreaterThanOrEqualToConstant*(
    first: LayoutDimensionAnchor, constant: float32, priority = LayoutPriorityRequired
): LayoutConstraint =
  first.constraintGreaterThanOrEqualTo(constant, priority)

proc constraintLessThanOrEqualToConstant*(
    first: LayoutDimensionAnchor, constant: float32, priority = LayoutPriorityRequired
): LayoutConstraint =
  first.constraintLessThanOrEqualTo(constant, priority)

proc pinEdges*(
    view: View,
    toView: View,
    insets = initEdgeInsets(0.0),
    edges = AllLayoutEdges,
    priority = LayoutPriorityRequired,
): seq[LayoutConstraint] =
  if leLeft in edges:
    result.add view.leftAnchor.constraintEqualTo(
      toView.leftAnchor, constant = insets.left, priority = priority
    )
  if leTop in edges:
    result.add view.topAnchor.constraintEqualTo(
      toView.topAnchor, constant = insets.top, priority = priority
    )
  if leRight in edges:
    result.add view.rightAnchor.constraintEqualTo(
      toView.rightAnchor, constant = -insets.right, priority = priority
    )
  if leBottom in edges:
    result.add view.bottomAnchor.constraintEqualTo(
      toView.bottomAnchor, constant = -insets.bottom, priority = priority
    )

proc pinEdges*(
    view: View,
    toGuide: LayoutGuide,
    insets = initEdgeInsets(0.0),
    edges = AllLayoutEdges,
    priority = LayoutPriorityRequired,
): seq[LayoutConstraint] =
  if leLeft in edges:
    result.add view.leftAnchor.constraintEqualTo(
      toGuide.leftAnchor, constant = insets.left, priority = priority
    )
  if leTop in edges:
    result.add view.topAnchor.constraintEqualTo(
      toGuide.topAnchor, constant = insets.top, priority = priority
    )
  if leRight in edges:
    result.add view.rightAnchor.constraintEqualTo(
      toGuide.rightAnchor, constant = -insets.right, priority = priority
    )
  if leBottom in edges:
    result.add view.bottomAnchor.constraintEqualTo(
      toGuide.bottomAnchor, constant = -insets.bottom, priority = priority
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

func solverValue(value: float32): KiwiScalar =
  value.KiwiScalar

func solverStrength(priority: LayoutPriority): Strength =
  if priority.priorityValue >= LayoutPriorityRequired.priorityValue:
    Required
  else:
    createStrength(0, 0, 1, max(priority.priorityValue, 1.0'f32).solverValue)

proc initLayoutSolveState(): LayoutSolveState =
  LayoutSolveState(solver: initSolver())

proc solverViewName(index: int, suffix: string): string =
  "v" & $index & "." & suffix

proc ensureSolverView(state: var LayoutSolveState, item: View): int =
  for index, solverView in state.items:
    if solverView.item == item:
      return index

  let index = state.items.len
  state.items.add SolverView(
    item: item,
    left: newVariable(index.solverViewName("left")),
    top: newVariable(index.solverViewName("top")),
    width: newVariable(index.solverViewName("width")),
    height: newVariable(index.solverViewName("height")),
  )
  index

proc solverView(state: var LayoutSolveState, item: View): SolverView =
  state.items[state.ensureSolverView(item)]

proc hasSolverView(state: LayoutSolveState, item: View): bool =
  for solverView in state.items:
    if solverView.item == item:
      return true
  false

proc addConstraintItem(state: var LayoutSolveState, item: View) =
  if item.isNil or not state.hasSolverView(item):
    return
  for existing in state.constraintItems:
    if existing == item:
      return
  state.constraintItems.add item

proc hasConstraintItem(state: LayoutSolveState, item: View): bool =
  for existing in state.constraintItems:
    if existing == item:
      return true
  false

proc collectSolverViews(state: var LayoutSolveState, item: View) =
  if item.isNil:
    return
  discard state.ensureSolverView(item)
  for child in item.xSubviews:
    state.collectSolverViews(child)

proc collectConstraintItems(state: var LayoutSolveState, owner: View) =
  if owner.isNil:
    return
  for constraint in owner.xConstraints:
    if not constraint.isNil and constraint.xActive:
      state.addConstraintItem(constraint.xFirstItem)
      state.addConstraintItem(constraint.xSecondItem)
  for child in owner.xSubviews:
    state.collectConstraintItems(child)

proc addStay(
    state: var LayoutSolveState, variable: Variable, value: float32, strength: Strength
) =
  state.solver.addEditVariable(variable, strength)
  state.solver.suggestValue(variable, value.solverValue)

proc addGeometryStays(state: var LayoutSolveState, root: View) =
  for solverView in state.items:
    if solverView.item != root:
      let rect = solverView.item.alignmentRect()
      state.addStay(solverView.left, rect.minX, Weak)
      state.addStay(solverView.top, rect.minY, Weak)
      state.addStay(solverView.width, rect.size.width, Weak)
      state.addStay(solverView.height, rect.size.height, Weak)

proc expressionFor(solverView: SolverView, attribute: LayoutAttribute): Expression =
  case attribute
  of latLeft, latLeading:
    solverView.left.toExpression()
  of latRight, latTrailing:
    solverView.left + solverView.width
  of latTop:
    solverView.top.toExpression()
  of latBottom:
    solverView.top + solverView.height
  of latWidth:
    solverView.width.toExpression()
  of latHeight:
    solverView.height.toExpression()
  of latCenterX:
    solverView.left + solverView.width * 0.5
  of latCenterY:
    solverView.top + solverView.height * 0.5
  of latFirstBaseline:
    solverView.top + solverView.item.firstBaselineOffset().solverValue
  of latLastBaseline:
    solverView.top + solverView.height - solverView.item.lastBaselineOffset().solverValue
  of latNotAnAttribute:
    toExpression(0.KiwiScalar)

proc strengthened(constraint: Constraint, priority: LayoutPriority): Constraint =
  if priority.priorityValue >= LayoutPriorityRequired.priorityValue:
    constraint
  else:
    constraint.withStrength(priority.solverStrength)

proc addSolverConstraint(
    state: var LayoutSolveState,
    constraint: Constraint,
    priority = LayoutPriorityRequired,
) =
  try:
    state.solver.addConstraint(constraint.strengthened(priority))
  except UnsatisfiableConstraintError:
    discard

proc addRootGeometryConstraints(state: var LayoutSolveState, root: View) =
  if root.isNil:
    return
  let
    solverView = state.solverView(root)
    rect = root.alignmentRect()
  state.addSolverConstraint(eq(solverView.left, rect.minX.solverValue))
  state.addSolverConstraint(eq(solverView.top, rect.minY.solverValue))
  state.addSolverConstraint(eq(solverView.width, rect.size.width.solverValue))
  state.addSolverConstraint(eq(solverView.height, rect.size.height.solverValue))

proc addRelation(
    state: var LayoutSolveState,
    left, right: Expression,
    relation: LayoutRelation,
    priority = LayoutPriorityRequired,
) =
  let constraint =
    case relation
    of lrLessThanOrEqual:
      le(left, right)
    of lrEqual:
      eq(left, right)
    of lrGreaterThanOrEqual:
      ge(left, right)
  state.addSolverConstraint(constraint, priority)

proc addNonNegativeSizeConstraints(state: var LayoutSolveState) =
  for solverView in state.items:
    state.addSolverConstraint(ge(solverView.width, 0))
    state.addSolverConstraint(ge(solverView.height, 0))

proc addIntrinsicConstraints(state: var LayoutSolveState, item: View) =
  if item.isNil:
    return

  if not item.xAutoresizingMaskConstraints or state.hasConstraintItem(item):
    let
      solverView = state.solverView(item)
      intrinsicSize = item.resolvedIntrinsicContentSize()
    if intrinsicSize.hasWidth:
      state.addSolverConstraint(
        ge(solverView.width, intrinsicSize.width.solverValue),
        item.compressionPriority(laHorizontal),
      )
      state.addSolverConstraint(
        le(solverView.width, intrinsicSize.width.solverValue),
        item.huggingPriority(laHorizontal),
      )
    if intrinsicSize.hasHeight:
      state.addSolverConstraint(
        ge(solverView.height, intrinsicSize.height.solverValue),
        item.compressionPriority(laVertical),
      )
      state.addSolverConstraint(
        le(solverView.height, intrinsicSize.height.solverValue),
        item.huggingPriority(laVertical),
      )

  for child in item.xSubviews:
    state.addIntrinsicConstraints(child)

proc addLayoutConstraint(state: var LayoutSolveState, constraint: LayoutConstraint) =
  if constraint.isNil or not constraint.xActive or constraint.xFirstItem.isNil:
    return
  if not state.hasSolverView(constraint.xFirstItem):
    return
  if not constraint.xSecondItem.isNil and not state.hasSolverView(
    constraint.xSecondItem
  ):
    return

  let left =
    state.solverView(constraint.xFirstItem).expressionFor(constraint.xFirstAttribute)
  let right =
    if constraint.xSecondItem.isNil:
      toExpression(constraint.xConstant.solverValue)
    else:
      state.solverView(constraint.xSecondItem).expressionFor(
        constraint.xSecondAttribute
      ) * constraint.xMultiplier.solverValue + constraint.xConstant.solverValue

  state.addRelation(left, right, constraint.xRelation, constraint.xPriority)

proc addOwnedConstraints(state: var LayoutSolveState, owner: View) =
  if owner.isNil:
    return
  for constraint in owner.xConstraints:
    state.addLayoutConstraint(constraint)
  for child in owner.xSubviews:
    state.addOwnedConstraints(child)

proc solvedFloat(variable: Variable): float32 =
  float32(variable.value.toFloat)

proc applySolvedFrames(state: LayoutSolveState) =
  for solverView in state.items:
    if not solverView.item.isNil:
      let alignmentRect = initRect(
        solverView.left.solvedFloat(),
        solverView.top.solvedFloat(),
        max(solverView.width.solvedFloat(), 0.0'f32),
        max(solverView.height.solvedFloat(), 0.0'f32),
      )
      solverView.item.setFrameFromLayout(
        solverView.item.frameForAlignmentRect(alignmentRect)
      )

proc applyConstraintsForSubtree*(view: View) =
  if view.isNil:
    return
  var state = initLayoutSolveState()
  state.collectSolverViews(view)
  state.collectConstraintItems(view)
  state.addRootGeometryConstraints(view)
  state.addGeometryStays(view)
  state.addNonNegativeSizeConstraints()
  state.addIntrinsicConstraints(view)
  state.addOwnedConstraints(view)
  state.solver.updateVariables()
  state.applySolvedFrames()
