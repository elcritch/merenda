## Retained real-view composition; mutation and flushing belong to the GUI thread.
import std/[sets, tables]
import sigils/[collections, core, reactive, selectors]
import ../view/views
import ../containers/stackviews
import ../controls/buttons
import ../text/textfields
import ../responder/actiontargets
import ../foundation/[selectors, types]
import ../declarative/actions
import ./bindings

type
  DirectTarget = ref object of ActionAdapter
    active: bool
    lifetime: BackRef[DirectNode]
    callback, changed: ViewAction

  DirectNode* = ref object of Responder
    ## Owned composition context. Pass it to ordinary component builder procs.
    ownedView: View
    hostRef: BackRef[StackView]
    parent: BackRef[DirectNode]
    compositionOwner: BackRef[Responder]
    bindings*: BindingScope
    bodyBindings: BindingScope
    sizing*: StackViewSizingPolicy
    children: seq[DirectNode]
    previous: Table[string, DirectNode]
    seen: HashSet[string]
    identity, widgetType: string
    authoredText: string
    hasAuthoredText, detached, applying, closed, component: bool
    collectingBody, suspended: bool
    target: DirectTarget

  DirectView* = ref object of StackView
    root: DirectNode

  DirectViewSession* = ref object
    ## Low-level compatibility API for an externally supplied host.
    host*: StackView
    detached*: bool
    root: DirectNode
    lifetimeOwner: Responder

  BodyValue[R, T] = object
    owner: BackRef[R]
    value: T
    draw: proc(context: DirectNode, owner: R, value: T) {.nimcall.}

let DirectAction = actionSelector("directViewAction")

proc view*(node: DirectNode): View =
  if node.component:
    if node.children.len == 1:
      result = node.children[0].view
  elif not node.ownedView.isNil:
    result = node.ownedView
  else:
    result = node.hostRef{}

proc invokeAction(self: DynamicAgent, invocation: var Invocation) =
  let target = DirectTarget(self)
  let callback = target.callback
  if target.active and not target.lifetime.isNil:
    callback.dispatchViewAction(invocation.argsAs(ActionArgs).sender)
  invocation.setResult(())

proc fieldChanged(target: DirectTarget, sender: DynamicAgent) {.slot.} =
  let callback = target.changed
  if target.active and not target.lifetime.isNil:
    callback.dispatchViewAction(sender)

proc newRoot(host: StackView, detached: bool, owner: Responder): DirectNode =
  result = DirectNode(detached: detached)
  result.compositionOwner.target = owner
  result.bindings = newBindingScope(preview = detached, owner = result.compositionOwner)
  result.hostRef.target = host

proc newDirectView*(frame = AutoRect, detached = false): DirectView =
  ## The view owns all composition and binding state. No session teardown needed.
  result = DirectView()
  initStackViewFields(result, laVertical, frame)
  result.spacing = 0
  result.distribution = svdNatural
  result.root = newRoot(result, detached, result)

proc newDirectViewSession*(host: StackView, detached = false): DirectViewSession =
  if host.isNil:
    raise newException(ValueError, "direct view host cannot be nil")
  let owner = Responder()
  DirectViewSession(
    host: host,
    detached: detached,
    root: newRoot(host, detached, owner),
    lifetimeOwner: owner,
  )

proc retireBindings(node: DirectNode) =
  let widget = node.ownedView
  if not widget.isNil and widget.xDirectNode{} == Responder(node):
    widget.xDirectNode.clear()
  node.bindings.dispose()
  node.bodyBindings.dispose()

proc retire(node: DirectNode) =
  if node.isNil:
    return
  if not node.target.isNil:
    node.target.active = false
    node.target.callback = ViewAction()
    node.target.changed = ViewAction()
    if node.view of TextField:
      TextField(node.view).disconnect(textDidChange, node.target, fieldChanged)
  node.retireBindings()
  for child in node.children:
    child.retire()
  if not node.view.isNil:
    node.view.removeFromSuperview()
  node.children.setLen(0)
  node.closed = true

proc clearNode(node: DirectNode) =
  if node.applying:
    raise newException(ValueError, "cannot clear during a direct view update")
  for child in node.children:
    child.retire()
  node.children.setLen(0)
  node.retireBindings()
  node.closed = true

proc retireEffects(node: DirectNode) =
  if not node.isNil and not node.closed:
    if not node.target.isNil:
      node.target.active = false
      node.target.callback = ViewAction()
      node.target.changed = ViewAction()
    node.retireBindings()
    for child in node.children:
      child.retireEffects()

proc retireEffects*(view: DirectView) =
  ## Disconnect effects before an owning container ends an active editor.
  if not view.isNil:
    view.root.retireEffects()

proc close*(session: DirectViewSession) =
  if not session.isNil and not session.root.closed:
    session.root.clearNode()

