import std/[options, os]

import sigils/selectors

import ../foundation/events
import ../controls/menus
import ../responder/responders
import ../foundation/selectors as nimkitSelectors
import ../drawing/theme
import ../foundation/types
import ../app/windows

type
  ModalSessionState* = enum
    mssRunning
    mssStopped
    mssAborted

  ModalSessionMode* = enum
    msmApplicationModal
    msmWindowModal

  ModalSession* = ref object
    window*: Window
    parentWindow*: Window
    previousKeyWindow*: Window
    previousMainWindow*: Window
    mode*: ModalSessionMode
    state*: ModalSessionState
    response*: int

  Application* = ref object of Responder
    xWindows: seq[Window]
    xOrderedWindows: seq[Window]
    xDelegate: DynamicAgent
    xAppearance: Appearance
    xHasAppearance: bool
    xCurrentEvent: KeyEvent
    xHasCurrentEvent: bool
    xKeyWindow: Window
    xMainWindow: Window
    xMainMenu: Menu
    xWindowsMenu: Menu
    xRunning: bool
    xActive: bool
    xHidden: bool
    xHiddenWindows: seq[Window]
    xLaunched: bool
    xTerminating: bool
    xModalSessions: seq[ModalSession]

const WindowDidOrderFrontSelector = "_nimkitWindowDidOrderFront"
const WindowDidOrderBackSelector = "_nimkitWindowDidOrderBack"
const WindowDidOrderOutSelector = "_nimkitWindowDidOrderOut"
const WindowDidCloseSelector = "_nimkitWindowDidClose"

var sharedApplicationInstance: Application

proc hide*(app: Application)
proc terminate*(app: Application): TerminationReply {.discardable.}
proc stop*(app: Application)
proc addWindow*(app: Application, window: Window)
proc activateWindow*(app: Application, window: Window)
proc updateWindowsMenu*(app: Application)
proc modalSession*(app: Application): ModalSession
proc performMenuKeyEquivalent*(app: Application, event: KeyEvent): bool
proc runForFrames*(app: Application, frames: Natural): int
proc setKeyWindow*(app: Application, window: Window)
proc setMainWindow*(app: Application, window: Window)
proc noteWindowOrderedFront(app: Application, window: Window)
proc noteWindowOrderedBack(app: Application, window: Window)
proc noteWindowOrderedOut(app: Application, window: Window)
proc noteWindowClosed(app: Application, window: Window)

proc orderFrontWindowAction*(): ActionSelector =
  actionSelector("orderFrontWindow")

