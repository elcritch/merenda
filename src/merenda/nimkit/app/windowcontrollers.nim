import std/options

import sigils/core

import ../foundation/selectors
import ../responder/responders
import ./application
import ./viewcontrollers
import ./windows

type WindowController* = ref object of Responder
  xWindow: Window
  xViewController: ViewController
  xForwardedWindowDelegate: DynamicAgent
  xForwardedNextResponder: Responder
  xDelegate: DynamicAgent
  xDocumentDisplayName: string
  xWindowTitle: string
  xHasWindowTitle: bool

protocol WindowControllerLoading {.selectorScope: protocol.}:
  method makeWindow*(): Window {.optional.}
  method titleForDisplayName*(displayName: string): string {.optional.}

protocol WindowControllerDelegate:
  method controllerWillLoad*(controller: WindowController) {.optional.}
  method controllerDidLoad*(controller: WindowController) {.optional.}
  method controllerWillShow*(controller: WindowController) {.optional.}
  method controllerDidShow*(controller: WindowController) {.optional.}
  method controllerShouldClose*(controller: WindowController): bool {.optional.}
  method controllerWillClose*(controller: WindowController) {.optional.}
  method controllerDidClose*(controller: WindowController) {.optional.}
  method controllerDidSyncTitle*(controller: WindowController) {.optional.}

protocol WindowControllerEvents:
  proc willLoadWindow*(controller: WindowController) {.signal.}
  proc didLoadWindow*(controller: WindowController, window: Window) {.signal.}
  proc willShowWindow*(controller: WindowController, window: Window) {.signal.}
  proc didShowWindow*(controller: WindowController, window: Window) {.signal.}
  proc willCloseWindow*(controller: WindowController, window: Window) {.signal.}
  proc didCloseWindow*(controller: WindowController, window: Window) {.signal.}
  proc didSyncWindowTitle*(controller: WindowController, title: string) {.signal.}

proc setWindow*(controller: WindowController, window: Window)
proc setViewController*(controller: WindowController, viewController: ViewController)
proc synchronizeWindowTitle*(controller: WindowController)

protocol DefaultWindowControllerLoading of WindowControllerLoading:
  method makeWindow(controller: WindowController): Window =
    newWindow()

  method titleForDisplayName(
      controller: WindowController, displayName: string
  ): string =
    displayName

proc windowControllerForwardingTarget(
    controller: WindowController, selector: SigilName
): DynamicAgent =
  if not controller.xDelegate.isNil and controller.xDelegate.respondsTo(selector):
    return controller.xDelegate
  let next = controller.nextResponder()
  if not next.isNil and next.respondsTo(selector):
    return DynamicAgent(next)

proc installWindowControllerForwarding(controller: WindowController) =
  controller.setForwardingTarget(
    proc(self: DynamicAgent, selector: SigilName): DynamicAgent =
      windowControllerForwardingTarget(WindowController(self), selector)
  )

proc sendControllerDelegate(
    controller: WindowController, selector: Selector[WindowController, EmptyArgs]
) =
  if not controller.isNil and not controller.xDelegate.isNil:
    discard controller.xDelegate.sendLocalIfHandled(selector, controller)

proc notifyWillLoadWindow(controller: WindowController) =
  controller.sendControllerDelegate(controllerWillLoad())
  emit controller.willLoadWindow()

proc notifyDidLoadWindow(controller: WindowController, window: Window) =
  controller.sendControllerDelegate(controllerDidLoad())
  emit controller.didLoadWindow(window)

proc notifyWillShowWindow(controller: WindowController, window: Window) =
  controller.sendControllerDelegate(controllerWillShow())
  emit controller.willShowWindow(window)

proc notifyDidShowWindow(controller: WindowController, window: Window) =
  controller.sendControllerDelegate(controllerDidShow())
  emit controller.didShowWindow(window)

proc notifyWillCloseWindow(controller: WindowController, window: Window) =
  controller.sendControllerDelegate(controllerWillClose())
  emit controller.willCloseWindow(window)

proc notifyDidCloseWindow(controller: WindowController, window: Window) =
  controller.sendControllerDelegate(controllerDidClose())
  emit controller.didCloseWindow(window)

