import std/math

import ../accessibility/accessibility
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../drawing
import ../themes
import ./controls

export controls

type
  Slider* = ref object of Control
    xMinValue: float32
    xMaxValue: float32
    xValue: float32
    xStepValue: float32

  SliderCell* = ref object of ActionCell

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

proc sliderStyleContext(slider: Slider): StyleContext =
  if slider.isNil:
    return initControlStyleContext(srSlider)
  initControlStyleContext(
    srSlider,
    slider.widgetStateSet(),
    id = slider.styleId,
    classes = slider.styleClasses,
  )

proc sliderStyle(cell: SliderCell): SliderStyle =
  let view = cell.controlView()
  if view of Slider:
    return
      view.effectiveAppearance().resolveSliderStyle(Slider(view).sliderStyleContext())
  initAppearance().resolveSliderStyle(initControlStyleContext(srSlider))

proc sliderStyle(slider: Slider, context: DrawContext = nil): SliderStyle =
  if not context.isNil:
    return context.appearance.resolveSliderStyle(slider.sliderStyleContext())
  slider.effectiveAppearance().resolveSliderStyle(slider.sliderStyleContext())

proc trackRect(slider: Slider, style: SliderStyle): Rect =
  let bounds = slider.bounds()
  initRect(
    bounds.origin.x + style.knobSize * 0.5'f32,
    bounds.origin.y + (bounds.size.height - style.trackHeight) * 0.5'f32,
    max(bounds.size.width - style.knobSize, 0.0'f32),
    style.trackHeight,
  )

proc trackRect(slider: Slider): Rect =
  slider.trackRect(slider.sliderStyle())

proc sliderFraction(slider: Slider): float32 =
  let range = slider.normalizedRange()
  if range.maxValue <= range.minValue:
    return 0.0'f32
  (slider.xValue - range.minValue) / (range.maxValue - range.minValue)

proc knobRect(slider: Slider, style: SliderStyle): Rect =
  let
    track = slider.trackRect(style)
    centerX = track.origin.x + track.size.width * slider.sliderFraction()
  initRect(
    centerX - style.knobSize * 0.5'f32,
    slider.bounds().origin.y + (slider.bounds().size.height - style.knobSize) * 0.5'f32,
    style.knobSize,
    style.knobSize,
  )

proc knobRect(slider: Slider): Rect =
  slider.knobRect(slider.sliderStyle())

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
    initIntrinsicSize(cell.sliderStyle().minSize)

  method cellSizeForBounds(cell: SliderCell, bounds: Rect): Size =
    let minSize = cell.sliderStyle().minSize
    initSize(max(bounds.size.width, minSize.width), minSize.height)

proc initSliderCellFields*(cell: SliderCell) =
  initActionCellFields(cell)
  discard cell.withProtocol(DefaultSliderCellMeasurement)

proc newSliderCell*(): SliderCell =
  result = SliderCell()
  initSliderCellFields(result)

proc sliderFocusBox(style: SliderStyle): ControlBoxStyle =
  ControlBoxStyle(
    focusRingWidth: 3.0'f32,
    focusRingInset: -3.0'f32,
    focusRingColor: initColor(0.28, 0.62, 1.0, 0.80),
    cornerRadius: style.knobSize * 0.5'f32,
  )

func sliderTrackBaseFill(enabled: bool): Fill =
  fill(initColor(0.76, 0.82, 0.88, if enabled: 1.0'f32 else: 0.60'f32))

func sliderActiveTrackBaseFill(enabled: bool): Fill =
  fill(initColor(0.13, 0.55, 0.96, if enabled: 1.0'f32 else: 0.40'f32))

func sliderKnobBaseFill(highlighted, enabled: bool): Fill =
  if highlighted and enabled:
    fill(initColor(0.15, 0.60, 0.98, 1.0))
  else:
    fill(initColor(0.92, 0.94, 0.97, if enabled: 1.0'f32 else: 0.66'f32))

proc sliderChromeStates(slider: Slider): set[WidgetState] =
  result = slider.widgetStateSet()
  if slider.cell().isHighlighted():
    result.incl ssHighlighted

proc drawSliderTrack(
    slider: Slider,
    context: DrawContext,
    rect: Rect,
    part: ChromePart,
    fillValue: Fill,
    style: SliderStyle,
) =
  if rect.isEmpty:
    return
  let
    frame = context.renderRectFor(rect)
    radius = rect.size.height * 0.5'f32
    chrome = chromeContext(
      style.chrome, crSliderTrack, part, fillValue, slider.sliderChromeStates()
    )
    borderColor =
      if part == cpHighlight:
        initColor(0.02, 0.20, 0.58, 0.70)
      else:
        initColor(0.38, 0.46, 0.56, if slider.isEnabled(): 0.75'f32 else: 0.35'f32)
    trackRoot = context.addRenderRectangle(
      frame,
      context.appearance.chromeFill(chrome),
      borderColor,
      1.0'f32,
      radius,
      @[
        insetShadow(
          initColor(0.0, 0.0, 0.0, if slider.isEnabled(): 0.16'f32 else: 0.06'f32),
          y = 1.0,
          blur = 2.0,
        )
      ],
      lightMaskContent = true,
    )
  context.drawChromeExtras(
    chrome, initChromeExtras(trackRoot, frame, cornerRadius = radius)
  )

proc drawSliderKnob(
    slider: Slider, context: DrawContext, rect: Rect, style: SliderStyle
) =
  if rect.isEmpty:
    return
  let
    enabled = slider.isEnabled()
    highlighted = slider.cell().isHighlighted()
    frame = context.renderRectFor(rect)
    radius = rect.size.width * 0.5'f32
    chrome = chromeContext(
      style.chrome,
      crSliderKnob,
      cpFace,
      sliderKnobBaseFill(highlighted, enabled),
      slider.sliderChromeStates(),
    )
    knobRoot = context.addRenderRectangle(
      frame,
      context.appearance.chromeFill(chrome),
      initColor(0.36, 0.40, 0.48, if enabled: 0.92'f32 else: 0.42'f32),
      1.0'f32,
      radius,
      @[
        dropShadow(
          initColor(0.0, 0.0, 0.0, if enabled: 0.20'f32 else: 0.08'f32),
          y = 1.0,
          blur = 3.0,
        ),
        insetShadow(
          initColor(1.0, 1.0, 1.0, if enabled: 0.75'f32 else: 0.22'f32),
          y = 1.0,
          blur = 2.0,
        ),
      ],
      lightMaskContent = true,
    )
  context.drawChromeExtras(
    chrome, initChromeExtras(knobRoot, frame, cornerRadius = radius)
  )

protocol DefaultSliderDrawing of ViewDrawingProtocol:
  method draw(slider: Slider, context: DrawContext) =
    let
      enabled = slider.isEnabled()
      style = slider.sliderStyle(context)
      track = slider.trackRect(style)
      knob = slider.knobRect(style)

    slider.drawSliderTrack(context, track, cpFace, sliderTrackBaseFill(enabled), style)

    let fillRect = initRect(
      track.origin.x,
      track.origin.y,
      track.size.width * slider.sliderFraction(),
      track.size.height,
    )
    if fillRect.size.width > 0.0'f32 and enabled:
      slider.drawSliderTrack(
        context, fillRect, cpHighlight, sliderActiveTrackBaseFill(enabled), style
      )

    slider.drawSliderKnob(context, knob, style)

    if slider.isFocusVisible:
      context.addFocusRing(context.renderRectFor(knob), sliderFocusBox(style))

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
