import std/[options, os]

import sigils/selectors
import sigils/threadBase

import ../foundation/events
import ../foundation/notifications
import ../controls/menus
import ../controls/nativemenus as nativeMenus
import ../responder/keybindings
import ../responder/responders
import ../foundation/selectors as nimkitSelectors
import ../themes
import ../foundation/types
import ../view/views
import ./userdefaults
import ./animations
import ./backend as nimkitBackend
import ./panels
import ../app/windows

type
  MainMenuPresentation* = enum
    mmpAutomatic
    mmpNative
    mmpInWindow

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
    xApplicationName: string
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
    xServicesMenu: Menu
    xDynamicWindowsMenuItems: seq[MenuItem]
    xMainMenuPresentation: MainMenuPresentation
    xRunning: bool
    xActive: bool
    xHidden: bool
    xHiddenWindows: seq[Window]
    xLaunched: bool
    xTerminating: bool
    xModalSessions: seq[ModalSession]
    xUserDefaults: UserDefaults
    xAnimationScheduler: AnimationScheduler
    xAnimationClock: AnimationSchedulerClock
    xRenderExecutionMode: RenderExecutionMode
    xThreadRenderer: ThreadRendererClient
    xApplicationThreadId: int

const WindowDidOrderFrontSelector = "_nimkitWindowDidOrderFront"
const WindowDidOrderBackSelector = "_nimkitWindowDidOrderBack"
const WindowDidOrderOutSelector = "_nimkitWindowDidOrderOut"
const WindowDidCloseSelector = "_nimkitWindowDidClose"
const ThreadSignalBudgetPerFrame = 10

var sharedApplicationInstance: Application

proc hide*(app: Application)
proc terminate*(app: Application): TerminationReply {.discardable.}
proc stop*(app: Application)
proc addWindow*(app: Application, window: Window)
proc activateWindow*(app: Application, window: Window)
proc updateWindowsMenu*(app: Application)
proc installStandardMainMenu*(app: Application)
proc modalSession*(app: Application): ModalSession
proc performMenuKeyEquivalent*(app: Application, event: KeyEvent): bool
proc runForFrames*(app: Application, frames: Natural): int
proc run*(app: Application)
proc drainAnimations*(app: Application): int {.discardable.}
proc setKeyWindow*(app: Application, window: Window)
proc setMainWindow*(app: Application, window: Window)
proc noteWindowOrderedFront(app: Application, window: Window)
proc noteWindowOrderedBack(app: Application, window: Window)
proc noteWindowOrderedOut(app: Application, window: Window)
proc noteWindowClosed(app: Application, window: Window)
proc keyEquivalentDispatchStart(app: Application): Responder
proc syncMainMenuPresentation(app: Application)
proc syncMenuBarPresenters(app: Application)
proc runApplicationFrame(app: Application): int

proc resolvedApplicationName(name: string): string =
  if name.len > 0:
    return name
  let executableName = getAppFilename().splitFile.name
  if executableName.len > 0:
    return executableName
  "Application"

proc orderFrontWindowAction*(): ActionSelector =
  actionSelector("orderFrontWindow")

proc installApplicationCommandMethods(app: Application) =
  let aboutMethod: DynamicMethod = proc(
      self: DynamicAgent, invocation: var Invocation
  ) =
    discard self
    nativeMenus.showStandardAboutPanel()
    invocation.setResult(())
  discard app.replaceMethod(actionSelector("orderFrontStandardAboutPanel"), aboutMethod)

  let hideMethod: DynamicMethod = proc(self: DynamicAgent, invocation: var Invocation) =
    Application(self).hide()
    invocation.setResult(())
  discard app.replaceMethod(actionSelector("hide"), hideMethod)

  let hideOthersMethod: DynamicMethod = proc(
      self: DynamicAgent, invocation: var Invocation
  ) =
    discard self
    nativeMenus.hideOtherNativeApplications()
    invocation.setResult(())
  discard app.replaceMethod(actionSelector("hideOtherApplications"), hideOthersMethod)

  let unhideAllMethod: DynamicMethod = proc(
      self: DynamicAgent, invocation: var Invocation
  ) =
    discard self
    nativeMenus.unhideAllNativeApplications()
    invocation.setResult(())
  discard app.replaceMethod(actionSelector("unhideAllApplications"), unhideAllMethod)

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

