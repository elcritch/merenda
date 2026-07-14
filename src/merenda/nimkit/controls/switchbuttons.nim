import ../accessibility/accessibility
import ../drawing
import ../themes
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ./controls

export controls

type
  SwitchButton* = ref object of Control

  SwitchButtonCell* = ref object of ActionCell

protocol SwitchButtonProtocol {.selectorScope: protocol.}:
  property on -> bool

proc switchButtonCell*(switchButton: SwitchButton): SwitchButtonCell
proc highlighted*(switchButton: SwitchButton): bool

func normalizedSwitchState(state: ButtonState): ButtonState =
  if state == bsOn: bsOn else: bsOff

proc syncSwitchWidgetState(cell: SwitchButtonCell) =
  let view = cell.controlView()
  if not view.isNil and view of SwitchButton:
    SwitchButton(view).setWidgetState(ssSelected, Cell(cell).state() == bsOn)

proc setSwitchCellState(cell: SwitchButtonCell, state: ButtonState) =
  let nextState = state.normalizedSwitchState()
  if Cell(cell).state() != nextState:
    Cell(cell).setState(nextState)
  cell.syncSwitchWidgetState()

proc switchChromeStates(switchButton: SwitchButton): set[WidgetState] =
  result = switchButton.widgetStateSet()
  if switchButton.on:
    result.incl ssSelected
  if switchButton.highlighted:
    result.incl ssHighlighted

proc switchStyleContext(switchButton: SwitchButton): StyleContext =
  controlStyle(
    srSwitch,
    switchButton.switchChromeStates(),
    id = switchButton.styleId,
    classes = switchButton.styleClasses,
  )

proc switchStyle(cell: SwitchButtonCell): SwitchButtonStyle =
  let view = cell.controlView()
  if view of SwitchButton:
    return view.effectiveAppearance().resolveSwitchButtonStyle(
        SwitchButton(view).switchStyleContext()
      )
  initAppearance().resolveSwitchButtonStyle(controlStyle(srSwitch))

proc switchStyle(switchButton: SwitchButton, context: DrawContext): SwitchButtonStyle =
  if not context.isNil:
    return
      context.appearance.resolveSwitchButtonStyle(switchButton.switchStyleContext())
  switchButton.effectiveAppearance().resolveSwitchButtonStyle(
    switchButton.switchStyleContext()
  )

func switchSize(style: SwitchButtonStyle): Size =
  initSize(max(style.minSize.width, 0.0'f32), max(style.minSize.height, 0.0'f32))

protocol DefaultSwitchButtonCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: SwitchButtonCell): IntrinsicSize =
    initIntrinsicSize(cell.switchStyle().switchSize())

  method cellSizeForBounds(cell: SwitchButtonCell, bounds: Rect): Size =
    let size = cell.switchStyle().switchSize()
    initSize(max(bounds.size.width, size.width), size.height)

proc initSwitchButtonCellFields*(cell: SwitchButtonCell) =
  initActionCellFields(cell)
  discard cell.withProtocol(DefaultSwitchButtonCellMeasurement)

proc newSwitchButtonCell*(): SwitchButtonCell =
  result = SwitchButtonCell()
  initSwitchButtonCellFields(result)

proc switchButtonCell*(switchButton: SwitchButton): SwitchButtonCell =
  let controlCell = switchButton.cell()
  if controlCell of SwitchButtonCell:
    return SwitchButtonCell(controlCell)

proc state*(cell: SwitchButtonCell): ButtonState =
  Cell(cell).state()

proc `state=`*(cell: SwitchButtonCell, state: ButtonState) =
  cell.setSwitchCellState(state)

proc state*(switchButton: SwitchButton): ButtonState =
  let cell = switchButton.switchButtonCell()
  if cell.isNil: bsOff else: cell.state

proc `state=`*(switchButton: SwitchButton, state: ButtonState) =
  let cell = switchButton.switchButtonCell()
  if not cell.isNil:
    cell.state = state

