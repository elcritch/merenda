import std/options

import sigils/selectors as dynamicSelectors

import ./selectors
import ./types

type Responder* = ref object of DynamicAgent
  xAcceptsFirstResponder: bool

protocol ResponderProtocolInternal:
  required:
    method acceptsFirstResponder(): bool
    method setAcceptsFirstResponder(value: bool)
    method becomeFirstResponder(): bool
    method resignFirstResponder(): bool
    method tryToPerform(args: TryToPerformArgs): bool
    method doCommandBySelector(selector: CommandSelector)
    method noResponderFor(selector: CommandSelector)

method responderAcceptsFirstResponder(self: Responder): bool {.selector.} =
  self.xAcceptsFirstResponder

method responderSetAcceptsFirstResponder(
    self: Responder, value: bool
): EmptyArgs {.selector.} =
  self.xAcceptsFirstResponder = value

method responderBecomeFirstResponder(self: Responder): bool {.selector.} =
  true

method responderResignFirstResponder(self: Responder): bool {.selector.} =
  true

method responderTryToPerform(
    self: Responder, args: TryToPerformArgs
): bool {.selector.} =
  var value: EmptyArgs
  self.perform(args.selector, ActionArgs(sender: args.sender), value)

method responderDoCommandBySelector(
    self: Responder, selector: CommandSelector
): EmptyArgs {.selector.} =
  var value: EmptyArgs
  if not self.perform(selector, ActionArgs(sender: DynamicAgent(self)), value):
    self.noResponderFor(selector)

method responderNoResponderFor(
    self: Responder, selector: CommandSelector
): EmptyArgs {.selector.} =
  let owner = if self.isNil: "nil" else: "responder"
  raise newException(
    UnhandledSelectorError, owner & " did not handle selector: " & $selector.name
  )

method responderMouseDown(self: Responder, event: MouseEvent): EmptyArgs {.selector.} =
  discard

method responderMouseUp(self: Responder, event: MouseEvent): EmptyArgs {.selector.} =
  discard

method responderKeyDown(self: Responder, event: KeyEvent): EmptyArgs {.selector.} =
  discard

proc installResponderMethods(responder: Responder) =
  discard responder.replaceMethod(acceptsFirstResponder, responderAcceptsFirstResponder)
  discard
    responder.replaceMethod(setAcceptsFirstResponder, responderSetAcceptsFirstResponder)
  discard responder.replaceMethod(becomeFirstResponder, responderBecomeFirstResponder)
  discard responder.replaceMethod(resignFirstResponder, responderResignFirstResponder)
  discard responder.replaceMethod(tryToPerform, responderTryToPerform)
  discard responder.replaceMethod(doCommandBySelector, responderDoCommandBySelector)
  discard responder.replaceMethod(noResponderFor, responderNoResponderFor)
  discard responder.replaceMethod(mouseDownSelector(), responderMouseDown)
  discard responder.replaceMethod(mouseUpSelector(), responderMouseUp)
  discard responder.replaceMethod(keyDownSelector(), responderKeyDown)

proc initResponder*(responder: Responder) =
  responder.xAcceptsFirstResponder = false
  responder.installResponderMethods()

proc newResponder*(): Responder =
  result = Responder()
  initResponder(result)

proc nextResponder*(responder: Responder): Responder =
  Responder(dynamicSelectors.nextResponder(responder))

proc setNextResponder*(responder, next: Responder) =
  dynamicSelectors.setNextResponder(responder, next)

proc clearNextResponder*(responder: Responder) =
  dynamicSelectors.clearNextResponder(responder)

proc acceptsFirstResponder*(responder: Responder): bool =
  responder.send(acceptsFirstResponder, ())

proc setAcceptsFirstResponder*(responder: Responder, value: bool) =
  discard responder.send(setAcceptsFirstResponder, value)

proc becomeFirstResponder*(responder: Responder): bool =
  responder.send(becomeFirstResponder, ())

proc resignFirstResponder*(responder: Responder): bool =
  responder.send(resignFirstResponder, ())

proc tryToPerform*(
    responder: Responder, selector: CommandSelector, sender: DynamicAgent
): bool =
  responder.send(tryToPerform, TryToPerformArgs(selector: selector, sender: sender))

proc doCommandBySelector*(responder: Responder, selector: CommandSelector) =
  discard responder.send(doCommandBySelector, selector)

proc noResponderFor*(responder: Responder, selector: CommandSelector) =
  discard responder.send(noResponderFor, selector)

proc performOptional*[A, R](
    responder: Responder, selector: Selector[A, R], args: sink A
): Option[R] =
  responder.perform(selector, ensureMove args)

let ResponderProtocol* = ResponderProtocolInternal