proc newApplication*(applicationName = ""): Application =
  result = Application(xApplicationName: resolvedApplicationName(applicationName))
  initResponder(result)
  result.installApplicationForwarding()
  result.installApplicationCommandMethods()
  when defined(macosx):
    result.installStandardMainMenu()

proc sharedApplication*(): Application =
  if sharedApplicationInstance.isNil:
    sharedApplicationInstance = newApplication()
  sharedApplicationInstance

func applicationName*(app: Application): string =
  app.xApplicationName

proc userDefaults*(app: Application): UserDefaults =
  if app.xUserDefaults.isNil:
    app.xUserDefaults = sharedUserDefaults()
  app.xUserDefaults

proc animationScheduler*(app: Application): AnimationScheduler =
  if app.xAnimationScheduler.isNil:
    app.xAnimationScheduler = newAnimationScheduler()
  app.xAnimationScheduler

proc animationClock*(app: Application): AnimationSchedulerClock =
  if app.xAnimationClock.isNil:
    app.xAnimationClock = newAnimationSchedulerClock()
  app.xAnimationClock

proc startAnimationClock*(app: Application) =
  let clock = app.animationClock()
  if not clock.isNil and not clock.isRunning:
    clock.start()

proc stopAnimationClock*(app: Application) =
  if app.xAnimationClock.isNil:
    return
  app.xAnimationClock.stop()

proc startAnimation*(app: Application, animation: Animation): bool {.discardable.} =
  let scheduler = app.animationScheduler()
  if scheduler.isNil:
    return false
  result = scheduler.startAnimation(animation)
  if result and scheduler.animationCount > 0:
    app.startAnimationClock()

proc stopAnimation*(
    app: Application, animation: Animation, finished = false
): bool {.discardable.} =
  if app.xAnimationScheduler.isNil:
    return false
  result = app.xAnimationScheduler.stopAnimation(animation, finished)
  if app.xAnimationScheduler.animationCount == 0:
    app.stopAnimationClock()

proc drainAnimations*(app: Application): int {.discardable.} =
  if app.xAnimationScheduler.isNil or app.xAnimationClock.isNil:
    return 0
  result = app.xAnimationScheduler.drain(app.xAnimationClock, pollSignals = false)
  if app.xAnimationScheduler.animationCount == 0:
    app.stopAnimationClock()

proc hasAppearance*(app: Application): bool =
  app.xHasAppearance

proc appearance*(app: Application): Appearance =
  if not app.xHasAppearance:
    return initAppearance()
  app.xAppearance

proc effectiveAppearance*(app: Application): Appearance =
  if not app.xHasAppearance:
    return initAppearance()
  app.xAppearance

proc delegate*(app: Application): DynamicAgent =
  app.xDelegate

proc `delegate=`*(app: Application, delegate: DynamicAgent) =
  app.xDelegate = delegate

proc `delegate=`*(app: Application, delegate: Responder) =
  app.delegate = DynamicAgent(delegate)

proc currentEvent*(app: Application): Option[KeyEvent] =
  if not app.xHasCurrentEvent:
    return none(KeyEvent)
  some(app.xCurrentEvent)

proc setCurrentEvent*(app: Application, event: KeyEvent) =
  app.xCurrentEvent = event
  app.xHasCurrentEvent = true

proc clearCurrentEvent*(app: Application) =
  app.xCurrentEvent = KeyEvent()
  app.xHasCurrentEvent = false

proc removeWindow(windows: var seq[Window], window: Window): bool =
  let idx = windows.find(window)
  if idx >= 0:
    windows.delete(idx)
    return true

proc includeOrderedWindow(app: Application, window: Window) =
  if window.isNil or window in app.xOrderedWindows:
    return
  app.xOrderedWindows.add window

