import std/options

import sigils/selectors as dynamicSelectors
from sigils/hom import findFirst, findFirstReply, get, isSome

import ../foundation/events
import ../foundation/backrefs
import ../foundation/selectors
import ../foundation/undomanagers

export backrefs

type
  Responder* = ref object of DynamicAgent
    xBackRefs*: BackRefSet[Responder]
    xNextResponderLink: ResponderLink
    xFocusable: bool

  ResponderLink = ref object of DynamicAgent
    targetRef: BackRef[Responder]

protocol ToolbarFocusProtocol:
  method requestToolbarFocus*(focused: Responder): Option[bool] {.optional.}
    ## Toggle focus between a tool's content and toolbar. Return `some` with
    ## the focus result to claim the request, or `none` to defer.

proc `target=`*[T: Responder](backRef: var BackRef[T], target: T) {.inline.} =
  if target.isNil:
    backRef.clear()
  else:
    backRef.set(target, target.xBackRefs)

proc `target=`*(backRef: var BackRef[Responder], target: Responder) =
  # Keep nil responders out of the DynamicAgent upcast on Nim 2.2.
  if target.isNil:
    backRef.clear()
  else:
    backRef.set(target, target.xBackRefs)

proc `target=`*(backRef: var BackRef[Responder], target: DynamicAgent) =
  ## Action targets need Responder's zeroing lifetime tracking.
  if not target.isNil and not (target of Responder):
    raise newException(ValueError, "Action target must be a Responder")
  if target.isNil:
    backRef.clear()
  else:
    let responder = Responder(target)
    backRef.set(responder, responder.xBackRefs)

proc `{}=`*[T: Responder](backRef: var BackRef[T], target: T) {.inline.} =
  ## Set a responder back reference without retaining the target.
  backRef.target = target

proc `{}=`*(backRef: var BackRef[Responder], target: Responder) {.inline.} =
  ## Keep typed nil responders out of the DynamicAgent upcast on Nim 2.2.
  backRef.target = target

proc `{}=`*(backRef: var BackRef[Responder], target: DynamicAgent) {.inline.} =
  ## Set a responder back reference, rejecting non-responder targets.
  backRef.target = target

proc `{}=`*[T: Responder](backRef: var BackRef[T], target: typeof(nil)) {.inline.} =
  ## Clear a responder back reference.
  backRef.clear()

proc asDynamicAgent*[T: Responder](target: T): DynamicAgent {.inline.} =
  ## Upcast only non-nil responders; Nim 2.2 otherwise emits a nil member access.
  if not target.isNil:
    result = DynamicAgent(target)

proc nextResponder*(responder: Responder): Responder
proc clearNextResponder*(responder: Responder)
proc performCommandInChain*(
  responder: Responder, args: TryToPerformArgs
): Responder {.discardable.}

proc responderLinkTarget(self: DynamicAgent, selector: SigilName): DynamicAgent =
  discard selector
  if not self.isNil:
    let link = ResponderLink(self)
    if not link.targetRef.isNil:
      result = DynamicAgent(link.targetRef.target)

protocol ResponderProtocol {.setterStyle: nim.} from Responder:
  ## `focusable` controls whether a responder can become the first responder.
  property focusable -> bool {.field: xFocusable.}

  method shouldBecomeFirstResponder*(self: Responder): bool =
    self.focusable()

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
    let routed = self.trySendLocal(dispatchCommand(), args)
    if routed.isSome:
      return routed.get()
    self.sendLocalIfHandled(args.selector, ActionArgs(sender: args.sender))

  method doCommandBySelector*(self: Responder, selector: CommandSelector) =
    let args = TryToPerformArgs(selector: selector, sender: DynamicAgent(self))
    if self.performCommandInChain(args).isNil:
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
  if not responder.isNil and not responder.xNextResponderLink.isNil and
      not responder.xNextResponderLink.targetRef.isNil:
    result = responder.xNextResponderLink.targetRef.target

proc setNextResponder*(responder, next: Responder) =
  if next.isNil:
    responder.clearNextResponder()
    return
  if responder.xNextResponderLink.isNil:
    let link = ResponderLink()
    dynamicSelectors.setForwardingTarget(link, responderLinkTarget)
    responder.xNextResponderLink = link
  responder.xNextResponderLink.targetRef.target = next
  dynamicSelectors.setNextResponder(responder, responder.xNextResponderLink)

proc clearNextResponder*(responder: Responder) =
  if not responder.xNextResponderLink.isNil:
    responder.xNextResponderLink.targetRef.clear()
  dynamicSelectors.clearNextResponder(responder)

iterator responderChain*(responder: Responder, stopBefore: Responder = nil): Responder =
  ## Walk live responder links up to the exclusive boundary.
  var current = responder
  while not current.isNil and current != stopBefore:
    yield current
    current = current.nextResponder()

proc responderChainContains*(responder, member: Responder): bool =
  ## Check identity along the live chain, including the starting responder.
  let match = responder.responderChain().findFirst do(candidate: Responder) -> bool:
    candidate == member
  match.isSome

proc performCommandInChain*(responder: Responder, args: TryToPerformArgs): Responder =
  ## Dispatch the command and return the first responder that consumes it.
  let handlesCommand = proc(candidate: Responder): bool =
    candidate.tryToPerform(args)
  responder.responderChain().findFirst(handlesCommand).get(nil)

proc performKeyEquivalentInChain*(responder: Responder, event: KeyEvent): bool =
  responder.responderChain().findFirst(performKeyEquivalent(), event).isSome

proc performToolbarFocusInChain*(focused: Responder): bool =
  ## Return the first claimed toolbar focus result, or false if every responder defers.
  let match = focused.responderChain().findFirstReply(
      requestToolbarFocus(), focused, options.isSome[bool]
    )
  match.isSome and match.get().reply.get()

proc sendToFirstHandlerInChain*[A](
    responder: Responder, selector: Selector[A, EmptyArgs], args: A
): bool =
  ## Send locally along the live responder chain until a handler runs.
  let handled = proc(_: EmptyArgs): bool =
    true
  responder.responderChain().findFirst(selector, args, handled).isSome

proc performScrollKeyInChain*(
    responder: Responder, event: KeyEvent, consumeIfOffered = false
): bool =
  ## Route unmodified reading keys through scroll containers.
  ## Containers without overflow on the requested axis defer to an outer container.
  ## Readers can consume an offered key even without overflow to preserve selection.
  if event.modifiers != {} or event.key notin KeyboardScrollKeys:
    return
  for candidate in responder.responderChain():
    let reply = candidate.trySendLocal(scrollKey(), event)
    if reply.isSome:
      if reply.get():
        return true
      result = consumeIfOffered

proc tryToPerform*(
    responder: Responder, selector: CommandSelector, sender: DynamicAgent = nil
): bool =
  responder.tryToPerform(TryToPerformArgs(selector: selector, sender: sender))

proc doCommandBySelector*(
    responder: Responder, selector: CommandSelector, sender: DynamicAgent
) =
  let args = TryToPerformArgs(selector: selector, sender: sender)
  if responder.performCommandInChain(args).isNil:
    responder.noResponderFor(selector)

proc findUndoManager*(responder: Responder): UndoManager =
  let matched = responder.responderChain().findFirstReply(
      undoManager(), (), options.isSome[UndoManager]
    )
  if matched.isSome:
    result = matched.get().reply.get()

proc performOptional*[A, R](
    responder: Responder, selector: Selector[A, R], args: sink A
): Option[R] =
  responder.trySend(selector, ensureMove args)
