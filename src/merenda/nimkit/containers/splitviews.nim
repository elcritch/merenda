import std/[strutils]

import sigils/core

import ../accessibility/accessibility
import ../app/animations
import ../drawing
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../themes
import ../view/viewgeometry
import ../view/views

export views

type
  SplitViewPane* = object
    view*: View
    minSize*: float32
    maxSize*: float32
    collapsible*: bool
    collapsed*: bool
    fraction*: float32

  SplitViewState* = object
    fractions*: seq[float32]
    collapsed*: seq[bool]

  SplitView* = ref object of View
    xAxis: LayoutAxis
    xPanes: seq[SplitViewPane]
    xDividerThickness: float32
    xAutosaveName: string
    xDragDivider: int
    xDragStartMain: float32
    xDragInitialFractions: seq[float32]

  SplitDividerTransactionTarget = ref object of DynamicAgent
    splitView: SplitView
    dividerIndex: int

const
  SplitViewDefaultDividerThickness = 6.0'f32
  SplitViewDefaultPaneMinSize = 0.0'f32
  SplitViewDefaultPaneMaxSize = float32.high
  SplitViewEpsilon = 0.001'f32

func mainSize(size: Size, axis: LayoutAxis): float32 =
  case axis
  of laHorizontal: size.width
  of laVertical: size.height

func crossSize(size: Size, axis: LayoutAxis): float32 =
  case axis
  of laHorizontal: size.height
  of laVertical: size.width

func mainOrigin(rect: Rect, axis: LayoutAxis): float32 =
  case axis
  of laHorizontal: rect.origin.x
  of laVertical: rect.origin.y

func mainPoint(point: Point, axis: LayoutAxis): float32 =
  case axis
  of laHorizontal: point.x
  of laVertical: point.y

func initSplitRect(
    axis: LayoutAxis, mainOrigin, crossOrigin, mainLength, crossLength: float32
): Rect =
  case axis
  of laHorizontal:
    rect(mainOrigin, crossOrigin, mainLength, crossLength)
  of laVertical:
    rect(crossOrigin, mainOrigin, crossLength, mainLength)

func normalizedFraction(value: float32): float32 =
  if value < 0.0'f32: 0.0'f32 else: value

