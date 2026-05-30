import ./controls
import ./selectors
import ./types

export controls

type Button* = ref object of Control
  xTitle: string
  xHighlighted: bool
  xState: ButtonState
  xButtonType: ButtonType
  xAllowsMixedState: bool

proc nextButtonState(button: Button): ButtonState =
  case button.xState
  of bsOff:
    bsOn
  of bsOn:
    if button.xAllowsMixedState: bsMixed else: bsOff
  of bsMixed:
    bsOff

proc clearRadioSiblings(button: Button) =
  let parent = button.superview
  if parent.isNil:
    return
  for sibling in parent.subviews:
    if sibling != button and sibling of Button:
      let siblingButton = Button(sibling)
      if siblingButton.xButtonType == btRadio and siblingButton.xState != bsOff:
        siblingButton.xState = bsOff
        siblingButton.setNeedsDisplay(true)

proc buttonPerformClick(button: Button, args: ActionArgs) =
  if not button.isEnabled or args.sender.isNil:
    return
  case button.xButtonType
  of btMomentary:
    discard
  of btToggle, btCheckBox:
    button.xState = button.nextButtonState()
  of btRadio:
    button.xState = bsOn
    button.clearRadioSiblings()
  button.setNeedsDisplay(true)
  discard button.sendAction()

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

protocol ButtonProtocolInternal from Button:
  property title -> string
  property state -> ButtonState
  property buttonType -> ButtonType
  property allowsMixedState -> bool

  method title(button: Button): string =
    button.xTitle

  method setTitle(button: Button, title: string) =
    if button.xTitle == title:
      return
    button.xTitle = title
    button.setNeedsDisplay(true)

  method state(button: Button): ButtonState =
    button.xState

  method setState(button: Button, state: ButtonState) =
    if button.xState == state:
      return
    button.xState = state
    button.setNeedsDisplay(true)

  method buttonType(button: Button): ButtonType =
    button.xButtonType

  method setButtonType(button: Button, buttonType: ButtonType) =
    if button.xButtonType == buttonType:
      return
    button.xButtonType = buttonType
    if buttonType == btRadio:
      button.xAllowsMixedState = false
      if button.xState == bsMixed:
        button.xState = bsOff
    button.setNeedsDisplay(true)

  method allowsMixedState(button: Button): bool =
    button.xAllowsMixedState

  method setAllowsMixedState(button: Button, value: bool) =
    if value and button.xButtonType == btRadio:
      return
    button.xAllowsMixedState = value
    if not value and button.state == bsMixed:
      button.setState(bsOff)

  method isHighlighted*(button: Button): bool =
    button.xHighlighted

  method setHighlighted*(button: Button, highlighted: bool) =
    if button.xHighlighted == highlighted:
      return
    button.xHighlighted = highlighted
    button.setNeedsDisplay(true)

proc initButtonFields*(button: Button, frame: Rect, title: string) =
  initControlFields(button, frame)
  button.xTitle = title
  button.xButtonType = btMomentary
  button.setAcceptsFirstResponder(true)
  discard button.withProtocol(DefaultButtonEvents)
  discard button.withProtocol(DefaultButtonAction)
  discard button.withProto()

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