proc moveWindowToFront(app: Application, window: Window) =
  if window.isNil:
    return
  discard app.xOrderedWindows.removeWindow(window)
  app.xOrderedWindows.insert(window, 0)

proc moveWindowToBack(app: Application, window: Window) =
  if window.isNil:
    return
  discard app.xOrderedWindows.removeWindow(window)
  app.xOrderedWindows.add window

proc frontVisibleWindow(app: Application, excluding: Window = nil): Window =
  for window in app.xOrderedWindows:
    if window != excluding and not window.isNil and window.isVisible:
      return window

proc restoreFocusAfterWindowHidden(app: Application, window: Window) =
  if app.xHidden:
    return
  let replacement = app.frontVisibleWindow(excluding = window)
  if app.xKeyWindow == window:
    app.setKeyWindow(replacement)
  if app.xMainWindow == window:
    app.setMainWindow(replacement)

proc restoreFocusAfterWindowClosed(app: Application, window: Window) =
  let replacement = app.frontVisibleWindow(excluding = window)
  if app.xKeyWindow == window:
    app.setKeyWindow(replacement)
  if app.xMainWindow == window:
    app.setMainWindow(replacement)

proc noteWindowOrderedFront(app: Application, window: Window) =
  if window.isNil or window.isClosed:
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
  if window.isNil or window.isClosed:
    return
  if window notin app.xWindows:
    app.addWindow(window)
  app.moveWindowToBack(window)
  app.updateWindowsMenu()

proc noteWindowOrderedOut(app: Application, window: Window) =
  if window.isNil:
    return
  app.restoreFocusAfterWindowHidden(window)
  app.updateWindowsMenu()

proc noteWindowClosed(app: Application, window: Window) =
  if window.isNil:
    return
  discard app.xOrderedWindows.removeWindow(window)
  app.restoreFocusAfterWindowClosed(window)
  app.updateWindowsMenu()

proc keyWindow*(app: Application): Window =
  app.xKeyWindow

proc mainWindow*(app: Application): Window =
  app.xMainWindow

proc setKeyWindow*(app: Application, window: Window) =
  if app.xKeyWindow == window:
    return
  if not app.xKeyWindow.isNil:
    app.xKeyWindow.setKeyWindow(false)
  app.xKeyWindow = window
  if not window.isNil:
    window.setKeyWindow(true)
  app.updateWindowsMenu()

proc setMainWindow*(app: Application, window: Window) =
  if app.xMainWindow == window:
    return
  if not app.xMainWindow.isNil:
    app.xMainWindow.setMainWindow(false)
  app.xMainWindow = window
  if not window.isNil:
    window.setMainWindow(true)
  app.updateWindowsMenu()

proc mainMenu*(app: Application): Menu =
  app.xMainMenu

func nativeMainMenuAvailable*(): bool =
  when defined(macosx): true else: false

func mainMenuPresentation*(app: Application): MainMenuPresentation =
  app.xMainMenuPresentation

func usesNativeMainMenu*(app: Application): bool =
  if not nativeMainMenuAvailable():
    return false
  app.xMainMenuPresentation != mmpInWindow

proc syncMenuBarPresenters(view: View, menu: Menu, presentedNatively: bool) =
  if view of MenuBar:
    let menuBar = MenuBar(view)
    menuBar.hidden = presentedNatively and menuBar.menu() == menu
  for child in view.subviews():
    child.syncMenuBarPresenters(menu, presentedNatively)

proc syncMenuBarPresenters(app: Application) =
  let presentedNatively = app.usesNativeMainMenu()
  for window in app.xWindows:
    if not window.isNil and not window.contentView().isNil:
      window.contentView().syncMenuBarPresenters(app.xMainMenu, presentedNatively)

proc syncMainMenuPresentation(app: Application) =
  app.xMainMenu.presentedNatively = app.usesNativeMainMenu()
  if app.usesNativeMainMenu():
    app.xMainMenu.installNativeMainMenu(
      proc(): Responder =
        app.keyEquivalentDispatchStart()
    )
    app.xWindowsMenu.installNativeWindowsMenu()
    app.xServicesMenu.installNativeServicesMenu()
  else:
    Menu(nil).installNativeMainMenu()
  app.syncMenuBarPresenters()

