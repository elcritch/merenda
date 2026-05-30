import ./controls
import ./selectors
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
  if button.sendAction() and button.buttonType == btRadio:
    button.clearRadioSiblings()

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
