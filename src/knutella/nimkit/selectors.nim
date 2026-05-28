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
  optional:
    method mouseDown(event: MouseEvent)
    method mouseUp(event: MouseEvent)
    method keyDown(event: KeyEvent)

protocol UserInterfaceValidationsInternal:
  required:
    method validateUserInterfaceItem(args: ValidationArgs): bool

protocol ButtonActionProtocolInternal:
  optional:
    method performClick(args: ActionArgs)

proc mouseDownSelector*(): MouseEventSelector =
  mouseDown()

proc mouseUpSelector*(): MouseEventSelector =
  mouseUp()

proc keyDownSelector*(): KeyEventSelector =
  keyDown()

proc performClickSelector*(): ActionSelector =
  performClick()

proc validateUserInterfaceItemSelector*(): ValidationSelector =
  validateUserInterfaceItem()

proc actionSelector*(name: string): ActionSelector =
  selector[ActionArgs, EmptyArgs](name)

let
  ResponderEventProtocol* = ResponderEventProtocolInternal
  UserInterfaceValidations* = UserInterfaceValidationsInternal
  ButtonActionProtocol* = ButtonActionProtocolInternal