proc notifyDidSynchronizeWindowTitle(controller: WindowController, title: string) =
  controller.sendControllerDelegate(controllerDidSyncTitle())
  emit controller.didSyncWindowTitle(title)

proc setViewControllerVisible(controller: WindowController, visible: bool) =
  if controller.isNil or controller.xViewController.isNil:
    return
  if visible:
    if not controller.xViewController.isViewVisible():
      controller.xViewController.viewWillAppear()
      controller.xViewController.viewDidAppear()
  elif controller.xViewController.isViewVisible():
    controller.xViewController.viewWillDisappear()
    controller.xViewController.viewDidDisappear()

proc installViewControllerContent(controller: WindowController) =
  if controller.isNil or controller.xWindow.isNil or controller.xViewController.isNil:
    return
  let view = controller.xViewController.view()
  if controller.xWindow.contentView() != view:
    controller.xWindow.setContentView(view)
  if not view.isNil:
    view.setNextResponder(controller.xViewController)
  controller.xViewController.setNextResponder(controller.xWindow)

proc controllerShouldCloseWindow(controller: WindowController): bool =
  if controller.isNil or controller.xDelegate.isNil:
    return true
  controller.xDelegate.trySendLocal(controllerShouldClose(), controller).get(true)

proc forwardedWindowShouldClose(controller: WindowController, window: Window): bool =
  if controller.isNil or controller.xForwardedWindowDelegate.isNil:
    return true
  controller.xForwardedWindowDelegate.trySendLocal(windowShouldClose(), window).get(
    true
  )

proc forwardWindowDelegate(
    controller: WindowController, selector: Selector[Window, EmptyArgs], window: Window
) =
  if not controller.isNil and not controller.xForwardedWindowDelegate.isNil:
    discard controller.xForwardedWindowDelegate.sendLocalIfHandled(selector, window)

protocol WindowControllerWindowDelegateBridge of WindowDelegateProtocol:
  method windowShouldClose(controller: WindowController, window: Window): bool =
    controller.forwardedWindowShouldClose(window) and
      controller.controllerShouldCloseWindow()

  method windowWillClose(controller: WindowController, window: Window) =
    controller.forwardWindowDelegate(windowWillClose(), window)
    if not controller.xViewController.isNil:
      controller.xViewController.viewWillDisappear()
    controller.notifyWillCloseWindow(window)

  method windowDidClose(controller: WindowController, window: Window) =
    controller.forwardWindowDelegate(windowDidClose(), window)
    if not controller.xViewController.isNil:
      controller.xViewController.viewDidDisappear()
    controller.notifyDidCloseWindow(window)

  method windowDidBecomeKey(controller: WindowController, window: Window) =
    controller.forwardWindowDelegate(windowDidBecomeKey(), window)

  method windowDidResignKey(controller: WindowController, window: Window) =
    controller.forwardWindowDelegate(windowDidResignKey(), window)

  method windowDidBecomeMain(controller: WindowController, window: Window) =
    controller.forwardWindowDelegate(windowDidBecomeMain(), window)

  method windowDidResignMain(controller: WindowController, window: Window) =
    controller.forwardWindowDelegate(windowDidResignMain(), window)

  method windowWillBeginSheet(controller: WindowController, sheet: Window) =
    controller.forwardWindowDelegate(windowWillBeginSheet(), sheet)

  method windowDidEndSheet(controller: WindowController, sheet: Window) =
    controller.forwardWindowDelegate(windowDidEndSheet(), sheet)

proc detachWindow(controller: WindowController) =
  let window = controller.xWindow
  if window.isNil:
    return
  if window.delegate() == DynamicAgent(controller):
    window.delegate = controller.xForwardedWindowDelegate
  if window.nextResponder() == Responder(controller):
    if controller.xForwardedNextResponder.isNil:
      window.clearNextResponder()
    else:
      window.setNextResponder(controller.xForwardedNextResponder)
  controller.xForwardedWindowDelegate = nil
  controller.xForwardedNextResponder = nil