proc clear*(view: DirectView) =
  ## Explicitly retire content while keeping the host available for a new body.
  let
    suspended = view.root.suspended
    detached = view.root.detached
  view.root.clearNode()
  view.root = newRoot(view, detached, view)
  if suspended:
    view.root.suspended = true
    view.root.bindings.suspendBindings()

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

proc beginUpdate*(node: DirectNode): DirectNode =
  if node.closed or node.applying or not node.bindings.isActive:
    raise newException(ValueError, "closed or recursively updating direct view context")
  if node.suspended:
    raise newException(ValueError, "cannot update a suspended direct view context")
  node.applying = true
  node.beginChildren()
  node

proc beginUpdate*(session: DirectViewSession): DirectNode =
  session.root.beginUpdate()

proc beginUpdate*(view: DirectView): DirectNode =
  view.root.beginUpdate()

proc arrangeChildren(node: DirectNode) =
  if node.component:
    let parent = node.parent{}
    if not parent.isNil and not parent.applying:
      parent.arrangeChildren()
    return
  if node.children.len > 0 and not (node.view of StackView):
    raise newException(ValueError, "direct view children require a StackView")
  if node.view of StackView:
    let stack = StackView(node.view)
    var children: seq[ArrangedSubview]
    for child in node.children:
      children.add ArrangedSubview(view: child.view, sizingPolicy: child.sizing)
    stack.arrangeSubviewPrefix(children)

proc endChildren*(node: DirectNode) =
  if node.view of TextField and node.bindings.ownsText(TextField(node.view)):
    node.hasAuthoredText = false
  node.bindings.endBindings()
  if not node.target.isNil:
    node.target.active = true
  for id, child in node.previous:
    if id notin node.seen:
      child.retire()
  node.previous.clear()
  if node.component:
    if node.children.len != 1:
      raise newException(ValueError, "a direct component requires exactly one root")
    node.sizing = node.children[0].sizing
  node.arrangeChildren()

proc endUpdate*(node: DirectNode) =
  try:
    node.endChildren()
  finally:
    node.applying = false

proc endUpdate*(session: DirectViewSession) =
  session.root.endUpdate()

proc endUpdate*(view: DirectView) =
  view.root.endUpdate()

proc interruptUpdate(node: DirectNode) =
  # Keep unvisited mounts reachable by clear(). Arranging a partial
  # component here can mask the body error with a root-count error.
  for id, child in node.previous:
    if id notin node.seen:
      node.children.add child
  node.previous.clear()
  node.applying = false

template composeBody*(receiver, context, body: untyped) =
  ## Finish a streamed body on normal exit, including an early return.
  block:
    let host = receiver
    let context = beginUpdate(host)
    try:
      body
    except CatchableError:
      interruptUpdate(context)
      raise
    finally:
      if context.applying:
        endUpdate(host)

proc abortUpdate*(session: DirectViewSession) =
  ## Complete a partially streamed update; this is not a rollback.
  session.endUpdate()

proc child*[T: View](
    parent: DirectNode, id, widgetType: string, factory: proc(): T {.closure.}
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
      ownedView: factory(),
      identity: id,
      widgetType: widgetType,
      compositionOwner: parent.compositionOwner,
      bindings:
        newBindingScope(preview = parent.detached, owner = parent.compositionOwner),
      detached: parent.detached,
    )
    result.parent.target = parent
    if not result.ownedView.isNil:
      result.ownedView.xDirectNode.target = result
  parent.children.add result
  result.sizing = svspAutomatic

proc componentChild*(parent: DirectNode, id, widgetType: string): DirectNode =
  ## A metadata-only identity boundary; components add no wrapper widgets.
  result = parent.child(
    id,
    widgetType,
    proc(): View =
      nil,
  )
  result.component = true
  result.collectingBody = true
  if not result.bodyBindings.isNil:
    result.bodyBindings.beginBindings()

proc endComponent*(node: DirectNode) =
  if not node.bodyBindings.isNil:
    node.bodyBindings.endBindings()
  node.collectingBody = false

proc setAction*(node: DirectNode, button: Button, action: ViewAction) =
  if node.detached:
    return
  if node.target.isNil:
    node.target = DirectTarget()
    node.target.lifetime.target = node
    initResponder(node.target)
    discard node.target.replaceMethod(DirectAction, DynamicMethod(invokeAction))
    button.target = ActionAdapter(node.target)
    button.action = DirectAction
  node.target.callback = action

proc bindingScope*(node: DirectNode): BindingScope =
  node.bindings

proc bindingScopeFor(view: View): BindingScope =
  if not view.isNil:
    let owner = view.xDirectNode{}
    if owner of DirectNode:
      let node = DirectNode(owner)
      if node.ownedView == view and node.bindings.isActive:
        return node.bindings
  raise newException(ValueError, "View has no active DirectView binding scope")

template bindTextField*(view: View, args: varargs[untyped]): untyped =
  ## Bind a text field using this widget's active DirectView scope.
  bindTextField(bindingScopeFor(view), args)

