import std/options

import sigils/selectors as dynamicSelectors

import ../foundation/events
import ../foundation/selectors

type Responder* = ref object of DynamicAgent
  xAcceptsFirstResponder: bool

protocol ResponderProtocol from Responder:
  property acceptsFirstResponder -> bool

  method acceptsFirstResponder(self: Responder): bool =
    self.xAcceptsFirstResponder

  method setAcceptsFirstResponder(self: Responder, value: bool) =
    self.xAcceptsFirstResponder = value

  method shouldBecomeFirstResponder*(self: Responder): bool =
    self.acceptsFirstResponder()

  method becomeFirstResponder*(self: Responder): bool =
    true

  method didBecomeFirstResponder*(self: Responder) =
    discard

  method shouldResignFirstResponder*(self: Responder): bool =
    true

  method resignFirstResponder*(self: Responder): bool =
    true

  method didResignFirstResponder*(self: Responder) =
    discard

  method setFirstResponderFocusState*(self: Responder, focused, focusVisible: bool) =
    discard

  method tryToPerform*(self: Responder, args: TryToPerformArgs): bool =
    self.sendLocalIfHandled(args.selector, ActionArgs(sender: args.sender))

  method doCommandBySelector*(self: Responder, selector: CommandSelector) =
    let args = TryToPerformArgs(selector: selector, sender: DynamicAgent(self))
    var responder = self
    while not responder.isNil:
      if responder.tryToPerform(args):
        return
      responder = Responder(dynamicSelectors.nextResponder(responder))
    self.noResponderFor(selector)

  method noResponderFor*(self: Responder, selector: CommandSelector) =
    let owner = if self.isNil: "nil" else: "responder"
    raise newException(
      UnhandledSelectorError, owner & " did not handle selector: " & $selector.name
    )

proc initResponder*(responder: Responder) =
  discard responder.withProto()

proc newResponder*(): Responder =
  result = Responder()
  initResponder(result)

proc nextResponder*(responder: Responder): Responder =
  Responder(dynamicSelectors.nextResponder(responder))

proc setNextResponder*(responder, next: Responder) =
  dynamicSelectors.setNextResponder(responder, next)

proc clearNextResponder*(responder: Responder) =
  dynamicSelectors.clearNextResponder(responder)

proc performKeyEquivalentInChain*(responder: Responder, event: KeyEvent): bool =
  var current = responder
  while not current.isNil:
    let handled = current.trySendLocal(performKeyEquivalent(), event)
    if handled.isSome and handled.get():
      return true
    current = current.nextResponder()

proc tryToPerform*(
    responder: Responder, selector: CommandSelector, sender: DynamicAgent = nil
): bool =
  if responder.isNil:
    return false
  responder.tryToPerform(TryToPerformArgs(selector: selector, sender: sender))

proc doCommandBySelector*(
    responder: Responder, selector: CommandSelector, sender: DynamicAgent
) =
  let args = TryToPerformArgs(selector: selector, sender: sender)
  var current = responder
  while not current.isNil:
    if current.tryToPerform(args):
      return
    current = current.nextResponder()
  responder.noResponderFor(selector)

proc findValidRequestorForSendType*(
    responder: Responder, sendType, returnType: string
): DynamicAgent =
  let args = ValidRequestorArgs(sendType: sendType, returnType: returnType)
  var current = responder
  while not current.isNil:
    let requestor = current.trySendLocal(validRequestorForSendType(), args)
    if requestor.isSome and requestor.get().isSome:
      return requestor.get().get()
    current = current.nextResponder()

proc findUndoManager*(responder: Responder): DynamicAgent =
  var current = responder
  while not current.isNil:
    let manager = current.trySendLocal(undoManager(), ())
    if manager.isSome and manager.get().isSome:
      return manager.get().get()
    current = current.nextResponder()

proc performOptional*[A, R](
    responder: Responder, selector: Selector[A, R], args: sink A
): Option[R] =
  responder.trySend(selector, ensureMove args)