proc attachWindow(controller: WindowController, window: Window) =
  if controller.isNil or window.isNil:
    return
  let existingDelegate = window.delegate()
  if existingDelegate != DynamicAgent(controller):
    controller.xForwardedWindowDelegate = existingDelegate
  let existingNextResponder = window.nextResponder()
  if existingNextResponder != Responder(controller):
    controller.xForwardedNextResponder = existingNextResponder
    if controller.nextResponder().isNil and not existingNextResponder.isNil:
      controller.setNextResponder(existingNextResponder)
  window.delegate = DynamicAgent(controller)
  window.setNextResponder(controller)

proc computedWindowTitle(controller: WindowController): string =
  if controller.isNil:
    return ""
  if controller.xHasWindowTitle:
    return controller.xWindowTitle
  if controller.xDocumentDisplayName.len > 0:
    return controller
      .trySendLocal(titleForDisplayName(), controller.xDocumentDisplayName)
      .get(controller.xDocumentDisplayName)
  if not controller.xWindow.isNil:
    return controller.xWindow.title()
  "Window"

proc initWindowController*(controller: WindowController, window: Window = nil) =
  if controller.isNil:
    return
  initResponder(controller)
  discard controller.withProtocol(DefaultWindowControllerLoading)
  discard controller.withProtocol(WindowControllerWindowDelegateBridge)
  controller.installWindowControllerForwarding()
  if not window.isNil:
    controller.setWindow(window)

proc newWindowController*(window: Window = nil): WindowController =
  result = WindowController()
  result.initWindowController(window)

proc delegate*(controller: WindowController): DynamicAgent =
  if controller.isNil: nil else: controller.xDelegate

proc `delegate=`*(controller: WindowController, delegate: DynamicAgent) =
  if not controller.isNil:
    controller.xDelegate = delegate

proc `delegate=`*(controller: WindowController, delegate: Responder) =
  controller.delegate = DynamicAgent(delegate)

proc isWindowLoaded*(controller: WindowController): bool =
  (not controller.isNil) and not controller.xWindow.isNil

proc windowOrNil*(controller: WindowController): Window =
  if controller.isNil: nil else: controller.xWindow

proc viewController*(controller: WindowController): ViewController =
  if controller.isNil: nil else: controller.xViewController

proc contentViewController*(controller: WindowController): ViewController =
  controller.viewController()

proc setWindow*(controller: WindowController, window: Window) =
  if controller.isNil or controller.xWindow == window:
    return
  let oldWindow = controller.xWindow
  if not oldWindow.isNil and not controller.xViewController.isNil:
    if controller.xViewController.isViewVisible():
      controller.xViewController.viewWillDisappear()
      controller.xViewController.viewDidDisappear()
    let view = controller.xViewController.viewOrNil()
    if not view.isNil and oldWindow.contentView() == view:
      oldWindow.setContentView(nil)
  controller.detachWindow()
  controller.xWindow = window
  if not window.isNil:
    controller.attachWindow(window)
    controller.synchronizeWindowTitle()
    controller.installViewControllerContent()
    if window.isVisible():
      controller.setViewControllerVisible(true)

proc `window=`*(controller: WindowController, window: Window) =
  controller.setWindow(window)

proc setViewController*(controller: WindowController, viewController: ViewController) =
  if controller.isNil or controller.xViewController == viewController:
    return
  let oldController = controller.xViewController
  if not oldController.isNil:
    if oldController.isViewVisible():
      oldController.viewWillDisappear()
      oldController.viewDidDisappear()
    let oldView = oldController.viewOrNil()
    if not controller.xWindow.isNil and not oldView.isNil and
        controller.xWindow.contentView() == oldView:
      controller.xWindow.setContentView(nil)
    if oldController.nextResponder() == Responder(controller.xWindow) or
        oldController.nextResponder() == Responder(controller):
      oldController.clearNextResponder()
  controller.xViewController = viewController
  if not viewController.isNil:
    if controller.xWindow.isNil:
      viewController.setNextResponder(controller)
    else:
      controller.installViewControllerContent()
      if controller.xWindow.isVisible():
        controller.setViewControllerVisible(true)

