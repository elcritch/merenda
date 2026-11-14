## Retained real-view composition; mutation and flushing belong to the GUI thread.
import std/[sets, tables]
import sigils/[core, selectors]
import ../view/views
import ../containers/stackviews
import ../controls/buttons
import ../text/textfields
import ../responder/actiontargets
import ../foundation/selectors
import ../declarative/actions
import ./bindings

type
  DirectTarget = ref object of ActionAdapter
    active: bool
    callback, changed: ViewAction

  DirectNode* = ref object
    view*: View
    bindings*: BindingScope
    sizing*: StackViewSizingPolicy
    children: seq[DirectNode]
    previous: Table[string, DirectNode]
    seen: HashSet[string]
    identity, widgetType: string
    authoredText: string
    hasAuthoredText: bool
    target: DirectTarget

  DirectViewSession* = ref object
    host*: StackView
    detached*: bool
    root: DirectNode
    applying, closed: bool

let DirectAction = actionSelector("directViewAction")

proc invokeAction(self: DynamicAgent, invocation: var Invocation) =
  let target = DirectTarget(self)
  let callback = target.callback
  if target.active:
    callback.dispatchViewAction(invocation.argsAs(ActionArgs).sender)
  invocation.setResult(())

proc fieldChanged(target: DirectTarget, sender: DynamicAgent) {.slot.} =
  let callback = target.changed
  if target.active:
    callback.dispatchViewAction(sender)

proc newDirectViewSession*(host: StackView, detached = false): DirectViewSession =
  if host.isNil:
    raise newException(ValueError, "direct view host cannot be nil")
  result = DirectViewSession(host: host, detached: detached)
  result.root = DirectNode(view: host, bindings: newBindingScope(preview = detached))

proc retire(node: DirectNode) =
  if node.isNil:
    return
  if not node.target.isNil:
    node.target.active = false
    node.target.callback = ViewAction()
    node.target.changed = ViewAction()
    if node.view of TextField:
      TextField(node.view).disconnect(textDidChange, node.target, fieldChanged)
  node.bindings.dispose()
  for child in node.children:
    child.retire()
  node.view.removeFromSuperview()
  node.children.setLen(0)

proc close*(session: DirectViewSession) =
  if session.isNil or session.closed:
    return
  if session.applying:
    raise newException(ValueError, "cannot close during a direct view update")
  for child in session.root.children:
    child.retire()
  session.root.children.setLen(0)
  session.root.bindings.dispose()
  session.closed = true

proc beginChildren*(node: DirectNode) =
  node.bindings.beginBindings()
  if not node.target.isNil:
    node.target.active = false
    node.target.callback = ViewAction()
    node.target.changed = ViewAction()
  node.previous.clear()
  node.seen.clear()
  for child in node.children:
    node.previous[child.identity] = child
  node.children = @[]

proc beginUpdate*(session: DirectViewSession): DirectNode =
  if session.closed or session.applying:
    raise newException(ValueError, "closed or recursively updating direct view session")
  session.applying = true
  result = session.root
  result.beginChildren()

proc endChildren*(node: DirectNode) =
  node.bindings.endBindings()
  if not node.target.isNil:
    node.target.active = true
  for id, child in node.previous:
    if id notin node.seen:
      child.retire()
  node.previous.clear()
  if node.children.len > 0 and not (node.view of StackView):
    raise newException(ValueError, "direct view children require a StackView")
  if node.view of StackView:
    let stack = StackView(node.view)
    for i, child in node.children:
      let arranged = stack.arrangedSubviews
      if i >= arranged.len or arranged[i] != child.view:
        stack.insertArrangedSubview(child.view, i, child.sizing)
      elif stack.arrangedSubviewSizingPolicy(child.view) != child.sizing:
        stack.setArrangedSubviewSizingPolicy(child.view, child.sizing)

proc endUpdate*(session: DirectViewSession) =
  try:
    session.root.endChildren()
  finally:
    session.applying = false

proc abortUpdate*(session: DirectViewSession) =
  ## Complete the partially streamed update to leave the session usable.
  session.endUpdate()

proc child*[T: View](
    session: DirectViewSession,
    parent: DirectNode,
    id, widgetType: string,
    factory: proc(): T {.closure.},
): DirectNode =
  if id in parent.seen:
    raise newException(ValueError, "duplicate direct view sibling identity: " & id)
  parent.seen.incl id
  result = parent.previous.getOrDefault(id)
  if not result.isNil and result.widgetType != widgetType:
    result.retire()
    result = nil
  if result.isNil:
    result = DirectNode(
      view: factory(),
      identity: id,
      widgetType: widgetType,
      bindings: newBindingScope(preview = session.detached),
    )
  parent.children.add result
  result.sizing = svspAutomatic
  result.beginChildren()

proc setAction*(
    session: DirectViewSession, node: DirectNode, button: Button, action: ViewAction
) =
  if session.detached:
    return
  if node.target.isNil:
    node.target = DirectTarget()
    initResponder(node.target)
    discard node.target.replaceMethod(DirectAction, DynamicMethod(invokeAction))
    button.target = ActionAdapter(node.target)
    button.action = DirectAction
  node.target.callback = action

proc bindingScope*(node: DirectNode): BindingScope =
  node.bindings

proc patchText*(node: DirectNode, field: TextField, value: string) =
  ## Preserve provisional editing when an unrelated composition repeats a value.
  if (not node.hasAuthoredText or node.authoredText != value) and
      field.stringValue != value:
    field.stringValue = value
  node.authoredText = value
  node.hasAuthoredText = true

proc disposeBindings(node: DirectNode) =
  node.bindings.dispose()
  for child in node.children:
    child.disposeBindings()

proc takeDetachedRoot*(session: DirectViewSession): View =
  ## Transfer the sole fresh preview root without installing actions or observers.
  if not session.detached or session.closed or session.applying or
      session.root.children.len != 1:
    raise newException(ValueError, "expected one completed detached root")
  let node = session.root.children[0]
  result = node.view
  result.removeFromSuperview()
  session.root.children.setLen(0)
  node.disposeBindings()
  session.root.bindings.dispose()
  session.closed = true

proc setChange*(
    session: DirectViewSession, node: DirectNode, field: TextField, action: ViewAction
) =
  if session.detached:
    return
  if node.target.isNil:
    node.target = DirectTarget()
    initResponder(node.target)
    field.connect(textDidChange, node.target, fieldChanged)
  node.target.changed = action

proc flushNode(node: DirectNode) =
  node.bindings.flushBindings()
  for child in node.children:
    child.flushNode()

proc flushBindings*(session: DirectViewSession) =
  ## Flush pending value updates without replaying structural composition.
  if not session.isNil and not session.closed:
    session.root.flushNode()
