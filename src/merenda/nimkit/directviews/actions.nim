## Declarative event bindings use NimKit's existing target ownership rules.
import ../responder/[actiontargets, responders]
import ../core/selectors

type ViewAction* = object
  target: ActionTarget
  selector: ActionSelector

proc initViewAction*[T: Responder](selector: ActionSelector, target: T): ViewAction =
  ## Ordinary responders are weak; explicitly supplied action adapters are retained.
  result.selector = selector
  result.target{} = target

proc dispatchViewAction*(action: ViewAction, sender: DynamicAgent) =
  ## Internal bridge used by DirectView.
  let target = action.target{}
  if not target.isNil:
    discard target.sendLocalIfHandled(action.selector, ActionArgs(sender: sender))

template viewAction*(receiver: typed, handler: untyped): ViewAction =
  ## Bind a receiver using newActionTarget's non-capturing handler contract.
  block:
    let selector = actionSelector(sig"declarativeViewEvent")
    initViewAction(selector, newActionTarget(selector, receiver, handler))

template viewAction*(receiver, context: typed, handler: untyped): ViewAction =
  ## Bind explicit row context alongside the weak receiver.
  block:
    let selector = actionSelector(sig"declarativeViewEvent")
    initViewAction(selector, newActionTarget(selector, receiver, context, handler))
