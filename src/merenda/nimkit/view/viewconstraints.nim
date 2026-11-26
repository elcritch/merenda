import std/[macros, math, monotimes, options, sets, tables, times]

import pkg/kiwiberry
import sigils/core
from sigils/hom import findFirst, isSome

import ../themes
from ../themes/themecore import
  layoutStyleSelection, constraintCount, validStyleConstraint
import ../themes/private/cssproperties
import ../foundation/selectors
import ../foundation/viewprofiling
import ../foundation/types
import ./viewgeometry
import ./viewbase
import ./viewprotos

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

  QueuedConstraint = object
    constraint: Constraint
    nonNegative: bool

  LayoutSolveState = object
    solver: Solver
    items: seq[SolverView]
    itemIndexes: Table[pointer, int]
    variableItems: Table[VariableId, int]
    queued: seq[QueuedConstraint]
    pins: seq[Constraint]
    pinnedVariables: Table[VariableId, int]
    partitioned: bool
    components: seq[Solver]
    componentPins: seq[set[uint8]]
    itemComponents: seq[int]
    pinComponent: int
    constraintItemIndexes: HashSet[pointer]
    keepsContainerFrames: bool
    generatedInputs: seq[LayoutInput]
    limits: LayoutSolveLimits
    startedAt: MonoTime
    constraintCount: Natural
    coefficientCount: Natural
    workConstraintCount: Natural
    workCoefficientCount: Natural
    cssInputs: seq[LayoutInput]
    cssSubjects: HashSet[pointer]
    cssTargets: HashSet[pointer]
    cssDiagnostics: seq[CssLayoutDiagnostic]
    didResolveCss: bool
    when defined(merendaPersistentLayout):
      recordOnly: bool
      captureConstraints: bool
      captureFailed: bool
      capturedConstraints: seq[Constraint]

  LayoutSolveBudgetExceeded = object of CatchableError
    diagnostic: LayoutSolveDiagnostic

  CssLayoutGeometryError = object of CatchableError

const
  AllLayoutEdges* = {leLeft, leTop, leRight, leBottom}
  GeneratedLayoutSources = {lisAutoresizingMask, lisIntrinsic, lisContainer}

proc initLayoutTerm(
    item: View, attribute: LayoutAttribute, multiplier = 1.0'f32
): LayoutTerm =
  result = LayoutTerm(attribute: attribute, multiplier: multiplier)
  result.item = item

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

proc cssLayoutDiagnostics*(view: View, fitting = false): seq[CssLayoutDiagnostic] =
  ## Returns defensive diagnostics for this root's latest attempt in that mode.
  ## Measuring a fitting size does not replace the last layout diagnostics.
  if view.isNil:
    return
  let mode = if fitting: lsmFitting else: lsmLayout
  for diagnostic in view.xCssLayoutDiagnostics[mode]:
    var copied: CssLayoutDiagnostic
    copied.viewId.add diagnostic.viewId
    copied.property.add diagnostic.property
    copied.message.add diagnostic.message
    result.add copied

proc generatedLayoutInputs*(view: View): seq[LayoutInput] =
  for source in LayoutInputSource:
    for input in view.xLayoutInputCache.generated[source]:
      result.add input

proc releaseGeneratedLayoutInputs*(view: View) =
  ## Drops cached equations and resets their generations throughout a tree.
  if view.isNil:
    return
  view.xLayoutInputCache = LayoutInputCache()
  when defined(merendaPersistentLayout):
    view.xPersistentLayout = default(PersistentLayoutCache)
  for child in view.xSubviews:
    child.releaseGeneratedLayoutInputs()

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
  view.xLayoutInputCache.dirtySources

proc layoutInputGeneration*(view: View): Natural =
  view.xLayoutInputCache.generation

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

proc initLayoutGuide*(owningView: View, insets = insets(0.0)): LayoutGuide =
  LayoutGuide(xOwningView: owningView, xInsets: insets)

proc contentLayoutGuide*(view: View, insets = insets(0.0)): LayoutGuide =
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

proc `+`*(anchor: LayoutXAxisAnchor, constant: LayoutLength): LayoutXAxisAnchor =
  anchor + constant.resolveLayoutLength()

proc `+`*(constant: float32, anchor: LayoutXAxisAnchor): LayoutXAxisAnchor =
  anchor + constant

proc `+`*(constant: LayoutLength, anchor: LayoutXAxisAnchor): LayoutXAxisAnchor =
  anchor + constant

proc `-`*(anchor: LayoutXAxisAnchor, constant: float32): LayoutXAxisAnchor =
  initXAxisAnchor(anchor.xItem, anchor.xAttribute, anchor.xOffset - constant)

proc `-`*(anchor: LayoutXAxisAnchor, constant: LayoutLength): LayoutXAxisAnchor =
  anchor - constant.resolveLayoutLength()

proc `+`*(anchor: LayoutYAxisAnchor, constant: float32): LayoutYAxisAnchor =
  initYAxisAnchor(anchor.xItem, anchor.xAttribute, anchor.xOffset + constant)

proc `+`*(anchor: LayoutYAxisAnchor, constant: LayoutLength): LayoutYAxisAnchor =
  anchor + constant.resolveLayoutLength()

proc `+`*(constant: float32, anchor: LayoutYAxisAnchor): LayoutYAxisAnchor =
  anchor + constant

proc `+`*(constant: LayoutLength, anchor: LayoutYAxisAnchor): LayoutYAxisAnchor =
  anchor + constant

proc `-`*(anchor: LayoutYAxisAnchor, constant: float32): LayoutYAxisAnchor =
  initYAxisAnchor(anchor.xItem, anchor.xAttribute, anchor.xOffset - constant)

proc `-`*(anchor: LayoutYAxisAnchor, constant: LayoutLength): LayoutYAxisAnchor =
  anchor - constant.resolveLayoutLength()

proc `+`*(anchor: LayoutDimensionAnchor, constant: float32): LayoutDimensionAnchor =
  initDimensionAnchor(anchor.xItem, anchor.xAttribute, anchor.xOffset + constant)

proc `+`*(
    anchor: LayoutDimensionAnchor, constant: LayoutLength
): LayoutDimensionAnchor =
  anchor + constant.resolveLayoutLength()

proc `+`*(constant: float32, anchor: LayoutDimensionAnchor): LayoutDimensionAnchor =
  anchor + constant

proc `+`*(
    constant: LayoutLength, anchor: LayoutDimensionAnchor
): LayoutDimensionAnchor =
  anchor + constant

proc `-`*(anchor: LayoutDimensionAnchor, constant: float32): LayoutDimensionAnchor =
  initDimensionAnchor(anchor.xItem, anchor.xAttribute, anchor.xOffset - constant)

