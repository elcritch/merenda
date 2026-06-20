import std/math

import ../accessibility/accessibility
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../drawing/drawing
import ../drawing/theme
import ./controls

export controls

type
  Slider* = ref object of Control
    xMinValue: float32
    xMaxValue: float32
    xValue: float32
    xStepValue: float32

  SliderCell* = ref object of ActionCell

const
  SliderTrackHeight = 6.0'f32
  SliderKnobSize = 18.0'f32
  SliderMinWidth = 160.0'f32
  SliderMinHeight = 24.0'f32

proc normalizedRange(slider: Slider): tuple[minValue, maxValue: float32] =
  if slider.xMaxValue > slider.xMinValue:
    (slider.xMinValue, slider.xMaxValue)
  else:
    (slider.xMaxValue, slider.xMinValue)

proc normalizedValue(slider: Slider, value: float32): float32 =
  let range = slider.normalizedRange()
  result = min(max(value, range.minValue), range.maxValue)
  if slider.xStepValue > 0.0'f32 and range.maxValue > range.minValue:
    let steps = round((result - range.minValue) / slider.xStepValue)
    result = min(
      max(range.minValue + float32(steps) * slider.xStepValue, range.minValue),
      range.maxValue,
    )

proc setSliderValue(slider: Slider, value: float32, notify = false) =
  if slider.isNil:
    return
  let nextValue = slider.normalizedValue(value)
  if slider.xValue == nextValue:
    return
  slider.xValue = nextValue
  slider.setNeedsDisplay(true)
  slider.postAccessibilityNotification(anValueChanged)
  if notify:
    discard slider.sendAction()

