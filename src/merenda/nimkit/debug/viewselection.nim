import sigils/core
import sigils/selectors

import ../foundation/events
import ../foundation/selectors as nimkitSelectors
import ../view/views

type
  ViewSelectionHandler* = proc(view: View, event: MouseEvent) {.closure.}
  ViewSelectionRemovalHandler* = proc(view: View) {.closure.}

  ViewSelectionOptions* = object
    includeRoot*: bool
    consumeUnhandledClicks*: bool
    followsSubviewChanges*: bool

  ViewSelectionState = ref object
    root: View
    handler: ViewSelectionHandler
    removalHandler: ViewSelectionRemovalHandler
    options: ViewSelectionOptions
    observer: ViewSelectionObserver
    tokens: seq[tuple[view: View, token: SwizzleToken]]
    observedViews: seq[View]
    installed: bool

  ViewSelectionObserver = ref object of Agent
    xState: ViewSelectionState

  ViewSelection* = object
    xState: ViewSelectionState

proc installOnSubtree(state: ViewSelectionState, view: View, includeSelf: bool)
proc uninstallFromSubtree(state: ViewSelectionState, view: View)

protocol ViewSelectionLifecycleSlots of ViewLifecycleProtocol:
  proc didAddSubview(observer: ViewSelectionObserver, child: View) {.slot.} =
    if not observer.xState.isNil:
      observer.xState.installOnSubtree(child, includeSelf = true)

  proc willRemoveSubview(observer: ViewSelectionObserver, child: View) {.slot.} =
    if not observer.xState.isNil:
      if not observer.xState.removalHandler.isNil:
        observer.xState.removalHandler(child)
      observer.xState.uninstallFromSubtree(child)

func initViewSelectionOptions*(
    includeRoot = true, consumeUnhandledClicks = true, followsSubviewChanges = true
): ViewSelectionOptions =
  ViewSelectionOptions(
    includeRoot: includeRoot,
    consumeUnhandledClicks: consumeUnhandledClicks,
    followsSubviewChanges: followsSubviewChanges,
  )

proc root*(selection: ViewSelection): View =
  if selection.xState.isNil: nil else: selection.xState.root

proc installed*(selection: ViewSelection): bool =
  not selection.xState.isNil and selection.xState.installed

proc hasMouseHook(state: ViewSelectionState, view: View): bool =
  for entry in state.tokens:
    if entry.view == view:
      return true

proc observesView(state: ViewSelectionState, view: View): bool =
  for observed in state.observedViews:
    if observed == view:
      return true

proc observeView(state: ViewSelectionState, view: View) =
  if view.isNil or not state.options.followsSubviewChanges or state.observesView(view):
    return
  state.observer.observeProtocol(view, ViewSelectionLifecycleSlots)
  state.observedViews.add view

proc installMouseHook(state: ViewSelectionState, view: View) =
  if view.isNil or state.hasMouseHook(view):
    return

  let
    selectionState = state
    wrapper: AroundMethod = proc(
        self: DynamicAgent, invocation: var Invocation, next: DynamicMethod
    ) =
      var originalConsumed = false
      if not next.isNil:
        next(self, invocation)
        if invocation.handled:
          originalConsumed = invocation.resultAs(bool)

      let event = invocation.argsAs(MouseEvent)
      if event.button != mbPrimary:
        return

      if selectionState.installed and not selectionState.handler.isNil:
        selectionState.handler(View(self), event)

      if selectionState.options.consumeUnhandledClicks and not originalConsumed:
        invocation.setResult(true)

  state.tokens.add (
    view: view,
    token: DynamicAgent(view).pushMethod(nimkitSelectors.mouseDown(), wrapper),
  )

proc installOnSubtree(state: ViewSelectionState, view: View, includeSelf: bool) =
  if view.isNil or not state.installed:
    return
  state.observeView(view)
  if includeSelf:
    state.installMouseHook(view)
  for child in view.subviews:
    state.installOnSubtree(child, includeSelf = true)

proc uninstallFromSubtree(state: ViewSelectionState, view: View) =
  if view.isNil:
    return

  for idx in countdown(state.observedViews.high, 0):
    let observed = state.observedViews[idx]
    if view.containsView(observed):
      state.observer.unobserveProtocol(observed, ViewSelectionLifecycleSlots)
      state.observedViews.delete(idx)

  for idx in countdown(state.tokens.high, 0):
    if view.containsView(state.tokens[idx].view):
      discard state.tokens[idx].token.popMethod()
      state.tokens.delete(idx)

proc uninstallState(state: ViewSelectionState): bool =
  if state.isNil or not state.installed:
    return

  state.installed = false
  for idx in countdown(state.observedViews.high, 0):
    state.observer.unobserveProtocol(
      state.observedViews[idx], ViewSelectionLifecycleSlots
    )
  state.observedViews.setLen(0)

  for idx in countdown(state.tokens.high, 0):
    result = state.tokens[idx].token.popMethod() or result
  state.tokens.setLen(0)
  state.root = nil
  if not state.observer.isNil:
    state.observer.xState = nil

proc installViewSelection*(
    root: View,
    handler: ViewSelectionHandler,
    options = initViewSelectionOptions(),
    removalHandler: ViewSelectionRemovalHandler = nil,
): ViewSelection =
  if root.isNil:
    return

  let state = ViewSelectionState(
    root: root,
    handler: handler,
    removalHandler: removalHandler,
    options: options,
    installed: true,
  )
  state.observer = ViewSelectionObserver(xState: state)
  state.installOnSubtree(root, options.includeRoot)
  result.xState = state

proc uninstall*(selection: var ViewSelection): bool {.discardable.} =
  result = selection.xState.uninstallState()
  selection.xState = nil
