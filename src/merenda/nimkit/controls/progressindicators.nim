import std/math

import ../app/animations
import ../accessibility/accessibility
import ../drawing
import ../foundation/selectors
import ../foundation/types
import ../themes
import ./controls

export controls

type
  ProgressIndicatorStyle* = enum
    pisBar
    pisSpinning

  ProgressIndicator* = ref object of Control
    xMinValue: float32
    xMaxValue: float32
    xValue: float32
    xIndeterminate: bool
    xAnimating: bool
    xDisplayedWhenStopped: bool
    xAnimationPhase: float32
    xStyle: ProgressIndicatorStyle

  ProgressIndicatorCell* = ref object of Cell

proc normalizedRange(indicator: ProgressIndicator): tuple[minValue, maxValue: float32] =
  if indicator.xMaxValue > indicator.xMinValue:
    (indicator.xMinValue, indicator.xMaxValue)
  else:
    (indicator.xMaxValue, indicator.xMinValue)

proc normalizedValue(indicator: ProgressIndicator, value: float32): float32 =
  let range = indicator.normalizedRange()
  min(max(value, range.minValue), range.maxValue)

proc progressFraction(indicator: ProgressIndicator): float32 =
  let range = indicator.normalizedRange()
  if range.maxValue <= range.minValue:
    return 0.0'f32
  (indicator.xValue - range.minValue) / (range.maxValue - range.minValue)

proc setProgressValue(indicator: ProgressIndicator, value: float32) =
  if indicator.isNil:
    return
  let nextValue = indicator.normalizedValue(value)
  if indicator.xValue == nextValue:
    return
  indicator.xValue = nextValue
  indicator.setNeedsDisplay(true)
  indicator.postAccessibilityNotification(anValueChanged)

proc progressStyleContext(indicator: ProgressIndicator): StyleContext =
  if indicator.isNil:
    return controlStyle(srProgressIndicator)
  controlStyle(
    srProgressIndicator,
    indicator.widgetStateSet(),
    id = indicator.styleId,
    classes = indicator.styleClasses,
  )

proc progressStyle(cell: ProgressIndicatorCell): SliderStyle =
  let view = cell.controlView()
  if view of ProgressIndicator:
    return view.effectiveAppearance().resolveProgressIndicatorStyle(
        ProgressIndicator(view).progressStyleContext()
      )
  initAppearance().resolveProgressIndicatorStyle(controlStyle(srProgressIndicator))

proc progressStyle(
    indicator: ProgressIndicator, context: DrawContext = nil
): SliderStyle =
  if not context.isNil:
    return
      context.appearance.resolveProgressIndicatorStyle(indicator.progressStyleContext())
  indicator.effectiveAppearance().resolveProgressIndicatorStyle(
    indicator.progressStyleContext()
  )

