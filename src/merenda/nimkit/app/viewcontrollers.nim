## View-controller infrastructure for NimKit applications.
##
## A `ViewController` owns or lazily builds one `View`, coordinates view lifecycle
## callbacks, and participates in the responder chain. It is intended for content
## construction and orchestration that does not belong directly in a `View`
## subclass: represented-object routing, command validation, undo-manager lookup,
## and child-controller containment.
##
## View controllers complement plain view composition. A controller can vend a
## reusable panel, a document-backed content view, or a split/sidebar composition,
## while the actual widgets remain ordinary `View` instances. `WindowController`
## can install a `ViewController` as window content, and `Document` seeds
## document-owned content controllers with the document as their represented
## object.
##
## The public contract is deliberately backend-free: native handles belong to
## windows, views, and platform adapters, not to view controllers.

import std/options

import sigils/core

import ../foundation/selectors
import ../foundation/undomanagers
import ../responder/responders
import ../view/views

type ViewController* = ref object of Responder
  ## Owns view construction and lifecycle for a view subtree.
  ##
  ## `ViewController` is also a responder. Its owned view is routed to the
  ## controller first, then onward to the parent controller, superview, window, or
  ## existing next responder as appropriate. Subclass it when view construction or
  ## command behavior needs identity and lifecycle without baking that logic into a
  ## `View` subclass.
  xView: View
  xDelegate: DynamicAgent
  xRepresentedObject: DynamicAgent
  xParentViewController: ViewController
  xChildViewControllers: seq[ViewController]
  xUndoManager: UndoManager
  xViewVisible: bool
  xAppearing: bool
  xDisappearing: bool
  xTearingDown: bool

protocol ViewControllerLoading {.selectorScope: protocol.}:
  method makeView*(): View {.optional.}
    ## Builds the controller's view when `loadView` is first called.
    ##
    ## Implement this on a controller subclass to construct the view tree lazily.
    ## Returning `nil` falls back to `newView()`.

protocol ViewControllerDelegate:
  method viewControllerWillLoadView*(controller: ViewController) {.optional.}
    ## Runs before lazy view construction starts.

  method viewControllerDidLoadView*(controller: ViewController) {.optional.}
    ## Runs after the controller has installed its loaded view.

  method viewControllerWillAppear*(controller: ViewController) {.optional.}
    ## Runs before the controller's view becomes visible.

  method viewControllerDidAppear*(controller: ViewController) {.optional.}
    ## Runs after the controller's view becomes visible.

  method viewControllerWillDisappear*(controller: ViewController) {.optional.}
    ## Runs before the controller's visible view is removed or hidden.

  method viewControllerDidDisappear*(controller: ViewController) {.optional.}
    ## Runs after the controller's view is no longer visible.

  method viewControllerDidChangeRepresentedObject*(
    controller: ViewController
  ) {.optional.} ## Runs after `representedObject` changes.

  method viewControllerWillTeardown*(controller: ViewController) {.optional.}
    ## Runs before teardown removes children, view observations, and hosted views.

  method viewControllerDidTeardown*(controller: ViewController) {.optional.}
    ## Runs after teardown has detached controller-owned state.

  method viewControllerDidAddChild*(
    controller: ViewController, child: ViewController
  ) {.optional.} ## Runs after a child controller is added.

  method viewControllerDidRemoveChild*(
    controller: ViewController, child: ViewController
  ) {.optional.} ## Runs after a child controller is removed.

protocol ViewControllerEvents:
  proc willLoadView*(controller: ViewController) {.signal.}
    ## Emitted before lazy view construction starts.

  proc didLoadView*(controller: ViewController, view: View) {.signal.}
    ## Emitted after lazy view construction installs `view`.

  proc willAppear*(controller: ViewController) {.signal.}
    ## Emitted before the controller enters the visible lifecycle state.

  proc didAppear*(controller: ViewController) {.signal.}
    ## Emitted after the controller enters the visible lifecycle state.

  proc willDisappear*(controller: ViewController) {.signal.}
    ## Emitted before the controller leaves the visible lifecycle state.

  proc didDisappear*(controller: ViewController) {.signal.}
    ## Emitted after the controller leaves the visible lifecycle state.

  proc didChangeRepresentedObject*(
    controller: ViewController, representedObject: DynamicAgent
  ) {.signal.} ## Emitted after the controller's represented object changes.

  proc willTeardown*(controller: ViewController) {.signal.}
    ## Emitted before teardown detaches controller-owned state.

  proc didTeardown*(controller: ViewController) {.signal.}
    ## Emitted after teardown detaches controller-owned state.

  proc didAddChildViewController*(
    controller: ViewController, child: ViewController
  ) {.signal.} ## Emitted after `child` is added.

  proc didRemoveChildViewController*(
    controller: ViewController, child: ViewController
  ) {.signal.} ## Emitted after `child` is removed.