proc `-`*(
    anchor: LayoutDimensionAnchor, constant: LayoutLength
): LayoutDimensionAnchor =
  anchor - constant.resolveLayoutLength()

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
    xFirstAttribute: firstAttribute,
    xRelation: relation,
    xSecondAttribute: if secondItem.isNil: atNotAnAttribute else: secondAttribute,
    xMultiplier: multiplier,
    xConstant: constant,
    xPriority: priority,
  )
  result.xFirstItemRef.target = firstItem
  result.xSecondItemRef.target = secondItem

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

# These operators build expressions rather than bools. Nim's automatic >=
# rewrite would swap the anchors or reject a dimension and constant pair.
when (NimMajor, NimMinor) >= (2, 4):
  {.push warning[InvalidCmpOp]: off.}

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

when (NimMajor, NimMinor) >= (2, 4):
  {.pop.}

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

proc greaterThanOrEqualTo*(
    first: LayoutDimensionAnchor, constant: float32, priority = LayoutPriorityRequired
): LayoutConstraint =
  first.constraintWithConstant(lrGreaterThanOrEqual, constant, priority)

proc lessThanOrEqualTo*(
    first: LayoutDimensionAnchor, constant: float32, priority = LayoutPriorityRequired
): LayoutConstraint =
  first.constraintWithConstant(lrLessThanOrEqual, constant, priority)

proc activate*(constraints: openArray[LayoutConstraint])

proc edgeConstraints*(
    view: View,
    toView: View,
    insets = insets(0.0),
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
    insets = insets(0.0),
    edges = AllLayoutEdges,
    priority = LayoutPriorityRequired,
): seq[LayoutConstraint] {.discardable.} =
  result = view.edgeConstraints(
    toView = toView, insets = insets, edges = edges, priority = priority
  )
  activate(result)

proc edgeConstraints*(
    view: View,
    toGuide: LayoutGuide,
    insets = insets(0.0),
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
    insets = insets(0.0),
    edges = AllLayoutEdges,
    priority = LayoutPriorityRequired,
): seq[LayoutConstraint] {.discardable.} =
  result = view.edgeConstraints(
    toGuide = toGuide, insets = insets, edges = edges, priority = priority
  )
  activate(result)

proc xFirstItem*(constraint: LayoutConstraint): View =
  constraint.xFirstItemRef.target

proc xSecondItem*(constraint: LayoutConstraint): View =
  constraint.xSecondItemRef.target

proc xOwningView*(constraint: LayoutConstraint): View =
  constraint.xOwningViewRef.target

proc `xOwningView=`(constraint: LayoutConstraint, view: View) =
  constraint.xOwningViewRef.target = view

proc firstItem*(constraint: LayoutConstraint): View =
  constraint.xFirstItem

proc firstAttribute*(constraint: LayoutConstraint): LayoutAttribute =
  constraint.xFirstAttribute

proc relation*(constraint: LayoutConstraint): LayoutRelation =
  constraint.xRelation

proc secondItem*(constraint: LayoutConstraint): View =
  constraint.xSecondItem

proc secondAttribute*(constraint: LayoutConstraint): LayoutAttribute =
  constraint.xSecondAttribute

proc multiplier*(constraint: LayoutConstraint): float32 =
  constraint.xMultiplier

proc constant*(constraint: LayoutConstraint): float32 =
  constraint.xConstant

proc priority*(constraint: LayoutConstraint): LayoutPriority =
  constraint.xPriority

proc isActive*(constraint: LayoutConstraint): bool =
  constraint.xActive and not constraint.xOwningViewRef.isNil

proc active*(constraint: LayoutConstraint): bool =
  constraint.isActive()

proc owningView*(constraint: LayoutConstraint): View =
  constraint.xOwningView

proc invalidateActiveConstraint(constraint: LayoutConstraint) =
  if not constraint.isActive:
    return
  constraint.xOwningView.markConstraintStorageChanged()

proc `constant=`*(constraint: LayoutConstraint, constant: float32) =
  if constraint.xConstant == constant:
    return
  constraint.xConstant = constant
  constraint.invalidateActiveConstraint()

proc `priority=`*(constraint: LayoutConstraint, priority: LayoutPriority) =
  if constraint.xPriority == priority:
    return
  constraint.xPriority = priority
  constraint.invalidateActiveConstraint()

proc indexOfConstraint(view: View, constraint: LayoutConstraint): int =
  if constraint.isNil:
    return -1
  for index, stored in view.xConstraints:
    if stored == constraint:
      return index
  -1

proc removeStoredConstraint(view: View, constraint: LayoutConstraint) =
  if constraint.isNil:
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
  view.xConstraints

proc addConstraint*(view: View, constraint: LayoutConstraint) =
  if constraint.isNil:
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
      other = other.superviewBacklink()
    candidate = candidate.superviewBacklink()

proc activationOwner(constraint: LayoutConstraint): View =
  if constraint.xFirstItem.isNil:
    return nil
  if constraint.xSecondItem.isNil:
    return constraint.xFirstItem
  let common = constraint.xFirstItem.nearestCommonSuperview(constraint.xSecondItem)
  if common.isNil: constraint.xFirstItem else: common

proc `active=`*(constraint: LayoutConstraint, active: bool) =
  if constraint.isActive == active:
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

proc isPriorityPipe(node: NimNode): bool =
  node.kind == nnkInfix and node[0].eqIdent("|") and node[2].eqIdent("priority")

proc cxCallFromBlockStatement(statement: NimNode): NimNode =
  if statement.kind == nnkAsgn:
    let left = statement[0]
    if left.isPriorityPipe():
      return newCall(
        ident"cx", left[1], newTree(nnkExprEqExpr, ident"priority", statement[1])
      )
    if left.kind == nnkInfix and left.len == 3 and left[2].isPriorityPipe():
      var expression = copyNimTree(left)
      expression[2] = left[2][1]
      return newCall(
        ident"cx", expression, newTree(nnkExprEqExpr, ident"priority", statement[1])
      )
  newCall(ident"cx", statement)

macro activateConstraints*(constraints: varargs[untyped]): untyped =
  result = newCall(ident"activate")
  if constraints.len == 1 and constraints[0].kind == nnkStmtList:
    for statement in constraints[0]:
      if statement.kind != nnkEmpty:
        result.add statement.cxCallFromBlockStatement()
  else:
    for constraint in constraints:
      result.add constraint

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

proc elapsedMilliseconds(state: LayoutSolveState): Natural =
  Natural(max(0, int((getMonoTime() - state.startedAt).inMilliseconds)))

func saturatingAdd(left, right: int64): int64 =
  ## Add non-negative counters without allowing integer wraparound.
  if left > high(int64) - right:
    return high(int64)
  left + right

func saturatingMultiply(left, right: int64): int64 =
  if left <= 0 or right <= 0:
    return 0
  if left > high(int64) div right:
    return high(int64)
  left * right