proc `mainMenuPresentation=`*(app: Application, presentation: MainMenuPresentation) =
  if app.xMainMenuPresentation == presentation:
    return
  app.xMainMenuPresentation = presentation
  app.syncMainMenuPresentation()

proc `mainMenu=`*(app: Application, menu: Menu) =
  if app.xMainMenu != menu:
    app.xMainMenu.presentedNatively = false
  app.xMainMenu = menu
  if not menu.isNil:
    menu.setNextResponder(app)
  app.syncMainMenuPresentation()

proc windowsMenu*(app: Application): Menu =
  app.xWindowsMenu

proc `windowsMenu=`*(app: Application, menu: Menu) =
  if app.xWindowsMenu == menu:
    return
  if not app.xWindowsMenu.isNil:
    for item in app.xDynamicWindowsMenuItems:
      discard app.xWindowsMenu.removeItem(item)
  app.xDynamicWindowsMenuItems.setLen(0)
  app.xWindowsMenu = menu
  if not menu.isNil:
    menu.setNextResponder(app)
  app.syncMainMenuPresentation()
  app.updateWindowsMenu()

proc servicesMenu*(app: Application): Menu =
  app.xServicesMenu

proc `servicesMenu=`*(app: Application, menu: Menu) =
  app.xServicesMenu = menu
  if not menu.isNil:
    menu.setNextResponder(app)
  app.syncMainMenuPresentation()

proc addStandardMenu(
    mainMenu: Menu, title: string, submenu: Menu
): MenuItem {.discardable.} =
  result = newMenuItem(title)
  result.submenu = submenu
  discard mainMenu.addItem(result)

proc addStandardApplicationItem(
    menu: Menu,
    app: Application,
    title: string,
    action: ActionSelector,
    keyEquivalent = "",
    modifiers: set[KeyModifier] = {},
): MenuItem {.discardable.} =
  result = menu.addItem(title, action, keyEquivalent, modifiers)
  result.target = app

proc installStandardMainMenu*(app: Application) =
  let
    shortcut = shortcutModifiers()
    appName = app.applicationName()
    mainMenu = newMenu("Main")
    applicationMenu = newMenu(appName)
    fileMenu = newMenu("File")
    editMenu = newMenu("Edit")
    windowMenu = newMenu("Window")
    helpMenu = newMenu("Help")
    servicesMenu = newMenu("Services")

  applicationMenu.addStandardApplicationItem(
    app, "About " & appName, actionSelector("orderFrontStandardAboutPanel")
  )
  applicationMenu.addSeparator()
  discard applicationMenu.addItem(
    "Settings…", actionSelector("showPreferences"), ",", shortcut
  )
  applicationMenu.addSeparator()
  applicationMenu.addStandardMenu("Services", servicesMenu)
  applicationMenu.addSeparator()
  applicationMenu.addStandardApplicationItem(
    app, "Hide " & appName, actionSelector("hide"), "h", shortcut
  )
  applicationMenu.addStandardApplicationItem(
    app,
    "Hide Others",
    actionSelector("hideOtherApplications"),
    "h",
    shortcut + {kmOption},
  )
  applicationMenu.addStandardApplicationItem(
    app, "Show All", actionSelector("unhideAllApplications")
  )
  applicationMenu.addSeparator()
  applicationMenu.addStandardApplicationItem(
    app, "Quit " & appName, actionSelector("terminate"), "q", shortcut
  )

  discard
    fileMenu.addItem("Close Window", actionSelector("performClose"), "w", shortcut)

  discard editMenu.addItem("Undo", actionSelector("undo"), "z", shortcut)
  discard editMenu.addItem("Redo", actionSelector("redo"), "z", shortcut + {kmShift})
  editMenu.addSeparator()
  discard editMenu.addItem("Cut", actionSelector("cut"), "x", shortcut)
  discard editMenu.addItem("Copy", actionSelector("copy"), "c", shortcut)
  discard editMenu.addItem("Paste", actionSelector("paste"), "v", shortcut)
  editMenu.addSeparator()
  discard editMenu.addItem("Select All", actionSelector("selectAll"), "a", shortcut)

  discard
    windowMenu.addItem("Minimize", actionSelector("performMiniaturize"), "m", shortcut)
  discard windowMenu.addItem("Zoom", actionSelector("performZoom"))
  windowMenu.addSeparator()

  discard helpMenu.addItem(appName & " Help", actionSelector("showHelp"))

  mainMenu.addStandardMenu(appName, applicationMenu)
  mainMenu.addStandardMenu("File", fileMenu)
  mainMenu.addStandardMenu("Edit", editMenu)
  mainMenu.addStandardMenu("Window", windowMenu)
  mainMenu.addStandardMenu("Help", helpMenu)

  app.windowsMenu = windowMenu
  app.servicesMenu = servicesMenu
  app.mainMenu = mainMenu

