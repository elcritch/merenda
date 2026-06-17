import ./controls
import ./selectors
import ./theme
import ./events
import ./types

export controls

type
  Button* = ref object of Control

  ButtonCell* = ref object of ActionCell
    xTitle: string
    xReservedTitles: seq[string]
    xButtonType: ButtonType

const CheckboxCheckmark = "✓"
const AquaButtonInset = 2.5'f32

proc updateButtonLayoutPriorities(cell: ButtonCell) =
  let view = cell.controlView()
  if view of Button:
    let button = Button(view)
    if cell.xButtonType in {btCheckBox, btRadio}:
      button.setHuggingPriority(LayoutPriorityHigh, laHorizontal)
    else:
      button.setHuggingPriority(LayoutPriorityLow, laHorizontal)

proc buttonStyleContext(cell: ButtonCell, role: StyleRole): StyleContext =
  let view = cell.controlView()
  if view of Button:
    let button = Button(view)
    var states: set[WidgetState] = button.widgetStateSet()
    if Cell(cell).state() in {bsOn, bsMixed}:
      states.incl ssSelected
    return initControlStyleContext(
      role, states = states, id = button.styleId, classes = button.styleClasses
    )
  var states: set[WidgetState] = {}
  if not cell.isEnabled:
    states.incl ssDisabled
  if cell.state in {bsOn, bsMixed}:
    states.incl ssSelected
  initControlStyleContext(role, states = states)

protocol ButtonProtocol {.selectorScope: protocol.}:
  property title -> string
  property state -> ButtonState
  property buttonType -> ButtonType
  property allowsMixedState -> bool

  method isHighlighted*(): bool
  method setHighlighted*(highlighted: bool)

proc buttonTextSize(cell: ButtonCell): Size =
  result = textNaturalSize(cell.title())
  for title in cell.xReservedTitles:
    let titleSize = textNaturalSize(title)
    result.width = max(result.width, titleSize.width)
    result.height = max(result.height, titleSize.height)

protocol DefaultButtonCell of ButtonProtocol:
  method title(cell: ButtonCell): string =
    cell.xTitle

  method setTitle(cell: ButtonCell, title: string) =
    if cell.xTitle == title:
      return
    cell.xTitle = title
    cell.invalidateControlMetrics()

  method state(cell: ButtonCell): ButtonState =
    Cell(cell).state()

  method setState(cell: ButtonCell, state: ButtonState) =
    Cell(cell).setState(state)

  method buttonType(cell: ButtonCell): ButtonType =
    cell.xButtonType

  method setButtonType(cell: ButtonCell, buttonType: ButtonType) =
    if cell.xButtonType == buttonType:
      return
    cell.xButtonType = buttonType
    if buttonType == btRadio:
      cell.setAllowsMixedState(false)
    cell.updateButtonLayoutPriorities()
    cell.invalidateControlMetrics()

  method allowsMixedState(cell: ButtonCell): bool =
    Cell(cell).allowsMixedState()

  method setAllowsMixedState(cell: ButtonCell, value: bool) =
    if value and cell.xButtonType == btRadio:
      return
    Cell(cell).setAllowsMixedState(value)

  method isHighlighted(cell: ButtonCell): bool =
    Cell(cell).isHighlighted()

  method setHighlighted(cell: ButtonCell, highlighted: bool) =
    Cell(cell).setHighlighted(highlighted)

protocol DefaultButtonCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: ButtonCell): IntrinsicSize =
    let
      textSize = cell.buttonTextSize()
      view = cell.controlView()
      appearance =
        if view.isNil:
          initAppearance()
        else:
          view.effectiveAppearance()
    if cell.buttonType() in {btCheckBox, btRadio}:
      let style = appearance.resolveChoiceButtonStyle(
        cell.buttonStyleContext(
          if cell.buttonType() == btRadio: srRadioButton else: srCheckBox
        )
      )
      return initIntrinsicSize(style.choiceControlSize(textSize))

    let style = appearance.resolveButtonStyle(cell.buttonStyleContext(srButton))
    initIntrinsicSize(style.buttonControlSize(textSize))

  method cellSizeForBounds(cell: ButtonCell, bounds: Rect): Size =
    cell.cellSize().resolveIntrinsicSize(bounds.size)

proc initButtonCellFields*(cell: ButtonCell, title: string) =
  initActionCellFields(cell)
  cell.xTitle = title
  cell.xButtonType = btMomentary
  discard cell.withProtocol(DefaultButtonCell)
  discard cell.withProtocol(DefaultButtonCellMeasurement)