proc installApplicationCommandMethods(app: Application) =
  let hideMethod: DynamicMethod = proc(self: DynamicAgent, invocation: var Invocation) =
    Application(self).hide()
    invocation.setResult(())
  discard app.replaceMethod(actionSelector("hide"), hideMethod)

  let terminateMethod: DynamicMethod = proc(
      self: DynamicAgent, invocation: var Invocation
  ) =
    discard Application(self).terminate()
    invocation.setResult(())
  discard app.replaceMethod(actionSelector("terminate"), terminateMethod)

  let orderFrontWindowMethod: DynamicMethod = proc(
      self: DynamicAgent, invocation: var Invocation
  ) =
    let args = invocation.argsAs(ActionArgs)
    if not args.sender.isNil and args.sender of MenuItem:
      let represented = MenuItem(args.sender).representedObject()
      if represented of Window:
        Application(self).activateWindow(Window(represented))
    invocation.setResult(())
  discard app.replaceMethod(orderFrontWindowAction(), orderFrontWindowMethod)

  let keyEquivalentMethod: DynamicMethod = proc(
      self: DynamicAgent, invocation: var Invocation
  ) =
    let event = invocation.argsAs(KeyEvent)
    invocation.setResult(Application(self).performMenuKeyEquivalent(event))
  discard app.replaceMethod(nimkitSelectors.performKeyEquivalent(), keyEquivalentMethod)

  let windowOrderedFrontMethod: DynamicMethod = proc(
      self: DynamicAgent, invocation: var Invocation
  ) =
    let args = invocation.argsAs(ActionArgs)
    if args.sender of Window:
      Application(self).noteWindowOrderedFront(Window(args.sender))
    invocation.setResult(())
  discard app.replaceMethod(
    actionSelector(WindowDidOrderFrontSelector), windowOrderedFrontMethod
  )

  let windowOrderedBackMethod: DynamicMethod = proc(
      self: DynamicAgent, invocation: var Invocation
  ) =
    let args = invocation.argsAs(ActionArgs)
    if args.sender of Window:
      Application(self).noteWindowOrderedBack(Window(args.sender))
    invocation.setResult(())
  discard app.replaceMethod(
    actionSelector(WindowDidOrderBackSelector), windowOrderedBackMethod
  )

  let windowOrderedOutMethod: DynamicMethod = proc(
      self: DynamicAgent, invocation: var Invocation
  ) =
    let args = invocation.argsAs(ActionArgs)
    if args.sender of Window:
      Application(self).noteWindowOrderedOut(Window(args.sender))
    invocation.setResult(())
  discard
    app.replaceMethod(actionSelector(WindowDidOrderOutSelector), windowOrderedOutMethod)

  let windowClosedMethod: DynamicMethod = proc(
      self: DynamicAgent, invocation: var Invocation
  ) =
    let args = invocation.argsAs(ActionArgs)
    if args.sender of Window:
      Application(self).noteWindowClosed(Window(args.sender))
    invocation.setResult(())
  discard app.replaceMethod(actionSelector(WindowDidCloseSelector), windowClosedMethod)

proc applicationForwardingTarget(app: Application, selector: SigilName): DynamicAgent =
  if not app.xDelegate.isNil and app.xDelegate.respondsTo(selector):
    return app.xDelegate

proc installApplicationForwarding(app: Application) =
  app.setForwardingTarget(
    proc(self: DynamicAgent, selector: SigilName): DynamicAgent =
      applicationForwardingTarget(Application(self), selector)
  )

proc newApplication*(): Application =
  result = Application()
  initResponder(result)
  result.installApplicationForwarding()
  result.installApplicationCommandMethods()

proc sharedApplication*(): Application =
  if sharedApplicationInstance.isNil:
    sharedApplicationInstance = newApplication()
  sharedApplicationInstance

proc hasAppearance*(app: Application): bool =
  (not app.isNil) and app.xHasAppearance

proc appearance*(app: Application): Appearance =
  if app.isNil or not app.xHasAppearance:
    return initAppearance()
  app.xAppearance

proc effectiveAppearance*(app: Application): Appearance =
  if app.isNil or not app.xHasAppearance:
    return initAppearance()
  app.xAppearance

proc delegate*(app: Application): DynamicAgent =
  if app.isNil: nil else: app.xDelegate

proc `delegate=`*(app: Application, delegate: DynamicAgent) =
  if app.isNil:
    return
  app.xDelegate = delegate

proc `delegate=`*(app: Application, delegate: Responder) =
  app.delegate = DynamicAgent(delegate)

proc currentEvent*(app: Application): Option[KeyEvent] =
  if app.isNil or not app.xHasCurrentEvent:
    return none(KeyEvent)
  some(app.xCurrentEvent)

proc setCurrentEvent*(app: Application, event: KeyEvent) =
  if not app.isNil:
    app.xCurrentEvent = event
    app.xHasCurrentEvent = true

proc clearCurrentEvent*(app: Application) =
  if not app.isNil:
    app.xCurrentEvent = KeyEvent()
    app.xHasCurrentEvent = false

proc removeWindow(windows: var seq[Window], window: Window): bool =
  let idx = windows.find(window)
  if idx >= 0:
    windows.delete(idx)
    return true

proc includeOrderedWindow(app: Application, window: Window) =
  if app.isNil or window.isNil or window in app.xOrderedWindows:
    return
  app.xOrderedWindows.add window