proc isActive*(app: Application): bool =
  app.xActive

proc isHidden*(app: Application): bool =
  app.xHidden

proc isTerminating*(app: Application): bool =
  app.xTerminating

proc sendDelegate(app: Application, selector: Selector[DynamicAgent, EmptyArgs]) =
  if not app.xDelegate.isNil:
    discard app.xDelegate.sendLocalIfHandled(selector, DynamicAgent(app))

proc postApplicationNotification(app: Application, kind: NotificationKind) =
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      kind,
      sender = DynamicAgent(app),
      payload = initApplicationNotificationPayload(
        active = app.xActive, hidden = app.xHidden, terminating = app.xTerminating
      ),
    )
  )

proc postApplicationAppearanceNotification(app: Application) =
  emit sharedNotificationCenter().notificationReceived(
    initNotification(
      nkApplicationAppearanceDidChange,
      sender = DynamicAgent(app),
      payload = initAppearanceNotificationPayload(
        atkApplication, app.effectiveAppearance(), app.xHasAppearance
      ),
    )
  )

proc willFinishLaunching*(app: Application) =
  app.sendDelegate(appWillFinishLaunching())
  app.postApplicationNotification(nkApplicationWillFinishLaunching)

proc finishLaunching*(app: Application) =
  if app.xLaunched:
    return
  app.willFinishLaunching()
  app.xLaunched = true
  app.sendDelegate(appDidFinishLaunching())
  app.postApplicationNotification(nkApplicationDidFinishLaunching)

proc activate*(app: Application) =
  if app.xActive:
    return
  app.xActive = true
  app.sendDelegate(appDidBecomeActive())
  app.postApplicationNotification(nkApplicationDidBecomeActive)

proc deactivate*(app: Application) =
  if not app.xActive:
    return
  app.xActive = false
  app.sendDelegate(appDidResignActive())
  app.postApplicationNotification(nkApplicationDidResignActive)

proc hide*(app: Application) =
  if app.xHidden:
    return
  app.sendDelegate(appWillHide())
  app.postApplicationNotification(nkApplicationWillHide)
  app.xHidden = true
  app.xHiddenWindows.setLen(0)
  for window in app.xWindows:
    if not window.isNil:
      if window.isVisible:
        app.xHiddenWindows.add window
      window.orderOut()
  app.sendDelegate(appDidHide())
  app.postApplicationNotification(nkApplicationDidHide)

proc unhide*(app: Application) =
  if not app.xHidden:
    return
  app.sendDelegate(appWillUnhide())
  app.postApplicationNotification(nkApplicationWillUnhide)
  app.xHidden = false
  for window in app.xHiddenWindows:
    if not window.isNil and not window.isClosed:
      window.orderFront()
  if not app.xKeyWindow.isNil and not app.xKeyWindow.isClosed:
    app.xKeyWindow.makeKeyAndOrderFront()
  app.xHiddenWindows.setLen(0)
  app.sendDelegate(appDidUnhide())
  app.postApplicationNotification(nkApplicationDidUnhide)

