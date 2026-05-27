import std/options

import sigils/selectors as dynamicSelectors

import ./selectors

type Responder* = ref object of DynamicAgent
  xNextResponder: Responder
  xAcceptsFirstResponder: bool

proc initResponder*(responder: Responder) =
  responder.xAcceptsFirstResponder = false

proc newResponder*(): Responder =
  result = Responder()
  initResponder(result)

proc nextResponder*(responder: Responder): Responder =
  responder.xNextResponder

proc setNextResponder*(responder, next: Responder) =
  responder.xNextResponder = next
  dynamicSelectors.setNextResponder(responder, next)

proc clearNextResponder*(responder: Responder) =
  responder.xNextResponder = nil
  dynamicSelectors.clearNextResponder(responder)

proc acceptsFirstResponder*(responder: Responder): bool =
  responder.xAcceptsFirstResponder

proc setAcceptsFirstResponder*(responder: Responder, value: bool) =
  responder.xAcceptsFirstResponder = value

proc becomeFirstResponder*(responder: Responder): bool =
  true

proc resignFirstResponder*(responder: Responder): bool =
  true

proc tryToPerform*[A, R](
    responder: Responder, selector: Selector[A, R], args: sink A
): bool =
  var value: R
  responder.perform(selector, ensureMove args, value)

proc performOptional*[A, R](
    responder: Responder, selector: Selector[A, R], args: sink A
): Option[R] =
  responder.perform(selector, ensureMove args)

proc doCommandBySelector*(responder: Responder, selector: CommandSelector): bool =
  var value: EmptyArgs
  responder.perform(selector, CommandArgs(sender: responder), value)

proc noResponderFor*(responder: Responder, selector: CommandSelector) =
  let owner = if responder.isNil: "nil" else: "responder"
  raise newException(
    UnhandledSelectorError, owner & " did not handle selector: " & $selector.name
  )
