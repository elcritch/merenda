import std/options

import sigils/selectors

from figdraw/figbasics import ZLevel

import ../drawing/drawing
import ./events
import ../text/texttypes
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

  ValidRequestorArgs* = object
    sendType*: string
    returnType*: string

  ValidationArgs* = object
    item*: DynamicAgent

  TerminationReply* = enum
    trCancel
    trNow
    trLater

  MouseEventSelector* = Selector[MouseEvent, bool]
  ScrollEventSelector* = Selector[ScrollEvent, bool]
  KeyEventSelector* = Selector[KeyEvent, bool]
  ActionSelector* = Selector[ActionArgs, EmptyArgs]
  CommandSelector* = ActionSelector
  ValidationSelector* = Selector[ValidationArgs, bool]
  ScrollEventForwardingSelector* = Selector[ScrollEvent, bool]
  KeyEquivalentSelector* = Selector[KeyEvent, bool]
  ValidRequestorSelector* = Selector[ValidRequestorArgs, Option[DynamicAgent]]
  UndoManagerSelector* = Selector[EmptyArgs, Option[DynamicAgent]]

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
  method rightMouseDown*(event: MouseEvent): bool {.optional.}
  method rightMouseDragged*(event: MouseEvent): bool {.optional.}
  method rightMouseUp*(event: MouseEvent): bool {.optional.}
  method otherMouseDown*(event: MouseEvent): bool {.optional.}
  method otherMouseDragged*(event: MouseEvent): bool {.optional.}
  method otherMouseUp*(event: MouseEvent): bool {.optional.}
  method mouseEntered*(event: MouseEvent): bool {.optional.}
  method mouseExited*(event: MouseEvent): bool {.optional.}
  method mouseMoved*(event: MouseEvent): bool {.optional.}
  method mouseDragged*(event: MouseEvent): bool {.optional.}
  method cursorUpdate*(event: MouseEvent): bool {.optional.}
  method updateTrackingAreas*(event: MouseEvent): bool {.optional.}
  method wantsForwardedScrollEvents*(event: ScrollEvent): bool {.optional.}
  method scrollWheel*(event: ScrollEvent): bool {.optional.}
  method keyDown*(event: KeyEvent): bool {.optional.}
  method keyUp*(event: KeyEvent): bool {.optional.}
  method flagsChanged*(event: KeyEvent): bool {.optional.}
  method helpRequested*(event: MouseEvent): bool {.optional.}

protocol ResponderCommandDispatchProtocol:
  method performKeyEquivalent*(event: KeyEvent): bool {.optional.}
  method validRequestorForSendType*(
    args: ValidRequestorArgs
  ): Option[DynamicAgent] {.optional.}

  method undoManager*(): Option[DynamicAgent] {.optional.}

protocol MouseHitPolicyProtocol:
  method mouseHitPolicy*(args: MouseHitPolicyArgs): CellHitPolicy {.optional.}
  method applyMouseHitPolicy*(args: MouseHitPolicyArgs): bool {.optional.}

protocol UserInterfaceValidations:
  method validateUserInterfaceItem*(args: ValidationArgs): bool

protocol MenuDelegateProtocol:
  method menuNeedsUpdate*(menu: DynamicAgent) {.optional.}
  method menuWillOpen*(menu: DynamicAgent) {.optional.}
  method menuDidClose*(menu: DynamicAgent) {.optional.}

