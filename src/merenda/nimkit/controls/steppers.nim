import std/[strutils, times]

import ../accessibility/accessibility
import ../drawing
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../themes
import ./controls

export controls

type
  StepperPart* = enum
    spNone
    spDecrement
    spIncrement

  StepperValueFormatter* = proc(value: float32): string {.closure.}

  Stepper* = ref object of Control
    xMinValue: float32
    xMaxValue: float32
    xValue: float32
    xIncrement: float32
    xWraps: bool
    xPressedPart: StepperPart
    xRepeatPart: StepperPart
    xRepeatCount: Natural
    xRepeatStartedAt: float
    xLastRepeatAt: float
    xValueFormatter: StepperValueFormatter

  StepperCell* = ref object of ActionCell

const
  StepperInitialRepeatDelaySeconds* = 0.35
  StepperRepeatIntervalSeconds* = 0.08

proc repeatTimestamp(timestamp: float): float =
  if timestamp > 0.0:
    timestamp
  else:
    epochTime()

func stepperRange(stepper: Stepper): tuple[minValue, maxValue: float32] =
  if stepper.xMaxValue > stepper.xMinValue:
    (stepper.xMinValue, stepper.xMaxValue)
  else:
    (stepper.xMaxValue, stepper.xMinValue)

func clampedValue(stepper: Stepper, value: float32): float32 =
  let range = stepper.stepperRange()
  min(max(value, range.minValue), range.maxValue)

func wrappedStepValue(stepper: Stepper, value: float32): float32 =
  let range = stepper.stepperRange()
  if range.maxValue <= range.minValue:
    return range.minValue
  if value > range.maxValue:
    range.minValue
  elif value < range.minValue:
    range.maxValue
  else:
    value

func normalizedStepValue(stepper: Stepper, value: float32): float32 =
  if stepper.xWraps:
    stepper.wrappedStepValue(value)
  else:
    stepper.clampedValue(value)

func defaultStepperValueFormat(value: float32): string =
  formatFloat(value, ffDefault, -1)

proc setStepperValue(stepper: Stepper, value: float32, notify = false): bool =
  if stepper.isNil:
    return false
  let nextValue = stepper.clampedValue(value)
  if stepper.xValue == nextValue:
    return false
  stepper.xValue = nextValue
  Control(stepper).setObjectValue(toObjectValue(nextValue))
  stepper.setNeedsDisplay(true)
  stepper.postAccessibilityNotification(anValueChanged)
  if notify:
    discard stepper.sendAction()
  true

proc stepBy*(stepper: Stepper, delta: float32, notify = true): bool =
  if stepper.isNil or delta == 0.0'f32:
    return false
  let nextValue = stepper.normalizedStepValue(stepper.xValue + delta)
  stepper.setStepperValue(nextValue, notify)

proc incrementValue*(stepper: Stepper, notify = true): bool =
  if stepper.isNil or stepper.xIncrement <= 0.0'f32:
    return false
  stepper.stepBy(stepper.xIncrement, notify)

proc decrementValue*(stepper: Stepper, notify = true): bool =
  if stepper.isNil or stepper.xIncrement <= 0.0'f32:
    return false
  stepper.stepBy(-stepper.xIncrement, notify)

proc performPart(stepper: Stepper, part: StepperPart, notify = true): bool =
  case part
  of spIncrement:
    stepper.incrementValue(notify)
  of spDecrement:
    stepper.decrementValue(notify)
  of spNone:
    false

proc beginRepeat*(
    stepper: Stepper, part: StepperPart, timestamp = 0.0, notify = true
): bool =
  if stepper.isNil or part == spNone:
    return false
  let now = repeatTimestamp(timestamp)
  stepper.xPressedPart = part
  stepper.xRepeatPart = part
  stepper.xRepeatCount = 1
  stepper.xRepeatStartedAt = now
  stepper.xLastRepeatAt = now
  stepper.setNeedsDisplay(true)
  stepper.performPart(part, notify)

proc continueRepeat*(stepper: Stepper, timestamp = 0.0, notify = true): bool =
  if stepper.isNil or stepper.xRepeatPart == spNone or
      stepper.xPressedPart != stepper.xRepeatPart:
    return false
  let now = repeatTimestamp(timestamp)
  inc stepper.xRepeatCount
  stepper.xLastRepeatAt = now
  stepper.performPart(stepper.xRepeatPart, notify)

proc repeatTick*(stepper: Stepper, timestamp = 0.0, notify = true): bool =
  if stepper.isNil or stepper.xRepeatPart == spNone or
      stepper.xPressedPart != stepper.xRepeatPart:
    return false
  let
    now = repeatTimestamp(timestamp)
    delay =
      if stepper.xRepeatCount <= 1:
        StepperInitialRepeatDelaySeconds
      else:
        StepperRepeatIntervalSeconds
  if now - stepper.xLastRepeatAt < delay:
    return false
  stepper.continueRepeat(now, notify)

