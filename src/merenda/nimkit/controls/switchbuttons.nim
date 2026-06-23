import ../accessibility/accessibility
import ../drawing/drawing
import ../themes
import ../foundation/events
import ../foundation/selectors
import ../foundation/types
import ./controls

export controls

type
  SwitchButton* = ref object of Control

  SwitchButtonCell* = ref object of ActionCell

const
  SwitchButtonWidth = 40'f32
  SwitchButtonHeight = 24'f32
  SwitchKnobInset = 1.7'f32
  SwitchKnobSize = SwitchButtonHeight - SwitchKnobInset * 2.0'f32

protocol SwitchButtonProtocol {.selectorScope: protocol.}:
  property on -> bool

func normalizedSwitchState(state: ButtonState): ButtonState =
  if state == bsOn: bsOn else: bsOff

proc syncSwitchWidgetState(cell: SwitchButtonCell) =
  if cell.isNil:
    return
  let view = cell.controlView()
  if not view.isNil and view of SwitchButton:
    SwitchButton(view).setWidgetState(ssSelected, Cell(cell).state() == bsOn)

proc setSwitchCellState(cell: SwitchButtonCell, state: ButtonState) =
  if cell.isNil:
    return
  let nextState = state.normalizedSwitchState()
  if Cell(cell).state() != nextState:
    Cell(cell).setState(nextState)
  cell.syncSwitchWidgetState()

protocol DefaultSwitchButtonCellMeasurement of CellMeasurementProtocol:
  method cellSize(cell: SwitchButtonCell): IntrinsicSize =
    initIntrinsicSize(SwitchButtonWidth, SwitchButtonHeight)

  method cellSizeForBounds(cell: SwitchButtonCell, bounds: Rect): Size =
    initSize(max(bounds.size.width, SwitchButtonWidth), SwitchButtonHeight)

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
  if cell.isNil:
    return bsOff
  Cell(cell).state()

proc `state=`*(cell: SwitchButtonCell, state: ButtonState) =
  cell.setSwitchCellState(state)

proc state*(switchButton: SwitchButton): ButtonState =
  if switchButton.isNil:
    return bsOff
  let cell = switchButton.switchButtonCell()
  if cell.isNil: bsOff else: cell.state

proc `state=`*(switchButton: SwitchButton, state: ButtonState) =
  let cell = switchButton.switchButtonCell()
  if not cell.isNil:
    cell.state = state

proc `on=`*(switchButton: SwitchButton, on: bool) =
  switchButton.setOn(on)

proc highlighted*(switchButton: SwitchButton): bool =
  if switchButton.isNil:
    return false
  let cell = switchButton.switchButtonCell()
  (not cell.isNil) and cell.isHighlighted()

proc `highlighted=`*(switchButton: SwitchButton, highlighted: bool) =
  if not switchButton.isNil:
    let cell = switchButton.switchButtonCell()
    if not cell.isNil:
      cell.setHighlighted(highlighted)

protocol DefaultSwitchButtonControl of SwitchButtonProtocol:
  method on(switchButton: SwitchButton): bool =
    switchButton.state == bsOn

  method setOn(switchButton: SwitchButton, on: bool) =
    switchButton.state = (if on: bsOn else: bsOff)

proc switchFocusBox(): ControlBoxStyle =
  ControlBoxStyle(
    focusRingWidth: 3.0'f32,
    focusRingInset: -3.0'f32,
    focusRingColor: initColor(0.28, 0.62, 1.0, 0.80),
    cornerRadius: SwitchButtonHeight * 0.5'f32,
  )

func switchTrackBaseFill(on, enabled: bool): Fill =
  let alpha = if enabled: 1.0'f32 else: 0.42'f32
  if on:
    fill(initColor(0.08, 0.54, 0.96, alpha))
  else:
    fill(initColor(0.72, 0.78, 0.84, alpha))

func switchKnobBaseFill(highlighted, enabled: bool): Fill =
  if highlighted and enabled:
    fill(initColor(0.91, 0.97, 1.0, 1.0))
  else:
    fill(initColor(0.96, 0.97, 0.99, if enabled: 1.0'f32 else: 0.68'f32))

proc switchChromeStates(switchButton: SwitchButton): set[WidgetState] =
  result = switchButton.widgetStateSet()
  if switchButton.on:
    result.incl ssSelected
  if switchButton.highlighted:
    result.incl ssHighlighted