proc `viewController=`*(controller: WindowController, viewController: ViewController) =
  controller.setViewController(viewController)

proc `contentViewController=`*(
    controller: WindowController, viewController: ViewController
) =
  controller.setViewController(viewController)

proc documentDisplayName*(controller: WindowController): string =
  if controller.isNil: "" else: controller.xDocumentDisplayName

proc setDocumentDisplayName*(controller: WindowController, displayName: string) =
  if controller.isNil or controller.xDocumentDisplayName == displayName:
    return
  controller.xDocumentDisplayName = displayName
  if not controller.xHasWindowTitle:
    controller.synchronizeWindowTitle()

proc `documentDisplayName=`*(controller: WindowController, displayName: string) =
  controller.setDocumentDisplayName(displayName)

proc windowTitle*(controller: WindowController): string =
  controller.computedWindowTitle()

proc setWindowTitle*(controller: WindowController, title: string) =
  if controller.isNil:
    return
  if controller.xHasWindowTitle and controller.xWindowTitle == title:
    return
  controller.xHasWindowTitle = true
  controller.xWindowTitle = title
  controller.synchronizeWindowTitle()

proc `windowTitle=`*(controller: WindowController, title: string) =
  controller.setWindowTitle(title)

proc clearWindowTitle*(controller: WindowController) =
  if controller.isNil or not controller.xHasWindowTitle:
    return
  controller.xHasWindowTitle = false
  controller.xWindowTitle = ""
  controller.synchronizeWindowTitle()

proc synchronizeWindowTitle*(controller: WindowController) =
  if controller.isNil or controller.xWindow.isNil:
    return
  let title = controller.computedWindowTitle()
  if controller.xWindow.title() == title:
    return
  controller.xWindow.setTitle(title)
  controller.notifyDidSynchronizeWindowTitle(title)

proc loadWindow*(controller: WindowController): Window =
  if controller.isNil:
    return nil
  if not controller.xWindow.isNil:
    return controller.xWindow
  controller.notifyWillLoadWindow()
  result = controller.trySendLocal(makeWindow(), ()).get(nil)
  if result.isNil:
    result = newWindow()
  controller.setWindow(result)
  controller.notifyDidLoadWindow(result)

proc controlledWindow*(controller: WindowController): Window =
  if controller.isNil:
    return nil
  if controller.xWindow.isNil:
    discard controller.loadWindow()
  controller.xWindow

proc showWindow*(
    controller: WindowController, sender: DynamicAgent = nil
): Window {.discardable.} =
  result = controller.controlledWindow()
  if result.isNil:
    return nil
  controller.installViewControllerContent()
  let shouldAppear =
    not controller.xViewController.isNil and
    not controller.xViewController.isViewVisible()
  controller.notifyWillShowWindow(result)
  if shouldAppear:
    controller.xViewController.viewWillAppear()
  result.makeKeyAndOrderFront()
  if shouldAppear:
    controller.xViewController.viewDidAppear()
  controller.notifyDidShowWindow(result)

proc showWindow*(
    controller: WindowController, app: Application, sender: DynamicAgent = nil
): Window {.discardable.} =
  result = controller.controlledWindow()
  if result.isNil:
    return nil
  controller.installViewControllerContent()
  let shouldAppear =
    not controller.xViewController.isNil and
    not controller.xViewController.isViewVisible()
  if not app.isNil:
    app.addWindow(result)
    let forwardedNextResponder = result.nextResponder()
    if forwardedNextResponder != Responder(controller):
      controller.xForwardedNextResponder = forwardedNextResponder
    controller.setNextResponder(app)
    result.setNextResponder(controller)
  controller.notifyWillShowWindow(result)
  if shouldAppear:
    controller.xViewController.viewWillAppear()
  if app.isNil:
    result.makeKeyAndOrderFront()
  else:
    app.activateWindow(result)
  if shouldAppear:
    controller.xViewController.viewDidAppear()
  controller.notifyDidShowWindow(result)

proc close*(controller: WindowController): bool {.discardable.} =
  if controller.isNil or controller.xWindow.isNil:
    return true
  controller.xWindow.close()
  controller.xWindow.isClosed()