proc endRepeat*(stepper: Stepper) =
  if stepper.isNil:
    return
  if stepper.xPressedPart == spNone and stepper.xRepeatPart == spNone:
    return
  stepper.xPressedPart = spNone
  stepper.xRepeatPart = spNone
  stepper.setNeedsDisplay(true)

proc value*(stepper: Stepper): float32 =
  if stepper.isNil: 0.0'f32 else: stepper.xValue

proc `value=`*(stepper: Stepper, value: float32) =
  discard stepper.setStepperValue(value)

proc setObjectValue*(stepper: Stepper, value: ObjectValue, notify = false) =
  if stepper.isNil:
    return
  try:
    discard stepper.setStepperValue(value.requireNumber().float32, notify)
  except ObjectValueError:
    discard Control(stepper).rejectObjectValueEdit(
        initObjectValidationError(
          oveTypeMismatch,
          message = getCurrentExceptionMsg(),
          expectedKind = ovFloat,
          actualKind = value.kind,
        )
      )

proc `objectValue=`*(stepper: Stepper, value: ObjectValue) =
  stepper.setObjectValue(value)

proc minValue*(stepper: Stepper): float32 =
  if stepper.isNil: 0.0'f32 else: stepper.xMinValue

proc `minValue=`*(stepper: Stepper, value: float32) =
  if stepper.isNil or stepper.xMinValue == value:
    return
  stepper.xMinValue = value
  discard stepper.setStepperValue(stepper.xValue)
  stepper.setNeedsDisplay(true)

proc maxValue*(stepper: Stepper): float32 =
  if stepper.isNil: 0.0'f32 else: stepper.xMaxValue

proc `maxValue=`*(stepper: Stepper, value: float32) =
  if stepper.isNil or stepper.xMaxValue == value:
    return
  stepper.xMaxValue = value
  discard stepper.setStepperValue(stepper.xValue)
  stepper.setNeedsDisplay(true)

proc increment*(stepper: Stepper): float32 =
  if stepper.isNil: 0.0'f32 else: stepper.xIncrement

proc `increment=`*(stepper: Stepper, value: float32) =
  if stepper.isNil:
    return
  let nextValue = max(value, 0.0'f32)
  if stepper.xIncrement == nextValue:
    return
  stepper.xIncrement = nextValue

proc wraps*(stepper: Stepper): bool =
  (not stepper.isNil) and stepper.xWraps

proc `wraps=`*(stepper: Stepper, value: bool) =
  if stepper.isNil or stepper.xWraps == value:
    return
  stepper.xWraps = value

proc pressedPart*(stepper: Stepper): StepperPart =
  if stepper.isNil: spNone else: stepper.xPressedPart

proc repeatPart*(stepper: Stepper): StepperPart =
  if stepper.isNil: spNone else: stepper.xRepeatPart

proc repeatActive*(stepper: Stepper): bool =
  (not stepper.isNil) and stepper.xRepeatPart != spNone

proc repeatCount*(stepper: Stepper): Natural =
  if stepper.isNil: 0 else: stepper.xRepeatCount

proc repeatStartedAt*(stepper: Stepper): float =
  if stepper.isNil: 0.0 else: stepper.xRepeatStartedAt

proc lastRepeatAt*(stepper: Stepper): float =
  if stepper.isNil: 0.0 else: stepper.xLastRepeatAt

proc valueFormatter*(stepper: Stepper): StepperValueFormatter =
  if stepper.isNil: nil else: stepper.xValueFormatter

proc `valueFormatter=`*(stepper: Stepper, formatter: StepperValueFormatter) =
  if not stepper.isNil:
    stepper.xValueFormatter = formatter

proc formatValue*(stepper: Stepper, value: float32): string =
  if not stepper.isNil and not stepper.xValueFormatter.isNil:
    return stepper.xValueFormatter(value)
  if not stepper.isNil:
    return Control(stepper).formatObjectValue(toObjectValue(value), ovrStepper)
  defaultStepperValueFormat(value)

proc formattedValue*(stepper: Stepper): string =
  if stepper.isNil:
    ""
  else:
    stepper.formatValue(stepper.xValue)

func decrementPartRect(bounds: Rect): Rect =
  initRect(
    bounds.origin.x, bounds.origin.y, bounds.size.width * 0.5'f32, bounds.size.height
  )

func incrementPartRect(bounds: Rect): Rect =
  let leftWidth = bounds.size.width * 0.5'f32
  initRect(
    bounds.origin.x + leftWidth,
    bounds.origin.y,
    bounds.size.width - leftWidth,
    bounds.size.height,
  )

proc partRect*(stepper: Stepper, part: StepperPart): Rect =
  if stepper.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let bounds = stepper.bounds()
  case part
  of spIncrement:
    incrementPartRect(bounds)
  of spDecrement:
    decrementPartRect(bounds)
  of spNone:
    initRect(0.0, 0.0, 0.0, 0.0)

proc partAtPoint*(stepper: Stepper, point: Point): StepperPart =
  if stepper.isNil or not stepper.bounds().contains(point):
    return spNone
  if stepper.partRect(spIncrement).contains(point):
    spIncrement
  elif stepper.partRect(spDecrement).contains(point):
    spDecrement
  else:
    spNone

proc stepperStyleContext(stepper: Stepper, states: set[WidgetState]): StyleContext =
  controlStyle(srStepper, states, id = stepper.styleId, classes = stepper.styleClasses)

proc stepperCellSize(cell: StepperCell): Size =
  let view = cell.controlView()
  let appearance =
    if view.isNil:
      initAppearance()
    else:
      view.effectiveAppearance()
  let style = appearance.resolveButtonStyle(controlStyle(srStepper))
  let contentSize = textNaturalSize("+", style.text)
  let textWidth = contentSize.width * 2.0'f32 + style.text.insets.horizontal
  initSize(max(style.minSize.width, textWidth), style.minSize.height)

protocol DefaultStepperCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: StepperCell): IntrinsicSize =
    initIntrinsicSize(cell.stepperCellSize())

  method cellSizeForBounds(cell: StepperCell, bounds: Rect): Size =
    let minSize = cell.stepperCellSize()
    initSize(
      max(bounds.size.width, minSize.width), max(bounds.size.height, minSize.height)
    )