proc newButtonCell*(title = "Button"): ButtonCell =
  result = ButtonCell()
  initButtonCellFields(result, title)

proc buttonCell*(button: Button): ButtonCell =
  let controlCell = button.cell()
  if controlCell of ButtonCell:
    return ButtonCell(controlCell)

proc reservedTitles*(button: Button): seq[string] =
  let cell = button.buttonCell()
  if cell.isNil:
    return @[]
  cell.xReservedTitles

proc `reservedTitles=`*(button: Button, titles: openArray[string]) =
  let cell = button.buttonCell()
  if cell.isNil:
    return
  let nextTitles = @titles
  if cell.xReservedTitles == nextTitles:
    return
  cell.xReservedTitles = nextTitles
  cell.invalidateControlMetrics()

proc `title=`*(button: Button, title: string) =
  button.setTitle(title)

proc `state=`*(button: Button, state: ButtonState) =
  button.setState(state)

proc `buttonType=`*(button: Button, buttonType: ButtonType) =
  button.setButtonType(buttonType)

proc `allowsMixedState=`*(button: Button, value: bool) =
  button.setAllowsMixedState(value)

proc highlighted*(button: Button): bool =
  (not button.isNil) and button.isHighlighted()

proc `highlighted=`*(button: Button, highlighted: bool) =
  if not button.isNil:
    button.setHighlighted(highlighted)

proc clearRadioSiblings(button: Button) =
  let parent = button.superview
  if parent.isNil:
    return
  for sibling in parent.subviews:
    if sibling != button and sibling of Button:
      let siblingButton = Button(sibling)
      if siblingButton.buttonType == btRadio and
          siblingButton.action() == button.action() and siblingButton.state != bsOff:
        siblingButton.setState(bsOff)

proc buttonPerformClick(button: Button, args: ActionArgs) =
  if not button.isEnabled or args.sender.isNil:
    return
  case button.buttonType
  of btMomentary:
    discard
  of btToggle, btCheckBox:
    button.buttonCell().setNextState()
  of btRadio:
    button.setState(bsOn)
    button.clearRadioSiblings()
  discard button.sendAction()

proc choiceRole(button: Button): StyleRole =
  if button.buttonType == btRadio: srRadioButton else: srCheckBox

proc selectedMarkRect(rect: Rect): Rect =
  let inset = max(rect.size.width * 0.28'f32, 3.0'f32)
  rect.inset(initEdgeInsets(inset))

proc mixedMarkRect(rect: Rect): Rect =
  let
    height = max(rect.size.height * 0.16'f32, 2.0'f32)
    inset = max(rect.size.width * 0.24'f32, 3.0'f32)
  initRect(
    rect.origin.x + inset,
    rect.origin.y + (rect.size.height - height) / 2.0'f32,
    rect.size.width - inset * 2.0'f32,
    height,
  )