proc setView*(controller: ViewController, view: View)
  ## Installs or replaces the controller's owned view.
  ##
  ## The old view is unobserved and has its controller responder link cleared when
  ## appropriate. The new view is observed for hierarchy/window moves so responder
  ## routing can be restored after embedding or reparenting.

proc view*(controller: ViewController): View
  ## Returns the controller view, loading it on first access.

proc viewOrNil*(controller: ViewController): View
  ## Returns the loaded view without triggering lazy loading.

proc parentViewController*(controller: ViewController): ViewController
  ## Returns the controller that owns this controller as a child.

proc installOwnedViewResponder(controller: ViewController)
proc viewWillAppear*(controller: ViewController)
  ## Begins the appear lifecycle transition.
  ##
  ## Delegates and signals run before child controllers receive their matching
  ## `viewWillAppear` calls.

proc viewDidAppear*(controller: ViewController)
  ## Completes the appear lifecycle transition and marks the controller visible.
  ##
  ## Calling this without a preceding `viewWillAppear` implicitly starts the
  ## transition first.

proc viewWillDisappear*(controller: ViewController)
  ## Begins the disappear lifecycle transition for a visible controller.
  ##
  ## Child controllers are notified in reverse containment order.

proc viewDidDisappear*(controller: ViewController)
  ## Completes the disappear lifecycle transition and marks the controller hidden.

proc removeChildViewController*(
  controller: ViewController, child: ViewController
): bool {.discardable.}
  ## Removes a direct child controller.
  ##
  ## Returns true when a child was removed. Visible children receive disappear
  ## lifecycle callbacks around removal.

proc teardown*(controller: ViewController)
  ## Detaches controller-owned state and recursively tears down children.
  ##
  ## Teardown ends the visible lifecycle if needed, removes child controllers,
  ## detaches the owned view from its superview, clears owned responder links, and
  ## removes view lifecycle observations so stale signal observers do not remain.

protocol DefaultViewControllerLoading of ViewControllerLoading:
  method makeView(controller: ViewController): View =
    newView()

protocol ViewControllerUndoManagerProvider of UndoManagerProvider:
  method undoManager(controller: ViewController): Option[UndoManager] =
    if controller.xUndoManager.isNil:
      none(UndoManager)
    else:
      some(controller.xUndoManager)

protocol ViewControllerValidations of UserInterfaceValidations:
  method validateUserInterfaceItem(
      controller: ViewController, args: ValidationArgs
  ): bool =
    args.action.name.len > 0 and controller.respondsTo(args.action.name)

protocol ViewControllerOwnedViewLifecycleSlots of ViewLifecycleProtocol:
  proc ownedViewDidMoveToSuperview(
      controller: ViewController
  ) {.slotFor: viewDidMoveToSuperview.} =
    controller.installOwnedViewResponder()

  proc ownedViewDidMoveToWindow(
      controller: ViewController
  ) {.slotFor: viewDidMoveToWindow.} =
    controller.installOwnedViewResponder()

proc viewControllerForwardingTarget(
    controller: ViewController, selector: SigilName
): DynamicAgent =
  if not controller.xDelegate.isNil and controller.xDelegate.respondsTo(selector):
    return controller.xDelegate
  let next = controller.nextResponder()
  if not next.isNil and next.respondsTo(selector):
    return DynamicAgent(next)

proc installViewControllerForwarding(controller: ViewController) =
  controller.setForwardingTarget(
    proc(self: DynamicAgent, selector: SigilName): DynamicAgent =
      viewControllerForwardingTarget(ViewController(self), selector)
  )

proc sendControllerDelegate(
    controller: ViewController, selector: Selector[ViewController, EmptyArgs]
) =
  if not controller.xDelegate.isNil:
    discard controller.xDelegate.sendLocalIfHandled(selector, controller)

