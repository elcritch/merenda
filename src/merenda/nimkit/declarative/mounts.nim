## Retained mounting and keyed updates for declarative descriptions.
## All operations belong to the owning GUI thread. Model ownership stays with callers.
import std/[sets, tables]
import sigils/[core, selectors]
import ../view/views
import ../containers/stackviews
import ../controls/[buttons, controls]
import ../text/textfields
import ../responder/actiontargets
import ../foundation/[types, selectors]
import ./descriptions
import ./actions
export descriptions

type
  ViewUpdateStats* = object
    created*, reused*, removed*, moved*: int

  EventTarget = ref object of ActionAdapter
    active, updating: bool
    action, changed: ViewAction

  MountedNode = object
    view: View
    spec: ViewSpec
    target: EventTarget
    children: seq[MountedNode]

  DeclarativeView* = ref object of StackView
    mounted: MountedNode
    applying: bool
    lastUpdate: ViewUpdateStats

let DeclarativeAction = actionSelector("declarativeViewAction")

proc invokeAction(self: DynamicAgent, invocation: var Invocation) =
  let target = EventTarget(self)
  let callback = target.action
  if target.active and not target.updating:
    callback.dispatchViewAction(invocation.argsAs(ActionArgs).sender)
  invocation.setResult(())

proc fieldChanged(target: EventTarget, sender: DynamicAgent) {.slot.} =
  let callback = target.changed
  if target.active and not target.updating:
    callback.dispatchViewAction(sender)

func identity(spec: ViewSpec, index: int): string =
  if spec.key.len > 0:
    "key:" & spec.key
  elif spec.slot > 0:
    "slot:" & $spec.slot
  else:
    "position:" & $index

proc validate(spec: ViewSpec) =
  if spec.kind == vskStack:
    var keys = initHashSet[string]()
    for i, child in spec.children:
      let id = child.identity(i)
      if id in keys:
        raise newException(ValueError, "duplicate declarative sibling identity: " & id)
      keys.incl id
      validate(child)

proc newWidget(spec: ViewSpec): View =
  case spec.kind
  of vskStack:
    newStackView(spec.orientation)
  of vskLabel:
    newLabel(spec.text, spec.labelStyle)
  of vskButton:
    newButton(spec.text)
  of vskTextField:
    newTextField(spec.text)

proc applyProperties(view: View, previous, next: ViewSpec, initial: bool) =
  if initial or previous.identifier != next.identifier:
    view.identifier = next.identifier
  if initial or previous.draggable != next.draggable:
    view[vpDraggable] = next.draggable
  if initial or previous.background != next.background:
    view.backgroundColor = next.background
  case next.kind
  of vskStack:
    let stack = StackView(view)
    if initial or previous.orientation != next.orientation:
      stack.orientation = next.orientation
    if initial or previous.spacing != next.spacing:
      stack.spacing = next.spacing
    if initial or previous.padding != next.padding:
      stack.edgeInsets = next.padding
    if initial or previous.alignment != next.alignment:
      stack.alignment = next.alignment
    if initial or previous.distribution != next.distribution:
      stack.distribution = next.distribution
  of vskLabel:
    let label = Label(view)
    if initial or previous.labelStyle != next.labelStyle:
      label.labelStyle = next.labelStyle
    if initial or previous.text != next.text:
      label.stringValue = next.text
  of vskButton:
    let button = Button(view)
    if initial or previous.text != next.text:
      button.title = next.text
    if initial or previous.enabled != next.enabled:
      button.enabled = next.enabled
    if initial or previous.focusable != next.focusable:
      button.acceptsFirstResponder = next.focusable
  of vskTextField:
    let field = TextField(view)
    # Unrelated updates leave live editing alone. An echoed edit already equals
    # the editor's text; rewriting it would discard selection or marked text.
    if (initial or previous.text != next.text) and field.stringValue != next.text:
      field.stringValue = next.text
    if initial or previous.placeholder != next.placeholder:
      field.placeholder = next.placeholder

proc remember(node: var MountedNode, spec: ViewSpec) =
  node.spec = spec
  if node.spec.kind == vskStack:
    node.spec.children = @[]

proc refreshTarget(node: var MountedNode, spec: ViewSpec) =
  if not node.target.isNil:
    case spec.kind
    of vskButton:
      node.target.action = spec.onAction
    of vskTextField:
      node.target.changed = spec.onChange
    else:
      discard