protocol ApplicationDelegateProtocol:
  method appWillFinishLaunching*(app: DynamicAgent) {.optional.}
  method appDidFinishLaunching*(app: DynamicAgent) {.optional.}
  method appDidBecomeActive*(app: DynamicAgent) {.optional.}
  method appDidResignActive*(app: DynamicAgent) {.optional.}
  method appWillHide*(app: DynamicAgent) {.optional.}
  method appDidHide*(app: DynamicAgent) {.optional.}
  method appWillUnhide*(app: DynamicAgent) {.optional.}
  method appDidUnhide*(app: DynamicAgent) {.optional.}
  method appShouldTerminate*(app: DynamicAgent): TerminationReply {.optional.}
  method appWillTerminate*(app: DynamicAgent) {.optional.}

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
  method deleteToBeginningOfLine*(args: ActionArgs) {.optional.}
  method deleteToEndOfLine*(args: ActionArgs) {.optional.}
  method insertLineBreak*(args: ActionArgs) {.optional.}
  method insertParagraphSeparator*(args: ActionArgs) {.optional.}
  method moveLeft*(args: ActionArgs) {.optional.}
  method moveRight*(args: ActionArgs) {.optional.}
  method moveUp*(args: ActionArgs) {.optional.}
  method moveDown*(args: ActionArgs) {.optional.}
  method moveWordLeft*(args: ActionArgs) {.optional.}
  method moveWordRight*(args: ActionArgs) {.optional.}
  method moveWordBackward*(args: ActionArgs) {.optional.}
  method moveWordForward*(args: ActionArgs) {.optional.}
  method moveToBeginningOfLine*(args: ActionArgs) {.optional.}
  method moveToEndOfLine*(args: ActionArgs) {.optional.}
  method moveToBeginningOfDocument*(args: ActionArgs) {.optional.}
  method moveToEndOfDocument*(args: ActionArgs) {.optional.}
  method moveLeftAndModifySelection*(args: ActionArgs) {.optional.}
  method moveRightAndModifySelection*(args: ActionArgs) {.optional.}
  method moveUpAndModifySelection*(args: ActionArgs) {.optional.}
  method moveDownAndModifySelection*(args: ActionArgs) {.optional.}
  method moveWordLeftAndModifySelection*(args: ActionArgs) {.optional.}
  method moveWordRightAndModifySelection*(args: ActionArgs) {.optional.}
  method moveWordBackwardAndModifySelection*(args: ActionArgs) {.optional.}
  method moveWordForwardAndModifySelection*(args: ActionArgs) {.optional.}
  method moveToBeginningOfLineAndModifySelection*(args: ActionArgs) {.optional.}
  method moveToEndOfLineAndModifySelection*(args: ActionArgs) {.optional.}
  method moveToBeginningOfDocumentAndModifySelection*(args: ActionArgs) {.optional.}
  method moveToEndOfDocumentAndModifySelection*(args: ActionArgs) {.optional.}

protocol KeyViewCommandProtocol:
  method insertNewline*(args: ActionArgs) {.optional.}
  method insertTab*(args: ActionArgs) {.optional.}
  method insertBacktab*(args: ActionArgs) {.optional.}
  method insertNewlineIgnoringFieldEditor*(args: ActionArgs) {.optional.}
  method insertTabIgnoringFieldEditor*(args: ActionArgs) {.optional.}
  method selectNextKeyView*(args: ActionArgs) {.optional.}
  method selectPreviousKeyView*(args: ActionArgs) {.optional.}

protocol MenuCommandProtocol:
  method cancelOperation*(args: ActionArgs) {.optional.}
  method complete*(args: ActionArgs) {.optional.}
  method orderFrontStandardAboutPanel*(args: ActionArgs) {.optional.}
  method hide*(args: ActionArgs) {.optional.}
  method hideOtherApplications*(args: ActionArgs) {.optional.}
  method unhideAllApplications*(args: ActionArgs) {.optional.}
  method terminate*(args: ActionArgs) {.optional.}
  method newDocument*(args: ActionArgs) {.optional.}
  method openDocument*(args: ActionArgs) {.optional.}
  method saveDocument*(args: ActionArgs) {.optional.}
  method saveDocumentAs*(args: ActionArgs) {.optional.}
  method revertDocumentToSaved*(args: ActionArgs) {.optional.}
  method printDocument*(args: ActionArgs) {.optional.}
  method close*(args: ActionArgs) {.optional.}
  method performClose*(args: ActionArgs) {.optional.}
  method performMiniaturize*(args: ActionArgs) {.optional.}
  method performZoom*(args: ActionArgs) {.optional.}
  method toggleFullScreen*(args: ActionArgs) {.optional.}

protocol CollectionCommandProtocol:
  method pageUp*(args: ActionArgs) {.optional.}
  method pageDown*(args: ActionArgs) {.optional.}
  method scrollToBeginningOfDocument*(args: ActionArgs) {.optional.}
  method scrollToEndOfDocument*(args: ActionArgs) {.optional.}
  method insertNewItem*(args: ActionArgs) {.optional.}
  method deleteSelection*(args: ActionArgs) {.optional.}

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