proc sendControllerDelegate(
    controller: ViewController,
    selector: Selector[tuple[controller, child: ViewController], EmptyArgs],
    child: ViewController,
) =
  if not controller.xDelegate.isNil:
    discard controller.xDelegate.sendLocalIfHandled(
      selector, (controller: controller, child: child)
    )

proc notifyDidAddChild(controller, child: ViewController) =
  controller.sendControllerDelegate(viewControllerDidAddChild(), child)
  emit controller.didAddChildViewController(child)

proc notifyDidRemoveChild(controller, child: ViewController) =
  controller.sendControllerDelegate(viewControllerDidRemoveChild(), child)
  emit controller.didRemoveChildViewController(child)

proc installOwnedViewResponder(controller: ViewController) =
  if controller.xView.isNil:
    return
  let next =
    if not controller.xParentViewController.isNil:
      Responder(controller.xParentViewController)
    elif not controller.xView.superview().isNil:
      Responder(controller.xView.superview())
    elif not controller.xView.window().isNil:
      controller.xView.window()
    else:
      controller.nextResponder()
  if controller.xView.nextResponder() != Responder(controller):
    controller.xView.setNextResponder(controller)
  if not next.isNil and next != Responder(controller) and
      controller.nextResponder() != next:
    controller.setNextResponder(next)

proc unobserveOwnedView(controller: ViewController, view: View) =
  if view.isNil:
    return
  controller.unobserveProtocol(view, ViewControllerOwnedViewLifecycleSlots)

proc observeOwnedView(controller: ViewController, view: View) =
  if view.isNil:
    return
  controller.observeProtocol(view, ViewControllerOwnedViewLifecycleSlots)

proc initViewController*(controller: ViewController, view: View = nil) =
  ## Initializes a view controller and optionally installs an already-built view.
  ##
  ## Subclasses should call this during construction. The initializer installs
  ## default view loading, undo lookup, command validation, and delegate
  ## forwarding behavior.
  initResponder(controller)
  discard controller.withProtocol(DefaultViewControllerLoading)
  discard controller.withProtocol(ViewControllerUndoManagerProvider)
  discard controller.withProtocol(ViewControllerValidations)
  controller.installViewControllerForwarding()
  if not view.isNil:
    controller.setView(view)

proc newViewController*(view: View = nil): ViewController =
  ## Creates a basic view controller.
  ##
  ## Pass `view` to wrap an existing view, or omit it to load a default view on
  ## demand.
  result = ViewController()
  result.initViewController(view)

proc delegate*(controller: ViewController): DynamicAgent =
  ## Returns the controller delegate.
  ##
  ## Delegates receive optional lifecycle and containment callbacks and can also
  ## act as selector forwarding targets.
  controller.xDelegate

proc `delegate=`*(controller: ViewController, delegate: DynamicAgent) =
  ## Sets the controller delegate.
  controller.xDelegate = delegate

proc `delegate=`*(controller: ViewController, delegate: Responder) =
  ## Sets a responder delegate by wrapping it as a dynamic agent.
  controller.delegate = DynamicAgent(delegate)

proc representedObject*(controller: ViewController): DynamicAgent =
  ## Returns the model object represented by this controller.
  ##
  ## Window and document controller integration use this to route document-backed
  ## content without forcing a specific model type.
  controller.xRepresentedObject

proc setRepresentedObject*(
    controller: ViewController, representedObject: DynamicAgent
) =
  ## Updates the represented object and publishes the change.
  ##
  ## A changed object notifies the delegate and emits `didChangeRepresentedObject`.
  ## Reassigning the same object is ignored.
  if controller.xRepresentedObject == representedObject:
    return
  controller.xRepresentedObject = representedObject
  controller.sendControllerDelegate(viewControllerDidChangeRepresentedObject())
  emit controller.didChangeRepresentedObject(representedObject)

proc `representedObject=`*(
    controller: ViewController, representedObject: DynamicAgent
) =
  ## Assignment form of `setRepresentedObject`.
  controller.setRepresentedObject(representedObject)

