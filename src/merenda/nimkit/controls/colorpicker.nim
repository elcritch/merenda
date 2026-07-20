## Color wells and tabbed color-picker controls.

when defined(useNativeDynlib):
  from figdraw/dynlib import FigIdx
else:
  from figdraw import FigIdx
import std/[math, strutils]

import sigils/core

import ../accessibility/accessibility
import ../app/windows
import ../containers/tabviews
import ../drawing
import ../foundation/[events, selectors, types]
import ../text/textfields
import ../themes
import ../view/views
import ./[buttons, controls, menus, sliders]

export menus, tabviews

type
  ColorWellChoice* = object
    title*: string
    color*: Color

  PopupColorChoice* = ColorWellChoice

  ColorPickerPart = enum
    cppNone
    cppWheel
    cppWell
    cppAlpha

  ColorWellCell = ref object of ActionCell

  ColorPicker* = ref object of TabView
    xSource: ColorWell
    xPaletteButtons: seq[Button]
    xWheelView: ColorWheelView
    xValuesView: ColorValuesView
    xOkayButton: Button

  ColorWell* = ref object of Control
    xColor: Color
    xChoices: seq[ColorWellChoice]
    xPopupWindow: Window
    xPicker: ColorPicker
    xPopupOpen: bool

  ColorPaletteView = ref object of View
    xPicker: ColorPicker

  ColorPaletteButton = ref object of Button
    xSource: ColorWell
    xChoiceIndex: int

  ColorWheelView = ref object of View
    xSource: ColorWell
    xHue: float32
    xSaturation: float32
    xValue: float32
    xAlpha: float32
    xActivePart: ColorPickerPart

  ColorValuesView = ref object of View
    xSource: ColorWell
    xCssLabel: Label
    xCssField: TextField
    xStatusLabel: Label
    xComponentLabels: array[4, Label]
    xValueLabels: array[4, Label]
    xSliders: array[4, Slider]

  PopupColorWell* = ref object of PopupMenuButton
    xColor: Color
    xChoices: seq[PopupColorChoice]

const
  ColorWellNaturalWidth = 72.0'f32
  ColorWellNaturalHeight = 30.0'f32
  ColorPickerWidth = 300.0'f32
  ColorPickerHeight = 340.0'f32
  ColorPaletteColumns = 5
  ColorPaletteSwatchSize = 38.0'f32
  ColorPaletteSpacing = 10.0'f32
  ColorWheelSegments = 96
  ColorWheelRingWidth = 18.0'f32
  ColorWheelPageInset = 16.0'f32
  ColorWheelAlphaHeight = 18.0'f32
  ColorWheelAlphaBottomInset = 12.0'f32
  ColorPickerOkayWidth = 72.0'f32
  ColorPickerOkayHeight = 30.0'f32
  ColorPickerOkayInset = 12.0'f32
  ColorPickerOkayGap = 10.0'f32
  CssColorHelp = "Try #RGB, rgb(), rgba(), or a CSS color name."
  ColorComponentNames = ["R", "G", "B", "A"]

proc openPopup*(well: ColorWell)
proc closePopup*(well: ColorWell)
proc activateColorAtIndex*(well: ColorWell, index: int): bool {.discardable.}
proc synchronizePicker(well: ColorWell)
proc synchronizeFromSource(wheel: ColorWheelView)
proc synchronizeFromSource(values: ColorValuesView)

protocol ColorWellEvents:
  proc colorDidChange*(well: ColorWell, sender: DynamicAgent) {.signal.}

protocol PopupColorWellEvents:
  proc colorDidChange*(well: PopupColorWell, sender: DynamicAgent) {.signal.}

func initColorWellChoice*(title: string, color: Color): ColorWellChoice =
  ColorWellChoice(title: title, color: color)

func initPopupColorChoice*(title: string, color: Color): PopupColorChoice =
  initColorWellChoice(title, color)

func defaultColorWellChoices*(): seq[ColorWellChoice] =
  @[
    initColorWellChoice("Clear", color(0.0, 0.0, 0.0, 0.0)),
    initColorWellChoice("Black", color(0.08, 0.09, 0.11, 1.0)),
    initColorWellChoice("White", color(1.0, 1.0, 1.0, 1.0)),
    initColorWellChoice("Gray", color(0.52, 0.54, 0.58, 1.0)),
    initColorWellChoice("Slate", color(0.28, 0.32, 0.40, 1.0)),
    initColorWellChoice("Red", color(0.88, 0.24, 0.26, 1.0)),
    initColorWellChoice("Coral", color(0.94, 0.40, 0.34, 1.0)),
    initColorWellChoice("Orange", color(0.96, 0.52, 0.16, 1.0)),
    initColorWellChoice("Amber", color(0.96, 0.66, 0.14, 1.0)),
    initColorWellChoice("Yellow", color(0.96, 0.82, 0.20, 1.0)),
    initColorWellChoice("Lime", color(0.58, 0.78, 0.20, 1.0)),
    initColorWellChoice("Green", color(0.22, 0.70, 0.38, 1.0)),
    initColorWellChoice("Teal", color(0.10, 0.66, 0.58, 1.0)),
    initColorWellChoice("Cyan", color(0.12, 0.70, 0.82, 1.0)),
    initColorWellChoice("Blue", color(0.20, 0.48, 0.92, 1.0)),
    initColorWellChoice("Indigo", color(0.34, 0.36, 0.82, 1.0)),
    initColorWellChoice("Purple", color(0.58, 0.34, 0.86, 1.0)),
    initColorWellChoice("Magenta", color(0.82, 0.28, 0.72, 1.0)),
    initColorWellChoice("Pink", color(0.94, 0.42, 0.62, 1.0)),
    initColorWellChoice("Brown", color(0.52, 0.34, 0.22, 1.0)),
  ]

