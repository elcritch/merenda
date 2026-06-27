import ./controls
import ../app/animations
import ../app/windows
import ../foundation/selectors
import ../drawing
import ../themes
import ../foundation/events
import ../foundation/types
import ../accessibility/accessibility
from pkg/chroma import ColorRGBA

export controls

type
  Button* = ref object of Control
    xHoverProgress: float32
    xHoverAnimation: Animation

  ButtonCell* = ref object of ActionCell
    xTitle: string
    xReservedTitles: seq[string]
    xButtonType: ButtonType

const CheckboxCheckmark = "✓"
const ButtonHoverAnimationMs = 120

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
    return controlStyle(
      role, states = states, id = button.styleId, classes = button.styleClasses
    )
  var states: set[WidgetState] = {}
  if not cell.isEnabled:
    states.incl ssDisabled
  if cell.state in {bsOn, bsMixed}:
    states.incl ssSelected
  controlStyle(role, states = states)

protocol ButtonProtocol {.selectorScope: protocol.}:
  property title -> string
  property state -> ButtonState
  property buttonType -> ButtonType
  property allowsMixedState -> bool

  method isHighlighted*(): bool
  method setHighlighted*(highlighted: bool)

protocol ButtonHoverProtocol {.selectorScope: protocol.}:
  property hoverProgress -> float32