proc undoManagerFor*(controller: ViewController): UndoManager =
  ## Returns the controller-local undo manager, creating one on first use.
  ##
  ## The controller also implements undo-manager lookup for responder-chain users.
  if controller.xUndoManager.isNil:
    controller.xUndoManager = newUndoManager()
  controller.xUndoManager

proc setUndoManager*(controller: ViewController, undoManager: UndoManager) =
  ## Replaces the controller-local undo manager.
  controller.xUndoManager = undoManager

proc `undoManager=`*(controller: ViewController, undoManager: UndoManager) =
  ## Assignment form of `setUndoManager`.
  controller.setUndoManager(undoManager)

proc isViewLoaded*(controller: ViewController): bool =
  ## Returns true when the controller currently has an installed view.
  not controller.xView.isNil

proc isViewVisible*(controller: ViewController): bool =
  ## Returns true while the controller is in the appeared lifecycle state.
  controller.xViewVisible

proc viewOrNil*(controller: ViewController): View =
  controller.xView

proc setView*(controller: ViewController, view: View) =
  if controller.xView == view:
    return
  let oldView = controller.xView
  if not oldView.isNil:
    controller.unobserveOwnedView(oldView)
    if oldView.nextResponder() == Responder(controller):
      oldView.clearNextResponder()
  controller.xView = view
  if not view.isNil:
    controller.observeOwnedView(view)
    controller.installOwnedViewResponder()

proc `view=`*(controller: ViewController, view: View) =
  ## Assignment form of `setView`.
  controller.setView(view)

proc loadView*(controller: ViewController): View =
  ## Loads and installs the controller view if needed.
  ##
  ## Loading notifies the delegate and signals before and after construction. If a
  ## `makeView` implementation is present it is used; otherwise a plain `newView`
  ## is installed.
  if not controller.xView.isNil:
    return controller.xView
  controller.sendControllerDelegate(viewControllerWillLoadView())
  emit controller.willLoadView()
  result = controller.trySendLocal(makeView(), ()).get(nil)
  if result.isNil:
    result = newView()
  controller.setView(result)
  controller.sendControllerDelegate(viewControllerDidLoadView())
  emit controller.didLoadView(result)

proc view*(controller: ViewController): View =
  if controller.xView.isNil:
    discard controller.loadView()
  controller.xView

proc parentViewController*(controller: ViewController): ViewController =
  controller.xParentViewController

proc childViewControllers*(controller: ViewController): lent seq[ViewController] =
  ## Returns the controller's child-controller list.
  ##
  ## The borrowed sequence is for inspection; mutate containment through
  ## `addChildViewController`, `insertChildViewController`, or
  ## `removeChildViewController`.
  controller.xChildViewControllers

proc childViewControllerCount*(controller: ViewController): int =
  ## Returns the number of child view controllers.
  controller.xChildViewControllers.len

proc contains*(controller: ViewController, child: ViewController): bool =
  ## Returns true when `child` is directly contained by `controller`.
  child in controller.xChildViewControllers

proc addChildViewController*(controller, child: ViewController) =
  ## Adds `child` as the last child controller.
  ##
  ## A child is removed from any previous parent first. If the parent is currently
  ## visible, the child receives matching appear callbacks around the containment
  ## change.
  if controller.isNil or child == controller:
    return
  if child.xParentViewController == controller:
    return
  if not child.xParentViewController.isNil:
    discard child.xParentViewController.removeChildViewController(child)
  if controller.xViewVisible:
    child.viewWillAppear()
  child.xParentViewController = controller
  controller.xChildViewControllers.add child
  child.installOwnedViewResponder()
  controller.notifyDidAddChild(child)
  if controller.xViewVisible:
    child.viewDidAppear()

proc insertChildViewController*(controller, child: ViewController, index: Natural) =
  ## Inserts `child` at `index`, clamping the index to the current child count.
  ##
  ## Re-inserting an existing child of the same parent reorders it without sending
  ## containment notifications.
  if controller.isNil or child == controller:
    return
  if child.xParentViewController == controller:
    let current = controller.xChildViewControllers.find(child)
    if current >= 0:
      controller.xChildViewControllers.delete(current)
      controller.xChildViewControllers.insert(
        child, min(index.int, controller.xChildViewControllers.len)
      )
    return
  if not child.xParentViewController.isNil:
    discard child.xParentViewController.removeChildViewController(child)
  if controller.xViewVisible:
    child.viewWillAppear()
  child.xParentViewController = controller
  controller.xChildViewControllers.insert(
    child, min(index.int, controller.xChildViewControllers.len)
  )
  child.installOwnedViewResponder()
  controller.notifyDidAddChild(child)
  if controller.xViewVisible:
    child.viewDidAppear()