func estimatedMemoryBytes(state: LayoutSolveState): Natural =
  ## Estimate the temporary solver working set from admitted sparse inputs.
  ## This is an admission heuristic rather than an allocator measurement.
  ## Reserve substantial headroom for row expansion without assuming that
  ## every tableau row contains every symbol.
  let
    itemBytes = saturatingMultiply(int64(state.items.len), 512)
    constraintBytes = saturatingMultiply(int64(state.constraintCount), 512)
    inputCoefficientBytes = saturatingMultiply(int64(state.coefficientCount), 64)
    expandedCoefficientBytes = saturatingMultiply(inputCoefficientBytes, 8)
    estimate =
      saturatingAdd(saturatingAdd(itemBytes, constraintBytes), expandedCoefficientBytes)
  Natural(min(estimate, int64(high(Natural))))

proc solveDiagnostic(state: LayoutSolveState, limit = lslNone): LayoutSolveDiagnostic =
  LayoutSolveDiagnostic(
    failed: limit != lslNone,
    limit: limit,
    views: Natural(state.items.len),
    constraints: state.workConstraintCount,
    coefficients: state.workCoefficientCount,
    estimatedMemoryBytes: state.estimatedMemoryBytes(),
    elapsedMilliseconds: state.elapsedMilliseconds(),
  )

proc raiseBudgetExceeded(
    state: LayoutSolveState, limit: LayoutSolveLimitKind
) {.noreturn.} =
  let diagnostic = state.solveDiagnostic(limit)
  var error = newException(LayoutSolveBudgetExceeded, "layout solver budget exceeded")
  error.diagnostic = diagnostic
  raise error

proc checkSolveBudget(state: LayoutSolveState) =
  if state.limits.maxViews > 0 and state.items.len > state.limits.maxViews:
    state.raiseBudgetExceeded(lslViews)
  if state.limits.maxConstraints > 0 and
      state.workConstraintCount > state.limits.maxConstraints:
    state.raiseBudgetExceeded(lslConstraints)
  if state.limits.maxCoefficients > 0 and
      state.workCoefficientCount > state.limits.maxCoefficients:
    state.raiseBudgetExceeded(lslCoefficients)
  if state.limits.maxMemoryBytes > 0 and
      state.estimatedMemoryBytes() > state.limits.maxMemoryBytes:
    state.raiseBudgetExceeded(lslMemory)
  if state.limits.maxMilliseconds > 0 and
      state.elapsedMilliseconds() >= state.limits.maxMilliseconds:
    state.raiseBudgetExceeded(lslTime)

proc initLayoutSolveState(
    limits: LayoutSolveLimits, mode: LayoutSolveMode
): LayoutSolveState =
  result = LayoutSolveState(
    solver: initSolver(),
    itemIndexes: initTable[pointer, int](),
    variableItems: initTable[VariableId, int](),
    pinnedVariables: initTable[VariableId, int](),
    constraintItemIndexes: initHashSet[pointer](),
    keepsContainerFrames: mode == lsmLayout,
    pinComponent: -1,
    limits: limits,
    startedAt: getMonoTime(),
  )

proc solverViewName(index: int, suffix: string): string =
  "v" & $index & "." & suffix

proc ensureSolverView(state: var LayoutSolveState, item: View): int =
  let key = cast[pointer](item)
  if state.itemIndexes.hasKey(key):
    return state.itemIndexes[key]

  let index = state.items.len
  state.items.add SolverView(
    item: item,
    left: newVariable(index.solverViewName("left")),
    top: newVariable(index.solverViewName("top")),
    width: newVariable(index.solverViewName("width")),
    height: newVariable(index.solverViewName("height")),
  )
  state.itemIndexes[key] = index
  let solverView = state.items[index]
  for variable in [solverView.left, solverView.top, solverView.width, solverView.height]:
    state.variableItems[variable.variableId] = index
  state.checkSolveBudget()
  index

proc solverView(state: var LayoutSolveState, item: View): SolverView =
  state.items[state.ensureSolverView(item)]

proc hasSolverView(state: LayoutSolveState, item: View): bool =
  not item.isNil and state.itemIndexes.hasKey(cast[pointer](item))

proc addConstraintItem(state: var LayoutSolveState, item: View) =
  if item.isNil or not state.hasSolverView(item):
    return
  let key = cast[pointer](item)
  if key in state.constraintItemIndexes:
    return
  state.constraintItemIndexes.incl key

proc hasConstraintItem(state: LayoutSolveState, item: View): bool =
  not item.isNil and cast[pointer](item) in state.constraintItemIndexes

when defined(merendaPersistentLayout):
  proc supportsPersistentTree(state: LayoutSolveState, item: View): bool =
    # CSS admission can reject inputs and retry with a different graph, so a
    # retained tableau cannot be matched to it. Intrinsic, container and
    # authored inputs are regenerated and compared on every reuse.
    state.checkSolveBudget()
    if item.effectiveAppearance().theme.hasLayoutRules:
      return false
    for child in item.xSubviews:
      if not state.supportsPersistentTree(child):
        return false
    true

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
    state.checkSolveBudget()
    if not constraint.isNil and constraint.xActive:
      state.addConstraintItem(constraint.xFirstItem)
      state.addConstraintItem(constraint.xSecondItem)
  for child in owner.xSubviews:
    state.checkSolveBudget()
    state.collectConstraintItems(child)

proc addSolverConstraint(
  state: var LayoutSolveState, constraint: Constraint, priority = LayoutPriorityRequired
)

proc addStay(
    state: var LayoutSolveState, variable: Variable, value: float32, strength: Strength
) =
  state.addSolverConstraint(eq(variable, value.solverValue).withStrength(strength))

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

proc constraintExpressionFor(
    state: var LayoutSolveState, item: View, attribute: LayoutAttribute
): Expression =
  # Solver geometry remains local to each superview. Authored positional
  # constraints need a shared coordinate space when they cross that boundary.
  result = state.solverView(item).expressionFor(attribute)

  case attribute
  of atLeft, atRight, atLeading, atTrailing, atCenterX:
    var ancestor = item.superviewBacklink()
    while not ancestor.isNil and state.hasSolverView(ancestor):
      state.checkSolveBudget()
      let ancestorView = state.solverView(ancestor)
      result =
        result + ancestorView.left -
        (ancestor.xAlignmentInsets.left + ancestor.xBounds.origin.x).solverValue
      ancestor = ancestor.superviewBacklink()
  of atTop, atBottom, atCenterY, atFirstBaseline, atLastBaseline:
    var ancestor = item.superviewBacklink()
    while not ancestor.isNil and state.hasSolverView(ancestor):
      state.checkSolveBudget()
      let
        ancestorView = state.solverView(ancestor)
        frameTop = ancestorView.top - ancestor.xAlignmentInsets.top.solverValue
      if vipFlipped in ancestor.xPrivProps:
        result = result + frameTop - ancestor.xBounds.origin.y.solverValue
      else:
        result = frameTop + ancestor.xBounds.maxY.solverValue - result
      ancestor = ancestor.superviewBacklink()
  of atWidth, atHeight, atNotAnAttribute:
    discard

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

