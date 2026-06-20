import std/macros

import pkg/kiwiberry

import ../drawing/theme
import ../foundation/types
import ./viewgeometry
import ./viewbase

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

  LayoutConstraintExpression*[A] = object
    xFirstItem: View
    xFirstAttribute: LayoutAttribute
    xRelation: LayoutRelation
    xSecondItem: View
    xSecondAttribute: LayoutAttribute
    xFirstOffset: float32
    xSecondOffset: float32
    xConstant: float32

  LayoutGuide* = object
    xOwningView: View
    xInsets: EdgeInsets

  SolverView = object
    item: View
    left: Variable
    top: Variable
    width: Variable
    height: Variable

  AutoresizingAxisOptions = object
    minMargin: AutoresizingMaskOption
    size: AutoresizingMaskOption
    maxMargin: AutoresizingMaskOption

  AutoresizingAxisShares = object
    minMargin: float32
    size: float32

  LayoutSolveState = object
    solver: Solver
    items: seq[SolverView]
    constraintItems: seq[View]
    generatedInputs: seq[LayoutInput]

const
  AllLayoutEdges* = {leLeft, leTop, leRight, leBottom}
  GeneratedLayoutSources = {lisAutoresizingMask, lisIntrinsic, lisContainer}

proc initLayoutTerm(
    item: View, attribute: LayoutAttribute, multiplier = 1.0'f32
): LayoutTerm =
  LayoutTerm(item: item, attribute: attribute, multiplier: multiplier)

proc initLayoutEquation(
    terms: openArray[LayoutTerm],
    relation: LayoutRelation,
    constant: float32,
    priority = LayoutPriorityRequired,
    source = lisContainer,
): LayoutEquation =
  LayoutEquation(
    terms: @terms,
    relation: relation,
    constant: constant,
    priority: priority,
    source: source,
  )

proc layoutEquationInput(equation: LayoutEquation): LayoutInput =
  LayoutInput(kind: likEquation, equation: equation)

proc layoutConstraintInput(constraint: LayoutConstraint): LayoutInput =
  LayoutInput(kind: likConstraint, constraint: constraint)

proc source*(input: LayoutInput): LayoutInputSource =
  case input.kind
  of likConstraint: lisUser
  of likEquation: input.equation.source

proc generatedLayoutInputs*(view: View): seq[LayoutInput] =
  for source in LayoutInputSource:
    for input in view.xLayoutInputCache.generated[source]:
      result.add input

proc addToSummary(
    summaries: var seq[LayoutInputSummary],
    source: LayoutInputSource,
    constraints = 0.Natural,
    equations = 0.Natural,
    terms = 0.Natural,
) =
  for summary in mitems(summaries):
    if summary.source == source:
      summary.constraints += constraints
      summary.equations += equations
      summary.terms += terms
      return
  summaries.add LayoutInputSummary(
    source: source, constraints: constraints, equations: equations, terms: terms
  )

proc addInputSummary(summaries: var seq[LayoutInputSummary], input: LayoutInput) =
  case input.kind
  of likConstraint:
    summaries.addToSummary(lisUser, constraints = 1.Natural)
  of likEquation:
    summaries.addToSummary(
      input.equation.source,
      equations = 1.Natural,
      terms = Natural(input.equation.terms.len),
    )

proc collectAuthoredConstraintSummary(
    view: View, summaries: var seq[LayoutInputSummary]
) =
  for constraint in view.xConstraints:
    if not constraint.isNil and constraint.xActive:
      summaries.addToSummary(lisUser, constraints = 1.Natural)
  for child in view.xSubviews:
    child.collectAuthoredConstraintSummary(summaries)

proc generatedLayoutSummary*(view: View): seq[LayoutInputSummary] =
  for input in view.generatedLayoutInputs():
    result.addInputSummary(input)

proc constraintsAffectingLayout*(view: View): seq[LayoutInputSummary] =
  view.collectAuthoredConstraintSummary(result)
  for summary in view.generatedLayoutSummary():
    result.addToSummary(
      summary.source,
      constraints = summary.constraints,
      equations = summary.equations,
      terms = summary.terms,
    )

proc layoutInputDirtySources*(view: View): LayoutInputSources =
  if view.isNil:
    {}
  else:
    view.xLayoutInputCache.dirtySources

proc layoutInputGeneration*(view: View): Natural =
  if view.isNil: 0 else: view.xLayoutInputCache.generation

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

const
  ViewXAxisAnchors = {atLeft, atRight, atLeading, atTrailing, atCenterX}
  ViewYAxisAnchors = {atTop, atBottom, atCenterY}