proc replyToApplicationShouldTerminate*(app: Application, shouldTerminate: bool) =
  if shouldTerminate:
    app.xTerminating = true
    app.sendDelegate(appWillTerminate())
    app.postApplicationNotification(nkApplicationWillTerminate)
    app.stop()
  else:
    app.xTerminating = false

proc terminate*(app: Application): TerminationReply {.discardable.} =
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
  app.postApplicationAppearanceNotification()

proc clearAppearance*(app: Application) =
  if not app.xHasAppearance:
    return
  app.xAppearance = Appearance()
  app.xHasAppearance = false
  app.propagateAppearance()
  app.postApplicationAppearanceNotification()

proc updateWindowsMenu*(app: Application) =
  if app.xWindowsMenu.isNil:
    return
  let menu = app.xWindowsMenu
  for item in app.xDynamicWindowsMenuItems:
    discard menu.removeItem(item)
  app.xDynamicWindowsMenuItems.setLen(0)
  for window in app.xWindows:
    if not window.isNil and not window.isClosed:
      let item = newMenuItem(window.title(), orderFrontWindowAction())
      item.target = app
      item.representedObject = DynamicAgent(window)
      if window == app.xMainWindow:
        item.state = bsOn
      discard menu.addItem(item)
      app.xDynamicWindowsMenuItems.add item

proc activateWindow*(app: Application, window: Window) =
  if window.isNil or window.isClosed:
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

proc showWindow*(
    app: Application, window: Window, contentView: View, firstResponder: Responder = nil
): Window {.discardable.} =
  if window.isNil:
    return nil
  window.setContentView(contentView)
  if firstResponder.isNil:
    discard window.selectNextKeyView()
  else:
    discard window.makeFirstResponder(firstResponder)
  app.activateWindow(window)
  window

proc runWindow*(
    app: Application, window: Window, contentView: View, firstResponder: Responder = nil
) =
  discard app.showWindow(window, contentView, firstResponder)
  app.run()

proc addWindow*(app: Application, window: Window) =
  if window.isNil:
    return
  if window notin app.xWindows:
    app.xWindows.add window
  app.includeOrderedWindow(window)
  window.setNextResponder(app)
  window.setInheritedAppearance(app.effectiveAppearance())
  if not app.xThreadRenderer.isNil:
    window.useThreadRenderer(app.xThreadRenderer)
  if app.xMainWindow.isNil:
    app.setMainWindow(window)
  if app.xKeyWindow.isNil:
    app.setKeyWindow(window)
  app.updateWindowsMenu()
  app.syncMenuBarPresenters()

proc windows*(app: Application): lent seq[Window] =
  app.xWindows

proc orderedWindows*(app: Application): lent seq[Window] =
  app.xOrderedWindows

proc isRunning*(app: Application): bool =
  app.xRunning

proc renderExecutionMode*(app: Application): RenderExecutionMode =
  app.xRenderExecutionMode

proc `renderExecutionMode=`*(app: Application, mode: RenderExecutionMode) =
  if app.xRunning:
    raise
      newException(ValueError, "set renderExecutionMode before running the application")
  app.xRenderExecutionMode = mode

proc usesDedicatedRenderer(app: Application): bool =
  case app.xRenderExecutionMode
  of remMainThread:
    false
  of remDedicatedThread:
    if not dedicatedRendererSupported():
      raise newException(ValueError, "the current backend has no dedicated renderer")
    true
  of remAutomatic:
    dedicatedRendererSupported()

proc isThreaded*(app: Application): bool =
  not app.xThreadRenderer.isNil and app.xThreadRenderer.isRunning()

proc applicationThreadId*(app: Application): int =
  app.xApplicationThreadId

proc rendererThreadId*(app: Application): int =
  if not app.xThreadRenderer.isNil:
    return app.xThreadRenderer.rendererThreadId()
  -1

proc keyEquivalentDispatchStart(app: Application): Responder =
  if not app.xKeyWindow.isNil:
    let firstResponder = app.xKeyWindow.firstResponder()
    if not firstResponder.isNil:
      return firstResponder
    return Responder(app.xKeyWindow)
  Responder(app)