proc accountConstraints(
    state: var LayoutSolveState, constraints, coefficients: Natural
) =
  state.constraintCount += constraints
  state.workConstraintCount += constraints
  state.coefficientCount = Natural(
    min(
      int64(high(Natural)),
      saturatingAdd(int64(state.coefficientCount), int64(coefficients)),
    )
  )
  state.workCoefficientCount = Natural(
    min(
      int64(high(Natural)),
      saturatingAdd(int64(state.workCoefficientCount), int64(coefficients)),
    )
  )
  state.checkSolveBudget()

proc accountSolverConstraint(state: var LayoutSolveState, constraint: Constraint) =
  state.accountConstraints(1, Natural(constraint.expression.len))

proc defersInsertion(state: LayoutSolveState): bool =
  ## Constraints wait until the graph is partitioned, except when a single
  ## persistent tableau must record or capture them in order.
  when defined(merendaPersistentLayout):
    not (state.captureConstraints or state.recordOnly)
  else:
    true

proc solverItem(state: LayoutSolveState, variable: Variable): int =
  ## The solver view owning `variable`, or -1 for a pinned root variable.
  ## Pins precede every other constraint, so a pinned variable is a constant
  ## that cannot connect otherwise independent groups.
  if state.pinnedVariables.hasKey(variable.variableId):
    return -1
  state.variableItems.getOrDefault(variable.variableId, -1)

proc addComponent(state: var LayoutSolveState): int =
  result = state.components.len
  state.components.add initSolver()
  state.componentPins.add {}

proc constraintComponent(state: var LayoutSolveState, constraint: Constraint): int =
  ## The partition owning `constraint`, or -1 when it only bounds a view that
  ## keeps its current geometry. Partitions never split a constraint's terms.
  for term in constraint.expression:
    let item = state.solverItem(term.variable)
    if item >= 0:
      return
        if item < state.itemComponents.len:
          state.itemComponents[item]
        else:
          -1
  # Only pinned or no variables: the pins alone decide whether it is satisfiable.
  if state.pinComponent < 0:
    state.pinComponent = state.addComponent()
  state.pinComponent

proc addReferencedPins(
    state: var LayoutSolveState, component: int, constraint: Constraint
) =
  for term in constraint.expression:
    let pin = state.pinnedVariables.getOrDefault(term.variable.variableId, -1)
    if pin >= 0 and uint8(pin) notin state.componentPins[component]:
      state.componentPins[component].incl uint8(pin)
      state.components[component].addConstraint(state.pins[pin])

proc insertSolverConstraint(state: var LayoutSolveState, constraint: Constraint): bool =
  ## Adds `constraint` to its solver and reports whether it was satisfiable.
  profileViewPhase(vppConstraintInsertion)
  try:
    if state.partitioned:
      let component = state.constraintComponent(constraint)
      if component >= 0:
        state.addReferencedPins(component, constraint)
        state.components[component].addConstraint(constraint)
    else:
      state.solver.addConstraint(constraint)
    state.checkSolveBudget()
    true
  except UnsatisfiableConstraintError:
    false

proc keepsCurrentGeometry(state: LayoutSolveState, index: int): bool =
  ## Views outside every solver keep their current geometry: a view constrained
  ## only by non-negative sizes, or a layout root fixed by its pins.
  state.partitioned and index < state.itemComponents.len and
    state.itemComponents[index] < 0

proc rootItem(parents: var seq[int], index: int): int =
  result = index
  while parents[result] != result:
    parents[result] = parents[parents[result]]
    result = parents[result]

proc linkTerms(
    state: LayoutSolveState,
    parents: var seq[int],
    needsSolver: var seq[bool],
    constraint: Constraint,
) =
  var first = -1
  for term in constraint.expression:
    let item = state.solverItem(term.variable)
    if item < 0:
      continue
    needsSolver[item] = true
    if first < 0:
      first = parents.rootItem(item)
    else:
      let other = parents.rootItem(item)
      if other != first:
        parents[other] = first

proc partitionConstraints(state: var LayoutSolveState, extra: openArray[Constraint]) =
  ## Kiwi substitutes every new row into every existing row, so one tableau
  ## grows quadratically with the tree. Views that share no constraint are
  ## independent problems; solve each connected group separately.
  if not state.defersInsertion() or state.partitioned:
    return
  var
    parents = newSeq[int](state.items.len)
    needsSolver = newSeq[bool](state.items.len)
  for index in 0 ..< parents.len:
    parents[index] = index
  for queued in state.queued:
    state.checkSolveBudget()
    if not queued.nonNegative:
      state.linkTerms(parents, needsSolver, queued.constraint)
  for constraint in extra:
    state.linkTerms(parents, needsSolver, constraint)

  for index in 0 ..< parents.len:
    if needsSolver[index]:
      needsSolver[parents.rootItem(index)] = true
  var rootComponents = newSeq[int](parents.len)
  for index in 0 ..< rootComponents.len:
    rootComponents[index] = -1
  state.itemComponents = newSeq[int](parents.len)
  for index in 0 ..< parents.len:
    let root = parents.rootItem(index)
    if not needsSolver[root]:
      state.itemComponents[index] = -1
      continue
    if rootComponents[root] < 0:
      rootComponents[root] = state.addComponent()
    state.itemComponents[index] = rootComponents[root]

  state.partitioned = true
  let queued = move state.queued
  for entry in queued:
    discard state.insertSolverConstraint(entry.constraint)

proc updateSolvedVariables(state: var LayoutSolveState) =
  profileViewPhase(vppSolverUpdate)
  if state.partitioned:
    for component in state.components.mitems:
      component.updateVariables()
  else:
    state.solver.updateVariables()

proc queueSolverConstraint(
    state: var LayoutSolveState, constraint: Constraint, nonNegative: bool
) =
  if state.partitioned:
    discard state.insertSolverConstraint(constraint)
  else:
    state.queued.add QueuedConstraint(constraint: constraint, nonNegative: nonNegative)

proc addSolverConstraint(
    state: var LayoutSolveState,
    constraint: Constraint,
    priority = LayoutPriorityRequired,
) =
  when defined(merendaPersistentLayout):
    if state.recordOnly:
      state.accountSolverConstraint(constraint)
      state.capturedConstraints.add constraint.strengthened(priority)
      return
  state.accountSolverConstraint(constraint)
  let admitted = constraint.strengthened(priority)
  if state.defersInsertion():
    state.queueSolverConstraint(admitted, nonNegative = false)
    return
  if not state.insertSolverConstraint(admitted):
    when defined(merendaPersistentLayout):
      state.captureFailed = true
    return
  when defined(merendaPersistentLayout):
    if state.captureConstraints:
      state.capturedConstraints.add admitted

