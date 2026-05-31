import ./selectors
import ./theme
import ./types
import ./views

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

  StackView* = ref object of View
    xArrangedSubviews: seq[View]
    xOrientation: LayoutAxis
    xSpacing: float32
    xEdgeInsets: EdgeInsets
    xAlignment: StackViewAlignment
    xDistribution: StackViewDistribution

const LayoutEpsilon = 0.001'f32

func normalizedSpacing(value: float32): float32 =
  max(value, 0.0'f32)

func normalizedInsets(insets: EdgeInsets): EdgeInsets =
  initEdgeInsets(
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
    initRect(mainOrigin, crossOrigin, mainLength, crossLength)
  of laVertical:
    initRect(crossOrigin, mainOrigin, crossLength, mainLength)

proc invalidateStackLayout(stackView: StackView) =
  if stackView.isNil:
    return
  stackView.invalidateIntrinsicContentSize()
  stackView.setNeedsLayout()
  stackView.setNeedsDisplay(true)

proc arrangedIndex(stackView: StackView, child: View): int =
  if stackView.isNil or child.isNil:
    return -1
  for index, arranged in stackView.xArrangedSubviews:
    if arranged == child:
      return index
  -1

proc layoutArrangedSubviews(stackView: StackView): seq[View] =
  if stackView.isNil:
    return
  for child in stackView.xArrangedSubviews:
    if not child.isNil and child.superview == stackView and not child.isHidden:
      result.add child

proc fittingSize(child: View): Size =
  if child.isNil:
    initSize(0.0, 0.0)
  else:
    child.sizeThatFits(UnconstrainedFittingSize)

proc stackNaturalSize(stackView: StackView): Size =
  if stackView.isNil:
    return initSize(0.0, 0.0)

  let
    children = stackView.layoutArrangedSubviews()
    axis = stackView.xOrientation
    insets = stackView.xEdgeInsets

  var
    main = insets.mainInset(axis)
    cross = insets.crossInset(axis)
    childMain = 0.0'f32
    childCross = 0.0'f32

  for child in children:
    let size = child.fittingSize()
    childMain += size.mainSize(axis)
    childCross = max(childCross, size.crossSize(axis))

  main += childMain + stackView.xSpacing.totalSpacing(children.len)
  cross += childCross
  initStackSize(axis, main, cross)

proc contentRect(stackView: StackView): Rect =
  let
    bounds = stackView.bounds()
    insets = stackView.xEdgeInsets
  initRect(
    insets.left,
    insets.top,
    bounds.size.width - insets.horizontal,
    bounds.size.height - insets.vertical,
  )

proc setFrameFromStackLayout(view: View, frame: Rect) =
  if view.isNil or view.xFrame == frame:
    return
  view.xFrame = frame
  view.xBounds = initRect(0.0, 0.0, frame.size.width, frame.size.height)
  view.xNeedsLayout = true
  view.xNeedsDisplay = true
  view.xInvalidRects.setLen(0)
  view.markSubviewAutoresizingConstraintsChanged()

func shouldAdjust(delta: float32): bool =
  delta < -LayoutEpsilon or delta > LayoutEpsilon

proc lowestAdjustmentPriority(
    children: openArray[View], axis: LayoutAxis, growing: bool
): LayoutPriority =
  result = LayoutPriorityRequired
  var hasPriority = false
  for child in children:
    let priority =
      if growing:
        child.contentHuggingPriority(axis)
      else:
        child.contentCompressionResistancePriority(axis)
    if not hasPriority or priority < result:
      result = priority
      hasPriority = true

proc countPriority(
    children: openArray[View], axis: LayoutAxis, growing: bool, priority: LayoutPriority
): int =
  for child in children:
    let childPriority =
      if growing:
        child.contentHuggingPriority(axis)
      else:
        child.contentCompressionResistancePriority(axis)
    if childPriority == priority:
      inc result

proc adjustFillSizes(
    stackView: StackView,
    children: openArray[View],
    sizes: var seq[float32],
    availableMain: float32,
) =
  if children.len == 0:
    return

  var usedMain = stackView.xSpacing.totalSpacing(children.len)
  for size in sizes:
    usedMain += size

  let delta = availableMain - usedMain
  if not delta.shouldAdjust():
    return

  let
    growing = delta > 0.0'f32
    priority = children.lowestAdjustmentPriority(stackView.xOrientation, growing)
    count = children.countPriority(stackView.xOrientation, growing, priority)
  if count <= 0:
    return

  let share = delta / float32(count)
  for index, child in children:
    let childPriority =
      if growing:
        child.contentHuggingPriority(stackView.xOrientation)
      else:
        child.contentCompressionResistancePriority(stackView.xOrientation)
    if childPriority == priority:
      sizes[index] = max(sizes[index] + share, 0.0'f32)

proc arrangedMainSizes(
    stackView: StackView, children: openArray[View], naturalSizes: openArray[Size]
): seq[float32] =
  let
    axis = stackView.xOrientation
    availableMain = stackView.contentRect().size.mainSize(axis)
  case stackView.xDistribution
  of svdFill:
    for size in naturalSizes:
      result.add size.mainSize(axis)
    stackView.adjustFillSizes(children, result, availableMain)
  of svdFillEqually:
    let size =
      if children.len == 0:
        0.0'f32
      else:
        max(
          (availableMain - stackView.xSpacing.totalSpacing(children.len)) /
            float32(children.len),
          0.0'f32,
        )
    result.setLen(children.len)
    for index in 0 ..< result.len:
      result[index] = size

proc alignedCrossFrame(
    stackView: StackView, content: Rect, naturalCross: float32
): tuple[origin, length: float32] =
  let
    axis = stackView.xOrientation
    availableCross = content.size.crossSize(axis)
    contentCrossOrigin =
      case axis
      of laHorizontal: content.origin.y
      of laVertical: content.origin.x

  if stackView.xAlignment == svaFill:
    return (contentCrossOrigin, availableCross)

  result.length = min(naturalCross, availableCross)
  case stackView.xAlignment
  of svaFill:
    discard
  of svaLeading:
    result.origin = contentCrossOrigin
  of svaCenter:
    result.origin = contentCrossOrigin + (availableCross - result.length) / 2.0'f32
  of svaTrailing:
    result.origin = contentCrossOrigin + availableCross - result.length

proc layoutStackSubviews(stackView: StackView) =
  if stackView.isNil:
    return

  let
    children = stackView.layoutArrangedSubviews()
    axis = stackView.xOrientation
    content = stackView.contentRect()

  var naturalSizes: seq[Size]
  for child in children:
    naturalSizes.add child.fittingSize()

  let mainSizes = stackView.arrangedMainSizes(children, naturalSizes)
  var mainCursor =
    case axis
    of laHorizontal: content.origin.x
    of laVertical: content.origin.y

  for index, child in children:
    let
      naturalCross = naturalSizes[index].crossSize(axis)
      cross = stackView.alignedCrossFrame(content, naturalCross)
      frame =
        initStackFrame(axis, mainCursor, cross.origin, mainSizes[index], cross.length)
    child.setFrameFromStackLayout(frame)
    mainCursor += mainSizes[index] + stackView.xSpacing

proc orientation*(stackView: StackView): LayoutAxis =
  if stackView.isNil: laVertical else: stackView.xOrientation

proc setOrientation*(stackView: StackView, orientation: LayoutAxis) =
  if stackView.isNil or stackView.xOrientation == orientation:
    return
  stackView.xOrientation = orientation
  stackView.invalidateStackLayout()

proc `orientation=`*(stackView: StackView, orientation: LayoutAxis) =
  stackView.setOrientation(orientation)

proc spacing*(stackView: StackView): float32 =
  if stackView.isNil: 0.0'f32 else: stackView.xSpacing

proc setSpacing*(stackView: StackView, spacing: float32) =
  let normalized = spacing.normalizedSpacing()
  if stackView.isNil or stackView.xSpacing == normalized:
    return
  stackView.xSpacing = normalized
  stackView.invalidateStackLayout()

proc `spacing=`*(stackView: StackView, spacing: float32) =
  stackView.setSpacing(spacing)

proc edgeInsets*(stackView: StackView): EdgeInsets =
  if stackView.isNil:
    initEdgeInsets(0.0)
  else:
    stackView.xEdgeInsets

proc setEdgeInsets*(stackView: StackView, insets: EdgeInsets) =
  let normalized = insets.normalizedInsets()
  if stackView.isNil or stackView.xEdgeInsets == normalized:
    return
  stackView.xEdgeInsets = normalized
  stackView.invalidateStackLayout()

proc `edgeInsets=`*(stackView: StackView, insets: EdgeInsets) =
  stackView.setEdgeInsets(insets)

proc alignment*(stackView: StackView): StackViewAlignment =
  if stackView.isNil: svaFill else: stackView.xAlignment

proc setAlignment*(stackView: StackView, alignment: StackViewAlignment) =
  if stackView.isNil or stackView.xAlignment == alignment:
    return
  stackView.xAlignment = alignment
  stackView.invalidateStackLayout()

proc `alignment=`*(stackView: StackView, alignment: StackViewAlignment) =
  stackView.setAlignment(alignment)

proc distribution*(stackView: StackView): StackViewDistribution =
  if stackView.isNil: svdFill else: stackView.xDistribution

proc setDistribution*(stackView: StackView, distribution: StackViewDistribution) =
  if stackView.isNil or stackView.xDistribution == distribution:
    return
  stackView.xDistribution = distribution
  stackView.invalidateStackLayout()

proc `distribution=`*(stackView: StackView, distribution: StackViewDistribution) =
  stackView.setDistribution(distribution)

proc intrinsicContentSize*(stackView: StackView): IntrinsicSize =
  if stackView.isNil:
    NoIntrinsicContentSize
  else:
    initIntrinsicSize(stackView.stackNaturalSize())

proc arrangedSubviews*(stackView: StackView): seq[View] =
  if stackView.isNil:
    @[]
  else:
    stackView.xArrangedSubviews

proc insertArrangedSubview*(stackView: StackView, child: View, index: int) =
  if stackView.isNil or child.isNil:
    return

  if child.superview != stackView:
    stackView.addSubview(child)

  let oldIndex = stackView.arrangedIndex(child)
  if oldIndex >= 0:
    stackView.xArrangedSubviews.delete(oldIndex)

  let boundedIndex = max(0, min(index, stackView.xArrangedSubviews.len))
  stackView.xArrangedSubviews.insert(child, boundedIndex)
  stackView.invalidateStackLayout()

proc addArrangedSubview*(stackView: StackView, child: View) =
  if stackView.isNil or child.isNil:
    return
  stackView.insertArrangedSubview(child, stackView.xArrangedSubviews.len)

proc addArrangedSubview*(stackView: StackView, children: varargs[View]) =
  for child in children:
    stackView.addArrangedSubview(child)

proc removeArrangedSubview*(stackView: StackView, child: View) =
  let index = stackView.arrangedIndex(child)
  if index < 0:
    return
  stackView.xArrangedSubviews.delete(index)
  stackView.invalidateStackLayout()

protocol DefaultStackViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(stackView: StackView): IntrinsicSize =
    initIntrinsicSize(stackView.stackNaturalSize())

  method layoutSubviews(stackView: StackView) =
    stackView.layoutStackSubviews()

protocol DefaultStackViewLifecycle of ViewLifecycleProtocol:
  method willRemoveSubview(stackView: StackView, subview: View) =
    stackView.removeArrangedSubview(subview)

proc initStackViewFields*(
    stackView: StackView, orientation = laVertical, frame: Rect = AutoRect
) =
  initViewFields(stackView, frame)
  stackView.xOrientation = orientation
  stackView.xSpacing = 8.0'f32
  stackView.xAlignment = svaFill
  stackView.xDistribution = svdFill
  discard stackView.withProtocol(DefaultStackViewLayout)
  discard stackView.withProtocol(DefaultStackViewLifecycle)
  stackView.applyInitialFrame(frame)

proc newStackView*(orientation = laVertical, frame: Rect = AutoRect): StackView =
  result = StackView()
  initStackViewFields(result, orientation, frame)
