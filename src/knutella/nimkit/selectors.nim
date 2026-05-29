import sigils/selectors

import ./drawing
import ./types

export drawing
export selectors

type
  EmptyArgs* = tuple[]

  MouseEventArgs* = object
    event*: MouseEvent

  KeyEventArgs* = object
    event*: KeyEvent

  ActionArgs* = object
    sender*: DynamicAgent

  CommandArgs* = object
    sender*: DynamicAgent

  ValidationArgs* = object
    item*: DynamicAgent

  MouseEventSelector* = Selector[MouseEvent, EmptyArgs]
  KeyEventSelector* = Selector[KeyEvent, EmptyArgs]
  ActionSelector* = Selector[ActionArgs, EmptyArgs]
  CommandSelector* = ActionSelector
  ValidationSelector* = Selector[ValidationArgs, bool]

  TryToPerformArgs* = object
    selector*: CommandSelector
    sender*: DynamicAgent

protocol ResponderEventProtocolInternal:
  method mouseDown*(event: MouseEvent) {.optional.}
  method mouseUp*(event: MouseEvent) {.optional.}
  method mouseEntered*(event: MouseEvent) {.optional.}
  method mouseExited*(event: MouseEvent) {.optional.}
  method mouseMoved*(event: MouseEvent) {.optional.}
  method mouseDragged*(event: MouseEvent) {.optional.}
  method keyDown*(event: KeyEvent) {.optional.}

protocol UserInterfaceValidationsInternal:
  method validateUserInterfaceItem*(args: ValidationArgs): bool

protocol ButtonActionProtocolInternal:
  method performClick*(args: ActionArgs) {.optional.}

protocol ViewDrawingProtocolInternal:
  method draw*(context: DrawContext) {.optional.}

protocol ViewLayoutProtocolInternal:
  method layoutSubviews*() {.optional.}
  method layout*() {.optional.}

proc actionSelector*(name: string): ActionSelector =
  selector[ActionArgs, EmptyArgs](name)

let
  ResponderEventProtocol* = ResponderEventProtocolInternal
  UserInterfaceValidations* = UserInterfaceValidationsInternal
  ButtonActionProtocol* = ButtonActionProtocolInternal
  ViewDrawingProtocol* = ViewDrawingProtocolInternal
  ViewLayoutProtocol* = ViewLayoutProtocolInternal
