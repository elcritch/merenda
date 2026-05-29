import std/options

import sigils/selectors as dynamicSelectors

import ./selectors

type Responder* = ref object of DynamicAgent
  xAcceptsFirstResponder: bool

protocol ResponderProtocolInternal from Responder:
  property acceptsFirstResponder -> bool

  method acceptsFirstResponder(self: Responder): bool =
    self.xAcceptsFirstResponder

  method setAcceptsFirstResponder(self: Responder, value: bool) =
    self.xAcceptsFirstResponder = value

  method becomeFirstResponder*(self: Responder): bool =
    true

  method resignFirstResponder*(self: Responder): bool =
    true

  method tryToPerform*(self: Responder, args: TryToPerformArgs): bool =
    self.sendIfHandled(args.selector, ActionArgs(sender: args.sender))

  method doCommandBySelector*(self: Responder, selector: CommandSelector) =
    if not self.sendIfHandled(selector, ActionArgs(sender: DynamicAgent(self))):
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

proc performOptional*[A, R](
    responder: Responder, selector: Selector[A, R], args: sink A
): Option[R] =
  responder.trySend(selector, ensureMove args)

let ResponderProtocol* = ResponderProtocolInternal
