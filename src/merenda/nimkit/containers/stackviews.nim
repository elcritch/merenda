import sigils/core

import ../foundation/selectors
import ../themes
import ../foundation/types
import ../view/viewgeometry
import ../view/views

export views

type
  StackViewAlignment* = enum
    svaFill
    svaLeading
    svaCenter
    svaTrailing

  StackViewDistribution* = enum
    svdFill
    svdFillEqually
    svdNatural
    svdEqualSpacing

  StackViewSizingPolicy* = enum
    ## Controls how one arranged subview uses the stack's available dimensions.
    svspAutomatic
    svspFillAvailableWidth
    svspFillAvailableSpace

  ArrangedSubview* = object
    ## One input to `addArrangedSubview`, with a per-view sizing policy.
    view*: View
    sizingPolicy*: StackViewSizingPolicy

  StackView* = ref object of View
    xArrangedSubviews: seq[View]
    xArrangedSubviewSizing: seq[StackViewSizingPolicy]
    xOrientation: LayoutAxis
    xSpacing: float32
    xEdgeInsets: EdgeInsets
    xAlignment: StackViewAlignment
    xDistribution: StackViewDistribution

  FlexibleSpacerView = ref object of View

  StackLayoutStyle = object
    orientation: LayoutAxis
    spacing: float32
    insets: EdgeInsets
    alignment: StackViewAlignment
    distribution: StackViewDistribution

const LayoutEpsilon = 0.001'f32

