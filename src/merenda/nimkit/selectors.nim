import sigils/selectors

import ./drawing
import ./types

export drawing
export selectors

type
  EmptyArgs* = tuple[]

  MouseEventArgs* = object
    event*: MouseEvent

  ScrollEventArgs* = object
    event*: ScrollEvent

  KeyEventArgs* = object
    event*: KeyEvent

  ActionArgs* = object
    sender*: DynamicAgent

  CommandArgs* = object
    sender*: DynamicAgent

  ValidationArgs* = object
    item*: DynamicAgent

  MouseEventSelector* = Selector[MouseEvent, EmptyArgs]
  ScrollEventSelector* = Selector[ScrollEvent, EmptyArgs]
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
  method scrollWheel*(event: ScrollEvent) {.optional.}
  method keyDown*(event: KeyEvent) {.optional.}

protocol UserInterfaceValidationsInternal:
  method validateUserInterfaceItem*(args: ValidationArgs): bool

protocol ButtonActionProtocolInternal:
  method performClick*(args: ActionArgs) {.optional.}

protocol TextInputProtocolInternal:
  method insertText*(text: string) {.optional.}

protocol TextEditingCommandProtocolInternal:
  method selectText*(args: ActionArgs) {.optional.}
  method selectAll*(args: ActionArgs) {.optional.}
  method deleteBackward*(args: ActionArgs) {.optional.}
  method deleteForward*(args: ActionArgs) {.optional.}
  method deleteWordBackward*(args: ActionArgs) {.optional.}
  method deleteWordForward*(args: ActionArgs) {.optional.}
  method moveLeft*(args: ActionArgs) {.optional.}
  method moveRight*(args: ActionArgs) {.optional.}
  method moveWordLeft*(args: ActionArgs) {.optional.}
  method moveWordRight*(args: ActionArgs) {.optional.}
  method moveToBeginningOfLine*(args: ActionArgs) {.optional.}
  method moveToEndOfLine*(args: ActionArgs) {.optional.}
  method moveLeftAndModifySelection*(args: ActionArgs) {.optional.}
  method moveRightAndModifySelection*(args: ActionArgs) {.optional.}
  method moveWordLeftAndModifySelection*(args: ActionArgs) {.optional.}
  method moveWordRightAndModifySelection*(args: ActionArgs) {.optional.}
  method moveToBeginningOfLineAndModifySelection*(args: ActionArgs) {.optional.}
  method moveToEndOfLineAndModifySelection*(args: ActionArgs) {.optional.}

protocol KeyViewCommandProtocolInternal:
  method insertTab*(args: ActionArgs) {.optional.}
  method insertBacktab*(args: ActionArgs) {.optional.}
  method selectNextKeyView*(args: ActionArgs) {.optional.}
  method selectPreviousKeyView*(args: ActionArgs) {.optional.}

protocol ViewDrawingProtocolInternal:
  method draw*(context: DrawContext) {.optional.}

protocol ViewLayoutProtocolInternal:
  method layoutIntrinsicContentSize*(): IntrinsicSize {.optional.}
  method updateConstraints*() {.optional.}
  method layoutSubviews*() {.optional.}
  method layout*() {.optional.}

proc actionSelector*(name: string): ActionSelector =
  selector[ActionArgs, EmptyArgs](name)

let
  ResponderEventProtocol* = ResponderEventProtocolInternal
  UserInterfaceValidations* = UserInterfaceValidationsInternal
  ButtonActionProtocol* = ButtonActionProtocolInternal
  TextInputProtocol* = TextInputProtocolInternal
  TextEditingCommandProtocol* = TextEditingCommandProtocolInternal
  KeyViewCommandProtocol* = KeyViewCommandProtocolInternal
  ViewDrawingProtocol* = ViewDrawingProtocolInternal
  ViewLayoutProtocol* = ViewLayoutProtocolInternal