func normalizedThickness(value: float32): float32 =
  max(value, 1.0'f32)

proc splitViewStyleContext(splitView: SplitView): StyleContext =
  if splitView.isNil:
    controlStyle(srSplitView)
  else:
    controlStyle(
      srSplitView,
      splitView.widgetStateSet(),
      id = splitView.styleId,
      classes = splitView.styleClasses,
    )

proc resolvedSplitViewStyle(splitView: SplitView): SplitViewStyle =
  let appearance =
    if splitView.isNil:
      initAppearance()
    else:
      splitView.effectiveAppearance()
  appearance.resolveSplitViewStyle(splitView.splitViewStyleContext())

proc effectiveDividerThickness(splitView: SplitView): float32 =
  if splitView.isNil:
    return SplitViewDefaultDividerThickness
  if splitView.xDividerThickness > 0.0'f32:
    splitView.xDividerThickness.normalizedThickness()
  else:
    splitView.resolvedSplitViewStyle().dividerThickness.normalizedThickness()

proc visiblePaneIndexes(splitView: SplitView): seq[int] =
  if splitView.isNil:
    return
  for index, pane in splitView.xPanes:
    if pane.view.isNil or pane.view.superview != splitView or pane.view.isHidden:
      continue
    if pane.collapsed:
      continue
    result.add index

proc splitDividerCount(splitView: SplitView): int =
  max(splitView.visiblePaneIndexes().len - 1, 0)

proc availablePaneLength(splitView: SplitView): float32 =
  if splitView.isNil:
    return 0.0'f32
  let
    bounds = splitView.bounds()
    dividerTotal =
      splitView.effectiveDividerThickness() * float32(splitView.splitDividerCount())
  max(bounds.size.mainSize(splitView.xAxis) - dividerTotal, 0.0'f32)

proc invalidateSplitViewLayout(splitView: SplitView) =
  if splitView.isNil:
    return
  splitView.invalidateContainerMetrics()
  splitView.setNeedsLayout()
  splitView.setNeedsDisplay(true)

proc setPositionOfDivider*(splitView: SplitView, dividerIndex: int, position: float32)

protocol SplitDividerTransactionAnimProtocol:
  method animSplitDividerPosition*(position: float32)

protocol SplitDividerTransactionAnim of SplitDividerTransactionAnimProtocol:
  method animSplitDividerPosition(
      target: SplitDividerTransactionTarget, position: float32
  ) =
    if not target.splitView.isNil:
      target.splitView.setPositionOfDivider(target.dividerIndex, position)

protocol SplitViewProtocol {.selectorScope: protocol.} from SplitView:
  property splitAxis -> LayoutAxis
  property dividerThickness -> float32
  property autosaveName -> string

  method paneIndex*(splitView: SplitView, pane: View): int =
    if splitView.isNil or pane.isNil:
      return -1
    for index, current in splitView.xPanes:
      if current.view == pane:
        return index
    -1

  method paneCount*(splitView: SplitView): int =
    if splitView.isNil: 0 else: splitView.xPanes.len

  method panes*(splitView: SplitView): seq[View] =
    if splitView.isNil:
      return @[]
    for pane in splitView.xPanes:
      result.add pane.view

  method splitAxis(splitView: SplitView): LayoutAxis =
    if splitView.isNil: laHorizontal else: splitView.xAxis

  method setSplitAxis(splitView: SplitView, axis: LayoutAxis) =
    if splitView.isNil or splitView.xAxis == axis:
      return
    splitView.xAxis = axis
    splitView.invalidateSplitViewLayout()

  method dividerThickness(splitView: SplitView): float32 =
    if splitView.isNil: 0.0'f32 else: splitView.xDividerThickness

  method setDividerThickness(splitView: SplitView, value: float32) =
    if splitView.isNil or splitView.xDividerThickness == value:
      return
    splitView.xDividerThickness = max(value, 0.0'f32)
    splitView.invalidateSplitViewLayout()

  method autosaveName(splitView: SplitView): string =
    if splitView.isNil: "" else: splitView.xAutosaveName

  method setAutosaveName(splitView: SplitView, name: string) =
    if splitView.isNil or splitView.xAutosaveName == name:
      return
    splitView.xAutosaveName = name

proc `splitAxis=`*(splitView: SplitView, axis: LayoutAxis) =
  splitView.setSplitAxis(axis)

proc `dividerThickness=`*(splitView: SplitView, value: float32) =
  splitView.setDividerThickness(value)

proc `autosaveName=`*(splitView: SplitView, name: string) =
  splitView.setAutosaveName(name)

proc paneMinSize*(splitView: SplitView, index: int): float32 =
  if splitView.isNil or index < 0 or index >= splitView.xPanes.len:
    return 0.0'f32
  splitView.xPanes[index].minSize

proc paneMaxSize*(splitView: SplitView, index: int): float32 =
  if splitView.isNil or index < 0 or index >= splitView.xPanes.len:
    return 0.0'f32
  splitView.xPanes[index].maxSize

proc setPaneSizeLimits*(
    splitView: SplitView, index: int, minSize = 0.0'f32, maxSize = float32.high
) =
  if splitView.isNil or index < 0 or index >= splitView.xPanes.len:
    return
  let
    nextMin = max(minSize, 0.0'f32)
    nextMax = max(maxSize, nextMin)
  if splitView.xPanes[index].minSize == nextMin and
      splitView.xPanes[index].maxSize == nextMax:
    return
  splitView.xPanes[index].minSize = nextMin
  splitView.xPanes[index].maxSize = nextMax
  splitView.invalidateSplitViewLayout()

proc paneCollapsible*(splitView: SplitView, index: int): bool =
  if splitView.isNil or index < 0 or index >= splitView.xPanes.len:
    return false
  splitView.xPanes[index].collapsible

proc `paneCollapsible=`*(splitView: SplitView, index: int, value: bool) =
  if splitView.isNil or index < 0 or index >= splitView.xPanes.len:
    return
  if splitView.xPanes[index].collapsible == value:
    return
  splitView.xPanes[index].collapsible = value

proc isPaneCollapsed*(splitView: SplitView, index: int): bool =
  if splitView.isNil or index < 0 or index >= splitView.xPanes.len:
    return false
  splitView.xPanes[index].collapsed

proc setPaneCollapsed*(splitView: SplitView, index: int, collapsed: bool) =
  if splitView.isNil or index < 0 or index >= splitView.xPanes.len:
    return
  if collapsed and not splitView.xPanes[index].collapsible:
    return
  if splitView.xPanes[index].collapsed == collapsed:
    return
  splitView.xPanes[index].collapsed = collapsed
  splitView.invalidateSplitViewLayout()
  splitView.postAccessibilityNotification(anExpandedChanged)

proc collapsed*(splitView: SplitView, index: int): bool =
  splitView.isPaneCollapsed(index)

proc addPane*(
    splitView: SplitView,
    pane: View,
    minSize = SplitViewDefaultPaneMinSize,
    maxSize = SplitViewDefaultPaneMaxSize,
    collapsible = false,
) =
  if splitView.isNil or pane.isNil:
    return
  let existing = splitView.paneIndex(pane)
  if existing >= 0:
    return
  pane.autoresizingMaskConstraints = false
  splitView.xPanes.add SplitViewPane(
    view: pane,
    minSize: max(minSize, 0.0'f32),
    maxSize: max(maxSize, max(minSize, 0.0'f32)),
    collapsible: collapsible,
    fraction: 1.0'f32,
  )
  if pane.superview != splitView:
    splitView.addSubview(pane)
  splitView.invalidateSplitViewLayout()

proc insertPane*(
    splitView: SplitView,
    pane: View,
    index: int,
    minSize = SplitViewDefaultPaneMinSize,
    maxSize = SplitViewDefaultPaneMaxSize,
    collapsible = false,
) =
  if splitView.isNil or pane.isNil:
    return
  if splitView.paneIndex(pane) >= 0:
    return
  let insertIndex = max(0, min(index, splitView.xPanes.len))
  pane.autoresizingMaskConstraints = false
  splitView.xPanes.insert(
    SplitViewPane(
      view: pane,
      minSize: max(minSize, 0.0'f32),
      maxSize: max(maxSize, max(minSize, 0.0'f32)),
      collapsible: collapsible,
      fraction: 1.0'f32,
    ),
    insertIndex,
  )
  if pane.superview != splitView:
    splitView.addSubview(pane)
  splitView.invalidateSplitViewLayout()

proc removePane*(splitView: SplitView, pane: View) =
  let index = splitView.paneIndex(pane)
  if index < 0:
    return
  splitView.xPanes.delete(index)
  if not pane.isNil and pane.superview == splitView:
    pane.removeFromSuperview()
  splitView.invalidateSplitViewLayout()

proc addArrangedSubview*(splitView: SplitView, pane: View) =
  splitView.addPane(pane)

proc setSplitViewSubviews*(splitView: SplitView, panes: openArray[View]) =
  if splitView.isNil:
    return
  for pane in splitView.panes():
    if not pane.isNil and pane.superview == splitView:
      pane.removeFromSuperview()
  splitView.xPanes.setLen(0)
  for pane in panes:
    splitView.addPane(pane)
  splitView.invalidateSplitViewLayout()

proc dividerRect*(splitView: SplitView, dividerIndex: int): Rect

proc dividerAtPoint*(splitView: SplitView, point: Point): int =
  if splitView.isNil:
    return -1
  for index in 0 ..< splitView.splitDividerCount():
    if splitView.dividerRect(index).contains(point):
      return index
  -1

proc paneLengthFractions(
    splitView: SplitView, visible: openArray[int], storedFractions: openArray[float32]
): seq[float32] =
  if splitView.isNil:
    return
  if visible.len == 0:
    return
  var total = 0.0'f32
  for paneIndex in visible:
    let fraction =
      if paneIndex < storedFractions.len:
        storedFractions[paneIndex]
      else:
        splitView.xPanes[paneIndex].fraction
    total += fraction.normalizedFraction()
  if total <= SplitViewEpsilon:
    let share = 1.0'f32 / float32(visible.len)
    result.setLen(visible.len)
    for index in 0 ..< result.len:
      result[index] = share
  else:
    for paneIndex in visible:
      let fraction =
        if paneIndex < storedFractions.len:
          storedFractions[paneIndex]
        else:
          splitView.xPanes[paneIndex].fraction
      result.add fraction.normalizedFraction() / total

proc redistributeDelta(
    splitView: SplitView,
    visible: openArray[int],
    lengths: var seq[float32],
    beforeVisibleIndex: int,
    delta: float32,
) =
  if splitView.isNil or beforeVisibleIndex < 0 or beforeVisibleIndex + 1 >= visible.len:
    return

  var remaining = delta
  if remaining > 0.0'f32:
    var right = beforeVisibleIndex + 1
    while remaining > SplitViewEpsilon and right < visible.len:
      let
        pane = splitView.xPanes[visible[right]]
        shrink = min(remaining, max(lengths[right] - pane.minSize, 0.0'f32))
      lengths[right] -= shrink
      remaining -= shrink
      inc right
    let consumed = delta - remaining
    var left = beforeVisibleIndex
    var addRemaining = consumed
    while addRemaining > SplitViewEpsilon and left >= 0:
      let
        pane = splitView.xPanes[visible[left]]
        grow = min(addRemaining, max(pane.maxSize - lengths[left], 0.0'f32))
      lengths[left] += grow
      addRemaining -= grow
      dec left
  elif remaining < -SplitViewEpsilon:
    remaining = -remaining
    var left = beforeVisibleIndex
    while remaining > SplitViewEpsilon and left >= 0:
      let
        pane = splitView.xPanes[visible[left]]
        shrink = min(remaining, max(lengths[left] - pane.minSize, 0.0'f32))
      lengths[left] -= shrink
      remaining -= shrink
      dec left
    let consumed = -delta - remaining
    var right = beforeVisibleIndex + 1
    var addRemaining = consumed
    while addRemaining > SplitViewEpsilon and right < visible.len:
      let
        pane = splitView.xPanes[visible[right]]
        grow = min(addRemaining, max(pane.maxSize - lengths[right], 0.0'f32))
      lengths[right] += grow
      addRemaining -= grow
      inc right

proc constrainedPaneLengths(
    splitView: SplitView,
    visible: openArray[int],
    availableLength: float32,
    storedFractions: openArray[float32] = [],
): seq[float32] =
  if visible.len == 0:
    return
  let fractions = splitView.paneLengthFractions(visible, storedFractions)
  for index, paneIndex in visible:
    let
      pane = splitView.xPanes[paneIndex]
      fraction =
        if index < fractions.len:
          fractions[index]
        else:
          1.0'f32 / float32(visible.len)
    result.add min(max(availableLength * fraction, pane.minSize), pane.maxSize)

  var total = 0.0'f32
  for length in result:
    total += length

  var delta = availableLength - total
  if delta > SplitViewEpsilon:
    var adjustable = true
    while delta > SplitViewEpsilon and adjustable:
      adjustable = false
      for index, paneIndex in visible:
        let room = max(splitView.xPanes[paneIndex].maxSize - result[index], 0.0'f32)
        if room > SplitViewEpsilon:
          let grow = min(delta, room)
          result[index] += grow
          delta -= grow
          adjustable = true
          if delta <= SplitViewEpsilon:
            break
  elif delta < -SplitViewEpsilon:
    delta = -delta
    var adjustable = true
    while delta > SplitViewEpsilon and adjustable:
      adjustable = false
      for index in countdown(visible.len - 1, 0):
        let room =
          max(result[index] - splitView.xPanes[visible[index]].minSize, 0.0'f32)
        if room > SplitViewEpsilon:
          let shrink = min(delta, room)
          result[index] -= shrink
          delta -= shrink
          adjustable = true
          if delta <= SplitViewEpsilon:
            break

proc saveFractionsFromLengths(
    splitView: SplitView, visible: openArray[int], lengths: openArray[float32]
) =
  var total = 0.0'f32
  for length in lengths:
    total += length
  if total <= SplitViewEpsilon:
    return
  for index, paneIndex in visible:
    splitView.xPanes[paneIndex].fraction = max(lengths[index] / total, 0.0'f32)

proc layoutSplitViewPanes(splitView: SplitView) =
  if splitView.isNil:
    return

  splitView.discardCursorRects()
  let
    visible = splitView.visiblePaneIndexes()
    availableLength = splitView.availablePaneLength()
    lengths = splitView.constrainedPaneLengths(visible, availableLength)
    axis = splitView.xAxis
    bounds = splitView.bounds()
    dividerThickness = splitView.effectiveDividerThickness()
    crossLength = bounds.size.crossSize(axis)

  var cursor = bounds.mainOrigin(axis)
  for visibleIndex, paneIndex in visible:
    let
      pane = splitView.xPanes[paneIndex].view
      length =
        if visibleIndex < lengths.len:
          lengths[visibleIndex]
        else:
          0.0'f32
    pane.applyLayoutFrame(
      initSplitRect(axis, cursor, 0.0'f32, length, crossLength), lfoContainer
    )
    cursor += length
    if visibleIndex < visible.len - 1:
      let divider = initSplitRect(axis, cursor, 0.0'f32, dividerThickness, crossLength)
      splitView.addCursorRect(
        divider, if axis == laHorizontal: "resize-left-right" else: "resize-up-down"
      )
      cursor += dividerThickness

  for index, pane in splitView.xPanes:
    if index notin visible and not pane.view.isNil and pane.view.superview == splitView:
      pane.view.applyLayoutFrame(
        initSplitRect(axis, bounds.mainOrigin(axis), 0.0'f32, 0.0'f32, crossLength),
        lfoContainer,
      )

proc dividerRect*(splitView: SplitView, dividerIndex: int): Rect =
  if splitView.isNil or dividerIndex < 0:
    return rect(0.0, 0.0, 0.0, 0.0)
  let
    visible = splitView.visiblePaneIndexes()
    availableLength = splitView.availablePaneLength()
    lengths = splitView.constrainedPaneLengths(visible, availableLength)
  if dividerIndex >= visible.len - 1:
    return rect(0.0, 0.0, 0.0, 0.0)

  var cursor = splitView.bounds().mainOrigin(splitView.xAxis)
  for index in 0 .. dividerIndex:
    cursor += lengths[index]
    if index < dividerIndex:
      cursor += splitView.effectiveDividerThickness()

  initSplitRect(
    splitView.xAxis,
    cursor,
    0.0'f32,
    splitView.effectiveDividerThickness(),
    splitView.bounds().size.crossSize(splitView.xAxis),
  )

proc setPositionOfDivider*(splitView: SplitView, dividerIndex: int, position: float32) =
  if splitView.isNil:
    return
  let
    visible = splitView.visiblePaneIndexes()
    availableLength = splitView.availablePaneLength()
  if dividerIndex < 0 or dividerIndex >= visible.len - 1:
    return
  var lengths = splitView.constrainedPaneLengths(visible, availableLength)
  var current = 0.0'f32
  for index in 0 .. dividerIndex:
    current += lengths[index]
    if index < dividerIndex:
      current += splitView.effectiveDividerThickness()
  if abs(position - current) <= SplitViewEpsilon:
    return
  let target =
    SplitDividerTransactionTarget(splitView: splitView, dividerIndex: dividerIndex)
  discard target.withProtocol(SplitDividerTransactionAnim)
  discard recordPropertyAnimation(
    DynamicAgent(target), animSplitDividerPosition(), current, position
  )
  splitView.redistributeDelta(visible, lengths, dividerIndex, position - current)
  splitView.saveFractionsFromLengths(visible, lengths)
  splitView.invalidateSplitViewLayout()

proc positionOfDivider*(splitView: SplitView, dividerIndex: int): float32 =
  if splitView.isNil or dividerIndex < 0:
    return 0.0'f32
  splitView.dividerRect(dividerIndex).mainOrigin(splitView.xAxis)

proc captureState*(splitView: SplitView): SplitViewState =
  if splitView.isNil:
    return
  for pane in splitView.xPanes:
    result.fractions.add pane.fraction
    result.collapsed.add pane.collapsed

proc restoreState*(splitView: SplitView, state: SplitViewState) =
  if splitView.isNil:
    return
  let previousCollapsed = splitView.captureState().collapsed
  for index in 0 ..< splitView.xPanes.len:
    if index < state.fractions.len:
      splitView.xPanes[index].fraction = state.fractions[index].normalizedFraction()
    if index < state.collapsed.len:
      splitView.xPanes[index].collapsed =
        state.collapsed[index] and splitView.xPanes[index].collapsible
  splitView.invalidateSplitViewLayout()
  if splitView.captureState().collapsed != previousCollapsed:
    splitView.postAccessibilityNotification(anExpandedChanged)

proc autosaveString*(state: SplitViewState): string =
  var parts: seq[string]
  for fraction in state.fractions:
    parts.add $fraction
  result = parts.join(",")
  result.add "|"
  parts.setLen(0)
  for collapsed in state.collapsed:
    parts.add(if collapsed: "1" else: "0")
  result.add parts.join(",")

proc restoreSplitViewState*(value: string): SplitViewState =
  let sections = value.split("|")
  if sections.len > 0 and sections[0].len > 0:
    for part in sections[0].split(","):
      try:
        result.fractions.add parseFloat(part).float32
      except ValueError:
        result.fractions.add 0.0'f32
  if sections.len > 1 and sections[1].len > 0:
    for part in sections[1].split(","):
      result.collapsed.add part == "1" or part == "true"

proc autosaveString*(splitView: SplitView): string =
  splitView.captureState().autosaveString()

proc restoreAutosaveString*(splitView: SplitView, value: string) =
  splitView.restoreState(restoreSplitViewState(value))

proc splitViewNaturalSize(splitView: SplitView): Size =
  if splitView.isNil:
    return initSize(0.0, 0.0)
  let
    axis = splitView.xAxis
    dividerThickness = splitView.effectiveDividerThickness()
  var
    main = 0.0'f32
    cross = 0.0'f32
    visibleCount = 0
  for pane in splitView.xPanes:
    if pane.view.isNil or pane.view.isHidden or pane.collapsed:
      continue
    let size = pane.view.sizeThatFits(UnconstrainedFittingSize)
    main += max(size.mainSize(axis), pane.minSize)
    cross = max(cross, size.crossSize(axis))
    inc visibleCount
  main += dividerThickness * float32(max(visibleCount - 1, 0))
  case axis
  of laHorizontal:
    initSize(main, cross)
  of laVertical:
    initSize(cross, main)

proc intrinsicContentSize*(splitView: SplitView): IntrinsicSize =
  if splitView.isNil:
    NoIntrinsicContentSize
  else:
    initIntrinsicSize(splitView.splitViewNaturalSize())

proc drawSplitViewDividers(splitView: SplitView, context: DrawContext) =
  if splitView.isNil or context.isNil:
    return
  let style =
    context.appearance.resolveSplitViewStyle(splitView.splitViewStyleContext())
  for index in 0 ..< splitView.splitDividerCount():
    let rect = splitView.dividerRect(index)
    if rect.isEmpty:
      continue
    discard context.addRenderRectangle(
      context.renderRectFor(rect),
      style.divider.fill,
      style.divider.borderColor,
      style.divider.borderWidth,
      style.divider.cornerRadius,
      style.divider.shadows,
      cornerRadii = style.divider.cornerRadii,
    )
    let
      markLength = min(max(style.dividerThickness * 0.45'f32, 2.0'f32), 4.0'f32)
      markInset = max((style.dividerThickness - markLength) / 2.0'f32, 0.0'f32)
      markRect =
        if splitView.xAxis == laHorizontal:
          rect(
            rect.origin.x + markInset,
            rect.origin.y + 4.0'f32,
            markLength,
            max(rect.size.height - 8.0'f32, 0.0'f32),
          )
        else:
          rect(
            rect.origin.x + 4.0'f32,
            rect.origin.y + markInset,
            max(rect.size.width - 8.0'f32, 0.0'f32),
            markLength,
          )
    if not markRect.isEmpty:
      discard context.addRenderRectangle(
        context.renderRectFor(markRect),
        fill(style.divider.borderColor),
        style.divider.borderColor,
        0.0'f32,
        style.divider.cornerRadius,
      )

protocol DefaultSplitViewLayout of ViewLayoutProtocol:
  method layoutIntrinsicContentSize(splitView: SplitView): IntrinsicSize =
    splitView.intrinsicContentSize()

  method layoutSubviews(splitView: SplitView) =
    splitView.layoutSplitViewPanes()

protocol DefaultSplitViewDrawing of ViewDrawingProtocol:
  method draw(splitView: SplitView, context: DrawContext) =
    if splitView.isNil or context.isNil or splitView.bounds().isEmpty:
      return
    splitView.drawSplitViewDividers(context)

protocol DefaultSplitViewEvents of ResponderEventProtocol:
  method mouseDown(splitView: SplitView, event: MouseEvent): bool =
    if splitView.isNil or event.button != mbPrimary:
      return false
    let divider = splitView.dividerAtPoint(event.location)
    if divider < 0:
      return false
    splitView.xDragDivider = divider
    splitView.xDragStartMain = event.location.mainPoint(splitView.xAxis)
    splitView.xDragInitialFractions.setLen(0)
    for pane in splitView.xPanes:
      splitView.xDragInitialFractions.add pane.fraction
    true

  method mouseDragged(splitView: SplitView, event: MouseEvent): bool =
    if splitView.isNil or event.button != mbPrimary or splitView.xDragDivider < 0:
      return false
    let
      visible = splitView.visiblePaneIndexes()
      availableLength = splitView.availablePaneLength()
    var lengths = splitView.constrainedPaneLengths(
      visible, availableLength, splitView.xDragInitialFractions
    )
    if splitView.xDragDivider >= visible.len - 1:
      return false
    let delta = event.location.mainPoint(splitView.xAxis) - splitView.xDragStartMain
    splitView.redistributeDelta(visible, lengths, splitView.xDragDivider, delta)
    splitView.saveFractionsFromLengths(visible, lengths)
    splitView.setNeedsLayout()
    splitView.setNeedsDisplay(true)
    true

  method mouseUp(splitView: SplitView, event: MouseEvent): bool =
    if splitView.isNil or event.button != mbPrimary or splitView.xDragDivider < 0:
      return false
    discard splitView.mouseDragged(event)
    splitView.xDragDivider = -1
    true

protocol DefaultSplitViewAccessibility of AccessibilityProtocol:
  method accessibilityRole(splitView: SplitView): AccessibilityRole =
    if splitView.xHasAccessibilityRole: splitView.xAccessibilityRole else: arGroup

  method accessibilityLabel(splitView: SplitView): string =
    if splitView.xAccessibilityLabel.len > 0:
      splitView.xAccessibilityLabel
    else:
      splitView.xIdentifier

  method isAccessibilityElement(splitView: SplitView): bool =
    false

  method accessibilityChildren(splitView: SplitView): seq[View] =
    for pane in splitView.xPanes:
      if pane.view.isNil or pane.collapsed or pane.view.isAccessibilityIgnored():
        continue
      if pane.view.isAccessibilityElement():
        result.add pane.view
      else:
        result.add pane.view.accessibilityChildren()

protocol SplitViewLifecycleSlots of ViewLifecycleProtocol:
  proc willRemoveSubview(splitView: SplitView, child: View) {.slot.} =
    let index = splitView.paneIndex(child)
    if index >= 0:
      splitView.xPanes.delete(index)
      splitView.invalidateSplitViewLayout()

proc initSplitViewFields*(
    splitView: SplitView, axis = laHorizontal, frame: Rect = AutoRect
) =
  initViewFields(splitView, frame)
  splitView.background = color(0.0, 0.0, 0.0, 0.0)
  splitView.xAxis = axis
  splitView.xDragDivider = -1
  discard splitView.withProto()
  discard splitView.withProtocol(DefaultSplitViewLayout)
  discard splitView.withProtocol(DefaultSplitViewDrawing)
  discard DynamicAgent(splitView).pushMethods(DefaultSplitViewEvents.init())
  discard splitView.withProtocol(DefaultSplitViewAccessibility)
  discard splitView.withProtocol(SplitViewLifecycleSlots)
  splitView.observeProtocol(splitView, SplitViewLifecycleSlots)
  splitView.applyInitialFrame(frame)

proc newSplitView*(axis = laHorizontal, frame: Rect = AutoRect): SplitView =
  result = SplitView()
  initSplitViewFields(result, axis, frame)

proc newHorizontalSplitView*(frame: Rect = AutoRect): SplitView =
  newSplitView(laHorizontal, frame)

proc newVerticalSplitView*(frame: Rect = AutoRect): SplitView =
  newSplitView(laVertical, frame)