func clampUnit(value: float32): float32 =
  min(max(value, 0.0'f32), 1.0'f32)

protocol DefaultButtonHover of ButtonHoverProtocol:
  method hoverProgress(button: Button): float32 =
    if button.isNil: 0.0'f32 else: button.xHoverProgress

  method setHoverProgress(button: Button, progress: float32) =
    if button.isNil:
      return
    let normalized = progress.clampUnit()
    if abs(button.xHoverProgress - normalized) <= 0.0001'f32:
      return
    button.xHoverProgress = normalized
    button.setNeedsDisplay(true)

proc buttonTextSize(cell: ButtonCell, style: TextStyle): Size =
  result = textNaturalSize(cell.title(), style)
  for title in cell.xReservedTitles:
    let titleSize = textNaturalSize(title, style)
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
      return initIntrinsicSize(style.choiceControlSize(cell.buttonTextSize(style.text)))

    let style = appearance.resolveButtonStyle(cell.buttonStyleContext(srButton))
    initIntrinsicSize(style.buttonControlSize(cell.buttonTextSize(style.text)))

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

proc stopHoverAnimation(button: Button) =
  if button.isNil or button.xHoverAnimation.isNil:
    return
  let owner = button.window()
  if owner of Window:
    discard Window(owner).stopAnimation(button.xHoverAnimation)
  else:
    button.xHoverAnimation.stop()
  button.xHoverAnimation = nil

proc animateHoverProgress(button: Button, progress: float32) =
  if button.isNil:
    return
  let target = progress.clampUnit()
  button.stopHoverAnimation()
  if abs(button.hoverProgress() - target) <= 0.0001'f32:
    return

  let animation = newPropertyAnimation[float32](
    DynamicAgent(button),
    setHoverProgress(),
    button.hoverProgress(),
    target,
    duration = initDuration(milliseconds = ButtonHoverAnimationMs),
  )
  animation.timing = easeOutTiming()
  button.xHoverAnimation = Animation(animation)
  let owner = button.window()
  if owner of Window:
    discard Window(owner).startAnimation(button.xHoverAnimation)
  else:
    button.setHoverProgress(target)

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

protocol DefaultButtonAccessibility of AccessibilityProtocol:
  method accessibilityRole(button: Button): AccessibilityRole =
    case button.buttonType()
    of btCheckBox: arCheckBox
    of btRadio: arRadioButton
    else: arButton

  method accessibilityLabel(button: Button): string =
    if button.xAccessibilityLabel.len > 0:
      button.xAccessibilityLabel
    else:
      button.title()

  method accessibilityValue(button: Button): string =
    case button.state()
    of bsOff: "off"
    of bsOn: "on"
    of bsMixed: "mixed"

  method accessibilityTraits(button: Button): AccessibilityTraits =
    result = button.xAccessibilityTraits + {atButton}
    if not button.isEnabled():
      result.incl atDisabled
    if button.focused():
      result.incl atFocused
    if button.state() in {bsOn, bsMixed}:
      result.incl atSelected

  method isAccessibilityElement(button: Button): bool =
    true

  method accessibilityActionNames(button: Button): seq[string] =
    @[AccessibilityActionPress]

  method accessibilityPerformAction(button: Button, action: string): bool =
    if action != AccessibilityActionPress or not button.isEnabled():
      return false
    button.buttonPerformClick(ActionArgs(sender: button))
    true

proc choiceRole(button: Button): StyleRole =
  if button.buttonType == btRadio: srRadioButton else: srCheckBox

proc choiceChromeRole(button: Button): ChromeRole =
  if button.buttonType == btRadio: crRadioIndicator else: crCheckBoxIndicator

proc selectedMarkRect(rect: Rect): Rect =
  let inset = max(rect.size.width * 0.33'f32, 3.0'f32)
  rect.inset(insets(inset))

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

func offsetRect(rect: Rect, dx, dy: float32): Rect =
  initRect(rect.origin.x + dx, rect.origin.y + dy, rect.size.width, rect.size.height)

func mixFloat(a, b, progress: float32): float32 =
  a + (b - a) * progress.clampUnit()

func mixColor(a, b: Color, progress: float32): Color =
  initColor(
    mixFloat(a.r, b.r, progress),
    mixFloat(a.g, b.g, progress),
    mixFloat(a.b, b.b, progress),
    mixFloat(a.a, b.a, progress),
  )

func rgbaColor(color: ColorRGBA): Color =
  initColor(
    color.r.float32 / 255.0'f32,
    color.g.float32 / 255.0'f32,
    color.b.float32 / 255.0'f32,
    color.a.float32 / 255.0'f32,
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

func canAnimateHover(states: set[WidgetState]): bool =
  ssDisabled notin states and ssHighlighted notin states and ssActive notin states and
    ssPressed notin states

func mixButtonStyle(
    baseStyle, hoverStyle: ButtonStyle, progress: float32
): ButtonStyle =
  let normalized = progress.clampUnit()
  if normalized <= 0.0'f32:
    return baseStyle
  if normalized >= 1.0'f32:
    return hoverStyle
  result = baseStyle
  result.box.fill = mixFill(baseStyle.box.fill, hoverStyle.box.fill, normalized)
  result.box.borderColor =
    mixColor(baseStyle.box.borderColor, hoverStyle.box.borderColor, normalized)

proc pushButtonStyle(
    button: Button, appearance: Appearance, states: set[WidgetState]
): ButtonStyle =
  if not states.canAnimateHover():
    return appearance.resolveButtonStyle(
      controlStyle(srButton, states, id = button.styleId, classes = button.styleClasses)
    )

  var baseStates = states
  baseStates.excl ssHovered
  var hoverStates = baseStates
  hoverStates.incl ssHovered

  let
    progress = button.hoverProgress()
    baseStyle = appearance.resolveButtonStyle(
      controlStyle(
        srButton, baseStates, id = button.styleId, classes = button.styleClasses
      )
    )
  if progress <= 0.0'f32:
    return baseStyle

  let hoverStyle = appearance.resolveButtonStyle(
    controlStyle(
      srButton, hoverStates, id = button.styleId, classes = button.styleClasses
    )
  )
  mixButtonStyle(baseStyle, hoverStyle, progress)

proc checkmarkTextRect(rect: Rect): Rect =
  rect.offsetRect(0.0'f32, -1.0'f32).inset(insets(-1.0'f32))

proc drawPushButtonFace(
    context: DrawContext,
    absoluteFrame: Rect,
    style: ButtonStyle,
    states: set[WidgetState],
) =
  let chrome = chromeContext(style.chrome, crButton, cpFace, style.box.fill, states)
  let
    radius = style.box.cornerRadius
    buttonRoot = context.addRenderRectangle(
      absoluteFrame,
      context.appearance.chromeFill(chrome),
      style.box.borderColor,
      style.box.borderWidth,
      radius,
      style.box.shadows,
      maskContent = true,
      cornerRadii = style.box.cornerRadii,
    )
  context.drawChromeExtras(
    chrome,
    initChromeExtras(
      buttonRoot,
      absoluteFrame,
      cornerRadius = radius,
      cornerRadii = style.box.cornerRadii,
    ),
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
        controlStyle(role, states, id = button.styleId, classes = button.styleClasses)
      )
      let indicatorRect = style.choiceIndicatorRect(button.bounds)
      let
        indicatorFrame = context.renderRectFor(indicatorRect)
        indicatorChrome = chromeContext(
          style.chrome, button.choiceChromeRole(), cpFace, style.indicator.fill, states
        )

      let indicatorRoot = context.addRenderRectangle(
        indicatorFrame,
        context.appearance.chromeFill(indicatorChrome),
        style.indicator.borderColor,
        style.indicator.borderWidth,
        style.indicator.cornerRadius,
        style.indicator.shadows,
        maskContent = true,
      )
      context.drawChromeExtras(
        indicatorChrome,
        initChromeExtras(
          indicatorRoot, indicatorFrame, cornerRadius = style.indicator.cornerRadius
        ),
      )
      if selected:
        if button.buttonType == btCheckBox and button.state == bsOn:
          let
            markRect = indicatorRect.checkmarkTextRect()
            markTextStyle = TextStyle(
              color: style.markColor,
              insets: style.text.insets,
              fontName: style.text.fontName,
              fontSize: style.text.fontSize,
            )
          context.addText(
            markRect, CheckboxCheckmark, markTextStyle, alignment = taCenter
          )
          context.addText(
            markRect.offsetRect(0.45'f32, 0.0'f32),
            CheckboxCheckmark,
            markTextStyle,
            alignment = taCenter,
          )
          context.addText(
            markRect.offsetRect(0.0'f32, -0.35'f32),
            CheckboxCheckmark,
            markTextStyle,
            alignment = taCenter,
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
      context.addText(style.choiceTextRect(button.bounds), button.title, style.text)
    else:
      let states = button.widgetStateSet()
      let style = button.pushButtonStyle(context.appearance, states)
      context.drawPushButtonFace(absoluteFrame, style, states)
      if button.isFocusVisible:
        context.addFocusRing(absoluteFrame, style.box)
      let textRect = style.buttonTextRect(button.bounds)
      if style.textHighlightColor.a > 0.0:
        context.addText(
          textRect.offsetRect(0.0, 1.0),
          button.title,
          TextStyle(
            color: style.textHighlightColor,
            insets: style.text.insets,
            fontName: style.text.fontName,
            fontSize: style.text.fontSize,
          ),
          alignment = taCenter,
        )
      if style.textShadowColor.a > 0.0:
        context.addText(
          textRect.offsetRect(0.0, -0.6'f32),
          button.title,
          TextStyle(
            color: style.textShadowColor,
            insets: style.text.insets,
            fontName: style.text.fontName,
            fontSize: style.text.fontSize,
          ),
          alignment = taCenter,
        )
      context.addText(textRect, button.title, style.text, alignment = taCenter)

protocol DefaultButtonEvents of ResponderEventProtocol:
  method mouseEntered(button: Button, event: MouseEvent): bool =
    discard event
    if button.isEnabled():
      button.animateHoverProgress(1.0'f32)
      return true

  method mouseExited(button: Button, event: MouseEvent): bool =
    discard event
    if button.isEnabled():
      button.animateHoverProgress(0.0'f32)
      return true

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
  discard button.withProtocol(DefaultButtonHover)
  discard button.withProtocol(DefaultButtonDrawing)
  discard button.withProtocol(DefaultButtonEvents)
  discard button.withProtocol(DefaultButtonAction)
  discard button.withProtocol(DefaultButtonKeyCommands)
  discard button.withProtocol(DefaultButtonAccessibility)
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
