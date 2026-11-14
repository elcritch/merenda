## Declarative event bindings use NimKit's existing target ownership rules.
import std/macros
import ../responder/[actiontargets, responders]
import ../foundation/selectors

type ViewAction* = object
  target: ActionTarget
  selector: ActionSelector

proc initViewAction*[T: Responder](selector: ActionSelector, target: T): ViewAction =
  ## Ordinary responders are weak; explicitly supplied action adapters are retained.
  result.selector = selector
  result.target{} = target

proc dispatchViewAction*(action: ViewAction, sender: DynamicAgent) =
  ## Internal bridge used by mounts; not exported through the declarative facade.
  let target = action.target{}
  if not target.isNil:
    discard target.sendLocalIfHandled(action.selector, ActionArgs(sender: sender))

macro viewAction*(receiver: typed, handler: untyped): untyped =
  ## Bind a receiver using newActionTarget's non-capturing handler contract.
  let selector = newCall(bindSym"actionSelector", newLit("declarativeViewEvent"))
  result = newCall(
    bindSym"initViewAction",
    selector,
    newCall(bindSym"newActionTarget", selector, receiver, handler),
  )

macro viewAction*(receiver, context: typed, handler: untyped): untyped =
  ## Bind explicit row context alongside the weak receiver.
  let selector = newCall(bindSym"actionSelector", newLit("declarativeViewEvent"))
  result = newCall(
    bindSym"initViewAction",
    selector,
    newCall(bindSym"newActionTarget", selector, receiver, context, handler),
  )