proc initStepperCellFields*(cell: StepperCell) =
  initActionCellFields(cell)
  discard cell.withProtocol(DefaultStepperCellMeasurement)

proc newStepperCell*(): StepperCell =
  result = StepperCell()
  initStepperCellFields(result)

proc stepperSegmentStates(stepper: Stepper, part: StepperPart): set[WidgetState] =
  result = stepper.widgetStateSet()
  if stepper.xPressedPart == part:
    result.incl ssHighlighted
    result.incl ssPressed

proc drawStepperSegment(
    stepper: Stepper, context: DrawContext, part: StepperPart, label: string
) =
  let
    states = stepper.stepperSegmentStates(part)
    style = context.appearance.resolveButtonStyle(stepper.stepperStyleContext(states))
    rect = stepper.partRect(part)
    textStyle = TextStyle(
      color: style.text.color,
      insets: insets(0.0),
      fontName: style.text.fontName,
      fontSize: max(style.text.fontSize, min(22.0'f32, rect.size.height - 6.0'f32)),
    )
  context.addText(rect, label, textStyle, alignment = taCenter)

protocol DefaultStepperDrawing of ViewDrawingProtocol:
  method draw(stepper: Stepper, context: DrawContext) =
    let
      bounds = stepper.bounds()
      style = context.appearance.resolveButtonStyle(
        stepper.stepperStyleContext(stepper.widgetStateSet())
      )
      frame = context.renderRectFor(bounds)
      radius = min(style.box.cornerRadius, max(bounds.size.height * 0.5'f32, 2.0'f32))
      chrome = chromeContext(
        style.chrome, crButton, cpFace, style.box.fill, stepper.widgetStateSet()
      )
      root = context.addRenderRectangle(
        frame,
        context.appearance.chromeFill(chrome),
        style.box.borderColor,
        style.box.borderWidth,
        radius,
        style.box.shadows,
        maskContent = true,
      )
    context.drawChromeExtras(
      chrome, initChromeExtras(root, frame, cornerRadius = radius)
    )

    if stepper.xPressedPart != spNone:
      let
        pressedStates = stepper.stepperSegmentStates(stepper.xPressedPart)
        pressedStyle = context.appearance.resolveButtonStyle(
          stepper.stepperStyleContext(pressedStates)
        )
        pressedChrome = chromeContext(
          pressedStyle.chrome, crButton, cpFace, pressedStyle.box.fill, pressedStates
        )
      discard context.addRenderRectangle(
        root,
        context.renderRectFor(stepper.partRect(stepper.xPressedPart)),
        context.appearance.chromeFill(pressedChrome),
      )

    let
      separatorX = bounds.origin.x + bounds.size.width * 0.5'f32 - 0.5'f32
      separator = initRect(separatorX, bounds.origin.y, 1.0'f32, bounds.size.height)
    discard context.addRenderRectangle(
      context.renderRectFor(separator),
      style.box.borderColor,
      style.box.borderColor,
      0.0'f32,
      0.0'f32,
    )

    stepper.drawStepperSegment(context, spDecrement, "-")
    stepper.drawStepperSegment(context, spIncrement, "+")

    if stepper.isFocusVisible:
      context.addFocusRing(context.renderRectFor(bounds), style.box)

protocol DefaultStepperEvents of ResponderEventProtocol:
  method mouseDown(stepper: Stepper, event: MouseEvent): bool =
    if stepper.isEnabled() and event.button == mbPrimary:
      let part = stepper.partAtPoint(event.location)
      if part == spNone:
        return false
      discard stepper.beginRepeat(part, event.timestamp)
      return true

  method mouseDragged(stepper: Stepper, event: MouseEvent): bool =
    if stepper.isEnabled() and event.button == mbPrimary and stepper.repeatActive():
      let part = stepper.partAtPoint(event.location)
      stepper.xPressedPart = if part == stepper.xRepeatPart: part else: spNone
      stepper.setNeedsDisplay(true)
      return true

  method mouseTrackingTick(stepper: Stepper, event: MouseEvent): bool =
    if stepper.isEnabled() and event.button == mbPrimary and stepper.repeatActive():
      let part = stepper.partAtPoint(event.location)
      let pressedPart = if part == stepper.xRepeatPart: part else: spNone
      if stepper.xPressedPart != pressedPart:
        stepper.xPressedPart = pressedPart
        stepper.setNeedsDisplay(true)
      if pressedPart != spNone:
        discard stepper.repeatTick(event.timestamp)
      return true

  method mouseUp(stepper: Stepper, event: MouseEvent): bool =
    if stepper.isEnabled() and event.button == mbPrimary:
      stepper.endRepeat()
      return true

  method keyDown(stepper: Stepper, event: KeyEvent): bool =
    if not stepper.isEnabled():
      return false
    case event.key
    of keyArrowUp, keyArrowRight, keyAdd, keyEqual:
      discard stepper.incrementValue()
      true
    of keyArrowDown, keyArrowLeft, keySubtract, keyMinus:
      discard stepper.decrementValue()
      true
    else:
      false

protocol DefaultStepperAccessibility of AccessibilityProtocol:
  method accessibilityRole(stepper: Stepper): AccessibilityRole =
    arSlider

  method accessibilityLabel(stepper: Stepper): string =
    if stepper.xAccessibilityLabel.len > 0: stepper.xAccessibilityLabel else: "stepper"

  method accessibilityValue(stepper: Stepper): string =
    stepper.formattedValue()

  method accessibilityTraits(stepper: Stepper): AccessibilityTraits =
    result = stepper.xAccessibilityTraits + {atAdjustable}
    if not stepper.isEnabled():
      result.incl atDisabled
    if stepper.focused():
      result.incl atFocused

  method isAccessibilityElement(stepper: Stepper): bool =
    true

  method accessibilityActionNames(stepper: Stepper): seq[string] =
    @[AccessibilityActionIncrement, AccessibilityActionDecrement]

  method accessibilityPerformAction(stepper: Stepper, action: string): bool =
    if not stepper.isEnabled():
      return false
    case action
    of AccessibilityActionIncrement:
      discard stepper.incrementValue()
      true
    of AccessibilityActionDecrement:
      discard stepper.decrementValue()
      true
    else:
      false

proc initStepperFields*(
    stepper: Stepper,
    minValue = 0.0'f32,
    maxValue = 100.0'f32,
    value = 0.0'f32,
    increment = 1.0'f32,
    frame: Rect = AutoRect,
) =
  initControlFields(stepper, frame, newStepperCell())
  stepper.xMinValue = minValue
  stepper.xMaxValue = maxValue
  stepper.xIncrement = max(increment, 0.0'f32)
  stepper.xValue = stepper.clampedValue(value)
  Control(stepper).objectParseContext =
    initObjectParseContext(expectedKind = ovFloat, role = ovrStepper)
  Control(stepper).setObjectValue(toObjectValue(stepper.xValue))
  stepper.setAcceptsFirstResponder(true)
  stepper.setHuggingPriority(LayoutPriorityRequired, laHorizontal)
  stepper.setCompressionPriority(LayoutPriorityHigh, laHorizontal)
  discard stepper.withProtocol(DefaultStepperDrawing)
  discard stepper.withProtocol(DefaultStepperEvents)
  discard stepper.withProtocol(DefaultStepperAccessibility)
  stepper.applyInitialFrame(frame)

proc newStepper*(
    minValue = 0.0'f32,
    maxValue = 100.0'f32,
    value = 0.0'f32,
    increment = 1.0'f32,
    frame: Rect = AutoRect,
): Stepper =
  result = Stepper()
  initStepperFields(result, minValue, maxValue, value, increment, frame)
