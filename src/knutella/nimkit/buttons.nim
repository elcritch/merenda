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

proc initButtonCellFields*(cell: ButtonCell, title: string) =
  initActionCellFields(cell)
  cell.xTitle = title
  cell.xButtonType = btMomentary
  discard cell.withProtocol(DefaultButtonCell)

proc newButtonCell*(title = "Button"): ButtonCell =
  result = ButtonCell()
  initButtonCellFields(result, title)

proc buttonCell*(button: Button): ButtonCell =
  if button.isNil:
    return nil
  let controlCell = button.cell()
  if controlCell of ButtonCell:
    return ButtonCell(controlCell)

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

proc initButtonFields*(button: Button, frame: Rect, title: string) =
  initControlFields(button, frame)
  button.setCell(newButtonCell(title))
  button.setAcceptsFirstResponder(true)
  discard button.withProtocol(DefaultButtonDrawing)
  discard button.withProtocol(DefaultButtonEvents)
  discard button.withProtocol(DefaultButtonAction)

proc newButton*(frame: Rect, title: string): Button =
  result = Button()
  initButtonFields(result, frame, title)

proc newButton*(x, y, width, height: float32, title: string): Button =
  newButton(initRect(x, y, width, height), title)

proc newCheckBox*(frame: Rect, title: string): Button =
  result = newButton(frame, title)
  result.setButtonType(btCheckBox)

proc newCheckBox*(x, y, width, height: float32, title: string): Button =
  newCheckBox(initRect(x, y, width, height), title)

proc newRadioButton*(frame: Rect, title: string): Button =
  result = newButton(frame, title)
  result.setButtonType(btRadio)

proc newRadioButton*(x, y, width, height: float32, title: string): Button =
  newRadioButton(initRect(x, y, width, height), title)

let ButtonProtocol* = ButtonProtocolInternal
