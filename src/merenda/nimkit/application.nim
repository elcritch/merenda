import std/[options, os]

import sigils/selectors

import ./events
import ./menus
import ./responders
import ./selectors as nimkitSelectors
import ./theme
import ./windows

type
  ModalSessionState* = enum
    mssRunning
    mssStopped
    mssAborted

  ModalSession* = ref object
    window*: Window
    state*: ModalSessionState
    response*: int

  Application* = ref object of Responder
    xWindows: seq[Window]
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
    xLaunched: bool
    xTerminating: bool
    xModalSessions: seq[ModalSession]

var sharedApplicationInstance: Application

proc hide*(app: Application)
proc terminate*(app: Application): TerminationReply {.discardable.}
proc stop*(app: Application)
proc performMenuKeyEquivalent*(app: Application, event: KeyEvent): bool
proc runForFrames*(app: Application, frames: Natural): int

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

  let keyEquivalentMethod: DynamicMethod = proc(
      self: DynamicAgent, invocation: var Invocation
  ) =
    let event = invocation.argsAs(KeyEvent)
    invocation.setResult(Application(self).performMenuKeyEquivalent(event))
  discard app.replaceMethod(nimkitSelectors.performKeyEquivalent(), keyEquivalentMethod)

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

proc setMainWindow*(app: Application, window: Window) =
  if app.isNil or app.xMainWindow == window:
    return
  if not app.xMainWindow.isNil:
    app.xMainWindow.setMainWindow(false)
  app.xMainWindow = window
  if not window.isNil:
    window.setMainWindow(true)

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
  for window in app.xWindows:
    if not window.isNil:
      window.orderOut()
  app.sendDelegate(appDidHide())

proc unhide*(app: Application) =
  if app.isNil or not app.xHidden:
    return
  app.sendDelegate(appWillUnhide())
  app.xHidden = false
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

proc addWindow*(app: Application, window: Window) =
  if app.isNil or window.isNil:
    return
  if window notin app.xWindows:
    app.xWindows.add window
  window.setNextResponder(app)
  window.setInheritedAppearance(app.effectiveAppearance())
  if app.xMainWindow.isNil:
    app.setMainWindow(window)
  if app.xKeyWindow.isNil:
    app.setKeyWindow(window)

proc windows*(app: Application): lent seq[Window] =
  app.xWindows

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
  app.xMainMenu.performKeyEquivalent(event, app.keyEquivalentDispatchStart())

proc beginModalSession*(app: Application, window: Window): ModalSession =
  if app.isNil or window.isNil:
    return nil
  result = ModalSession(window: window, state: mssRunning)
  app.xModalSessions.add result
  app.setKeyWindow(window)
  app.setMainWindow(window)

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

proc runModalSession*(app: Application, session: ModalSession): int =
  if app.isNil or session.isNil:
    return 0
  while app.xRunning and session.state == mssRunning:
    discard app.runForFrames(1)
  result = session.response

proc runModalForWindow*(app: Application, window: Window): int =
  let session = app.beginModalSession(window)
  result = app.runModalSession(session)
  app.endModalSession(session)

proc runForFrames*(app: Application, frames: Natural): int =
  if frames == 0:
    return 0
  app.xRunning = true
  while app.xRunning:
    var activeWindows = 0
    var idx = 0
    while idx < app.xWindows.len:
      let window = app.xWindows[idx]
      if window.isNil or window.isClosed:
        if not window.isNil and window.nextResponder() == Responder(app):
          window.clearNextResponder()
        app.xWindows.delete(idx)
        continue
      if window.isVisible:
        window.pumpNativeWindowFrame()
        if not window.isClosed:
          inc activeWindows
      inc idx

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
    var idx = 0
    while idx < app.xWindows.len:
      let window = app.xWindows[idx]
      if window.isNil or window.isClosed:
        if not window.isNil and window.nextResponder() == Responder(app):
          window.clearNextResponder()
        app.xWindows.delete(idx)
        continue
      if window.isVisible:
        window.pumpNativeWindowFrame()
        if not window.isClosed:
          inc activeWindows
      inc idx

    if activeWindows == 0:
      break
    sleep(8)
  app.xRunning = false

proc stop*(app: Application) =
  app.xRunning = false
