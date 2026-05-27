import sigils/reactive
import sigils/selectors

import ./controls
import ./selectors
import ./types

export controls

type Button* = ref object of Control
  xTitle: Sigil[string]
  xHighlighted: Sigil[bool]
  xState: Sigil[ButtonState]
  xButtonType: Sigil[ButtonType]
  xAllowsMixedState: Sigil[bool]

proc nextButtonState(button: Button): ButtonState =
  case button.xState{}
  of bsOff:
    bsOn
  of bsOn:
    if button.xAllowsMixedState{}: bsMixed else: bsOff
  of bsMixed:
    bsOff

proc buttonMouseDown(button: Button, args: MouseEventArgs): EmptyArgs =
  if button.isEnabled and args.event.button == mbPrimary:
    button.xHighlighted <- true
    button.setNeedsDisplay(true)

proc buttonMouseUp(button: Button, args: MouseEventArgs): EmptyArgs =
  if button.isEnabled and args.event.button == mbPrimary:
    button.xHighlighted <- false
    button.setNeedsDisplay(true)
    discard button.send(performClickSelector(), ActionArgs(sender: button))

proc buttonPerformClick(button: Button, args: ActionArgs): EmptyArgs =
  if not button.isEnabled or args.sender.isNil:
    return
  case button.xButtonType{}
  of btMomentary:
    discard
  of btToggle:
    button.xState <- button.nextButtonState()
  button.setNeedsDisplay(true)
  discard button.sendAction()

proc buttonKeyDown(button: Button, args: KeyEventArgs): EmptyArgs =
  if button.isEnabled and args.event.text == " ":
    discard button.send(performClickSelector(), ActionArgs(sender: button))

proc initButtonFields*(button: Button, frame: Rect, title: string) =
  initControlFields(button, frame)
  button.xTitle = newSigil(title)
  button.xHighlighted = newSigil(false)
  button.xState = newSigil(bsOff)
  button.xButtonType = newSigil(btMomentary)
  button.xAllowsMixedState = newSigil(false)
  button.setAcceptsFirstResponder(true)
  discard button.addMethod(mouseDownSelector(), toDynamicMethod(buttonMouseDown))
  discard button.addMethod(mouseUpSelector(), toDynamicMethod(buttonMouseUp))
  discard button.addMethod(keyDownSelector(), toDynamicMethod(buttonKeyDown))
  discard button.addMethod(performClickSelector(), toDynamicMethod(buttonPerformClick))

proc newButton*(frame: Rect, title: string): Button =
  result = Button()
  initButtonFields(result, frame, title)

proc newButton*(x, y, width, height: float32, title: string): Button =
  newButton(initRect(x, y, width, height), title)

proc title*(button: Button): string =
  button.xTitle{}

proc setTitle*(button: Button, title: string) =
  if button.title == title:
    return
  button.xTitle <- title
  button.setNeedsDisplay(true)

proc isHighlighted*(button: Button): bool =
  button.xHighlighted{}

proc setHighlighted*(button: Button, highlighted: bool) =
  if button.isHighlighted == highlighted:
    return
  button.xHighlighted <- highlighted
  button.setNeedsDisplay(true)

proc state*(button: Button): ButtonState =
  button.xState{}

proc setState*(button: Button, state: ButtonState) =
  if button.state == state:
    return
  button.xState <- state
  button.setNeedsDisplay(true)

proc buttonType*(button: Button): ButtonType =
  button.xButtonType{}

proc setButtonType*(button: Button, buttonType: ButtonType) =
  if button.buttonType == buttonType:
    return
  button.xButtonType <- buttonType
  button.setNeedsDisplay(true)

proc allowsMixedState*(button: Button): bool =
  button.xAllowsMixedState{}

proc setAllowsMixedState*(button: Button, value: bool) =
  button.xAllowsMixedState <- value
  if not value and button.state == bsMixed:
    button.setState(bsOff)