proc addGeometryStays(state: var LayoutSolveState, root: View) =
  profileViewPhase(vppConstraintConstruction)
  for index, solverView in state.items:
    state.checkSolveBudget()
    if solverView.item == root:
      continue
    if state.keepsCurrentGeometry(index):
      # Each omitted stay is one single-term constraint. Count them so the
      # budget does not depend on which views needed a solver.
      state.accountConstraints(4, 4)
    else:
      let rect = solverView.item.alignmentRect()
      state.addStay(solverView.width, rect.size.width, Weak)
      state.addStay(solverView.height, rect.size.height, Weak)
      state.addStay(solverView.left, rect.minX, Weak)
      state.addStay(solverView.top, rect.minY, Weak)

proc addRootPin(state: var LayoutSolveState, variable: Variable, value: float32) =
  ## Required root geometry, added before any other constraint.
  let constraint = eq(variable, value.solverValue)
  if not state.defersInsertion():
    state.addSolverConstraint(constraint)
    return
  state.accountSolverConstraint(constraint)
  state.pinnedVariables[variable.variableId] = state.pins.len
  state.pins.add constraint

proc addRootGeometryConstraints(state: var LayoutSolveState, root: View) =
  profileViewPhase(vppConstraintConstruction)
  if root.isNil:
    return
  let
    solverView = state.solverView(root)
    rect = root.alignmentRect()
  state.addRootPin(solverView.left, rect.minX)
  state.addRootPin(solverView.top, rect.minY)
  state.addRootPin(solverView.width, rect.size.width)
  state.addRootPin(solverView.height, rect.size.height)

