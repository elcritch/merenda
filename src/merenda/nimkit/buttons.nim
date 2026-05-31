import ./controls
import ./selectors
import ./theme
import ./types

export controls

type
  Button* = ref object of Control

  ButtonCell* = ref object of ActionCell
    xTitle: string
    xButtonType: ButtonType

const CheckboxCheckmark = "✓"

proc updateButtonLayoutPriorities(cell: ButtonCell) =
  let view = cell.controlView()
  if view of Button:
    let button = Button(view)
    if cell.xButtonType in {btCheckBox, btRadio}:
      button.setHuggingPriority(LayoutPriorityDefaultHigh, laHorizontal)
    else:
      button.setHuggingPriority(LayoutPriorityDefaultLow, laHorizontal)

proc buttonStyleContext(cell: ButtonCell, role: StyleRole): StyleContext =
  let view = cell.controlView()
  if view of Button:
    let button = Button(view)
    return initControlStyleContext(
      role,
      enabled = button.isEnabled,
      highlighted = cell.isHighlighted,
      hovered = button.isHovered,
      active = button.isActive,
      focused = button.isFocused,
      focusVisible = button.isFocusVisible,
      selected = Cell(cell).state() in {bsOn, bsMixed},
      id = button.styleId,
      classes = button.styleClasses,
    )
  initControlStyleContext(
    role,
    enabled = cell.isEnabled,
    highlighted = cell.isHighlighted,
    selected = cell.state in {bsOn, bsMixed},
  )

protocol ButtonProtocolInternal:
  property title -> string
  property state -> ButtonState
  property buttonType -> ButtonType
  property allowsMixedState -> bool

  method isHighlighted*(): bool
  method setHighlighted*(highlighted: bool)

protocol DefaultButtonCell of ButtonProtocolInternal:
  method title(cell: ButtonCell): string =
    cell.xTitle

  method setTitle(cell: ButtonCell, title: string) =
    if cell.xTitle == title:
      return
    cell.xTitle = title
    cell.updateControlView()

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
    cell.updateControlView()

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
      textSize = textNaturalSize(cell.title())
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
  if button.isNil:
    return nil
  let controlCell = button.cell()
  if controlCell of ButtonCell:
    return ButtonCell(controlCell)

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

protocol DefaultButtonDrawing of ViewDrawingProtocol:
  method draw(button: Button, context: DrawContext) =
    let absoluteFrame = button.rectToWindow(button.bounds)
    if button.buttonType in {btCheckBox, btRadio}:
      let
        role = button.choiceRole()
        selected = button.state in {bsOn, bsMixed}
        style = context.appearance.resolveChoiceButtonStyle(
          initControlStyleContext(
            role,
            enabled = button.isEnabled,
            highlighted = button.isHighlighted,
            hovered = button.isHovered,
            active = button.isActive,
            focused = button.isFocused,
            focusVisible = button.isFocusVisible,
            selected = selected,
            id = button.styleId,
            classes = button.styleClasses,
          )
        )
        indicatorRect = style.choiceIndicatorRect(button.bounds)

      discard context.addWindowRectangle(
        button.rectToWindow(indicatorRect),
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
          discard context.addWindowRectangle(
            button.rectToWindow(markRect),
            style.markColor,
            style.markColor,
            0.0'f32,
            if button.buttonType == btRadio:
              markRect.size.width / 2.0'f32
            else:
              1.0'f32,
          )
      if button.isFocusVisible:
        context.addFocusRing(button.rectToWindow(indicatorRect), style.indicator)
      context.addText(
        style.choiceTextRect(button.bounds), button.title, style.text.color
      )
    else:
      let style = context.appearance.resolveButtonStyle(
        initControlStyleContext(
          srButton,
          enabled = button.isEnabled,
          highlighted = button.isHighlighted,
          hovered = button.isHovered,
          active = button.isActive,
          focused = button.isFocused,
          focusVisible = button.isFocusVisible,
          id = button.styleId,
          classes = button.styleClasses,
        )
      )
      discard context.addWindowRectangle(
        absoluteFrame, style.box.fill, style.box.borderColor, style.box.borderWidth,
        style.box.cornerRadius, style.box.shadows,
      )
      if button.isFocusVisible:
        context.addFocusRing(absoluteFrame, style.box)
      context.addText(
        style.buttonTextRect(button.bounds),
        button.title,
        style.text.color,
        alignment = taCenter,
      )

protocol DefaultButtonEvents of ResponderEventProtocol:
  method mouseDown(button: Button, event: MouseEvent) =
    if button.isEnabled and event.button == mbPrimary:
      button.setHighlighted(true)

  method mouseDragged(button: Button, event: MouseEvent) =
    if button.isEnabled and event.button == mbPrimary:
      button.setHighlighted(button.pointInside(event.location))

  method mouseUp(button: Button, event: MouseEvent) =
    if button.isEnabled and event.button == mbPrimary:
      let clicked = button.pointInside(event.location)
      button.setHighlighted(false)
      if clicked:
        button.buttonPerformClick(ActionArgs(sender: button))

protocol DefaultButtonAction of ButtonActionProtocol:
  method performClick(button: Button, args: ActionArgs) =
    button.buttonPerformClick(args)

proc initButtonFields*(button: Button, title = "Button", frame: Rect = AutoRect) =
  initControlFields(button, frame)
  button.setCell(newButtonCell(title))
  button.buttonCell().updateButtonLayoutPriorities()
  button.setAcceptsFirstResponder(true)
  discard button.withProtocol(DefaultButtonDrawing)
  discard button.withProtocol(DefaultButtonEvents)
  discard button.withProtocol(DefaultButtonAction)
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

let ButtonProtocol* = ButtonProtocolInternal