proc trackRect(slider: Slider): Rect =
  let bounds = slider.bounds()
  initRect(
    bounds.origin.x + SliderKnobSize * 0.5'f32,
    bounds.origin.y + (bounds.size.height - SliderTrackHeight) * 0.5'f32,
    max(bounds.size.width - SliderKnobSize, 0.0'f32),
    SliderTrackHeight,
  )

proc sliderFraction(slider: Slider): float32 =
  let range = slider.normalizedRange()
  if range.maxValue <= range.minValue:
    return 0.0'f32
  (slider.xValue - range.minValue) / (range.maxValue - range.minValue)

proc knobRect(slider: Slider): Rect =
  let
    track = slider.trackRect()
    centerX = track.origin.x + track.size.width * slider.sliderFraction()
  initRect(
    centerX - SliderKnobSize * 0.5'f32,
    slider.bounds().origin.y + (slider.bounds().size.height - SliderKnobSize) * 0.5'f32,
    SliderKnobSize,
    SliderKnobSize,
  )

proc updateValueFromPoint(slider: Slider, point: Point, notify = true) =
  let
    track = slider.trackRect()
    range = slider.normalizedRange()
  if track.size.width <= 0.0'f32:
    return
  let fraction =
    min(max((point.x - track.origin.x) / track.size.width, 0.0'f32), 1.0'f32)
  slider.setSliderValue(
    range.minValue + (range.maxValue - range.minValue) * fraction, notify
  )

proc value*(slider: Slider): float32 =
  if slider.isNil: 0.0'f32 else: slider.xValue

proc `value=`*(slider: Slider, value: float32) =
  slider.setSliderValue(value)

proc minValue*(slider: Slider): float32 =
  if slider.isNil: 0.0'f32 else: slider.xMinValue

proc `minValue=`*(slider: Slider, value: float32) =
  if slider.isNil or slider.xMinValue == value:
    return
  slider.xMinValue = value
  slider.setSliderValue(slider.xValue)
  slider.setNeedsDisplay(true)

proc maxValue*(slider: Slider): float32 =
  if slider.isNil: 0.0'f32 else: slider.xMaxValue

proc `maxValue=`*(slider: Slider, value: float32) =
  if slider.isNil or slider.xMaxValue == value:
    return
  slider.xMaxValue = value
  slider.setSliderValue(slider.xValue)
  slider.setNeedsDisplay(true)

proc stepValue*(slider: Slider): float32 =
  if slider.isNil: 0.0'f32 else: slider.xStepValue

proc `stepValue=`*(slider: Slider, value: float32) =
  if slider.isNil:
    return
  let nextValue = max(value, 0.0'f32)
  if slider.xStepValue == nextValue:
    return
  slider.xStepValue = nextValue
  slider.setSliderValue(slider.xValue)

protocol DefaultSliderCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: SliderCell): IntrinsicSize =
    initIntrinsicSize(SliderMinWidth, SliderMinHeight)

  method cellSizeForBounds(cell: SliderCell, bounds: Rect): Size =
    initSize(max(bounds.size.width, SliderMinWidth), SliderMinHeight)

proc initSliderCellFields*(cell: SliderCell) =
  initActionCellFields(cell)
  discard cell.withProtocol(DefaultSliderCellMeasurement)

proc newSliderCell*(): SliderCell =
  result = SliderCell()
  initSliderCellFields(result)

func aquaSliderTrackFill(): Fill =
  linear(initColor(0.68, 0.73, 0.78, 1.0), initColor(0.92, 0.95, 0.98, 1.0), fgaY)

func aquaSliderFill(): Fill =
  linear(initColor(0.08, 0.42, 0.89, 1.0), initColor(0.36, 0.78, 1.0, 1.0), fgaY)

func aquaSliderKnobFill(highlighted, enabled: bool): Fill =
  if not enabled:
    return
      linear(initColor(0.90, 0.91, 0.93, 1.0), initColor(0.76, 0.78, 0.82, 1.0), fgaY)
  if highlighted:
    return linear(
      initColor(0.72, 0.88, 1.0, 1.0),
      initColor(0.14, 0.50, 0.94, 1.0),
      initColor(0.02, 0.26, 0.72, 1.0),
      fgaY,
      104'u8,
    )
  linear(initColor(1.0, 1.0, 1.0, 1.0), initColor(0.78, 0.82, 0.88, 1.0), fgaY)

proc sliderFocusBox(): ControlBoxStyle =
  ControlBoxStyle(
    focusRingWidth: 3.0'f32,
    focusRingInset: -3.0'f32,
    focusRingColor: initColor(0.28, 0.62, 1.0, 0.80),
    cornerRadius: SliderKnobSize * 0.5'f32,
  )

protocol DefaultSliderDrawing of ViewDrawingProtocol:
  method draw(slider: Slider, context: DrawContext) =
    let
      enabled = slider.isEnabled()
      track = slider.trackRect()
      knob = slider.knobRect()
      radius = SliderTrackHeight * 0.5'f32

    discard context.addRenderRectangle(
      context.renderRectFor(track),
      aquaSliderTrackFill(),
      initColor(0.38, 0.46, 0.56, if enabled: 0.75'f32 else: 0.35'f32),
      1.0'f32,
      radius,
      @[insetShadow(initColor(0.0, 0.0, 0.0, 0.16), y = 1.0, blur = 2.0)],
    )

    let fillRect = initRect(
      track.origin.x,
      track.origin.y,
      track.size.width * slider.sliderFraction(),
      track.size.height,
    )
    if fillRect.size.width > 0.0'f32 and enabled:
      discard context.addRenderRectangle(
        context.renderRectFor(fillRect),
        aquaSliderFill(),
        initColor(0.02, 0.20, 0.58, 0.70),
        1.0'f32,
        radius,
      )

    discard context.addRenderRectangle(
      context.renderRectFor(knob),
      aquaSliderKnobFill(slider.cell().isHighlighted(), enabled),
      initColor(0.36, 0.40, 0.48, if enabled: 0.92'f32 else: 0.42'f32),
      1.0'f32,
      SliderKnobSize * 0.5'f32,
      @[
        dropShadow(initColor(0.0, 0.0, 0.0, 0.20), y = 1.0, blur = 3.0),
        insetShadow(initColor(1.0, 1.0, 1.0, 0.75), y = 1.0, blur = 2.0),
      ],
      maskContent = true,
    )

    if slider.isFocusVisible:
      context.addFocusRing(context.renderRectFor(knob), sliderFocusBox())

protocol DefaultSliderEvents of ResponderEventProtocol:
  method mouseDown(slider: Slider, event: MouseEvent): bool =
    if slider.isEnabled() and event.button == mbPrimary:
      slider.cell().setHighlighted(true)
      slider.updateValueFromPoint(event.location)
      return true

  method mouseDragged(slider: Slider, event: MouseEvent): bool =
    if slider.isEnabled() and event.button == mbPrimary:
      slider.updateValueFromPoint(event.location)
      return true

  method mouseUp(slider: Slider, event: MouseEvent): bool =
    if slider.isEnabled() and event.button == mbPrimary:
      slider.cell().setHighlighted(false)
      slider.updateValueFromPoint(event.location)
      return true

  method keyDown(slider: Slider, event: KeyEvent): bool =
    if not slider.isEnabled():
      return false
    let delta =
      if slider.xStepValue > 0.0'f32:
        slider.xStepValue
      else:
        (slider.normalizedRange().maxValue - slider.normalizedRange().minValue) /
          20.0'f32
    case event.key
    of keyArrowLeft, keyArrowDown:
      slider.setSliderValue(slider.value - delta, notify = true)
      true
    of keyArrowRight, keyArrowUp:
      slider.setSliderValue(slider.value + delta, notify = true)
      true
    else:
      false

protocol DefaultSliderAccessibility of AccessibilityProtocol:
  method accessibilityRole(slider: Slider): AccessibilityRole =
    arSlider

  method accessibilityLabel(slider: Slider): string =
    if slider.xAccessibilityLabel.len > 0: slider.xAccessibilityLabel else: "slider"

  method accessibilityValue(slider: Slider): string =
    $slider.value

  method accessibilityTraits(slider: Slider): AccessibilityTraits =
    result = slider.xAccessibilityTraits
    if not slider.isEnabled():
      result.incl atDisabled
    if slider.focused():
      result.incl atFocused

  method isAccessibilityElement(slider: Slider): bool =
    true

proc initSliderFields*(
    slider: Slider,
    minValue = 0.0'f32,
    maxValue = 1.0'f32,
    value = 0.0'f32,
    frame: Rect = AutoRect,
) =
  initControlFields(slider, frame, newSliderCell())
  slider.xMinValue = minValue
  slider.xMaxValue = maxValue
  slider.xStepValue = 0.0'f32
  slider.xValue = slider.normalizedValue(value)
  slider.setAcceptsFirstResponder(true)
  slider.setHuggingPriority(LayoutPriorityLow, laHorizontal)
  slider.setCompressionPriority(LayoutPriorityHigh, laHorizontal)
  discard slider.withProtocol(DefaultSliderDrawing)
  discard slider.withProtocol(DefaultSliderEvents)
  discard slider.withProtocol(DefaultSliderAccessibility)
  slider.applyInitialFrame(frame)

proc newSlider*(
    minValue = 0.0'f32, maxValue = 1.0'f32, value = 0.0'f32, frame: Rect = AutoRect
): Slider =
  result = Slider()
  initSliderFields(result, minValue, maxValue, value, frame)
