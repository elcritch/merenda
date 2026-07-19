import std/math

import ../accessibility/accessibility
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ../drawing
import ../themes
import ./controls
from pkg/chroma import ColorRGBA

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
  let nextValue = slider.normalizedValue(value)
  if slider.xValue == nextValue:
    return
  slider.xValue = nextValue
  Control(slider).setObjectValue(toObj(nextValue))
  slider.needsDisplay = true
  slider.postAccessibilityNotification(anValueChanged)
  if notify:
    discard slider.sendAction()

proc sliderStyleContext(slider: Slider): StyleContext =
  controlStyle(
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
  initAppearance().resolveSliderStyle(controlStyle(srSlider))

proc sliderStyle(slider: Slider, context: DrawContext = nil): SliderStyle =
  if not context.isNil:
    return context.appearance.resolveSliderStyle(slider.sliderStyleContext())
  slider.effectiveAppearance().resolveSliderStyle(slider.sliderStyleContext())

proc trackRect(slider: Slider, style: SliderStyle): Rect =
  let bounds = slider.bounds()
  rect(
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
  rect(
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
  slider.xValue

proc `value=`*(slider: Slider, value: float32) =
  slider.setSliderValue(value)

proc setObjectValue*(slider: Slider, value: ObjectValue, notify = false) =
  try:
    slider.setSliderValue(value.requireNumber().float32, notify)
  except ObjectValueError:
    discard Control(slider).rejectObjectValueEdit(
        initObjectValidationError(
          oveTypeMismatch,
          message = getCurrentExceptionMsg(),
          expectedKind = ovFloat,
          actualKind = value.kind,
        )
      )

proc `objectValue=`*(slider: Slider, value: ObjectValue) =
  slider.setObjectValue(value)

proc minValue*(slider: Slider): float32 =
  slider.xMinValue

proc `minValue=`*(slider: Slider, value: float32) =
  if slider.xMinValue == value:
    return
  slider.xMinValue = value
  slider.setSliderValue(slider.xValue)
  slider.needsDisplay = true

proc maxValue*(slider: Slider): float32 =
  slider.xMaxValue

proc `maxValue=`*(slider: Slider, value: float32) =
  if slider.xMaxValue == value:
    return
  slider.xMaxValue = value
  slider.setSliderValue(slider.xValue)
  slider.needsDisplay = true

proc stepValue*(slider: Slider): float32 =
  slider.xStepValue

proc `stepValue=`*(slider: Slider, value: float32) =
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
    focusRingColor: color(0.28, 0.62, 1.0, 0.80),
    cornerRadius: style.knobSize * 0.5'f32,
  )

func clampUnit(value: float32): float32 =
  min(max(value, 0.0'f32), 1.0'f32)

func mixFloat(a, b, progress: float32): float32 =
  a + (b - a) * progress.clampUnit()

func mixColor(a, b: Color, progress: float32): Color =
  color(
    mixFloat(a.r, b.r, progress),
    mixFloat(a.g, b.g, progress),
    mixFloat(a.b, b.b, progress),
    mixFloat(a.a, b.a, progress),
  )

func rgbaColor(value: ColorRGBA): Color =
  color(
    value.r.float32 / 255.0'f32,
    value.g.float32 / 255.0'f32,
    value.b.float32 / 255.0'f32,
    value.a.float32 / 255.0'f32,
  )

func mixFill(a, b: Fill, progress: float32): Fill =
  if a.kind == b.kind:
    case a.kind
    of flColor:
      return fill(mixColor(a.color.rgbaColor(), b.color.rgbaColor(), progress))
    of flLinear2:
      if a.lin2.axis == b.lin2.axis:
        return linear(
          mixColor(a.lin2.start.rgbaColor(), b.lin2.start.rgbaColor(), progress),
          mixColor(a.lin2.stop.rgbaColor(), b.lin2.stop.rgbaColor(), progress),
          a.lin2.axis,
        )
    of flLinear3:
      if a.lin3.axis == b.lin3.axis and a.lin3.midPos == b.lin3.midPos:
        return linear(
          mixColor(a.lin3.start.rgbaColor(), b.lin3.start.rgbaColor(), progress),
          mixColor(a.lin3.mid.rgbaColor(), b.lin3.mid.rgbaColor(), progress),
          mixColor(a.lin3.stop.rgbaColor(), b.lin3.stop.rgbaColor(), progress),
          a.lin3.axis,
          a.lin3.midPos,
        )
  fill(mixColor(a.centerColor(), b.centerColor(), progress))

proc sliderKnobFill(slider: Slider, style: SliderStyle): Fill =
  mixFill(style.knob.fill, style.activeTrack.fill, slider.sliderFraction())

proc sliderChromeStates(slider: Slider): set[WidgetState] =
  result = slider.widgetStateSet()
  if slider.cell().isHighlighted():
    result.incl ssHighlighted

proc drawSliderTrack(
    slider: Slider,
    context: DrawContext,
    rect: Rect,
    part: ChromePart,
    style: SliderStyle,
) =
  if rect.isEmpty:
    return
  let
    frame = context.renderRectFor(rect)
    radius = rect.size.height * 0.5'f32
    box = if part == cpHighlight: style.activeTrack else: style.track
    chrome = chromeContext(
      style.chrome, crSliderTrack, part, box.fill, slider.sliderChromeStates()
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

proc drawSliderKnob(
    slider: Slider, context: DrawContext, rect: Rect, style: SliderStyle
) =
  if rect.isEmpty:
    return
  let
    frame = context.renderRectFor(rect)
    radius = rect.size.width * 0.5'f32
    chrome = chromeContext(
      style.chrome,
      crSliderKnob,
      cpFace,
      slider.sliderKnobFill(style),
      slider.sliderChromeStates(),
    )
  context.drawChromeBacking(
    chrome, initChromeExtras(context.renderParent(), frame, cornerRadius = radius)
  )
  let knobRoot = context.addRenderRectangle(
    frame,
    context.appearance.chromeFill(chrome),
    style.knob.borderColor,
    style.knob.borderWidth,
    radius,
    style.knob.shadows,
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

    slider.drawSliderTrack(context, track, cpFace, style)

    let fillRect = rect(
      track.origin.x,
      track.origin.y,
      track.size.width * slider.sliderFraction(),
      track.size.height,
    )
    if fillRect.size.width > 0.0'f32 and enabled:
      slider.drawSliderTrack(context, fillRect, cpHighlight, style)

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
  Control(slider).objectParseContext =
    initObjectParseContext(expectedKind = ovFloat, role = ovrSlider)
  Control(slider).setObjectValue(toObj(slider.xValue))
  slider.acceptsFirstResponder = true
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