template bindValue*(view: View, args: varargs[untyped]): untyped =
  ## Bind a value using this widget's active DirectView scope.
  bindValue(bindingScopeFor(view), args)

proc patchText*(node: DirectNode, field: TextField, value: string) =
  ## Preserve provisional editing when an unrelated composition repeats a value.
  if node.bindings.relinquishText(field):
    node.hasAuthoredText = false
  if (not node.hasAuthoredText or node.authoredText != value) and
      field.stringValue != value:
    field.stringValue = value
  node.authoredText = value
  node.hasAuthoredText = true

proc disposeBindings(node: DirectNode) =
  node.retireBindings()
  for child in node.children:
    child.disposeBindings()

proc takeRoot(node: DirectNode): View =
  if not node.detached or node.closed or node.applying or node.children.len != 1:
    raise newException(ValueError, "expected one completed detached root")
  let child = node.children[0]
  result = child.view
  result.removeFromSuperview()
  node.children.setLen(0)
  child.disposeBindings()
  node.retireBindings()
  node.closed = true

proc takeDetachedRoot*(session: DirectViewSession): View =
  session.root.takeRoot()

proc takeDetachedRoot*(view: DirectView): View =
  view.root.takeRoot()

proc setChange*(node: DirectNode, field: TextField, action: ViewAction) =
  if node.detached:
    return
  if node.target.isNil:
    node.target = DirectTarget()
    node.target.lifetime.target = node
    initResponder(node.target)
    field.connect(textDidChange, node.target, fieldChanged)
  node.target.changed = action

proc flushBindings*(node: sink DirectNode) =
  ## Keep the node alive when a binding clears or replaces its owning root.
  if not node.isNil and not node.closed and not node.suspended:
    node.bodyBindings.flushBindings()
    if not node.closed and not node.suspended:
      node.bindings.flushBindings()
      var children: seq[DirectNode]
      for child in node.children:
        children.add child
      for child in children:
        if node.closed or node.suspended:
          break
        if not child.closed and child.parent{} == node:
          child.flushBindings()

proc hasApplyingNode(node: DirectNode): bool =
  if not node.isNil and not node.closed:
    if node.applying:
      return true
    for child in node.children:
      if child.hasApplyingNode():
        return true

proc suspendNode(node: DirectNode) =
  if not node.isNil and not node.closed and not node.suspended:
    node.suspended = true
    node.bodyBindings.suspendBindings()
    node.bindings.suspendBindings()
    for child in node.children:
      child.suspendNode()

proc resumeNode(node: DirectNode) =
  if not node.isNil and not node.closed and node.suspended:
    node.suspended = false
    node.bodyBindings.resumeBindings(flush = false)
    node.bindings.resumeBindings(flush = false)
    for child in node.children:
      child.resumeNode()

proc suspendUpdates*(session: DirectViewSession) =
  ## Pause observed writes without detaching the retained view tree. An active
  ## composition must finish first. Action callbacks remain enabled.
  if not session.isNil:
    if session.root.hasApplyingNode():
      raise newException(ValueError, "cannot suspend during a direct view update")
    session.root.suspendNode()

proc suspendUpdates*(view: DirectView) =
  if not view.isNil:
    if view.root.hasApplyingNode():
      raise newException(ValueError, "cannot suspend during a direct view update")
    view.root.suspendNode()

proc resumeUpdates*(session: DirectViewSession) =
  ## Apply coalesced pending changes from current sources.
  if not session.isNil and not session.root.closed and session.root.suspended:
    session.root.resumeNode()
    session.root.flushBindings()

proc resumeUpdates*(view: DirectView) =
  if not view.isNil and not view.root.closed and view.root.suspended:
    view.root.resumeNode()
    view.root.flushBindings()

proc flushBindings*(session: DirectViewSession) =
  session.root.flushBindings()

proc flushBindings*(view: DirectView) =
  view.root.flushBindings()

proc bindBody*[S; R: Responder, T](
    node: DirectNode,
    input: S,
    owner: R,
    draw: proc(context: DirectNode, owner: R, value: T) {.nimcall.},
) =
  ## A component-owned structural binding. The body may update its own child
  ## bindings without removing this subscription. Receiver and context are weak.
  if node.bodyBindings.isNil:
    node.bodyBindings =
      newBindingScope(preview = node.detached, owner = node.compositionOwner)
    if node.collectingBody:
      node.bodyBindings.beginBindings()
  type Input = tuple[source: S, draw: typeof(draw)]
  proc read(owner: R, input: Input): BodyValue[R, T] =
    result.owner.target = owner
    result.draw = input.draw
    unBindSigilEvents:
      result.value = input.source{}

  proc apply(node: DirectNode, value: BodyValue[R, T]) =
    let owner = value.owner{}
    if not owner.isNil:
      value.draw(node, owner, value.value)

  bindSigilValue(
    node.bodyBindings, "body", input, owner, (input, draw), read, node, apply
  )