func normalizedSpacing(value: float32): float32 =
  max(value, 0.0'f32)

func normalizedInsets(insets: EdgeInsets): EdgeInsets =
  insets(
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

func mainSize(size: Size, axis: LayoutAxis): float32 =
  case axis
  of laHorizontal: size.width
  of laVertical: size.height

func crossSize(size: Size, axis: LayoutAxis): float32 =
  case axis
  of laHorizontal: size.height
  of laVertical: size.width

func mainInset(insets: EdgeInsets, axis: LayoutAxis): float32 =
  case axis
  of laHorizontal: insets.horizontal
  of laVertical: insets.vertical

func crossInset(insets: EdgeInsets, axis: LayoutAxis): float32 =
  case axis
  of laHorizontal: insets.vertical
  of laVertical: insets.horizontal

func initStackSize(axis: LayoutAxis, main, cross: float32): Size =
  case axis
  of laHorizontal:
    initSize(main, cross)
  of laVertical:
    initSize(cross, main)

func initStackFrame(
    axis: LayoutAxis, mainOrigin, crossOrigin, mainLength, crossLength: float32
): Rect =
  case axis
  of laHorizontal:
    rect(mainOrigin, crossOrigin, mainLength, crossLength)
  of laVertical:
    rect(crossOrigin, mainOrigin, crossLength, mainLength)

func crossAxis(axis: LayoutAxis): LayoutAxis =
  case axis
  of laHorizontal: laVertical
  of laVertical: laHorizontal

func fillsAxis(policy: StackViewSizingPolicy, axis: LayoutAxis): bool =
  case policy
  of svspAutomatic:
    false
  of svspFillAvailableWidth:
    axis == laHorizontal
  of svspFillAvailableSpace:
    true

protocol FlexibleSpacerLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(spacer: FlexibleSpacerView): IntrinsicSize =
    initIntrinsicSize(0.0, 0.0)

proc newFlexibleSpacer*(axis = laVertical, frame: Rect = AutoRect): View =
  let spacer = FlexibleSpacerView()
  initViewFields(spacer, frame)
  discard spacer.withProtocol(FlexibleSpacerLayout)
  result = spacer
  result.background = color(0.0, 0.0, 0.0, 0.0)
  result.setHuggingPriority(LayoutPriorityLow, axis)
  result.setCompressionPriority(LayoutPriorityLow, axis)
  result.setHuggingPriority(LayoutPriorityRequired, axis.crossAxis)
  result.setCompressionPriority(LayoutPriorityRequired, axis.crossAxis)

proc flexibleSpacer*(axis = laVertical, frame: Rect = AutoRect): View =
  newFlexibleSpacer(axis, frame)

proc invalidateStackLayout(stackView: StackView) =
  stackView.invalidateContainerMetrics()
  stackView.needsDisplay = true

proc arrangedIndex(stackView: StackView, child: View): int =
  if child.isNil:
    return -1
  for index, arranged in stackView.xArrangedSubviews:
    if arranged == child:
      return index
  -1

proc sizingPolicy(stackView: StackView, child: View): StackViewSizingPolicy =
  let index = stackView.arrangedIndex(child)
  if index >= 0 and index < stackView.xArrangedSubviewSizing.len:
    stackView.xArrangedSubviewSizing[index]
  else:
    svspAutomatic

proc layoutArrangedSubviews(stackView: StackView): seq[View] =
  for child in stackView.xArrangedSubviews:
    if not child.isNil and child.superview == stackView and not child.isHidden:
      result.add child

proc resolvedStackLayoutStyle(stack: StackView): StackLayoutStyle =
  let
    theme = stack.effectiveAppearance().theme
    context = controlStyle(
      srStackView,
      stack.widgetStateSet(),
      id = stack.styleId,
      classes = stack.styleClasses,
    )
    orientation = theme.resolveKeyword(
      context,
      StyleContainerOrientation,
      if stack.xOrientation == laHorizontal: "horizontal" else: "vertical",
    )
    alignment = theme.resolveKeyword(
      context,
      StyleContainerAlignment,
      case stack.xAlignment
      of svaFill: "fill"
      of svaLeading: "leading"
      of svaCenter: "center"
      of svaTrailing: "trailing"
      ,
    )
    distribution = theme.resolveKeyword(
      context,
      StyleContainerDistribution,
      case stack.xDistribution
      of svdFill: "fill"
      of svdFillEqually: "fill-equally"
      of svdNatural: "natural"
      of svdEqualSpacing: "equal-spacing"
      ,
    )
  result.orientation = if orientation == "horizontal": laHorizontal else: laVertical
  result.spacing = theme
    .resolveLength(
      context,
      if result.orientation == laHorizontal:
        StyleContainerColumnGap
      else:
        StyleContainerRowGap,
      stack.xSpacing,
    )
    .normalizedSpacing()
  result.insets = theme
    .resolveInsets(context, StyleContainerInsets, stack.xEdgeInsets)
    .normalizedInsets()
  result.alignment =
    case alignment
    of "leading": svaLeading
    of "center": svaCenter
    of "trailing": svaTrailing
    else: svaFill
  result.distribution =
    case distribution
    of "fill-equally": svdFillEqually
    of "natural": svdNatural
    of "equal-spacing": svdEqualSpacing
    else: svdFill

proc fittingSize(child: View): Size =
  if child.isNil:
    initSize(0.0, 0.0)
  else:
    child.sizeThatFits(UnconstrainedFittingSize)

proc stackNaturalSize(stackView: StackView): Size =
  let
    style = stackView.resolvedStackLayoutStyle()
    children = stackView.layoutArrangedSubviews()
    axis = style.orientation
    insets = style.insets

  var
    main = insets.mainInset(axis)
    cross = insets.crossInset(axis)
    childMain = 0.0'f32
    childCross = 0.0'f32

  for child in children:
    let size = child.fittingSize()
    childMain += size.mainSize(axis)
    childCross = max(childCross, size.crossSize(axis))

  main += childMain + style.spacing.totalSpacing(children.len)
  cross += childCross
  initStackSize(axis, main, cross)

proc contentRect(stackView: StackView, style: StackLayoutStyle): Rect =
  let
    bounds = stackView.bounds()
    insets = style.insets
  rect(
    insets.left,
    insets.top,
    bounds.size.width - insets.horizontal,
    bounds.size.height - insets.vertical,
  )

proc setFrameFromStackLayout(view: View, frame: Rect) =
  view.applyLayoutFrame(frame, lfoContainer)

func shouldAdjust(delta: float32): bool =
  delta < -LayoutEpsilon or delta > LayoutEpsilon

func usedMainLength(sizes: openArray[float32], spacing: float32): float32 =
  result = spacing.totalSpacing(sizes.len)
  for size in sizes:
    result += size

proc lowestAdjustmentPriority(
    children: openArray[View], axis: LayoutAxis, growing: bool
): LayoutPriority =
  result = LayoutPriorityRequired
  var hasPriority = false
  for child in children:
    let priority =
      if growing:
        child.huggingPriority(axis)
      else:
        child.compressionPriority(axis)
    if not hasPriority or priority < result:
      result = priority
      hasPriority = true

proc countPriority(
    children: openArray[View], axis: LayoutAxis, growing: bool, priority: LayoutPriority
): int =
  for child in children:
    let childPriority =
      if growing:
        child.huggingPriority(axis)
      else:
        child.compressionPriority(axis)
    if childPriority == priority:
      inc result

proc adjustFillSizes(
    children: openArray[View],
    sizes: var seq[float32],
    availableMain: float32,
    style: StackLayoutStyle,
) =
  if children.len == 0:
    return

  let delta = availableMain - sizes.usedMainLength(style.spacing)
  if not delta.shouldAdjust():
    return

  let
    growing = delta > 0.0'f32
    priority = children.lowestAdjustmentPriority(style.orientation, growing)
    count = children.countPriority(style.orientation, growing, priority)
  if growing and priority == LayoutPriorityRequired:
    return
  if count <= 0:
    return

  let share = delta / float32(count)
  for index, child in children:
    let childPriority =
      if growing:
        child.huggingPriority(style.orientation)
      else:
        child.compressionPriority(style.orientation)
    if childPriority == priority:
      sizes[index] = max(sizes[index] + share, 0.0'f32)

proc adjustPolicyFillSizes(
    stackView: StackView,
    children: openArray[View],
    sizes: var seq[float32],
    availableMain: float32,
    style: StackLayoutStyle,
): bool =
  var indexes: seq[int]
  for index, child in children:
    if stackView.sizingPolicy(child).fillsAxis(style.orientation):
      indexes.add index
  if indexes.len == 0:
    return

  result = true
  let delta = availableMain - sizes.usedMainLength(style.spacing)
  if not delta.shouldAdjust():
    return

  let share = delta / float32(indexes.len)
  for index in indexes:
    sizes[index] = max(sizes[index] + share, 0.0'f32)

proc arrangedMainSizes(
    stackView: StackView,
    children: openArray[View],
    naturalSizes: openArray[Size],
    style: StackLayoutStyle,
): seq[float32] =
  let
    axis = style.orientation
    availableMain = stackView.contentRect(style).size.mainSize(axis)
  case style.distribution
  of svdFill:
    for size in naturalSizes:
      result.add size.mainSize(axis)
    if not stackView.adjustPolicyFillSizes(children, result, availableMain, style):
      adjustFillSizes(children, result, availableMain, style)
  of svdFillEqually:
    let size =
      if children.len == 0:
        0.0'f32
      else:
        max(
          (availableMain - style.spacing.totalSpacing(children.len)) /
            float32(children.len),
          0.0'f32,
        )
    result.setLen(children.len)
    for index in 0 ..< result.len:
      result[index] = size
  of svdNatural, svdEqualSpacing:
    for size in naturalSizes:
      result.add size.mainSize(axis)
    let usedPolicy =
      stackView.adjustPolicyFillSizes(children, result, availableMain, style)
    if not usedPolicy and result.usedMainLength(style.spacing) > availableMain:
      adjustFillSizes(children, result, availableMain, style)

proc arrangedSpacing(
    stackView: StackView,
    children: openArray[View],
    mainSizes: openArray[float32],
    style: StackLayoutStyle,
): float32 =
  result = style.spacing
  if style.distribution != svdEqualSpacing or children.len <= 1:
    return

  let
    availableMain = stackView.contentRect(style).size.mainSize(style.orientation)
    usedMain = mainSizes.usedMainLength(style.spacing)
    extra = availableMain - usedMain
  if extra > LayoutEpsilon:
    result += extra / float32(children.len - 1)

proc alignedCrossFrame(
    stackView: StackView,
    child: View,
    content: Rect,
    naturalCross: float32,
    style: StackLayoutStyle,
): tuple[origin, length: float32] =
  let
    axis = style.orientation
    availableCross = content.size.crossSize(axis)
    contentCrossOrigin =
      case axis
      of laHorizontal: content.origin.y
      of laVertical: content.origin.x

  let policy = stackView.sizingPolicy(child)
  if policy.fillsAxis(axis.crossAxis) or style.alignment == svaFill:
    return (contentCrossOrigin, availableCross)

  result.length = min(naturalCross, availableCross)
  case style.alignment
  of svaFill:
    discard
  of svaLeading:
    result.origin = contentCrossOrigin
  of svaCenter:
    result.origin = contentCrossOrigin + (availableCross - result.length) / 2.0'f32
  of svaTrailing:
    result.origin = contentCrossOrigin + availableCross - result.length

proc layoutStackSubviews(stackView: StackView) =
  let
    style = stackView.resolvedStackLayoutStyle()
    children = stackView.layoutArrangedSubviews()
    axis = style.orientation
    content = stackView.contentRect(style)

  var naturalSizes: seq[Size]
  for child in children:
    naturalSizes.add child.fittingSize()

  let mainSizes = stackView.arrangedMainSizes(children, naturalSizes, style)
  let spacing = stackView.arrangedSpacing(children, mainSizes, style)
  var mainCursor =
    case axis
    of laHorizontal: content.origin.x
    of laVertical: content.origin.y

  for index, child in children:
    let
      naturalCross = naturalSizes[index].crossSize(axis)
      cross = stackView.alignedCrossFrame(child, content, naturalCross, style)
      frame =
        initStackFrame(axis, mainCursor, cross.origin, mainSizes[index], cross.length)
    child.setFrameFromStackLayout(frame)
    mainCursor += mainSizes[index] + spacing

protocol StackViewProtocol {.selectorScope: protocol, setterStyle: nim.} from StackView:
  property orientation -> LayoutAxis
  property spacing -> float32
  property edgeInsets -> EdgeInsets
  property stackAlignment -> StackViewAlignment
  property distribution -> StackViewDistribution

  method orientation(stackView: StackView): LayoutAxis =
    stackView.xOrientation

  method `orientation=`(stackView: StackView, orientation: LayoutAxis) =
    if stackView.xOrientation == orientation:
      return
    stackView.xOrientation = orientation
    stackView.invalidateStackLayout()

  method spacing(stackView: StackView): float32 =
    stackView.xSpacing

  method `spacing=`(stackView: StackView, spacing: float32) =
    let normalized = spacing.normalizedSpacing()
    if stackView.xSpacing == normalized:
      return
    stackView.xSpacing = normalized
    stackView.invalidateStackLayout()

  method edgeInsets(stackView: StackView): EdgeInsets =
    stackView.xEdgeInsets

  method `edgeInsets=`(stackView: StackView, insets: EdgeInsets) =
    let normalized = insets.normalizedInsets()
    if stackView.xEdgeInsets == normalized:
      return
    stackView.xEdgeInsets = normalized
    stackView.invalidateStackLayout()

  method stackAlignment(stackView: StackView): StackViewAlignment =
    stackView.xAlignment

  method `stackAlignment=`(stackView: StackView, alignment: StackViewAlignment) =
    if stackView.xAlignment == alignment:
      return
    stackView.xAlignment = alignment
    stackView.invalidateStackLayout()

  method distribution(stackView: StackView): StackViewDistribution =
    stackView.xDistribution

  method `distribution=`(stackView: StackView, distribution: StackViewDistribution) =
    if stackView.xDistribution == distribution:
      return
    stackView.xDistribution = distribution
    stackView.invalidateStackLayout()

proc alignment*(stackView: StackView): StackViewAlignment =
  stackView.stackAlignment()

proc `alignment=`*(stackView: StackView, alignment: StackViewAlignment) =
  stackView.stackAlignment = alignment

proc intrinsicContentSize*(stackView: StackView): IntrinsicSize =
  initIntrinsicSize(stackView.stackNaturalSize())

proc arrangedSubviews*(stackView: StackView): seq[View] =
  stackView.xArrangedSubviews

proc insertArrangedSubview*(
    stackView: StackView, child: View, index: int, sizingPolicy = svspAutomatic
) =
  if child.isNil:
    return

  if child.superview != stackView:
    stackView.addSubview(child)

  let oldIndex = stackView.arrangedIndex(child)
  if oldIndex >= 0:
    stackView.xArrangedSubviews.delete(oldIndex)
    stackView.xArrangedSubviewSizing.delete(oldIndex)

  let boundedIndex = max(0, min(index, stackView.xArrangedSubviews.len))
  stackView.xArrangedSubviews.insert(child, boundedIndex)
  stackView.xArrangedSubviewSizing.insert(sizingPolicy, boundedIndex)
  stackView.invalidateStackLayout()

proc addArrangedSubview*(stackView: StackView, child: View) =
  if child.isNil:
    return
  stackView.insertArrangedSubview(child, stackView.xArrangedSubviews.len)

proc addArrangedSubview*(
    stackView: StackView, child: View, sizingPolicy: StackViewSizingPolicy
) =
  if child.isNil:
    return
  stackView.insertArrangedSubview(child, stackView.xArrangedSubviews.len, sizingPolicy)

proc addArrangedSubview*(stackView: StackView, children: varargs[View]) =
  for child in children:
    stackView.addArrangedSubview(child)

func toArrangedSubview*(view: View): ArrangedSubview =
  ## Converts a view to an arranged input using automatic sizing.
  ArrangedSubview(view: view)

func toArrangedSubview*[T: View | typeof(nil)](
    item: (T, StackViewSizingPolicy)
): ArrangedSubview =
  ## Converts a `(view, sizingPolicy)` pair to an arranged input.
  ArrangedSubview(view: item[0], sizingPolicy: item[1])

proc addArrangedSubview*(
    stackView: StackView, children: varargs[ArrangedSubview, toArrangedSubview]
) =
  ## Arranges a mixture of views and `(view, sizingPolicy)` pairs in order.
  ## Plain views use `svspAutomatic`; nil views are skipped.
  for child in children:
    stackView.addArrangedSubview(child.view, child.sizingPolicy)

proc arrangedSubviewSizingPolicy*(
    stackView: StackView, child: View
): StackViewSizingPolicy =
  ## Returns the child's sizing policy, or automatic when it is not arranged.
  stackView.sizingPolicy(child)

proc setArrangedSubviewSizingPolicy*(
    stackView: StackView, child: View, sizingPolicy: StackViewSizingPolicy
) =
  ## Changes the sizing policy of an existing arranged subview.
  let index = stackView.arrangedIndex(child)
  if index < 0 or stackView.xArrangedSubviewSizing[index] == sizingPolicy:
    return
  stackView.xArrangedSubviewSizing[index] = sizingPolicy
  stackView.setNeedsLayout()

proc fillAvailableWidth*(stackView: StackView, child: View) =
  ## Arranges the child, if needed, and makes it fill the horizontal dimension.
  let index = stackView.arrangedIndex(child)
  if index < 0:
    stackView.addArrangedSubview(child, svspFillAvailableWidth)
  else:
    stackView.setArrangedSubviewSizingPolicy(child, svspFillAvailableWidth)

proc fillAvailableSpace*(stackView: StackView, child: View) =
  ## Arranges the child, if needed, and makes it fill both available dimensions.
  let index = stackView.arrangedIndex(child)
  if index < 0:
    stackView.addArrangedSubview(child, svspFillAvailableSpace)
  else:
    stackView.setArrangedSubviewSizingPolicy(child, svspFillAvailableSpace)

proc addFlexibleSpacer*(stackView: StackView): View {.discardable.} =
  result = newFlexibleSpacer(stackView.xOrientation)
  stackView.addArrangedSubview(result)

proc removeArrangedSubview*(stackView: StackView, child: View) =
  let index = stackView.arrangedIndex(child)
  if index < 0:
    return
  stackView.xArrangedSubviews.delete(index)
  stackView.xArrangedSubviewSizing.delete(index)
  stackView.invalidateStackLayout()

protocol StackViewLifecycleSlots of ViewLifecycleProtocol:
  proc removeOwnedSubview(
      stackView: StackView, child: View
  ) {.slotFor: willRemoveSubview.} =
    stackView.removeArrangedSubview(child)

protocol DefaultStackViewLayout of ViewLayoutProtocol:
  method layoutStyleContext(stack: StackView): StyleContext =
    controlStyle(
      srStackView,
      stack.widgetStateSet(),
      id = stack.styleId,
      classes = stack.styleClasses,
    )

  method managesSubviewLayout(stack: StackView, child: DynamicAgent): bool =
    for arranged in stack.xArrangedSubviews:
      if DynamicAgent(arranged) == child and arranged.superviewBacklink() == stack:
        return true

  method layoutIntrinsicContentSize(stackView: StackView): IntrinsicSize =
    initIntrinsicSize(stackView.stackNaturalSize())

  method layoutSubviews(stackView: StackView) =
    stackView.layoutStackSubviews()

proc initStackViewFields*(
    stackView: StackView, orientation = laVertical, frame: Rect = AutoRect
) =
  initViewFields(stackView, frame)
  stackView.background = color(0.0, 0.0, 0.0, 0.0)
  stackView.xOrientation = orientation
  stackView.xSpacing = 8.0'f32
  stackView.xAlignment = svaFill
  stackView.xDistribution = svdFill
  discard stackView.withProto()
  discard stackView.withProtocol(DefaultStackViewLayout)
  discard stackView.withProtocol(StackViewLifecycleSlots)
  stackView.observeProtocol(stackView, StackViewLifecycleSlots)
  stackView.applyInitialFrame(frame)

proc newStackView*(orientation = laVertical, frame: Rect = AutoRect): StackView =
  result = StackView()
  initStackViewFields(result, orientation, frame)
