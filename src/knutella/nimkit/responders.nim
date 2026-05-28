import std/options

import sigils/selectors as dynamicSelectors

import ./selectors
import ./types

type Responder* = ref object of DynamicAgent
  xAcceptsFirstResponder: bool

protocol ResponderProtocolInternal:
  required:
    method acceptsFirstResponder*(): bool
    method setAcceptsFirstResponder*(value: bool)
    method becomeFirstResponder*(): bool
    method resignFirstResponder*(): bool
    method tryToPerform*(args: TryToPerformArgs): bool
    method doCommandBySelector*(selector: CommandSelector)
    method noResponderFor*(selector: CommandSelector)

protocol DefaultResponder of ResponderProtocolInternal:
  method acceptsFirstResponder(self: Responder): bool =
    self.xAcceptsFirstResponder

  method setAcceptsFirstResponder(self: Responder, value: bool) =
    self.xAcceptsFirstResponder = value

  method becomeFirstResponder(self: Responder): bool =
    true

  method resignFirstResponder(self: Responder): bool =
    true

  method tryToPerform(self: Responder, args: TryToPerformArgs): bool =
    var value: EmptyArgs
    self.perform(args.selector, ActionArgs(sender: args.sender), value)

  method doCommandBySelector(self: Responder, selector: CommandSelector) =
    var value: EmptyArgs
    if not self.perform(selector, ActionArgs(sender: DynamicAgent(self)), value):
      self.noResponderFor(selector)

  method noResponderFor(self: Responder, selector: CommandSelector) =
    let owner = if self.isNil: "nil" else: "responder"
    raise newException(
      UnhandledSelectorError, owner & " did not handle selector: " & $selector.name
    )

protocol DefaultResponderEvents of ResponderEventProtocol:
  method mouseDown(self: Responder, event: MouseEvent) =
    discard

  method mouseUp(self: Responder, event: MouseEvent) =
    discard

  method keyDown(self: Responder, event: KeyEvent) =
    discard

proc initResponder*(responder: Responder) =
  discard responder.replaceMethods(DefaultResponder.init())
  discard responder.replaceMethods(DefaultResponderEvents.init())

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
  responder.perform(selector, ensureMove args)

let ResponderProtocol* = ResponderProtocolInternal