proc `[]`*(view: View, anchor: static[LayoutAttribute]): auto =
  when anchor in ViewXAxisAnchors:
    return initXAxisAnchor(view, anchor)
  elif anchor in ViewYAxisAnchors:
    return initYAxisAnchor(view, anchor)
  elif anchor in {atWidth, atHeight}:
    return initDimensionAnchor(view, anchor)
  else:
    {.
      error:
        "Invalid LayoutAttribute in view[] indexing; use one of atLeft, atRight, atLeading, atTrailing, atTop, atBottom, atCenterX, atCenterY, atWidth, atHeight."
    .}

proc `[]`*(guide: LayoutGuide, anchor: static[LayoutAttribute]): auto =
  let offset =
    case anchor
    of atLeft, atLeading:
      guide.xInsets.left
    of atRight, atTrailing:
      -guide.xInsets.right
    of atTop:
      guide.xInsets.top
    of atBottom:
      -guide.xInsets.bottom
    of atCenterX:
      (guide.xInsets.left - guide.xInsets.right) / 2.0
    of atCenterY:
      (guide.xInsets.top - guide.xInsets.bottom) / 2.0
    of atWidth:
      -guide.xInsets.horizontal
    of atHeight:
      -guide.xInsets.vertical
    else:
      0.0'f32
  when anchor in ViewXAxisAnchors:
    return initXAxisAnchor(guide.xOwningView, anchor, offset)
  elif anchor in ViewYAxisAnchors:
    return initYAxisAnchor(guide.xOwningView, anchor, offset)
  elif anchor in {atWidth, atHeight}:
    return initDimensionAnchor(guide.xOwningView, anchor, offset)
  else:
    {.
      error:
        "Invalid LayoutAttribute in guide[] indexing; use one of atLeft, atRight, atLeading, atTrailing, atTop, atBottom, atCenterX, atCenterY, atWidth, atHeight."
    .}

proc `+`*(anchor: LayoutXAxisAnchor, constant: float32): LayoutXAxisAnchor =
  initXAxisAnchor(anchor.xItem, anchor.xAttribute, anchor.xOffset + constant)

proc `+`*(constant: float32, anchor: LayoutXAxisAnchor): LayoutXAxisAnchor =
  anchor + constant

proc `-`*(anchor: LayoutXAxisAnchor, constant: float32): LayoutXAxisAnchor =
  initXAxisAnchor(anchor.xItem, anchor.xAttribute, anchor.xOffset - constant)

proc `+`*(anchor: LayoutYAxisAnchor, constant: float32): LayoutYAxisAnchor =
  initYAxisAnchor(anchor.xItem, anchor.xAttribute, anchor.xOffset + constant)

proc `+`*(constant: float32, anchor: LayoutYAxisAnchor): LayoutYAxisAnchor =
  anchor + constant

proc `-`*(anchor: LayoutYAxisAnchor, constant: float32): LayoutYAxisAnchor =
  initYAxisAnchor(anchor.xItem, anchor.xAttribute, anchor.xOffset - constant)

proc `+`*(anchor: LayoutDimensionAnchor, constant: float32): LayoutDimensionAnchor =
  initDimensionAnchor(anchor.xItem, anchor.xAttribute, anchor.xOffset + constant)

proc `+`*(constant: float32, anchor: LayoutDimensionAnchor): LayoutDimensionAnchor =
  anchor + constant

proc `-`*(anchor: LayoutDimensionAnchor, constant: float32): LayoutDimensionAnchor =
  initDimensionAnchor(anchor.xItem, anchor.xAttribute, anchor.xOffset - constant)

proc newLayoutConstraint*(
    firstItem: View,
    firstAttribute: LayoutAttribute,
    relation = lrEqual,
    secondItem: View = nil,
    secondAttribute = atNotAnAttribute,
    multiplier = 1.0'f32,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  result = LayoutConstraint(
    xFirstItem: firstItem,
    xFirstAttribute: firstAttribute,
    xRelation: relation,
    xSecondItem: secondItem,
    xSecondAttribute: if secondItem.isNil: atNotAnAttribute else: secondAttribute,
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
    atNotAnAttribute,
    1.0'f32,
    constant - first.xOffset,
    priority,
  )

proc equalTo*(
    first: LayoutXAxisAnchor,
    second: LayoutXAxisAnchor,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrEqual, second, constant, priority)

proc greaterThanOrEqualTo*(
    first: LayoutXAxisAnchor,
    second: LayoutXAxisAnchor,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrGreaterThanOrEqual, second, constant, priority)

proc lessThanOrEqualTo*(
    first: LayoutXAxisAnchor,
    second: LayoutXAxisAnchor,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrLessThanOrEqual, second, constant, priority)