func defaultPopupColorChoices*(): seq[PopupColorChoice] =
  defaultColorWellChoices()

func colorDescription*(value: Color): string =
  "#" & value.toHexAlpha()

proc colorDescription*(well: ColorWell): string =
  well.xColor.colorDescription()

proc choices*(well: ColorWell): lent seq[ColorWellChoice] =
  well.xChoices

proc selectedIndex*(well: ColorWell): int =
  for index, choice in well.xChoices:
    if choice.color == well.xColor:
      return index
  -1

proc selectedTitle*(well: ColorWell): string =
  let index = well.selectedIndex()
  if index >= 0:
    well.xChoices[index].title
  else:
    well.colorDescription()

proc picker*(well: ColorWell): ColorPicker =
  well.xPicker

proc okayButton*(picker: ColorPicker): Button =
  picker.xOkayButton

proc cssColorField*(picker: ColorPicker): TextField =
  if not picker.isNil and not picker.xValuesView.isNil:
    result = picker.xValuesView.xCssField

proc rgbaSlider*(picker: ColorPicker, index: int): Slider =
  if not picker.isNil and not picker.xValuesView.isNil and index in 0 .. 3:
    result = picker.xValuesView.xSliders[index]

proc popupWindow*(well: ColorWell): Window =
  well.xPopupWindow

protocol ColorWellProtocol {.selectorScope: protocol, setterStyle: nim.} from ColorWell:
  property color -> Color

  method color(well: ColorWell): Color =
    well.xColor

  method `color=`(well: ColorWell, value: Color) =
    if well.xColor == value:
      return
    well.xColor = value
    well.synchronizePicker()
    well.needsDisplay = true
    well.postAccessibilityNotification(anValueChanged)

proc popupOpen*(well: ColorWell): bool =
  well.xPopupOpen

proc `popupOpen=`*(well: ColorWell, value: bool) =
  if value:
    well.openPopup()
  else:
    well.closePopup()