proc moveWindowToFront(app: Application, window: Window) =
  if app.isNil or window.isNil:
    return
  discard app.xOrderedWindows.removeWindow(window)
  app.xOrderedWindows.insert(window, 0)

proc moveWindowToBack(app: Application, window: Window) =
  if app.isNil or window.isNil:
    return
  discard app.xOrderedWindows.removeWindow(window)
  app.xOrderedWindows.add window

proc frontVisibleWindow(app: Application, excluding: Window = nil): Window =
  if app.isNil:
    return nil
  for window in app.xOrderedWindows:
    if window != excluding and not window.isNil and window.isVisible:
      return window

proc restoreFocusAfterWindowHidden(app: Application, window: Window) =
  if app.isNil or app.xHidden:
    return
  let replacement = app.frontVisibleWindow(excluding = window)
  if app.xKeyWindow == window:
    app.setKeyWindow(replacement)
  if app.xMainWindow == window:
    app.setMainWindow(replacement)

proc restoreFocusAfterWindowClosed(app: Application, window: Window) =
  if app.isNil:
    return
  let replacement = app.frontVisibleWindow(excluding = window)
  if app.xKeyWindow == window:
    app.setKeyWindow(replacement)
  if app.xMainWindow == window:
    app.setMainWindow(replacement)

proc noteWindowOrderedFront(app: Application, window: Window) =
  if app.isNil or window.isNil or window.isClosed:
    return
  if window notin app.xWindows:
    app.addWindow(window)
  app.moveWindowToFront(window)
  if window.isKeyWindow:
    app.setKeyWindow(window)
  if window.isMainWindow:
    app.setMainWindow(window)
  app.updateWindowsMenu()

proc noteWindowOrderedBack(app: Application, window: Window) =
  if app.isNil or window.isNil or window.isClosed:
    return
  if window notin app.xWindows:
    app.addWindow(window)
  app.moveWindowToBack(window)
  app.updateWindowsMenu()

proc noteWindowOrderedOut(app: Application, window: Window) =
  if app.isNil or window.isNil:
    return
  app.restoreFocusAfterWindowHidden(window)
  app.updateWindowsMenu()

proc noteWindowClosed(app: Application, window: Window) =
  if app.isNil or window.isNil:
    return
  discard app.xOrderedWindows.removeWindow(window)
  app.restoreFocusAfterWindowClosed(window)
  app.updateWindowsMenu()

proc keyWindow*(app: Application): Window =
  if app.isNil: nil else: app.xKeyWindow

proc mainWindow*(app: Application): Window =
  if app.isNil: nil else: app.xMainWindow

proc setKeyWindow*(app: Application, window: Window) =
  if app.isNil or app.xKeyWindow == window:
    return
  if not app.xKeyWindow.isNil:
    app.xKeyWindow.setKeyWindow(false)
  app.xKeyWindow = window
  if not window.isNil:
    window.setKeyWindow(true)
  app.updateWindowsMenu()

proc setMainWindow*(app: Application, window: Window) =
  if app.isNil or app.xMainWindow == window:
    return
  if not app.xMainWindow.isNil:
    app.xMainWindow.setMainWindow(false)
  app.xMainWindow = window
  if not window.isNil:
    window.setMainWindow(true)
  app.updateWindowsMenu()

proc mainMenu*(app: Application): Menu =
  if app.isNil: nil else: app.xMainMenu

proc `mainMenu=`*(app: Application, menu: Menu) =
  if app.isNil:
    return
  app.xMainMenu = menu
  if not menu.isNil:
    menu.setNextResponder(app)

proc windowsMenu*(app: Application): Menu =
  if app.isNil: nil else: app.xWindowsMenu

proc `windowsMenu=`*(app: Application, menu: Menu) =
  if app.isNil:
    return
  app.xWindowsMenu = menu
  if not menu.isNil:
    menu.setNextResponder(app)
  app.updateWindowsMenu()

proc isActive*(app: Application): bool =
  (not app.isNil) and app.xActive

proc isHidden*(app: Application): bool =
  (not app.isNil) and app.xHidden