proc switchTrackRect(switchButton: SwitchButton): Rect =
  let
    bounds = switchButton.bounds()
    width = min(bounds.size.width, SwitchButtonWidth)
    height = min(bounds.size.height, SwitchButtonHeight)
  initRect(
    bounds.origin.x + (bounds.size.width - width) * 0.5'f32,
    bounds.origin.y + (bounds.size.height - height) * 0.5'f32,
    width,
    height,
  )

proc switchKnobRect(switchButton: SwitchButton, track: Rect): Rect =
  let x =
    if switchButton.on:
      track.maxX - SwitchKnobInset - SwitchKnobSize
    else:
      track.origin.x + SwitchKnobInset
  initRect(
    x,
    track.origin.y + (track.size.height - SwitchKnobSize) * 0.5'f32,
    SwitchKnobSize,
    SwitchKnobSize,
  )

proc drawSwitchTrack(switchButton: SwitchButton, context: DrawContext, rect: Rect) =
  if rect.isEmpty:
    return
  let
    enabled = switchButton.isEnabled()
    selected = switchButton.on
    frame = context.renderRectFor(rect)
    radius = rect.size.height * 0.5'f32
    chrome = chromeContext(
      AquaChromeName,
      crSliderTrack,
      if selected: cpHighlight else: cpFace,
      switchTrackBaseFill(selected, enabled),
      switchButton.switchChromeStates(),
    )
    borderColor =
      if selected:
        initColor(0.02, 0.24, 0.62, if enabled: 0.70'f32 else: 0.32'f32)
      else:
        initColor(0.38, 0.45, 0.53, if enabled: 0.70'f32 else: 0.32'f32)
    trackRoot = context.addRenderRectangle(
      frame,
      context.appearance.chromeFill(chrome),
      borderColor,
      1.0'f32,
      radius,
      @[
        insetShadow(
          initColor(0.0, 0.0, 0.0, if enabled: 0.14'f32 else: 0.05'f32),
          y = 1.0,
          blur = 2.0,
        )
      ],
      maskContent = true,
    )
  context.drawChromeExtras(
    chrome, initChromeExtras(trackRoot, frame, cornerRadius = radius)
  )

proc drawSwitchKnob(switchButton: SwitchButton, context: DrawContext, rect: Rect) =
  if rect.isEmpty:
    return
  let
    enabled = switchButton.isEnabled()
    highlighted = switchButton.highlighted
    frame = context.renderRectFor(rect)
    radius = rect.size.width * 0.5'f32
    chrome = chromeContext(
      AquaChromeName,
      crSliderKnob,
      cpFace,
      switchKnobBaseFill(highlighted, enabled),
      switchButton.switchChromeStates(),
    )
    knobRoot = context.addRenderRectangle(
      frame,
      context.appearance.chromeFill(chrome),
      initColor(0.32, 0.36, 0.44, if enabled: 0.78'f32 else: 0.34'f32),
      1.0'f32,
      radius,
      @[
        dropShadow(
          initColor(0.0, 0.0, 0.0, if enabled: 0.22'f32 else: 0.08'f32),
          y = 1.0,
          blur = 3.0,
        ),
        insetShadow(
          initColor(1.0, 1.0, 1.0, if enabled: 0.82'f32 else: 0.26'f32),
          y = 1.0,
          blur = 2.0,
        ),
      ],
      maskContent = true,
    )
  context.drawChromeExtras(
    chrome, initChromeExtras(knobRoot, frame, cornerRadius = radius)
  )

proc switchButtonPerformClick(switchButton: SwitchButton, args: ActionArgs) =
  if switchButton.isNil or not switchButton.isEnabled() or args.sender.isNil:
    return
  switchButton.on = not switchButton.on
  discard switchButton.sendAction()

protocol DefaultSwitchButtonDrawing of ViewDrawingProtocol:
  method draw(switchButton: SwitchButton, context: DrawContext) =
    let track = switchButton.switchTrackRect()
    switchButton.drawSwitchTrack(context, track)
    switchButton.drawSwitchKnob(context, switchButton.switchKnobRect(track))
    if switchButton.isFocusVisible:
      context.addFocusRing(context.renderRectFor(track), switchFocusBox())

protocol DefaultSwitchButtonEvents of ResponderEventProtocol:
  method mouseDown(switchButton: SwitchButton, event: MouseEvent): bool =
    if switchButton.isEnabled() and event.button == mbPrimary:
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
    switchButton.switchButtonPerformClick(args)

protocol DefaultSwitchButtonKeyCommands of KeyViewCommandProtocol:
  method insertNewline(switchButton: SwitchButton, args: ActionArgs) =
    switchButton.switchButtonPerformClick(args)

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
