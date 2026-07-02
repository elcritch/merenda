import std/[options, unittest]

import sigils/core

import merenda/nimkit

type
  LoadingViewController = ref object of ViewController
  CommandViewController = ref object of ViewController
  ViewControllerDelegateSpy = ref object of Responder
  ViewControllerSignalSpy = ref object of Agent

var
  lifecycleEvents: seq[string]
  signalEvents: seq[string]
  commandEvents: seq[string]

protocol LoadingViewControllerProtocol of ViewControllerLoading:
  method makeView(controller: LoadingViewController): View =
    lifecycleEvents.add "makeView"
    newView("loaded", frame = initRect(0, 0, 120, 80))

protocol CommandViewControllerProtocol of MenuCommandProtocol:
  method complete(controller: CommandViewController, args: ActionArgs) =
    commandEvents.add "complete"

protocol ViewControllerDelegateSpyProtocol of ViewControllerDelegate:
  method viewControllerWillLoadView(
      delegate: ViewControllerDelegateSpy, controller: ViewController
  ) =
    lifecycleEvents.add "willLoad"

  method viewControllerDidLoadView(
      delegate: ViewControllerDelegateSpy, controller: ViewController
  ) =
    lifecycleEvents.add "didLoad"

  method viewControllerWillAppear(
      delegate: ViewControllerDelegateSpy, controller: ViewController
  ) =
    lifecycleEvents.add "willAppear"

  method viewControllerDidAppear(
      delegate: ViewControllerDelegateSpy, controller: ViewController
  ) =
    lifecycleEvents.add "didAppear"

  method viewControllerWillDisappear(
      delegate: ViewControllerDelegateSpy, controller: ViewController
  ) =
    lifecycleEvents.add "willDisappear"

  method viewControllerDidDisappear(
      delegate: ViewControllerDelegateSpy, controller: ViewController
  ) =
    lifecycleEvents.add "didDisappear"

  method viewControllerDidChangeRepresentedObject(
      delegate: ViewControllerDelegateSpy, controller: ViewController
  ) =
    lifecycleEvents.add "represented"

  method viewControllerWillTeardown(
      delegate: ViewControllerDelegateSpy, controller: ViewController
  ) =
    lifecycleEvents.add "willTeardown"

  method viewControllerDidTeardown(
      delegate: ViewControllerDelegateSpy, controller: ViewController
  ) =
    lifecycleEvents.add "didTeardown"

  method viewControllerDidAddChild(
      delegate: ViewControllerDelegateSpy,
      controller: ViewController,
      child: ViewController,
  ) =
    lifecycleEvents.add "addChild"

  method viewControllerDidRemoveChild(
      delegate: ViewControllerDelegateSpy,
      controller: ViewController,
      child: ViewController,
  ) =
    lifecycleEvents.add "removeChild"

proc rememberWillLoad(spy: ViewControllerSignalSpy) {.slot.} =
  signalEvents.add "willLoad"

proc rememberDidLoad(spy: ViewControllerSignalSpy, view: View) {.slot.} =
  signalEvents.add "didLoad:" & view.name

proc rememberRepresented(
    spy: ViewControllerSignalSpy, representedObject: DynamicAgent
) {.slot.} =
  if representedObject.isNil:
    signalEvents.add "represented:nil"
  else:
    signalEvents.add "represented"