proc isTerminating*(app: Application): bool =
  (not app.isNil) and app.xTerminating

proc sendDelegate(app: Application, selector: Selector[DynamicAgent, EmptyArgs]) =
  if not app.isNil and not app.xDelegate.isNil:
    discard app.xDelegate.sendLocalIfHandled(selector, DynamicAgent(app))

proc willFinishLaunching*(app: Application) =
  app.sendDelegate(appWillFinishLaunching())

proc finishLaunching*(app: Application) =
  if app.isNil or app.xLaunched:
    return
  app.willFinishLaunching()
  app.xLaunched = true
  app.sendDelegate(appDidFinishLaunching())

proc activate*(app: Application) =
  if app.isNil or app.xActive:
    return
  app.xActive = true
  app.sendDelegate(appDidBecomeActive())

proc deactivate*(app: Application) =
  if app.isNil or not app.xActive:
    return
  app.xActive = false
  app.sendDelegate(appDidResignActive())

proc hide*(app: Application) =
  if app.isNil or app.xHidden:
    return
  app.sendDelegate(appWillHide())
  app.xHidden = true
  app.xHiddenWindows.setLen(0)
  for window in app.xWindows:
    if not window.isNil:
      if window.isVisible:
        app.xHiddenWindows.add window
      window.orderOut()
  app.sendDelegate(appDidHide())

proc unhide*(app: Application) =
  if app.isNil or not app.xHidden:
    return
  app.sendDelegate(appWillUnhide())
  app.xHidden = false
  for window in app.xHiddenWindows:
    if not window.isNil and not window.isClosed:
      window.orderFront()
  if not app.xKeyWindow.isNil and not app.xKeyWindow.isClosed:
    app.xKeyWindow.makeKeyAndOrderFront()
  app.xHiddenWindows.setLen(0)
  app.sendDelegate(appDidUnhide())

proc replyToApplicationShouldTerminate*(app: Application, shouldTerminate: bool) =
  if app.isNil:
    return
  if shouldTerminate:
    app.xTerminating = true
    app.sendDelegate(appWillTerminate())
    app.stop()
  else:
    app.xTerminating = false

proc terminate*(app: Application): TerminationReply {.discardable.} =
  if app.isNil:
    return trCancel
  if not app.modalSession().isNil:
    app.xTerminating = true
    return trLater
  result = trNow
  if not app.xDelegate.isNil:
    result =
      app.xDelegate.trySendLocal(appShouldTerminate(), DynamicAgent(app)).get(trNow)
  case result
  of trCancel:
    app.xTerminating = false
  of trNow:
    app.replyToApplicationShouldTerminate(true)
  of trLater:
    app.xTerminating = true

proc propagateAppearance(app: Application) =
  let inherited = app.effectiveAppearance()
  for window in app.xWindows:
    window.setInheritedAppearance(inherited)

proc setAppearance*(app: Application, appearance: Appearance) =
  app.xAppearance = appearance
  app.xHasAppearance = true
  app.propagateAppearance()

proc clearAppearance*(app: Application) =
  if app.isNil or not app.xHasAppearance:
    return
  app.xAppearance = Appearance()
  app.xHasAppearance = false
  app.propagateAppearance()

proc clearMenuItems(menu: Menu) =
  if menu.isNil:
    return
  while menu.len > 0:
    discard menu.removeItem(menu[0])

proc updateWindowsMenu*(app: Application) =
  if app.isNil or app.xWindowsMenu.isNil:
    return
  let menu = app.xWindowsMenu
  menu.clearMenuItems()
  for window in app.xWindows:
    if not window.isNil and not window.isClosed:
      let item = newMenuItem(window.title(), orderFrontWindowAction())
      item.target = app
      item.representedObject = DynamicAgent(window)
      if window == app.xMainWindow:
        item.state = bsOn
      discard menu.addItem(item)