proc `on=`*(switchButton: SwitchButton, on: bool) =
  switchButton.setOn(on)

proc highlighted*(switchButton: SwitchButton): bool =
  let cell = switchButton.switchButtonCell()
  (not cell.isNil) and cell.isHighlighted()

proc `highlighted=`*(switchButton: SwitchButton, highlighted: bool) =
  let cell = switchButton.switchButtonCell()
  if not cell.isNil:
    cell.setHighlighted(highlighted)

protocol DefaultSwitchButtonControl of SwitchButtonProtocol:
  method on(switchButton: SwitchButton): bool =
    switchButton.state == bsOn

  method setOn(switchButton: SwitchButton, on: bool) =
    switchButton.state = (if on: bsOn else: bsOff)

proc switchTrackRect(switchButton: SwitchButton, style: SwitchButtonStyle): Rect =
  let
    bounds = switchButton.bounds()
    size = style.switchSize()
    width = min(bounds.size.width, size.width)
    height = min(bounds.size.height, size.height)
  rect(
    bounds.origin.x + (bounds.size.width - width) * 0.5'f32,
    bounds.origin.y + (bounds.size.height - height) * 0.5'f32,
    width,
    height,
  )

proc switchKnobRect(
    switchButton: SwitchButton, track: Rect, style: SwitchButtonStyle
): Rect =
  let
    knobInset = max(style.knobInset, 0.0'f32)
    knobSize = max(track.size.height - knobInset * style.knobSizeFactor, 0.0'f32)
    x =
      if switchButton.on:
        track.maxX - knobInset - knobSize
      else:
        track.origin.x + knobInset
  rect(x, track.origin.y + (track.size.height - knobSize) * 0.5'f32, knobSize, knobSize)

proc drawSwitchTrack(
    switchButton: SwitchButton,
    context: DrawContext,
    rect: Rect,
    style: SwitchButtonStyle,
    states: set[WidgetState],
) =
  if rect.isEmpty:
    return
  let
    selected = switchButton.on
    frame = context.renderRectFor(rect)
    radius = rect.size.height * 0.5'f32
    chrome = chromeContext(
      style.chrome,
      crSliderTrack,
      if selected: cpHighlight else: cpFace,
      style.track.fill,
      states,
    )
    trackRoot = context.addRenderRectangle(
      frame,
      context.appearance.chromeFill(chrome),
      style.track.borderColor,
      style.track.borderWidth,
      radius,
      style.track.shadows,
      lightMaskContent = true,
    )
  context.drawChromeExtras(
    chrome, initChromeExtras(trackRoot, frame, cornerRadius = radius)
  )

proc drawSwitchKnob(
    switchButton: SwitchButton,
    context: DrawContext,
    rect: Rect,
    style: SwitchButtonStyle,
    states: set[WidgetState],
) =
  if rect.isEmpty:
    return
  let
    frame = context.renderRectFor(rect)
    radius = rect.size.width * 0.5'f32
    chrome = chromeContext(style.chrome, crSliderKnob, cpFace, style.knob.fill, states)
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

proc switchButtonPerformClick(
    switchButton: SwitchButton, args: ActionArgs, showActivationFeedback = false
) =
  if not switchButton.isEnabled() or args.sender.isNil:
    return
  if showActivationFeedback:
    switchButton.pulseActivationFeedback()
  switchButton.on = not switchButton.on
  discard switchButton.sendAction()

protocol DefaultSwitchButtonDrawing of ViewDrawingProtocol:
  method draw(switchButton: SwitchButton, context: DrawContext) =
    let
      states = switchButton.switchChromeStates()
      style = switchButton.switchStyle(context)
      track = switchButton.switchTrackRect(style)
    switchButton.drawSwitchTrack(context, track, style, states)
    switchButton.drawSwitchKnob(
      context, switchButton.switchKnobRect(track, style), style, states
    )
    if switchButton.isFocusVisible:
      context.addFocusRing(context.renderRectFor(track), style.track)

protocol DefaultSwitchButtonEvents of ResponderEventProtocol:
  method mouseDown(switchButton: SwitchButton, event: MouseEvent): bool =
    if switchButton.isEnabled() and event.button == mbPrimary:
      switchButton.cancelActivationFeedback()
      switchButton.highlighted = true
      return true

  method mouseDragged(switchButton: SwitchButton, event: MouseEvent): bool =
    if switchButton.isEnabled() and event.button == mbPrimary:
      switchButton.highlighted = switchButton.pointInside(event.location)
      return true

  method mouseUp(switchButton: SwitchButton, event: MouseEvent): bool =
    if switchButton.isEnabled() and event.button == mbPrimary:
      let clicked = switchButton.pointInside(event.location)
      switchButton.highlighted = false
      if clicked:
        switchButton.switchButtonPerformClick(ActionArgs(sender: switchButton))
      return true

protocol DefaultSwitchButtonAction of ButtonActionProtocol:
  method performClick(switchButton: SwitchButton, args: ActionArgs) =
    switchButton.switchButtonPerformClick(args, showActivationFeedback = true)

protocol DefaultSwitchButtonKeyCommands of KeyViewCommandProtocol:
  method insertNewline(switchButton: SwitchButton, args: ActionArgs) =
    switchButton.switchButtonPerformClick(args, showActivationFeedback = true)

protocol DefaultSwitchButtonAccessibility of AccessibilityProtocol:
  method accessibilityRole(switchButton: SwitchButton): AccessibilityRole =
    arCheckBox

  method accessibilityLabel(switchButton: SwitchButton): string =
    if switchButton.xAccessibilityLabel.len > 0:
      switchButton.xAccessibilityLabel
    else:
      "switch"

  method accessibilityValue(switchButton: SwitchButton): string =
    if switchButton.on: "on" else: "off"

  method accessibilityTraits(switchButton: SwitchButton): AccessibilityTraits =
    result = switchButton.xAccessibilityTraits + {atButton}
    if not switchButton.isEnabled():
      result.incl atDisabled
    if switchButton.focused():
      result.incl atFocused
    if switchButton.on:
      result.incl atSelected

  method isAccessibilityElement(switchButton: SwitchButton): bool =
    true

  method accessibilityActionNames(switchButton: SwitchButton): seq[string] =
    @[AccessibilityActionPress]

  method accessibilityPerformAction(switchButton: SwitchButton, action: string): bool =
    if action != AccessibilityActionPress or not switchButton.isEnabled():
      return false
    switchButton.switchButtonPerformClick(ActionArgs(sender: switchButton))
    true

proc initSwitchButtonFields*(
    switchButton: SwitchButton, on = false, frame: Rect = AutoRect
) =
  initControlFields(switchButton, frame, newSwitchButtonCell())
  switchButton.state = (if on: bsOn else: bsOff)
  switchButton.setAcceptsFirstResponder(true)
  switchButton.setHuggingPriority(LayoutPriorityHigh, laHorizontal)
  switchButton.setCompressionPriority(LayoutPriorityRequired, laHorizontal)
  discard switchButton.withProtocol(DefaultSwitchButtonDrawing)
  discard switchButton.withProtocol(DefaultSwitchButtonEvents)
  discard switchButton.withProtocol(DefaultSwitchButtonAction)
  discard switchButton.withProtocol(DefaultSwitchButtonKeyCommands)
  discard switchButton.withProtocol(DefaultSwitchButtonAccessibility)
  discard switchButton.withProtocol(DefaultSwitchButtonControl)
  switchButton.applyInitialFrame(frame)

proc newSwitchButton*(on = false, frame: Rect = AutoRect): SwitchButton =
  result = SwitchButton()
  initSwitchButtonFields(result, on, frame)