suite "nimkit view controllers":
  test "view controller loads views lazily and publishes lifecycle state":
    let
      controller = LoadingViewController()
      delegate = ViewControllerDelegateSpy()
      signalSpy = ViewControllerSignalSpy()
      represented = newResponder()

    lifecycleEvents = @[]
    signalEvents = @[]
    controller.initViewController()
    discard controller.withProtocol(LoadingViewControllerProtocol)
    discard delegate.withProtocol(ViewControllerDelegateSpyProtocol)
    controller.delegate = delegate
    controller.connect(willLoadView, signalSpy, rememberWillLoad)
    controller.connect(didLoadView, signalSpy, rememberDidLoad)
    controller.connect(didChangeRepresentedObject, signalSpy, rememberRepresented)

    check not controller.isViewLoaded
    let view = controller.view()
    check controller.isViewLoaded
    check view.name == "loaded"
    check view.nextResponder() == Responder(controller)
    check lifecycleEvents == @["willLoad", "makeView", "didLoad"]
    check signalEvents == @["willLoad", "didLoad:loaded"]

    controller.representedObject = DynamicAgent(represented)
    check controller.representedObject() == DynamicAgent(represented)
    check lifecycleEvents[^1] == "represented"
    check signalEvents[^1] == "represented"

  test "child containment restores responder routing and tears down owned views":
    let
      parent = newViewController(newView("parent", frame = initRect(0, 0, 200, 120)))
      child = newViewController(newView("child", frame = initRect(0, 0, 80, 40)))
      delegate = ViewControllerDelegateSpy()

    lifecycleEvents = @[]
    discard delegate.withProtocol(ViewControllerDelegateSpyProtocol)
    parent.delegate = delegate

    let childView = parent.embedChildViewController(child)
    check parent.childViewControllerCount == 1
    check parent.childViewControllers()[0] == child
    check parent.contains(child)
    check child.parentViewController() == parent
    check childView.superview() == parent.view()
    check childView.nextResponder() == Responder(child)
    check child.nextResponder() == Responder(parent)
    check "addChild" in lifecycleEvents

    parent.viewWillAppear()
    parent.viewDidAppear()
    check parent.isViewVisible
    check child.isViewVisible

    parent.teardown()
    check parent.viewOrNil().isNil
    check child.viewOrNil().isNil
    check child.parentViewController().isNil
    check parent.childViewControllerCount == 0
    check "willTeardown" in lifecycleEvents
    check "didTeardown" in lifecycleEvents

  test "window controllers install swap and detach content view controllers":
    let
      app = newApplication()
      window = newWindow("Content", frame = initRect(0, 0, 240, 160))
      controller = newWindowController(window)
      first = CommandViewController()
      second = newViewController(newView("second", frame = initRect(0, 0, 160, 100)))
      manager = newUndoManager()

    lifecycleEvents = @[]
    commandEvents = @[]
    first.initViewController(newView("first", frame = initRect(0, 0, 160, 100)))
    discard first.withProtocol(CommandViewControllerProtocol)
    first.undoManager = manager
    controller.viewController = first

    check controller.viewController() == first
    check controller.contentViewController() == first
    check window.contentView() == first.view()
    check first.view().nextResponder() == Responder(first)
    check first.nextResponder() == Responder(window)
    check first.view().findUndoManager() == manager

    let validation = first.trySendLocal(
      validateUserInterfaceItem(), ValidationArgs(item: nil, action: complete())
    )
    check validation.isSome and validation.get()
    first.view().doCommandBySelector(complete(), DynamicAgent(first.view()))
    check commandEvents == @["complete"]

    discard controller.showWindow(app)
    check first.isViewVisible

    controller.viewController = second
    check not first.isViewVisible
    check second.isViewVisible
    check window.contentView() == second.view()
    check second.view().nextResponder() == Responder(second)
    check second.nextResponder() == Responder(window)

    window.close()
    check not second.isViewVisible
    check commandEvents == @["complete"]

  test "document-owned window controllers seed represented object and responder chain":
    let
      app = newApplication()
      document = newDocument("file:///tmp/Doc.txt")
      content = newViewController(newView("document-content"))
      controller = newWindowController()

    controller.viewController = content
    document.addWindowController(controller)
    check content.representedObject() == DynamicAgent(document)

    let windows = document.showWindows(app)
    check windows.len == 1
    check windows[0].contentView() == content.view()
    check content.view().nextResponder() == Responder(content)
    check content.nextResponder() == Responder(windows[0])
    check windows[0].nextResponder() == Responder(controller)
    check controller.nextResponder() == Responder(document)
    check document.nextResponder() == Responder(app)

  test "panel accessory views can be backed by reusable view controllers":
    let
      alert = newAlert("Accessory")
      accessory = newViewController(View(newStatusLabel("Controller content")))

    alert.setAccessoryView(accessory.view())
    discard alert.contentView()

    check accessory.isViewLoaded
    check not accessory.view().superview().isNil
    check accessory.view().nextResponder() == Responder(accessory)

    let oldView = accessory.view()
    accessory.teardown()
    check accessory.viewOrNil().isNil
    check oldView.superview().isNil