proc equalTo*(
    first: LayoutYAxisAnchor,
    second: LayoutYAxisAnchor,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrEqual, second, constant, priority)

proc greaterThanOrEqualTo*(
    first: LayoutYAxisAnchor,
    second: LayoutYAxisAnchor,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrGreaterThanOrEqual, second, constant, priority)

proc lessThanOrEqualTo*(
    first: LayoutYAxisAnchor,
    second: LayoutYAxisAnchor,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrLessThanOrEqual, second, constant, priority)

proc equalTo*(
    first: LayoutDimensionAnchor,
    second: LayoutDimensionAnchor,
    multiplier = 1.0'f32,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrEqual, second, multiplier, constant, priority)

proc greaterThanOrEqualTo*(
    first: LayoutDimensionAnchor,
    second: LayoutDimensionAnchor,
    multiplier = 1.0'f32,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(
    lrGreaterThanOrEqual, second, multiplier, constant, priority
  )

proc lessThanOrEqualTo*(
    first: LayoutDimensionAnchor,
    second: LayoutDimensionAnchor,
    multiplier = 1.0'f32,
    constant = 0.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  first.constraintWithAnchor(lrLessThanOrEqual, second, multiplier, constant, priority)

proc equalTo*(
    first: LayoutDimensionAnchor, constant: float32, priority = LayoutPriorityRequired
): LayoutConstraint =
  first.constraintWithConstant(lrEqual, constant, priority)

proc initConstraintExpression(
    A: typedesc,
    firstItem: View,
    firstAttribute: LayoutAttribute,
    relation: LayoutRelation,
    secondItem: View,
    secondAttribute: LayoutAttribute,
    firstOffset: float32,
    secondOffset: float32,
    constant: float32,
): LayoutConstraintExpression[A] =
  LayoutConstraintExpression[A](
    xFirstItem: firstItem,
    xFirstAttribute: firstAttribute,
    xRelation: relation,
    xSecondItem: secondItem,
    xSecondAttribute: secondAttribute,
    xFirstOffset: firstOffset,
    xSecondOffset: secondOffset,
    xConstant: constant,
  )

proc constraintExpression(
    first: LayoutXAxisAnchor, relation: LayoutRelation, second: LayoutXAxisAnchor
): LayoutConstraintExpression[LayoutXAxisAnchor] =
  initConstraintExpression(
    LayoutXAxisAnchor, first.xItem, first.xAttribute, relation, second.xItem,
    second.xAttribute, first.xOffset, second.xOffset, 0.0'f32,
  )

proc constraintExpression(
    first: LayoutYAxisAnchor, relation: LayoutRelation, second: LayoutYAxisAnchor
): LayoutConstraintExpression[LayoutYAxisAnchor] =
  initConstraintExpression(
    LayoutYAxisAnchor, first.xItem, first.xAttribute, relation, second.xItem,
    second.xAttribute, first.xOffset, second.xOffset, 0.0'f32,
  )

proc constraintExpression(
    first: LayoutDimensionAnchor,
    relation: LayoutRelation,
    second: LayoutDimensionAnchor,
): LayoutConstraintExpression[LayoutDimensionAnchor] =
  initConstraintExpression(
    LayoutDimensionAnchor, first.xItem, first.xAttribute, relation, second.xItem,
    second.xAttribute, first.xOffset, second.xOffset, 0.0'f32,
  )

proc constraintExpression(
    first: LayoutDimensionAnchor, relation: LayoutRelation, constant: float32
): LayoutConstraintExpression[LayoutDimensionAnchor] =
  initConstraintExpression(
    LayoutDimensionAnchor, first.xItem, first.xAttribute, relation, nil,
    atNotAnAttribute, first.xOffset, 0.0'f32, constant,
  )

proc constraintExpression(
    first: LayoutDimensionAnchor, relation: LayoutRelation, constant: LayoutLength
): LayoutConstraintExpression[LayoutDimensionAnchor] =
  first.constraintExpression(relation, constant.resolveLayoutLength())

proc `==`*(
    first, second: LayoutXAxisAnchor
): LayoutConstraintExpression[LayoutXAxisAnchor] =
  first.constraintExpression(lrEqual, second)

proc `>=`*(
    first, second: LayoutXAxisAnchor
): LayoutConstraintExpression[LayoutXAxisAnchor] =
  first.constraintExpression(lrGreaterThanOrEqual, second)

proc `<=`*(
    first, second: LayoutXAxisAnchor
): LayoutConstraintExpression[LayoutXAxisAnchor] =
  first.constraintExpression(lrLessThanOrEqual, second)

proc `==`*(
    first, second: LayoutYAxisAnchor
): LayoutConstraintExpression[LayoutYAxisAnchor] =
  first.constraintExpression(lrEqual, second)

proc `>=`*(
    first, second: LayoutYAxisAnchor
): LayoutConstraintExpression[LayoutYAxisAnchor] =
  first.constraintExpression(lrGreaterThanOrEqual, second)

proc `<=`*(
    first, second: LayoutYAxisAnchor
): LayoutConstraintExpression[LayoutYAxisAnchor] =
  first.constraintExpression(lrLessThanOrEqual, second)

proc `==`*(
    first, second: LayoutDimensionAnchor
): LayoutConstraintExpression[LayoutDimensionAnchor] =
  first.constraintExpression(lrEqual, second)

proc `>=`*(
    first, second: LayoutDimensionAnchor
): LayoutConstraintExpression[LayoutDimensionAnchor] =
  first.constraintExpression(lrGreaterThanOrEqual, second)

proc `<=`*(
    first, second: LayoutDimensionAnchor
): LayoutConstraintExpression[LayoutDimensionAnchor] =
  first.constraintExpression(lrLessThanOrEqual, second)

proc `==`*(
    first: LayoutDimensionAnchor, constant: float32
): LayoutConstraintExpression[LayoutDimensionAnchor] =
  first.constraintExpression(lrEqual, constant)

proc `==`*(
    first: LayoutDimensionAnchor, constant: LayoutLength
): LayoutConstraintExpression[LayoutDimensionAnchor] =
  first.constraintExpression(lrEqual, constant)

proc `>=`*(
    first: LayoutDimensionAnchor, constant: float32
): LayoutConstraintExpression[LayoutDimensionAnchor] =
  first.constraintExpression(lrGreaterThanOrEqual, constant)

proc `>=`*(
    first: LayoutDimensionAnchor, constant: LayoutLength
): LayoutConstraintExpression[LayoutDimensionAnchor] =
  first.constraintExpression(lrGreaterThanOrEqual, constant)

proc `<=`*(
    first: LayoutDimensionAnchor, constant: float32
): LayoutConstraintExpression[LayoutDimensionAnchor] =
  first.constraintExpression(lrLessThanOrEqual, constant)

proc `<=`*(
    first: LayoutDimensionAnchor, constant: LayoutLength
): LayoutConstraintExpression[LayoutDimensionAnchor] =
  first.constraintExpression(lrLessThanOrEqual, constant)

proc constraintFromExpression(
    expression: LayoutConstraintExpression,
    multiplier = 1.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  let resolvedConstant =
    if expression.xSecondItem.isNil:
      expression.xConstant - expression.xFirstOffset
    else:
      resolvedAnchorConstant(
        expression.xFirstOffset,
        expression.xSecondOffset * multiplier,
        expression.xConstant,
      )
  newAnchorConstraint(
    expression.xFirstItem, expression.xFirstAttribute, expression.xRelation,
    expression.xSecondItem, expression.xSecondAttribute, multiplier, resolvedConstant,
    priority,
  )

proc cx*(
    expression: LayoutConstraintExpression[LayoutXAxisAnchor],
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  expression.constraintFromExpression(priority = priority)

proc cx*(
    expression: LayoutConstraintExpression[LayoutYAxisAnchor],
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  expression.constraintFromExpression(priority = priority)

proc cx*(
    expression: LayoutConstraintExpression[LayoutDimensionAnchor],
    multiplier = 1.0'f32,
    priority = LayoutPriorityRequired,
): LayoutConstraint =
  expression.constraintFromExpression(multiplier = multiplier, priority = priority)

proc cx*(constraint: LayoutConstraint): LayoutConstraint =
  constraint

macro activateConstraints*(body: untyped): untyped =
  result = newCall(ident"activate")
  let statements =
    if body.kind == nnkStmtList:
      body
    else:
      newStmtList(body)
  for statement in statements:
    if statement.kind != nnkEmpty:
      result.add newCall(ident"cx", statement)

proc greaterThanOrEqualTo*(
    first: LayoutDimensionAnchor, constant: float32, priority = LayoutPriorityRequired
): LayoutConstraint =
  first.constraintWithConstant(lrGreaterThanOrEqual, constant, priority)

proc lessThanOrEqualTo*(
    first: LayoutDimensionAnchor, constant: float32, priority = LayoutPriorityRequired
): LayoutConstraint =
  first.constraintWithConstant(lrLessThanOrEqual, constant, priority)

proc activateConstraints*(constraints: openArray[LayoutConstraint])

proc edgeConstraints*(
    view: View,
    toView: View,
    insets = initEdgeInsets(0.0),
    edges = AllLayoutEdges,
    priority = LayoutPriorityRequired,
): seq[LayoutConstraint] =
  if leLeft in edges:
    result.add view[atLeft].equalTo(
      toView[atLeft], constant = insets.left, priority = priority
    )
  if leTop in edges:
    result.add view[atTop].equalTo(
      toView[atTop], constant = insets.top, priority = priority
    )
  if leRight in edges:
    result.add view[atRight].equalTo(
      toView[atRight], constant = -insets.right, priority = priority
    )
  if leBottom in edges:
    result.add view[atBottom].equalTo(
      toView[atBottom], constant = -insets.bottom, priority = priority
    )

proc pinEdges*(
    view: View,
    toView: View,
    insets = initEdgeInsets(0.0),
    edges = AllLayoutEdges,
    priority = LayoutPriorityRequired,
): seq[LayoutConstraint] {.discardable.} =
  result = view.edgeConstraints(
    toView = toView, insets = insets, edges = edges, priority = priority
  )
  activateConstraints(result)

proc edgeConstraints*(
    view: View,
    toGuide: LayoutGuide,
    insets = initEdgeInsets(0.0),
    edges = AllLayoutEdges,
    priority = LayoutPriorityRequired,
): seq[LayoutConstraint] =
  if leLeft in edges:
    result.add view[atLeft].equalTo(
      toGuide[atLeft], constant = insets.left, priority = priority
    )
  if leTop in edges:
    result.add view[atTop].equalTo(
      toGuide[atTop], constant = insets.top, priority = priority
    )
  if leRight in edges:
    result.add view[atRight].equalTo(
      toGuide[atRight], constant = -insets.right, priority = priority
    )
  if leBottom in edges:
    result.add view[atBottom].equalTo(
      toGuide[atBottom], constant = -insets.bottom, priority = priority
    )

proc pinEdges*(
    view: View,
    toGuide: LayoutGuide,
    insets = initEdgeInsets(0.0),
    edges = AllLayoutEdges,
    priority = LayoutPriorityRequired,
): seq[LayoutConstraint] {.discardable.} =
  result = view.edgeConstraints(
    toGuide = toGuide, insets = insets, edges = edges, priority = priority
  )
  activateConstraints(result)

proc firstItem*(constraint: LayoutConstraint): View =
  if constraint.isNil: nil else: constraint.xFirstItem

proc firstAttribute*(constraint: LayoutConstraint): LayoutAttribute =
  if constraint.isNil: atNotAnAttribute else: constraint.xFirstAttribute

proc relation*(constraint: LayoutConstraint): LayoutRelation =
  if constraint.isNil: lrEqual else: constraint.xRelation

proc secondItem*(constraint: LayoutConstraint): View =
  if constraint.isNil: nil else: constraint.xSecondItem

proc secondAttribute*(constraint: LayoutConstraint): LayoutAttribute =
  if constraint.isNil: atNotAnAttribute else: constraint.xSecondAttribute

proc multiplier*(constraint: LayoutConstraint): float32 =
  if constraint.isNil: 1.0'f32 else: constraint.xMultiplier

proc constant*(constraint: LayoutConstraint): float32 =
  if constraint.isNil: 0.0'f32 else: constraint.xConstant

proc priority*(constraint: LayoutConstraint): LayoutPriority =
  if constraint.isNil: LayoutPriorityRequired else: constraint.xPriority

proc isActive*(constraint: LayoutConstraint): bool =
  (not constraint.isNil) and constraint.xActive

proc active*(constraint: LayoutConstraint): bool =
  constraint.isActive()

proc owningView*(constraint: LayoutConstraint): View =
  if constraint.isNil: nil else: constraint.xOwningView

proc invalidateActiveConstraint(constraint: LayoutConstraint) =
  if constraint.isNil or not constraint.xActive:
    return
  constraint.xOwningView.markConstraintStorageChanged()

proc `constant=`*(constraint: LayoutConstraint, constant: float32) =
  if constraint.isNil or constraint.xConstant == constant:
    return
  constraint.xConstant = constant
  constraint.invalidateActiveConstraint()

proc `priority=`*(constraint: LayoutConstraint, priority: LayoutPriority) =
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

proc addConstraints*(
    view: View, constraint: LayoutConstraint, rest: varargs[LayoutConstraint]
) =
  view.addConstraint(constraint)
  view.addConstraints(rest)

proc removeConstraint*(view: View, constraint: LayoutConstraint) =
  view.removeStoredConstraint(constraint)

proc removeConstraints*(view: View, constraints: openArray[LayoutConstraint]) =
  for constraint in constraints:
    view.removeConstraint(constraint)

proc removeConstraints*(
    view: View, constraint: LayoutConstraint, rest: varargs[LayoutConstraint]
) =
  view.removeConstraint(constraint)
  view.removeConstraints(rest)

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

proc `active=`*(constraint: LayoutConstraint, active: bool) =
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

proc setConstraintsActive(constraints: openArray[LayoutConstraint], active: bool) =
  for constraint in constraints:
    constraint.active = active

proc setConstraintsActive(
    constraint: LayoutConstraint, rest: openArray[LayoutConstraint], active: bool
) =
  constraint.active = active
  setConstraintsActive(rest, active)

proc activateConstraints*(constraints: openArray[LayoutConstraint]) =
  setConstraintsActive(constraints, true)

proc activateConstraints*(
    constraint: LayoutConstraint, rest: varargs[LayoutConstraint]
) =
  setConstraintsActive(constraint, rest, true)

proc deactivateConstraints*(constraints: openArray[LayoutConstraint]) =
  setConstraintsActive(constraints, false)

proc deactivateConstraints*(
    constraint: LayoutConstraint, rest: varargs[LayoutConstraint]
) =
  setConstraintsActive(constraint, rest, false)

proc activate*(constraints: openArray[LayoutConstraint]) =
  setConstraintsActive(constraints, true)

proc activate*(constraint: LayoutConstraint, rest: varargs[LayoutConstraint]) =
  setConstraintsActive(constraint, rest, true)

proc deactivate*(constraints: openArray[LayoutConstraint]) =
  setConstraintsActive(constraints, false)

proc deactivate*(constraint: LayoutConstraint, rest: varargs[LayoutConstraint]) =
  setConstraintsActive(constraint, rest, false)

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
  of atLeft, atLeading:
    solverView.left.toExpression()
  of atRight, atTrailing:
    solverView.left + solverView.width
  of atTop:
    solverView.top.toExpression()
  of atBottom:
    solverView.top + solverView.height
  of atWidth:
    solverView.width.toExpression()
  of atHeight:
    solverView.height.toExpression()
  of atCenterX:
    solverView.left + solverView.width * 0.5
  of atCenterY:
    solverView.top + solverView.height * 0.5
  of atFirstBaseline:
    solverView.top + solverView.item.firstBaselineOffset().solverValue
  of atLastBaseline:
    solverView.top + solverView.height - solverView.item.lastBaselineOffset().solverValue
  of atNotAnAttribute:
    toExpression(0.KiwiScalar)

func autoresizingOptions(axis: LayoutAxis): AutoresizingAxisOptions =
  case axis
  of laHorizontal:
    AutoresizingAxisOptions(
      minMargin: cxMinXMargin, size: cxWidthSizable, maxMargin: cxMaxXMargin
    )
  of laVertical:
    AutoresizingAxisOptions(
      minMargin: cxMinYMargin, size: cxHeightSizable, maxMargin: cxMaxYMargin
    )

func originAttribute(axis: LayoutAxis): LayoutAttribute =
  case axis
  of laHorizontal: atLeft
  of laVertical: atTop

func sizeAttribute(axis: LayoutAxis): LayoutAttribute =
  case axis
  of laHorizontal: atWidth
  of laVertical: atHeight

func axisFlexShare(
    flexible: bool, base, totalWeight: float32, flexibleCount: int
): float32 =
  if not flexible:
    return 0.0'f32
  if totalWeight > 0.0'f32:
    return max(base, 0.0'f32) / totalWeight
  if flexibleCount > 0:
    return 1.0'f32 / float32(flexibleCount)
  0.0'f32

func autoresizingAxisShares(
    mask: AutoresizingMask, axis: LayoutAxis, minMargin, size, maxMargin: float32
): AutoresizingAxisShares =
  let
    options = axis.autoresizingOptions()
    minFlexible = options.minMargin in mask
    sizeFlexible = options.size in mask
    maxFlexible = options.maxMargin in mask
    flexibleCount = ord(minFlexible) + ord(sizeFlexible) + ord(maxFlexible)
    totalWeight =
      (if minFlexible: max(minMargin, 0.0'f32) else: 0.0'f32) +
      (if sizeFlexible: max(size, 0.0'f32) else: 0.0'f32) +
      (if maxFlexible: max(maxMargin, 0.0'f32) else: 0.0'f32)

  if flexibleCount == 0:
    return AutoresizingAxisShares(minMargin: 0.0'f32, size: 0.0'f32)

  AutoresizingAxisShares(
    minMargin: axisFlexShare(minFlexible, minMargin, totalWeight, flexibleCount),
    size: axisFlexShare(sizeFlexible, size, totalWeight, flexibleCount),
  )

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

proc expressionFor(state: var LayoutSolveState, term: LayoutTerm): Expression =
  if term.item.isNil or not state.hasSolverView(term.item):
    return toExpression(0.KiwiScalar)
  state.solverView(term.item).expressionFor(term.attribute) * term.multiplier.solverValue

proc addLayoutEquation(state: var LayoutSolveState, equation: LayoutEquation) =
  if equation.terms.len == 0:
    return
  for term in equation.terms:
    if term.item.isNil or not state.hasSolverView(term.item):
      return

  var left = toExpression(0.KiwiScalar)
  for term in equation.terms:
    left = left + state.expressionFor(term)
  state.addRelation(
    left,
    toExpression(equation.constant.solverValue),
    equation.relation,
    equation.priority,
  )

proc addGeneratedEquation(state: var LayoutSolveState, equation: LayoutEquation) =
  state.generatedInputs.add equation.layoutEquationInput()

proc addNonNegativeSizeConstraints(state: var LayoutSolveState) =
  for solverView in state.items:
    state.addSolverConstraint(ge(solverView.width, 0))
    state.addSolverConstraint(ge(solverView.height, 0))

proc addIntrinsicConstraints(state: var LayoutSolveState, item: View) =
  if item.isNil:
    return

  if not item.xAutoresizingMaskConstraints or state.hasConstraintItem(item):
    let intrinsicSize = item.resolvedIntrinsicContentSize()
    if intrinsicSize.hasWidth:
      state.addGeneratedEquation(
        initLayoutEquation(
          [initLayoutTerm(item, atWidth)],
          lrGreaterThanOrEqual,
          intrinsicSize.width,
          item.compressionPriority(laHorizontal),
          lisIntrinsic,
        )
      )
      state.addGeneratedEquation(
        initLayoutEquation(
          [initLayoutTerm(item, atWidth)],
          lrLessThanOrEqual,
          intrinsicSize.width,
          item.huggingPriority(laHorizontal),
          lisIntrinsic,
        )
      )
    if intrinsicSize.hasHeight:
      state.addGeneratedEquation(
        initLayoutEquation(
          [initLayoutTerm(item, atHeight)],
          lrGreaterThanOrEqual,
          intrinsicSize.height,
          item.compressionPriority(laVertical),
          lisIntrinsic,
        )
      )
      state.addGeneratedEquation(
        initLayoutEquation(
          [initLayoutTerm(item, atHeight)],
          lrLessThanOrEqual,
          intrinsicSize.height,
          item.huggingPriority(laVertical),
          lisIntrinsic,
        )
      )

  for child in item.xSubviews:
    state.addIntrinsicConstraints(child)

proc addAutoresizingAxisConstraints(
    state: var LayoutSolveState, item, superview: View, axis: LayoutAxis
) =
  if item.isNil or superview.isNil:
    return

  let
    autoresizing = item.xAutoresizingState
    referenceChild = autoresizing.referenceRect
    referenceParent = autoresizing.referenceSuperviewRect
    minMargin = referenceChild.axisOrigin(axis) - referenceParent.axisOrigin(axis)
    size = referenceChild.axisSize(axis)
    maxMargin = referenceParent.axisSize(axis) - minMargin - size
    shares =
      item.xAutoresizingMask.autoresizingAxisShares(axis, minMargin, size, maxMargin)
    parentSize = referenceParent.axisSize(axis)
    originAttribute = axis.originAttribute()
    sizeAttribute = axis.sizeAttribute()

  state.addGeneratedEquation(
    initLayoutEquation(
      [
        initLayoutTerm(item, originAttribute),
        initLayoutTerm(superview, originAttribute, -1.0'f32),
        initLayoutTerm(superview, sizeAttribute, -shares.minMargin),
      ],
      lrEqual,
      minMargin - parentSize * shares.minMargin,
      source = lisAutoresizingMask,
    )
  )
  state.addGeneratedEquation(
    initLayoutEquation(
      [
        initLayoutTerm(item, sizeAttribute),
        initLayoutTerm(superview, sizeAttribute, -shares.size),
      ],
      lrEqual,
      size - parentSize * shares.size,
      source = lisAutoresizingMask,
    )
  )

proc addAutoresizingMaskConstraints(state: var LayoutSolveState, owner: View) =
  if owner.isNil:
    return

  for child in owner.xSubviews:
    if child.xAutoresizingMaskConstraints and not state.hasConstraintItem(child):
      child.refreshAutoresizingReferenceIfNeeded()
      if child.xAutoresizingState.hasReference and state.hasSolverView(child) and
          state.hasSolverView(owner):
        state.addAutoresizingAxisConstraints(child, owner, laHorizontal)
        state.addAutoresizingAxisConstraints(child, owner, laVertical)
    state.addAutoresizingMaskConstraints(child)

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

proc addLayoutInput(state: var LayoutSolveState, input: LayoutInput) =
  case input.kind
  of likConstraint:
    state.addLayoutConstraint(input.constraint)
  of likEquation:
    state.addLayoutEquation(input.equation)

proc addLayoutInputs(state: var LayoutSolveState, inputs: openArray[LayoutInput]) =
  for input in inputs:
    state.addLayoutInput(input)

proc addOwnedConstraints(state: var LayoutSolveState, owner: View) =
  if owner.isNil:
    return
  for constraint in owner.xConstraints:
    state.addLayoutInput(constraint.layoutConstraintInput())
  for child in owner.xSubviews:
    state.addOwnedConstraints(child)

proc solvedFloat(variable: Variable): float32 =
  float32(variable.value)

proc applySolvedFrames(state: LayoutSolveState) =
  for solverView in state.items:
    if not solverView.item.isNil:
      let alignmentRect = initRect(
        solverView.left.solvedFloat(),
        solverView.top.solvedFloat(),
        max(solverView.width.solvedFloat(), 0.0'f32),
        max(solverView.height.solvedFloat(), 0.0'f32),
      )
      solverView.item.applyLayoutFrame(
        solverView.item.frameForAlignmentRect(alignmentRect), lfoSolver
      )

proc refreshAutoresizingStates(state: LayoutSolveState) =
  for solverView in state.items:
    if not solverView.item.isNil and solverView.item.xAutoresizingMaskConstraints:
      solverView.item.refreshAutoresizingReference()

proc generatedSourcesToRebuild(root: View): LayoutInputSources =
  let dirtySources =
    root.xLayoutInputCache.dirtySources + root.xLayoutInputCache.aggregateDirtySources
  if root.xLayoutInputCache.generation == 0 or root.xLayoutInputCache.structureDirty or
      root.xLayoutInputCache.aggregateStructureDirty or lisUser in dirtySources:
    return GeneratedLayoutSources

  for source in GeneratedLayoutSources:
    if source in dirtySources:
      result.incl source

proc generateLayoutInputsForSource(
    state: var LayoutSolveState, root: View, source: LayoutInputSource
): seq[LayoutInput] =
  let start = state.generatedInputs.len
  case source
  of lisAutoresizingMask:
    state.addAutoresizingMaskConstraints(root)
  of lisIntrinsic:
    state.addIntrinsicConstraints(root)
  of lisContainer:
    discard
  of lisUser:
    discard

  if state.generatedInputs.len > start:
    result = state.generatedInputs[start ..< state.generatedInputs.len]
    state.generatedInputs.setLen(start)

proc refreshGeneratedLayoutInputs(state: var LayoutSolveState, root: View) =
  if root.isNil:
    return

  for source in root.generatedSourcesToRebuild():
    root.xLayoutInputCache.generated[source] =
      state.generateLayoutInputsForSource(root, source)
    inc root.xLayoutInputCache.sourceGenerations[source]

  for source in GeneratedLayoutSources:
    state.addLayoutInputs(root.xLayoutInputCache.generated[source])

proc refreshLayoutInputCaches(state: LayoutSolveState, root: View) =
  if not root.isNil:
    root.xLayoutInputCache.dirtySources = {}
    root.xLayoutInputCache.aggregateDirtySources = {}
    root.xLayoutInputCache.structureDirty = false
    root.xLayoutInputCache.aggregateStructureDirty = false
    inc root.xLayoutInputCache.generation

  for solverView in state.items:
    if not solverView.item.isNil and solverView.item != root:
      solverView.item.xLayoutInputCache.generated =
        default(array[LayoutInputSource, seq[LayoutInput]])
      solverView.item.xLayoutInputCache.dirtySources = {}
      solverView.item.xLayoutInputCache.aggregateDirtySources = {}
      solverView.item.xLayoutInputCache.structureDirty = false
      solverView.item.xLayoutInputCache.aggregateStructureDirty = false
      solverView.item.xLayoutInputCache.sourceGenerations =
        default(array[LayoutInputSource, Natural])
      solverView.item.xLayoutInputCache.generation = 0

proc applyConstraintsForSubtree*(view: View) =
  var state = initLayoutSolveState()
  state.collectSolverViews(view)
  state.collectConstraintItems(view)
  state.addRootGeometryConstraints(view)
  state.addGeometryStays(view)
  state.addNonNegativeSizeConstraints()
  state.refreshGeneratedLayoutInputs(view)
  state.addOwnedConstraints(view)
  state.solver.updateVariables()
  state.applySolvedFrames()
  state.refreshAutoresizingStates()
  state.refreshLayoutInputCaches(view)