func clampUnit(value: float32): float32 =
  min(max(value, 0.0'f32), 1.0'f32)

proc drawTransparencyBackground(context: DrawContext, bounds: Rect): FigIdx =
  let
    frame = context.renderRectFor(bounds)
    background = context.addRenderRectangle(
      frame, fill(color(0.0, 0.0, 0.0, 0.0)), cornerRadius = 4.0'f32, maskContent = true
    )
    rowCount = 2
    cellHeight = bounds.size.height / float32(rowCount)
    columnCount = max(int(bounds.size.width / max(cellHeight, 1.0'f32)), 1)
    cellWidth = bounds.size.width / float32(columnCount)
  for row in 0 ..< rowCount:
    for column in 0 ..< columnCount:
      let shade =
        if (row + column) mod 2 == 0:
          color(0.94, 0.95, 0.97, 1.0)
        else:
          color(0.68, 0.70, 0.74, 1.0)
      discard context.addRenderRectangle(
        background,
        context.renderRectFor(
          rect(
            bounds.origin.x + float32(column) * cellWidth,
            bounds.origin.y + float32(row) * cellHeight,
            cellWidth,
            cellHeight,
          )
        ),
        fill(shade),
      )
  background

proc drawColorSample(
    context: DrawContext,
    bounds: Rect,
    value: Color,
    selected = false,
    selectionColor = color(0.18, 0.48, 0.92, 1.0),
) =
  let sample = bounds.inset(insets(1.0))
  let background = context.drawTransparencyBackground(sample)
  discard context.addRenderRectangle(
    background,
    context.renderRectFor(sample),
    fill(value),
    if selected:
      selectionColor
    else:
      color(0.25, 0.27, 0.31, 0.9),
    if selected: 3.0'f32 else: 1.0'f32,
    4.0'f32,
  )

protocol ColorWellCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: ColorWellCell): IntrinsicSize =
    initIntrinsicSize(ColorWellNaturalWidth, ColorWellNaturalHeight)

  method cellSizeForBounds(cell: ColorWellCell, bounds: Rect): Size =
    initSize(max(bounds.size.width, ColorWellNaturalWidth), ColorWellNaturalHeight)

proc newColorWellCell(): ColorWellCell =
  result = ColorWellCell()
  initActionCellFields(result)
  discard result.withProtocol(ColorWellCellMeasurement)

protocol ColorWellDrawing of ViewDrawingProtocol:
  method draw(well: ColorWell, context: DrawContext) =
    discard well.performNext(draw, context)
    let appearance = context.appearance()
    context.drawColorSample(
      well.bounds().inset(insets(3.0)),
      well.xColor,
      well.xPopupOpen or well.cell().isHighlighted(),
      appearance.colorToken("accent", color(0.18, 0.48, 0.92, 1.0)),
    )
    if well.isFocusVisible():
      context.addFocusRing(
        context.renderRectFor(well.bounds().inset(insets(3.0))),
        ControlBoxStyle(
          focusRingWidth: 3.0'f32,
          focusRingInset: -2.0'f32,
          focusRingColor:
            appearance.colorToken("focus.ring.color", color(0.28, 0.62, 1.0, 0.80)),
          cornerRadius: 4.0'f32,
        ),
      )

proc applyPickerColor(well: ColorWell, value: Color): bool =
  if well.xColor == value:
    return
  well.color = value
  emit well.colorDidChange(DynamicAgent(well))
  discard well.sendAction()
  true

protocol ColorPaletteButtonDrawing of ViewDrawingProtocol:
  method draw(button: ColorPaletteButton, context: DrawContext) =
    discard button.performNext(draw, context)
    if not button.xSource.isNil and
        button.xChoiceIndex in 0 ..< button.xSource.xChoices.len:
      let choice = button.xSource.xChoices[button.xChoiceIndex]
      context.drawColorSample(
        button.bounds().inset(insets(3.0)),
        choice.color,
        choice.color == button.xSource.xColor,
        context.appearance().colorToken("accent", color(0.18, 0.48, 0.92, 1.0)),
      )

proc newColorPaletteButton(
    well: ColorWell, index: int, frame = AutoRect
): ColorPaletteButton =
  result = ColorPaletteButton(xSource: well, xChoiceIndex: index)
  initButtonFields(result, "", frame)
  result.accessibilityLabel = well.xChoices[index].title
  result.toolTip = well.xChoices[index].title
  discard result.withProtocol(ColorPaletteButtonDrawing)
  let action = actionSelector("colorPickerPalette" & $index)
  result.target = newActionTarget(
    action,
    proc(sender: DynamicAgent) =
      discard sender
      discard well.activateColorAtIndex(index),
  )
  result.action = action

protocol ColorPaletteLayout of ViewLayoutProtocol:
  method layoutSubviews(palette: ColorPaletteView) =
    let
      count = palette.xPicker.xPaletteButtons.len
      columns = min(max(count, 1), ColorPaletteColumns)
      rows = max((count + columns - 1) div columns, 1)
      totalWidth =
        float32(columns) * ColorPaletteSwatchSize +
        float32(columns - 1) * ColorPaletteSpacing
      totalHeight =
        float32(rows) * ColorPaletteSwatchSize + float32(rows - 1) * ColorPaletteSpacing
      startX =
        palette.bounds().origin.x +
        max((palette.bounds().size.width - totalWidth) * 0.5'f32, 0.0'f32)
      startY =
        palette.bounds().origin.y +
        max((palette.bounds().size.height - totalHeight) * 0.5'f32, 0.0'f32)
    for index, button in palette.xPicker.xPaletteButtons:
      let
        column = index mod columns
        row = index div columns
      button.frame = rect(
        startX + float32(column) * (ColorPaletteSwatchSize + ColorPaletteSpacing),
        startY + float32(row) * (ColorPaletteSwatchSize + ColorPaletteSpacing),
        ColorPaletteSwatchSize,
        ColorPaletteSwatchSize,
      )

proc newColorPaletteView(picker: ColorPicker): ColorPaletteView =
  result = ColorPaletteView(xPicker: picker)
  initViewFields(result)
  result.backgroundColor = color(0.0, 0.0, 0.0, 0.0)
  result.accessibilityRole = arGroup
  result.accessibilityLabel = "Color palette"
  discard result.withProtocol(ColorPaletteLayout)
  for index in 0 ..< picker.xSource.xChoices.len:
    let button = picker.xSource.newColorPaletteButton(index)
    picker.xPaletteButtons.add button
    result.addSubview(button)

func colorAtHsv(hue, saturation, value, alpha: float32): Color =
  result = color(hsv(hue, saturation, value))
  result.a = alpha

func wheelColor(wheel: ColorWheelView): Color =
  colorAtHsv(wheel.xHue, wheel.xSaturation, wheel.xValue, wheel.xAlpha)

proc wheelGeometry(
    wheel: ColorWheelView
): tuple[center: Point, outerRadius, innerRadius: float32] =
  let
    bounds = wheel.bounds()
    availableHeight = max(
      bounds.size.height - ColorWheelAlphaHeight - ColorWheelAlphaBottomInset * 2.0'f32,
      1.0'f32,
    )
    diameter = max(
      min(
        bounds.size.width - ColorWheelPageInset * 2.0'f32,
        availableHeight - ColorWheelPageInset,
      ),
      40.0'f32,
    )
    outerRadius = diameter * 0.5'f32
  (
    center: initPoint(
      bounds.origin.x + bounds.size.width * 0.5'f32,
      bounds.origin.y + ColorWheelPageInset + outerRadius,
    ),
    outerRadius: outerRadius,
    innerRadius: max(outerRadius - ColorWheelRingWidth, 1.0'f32),
  )

proc colorWellRect(wheel: ColorWheelView): Rect =
  let geometry = wheel.wheelGeometry()
  let side = geometry.innerRadius * 1.08'f32
  rect(
    geometry.center.x - side * 0.5'f32, geometry.center.y - side * 0.5'f32, side, side
  )

proc alphaRect(wheel: ColorWheelView): Rect =
  let
    geometry = wheel.wheelGeometry()
    bounds = wheel.bounds()
    availableWidth = max(
      bounds.size.width - ColorWheelPageInset * 2.0'f32 - ColorPickerOkayWidth -
        ColorPickerOkayGap,
      1.0'f32,
    )
  rect(
    bounds.origin.x + ColorWheelPageInset,
    bounds.origin.y + bounds.size.height - ColorWheelAlphaBottomInset -
      ColorWheelAlphaHeight,
    min(geometry.outerRadius * 2.0'f32, availableWidth),
    ColorWheelAlphaHeight,
  )

proc synchronizeFromSource(wheel: ColorWheelView) =
  if wheel.isNil or wheel.xSource.isNil:
    return
  let
    sourceColor = wheel.xSource.xColor
    converted = sourceColor.hsv()
  if converted.s > 0.0'f32 and converted.v > 0.0'f32:
    wheel.xHue = converted.h
  wheel.xSaturation = converted.s
  wheel.xValue = converted.v
  wheel.xAlpha = sourceColor.a
  wheel.needsDisplay = true

proc synchronizePicker(well: ColorWell) =
  if well.xPicker.isNil:
    return
  for button in well.xPicker.xPaletteButtons:
    button.needsDisplay = true
  well.xPicker.xWheelView.synchronizeFromSource()
  well.xPicker.xValuesView.synchronizeFromSource()

proc drawColorWellField(wheel: ColorWheelView, context: DrawContext) =
  let
    bounds = wheel.colorWellRect()
    hueColor = colorAtHsv(wheel.xHue, 100.0'f32, 100.0'f32, 1.0'f32)
    transparentBlack = color(0.0, 0.0, 0.0, 0.0)
  discard context.addRenderRectangle(
    context.renderRectFor(bounds), linear(color(1.0, 1.0, 1.0, 1.0), hueColor, fgaX)
  )
  discard context.addRenderRectangle(
    context.renderRectFor(bounds),
    linear(transparentBlack, color(0.0, 0.0, 0.0, 1.0), fgaY),
  )
  discard context.addRenderRectangle(
    context.renderRectFor(bounds),
    fill(transparentBlack),
    color(0.16, 0.18, 0.22, 0.9),
    1.0'f32,
    3.0'f32,
  )
  let marker = initPoint(
    bounds.origin.x + bounds.size.width * wheel.xSaturation / 100.0'f32,
    bounds.origin.y + bounds.size.height * (1.0'f32 - wheel.xValue / 100.0'f32),
  )
  discard context.addRenderCircle(marker, fill(color(0.0, 0.0, 0.0, 0.85)), 6.0'f32)
  discard context.addRenderCircle(marker, fill(color(1.0, 1.0, 1.0, 1.0)), 4.0'f32)

proc drawHueWheel(wheel: ColorWheelView, context: DrawContext) =
  let
    geometry = wheel.wheelGeometry()
    middleRadius = (geometry.outerRadius + geometry.innerRadius) * 0.5'f32
    segmentWeight = max(
      2.0'f32 * PI.float32 * middleRadius / float32(ColorWheelSegments) + 1.0'f32,
      4.0'f32,
    )
  for index in 0 ..< ColorWheelSegments:
    let
      hue = float32(index) * 360.0'f32 / float32(ColorWheelSegments)
      radians = hue * PI.float32 / 180.0'f32
      direction = initPoint(sin(radians), -cos(radians))
      start = initPoint(
        geometry.center.x + direction.x * geometry.innerRadius,
        geometry.center.y + direction.y * geometry.innerRadius,
      )
      stop = initPoint(
        geometry.center.x + direction.x * geometry.outerRadius,
        geometry.center.y + direction.y * geometry.outerRadius,
      )
    discard context.addRenderLine(
      start, stop, fill(colorAtHsv(hue, 100.0'f32, 100.0'f32, 1.0'f32)), segmentWeight
    )
  let
    selectedRadians = wheel.xHue * PI.float32 / 180.0'f32
    selectedPoint = initPoint(
      geometry.center.x + sin(selectedRadians) * middleRadius,
      geometry.center.y - cos(selectedRadians) * middleRadius,
    )
  discard
    context.addRenderCircle(selectedPoint, fill(color(0.0, 0.0, 0.0, 0.85)), 7.0'f32)
  discard
    context.addRenderCircle(selectedPoint, fill(color(1.0, 1.0, 1.0, 1.0)), 4.5'f32)

proc drawAlphaControl(wheel: ColorWheelView, context: DrawContext) =
  let
    bounds = wheel.alphaRect()
    opaque = colorAtHsv(wheel.xHue, wheel.xSaturation, wheel.xValue, 1.0'f32)
    clear = color(opaque.r, opaque.g, opaque.b, 0.0'f32)
  let background = context.drawTransparencyBackground(bounds)
  discard context.addRenderRectangle(
    background,
    context.renderRectFor(bounds),
    linear(clear, opaque, fgaX),
    color(0.20, 0.22, 0.26, 0.9),
    1.0'f32,
    3.0'f32,
  )
  let markerX = bounds.origin.x + bounds.size.width * wheel.xAlpha
  discard context.addRenderRectangle(
    context.renderRectFor(
      rect(
        markerX - 2.0'f32,
        bounds.origin.y - 2.0'f32,
        4.0'f32,
        bounds.size.height + 4.0'f32,
      )
    ),
    fill(color(1.0, 1.0, 1.0, 0.9)),
    color(0.0, 0.0, 0.0, 0.9),
    1.0'f32,
    2.0'f32,
  )

protocol ColorWheelDrawing of ViewDrawingProtocol:
  method draw(wheel: ColorWheelView, context: DrawContext) =
    discard wheel.performNext(draw, context)
    wheel.drawHueWheel(context)
    wheel.drawColorWellField(context)
    wheel.drawAlphaControl(context)

proc pickerPartAt(wheel: ColorWheelView, point: Point): ColorPickerPart =
  if wheel.colorWellRect().contains(point):
    return cppWell
  if wheel.alphaRect().contains(point):
    return cppAlpha
  let
    geometry = wheel.wheelGeometry()
    dx = point.x - geometry.center.x
    dy = point.y - geometry.center.y
    distance = sqrt(dx * dx + dy * dy)
  if distance >= geometry.innerRadius - 3.0'f32 and
      distance <= geometry.outerRadius + 3.0'f32: cppWheel else: cppNone

proc updateColorAtPoint(wheel: ColorWheelView, point: Point, part: ColorPickerPart) =
  case part
  of cppWheel:
    let geometry = wheel.wheelGeometry()
    var degrees =
      arctan2(point.x - geometry.center.x, geometry.center.y - point.y) * 180.0'f32 /
      PI.float32
    if degrees < 0.0'f32:
      degrees += 360.0'f32
    wheel.xHue = degrees
  of cppWell:
    let bounds = wheel.colorWellRect()
    wheel.xSaturation =
      ((point.x - bounds.origin.x) / max(bounds.size.width, 1.0'f32)).clampUnit() *
      100.0'f32
    wheel.xValue =
      (
        1.0'f32 -
        ((point.y - bounds.origin.y) / max(bounds.size.height, 1.0'f32)).clampUnit()
      ) * 100.0'f32
  of cppAlpha:
    let bounds = wheel.alphaRect()
    wheel.xAlpha =
      ((point.x - bounds.origin.x) / max(bounds.size.width, 1.0'f32)).clampUnit()
  of cppNone:
    return
  discard wheel.xSource.applyPickerColor(wheel.wheelColor())
  wheel.needsDisplay = true

protocol ColorWheelInteraction of ResponderEventProtocol:
  method mouseDown(wheel: ColorWheelView, event: MouseEvent): bool =
    if event.button != mbPrimary:
      return false
    wheel.xActivePart = wheel.pickerPartAt(event.location)
    if wheel.xActivePart == cppNone:
      return false
    wheel.updateColorAtPoint(event.location, wheel.xActivePart)
    true

  method mouseDragged(wheel: ColorWheelView, event: MouseEvent): bool =
    if wheel.xActivePart == cppNone:
      return false
    wheel.updateColorAtPoint(event.location, wheel.xActivePart)
    true

  method mouseUp(wheel: ColorWheelView, event: MouseEvent): bool =
    if wheel.xActivePart == cppNone or event.button != mbPrimary:
      return false
    wheel.updateColorAtPoint(event.location, wheel.xActivePart)
    wheel.xActivePart = cppNone
    true

proc newColorWheelView(well: ColorWell): ColorWheelView =
  result = ColorWheelView(xSource: well)
  initViewFields(result)
  result.backgroundColor = color(0.0, 0.0, 0.0, 0.0)
  result.acceptsFirstResponder = true
  result.accessibilityRole = arGroup
  result.accessibilityLabel = "Color wheel"
  discard result.withProtocol(ColorWheelDrawing)
  discard result.withProtocol(ColorWheelInteraction)
  result.synchronizeFromSource()

func cssColorString(value: Color): string =
  if value.a >= 0.999'f32:
    value.toHtmlHex()
  else:
    value.toHtmlRgba()

func colorComponents(value: Color): array[4, float32] =
  [value.r, value.g, value.b, value.a]

proc synchronizeFromSource(values: ColorValuesView) =
  if values.isNil or values.xSource.isNil:
    return
  let components = values.xSource.xColor.colorComponents()
  values.xCssField.stringValue = values.xSource.xColor.cssColorString()
  values.xCssField.accessibilityHelp = CssColorHelp
  values.xStatusLabel.text = CssColorHelp
  for index in 0 .. 3:
    values.xSliders[index].value = components[index]
    values.xValueLabels[index].text = components[index].formatFloat(ffDecimal, 2)

proc applySliderColor(values: ColorValuesView) =
  discard values.xSource.applyPickerColor(
    color(
      values.xSliders[0].value(),
      values.xSliders[1].value(),
      values.xSliders[2].value(),
      values.xSliders[3].value(),
    )
  )

proc applyCssColor(values: ColorValuesView): bool =
  let input = values.xCssField.stringValue().strip()
  if input.len == 0:
    values.xStatusLabel.text = "Enter a CSS color."
    return
  try:
    let parsed = parseHtmlColor(input)
    discard values.xSource.applyPickerColor(parsed)
    values.synchronizeFromSource()
    true
  except CatchableError:
    values.xStatusLabel.text = "Invalid CSS color."
    values.xCssField.accessibilityHelp = "Invalid CSS color: " & input
    false

protocol ColorValuesLayout of ViewLayoutProtocol:
  method layoutSubviews(values: ColorValuesView) =
    let
      bounds = values.bounds()
      horizontalInset = 12.0'f32
      fieldLabelWidth = 68.0'f32
      componentLabelWidth = 18.0'f32
      valueLabelWidth = 42.0'f32
      rowHeight = 30.0'f32
      fieldX = horizontalInset + fieldLabelWidth + 6.0'f32
    values.xCssLabel.frame = rect(horizontalInset, 12.0'f32, fieldLabelWidth, rowHeight)
    values.xCssField.frame = rect(
      fieldX,
      12.0'f32,
      max(bounds.size.width - fieldX - horizontalInset, 1.0'f32),
      rowHeight,
    )
    values.xStatusLabel.frame = rect(
      horizontalInset,
      46.0'f32,
      max(bounds.size.width - horizontalInset * 2.0'f32, 1.0'f32),
      24.0'f32,
    )
    for index in 0 .. 3:
      let
        rowY = 76.0'f32 + float32(index) * 42.0'f32
        sliderX = horizontalInset + componentLabelWidth + 6.0'f32
        valueX = bounds.size.width - horizontalInset - valueLabelWidth
      values.xComponentLabels[index].frame =
        rect(horizontalInset, rowY, componentLabelWidth, rowHeight)
      values.xSliders[index].frame =
        rect(sliderX, rowY, max(valueX - sliderX - 6.0'f32, 1.0'f32), rowHeight)
      values.xValueLabels[index].frame = rect(valueX, rowY, valueLabelWidth, rowHeight)

proc newColorValuesView(well: ColorWell): ColorValuesView =
  result = ColorValuesView(xSource: well)
  initViewFields(result)
  result.backgroundColor = color(0.0, 0.0, 0.0, 0.0)
  result.accessibilityRole = arGroup
  result.accessibilityLabel = "Color values"
  result.xCssLabel = newFormLabel("CSS Color")
  result.xCssField = newTextField()
  result.xCssField.accessibilityLabel = "CSS color"
  result.xCssField.toolTip = CssColorHelp
  result.xCssField.textFieldCell().sendsActionOnEndEditing = true
  result.xStatusLabel = newStatusLabel(CssColorHelp)
  let
    values = result
    cssAction = actionSelector("colorPickerCssChanged")
    sliderAction = actionSelector("colorPickerRgbaChanged")
  result.xCssField.target = newActionTarget(
    cssAction,
    proc(sender: DynamicAgent) =
      discard sender
      discard values.applyCssColor(),
  )
  result.xCssField.action = cssAction
  let sliderTarget = newActionTarget(
    sliderAction,
    proc(sender: DynamicAgent) =
      discard sender
      values.applySliderColor(),
  )
  result.addSubview(result.xCssLabel)
  result.addSubview(result.xCssField)
  result.addSubview(result.xStatusLabel)
  for index in 0 .. 3:
    result.xComponentLabels[index] = newFormLabel(ColorComponentNames[index])
    result.xValueLabels[index] = newStatusLabel("")
    result.xSliders[index] = newSlider(0.0'f32, 1.0'f32)
    result.xSliders[index].stepValue = 0.01'f32
    result.xSliders[index].accessibilityLabel =
      ColorComponentNames[index] & " color component"
    result.xSliders[index].target = sliderTarget
    result.xSliders[index].action = sliderAction
    result.addSubview(result.xComponentLabels[index])
    result.addSubview(result.xSliders[index])
    result.addSubview(result.xValueLabels[index])
  discard result.withProtocol(ColorValuesLayout)
  result.synchronizeFromSource()

proc applyCssColor*(picker: ColorPicker, input: string): bool {.discardable.} =
  if picker.isNil or picker.xValuesView.isNil:
    return
  picker.xValuesView.xCssField.stringValue = input
  picker.xValuesView.applyCssColor()

proc newColorPickerOkayButton(picker: ColorPicker): Button =
  let action = actionSelector("colorPickerOkay")
  result = newButton(
    "OK",
    rect(
      ColorPickerWidth - ColorPickerOkayInset - ColorPickerOkayWidth,
      ColorPickerHeight - ColorPickerOkayInset - ColorPickerOkayHeight,
      ColorPickerOkayWidth,
      ColorPickerOkayHeight,
    ),
  )
  result.target = newActionTarget(
    action,
    proc(sender: DynamicAgent) =
      discard sender
      picker.xSource.closePopup(),
  )
  result.action = action

proc initColorPickerFields*(picker: ColorPicker, source: ColorWell, frame = AutoRect) =
  initTabViewFields(picker, frame)
  picker.xSource = source
  let
    palette = newColorPaletteView(picker)
    wheel = newColorWheelView(source)
    values = newColorValuesView(source)
  picker.xWheelView = wheel
  picker.xValuesView = values
  picker.accessibilityLabel = "Color picker"
  discard picker.addTabViewItem(newTabViewItem("Palette", palette, "palette"))
  discard picker.addTabViewItem(newTabViewItem("Wheel", wheel, "wheel"))
  discard picker.addTabViewItem(newTabViewItem("Values", values, "values"))
  picker.xOkayButton = picker.newColorPickerOkayButton()
  picker.addSubview(picker.xOkayButton)

proc newColorPicker*(source: ColorWell, frame = AutoRect): ColorPicker =
  result = ColorPicker()
  result.initColorPickerFields(source, frame)

proc ownerWindow(well: ColorWell): Window =
  let owner = well.window()
  if owner of Window:
    result = Window(owner)

proc clearPopupState(well: ColorWell) =
  well.xPopupOpen = false
  well.xPopupWindow = nil
  well.xPicker = nil
  well.setWidgetState(ssOpen, false)
  well.needsDisplay = true

proc dismissPopup(well: ColorWell, reason: DismissReason) =
  discard reason
  let popupWindow = well.xPopupWindow
  well.clearPopupState()
  if not popupWindow.isNil and not popupWindow.isClosed():
    popupWindow.close()

proc openPopup*(well: ColorWell) =
  if well.xPopupOpen or not well.isEnabled():
    return
  let owner = well.ownerWindow()
  if owner.isNil:
    return
  let
    size = initSize(ColorPickerWidth, ColorPickerHeight)
    picker = newColorPicker(well, rect(0.0, 0.0, size.width, size.height))
    popupWindow =
      owner.newPopupWindow(well.rectToWindow(well.bounds()), size, "Color Picker")
  popupWindow.setContentView(picker)
  well.xPopupOpen = true
  well.xPopupWindow = popupWindow
  well.xPicker = picker
  well.setWidgetState(ssOpen, true)
  well.needsDisplay = true
  popupWindow.setPopupDoneHandler(
    proc() =
      if well.xPopupWindow != popupWindow:
        return
      if owner.hasActiveTransientSession() and owner.transientWindow() == popupWindow:
        discard owner.dismissTransientSession(tdrNativeDone)
      else:
        well.clearPopupState()
  )
  owner.beginTransientSession(
    owner = Responder(well),
    transientWindow = popupWindow,
    restoreResponder = Responder(well),
    onDismiss = proc(reason: DismissReason) =
      well.dismissPopup(reason),
  )
  popupWindow.setInitialFirstResponder(picker)
  popupWindow.makeKeyAndOrderFront()
  if owner.nativeReady():
    popupWindow.ensureNativeWindow()
  discard popupWindow.makeFirstResponder(picker)

proc closePopup*(well: ColorWell) =
  let
    owner = well.ownerWindow()
    popupWindow = well.xPopupWindow
  if not well.xPopupOpen and popupWindow.isNil:
    return
  well.clearPopupState()
  if not owner.isNil and owner.hasActiveTransientSession() and
      owner.transientWindow() == popupWindow:
    discard owner.endTransientSession()
  if not popupWindow.isNil and not popupWindow.isClosed():
    popupWindow.close()

proc activateColorAtIndex*(well: ColorWell, index: int): bool {.discardable.} =
  if index notin 0 ..< well.xChoices.len:
    return
  well.applyPickerColor(well.xChoices[index].color)

protocol ColorWellInteraction of ResponderEventProtocol:
  method mouseExited(well: ColorWell, event: MouseEvent): bool =
    discard event
    well.cell().setHighlighted(false)
    true

  method mouseDown(well: ColorWell, event: MouseEvent): bool =
    if well.isEnabled() and event.button == mbPrimary:
      well.cell().setHighlighted(true)
      return true

  method mouseUp(well: ColorWell, event: MouseEvent): bool =
    if well.isEnabled() and event.button == mbPrimary:
      let clicked = well.bounds().contains(event.location)
      well.cell().setHighlighted(false)
      if clicked:
        well.popupOpen = not well.popupOpen()
      return true

  method keyDown(well: ColorWell, event: KeyEvent): bool =
    if not well.isEnabled():
      return false
    case event.key
    of keyEnter, keySpace, keyArrowDown:
      well.openPopup()
      true
    of keyEscape:
      if well.popupOpen():
        well.closePopup()
        true
      else:
        false
    else:
      false

protocol ColorWellAccessibility of AccessibilityProtocol:
  method accessibilityRole(well: ColorWell): AccessibilityRole =
    arPopupButton

  method accessibilityLabel(well: ColorWell): string =
    if well.xAccessibilityLabel.len > 0: well.xAccessibilityLabel else: "Color"

  method accessibilityValue(well: ColorWell): string =
    well.selectedTitle()

  method accessibilityTraits(well: ColorWell): AccessibilityTraits =
    result = well.xAccessibilityTraits + {atButton}
    if not well.isEnabled():
      result.incl atDisabled
    if well.focused():
      result.incl atFocused

  method isAccessibilityElement(well: ColorWell): bool =
    true

  method accessibilityActionNames(well: ColorWell): seq[string] =
    @[AccessibilityActionShowMenu]

  method accessibilityPerformAction(well: ColorWell, action: string): bool =
    if action != AccessibilityActionShowMenu or not well.isEnabled():
      return false
    well.openPopup()
    true

proc initColorWellFields*(
    well: ColorWell,
    choices: openArray[ColorWellChoice],
    selectedColor: Color,
    frame = AutoRect,
) =
  initControlFields(well, frame, newColorWellCell())
  well.xChoices = @choices
  well.xColor = selectedColor
  well.backgroundColor = color(0.0, 0.0, 0.0, 0.0)
  well.acceptsFirstResponder = true
  well.setHuggingPriority(LayoutPriorityHigh, laHorizontal)
  well.setCompressionPriority(LayoutPriorityHigh, laHorizontal)
  discard well.withProto()
  discard well.withProtocol(ColorWellDrawing)
  discard well.withProtocol(ColorWellInteraction)
  discard well.withProtocol(ColorWellAccessibility)
  well.applyInitialFrame(frame)

proc newColorWell*(
    choices: openArray[ColorWellChoice],
    selectedColor = color(0.20, 0.48, 0.92, 1.0),
    frame = AutoRect,
): ColorWell =
  result = ColorWell()
  result.initColorWellFields(choices, selectedColor, frame)

proc newColorWell*(
    selectedColor = color(0.20, 0.48, 0.92, 1.0), frame = AutoRect
): ColorWell =
  newColorWell(defaultColorWellChoices(), selectedColor, frame)

proc color*(well: PopupColorWell): Color =
  well.xColor

proc choices*(well: PopupColorWell): lent seq[PopupColorChoice] =
  well.xChoices

proc selectedIndex*(well: PopupColorWell): int =
  for index, choice in well.xChoices:
    if choice.color == well.xColor:
      return index
  -1

proc choiceTitle(well: PopupColorWell): string =
  let index = well.selectedIndex()
  if index >= 0:
    well.xChoices[index].title
  else:
    "Custom"

proc synchronizeChoiceState(well: PopupColorWell) =
  let selected = well.selectedIndex()
  if not well.menu().isNil:
    for index, item in well.menu().items():
      item.state = if index == selected: bsOn else: bsOff
  PopupMenuButton(well).title = "      " & well.choiceTitle()
  well.accessibilityValue = well.choiceTitle()

proc `color=`*(well: PopupColorWell, value: Color) =
  if well.xColor == value:
    well.synchronizeChoiceState()
    return
  well.xColor = value
  well.synchronizeChoiceState()
  well.needsDisplay = true

proc activateColorAtIndex*(well: PopupColorWell, index: int): bool {.discardable.} =
  if index notin 0 ..< well.xChoices.len:
    return
  well.color = well.xChoices[index].color
  emit well.colorDidChange(DynamicAgent(well))
  discard well.sendAction()
  true

protocol PopupColorWellDrawing of ViewDrawingProtocol:
  method draw(well: PopupColorWell, context: DrawContext) =
    discard well.performNext(draw, context)
    let
      bounds = well.bounds()
      swatchSize = max(min(bounds.size.height - 10.0'f32, 18.0'f32), 0.0'f32)
      swatch = rect(
        bounds.origin.x + 7.0'f32,
        bounds.origin.y + (bounds.size.height - swatchSize) * 0.5'f32,
        swatchSize,
        swatchSize,
      )
    discard context.addRenderRectangle(
      context.renderRectFor(swatch),
      fill(well.xColor),
      color(0.28, 0.30, 0.34, 0.85),
      1.0'f32,
      3.0'f32,
    )

proc newColorChoiceMenuItem(well: PopupColorWell, index: int): MenuItem =
  let action = actionSelector("popupColorWellChoose" & $index)
  result = newMenuItem(well.xChoices[index].title, action)
  result.identifier = "color." & $index
  result.validates = false
  result.target = newActionTarget(
    action,
    proc(sender: DynamicAgent) =
      discard sender
      discard well.activateColorAtIndex(index),
  )

proc rebuildMenu(well: PopupColorWell) =
  let menu = newMenu("Colors")
  for index in 0 ..< well.xChoices.len:
    discard menu.addItem(well.newColorChoiceMenuItem(index))
  well.menu = menu
  well.synchronizeChoiceState()

proc initPopupColorWellFields*(
    well: PopupColorWell,
    choices: openArray[PopupColorChoice],
    selectedColor: Color,
    frame = AutoRect,
) =
  initPopupMenuButtonFields(well, frame = frame)
  well.xChoices = @choices
  well.xColor = selectedColor
  well.rebuildMenu()
  well.accessibilityLabel = "Color"
  discard well.withProtocol(PopupColorWellDrawing)

proc newPopupColorWell*(
    choices: openArray[PopupColorChoice],
    selectedColor = color(0.08, 0.09, 0.11, 1.0),
    frame = AutoRect,
): PopupColorWell =
  result = PopupColorWell()
  result.initPopupColorWellFields(choices, selectedColor, frame)

proc newPopupColorWell*(
    selectedColor = color(0.08, 0.09, 0.11, 1.0), frame = AutoRect
): PopupColorWell =
  newPopupColorWell(defaultPopupColorChoices(), selectedColor, frame)