proc performMenuKeyEquivalent*(app: Application, event: KeyEvent): bool =
  if app.xMainMenu.isNil:
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
  if window.isNil:
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
  if app.xModalSessions.len == 0:
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
  if session.isNil:
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
  if session.isNil:
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
  alert.prepareForModal(
    proc(response: int) =
      app.stopModal(response)
  )
  app.runModalForWindow(alert.window)

proc runModal*(app: Application, panel: OpenPanel): int =
  if panel.isNil:
    return 0
  panel.prepareForModal(
    proc(response: int) =
      app.stopModal(response)
  )
  app.runModalForWindow(panel.window)

proc runModal*(app: Application, panel: SavePanel): int =
  if panel.isNil:
    return 0
  panel.prepareForModal(
    proc(response: int) =
      app.stopModal(response)
  )
  app.runModalForWindow(panel.window)

proc beginModalSheet*(
    app: Application, parentWindow: Window, alert: Alert
): ModalSession =
  if alert.isNil:
    return nil
  alert.prepareForModal(
    proc(response: int) =
      app.stopModal(response)
  )
  app.beginModalSheet(parentWindow, alert.window)

proc beginModalSheet*(
    app: Application, parentWindow: Window, panel: OpenPanel
): ModalSession =
  if panel.isNil:
    return nil
  panel.prepareForModal(
    proc(response: int) =
      app.stopModal(response)
  )
  app.beginModalSheet(parentWindow, panel.window)

proc beginModalSheet*(
    app: Application, parentWindow: Window, panel: SavePanel
): ModalSession =
  if panel.isNil:
    return nil
  panel.prepareForModal(
    proc(response: int) =
      app.stopModal(response)
  )
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

proc runApplicationFrame(app: Application): int =
  if hasLocalSigilThread():
    let thread = getCurrentSigilThread()
    for _ in 0 ..< ThreadSignalBudgetPerFrame:
      if not thread.poll(NonBlocking):
        break
  discard app.drainAnimations()
  var
    removedWindow = false
    hostWindowCreated = false
    idx = 0
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
        let wasNativeReady = window.nativeReady
        if not app.xThreadRenderer.isNil:
          window.useThreadRenderer(app.xThreadRenderer)
        window.pumpNativeWindowFrame()
        if not wasNativeReady and window.nativeReady:
          hostWindowCreated = true
        if not window.isClosed:
          inc result
      inc idx
  if removedWindow:
    app.updateWindowsMenu()
  if hostWindowCreated:
    app.syncMainMenuPresentation()

proc runForFrames*(app: Application, frames: Natural): int =
  if frames == 0:
    return 0
  let wasRunning = app.xRunning
  var keepRunning = wasRunning
  app.xRunning = true
  while app.xRunning:
    let activeWindows = app.runApplicationFrame()
    inc result
    if result >= frames.int:
      break
    if activeWindows == 0:
      keepRunning = false
      break
    sleep(8)
  if app.xRunning:
    app.xRunning = keepRunning

proc run*(app: Application) =
  app.xApplicationThreadId = getThreadId()
  var runtime: ThreadRendererRuntime
  try:
    if app.usesDedicatedRenderer():
      runtime = newThreadRendererRuntime()
      runtime.start()
      app.xThreadRenderer = runtime.client
      for window in app.xWindows:
        if not window.isNil:
          window.useThreadRenderer(runtime.client)

    app.xRunning = true
    while app.xRunning:
      let activeWindows = app.runApplicationFrame()
      if activeWindows == 0:
        app.xRunning = false
      elif app.xRunning:
        sleep(8)
  finally:
    try:
      for window in app.xWindows:
        if not window.isNil:
          window.useThreadRenderer(nil)
    finally:
      runtime.stop()
      runtime.join()
      app.xThreadRenderer = nil
      app.xRunning = false
      app.stopAnimationClock()

proc stop*(app: Application) =
  app.xRunning = false