proc mount(spec: ViewSpec, stats: var ViewUpdateStats): MountedNode =
  result.view = newWidget(spec)
  inc stats.created
  result.view.applyProperties(spec, spec, true)
  if spec.kind in {vskButton, vskTextField}:
    result.target = EventTarget(active: true)
    initResponder(result.target)
    result.refreshTarget(spec)
    if spec.kind == vskButton:
      discard
        result.target.replaceMethod(DeclarativeAction, DynamicMethod(invokeAction))
      Button(result.view).target = ActionAdapter(result.target)
      Button(result.view).action = DeclarativeAction
    else:
      TextField(result.view).connect(textDidChange, result.target, fieldChanged)
  if spec.kind == vskStack:
    for child in spec.children:
      let mounted = mount(child, stats)
      StackView(result.view).addArrangedSubview(mounted.view, child.sizing)
      result.children.add mounted
  result.remember(spec)

proc deactivate(node: var MountedNode, stats: var ViewUpdateStats) =
  inc stats.removed
  if not node.target.isNil:
    node.target.active = false
    node.target.action = ViewAction()
    node.target.changed = ViewAction()
    if node.spec.kind == vskTextField:
      TextField(node.view).disconnect(textDidChange, node.target, fieldChanged)
    else:
      Button(node.view).target = nil
  for child in node.children.mitems:
    child.deactivate(stats)

proc retire(node: var MountedNode, stats: var ViewUpdateStats) =
  if not node.view.isNil:
    node.deactivate(stats)
    node.view.removeFromSuperview()
    node = default(MountedNode)

proc reconcile(node: var MountedNode, spec: ViewSpec, stats: var ViewUpdateStats) =
  if node.view.isNil:
    node = mount(spec, stats)
  elif node.spec.kind != spec.kind or node.spec.identity(0) != spec.identity(0):
    node.retire(stats)
    node = mount(spec, stats)
  else:
    inc stats.reused
    node.refreshTarget(spec)
    if not node.target.isNil:
      node.target.updating = true
    try:
      node.view.applyProperties(node.spec, spec, false)
    finally:
      if not node.target.isNil:
        node.target.updating = false
    if spec.kind == vskStack:
      var previous = initTable[string, int]()
      for i, child in node.children:
        previous[child.spec.identity(i)] = i
      var next: seq[MountedNode]
      for i, child in spec.children:
        var mounted: MountedNode
        let oldIndex = previous.getOrDefault(child.identity(i), -1)
        if oldIndex >= 0:
          mounted = move node.children[oldIndex]
        mounted.reconcile(child, stats)
        next.add mounted
      # Retire event wiring before detaching a removed editor from its window.
      for old in node.children.mitems:
        old.retire(stats)
      let stack = StackView(node.view)
      for i, child in next:
        let arranged = stack.arrangedSubviews
        if i >= arranged.len or arranged[i] != child.view:
          if child.view.superview == stack:
            inc stats.moved
          stack.insertArrangedSubview(child.view, i, child.spec.sizing)
        else:
          stack.setArrangedSubviewSizingPolicy(child.view, child.spec.sizing)
      node.children = next
    node.remember(spec)

proc update*(host: DeclarativeView, spec: ViewSpec) =
  ## Reevaluate a body outside this call, then apply its description synchronously.
  ## Validation precedes mutation. Arbitrary overriding widget setters are not
  ## transactional; recursive update calls from such setters are rejected.
  if host.applying:
    raise newException(ValueError, "recursive declarative update")
  validate(spec)
  host.applying = true
  defer:
    host.applying = false
  var stats: ViewUpdateStats
  host.mounted.reconcile(spec, stats)
  if host.mounted.view.superview != host:
    host.addArrangedSubview(host.mounted.view, svspFillAvailableSpace)
  host.lastUpdate = stats

proc newDeclarativeView*(spec: ViewSpec, frame = AutoRect): DeclarativeView =
  result = DeclarativeView()
  initStackViewFields(result, laVertical, frame)
  result.spacing = 0
  result.update(spec)

proc updateStats*(host: DeclarativeView): ViewUpdateStats =
  ## Counts for the most recent update, useful when comparing implementations.
  host.lastUpdate

proc clear*(host: DeclarativeView) =
  ## Release mounted controls and their callbacks. Retained removed controls are inert.
  if host.applying:
    raise newException(ValueError, "cannot clear during a declarative update")
  host.applying = true
  defer:
    host.applying = false
  var stats: ViewUpdateStats
  host.mounted.retire(stats)
  host.lastUpdate = stats

proc materialize(spec: ViewSpec): View =
  result = newWidget(spec)
  result.applyProperties(spec, spec, true)
  if spec.kind == vskStack:
    for child in spec.children:
      StackView(result).addArrangedSubview(materialize(child), child.sizing)

proc buildDetachedView*(spec: ViewSpec): View =
  ## Build fresh widgets for layout/render capture, with no event targets or
  ## model subscriptions. Callbacks in the description are never installed.
  validate(spec)
  materialize(spec)