proc barTrackRect(indicator: ProgressIndicator, style: SliderStyle): Rect =
  let
    bounds = indicator.bounds()
    height = min(bounds.size.height, max(style.trackHeight, 1.0'f32))
  rect(
    bounds.origin.x,
    bounds.origin.y + (bounds.size.height - height) * 0.5'f32,
    bounds.size.width,
    height,
  )

proc spinnerRect(indicator: ProgressIndicator, style: SliderStyle): Rect =
  let
    bounds = indicator.bounds()
    side = min(
      min(bounds.size.width, bounds.size.height),
      max(style.minSize.height, style.knobSize),
    )
  rect(
    bounds.origin.x + (bounds.size.width - side) * 0.5'f32,
    bounds.origin.y + (bounds.size.height - side) * 0.5'f32,
    side,
    side,
  )

proc progressCellSize(cell: ProgressIndicatorCell, style: SliderStyle): Size =
  let view = cell.controlView()
  if view of ProgressIndicator and ProgressIndicator(view).xStyle == pisSpinning:
    let side = max(style.minSize.height, style.knobSize)
    return initSize(side, side)
  style.minSize

proc progressIndicatorCell*(indicator: ProgressIndicator): ProgressIndicatorCell =
  let controlCell = indicator.cell()
  if controlCell of ProgressIndicatorCell:
    return ProgressIndicatorCell(controlCell)

protocol ProgressProtocol {.selectorScope: protocol.} from ProgressIndicator:
  property value -> float32
  property minValue -> float32
  property maxValue -> float32
  property indeterminate -> bool
  property displayedWhenStopped -> bool
  property progressIndicatorStyle -> ProgressIndicatorStyle
  property animationPhase -> float32

  method value(indicator: ProgressIndicator): float32 =
    if indicator.isNil: 0.0'f32 else: indicator.xValue

  method setValue(indicator: ProgressIndicator, value: float32) =
    if indicator.isNil:
      return
    let nextValue = indicator.normalizedValue(value)
    if indicator.xValue == nextValue:
      return
    discard recordPropertyAnimation(
      DynamicAgent(indicator), setValue(), indicator.xValue, nextValue
    )
    indicator.setProgressValue(nextValue)

  method minValue(indicator: ProgressIndicator): float32 =
    if indicator.isNil: 0.0'f32 else: indicator.xMinValue

  method setMinValue(indicator: ProgressIndicator, value: float32) =
    if indicator.isNil or indicator.xMinValue == value:
      return
    indicator.xMinValue = value
    indicator.setProgressValue(indicator.xValue)
    indicator.setNeedsDisplay(true)

  method maxValue(indicator: ProgressIndicator): float32 =
    if indicator.isNil: 0.0'f32 else: indicator.xMaxValue

  method setMaxValue(indicator: ProgressIndicator, value: float32) =
    if indicator.isNil or indicator.xMaxValue == value:
      return
    indicator.xMaxValue = value
    indicator.setProgressValue(indicator.xValue)
    indicator.setNeedsDisplay(true)

  method indeterminate(indicator: ProgressIndicator): bool =
    (not indicator.isNil) and indicator.xIndeterminate

  method setIndeterminate(indicator: ProgressIndicator, value: bool) =
    if indicator.isNil or indicator.xIndeterminate == value:
      return
    indicator.xIndeterminate = value
    indicator.setNeedsDisplay(true)
    indicator.postAccessibilityNotification(anValueChanged)

  method animating*(indicator: ProgressIndicator): bool =
    (not indicator.isNil) and indicator.xAnimating

  method displayedWhenStopped(indicator: ProgressIndicator): bool =
    indicator.isNil or indicator.xDisplayedWhenStopped

  method setDisplayedWhenStopped(indicator: ProgressIndicator, value: bool) =
    if indicator.isNil or indicator.xDisplayedWhenStopped == value:
      return
    indicator.xDisplayedWhenStopped = value
    indicator.setNeedsDisplay(true)

  method progressIndicatorStyle(indicator: ProgressIndicator): ProgressIndicatorStyle =
    if indicator.isNil: pisBar else: indicator.xStyle

  method setProgressIndicatorStyle(
      indicator: ProgressIndicator, style: ProgressIndicatorStyle
  ) =
    if indicator.isNil or indicator.xStyle == style:
      return
    indicator.xStyle = style
    indicator.invalidateIntrinsicContentSize()
    indicator.setNeedsDisplay(true)

  method animationPhase(indicator: ProgressIndicator): float32 =
    if indicator.isNil: 0.0'f32 else: indicator.xAnimationPhase

  method setAnimationPhase(indicator: ProgressIndicator, phase: float32) =
    if indicator.isNil:
      return
    let nextPhase = phase - floor(phase)
    if indicator.xAnimationPhase == nextPhase:
      return
    indicator.xAnimationPhase = nextPhase
    indicator.setNeedsDisplay(true)

  method startAnimation*(indicator: ProgressIndicator) =
    if indicator.isNil or indicator.xAnimating:
      return
    indicator.xAnimating = true
    indicator.setWidgetState(ssActive, true)
    indicator.setNeedsDisplay(true)

  method stopAnimation*(indicator: ProgressIndicator) =
    if indicator.isNil or not indicator.xAnimating:
      return
    indicator.xAnimating = false
    indicator.setWidgetState(ssActive, false)
    indicator.setNeedsDisplay(true)

  method stepAnimation*(indicator: ProgressIndicator) =
    if not indicator.isNil:
      indicator.setAnimationPhase(indicator.animationPhase + 1.0'f32 / 12.0'f32)

  method incrementBy*(indicator: ProgressIndicator, amount: float32) =
    if not indicator.isNil:
      indicator.setValue(indicator.value + amount)

proc stepAnimation*(indicator: ProgressIndicator, delta: float32) =
  if not indicator.isNil:
    indicator.setAnimationPhase(indicator.animationPhase + delta)

proc `value=`*(indicator: ProgressIndicator, value: float32) =
  indicator.setValue(value)

proc `minValue=`*(indicator: ProgressIndicator, value: float32) =
  indicator.setMinValue(value)

proc `maxValue=`*(indicator: ProgressIndicator, value: float32) =
  indicator.setMaxValue(value)

proc `indeterminate=`*(indicator: ProgressIndicator, value: bool) =
  indicator.setIndeterminate(value)

proc `displayedWhenStopped=`*(indicator: ProgressIndicator, value: bool) =
  indicator.setDisplayedWhenStopped(value)

proc `progressIndicatorStyle=`*(
    indicator: ProgressIndicator, style: ProgressIndicatorStyle
) =
  indicator.setProgressIndicatorStyle(style)

proc `animationPhase=`*(indicator: ProgressIndicator, phase: float32) =
  indicator.setAnimationPhase(phase)

protocol DefaultProgressIndicatorCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: ProgressIndicatorCell): IntrinsicSize =
    initIntrinsicSize(cell.progressCellSize(cell.progressStyle()))

  method cellSizeForBounds(cell: ProgressIndicatorCell, bounds: Rect): Size =
    let size = cell.progressCellSize(cell.progressStyle())
    initSize(max(bounds.size.width, size.width), size.height)

proc initProgressIndicatorCellFields*(cell: ProgressIndicatorCell) =
  initCellFields(cell)
  discard cell.withProtocol(DefaultProgressIndicatorCellMeasurement)

proc newProgressIndicatorCell*(): ProgressIndicatorCell =
  result = ProgressIndicatorCell()
  initProgressIndicatorCellFields(result)

proc progressChromeStates(indicator: ProgressIndicator): set[WidgetState] =
  result = indicator.widgetStateSet()
  if indicator.animating:
    result.incl ssActive

proc drawProgressTrack(
    indicator: ProgressIndicator,
    context: DrawContext,
    rect: Rect,
    part: ChromePart,
    box: ControlBoxStyle,
    style: SliderStyle,
) =
  if rect.isEmpty:
    return
  let
    frame = context.renderRectFor(rect)
    radius = rect.size.height * 0.5'f32
    chrome = chromeContext(
      style.chrome, crSliderTrack, part, box.fill, indicator.progressChromeStates()
    )
    trackRoot = context.addRenderRectangle(
      frame,
      context.appearance.chromeFill(chrome),
      box.borderColor,
      box.borderWidth,
      radius,
      box.shadows,
      lightMaskContent = true,
    )
  context.drawChromeExtras(
    chrome, initChromeExtras(trackRoot, frame, cornerRadius = radius)
  )

proc drawDeterminateBar(
    indicator: ProgressIndicator, context: DrawContext, track: Rect, style: SliderStyle
) =
  let fillRect = rect(
    track.origin.x,
    track.origin.y,
    track.size.width * indicator.progressFraction(),
    track.size.height,
  )
  indicator.drawProgressTrack(context, track, cpFace, style.track, style)
  if fillRect.size.width > 0.0'f32:
    indicator.drawProgressTrack(
      context, fillRect, cpHighlight, style.activeTrack, style
    )

proc drawIndeterminateBar(
    indicator: ProgressIndicator, context: DrawContext, track: Rect, style: SliderStyle
) =
  indicator.drawProgressTrack(context, track, cpFace, style.track, style)
  if not indicator.animating:
    return
  let
    phase = indicator.animationPhase
    segmentWidth = max(track.size.width * 0.35'f32, track.size.height * 2.0'f32)
    travel = track.size.width + segmentWidth
    rawX = track.origin.x + phase * travel - segmentWidth
    x1 = max(track.origin.x, rawX)
    x2 = min(track.maxX, rawX + segmentWidth)
  if x2 > x1:
    indicator.drawProgressTrack(
      context,
      rect(x1, track.origin.y, x2 - x1, track.size.height),
      cpHighlight,
      style.activeTrack,
      style,
    )

proc spinnerColor(style: SliderStyle, alpha: float32): Color =
  let color = style.activeTrack.borderColor
  color(color.r, color.g, color.b, color.a * alpha)

proc drawSpinner(
    indicator: ProgressIndicator, context: DrawContext, rect: Rect, style: SliderStyle
) =
  if rect.isEmpty or (not indicator.animating and not indicator.displayedWhenStopped):
    return
  let
    center = initPoint(
      rect.origin.x + rect.size.width * 0.5'f32,
      rect.origin.y + rect.size.height * 0.5'f32,
    )
    orbit = rect.size.width * 0.34'f32
    dotRadius = max(rect.size.width * 0.055'f32, 1.0'f32)
    phaseOffset = int(floor(indicator.animationPhase * 12.0'f32)) mod 12
  for index in 0 ..< 12:
    let
      dotIndex = (index + phaseOffset) mod 12
      angle = (float32(index) / 12.0'f32) * 2.0'f32 * PI.float32
      alpha = 0.18'f32 + 0.82'f32 * (float32(dotIndex + 1) / 12.0'f32)
      point = initPoint(center.x + cos(angle) * orbit, center.y + sin(angle) * orbit)
    discard context.addRenderCircle(point, fill(spinnerColor(style, alpha)), dotRadius)

protocol DefaultProgressIndicatorDrawing of ViewDrawingProtocol:
  method draw(indicator: ProgressIndicator, context: DrawContext) =
    if not indicator.displayedWhenStopped and not indicator.animating:
      return
    let style = indicator.progressStyle(context)
    case indicator.progressIndicatorStyle
    of pisBar:
      let track = indicator.barTrackRect(style)
      if indicator.indeterminate:
        indicator.drawIndeterminateBar(context, track, style)
      else:
        indicator.drawDeterminateBar(context, track, style)
    of pisSpinning:
      indicator.drawSpinner(context, indicator.spinnerRect(style), style)

protocol DefaultProgressIndicatorAccessibility of AccessibilityProtocol:
  method accessibilityRole(indicator: ProgressIndicator): AccessibilityRole =
    arProgressIndicator

  method accessibilityLabel(indicator: ProgressIndicator): string =
    if indicator.xAccessibilityLabel.len > 0:
      indicator.xAccessibilityLabel
    else:
      "progress"

  method accessibilityValue(indicator: ProgressIndicator): string =
    if indicator.indeterminate:
      "indeterminate"
    else:
      $indicator.value

  method accessibilityTraits(indicator: ProgressIndicator): AccessibilityTraits =
    result = indicator.xAccessibilityTraits
    if not indicator.isEnabled():
      result.incl atDisabled

  method isAccessibilityElement(indicator: ProgressIndicator): bool =
    true

proc initProgressIndicatorFields*(
    indicator: ProgressIndicator,
    minValue = 0.0'f32,
    maxValue = 1.0'f32,
    value = 0.0'f32,
    frame: Rect = AutoRect,
) =
  initControlFields(indicator, frame, newProgressIndicatorCell())
  indicator.xMinValue = minValue
  indicator.xMaxValue = maxValue
  indicator.xValue = indicator.normalizedValue(value)
  indicator.xDisplayedWhenStopped = true
  indicator.xStyle = pisBar
  indicator.setHuggingPriority(LayoutPriorityLow, laHorizontal)
  indicator.setCompressionPriority(LayoutPriorityHigh, laHorizontal)
  discard indicator.withProto()
  discard indicator.withProtocol(DefaultProgressIndicatorDrawing)
  discard indicator.withProtocol(DefaultProgressIndicatorAccessibility)
  indicator.applyInitialFrame(frame)

proc newProgressIndicator*(
    minValue = 0.0'f32, maxValue = 1.0'f32, value = 0.0'f32, frame: Rect = AutoRect
): ProgressIndicator =
  result = ProgressIndicator()
  initProgressIndicatorFields(result, minValue, maxValue, value, frame)