func clampUnit(value: float32): float32 =
  min(max(value, 0.0'f32), 1.0'f32)

func lightenColor(color: Color, amount: float32, alpha: float32): Color =
  let mix = amount.clampUnit
  initColor(
    color.r + (1.0'f32 - color.r) * mix,
    color.g + (1.0'f32 - color.g) * mix,
    color.b + (1.0'f32 - color.b) * mix,
    alpha.clampUnit,
  )

func darkenColor(color: Color, amount: float32, alpha: float32): Color =
  let mix = 1.0'f32 - amount.clampUnit
  initColor(color.r * mix, color.g * mix, color.b * mix, alpha.clampUnit)

func colorSaturation(color: Color): float32 =
  let
    high = max(max(color.r, color.g), color.b)
    low = min(min(color.r, color.g), color.b)
  high - low

func aquaFaceFill(fillValue: Fill, enabled: bool): Fill =
  let
    base = fillValue.centerColor()
    saturated = base.colorSaturation() > 0.18'f32
    topMix = if saturated: 0.58'f32 else: 0.82'f32
    bottomMix = if saturated: 0.14'f32 else: 0.46'f32
    alpha = if enabled: 0.92'f32 else: 0.58'f32
  linear(base.lightenColor(topMix, alpha), base.lightenColor(bottomMix, alpha), fgaY)

func aquaLowerWash(fillValue: Fill, enabled: bool): Fill =
  let
    base = fillValue.centerColor()
    saturated = base.colorSaturation() > 0.18'f32
    alpha =
      if not enabled:
        0.10'f32
      elif saturated:
        0.28'f32
      else:
        0.22'f32
    tint =
      if saturated:
        base.lightenColor(0.10'f32, alpha)
      else:
        base.darkenColor(0.15'f32, alpha)
  linear(initColor(1.0, 1.0, 1.0, 0.0), tint, fgaY)

func aquaGlossFill(enabled: bool): Fill =
  let alpha = if enabled: 0.62'f32 else: 0.24'f32
  linear(initColor(1.0, 1.0, 1.0, alpha), initColor(1.0, 1.0, 1.0, 0.0), fgaY)

func aquaInnerShadows(fillValue: Fill, enabled: bool): seq[BoxShadow] =
  let
    base = fillValue.centerColor()
    saturated = base.colorSaturation() > 0.18'f32
    darkAlpha =
      if not enabled:
        0.08'f32
      elif saturated:
        0.16'f32
      else:
        0.10'f32
  @[
    insetShadow(
      initColor(1.0, 1.0, 1.0, if enabled: 0.38 else: 0.14), y = 2.0, blur = 7.0
    ),
    insetShadow(initColor(0.0, 0.0, 0.0, darkAlpha), y = -2.0, blur = 7.0),
  ]

func offsetRect(rect: Rect, dx, dy: float32): Rect =
  initRect(rect.origin.x + dx, rect.origin.y + dy, rect.size.width, rect.size.height)

proc drawAquaPushButton(
    button: Button, context: DrawContext, absoluteFrame: Rect, style: ButtonStyle
) =
  let
    enabled = button.isEnabled()
    radius = style.box.cornerRadius
    buttonRoot = context.addRenderRectangle(
      absoluteFrame,
      style.box.fill,
      style.box.borderColor,
      style.box.borderWidth,
      radius,
      style.box.shadows,
      maskContent = true,
    )
    inner = absoluteFrame.inset(initEdgeInsets(AquaButtonInset))
  if not inner.isEmpty:
    let
      innerRadius = max(radius - AquaButtonInset, 1.0'f32)
      innerRoot = context.addRenderRectangle(
        buttonRoot,
        inner,
        aquaFaceFill(style.box.fill, enabled),
        initColor(0.0, 0.0, 0.0, 0.0),
        0.0'f32,
        innerRadius,
        aquaInnerShadows(style.box.fill, enabled),
        maskContent = true,
      )
      topGloss = initRect(
        inner.origin.x - 4.0'f32,
        inner.origin.y,
        inner.size.width + 8.0'f32,
        inner.size.height * 0.62'f32,
      )
      lowerWash = initRect(
        inner.origin.x - 4.0'f32,
        inner.origin.y + inner.size.height * 0.36'f32,
        inner.size.width + 8.0'f32,
        inner.size.height * 0.64'f32,
      )
      topGlow = initRect(
        inner.origin.x - 8.0'f32,
        inner.origin.y + 1.0'f32,
        inner.size.width + 16.0'f32,
        1.0'f32,
      )
      waistGlow = initRect(
        inner.origin.x - 8.0'f32,
        inner.origin.y + inner.size.height * 0.49'f32,
        inner.size.width + 16.0'f32,
        1.0'f32,
      )

    discard context.addRenderRectangle(
      innerRoot,
      topGlow,
      initColor(0, 0, 0, 0),
      shadows = [
        dropShadow(
          initColor(1.0, 1.0, 1.0, if enabled: 0.46 else: 0.16), y = 1.2, blur = 5.0
        )
      ],
    )
    discard context.addRenderRectangle(innerRoot, topGloss, aquaGlossFill(enabled))
    discard context.addRenderRectangle(
      innerRoot, lowerWash, aquaLowerWash(style.box.fill, enabled)
    )
    discard context.addRenderRectangle(
      innerRoot,
      waistGlow,
      initColor(0, 0, 0, 0),
      shadows = [
        dropShadow(
          initColor(1.0, 1.0, 1.0, if enabled: 0.16 else: 0.06), y = 0.8, blur = 7.0
        ),
        dropShadow(
          initColor(0.0, 0.0, 0.0, if enabled: 0.08 else: 0.03), y = 4.0, blur = 8.0
        ),
      ],
    )

protocol DefaultButtonDrawing of ViewDrawingProtocol:
  method draw(button: Button, context: DrawContext) =
    let absoluteFrame = context.renderRectFor(button.bounds)
    if button.buttonType in {btCheckBox, btRadio}:
      let role = button.choiceRole()
      let selected = button.state in {bsOn, bsMixed}
      var states: set[WidgetState] = button.widgetStateSet()
      if selected:
        states.incl ssSelected

      let style = context.appearance.resolveChoiceButtonStyle(
        initControlStyleContext(
          role, states, id = button.styleId, classes = button.styleClasses
        )
      )
      let indicatorRect = style.choiceIndicatorRect(button.bounds)

      discard context.addRenderRectangle(
        context.renderRectFor(indicatorRect),
        style.indicator.fill,
        style.indicator.borderColor,
        style.indicator.borderWidth,
        style.indicator.cornerRadius,
        style.indicator.shadows,
      )
      if selected:
        if button.buttonType == btCheckBox and button.state == bsOn:
          context.addText(
            indicatorRect, CheckboxCheckmark, style.markColor, alignment = taCenter
          )
        else:
          let markRect =
            if button.state == bsMixed and button.buttonType == btCheckBox:
              indicatorRect.mixedMarkRect()
            else:
              indicatorRect.selectedMarkRect()
          discard context.addRenderRectangle(
            context.renderRectFor(markRect),
            style.markColor,
            style.markColor,
            0.0'f32,
            if button.buttonType == btRadio:
              markRect.size.width / 2.0'f32
            else:
              1.0'f32,
          )
      if button.isFocusVisible:
        context.addFocusRing(context.renderRectFor(indicatorRect), style.indicator)
      context.addText(
        style.choiceTextRect(button.bounds), button.title, style.text.color
      )
    else:
      let states = button.widgetStateSet()

      let style = context.appearance.resolveButtonStyle(
        initControlStyleContext(
          srButton, states, id = button.styleId, classes = button.styleClasses
        )
      )
      button.drawAquaPushButton(context, absoluteFrame, style)
      if button.isFocusVisible:
        context.addFocusRing(absoluteFrame, style.box)
      let textRect = style.buttonTextRect(button.bounds)
      context.addText(
        textRect.offsetRect(0.0, 1.0),
        button.title,
        initColor(1.0, 1.0, 1.0, if button.isEnabled: 0.42 else: 0.16),
        alignment = taCenter,
      )
      context.addText(
        textRect.offsetRect(0.0, -0.6'f32),
        button.title,
        initColor(0.0, 0.0, 0.0, if button.isEnabled: 0.20 else: 0.08),
        alignment = taCenter,
      )
      context.addText(textRect, button.title, style.text.color, alignment = taCenter)

protocol DefaultButtonEvents of ResponderEventProtocol:
  method mouseDown(button: Button, event: MouseEvent): bool =
    if button.isEnabled and event.button == mbPrimary:
      button.setHighlighted(true)
      return true

  method mouseDragged(button: Button, event: MouseEvent): bool =
    if button.isEnabled and event.button == mbPrimary:
      button.setHighlighted(button.pointInside(event.location))
      return true

  method mouseUp(button: Button, event: MouseEvent): bool =
    if button.isEnabled and event.button == mbPrimary:
      let clicked = button.pointInside(event.location)
      button.setHighlighted(false)
      if clicked:
        button.buttonPerformClick(ActionArgs(sender: button))
      return true

protocol DefaultButtonAction of ButtonActionProtocol:
  method performClick(button: Button, args: ActionArgs) =
    button.buttonPerformClick(args)

protocol DefaultButtonKeyCommands of KeyViewCommandProtocol:
  method insertNewline(button: Button, args: ActionArgs) =
    button.buttonPerformClick(args)

proc initButtonFields*(button: Button, title = "Button", frame: Rect = AutoRect) =
  initControlFields(button, frame, newButtonCell(title))
  button.buttonCell().updateButtonLayoutPriorities()
  button.setAcceptsFirstResponder(true)
  discard button.withProtocol(DefaultButtonDrawing)
  discard button.withProtocol(DefaultButtonEvents)
  discard button.withProtocol(DefaultButtonAction)
  discard button.withProtocol(DefaultButtonKeyCommands)
  button.applyInitialFrame(frame)

proc newButton*(title = "Button", frame: Rect = AutoRect): Button =
  result = Button()
  initButtonFields(result, title, frame)

proc newCheckBox*(title = "Check Box", frame: Rect = AutoRect): Button =
  result = newButton(title, frame)
  result.setButtonType(btCheckBox)
  result.applyInitialFrame(frame)

proc newRadioButton*(title = "Radio", frame: Rect = AutoRect): Button =
  result = newButton(title, frame)
  result.setButtonType(btRadio)
  result.applyInitialFrame(frame)