proc activateWindow*(app: Application, window: Window) =
  if app.isNil or window.isNil or window.isClosed:
    return
  if window notin app.xWindows:
    app.addWindow(window)
  if app.xHidden:
    app.xHidden = false
  window.makeKeyAndOrderFront()
  app.moveWindowToFront(window)
  app.setMainWindow(window)
  app.setKeyWindow(window)
  app.updateWindowsMenu()

proc addWindow*(app: Application, window: Window) =
  if app.isNil or window.isNil:
    return
  if window notin app.xWindows:
    app.xWindows.add window
  app.includeOrderedWindow(window)
  window.setNextResponder(app)
  window.setInheritedAppearance(app.effectiveAppearance())
  if app.xMainWindow.isNil:
    app.setMainWindow(window)
  if app.xKeyWindow.isNil:
    app.setKeyWindow(window)
  app.updateWindowsMenu()

proc windows*(app: Application): lent seq[Window] =
  app.xWindows

proc orderedWindows*(app: Application): lent seq[Window] =
  app.xOrderedWindows

proc isRunning*(app: Application): bool =
  app.xRunning

proc keyEquivalentDispatchStart(app: Application): Responder =
  if app.isNil:
    return nil
  if not app.xKeyWindow.isNil:
    let firstResponder = app.xKeyWindow.firstResponder()
    if not firstResponder.isNil:
      return firstResponder
    return Responder(app.xKeyWindow)
  Responder(app)

proc performMenuKeyEquivalent*(app: Application, event: KeyEvent): bool =
  if app.isNil or app.xMainMenu.isNil:
    return false
  app.setCurrentEvent(event)
  app.updateWindowsMenu()
  app.xMainMenu.performKeyEquivalent(event, app.keyEquivalentDispatchStart())

proc beginModalSession*(
    app: Application,
    window: Window,
    mode = msmApplicationModal,
    parentWindow: Window = nil,
): ModalSession =
  if app.isNil or window.isNil:
    return nil
  result = ModalSession(
    window: window,
    parentWindow: parentWindow,
    previousKeyWindow: app.xKeyWindow,
    previousMainWindow: app.xMainWindow,
    mode: mode,
    state: mssRunning,
  )
  app.xModalSessions.add result
  if window notin app.xWindows:
    app.addWindow(window)
  if mode == msmWindowModal and not parentWindow.isNil:
    parentWindow.beginSheet(window)
  else:
    window.makeKeyAndOrderFront()
  app.setKeyWindow(window)
  app.setMainWindow(window)

proc beginModalSheet*(
    app: Application, parentWindow: Window, sheet: Window
): ModalSession =
  app.beginModalSession(sheet, msmWindowModal, parentWindow)

proc modalSession*(app: Application): ModalSession =
  if app.isNil or app.xModalSessions.len == 0:
    return nil
  app.xModalSessions[^1]

proc stopModal*(app: Application, response = 0) =
  let session = app.modalSession()
  if not session.isNil:
    session.response = response
    session.state = mssStopped

proc abortModal*(app: Application) =
  let session = app.modalSession()
  if not session.isNil:
    session.state = mssAborted

proc endModalSession*(app: Application, session: ModalSession) =
  if app.isNil or session.isNil:
    return
  let idx = app.xModalSessions.find(session)
  if idx >= 0:
    app.xModalSessions.delete(idx)
  if session.mode == msmWindowModal and not session.parentWindow.isNil:
    session.parentWindow.endSheet(session.window)
  elif not session.window.isNil:
    session.window.orderOut()
  if not session.previousMainWindow.isNil and not session.previousMainWindow.isClosed:
    app.setMainWindow(session.previousMainWindow)
  if not session.previousKeyWindow.isNil and not session.previousKeyWindow.isClosed:
    app.setKeyWindow(session.previousKeyWindow)
  app.updateWindowsMenu()

proc runModalSession*(app: Application, session: ModalSession): int =
  if app.isNil or session.isNil:
    return 0
  while session.state == mssRunning:
    if app.runForFrames(1) == 0:
      session.state = mssAborted
      break
  result = session.response