proc embedChildViewController*(
    controller, child: ViewController, container: View = nil
): View {.discardable.} =
  ## Adds `child` and places the child's view in a container view.
  ##
  ## When `container` is nil, the parent controller's own view is used as the host.
  ## The child view is loaded as needed and returned.
  if controller.isNil:
    return nil
  controller.addChildViewController(child)
  let host =
    if container.isNil:
      controller.view()
    else:
      container
  result = child.view()
  if not host.isNil and not result.isNil and result.superview() != host:
    host.addSubview(result)
    child.installOwnedViewResponder()

proc removeChildViewController*(
    controller: ViewController, child: ViewController
): bool {.discardable.} =
  if child.isNil:
    return false
  let index = controller.xChildViewControllers.find(child)
  if index < 0:
    return false
  if child.xViewVisible:
    child.viewWillDisappear()
  controller.xChildViewControllers.delete(index)
  child.xParentViewController = nil
  if child.nextResponder() == Responder(controller):
    child.clearNextResponder()
  if not child.xView.isNil:
    child.installOwnedViewResponder()
  controller.notifyDidRemoveChild(child)
  if child.xViewVisible:
    child.viewDidDisappear()
  true

proc removeFromParentViewController*(controller: ViewController): bool {.discardable.} =
  ## Removes this controller from its parent, if it has one.
  if controller.xParentViewController.isNil:
    return false
  controller.xParentViewController.removeChildViewController(controller)

proc viewWillAppear*(controller: ViewController) =
  if controller.xViewVisible or controller.xAppearing:
    return
  controller.xAppearing = true
  controller.sendControllerDelegate(viewControllerWillAppear())
  emit controller.willAppear()
  for child in controller.xChildViewControllers:
    child.viewWillAppear()

proc viewDidAppear*(controller: ViewController) =
  if controller.xViewVisible:
    return
  if not controller.xAppearing:
    controller.viewWillAppear()
  for child in controller.xChildViewControllers:
    child.viewDidAppear()
  controller.xAppearing = false
  controller.xViewVisible = true
  controller.sendControllerDelegate(viewControllerDidAppear())
  emit controller.didAppear()

proc viewWillDisappear*(controller: ViewController) =
  if (not controller.xViewVisible) or controller.xDisappearing:
    return
  controller.xDisappearing = true
  controller.sendControllerDelegate(viewControllerWillDisappear())
  emit controller.willDisappear()
  for index in countdown(controller.xChildViewControllers.high, 0):
    controller.xChildViewControllers[index].viewWillDisappear()

proc viewDidDisappear*(controller: ViewController) =
  if ((not controller.xViewVisible) and not controller.xDisappearing):
    return
  for index in countdown(controller.xChildViewControllers.high, 0):
    controller.xChildViewControllers[index].viewDidDisappear()
  controller.xDisappearing = false
  controller.xViewVisible = false
  controller.sendControllerDelegate(viewControllerDidDisappear())
  emit controller.didDisappear()

proc teardown*(controller: ViewController) =
  if controller.xTearingDown:
    return
  controller.xTearingDown = true
  if controller.xViewVisible:
    controller.viewWillDisappear()
    controller.viewDidDisappear()
  controller.sendControllerDelegate(viewControllerWillTeardown())
  emit controller.willTeardown()
  while controller.xChildViewControllers.len > 0:
    let child = controller.xChildViewControllers[^1]
    discard controller.removeChildViewController(child)
    child.teardown()
  if not controller.xParentViewController.isNil:
    discard controller.xParentViewController.removeChildViewController(controller)
  if not controller.xView.isNil:
    let oldView = controller.xView
    controller.unobserveOwnedView(oldView)
    if not oldView.superview().isNil:
      oldView.removeFromSuperview()
    if oldView.nextResponder() == Responder(controller):
      oldView.clearNextResponder()
    controller.xView = nil
  controller.sendControllerDelegate(viewControllerDidTeardown())
  emit controller.didTeardown()
  controller.xTearingDown = false
