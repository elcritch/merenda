import sigils/selectors

from figdraw/figbasics import ZLevel

import ./drawing
import ./events
import ./texttypes
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

  MouseHitPolicyArgs* = object
    target*: DynamicAgent
    event*: MouseEvent

  ActionArgs* = object
    sender*: DynamicAgent

  CommandArgs* = object
    sender*: DynamicAgent

  ValidationArgs* = object
    item*: DynamicAgent

  MouseEventSelector* = Selector[MouseEvent, bool]
  ScrollEventSelector* = Selector[ScrollEvent, EmptyArgs]
  KeyEventSelector* = Selector[KeyEvent, EmptyArgs]
  ActionSelector* = Selector[ActionArgs, EmptyArgs]
  CommandSelector* = ActionSelector
  ValidationSelector* = Selector[ValidationArgs, bool]
  ScrollEventForwardingSelector* = Selector[ScrollEvent, bool]

  TryToPerformArgs* = object
    selector*: CommandSelector
    sender*: DynamicAgent

## Event handler return contract:
## returning ``true`` means the handler consumed the event and bubbling should stop;
## returning ``false`` means the event was not handled and should continue to the
## next responder in the chain.
protocol ResponderEventProtocol:
  method mouseDown*(event: MouseEvent): bool {.optional.}
  method mouseUp*(event: MouseEvent): bool {.optional.}
  method mouseEntered*(event: MouseEvent): bool {.optional.}
  method mouseExited*(event: MouseEvent): bool {.optional.}
  method mouseMoved*(event: MouseEvent): bool {.optional.}
  method mouseDragged*(event: MouseEvent): bool {.optional.}
  method wantsForwardedScrollEvents*(event: ScrollEvent): bool {.optional.}
  method scrollWheel*(event: ScrollEvent) {.optional.}
  method keyDown*(event: KeyEvent) {.optional.}

protocol MouseHitPolicyProtocol:
  method mouseHitPolicy*(args: MouseHitPolicyArgs): CellHitPolicy {.optional.}
  method applyMouseHitPolicy*(args: MouseHitPolicyArgs): bool {.optional.}

protocol UserInterfaceValidations:
  method validateUserInterfaceItem*(args: ValidationArgs): bool

protocol ButtonActionProtocol:
  method performClick*(args: ActionArgs) {.optional.}

protocol TextInputProtocol:
  method insertText*(text: string) {.optional.}
  method setMarkedText*(
    text: string, selectedRange: TextRange, replacementRange: TextRange
  ) {.optional.}

  method unmarkText*() {.optional.}

protocol TextEditingCommandProtocol:
  method selectText*(args: ActionArgs) {.optional.}
  method selectAll*(args: ActionArgs) {.optional.}
  method copy*(args: ActionArgs) {.optional.}
  method cut*(args: ActionArgs) {.optional.}
  method paste*(args: ActionArgs) {.optional.}
  method undo*(args: ActionArgs) {.optional.}
  method redo*(args: ActionArgs) {.optional.}
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

protocol KeyViewCommandProtocol:
  method insertNewline*(args: ActionArgs) {.optional.}
  method insertTab*(args: ActionArgs) {.optional.}
  method insertBacktab*(args: ActionArgs) {.optional.}
  method insertNewlineIgnoringFieldEditor*(args: ActionArgs) {.optional.}
  method insertTabIgnoringFieldEditor*(args: ActionArgs) {.optional.}
  method selectNextKeyView*(args: ActionArgs) {.optional.}
  method selectPreviousKeyView*(args: ActionArgs) {.optional.}

protocol ViewDrawingProtocol:
  method drawLevel*(): ZLevel {.optional.}
  method draw*(context: DrawContext) {.optional.}

protocol ViewLayoutProtocol:
  method layoutIntrinsicContentSize*(): IntrinsicSize {.optional.}
  method updateConstraints*() {.optional.}
  method layoutSubviews*() {.optional.}
  method layout*() {.optional.}

proc actionSelector*(name: string): ActionSelector =
  selector[ActionArgs, EmptyArgs](name)