proc runModalForWindow*(app: Application, window: Window): int =
  let session = app.beginModalSession(window)
  result = app.runModalSession(session)
  app.endModalSession(session)

proc runModalForWindow*(
    app: Application, window: Window, mode: ModalSessionMode, parentWindow: Window = nil
): int =
  let session = app.beginModalSession(window, mode, parentWindow)
  result = app.runModalSession(session)
  app.endModalSession(session)

proc runModalSheet*(app: Application, parentWindow: Window, sheet: Window): int =
  app.runModalForWindow(sheet, msmWindowModal, parentWindow)

proc runModal*(app: Application, alert: Alert): int =
  if alert.isNil:
    return 0
  app.runModalForWindow(alert.window)

proc runModal*(app: Application, panel: OpenPanel): int =
  if panel.isNil:
    return 0
  app.runModalForWindow(panel.window)

proc runModal*(app: Application, panel: SavePanel): int =
  if panel.isNil:
    return 0
  app.runModalForWindow(panel.window)

proc beginModalSheet*(
    app: Application, parentWindow: Window, alert: Alert
): ModalSession =
  if alert.isNil:
    return nil
  app.beginModalSheet(parentWindow, alert.window)

proc beginModalSheet*(
    app: Application, parentWindow: Window, panel: OpenPanel
): ModalSession =
  if panel.isNil:
    return nil
  app.beginModalSheet(parentWindow, panel.window)

proc beginModalSheet*(
    app: Application, parentWindow: Window, panel: SavePanel
): ModalSession =
  if panel.isNil:
    return nil
  app.beginModalSheet(parentWindow, panel.window)

proc runModal*(alert: Alert, app = sharedApplication()): int =
  app.runModal(alert)

proc runModal*(panel: OpenPanel, app = sharedApplication()): int =
  app.runModal(panel)

proc runModal*(panel: SavePanel, app = sharedApplication()): int =
  app.runModal(panel)

proc windowBlockedByModal*(app: Application, window: Window): bool =
  let session = app.modalSession()
  if session.isNil or window.isNil:
    return false
  if window == session.window:
    return false
  case session.mode
  of msmApplicationModal:
    true
  of msmWindowModal:
    window == session.parentWindow

proc runForFrames*(app: Application, frames: Natural): int =
  if frames == 0:
    return 0
  app.xRunning = true
  while app.xRunning:
    var activeWindows = 0
    var removedWindow = false
    var idx = 0
    while idx < app.xWindows.len:
      let window = app.xWindows[idx]
      if window.isNil or window.isClosed:
        if not window.isNil and window.nextResponder() == Responder(app):
          window.clearNextResponder()
        if not window.isNil:
          discard app.xOrderedWindows.removeWindow(window)
          app.restoreFocusAfterWindowClosed(window)
        app.xWindows.delete(idx)
        removedWindow = true
      else:
        if window.isVisible:
          window.pumpNativeWindowFrame()
          if not window.isClosed:
            inc activeWindows
        inc idx
    if removedWindow:
      app.updateWindowsMenu()

    inc result
    if result >= frames.int:
      break
    if activeWindows == 0:
      break
    sleep(8)
  app.xRunning = false

proc run*(app: Application) =
  app.xRunning = true
  while app.xRunning:
    var activeWindows = 0
    var removedWindow = false
    var idx = 0
    while idx < app.xWindows.len:
      let window = app.xWindows[idx]
      if window.isNil or window.isClosed:
        if not window.isNil and window.nextResponder() == Responder(app):
          window.clearNextResponder()
        if not window.isNil:
          discard app.xOrderedWindows.removeWindow(window)
          app.restoreFocusAfterWindowClosed(window)
        app.xWindows.delete(idx)
        removedWindow = true
      else:
        if window.isVisible:
          window.pumpNativeWindowFrame()
          if not window.isClosed:
            inc activeWindows
        inc idx
    if removedWindow:
      app.updateWindowsMenu()

    if activeWindows == 0:
      break
    sleep(8)
  app.xRunning = false

proc stop*(app: Application) =
  app.xRunning = false
