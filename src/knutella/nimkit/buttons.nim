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

proc buttonPerformClick(button: Button, args: ActionArgs) =
  if not button.isEnabled or args.sender.isNil:
    return
  case button.xButtonType
  of btMomentary:
    discard
  of btToggle:
    button.xState = button.nextButtonState()
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
    button.setNeedsDisplay(true)

  method allowsMixedState(button: Button): bool =
    button.xAllowsMixedState

  method setAllowsMixedState(button: Button, value: bool) =
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

let ButtonProtocol* = ButtonProtocolInternal
