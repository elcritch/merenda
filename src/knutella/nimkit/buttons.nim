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

protocol ButtonProtocolInternal:
  required:
    method title(): string
    method setTitle(title: string)
    method isHighlighted(): bool
    method setHighlighted(highlighted: bool)
    method state(): ButtonState
    method setState(state: ButtonState)
    method buttonType(): ButtonType
    method setButtonType(buttonType: ButtonType)
    method allowsMixedState(): bool
    method setAllowsMixedState(value: bool)

proc nextButtonState(button: Button): ButtonState =
  case button.xState
  of bsOff:
    bsOn
  of bsOn:
    if button.xAllowsMixedState: bsMixed else: bsOff
  of bsMixed:
    bsOff

method buttonMouseDown(button: Button, event: MouseEvent): EmptyArgs {.selector.} =
  if button.isEnabled and event.button == mbPrimary:
    button.xHighlighted = true
    button.setNeedsDisplay(true)

method buttonMouseUp(button: Button, event: MouseEvent): EmptyArgs {.selector.} =
  if button.isEnabled and event.button == mbPrimary:
    button.xHighlighted = false
    button.setNeedsDisplay(true)
    discard button.send(performClickSelector(), ActionArgs(sender: button))

method buttonPerformClick(button: Button, args: ActionArgs): EmptyArgs {.selector.} =
  if not button.isEnabled or args.sender.isNil:
    return
  case button.xButtonType
  of btMomentary:
    discard
  of btToggle:
    button.xState = button.nextButtonState()
  button.setNeedsDisplay(true)
  discard button.sendAction()

method buttonKeyDown(button: Button, event: KeyEvent): EmptyArgs {.selector.} =
  if button.isEnabled and event.text == " ":
    discard button.send(performClickSelector(), ActionArgs(sender: button))

method buttonTitle(button: Button): string {.selector.} =
  button.xTitle

method buttonSetTitle(button: Button, title: string): EmptyArgs {.selector.} =
  if button.xTitle == title:
    return
  button.xTitle = title
  button.setNeedsDisplay(true)

method buttonIsHighlighted(button: Button): bool {.selector.} =
  button.xHighlighted

method buttonSetHighlighted(button: Button, highlighted: bool): EmptyArgs {.selector.} =
  if button.xHighlighted == highlighted:
    return
  button.xHighlighted = highlighted
  button.setNeedsDisplay(true)

method buttonState(button: Button): ButtonState {.selector.} =
  button.xState

method buttonSetState(button: Button, state: ButtonState): EmptyArgs {.selector.} =
  if button.xState == state:
    return
  button.xState = state
  button.setNeedsDisplay(true)

method buttonButtonType(button: Button): ButtonType {.selector.} =
  button.xButtonType

method buttonSetButtonType(
    button: Button, buttonType: ButtonType
): EmptyArgs {.selector.} =
  if button.xButtonType == buttonType:
    return
  button.xButtonType = buttonType
  button.setNeedsDisplay(true)

method buttonAllowsMixedState(button: Button): bool {.selector.} =
  button.xAllowsMixedState

method buttonSetAllowsMixedState(button: Button, value: bool): EmptyArgs {.selector.} =
  button.xAllowsMixedState = value
  if not value and button.state == bsMixed:
    button.setState(bsOff)

proc installButtonMethods(button: Button) =
  discard button.replaceMethod(mouseDownSelector(), buttonMouseDown)
  discard button.replaceMethod(mouseUpSelector(), buttonMouseUp)
  discard button.replaceMethod(keyDownSelector(), buttonKeyDown)
  discard button.replaceMethod(performClickSelector(), buttonPerformClick)
  discard button.replaceMethod(title, buttonTitle)
  discard button.replaceMethod(setTitle, buttonSetTitle)
  discard button.replaceMethod(isHighlighted, buttonIsHighlighted)
  discard button.replaceMethod(setHighlighted, buttonSetHighlighted)
  discard button.replaceMethod(state, buttonState)
  discard button.replaceMethod(setState, buttonSetState)
  discard button.replaceMethod(buttonType, buttonButtonType)
  discard button.replaceMethod(setButtonType, buttonSetButtonType)
  discard button.replaceMethod(allowsMixedState, buttonAllowsMixedState)
  discard button.replaceMethod(setAllowsMixedState, buttonSetAllowsMixedState)

proc initButtonFields*(button: Button, frame: Rect, title: string) =
  initControlFields(button, frame)
  button.xTitle = title
  button.xButtonType = btMomentary
  button.setAcceptsFirstResponder(true)
  button.installButtonMethods()

proc newButton*(frame: Rect, title: string): Button =
  result = Button()
  initButtonFields(result, frame, title)

proc newButton*(x, y, width, height: float32, title: string): Button =
  newButton(initRect(x, y, width, height), title)

proc title*(button: Button): string =
  button.send(title, ())

proc setTitle*(button: Button, title: string) =
  discard button.send(setTitle, title)

proc isHighlighted*(button: Button): bool =
  button.send(isHighlighted, ())

proc setHighlighted*(button: Button, highlighted: bool) =
  discard button.send(setHighlighted, highlighted)

proc state*(button: Button): ButtonState =
  button.send(state, ())

proc setState*(button: Button, state: ButtonState) =
  discard button.send(setState, state)

proc buttonType*(button: Button): ButtonType =
  button.send(buttonType, ())

proc setButtonType*(button: Button, buttonType: ButtonType) =
  discard button.send(setButtonType, buttonType)

proc allowsMixedState*(button: Button): bool =
  button.send(allowsMixedState, ())

proc setAllowsMixedState*(button: Button, value: bool) =
  discard button.send(setAllowsMixedState, value)

let ButtonProtocol* = ButtonProtocolInternal