proc addRootFittingConstraints(state: var LayoutSolveState, root: View) =
  profileViewPhase(vppConstraintConstruction)
  if root.isNil:
    return
  let
    solverView = state.solverView(root)
    rect = root.alignmentRect()
  state.addRootPin(solverView.left, rect.minX)
  state.addRootPin(solverView.top, rect.minY)
  state.addStay(solverView.width, 0.0'f32, Weak)
  state.addStay(solverView.height, 0.0'f32, Weak)

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

proc keepsContainerFrame(state: LayoutSolveState, item: View): bool =
  ## A container assigns this view's frame after the solve, so sizing it to its
  ## intrinsic content would only be overwritten, every transaction.
  state.keepsContainerFrames and not item.isNil and
    vipContainerOwnedFrame in item.xPrivProps and not state.hasConstraintItem(item) and
    cast[pointer](item) notin state.cssTargets

proc addLayoutEquation(state: var LayoutSolveState, equation: LayoutEquation) =
  if equation.terms.len == 0:
    return
  if equation.source == lisIntrinsic and
      state.keepsContainerFrame(equation.terms[0].item):
    return
  for term in equation.terms:
    state.checkSolveBudget()
    if term.item.isNil or not state.hasSolverView(term.item):
      return

  var left = toExpression(0.KiwiScalar)
  for term in equation.terms:
    state.checkSolveBudget()
    left = left + state.expressionFor(term)
  state.addRelation(
    left,
    toExpression(equation.constant.solverValue),
    equation.relation,
    equation.priority,
  )

proc addGeneratedEquation(state: var LayoutSolveState, equation: LayoutEquation) =
  state.generatedInputs.add equation.layoutEquationInput()
  state.checkSolveBudget()

proc addNonNegativeSizeConstraints(state: var LayoutSolveState) =
  profileViewPhase(vppConstraintConstruction)
  for solverView in state.items:
    for variable in [solverView.width, solverView.height]:
      let constraint = ge(variable, 0)
      if not state.defersInsertion():
        state.addSolverConstraint(constraint)
        continue
      state.accountSolverConstraint(constraint)
      state.queueSolverConstraint(constraint, nonNegative = true)

proc addIntrinsicConstraints(state: var LayoutSolveState, item: View) =
  if item.isNil:
    return
  state.checkSolveBudget()

  if vipAutoresizingMaskConstraints notin item.xPrivProps or
      state.hasConstraintItem(item):
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
    state.checkSolveBudget()
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
    state.checkSolveBudget()
    if vipAutoresizingMaskConstraints in child.xPrivProps and
        not state.hasConstraintItem(child):
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
    state.constraintExpressionFor(constraint.xFirstItem, constraint.xFirstAttribute)
  let right =
    if constraint.xSecondItem.isNil:
      toExpression(constraint.xConstant.solverValue)
    else:
      state.constraintExpressionFor(constraint.xSecondItem, constraint.xSecondAttribute) *
        constraint.xMultiplier.solverValue + constraint.xConstant.solverValue

  state.addRelation(left, right, constraint.xRelation, constraint.xPriority)

proc addLayoutInput(state: var LayoutSolveState, input: LayoutInput) =
  profileViewPhase(vppConstraintConstruction)
  case input.kind
  of likConstraint:
    state.addLayoutConstraint(input.constraint)
  of likEquation:
    state.addLayoutEquation(input.equation)

proc addLayoutInputs(state: var LayoutSolveState, inputs: openArray[LayoutInput]) =
  for input in inputs:
    state.checkSolveBudget()
    state.addLayoutInput(input)

proc addOwnedConstraints(state: var LayoutSolveState, owner: View) =
  if owner.isNil:
    return
  for constraint in owner.xConstraints:
    state.checkSolveBudget()
    state.addLayoutInput(constraint.layoutConstraintInput())
  for child in owner.xSubviews:
    state.checkSolveBudget()
    state.addOwnedConstraints(child)

proc cssDiagnostic(state: var LayoutSolveState, view: View, property, message: string) =
  let id = if view.xStyleId.len > 0: view.xStyleId else: view.xIdentifier
  let diagnostic = CssLayoutDiagnostic(viewId: id, property: property, message: message)
  if diagnostic notin state.cssDiagnostics:
    state.cssDiagnostics.add diagnostic

iterator superviewChain(view: View): View =
  var parent = view.superviewBacklink()
  while not parent.isNil:
    yield parent
    parent = parent.superviewBacklink()

proc managedBySuperview(view: View): bool =
  view.superviewChain().findFirst(managesSubviewLayout(), DynamicAgent(view)).isSome

proc checkCssGenerationBudget(state: LayoutSolveState, additional: Natural) =
  state.checkSolveBudget()
  let
    count = saturatingAdd(int64(state.cssInputs.len), int64(additional))
    constraints = saturatingAdd(int64(state.workConstraintCount), count)
    coefficients =
      saturatingAdd(int64(state.workCoefficientCount), saturatingMultiply(count, 2))
    memory = saturatingAdd(
      int64(state.estimatedMemoryBytes()), saturatingMultiply(count, 1536)
    )
  if state.limits.maxConstraints > 0 and constraints > int64(
    state.limits.maxConstraints
  ):
    state.raiseBudgetExceeded(lslConstraints)
  if state.limits.maxCoefficients > 0 and
      coefficients > int64(state.limits.maxCoefficients):
    state.raiseBudgetExceeded(lslCoefficients)
  if state.limits.maxMemoryBytes > 0 and memory > int64(state.limits.maxMemoryBytes):
    state.raiseBudgetExceeded(lslMemory)

proc cssTarget(
    state: var LayoutSolveState,
    subject: View,
    spec: StyleLayoutConstraint,
    property: string,
    target: var View,
): bool =
  case spec.target
  of sltConstant:
    return true
  of sltSelf:
    target = subject
  of sltParent:
    target = subject.superviewBacklink()
  of sltSibling:
    let parent = subject.superviewBacklink()
    if not parent.isNil:
      for child in parent.xSubviews:
        state.checkSolveBudget()
        if child.xStyleId == spec.targetId:
          if not target.isNil:
            state.cssDiagnostic(
              subject, property, "Duplicate sibling style id #" & spec.targetId
            )
            return
          target = child
  if target.isNil or not state.hasSolverView(target):
    state.cssDiagnostic(
      subject, property,
      "Constraint target is missing or outside this solve tree; use parent, self, or a unique sibling #id",
    )
    return
  if target != subject and target.managedBySuperview():
    state.cssDiagnostic(
      subject, property,
      "Constraint target is managed by its container and moves after the constraint solve",
    )
    return
  true

proc prepareCssProperty(
    state: var LayoutSolveState,
    root, subject: View,
    mode: LayoutSolveMode,
    theme: Theme,
    context: StyleContext,
    key: StyleKey[seq[StyleLayoutConstraint]],
    property: string,
) =
  let statePointer = addr state
  let checkWork = proc() =
    statePointer[].checkSolveBudget()
  let selection = theme.layoutStyleSelection(context, key, checkWork)
  let count = selection.constraintCount
  state.checkCssGenerationBudget(count)
  if count == 0:
    return
  if subject == root and mode == lsmLayout:
    state.cssDiagnostic(
      subject, property, "The solve root keeps its native frame; style a child view"
    )
    return
  if subject != root and subject.managedBySuperview():
    state.cssDiagnostic(
      subject, property,
      "This subview is arranged by its container; style the container layout instead",
    )
    return
  for spec in selection.resolveLayoutConstraints(checkWork):
    state.checkSolveBudget()
    if not spec.validStyleConstraint():
      state.cssDiagnostic(subject, property, "Invalid native constraint specification")
    elif subject == root and spec.attribute notin {atWidth, atHeight}:
      state.cssDiagnostic(
        subject, property, "A fitting root can style its dimensions, not its position"
      )
    else:
      var target: View
      if state.cssTarget(subject, spec, property, target):
        var terms = @[initLayoutTerm(subject, spec.attribute)]
        if not target.isNil:
          terms.add initLayoutTerm(target, spec.targetAttribute, -spec.multiplier)
          state.cssTargets.incl cast[pointer](target)
        var equation =
          initLayoutEquation(terms, spec.relation, spec.constant, spec.priority, lisCss)
        equation.cssProperty = property
        state.cssInputs.add equation.layoutEquationInput()
        state.cssSubjects.incl cast[pointer](subject)

proc prepareCssInputs(
    state: var LayoutSolveState,
    root: View,
    mode: LayoutSolveMode,
    excluded: HashSet[pointer],
) =
  profileViewPhase(vppConstraintGeneration)
  for solverView in state.items:
    state.checkSolveBudget()
    let subject = solverView.item
    let theme = subject.effectiveAppearance().theme
    if theme.hasLayoutRules and cast[pointer](subject) notin excluded:
      state.didResolveCss = true
      let context = subject.resolvedLayoutStyleContext()
      for property in CssGeometryProperties:
        state.prepareCssProperty(
          root,
          subject,
          mode,
          theme,
          context,
          StyleKey[seq[StyleLayoutConstraint]](property.key),
          property.name,
        )
      state.prepareCssProperty(
        root, subject, mode, theme, context, StyleLayoutConstraints,
        "-nimkit-constraints",
      )
  for key in state.cssSubjects:
    state.constraintItemIndexes.incl key

proc admitCssInputs(state: var LayoutSolveState): HashSet[pointer] =
  profileViewPhase(vppConstraintConstruction)
  var constraints: seq[Constraint]
  for input in state.cssInputs:
    state.checkSolveBudget()
    let equation = input.equation
    var expression = toExpression(0.KiwiScalar)
    for term in equation.terms:
      state.checkSolveBudget()
      expression =
        expression +
        state.constraintExpressionFor(term.item, term.attribute) *
        term.multiplier.solverValue
    let right = toExpression(equation.constant.solverValue)
    let constraint =
      case equation.relation
      of lrEqual:
        eq(expression, right)
      of lrLessThanOrEqual:
        le(expression, right)
      of lrGreaterThanOrEqual:
        ge(expression, right)
    state.accountSolverConstraint(constraint)
    constraints.add constraint.strengthened(equation.priority)

  state.partitionConstraints(constraints)
  var admitted: seq[LayoutInput]
  for index, input in state.cssInputs:
    let equation = input.equation
    if state.insertSolverConstraint(constraints[index]):
      result.incl cast[pointer](equation.terms[0].item)
      admitted.add input
    else:
      state.cssDiagnostic(
        equation.terms[0].item,
        equation.cssProperty,
        "Required constraint conflicts with native geometry or an earlier CSS constraint",
      )
  state.cssInputs = move admitted

proc solvedFloat(variable: Variable): float32 =
  float32(variable.value)

type SolvedFrame = object
  item: View
  frame: Rect

proc requireFiniteCssGeometry(
    state: var LayoutSolveState, view: View, values: openArray[float32]
) =
  if state.didResolveCss:
    for value in values:
      if value.classify in {fcNan, fcInf, fcNegInf}:
        state.cssDiagnostic(
          view, "-nimkit-constraints",
          "CSS geometry exceeded the finite coordinate range; reduce lengths or multipliers",
        )
        raise newException(CssLayoutGeometryError, "Nonfinite CSS geometry")

proc solvedAlignmentRect(state: LayoutSolveState, index: int): Rect =
  let solverView = state.items[index]
  if state.keepsCurrentGeometry(index):
    return solverView.item.alignmentRect()
  rect(
    solverView.left.solvedFloat(),
    solverView.top.solvedFloat(),
    solverView.width.solvedFloat(),
    solverView.height.solvedFloat(),
  )

proc solvedFrames(state: var LayoutSolveState): seq[SolvedFrame] =
  result = newSeqOfCap[SolvedFrame](state.items.len)
  for index, solverView in state.items:
    state.checkSolveBudget()
    if not solverView.item.isNil:
      let solved = state.solvedAlignmentRect(index)
      state.requireFiniteCssGeometry(
        solverView.item, [solved.size.width, solved.size.height]
      )
      let alignmentRect = rect(
        solved.minX,
        solved.minY,
        max(solved.size.width, 0.0'f32),
        max(solved.size.height, 0.0'f32),
      )
      let frame = solverView.item.frameForAlignmentRect(alignmentRect)
      state.requireFiniteCssGeometry(
        solverView.item,
        [
          frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
          frame.maxX, frame.maxY,
        ],
      )
      result.add SolvedFrame(item: solverView.item, frame: frame)

proc applySolvedFrames(frames: openArray[SolvedFrame]): seq[View] =
  profileViewPhase(vppFrameApplication)
  for solved in frames:
    if solved.item.xFrame != solved.frame:
      result.add solved.item
    solved.item.applyLayoutFrame(solved.frame, lfoSolver)

proc refreshAutoresizingStates(state: LayoutSolveState) =
  for solverView in state.items:
    if not solverView.item.isNil and
        vipAutoresizingMaskConstraints in solverView.item.xPrivProps:
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
  profileViewPhase(vppConstraintGeneration)
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
  of lisCss:
    discard

  if state.generatedInputs.len > start:
    result = state.generatedInputs[start ..< state.generatedInputs.len]
    state.generatedInputs.setLen(start)

proc refreshGeneratedLayoutInputs(
    state: var LayoutSolveState, root: View, rebuildStyledInputs = false
) =
  if root.isNil:
    return

  var sources = root.generatedSourcesToRebuild()
  if rebuildStyledInputs:
    sources.incl lisAutoresizingMask
    sources.incl lisIntrinsic
  for source in sources:
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

proc solveBlocked*(view: View, mode: LayoutSolveMode): bool =
  let failure = view.xLayoutSolveFailures[mode]
  failure.blocked and failure.limits == view.xLayoutSolveLimits and
    failure.inputRevision == view.xLayoutInputRevision

proc clearSolveFailure(view: View, mode: LayoutSolveMode) =
  view.xLayoutSolveFailures[mode] = LayoutSolveFailure()

proc recordSolveFailure(view: View, mode: LayoutSolveMode) =
  view.xLayoutSolveFailures[mode] = LayoutSolveFailure(
    blocked: true,
    limits: view.xLayoutSolveLimits,
    inputRevision: view.xLayoutInputRevision,
  )

proc needsConstraintSolve(view: View): bool =
  let cache = view.xLayoutInputCache
  cache.generation == 0 or cache.structureDirty or cache.aggregateStructureDirty or
    cache.dirtySources != {} or cache.aggregateDirtySources != {}

proc buildAndSolveConstraints(
    state: var LayoutSolveState, view: View, mode: LayoutSolveMode
) =
  profileViewPhase(vppSolve)
  defer:
    recordSolverSize(state.items.len, state.constraintCount)
  let
    startedAt = state.startedAt
    previousCache = view.xLayoutInputCache
    previousCss = previousCache.generated[lisCss].len > 0
  var
    excluded = initHashSet[pointer]()
    diagnostics: seq[CssLayoutDiagnostic]
    constraintCount: Natural
    coefficientCount: Natural
    hadCss = previousCss or view.effectiveAppearance().theme.hasLayoutRules
  when defined(merendaPersistentLayout):
    let capturePersistent =
      mode == lsmLayout and vpPersistentLayout in view.xProps and
      not activeLayoutTransaction.isNil and activeLayoutTransaction[].root == view and
      activeLayoutTransaction[].phase == ltpSolvingConstraints and not previousCss and
      state.supportsPersistentTree(view)
  while true:
    view.xLayoutInputCache = previousCache
    state = initLayoutSolveState(view.xLayoutSolveLimits, mode)
    when defined(merendaPersistentLayout):
      state.captureConstraints = capturePersistent
    state.startedAt = startedAt
    state.workConstraintCount = constraintCount
    state.workCoefficientCount = coefficientCount
    state.didResolveCss = hadCss
    state.cssDiagnostics = diagnostics
    state.collectSolverViews(view)
    state.collectConstraintItems(view)
    state.prepareCssInputs(view, mode, excluded)
    case mode
    of lsmLayout:
      state.addRootGeometryConstraints(view)
    of lsmFitting:
      state.addConstraintItem(view)
      state.addRootFittingConstraints(view)
    state.addOwnedConstraints(view)
    state.refreshGeneratedLayoutInputs(
      view, rebuildStyledInputs = state.cssInputs.len > 0 or previousCss
    )
    state.addNonNegativeSizeConstraints()
    let admitted = state.admitCssInputs()
    for diagnostic in state.cssDiagnostics:
      if diagnostic notin diagnostics:
        diagnostics.add diagnostic
    let rejected = state.cssSubjects - admitted
    if rejected.len == 0:
      break
    excluded = excluded + rejected
    hadCss = state.didResolveCss
    constraintCount = state.workConstraintCount
    coefficientCount = state.workCoefficientCount
    state.checkSolveBudget()
  state.cssDiagnostics = move diagnostics
  view.xLayoutInputCache.generated[lisCss] = state.cssInputs
  state.addGeometryStays(view)
  state.checkSolveBudget()
  state.updateSolvedVariables()
  state.checkSolveBudget()

when defined(merendaPersistentLayout):
  proc collectPersistentViews(
      state: var LayoutSolveState,
      items: seq[PersistentSolverView],
      item: View,
      index: var int,
  ): bool =
    if index >= items.len or items[index].item{} != item:
      return false
    let saved = items[index]
    state.itemIndexes[cast[pointer](item)] = state.items.len
    state.items.add SolverView(
      item: item,
      left: saved.left,
      top: saved.top,
      width: saved.width,
      height: saved.height,
    )
    inc index
    state.checkSolveBudget()
    for child in item.xSubviews:
      if not state.collectPersistentViews(items, child, index):
        return false
    true

  proc savePersistentLayout(view: View, state: var LayoutSolveState) =
    var cache =
      PersistentLayoutCache(valid: true, constraints: move state.capturedConstraints)
    for solverView in state.items:
      var saved = PersistentSolverView(
        left: solverView.left,
        top: solverView.top,
        width: solverView.width,
        height: solverView.height,
      )
      saved.item.target = solverView.item
      cache.items.add move saved
    cache.solver = move state.solver
    view.xPersistentLayout = move cache
    recordPersistentBuild()

  proc tryPersistentLayout(
      view: View, startedAt: MonoTime, changedFrames: var seq[View]
  ): bool =
    if not view.xPersistentLayout.valid or vpPersistentLayout notin view.xProps or
        activeLayoutTransaction.isNil or activeLayoutTransaction[].root != view or
        activeLayoutTransaction[].phase != ltpSolvingConstraints:
      return false
    profileViewPhase(vppSolve)
    let
      previousCache = view.xLayoutInputCache
      previousRevision = view.xLayoutInputRevision
    var cache = move view.xPersistentLayout
    defer:
      if not result:
        # An update may already have changed Kiwi's tableau. Discard it and
        # rebuild every source before the existing fresh solve is attempted.
        view.xPersistentLayout = default(PersistentLayoutCache)
        view.xLayoutInputCache = previousCache
        view.xLayoutInputCache.structureDirty = true
        recordPersistentFallback()

    var state = initLayoutSolveState(view.xLayoutSolveLimits, lsmLayout)
    state.startedAt = startedAt
    try:
      if not state.supportsPersistentTree(view) or
          view.xLayoutInputCache.generated[lisCss].len > 0:
        return false
      var index = 0
      if not state.collectPersistentViews(cache.items, view, index) or
          index != cache.items.len:
        return false
      state.recordOnly = true
      state.collectConstraintItems(view)
      state.addRootGeometryConstraints(view)
      state.addOwnedConstraints(view)
      state.refreshGeneratedLayoutInputs(view)
      state.addNonNegativeSizeConstraints()
      state.addGeometryStays(view)
      if view.xLayoutInputRevision != previousRevision or
          state.capturedConstraints.len != cache.constraints.len:
        return false

      state.recordOnly = false
      state.solver = move cache.solver
      for i in 0 ..< state.capturedConstraints.len:
        state.checkSolveBudget()
        if not state.capturedConstraints[i].sameShape(cache.constraints[i]):
          block:
            profileViewPhase(vppConstraintInsertion)
            state.solver.removeConstraint(cache.constraints[i])
            state.solver.addConstraint(state.capturedConstraints[i])
          cache.constraints[i] = state.capturedConstraints[i]
          state.checkSolveBudget()
      block:
        profileViewPhase(vppSolverUpdate)
        state.solver.updateVariables()
      state.checkSolveBudget()
      let frames = state.solvedFrames()
      state.checkSolveBudget()
      changedFrames = applySolvedFrames(frames)
      state.refreshAutoresizingStates()
      state.refreshLayoutInputCaches(view)
      view.clearSolveFailure(lsmLayout)
      view.xLastLayoutSolveDiagnostic = LayoutSolveDiagnostic()
      view.xCssLayoutDiagnostics[lsmLayout] = @[]
      cache.solver = move state.solver
      view.xPersistentLayout = move cache
      recordSolverSize(state.items.len, state.constraintCount)
      recordPersistentReuse()
      return true
    except CatchableError:
      # Includes conflicts, invalid values, and cooperative budget failures.
      # The fresh path owns diagnostics and never sees the mutated tableau.
      return false

proc applyConstraintsForSubtree*(view: View): bool =
  if view.isNil:
    return true
  if view.solveBlocked(lsmLayout):
    return false
  if not view.needsConstraintSolve():
    return true

  var changedFrames: seq[View]
  defer:
    # Notify after the frames and solver caches have settled. The ordinary
    # geometry signal also drives autoresizing input invalidation.
    for item in changedFrames:
      emit item.solvedFrameDidChange()

  when defined(merendaPersistentLayout):
    let attemptStarted = getMonoTime()
    if view.tryPersistentLayout(attemptStarted, changedFrames):
      return true

  let previousCache = view.xLayoutInputCache
  when defined(merendaPersistentLayout):
    let inputRevision = view.xLayoutInputRevision
  var state = initLayoutSolveState(view.xLayoutSolveLimits, lsmLayout)
  when defined(merendaPersistentLayout):
    state.startedAt = attemptStarted
  try:
    state.buildAndSolveConstraints(view, lsmLayout)
    let frames = state.solvedFrames()
    state.checkSolveBudget()
    changedFrames = applySolvedFrames(frames)
    state.refreshAutoresizingStates()
    state.refreshLayoutInputCaches(view)
    when defined(merendaPersistentLayout):
      if state.captureConstraints and not state.captureFailed and
          view.xLayoutInputRevision == inputRevision and
          state.capturedConstraints.len == state.constraintCount:
        view.savePersistentLayout(state)
      else:
        view.xPersistentLayout = default(PersistentLayoutCache)
    view.clearSolveFailure(lsmLayout)
    view.xLastLayoutSolveDiagnostic = LayoutSolveDiagnostic()
    view.xCssLayoutDiagnostics[lsmLayout] = state.cssDiagnostics
    return true
  except LayoutSolveBudgetExceeded as error:
    recordSolverFailure()
    view.xLayoutInputCache = previousCache
    view.xLastLayoutSolveDiagnostic = error.diagnostic
    view.recordSolveFailure(lsmLayout)
    if state.didResolveCss:
      state.cssDiagnostics.add CssLayoutDiagnostic(
        property: "-nimkit-constraints",
        message: "Layout solver budget exceeded " & $error.diagnostic.limit,
      )
    view.xCssLayoutDiagnostics[lsmLayout] = state.cssDiagnostics
    false
  except CssLayoutGeometryError:
    recordSolverFailure()
    view.xLayoutInputCache = previousCache
    view.xLastLayoutSolveDiagnostic = state.solveDiagnostic()
    view.xLastLayoutSolveDiagnostic.failed = true
    view.recordSolveFailure(lsmLayout)
    view.xCssLayoutDiagnostics[lsmLayout] = state.cssDiagnostics
    false
  except CatchableError:
    view.xLayoutInputCache = previousCache
    raise

proc fittingSize*(view: View): Size =
  if view.isNil:
    return initSize()

  if view.solveBlocked(lsmFitting):
    return view.alignmentRect().size

  let previousCache = view.xLayoutInputCache
  var state = initLayoutSolveState(view.xLayoutSolveLimits, lsmFitting)
  try:
    state.buildAndSolveConstraints(view, lsmFitting)

    let solverView = state.solverView(view)
    let width = solverView.width.solvedFloat()
    let height = solverView.height.solvedFloat()
    state.requireFiniteCssGeometry(view, [width, height])
    result = initSize(max(width, 0.0'f32), max(height, 0.0'f32))
    state.requireFiniteCssGeometry(view, [result.width, result.height])
    if state.didResolveCss or previousCache.generated[lisCss].len > 0:
      view.xLayoutInputCache = previousCache
    view.clearSolveFailure(lsmFitting)
    view.xLastLayoutSolveDiagnostic = LayoutSolveDiagnostic()
    view.xCssLayoutDiagnostics[lsmFitting] = state.cssDiagnostics
  except LayoutSolveBudgetExceeded as error:
    recordSolverFailure()
    view.xLayoutInputCache = previousCache
    view.xLastLayoutSolveDiagnostic = error.diagnostic
    view.recordSolveFailure(lsmFitting)
    if state.didResolveCss:
      state.cssDiagnostics.add CssLayoutDiagnostic(
        property: "-nimkit-constraints",
        message: "Fitting solver budget exceeded " & $error.diagnostic.limit,
      )
    view.xCssLayoutDiagnostics[lsmFitting] = state.cssDiagnostics
    result = view.alignmentRect().size
  except CssLayoutGeometryError:
    recordSolverFailure()
    view.xLayoutInputCache = previousCache
    view.xLastLayoutSolveDiagnostic = state.solveDiagnostic()
    view.xLastLayoutSolveDiagnostic.failed = true
    view.recordSolveFailure(lsmFitting)
    view.xCssLayoutDiagnostics[lsmFitting] = state.cssDiagnostics
    result = view.alignmentRect().size
  except CatchableError:
    view.xLayoutInputCache = previousCache
    raise
