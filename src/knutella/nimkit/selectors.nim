import sigils/selectors

import ./types

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
  method keyDown*(event: KeyEvent) {.optional.}

protocol UserInterfaceValidationsInternal:
  method validateUserInterfaceItem*(args: ValidationArgs): bool

protocol ButtonActionProtocolInternal:
  method performClick*(args: ActionArgs) {.optional.}

proc actionSelector*(name: string): ActionSelector =
  selector[ActionArgs, EmptyArgs](name)

let
  ResponderEventProtocol* = ResponderEventProtocolInternal
  UserInterfaceValidations* = UserInterfaceValidationsInternal
  ButtonActionProtocol* = ButtonActionProtocolInternal
