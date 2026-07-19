import std/[os, tables, unicode, unittest]

import figdraw
from figdraw/windowing/siwinshim import nil
import sigils/core
import sigils/threads

import merenda/nimkit
from merenda/nimkit/app/backend import join, newThreadRendererRuntime, start, stop

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add(rune)

proc pressKey(window: Window, key: Key, modifiers: set[KeyModifier] = {}): bool =
  window.dispatchKeyDown(KeyEvent(key: key, keyCode: key.ord, modifiers: modifiers))

proc rowPoint(tableView: TableView, row: int): Point =
  let rowRect = tableView.rowItemRect(row)
  if rowRect.isEmpty:
    return tableView.pointToWindow(initPoint(0.0, 0.0))
  var x = rowRect.origin.x + min(12.0'f32, rowRect.size.width * 0.5'f32)
  let column = tableView.columnAt(0)
  if not column.isNil:
    let columnRect = tableView.tableColumnRect(column)
    if not columnRect.isEmpty:
      x = columnRect.origin.x + min(12.0'f32, columnRect.size.width * 0.5'f32)
  tableView.pointToWindow(
    initPoint(x, rowRect.origin.y + rowRect.size.height * 0.5'f32)
  )

proc clickTableRow(window: Window, tableView: TableView, row: int): bool =
  let point = tableView.rowPoint(row)
  window.mouseDownAt(point) and window.mouseUpAt(point)

proc doubleClickTableRow(window: Window, tableView: TableView, row: int): bool =
  let point = tableView.rowPoint(row)
  window.mouseDownAt(point, clickCount = 2) and window.mouseUpAt(point, clickCount = 2)

proc renderedTextX(window: Window, text: string): float32 =
  let renders = window.buildRenders()
  if DefaultDrawLevel notin renders.layers:
    return -1.0'f32
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkText and node.renderedText() == text:
      return node.screenBox.x
  -1.0'f32

type WindowHookObserver = ref object of Agent

type
  ThreadPollDispatcher = ref object of Agent
  ThreadPollWorker = ref object of AgentActor
  ThreadPollCollector = ref object of Agent
    value: int

proc threadPollRequested*(dispatcher: ThreadPollDispatcher, value: int) {.signal.}
proc threadPollFinished*(worker: ThreadPollWorker, value: int) {.signal.}

proc processThreadPoll(worker: ThreadPollWorker, value: int) {.slot.} =
  emit worker.threadPollFinished(value)

proc collectThreadPoll(collector: ThreadPollCollector, value: int) {.slot.} =
  collector.value = value

type
  MenuSpyTarget = ref object of View
  AppDelegateSpy = ref object of Responder
  WindowDelegateSpy = ref object of Responder

var
  windowHookEvents: seq[string]
  windowHookAllowContentView: bool
  windowHookAllowFirstResponder: bool
  windowHookAllowDismiss: bool
  menuSpyEvents: seq[string]
  menuSpyValidate: bool
  appDelegateEvents: seq[string]
  appTerminateReply: TerminationReply
  windowDelegateEvents: seq[string]
  windowDelegateShouldClose: bool

protocol WindowLifecycleSpyHooks of WindowLifecycleProtocol:
  method shouldSetContentView(window: Window, view: View): bool =
    windowHookEvents.add "shouldContentView"
    windowHookAllowContentView

protocol WindowFocusSpyHooks of WindowFocusProtocol:
  method shouldMakeFirstResponder(window: Window, responder: Responder): bool =
    windowHookEvents.add "shouldFirstResponder"
    windowHookAllowFirstResponder

protocol WindowPopupSpyHooks of WindowPopupProtocol:
  method shouldDismiss(window: Window, reason: DismissReason): bool =
    windowHookEvents.add "shouldDismiss"
    windowHookAllowDismiss

protocol WindowLifecycleObserverEvents of WindowLifecycleEvents:
  proc willSetContentView(observer: WindowHookObserver, view: View) {.slot.} =
    windowHookEvents.add "willContentView"

  proc didSetContentView(observer: WindowHookObserver, oldView: View) {.slot.} =
    windowHookEvents.add "didContentView"

protocol WindowFocusObserverEvents of WindowFocusEvents:
  proc didChangeFirstResponder(
      observer: WindowHookObserver, previous: Responder
  ) {.slot.} =
    windowHookEvents.add "didFirstResponder"

protocol WindowAppearanceObserverEvents of WindowAppearanceEvents:
  proc didChangeEffectiveAppearance(
      observer: WindowHookObserver, appearance: Appearance
  ) {.slot.} =
    windowHookEvents.add "didAppearance"

protocol WindowPopupObserverEvents of WindowPopupEvents:
  proc didDismissTransientSession(
      observer: WindowHookObserver, reason: DismissReason
  ) {.slot.} =
    windowHookEvents.add "didDismiss"

  proc didChangePopupPresentation(
      observer: WindowHookObserver, presentation: PopupPresentation
  ) {.slot.} =
    windowHookEvents.add "didPopupPresentation"

protocol MenuSpyActionProtocol:
  method menuSpyAction*(args: ActionArgs) {.optional.}

protocol MenuSpyActions of MenuSpyActionProtocol:
  method menuSpyAction(target: MenuSpyTarget, args: ActionArgs) =
    menuSpyEvents.add "action"

protocol MenuSpyValidation of UserInterfaceValidations:
  method validateUserInterfaceItem(target: MenuSpyTarget, args: ValidationArgs): bool =
    menuSpyEvents.add "validate:" & MenuItem(args.item).title
    menuSpyValidate

protocol AppDelegateSpyProtocol of ApplicationDelegateProtocol:
  method appWillFinishLaunching(delegate: AppDelegateSpy, app: DynamicAgent) =
    appDelegateEvents.add "willLaunch"

  method appDidFinishLaunching(delegate: AppDelegateSpy, app: DynamicAgent) =
    appDelegateEvents.add "didLaunch"

  method appDidBecomeActive(delegate: AppDelegateSpy, app: DynamicAgent) =
    appDelegateEvents.add "active"

  method appDidResignActive(delegate: AppDelegateSpy, app: DynamicAgent) =
    appDelegateEvents.add "inactive"

  method appWillHide(delegate: AppDelegateSpy, app: DynamicAgent) =
    appDelegateEvents.add "willHide"

  method appDidHide(delegate: AppDelegateSpy, app: DynamicAgent) =
    appDelegateEvents.add "didHide"

  method appWillUnhide(delegate: AppDelegateSpy, app: DynamicAgent) =
    appDelegateEvents.add "willUnhide"

  method appDidUnhide(delegate: AppDelegateSpy, app: DynamicAgent) =
    appDelegateEvents.add "didUnhide"

  method appShouldTerminate(
      delegate: AppDelegateSpy, app: DynamicAgent
  ): TerminationReply =
    appDelegateEvents.add "shouldTerminate"
    appTerminateReply

  method appWillTerminate(delegate: AppDelegateSpy, app: DynamicAgent) =
    appDelegateEvents.add "willTerminate"

protocol WindowDelegateSpyProtocol of WindowDelegateProtocol:
  method windowShouldClose(delegate: WindowDelegateSpy, window: Window): bool =
    windowDelegateEvents.add "shouldClose"
    windowDelegateShouldClose

  method windowWillClose(delegate: WindowDelegateSpy, window: Window) =
    windowDelegateEvents.add "willClose"

  method windowDidClose(delegate: WindowDelegateSpy, window: Window) =
    windowDelegateEvents.add "didClose"

  method windowDidBecomeKey(delegate: WindowDelegateSpy, window: Window) =
    windowDelegateEvents.add "key"

  method windowDidBecomeMain(delegate: WindowDelegateSpy, window: Window) =
    windowDelegateEvents.add "main"

  method windowWillBeginSheet(delegate: WindowDelegateSpy, sheet: Window) =
    windowDelegateEvents.add "willSheet:" & sheet.title

  method windowDidEndSheet(delegate: WindowDelegateSpy, sheet: Window) =
    windowDelegateEvents.add "didSheet:" & sheet.title

suite "nimkit application":
  test "standard application menus include commands and preserve window entries":
    let app = newApplication("Menu Test")
    app.installStandardMainMenu()

    let mainMenu = app.mainMenu()
    check mainMenu.len == 5
    check mainMenu[0].title == "Menu Test"
    check mainMenu[1].title == "File"
    check mainMenu[2].title == "Edit"
    check mainMenu[3].title == "Window"
    check mainMenu[4].title == "Help"

    let
      applicationMenu = mainMenu[0].submenu()
      quitItem = applicationMenu[applicationMenu.len - 1]
    check quitItem.title == "Quit Menu Test"
    check quitItem.action().name == actionSelector("terminate").name
    check quitItem.keyEquivalent().modifiers == shortcutModifiers()

    let windowMenu = app.windowsMenu()
    check windowMenu == mainMenu[3].submenu()
    check windowMenu.len == 5
    check windowMenu[0].title == "Minimize"
    check windowMenu[1].title == "Zoom"
    check windowMenu[2].isSeparatorItem()
    check windowMenu[3].title == "Merenda Settings"
    check windowMenu[3].action().name == actionSelector("showMerendaSettings").name
    check windowMenu[3].target() == app
    check windowMenu[4].isSeparatorItem()

    let window = newWindow("Standard Menu Window")
    app.addWindow(window)
    check windowMenu.len == 6
    check windowMenu[5].title == "Standard Menu Window"

    let quitEvent =
      KeyEvent(key: keyQ, keyCode: keyQ.ord, modifiers: shortcutModifiers())
    check mainMenu.findKeyEquivalentItem(quitEvent) == quitItem
    check quitItem.enabled()
    check quitItem.validate(Responder(app))
    check app.performMenuKeyEquivalent(quitEvent)
    check app.isTerminating

  test "Merenda Settings menu command opens and closes its panel":
    let app = newApplication("Settings Menu Test")
    app.installStandardMainMenu()

    let settingsItem = app.windowsMenu()[3]
    check settingsItem.perform(Responder(app))
    check app.windows.len == 1
    let settingsPanel = app.windows[0]
    check settingsPanel.title == "Merenda Settings"
    check settingsPanel.isVisible

    settingsPanel.close()
    check settingsPanel.isClosed

  test "window protocols observe and veto core window behavior":
    let
      window = newWindow("Window hooks", frame = rect(0, 0, 240, 160))
      root = newView(frame = rect(0, 0, 240, 160))
      replacement = newView(frame = rect(0, 0, 240, 160))
      button = newButton("Focus", frame = rect(16, 16, 90, 32))
      observer = WindowHookObserver()

    windowHookEvents = @[]
    windowHookAllowContentView = false
    windowHookAllowFirstResponder = false
    windowHookAllowDismiss = false
    discard window.withProtocol(WindowLifecycleSpyHooks)
    discard window.withProtocol(WindowFocusSpyHooks)
    discard window.withProtocol(WindowPopupSpyHooks)
    observer.observeProtocol(window, WindowLifecycleEvents)
    observer.observeProtocol(window, WindowFocusEvents)
    observer.observeProtocol(window, WindowAppearanceEvents)
    observer.observeProtocol(window, WindowPopupEvents)

    window.setContentView(root)
    check window.contentView.isNil
    check windowHookEvents == @["shouldContentView"]

    windowHookEvents = @[]
    windowHookAllowContentView = true
    window.setContentView(root)
    check window.contentView == root
    check windowHookEvents == @[
      "shouldContentView", "willContentView", "didContentView"
    ]

    root.addSubview(button)
    windowHookEvents = @[]
    check not window.makeFirstResponder(button)
    check window.firstResponder.isNil
    check windowHookEvents == @["shouldFirstResponder"]

    windowHookEvents = @[]
    windowHookAllowFirstResponder = true
    check window.makeFirstResponder(button)
    check window.firstResponder == button
    check windowHookEvents == @["shouldFirstResponder", "didFirstResponder"]

    windowHookEvents = @[]
    window.setContentView(replacement)
    check window.contentView == replacement
    check window.firstResponder.isNil
    check windowHookEvents ==
      @[
        "shouldContentView", "willContentView", "shouldFirstResponder",
        "didFirstResponder", "didContentView",
      ]

    windowHookEvents = @[]
    window.setAppearance(initAppearance())
    check windowHookEvents == @["didAppearance"]

    windowHookEvents = @[]
    window.setPopupPresentation(ppInline)
    check window.popupPresentation == ppInline
    check windowHookEvents == @["didPopupPresentation"]

    window.beginTransientSession(owner = window)
    windowHookEvents = @[]
    check not window.dismissTransientSession(tdrProgrammatic)
    check window.hasActiveTransientSession()
    check windowHookEvents == @["shouldDismiss"]

    windowHookEvents = @[]
    windowHookAllowDismiss = true
    check window.dismissTransientSession(tdrProgrammatic)
    check not window.hasActiveTransientSession()
    check windowHookEvents == @["shouldDismiss", "didDismiss"]

  test "nil-target actions dispatch through window app and app delegate":
    let
      app = newApplication()
      window = newWindow("Action chain", frame = rect(0, 0, 240, 160))
      root = newView(frame = rect(0, 0, 240, 160))
      button = newButton("Run", frame = rect(20, 20, 90, 32))
      action = actionSelector("appDelegateAction")

    var
      actionCount = 0
      actionSender: DynamicAgent

    proc onAction(sender: DynamicAgent) =
      inc actionCount
      actionSender = sender

    let delegate = newActionTarget(action, onAction)
    app.delegate = delegate
    button.action = action
    root.addSubview(button)
    window.setContentView(root)
    app.addWindow(window)

    check button.sendAction()
    check actionCount == 1
    check actionSender == DynamicAgent(button)

  test "showWindow installs content selects key view and activates window":
    let
      app = newApplication()
      window = newWindow("Show Window", frame = rect(0, 0, 240, 160))
      root = newView(frame = rect(0, 0, 240, 160))
      focusView = newView(frame = rect(20, 20, 120, 32))

    focusView.acceptsFirstResponder = true
    root.addSubview(focusView)

    check app.showWindow(window, root) == window
    check window.contentView == root
    check window.firstResponder == Responder(focusView)
    check window.isVisible
    check window.isKeyWindow
    check window.isMainWindow
    check app.keyWindow == window
    check app.mainWindow == window
    check app.windows.len == 1

    let
      explicitWindow = newWindow("Explicit Focus", frame = rect(0, 0, 240, 160))
      explicitRoot = newView(frame = rect(0, 0, 240, 160))
      firstView = newView(frame = rect(20, 20, 80, 32))
      explicitFocus = newView(frame = rect(20, 64, 80, 32))

    firstView.acceptsFirstResponder = true
    explicitFocus.acceptsFirstResponder = true
    explicitRoot.addSubview(firstView)
    explicitRoot.addSubview(explicitFocus)

    check app.showWindow(explicitWindow, explicitRoot, explicitFocus) == explicitWindow
    check explicitWindow.firstResponder == Responder(explicitFocus)
    check app.keyWindow == explicitWindow
    check app.windows.len == 2

  test "window key commands continue through application delegate":
    let
      app = newApplication()
      window = newWindow("Command chain", frame = rect(0, 0, 240, 160))
      root = newView(frame = rect(0, 0, 240, 160))
      child = newView(frame = rect(20, 20, 80, 32))
      action = actionSelector("appDelegateCommand")

    var
      actionCount = 0
      actionSender: DynamicAgent

    proc onAction(sender: DynamicAgent) =
      inc actionCount
      actionSender = sender

    child.acceptsFirstResponder = true
    root.addSubview(child)
    window.setContentView(root)
    window.bindKey("k", {kmCommand}, action)
    app.delegate = newActionTarget(action, onAction)
    app.addWindow(window)

    check window.makeFirstResponder(child)
    check window.dispatchKeyDown(
      KeyEvent(key: keyK, keyCode: keyK.ord, modifiers: {kmCommand})
    )
    check actionCount == 1
    check actionSender == DynamicAgent(child)

  test "main menu validates items and dispatches key equivalents through action chain":
    let
      app = newApplication()
      window = newWindow("Menu dispatch", frame = rect(0, 0, 240, 160))
      root = newView(frame = rect(0, 0, 240, 160))
      target = MenuSpyTarget()
      menu = newMenu("Main")
      item = newMenuItem("Do Thing", actionSelector("menuSpyAction"), "d", {kmCommand})

    initViewFields(target, rect(10, 10, 80, 30))
    discard target.withProtocol(MenuSpyActions)
    discard target.withProtocol(MenuSpyValidation)
    target.acceptsFirstResponder = true

    menuSpyEvents = @[]
    menuSpyValidate = true
    root.addSubview(target)
    window.setContentView(root)
    app.addWindow(window)
    app.mainMenu = menu
    discard menu.addItem(item)

    check window.makeFirstResponder(target)
    menu.update(target)
    check item.enabled
    check menuSpyEvents == @["validate:Do Thing"]

    menuSpyEvents = @[]
    check window.dispatchKeyDown(
      KeyEvent(key: keyD, keyCode: keyD.ord, modifiers: {kmCommand})
    )
    check menuSpyEvents == @["validate:Do Thing", "action"]

    menuSpyEvents = @[]
    menuSpyValidate = false
    menu.update(target)
    check not item.enabled
    check not window.dispatchKeyDown(
      KeyEvent(key: keyD, keyCode: keyD.ord, modifiers: {kmCommand})
    )
    check menuSpyEvents == @["validate:Do Thing"]

  test "application lifecycle state and modal sessions are first-class":
    let
      app = newApplication()
      delegate = AppDelegateSpy()
      window = newWindow("Modal", frame = rect(0, 0, 240, 160))

    initResponder(delegate)
    discard delegate.withProtocol(AppDelegateSpyProtocol)
    app.delegate = delegate
    app.addWindow(window)

    appDelegateEvents = @[]
    appTerminateReply = trLater
    app.finishLaunching()
    app.activate()
    app.deactivate()
    app.hide()
    app.unhide()
    check appDelegateEvents ==
      @[
        "willLaunch", "didLaunch", "active", "inactive", "willHide", "didHide",
        "willUnhide", "didUnhide",
      ]
    check not app.isHidden

    let session = app.beginModalSession(window)
    check app.modalSession == session
    check app.keyWindow == window
    app.stopModal(42)
    check session.state == mssStopped
    check session.response == 42
    app.endModalSession(session)
    check app.modalSession.isNil

    appDelegateEvents = @[]
    check app.terminate() == trLater
    check app.isTerminating
    check appDelegateEvents == @["shouldTerminate"]
    app.replyToApplicationShouldTerminate(true)
    check appDelegateEvents == @["shouldTerminate", "willTerminate"]

  test "application keeps ordered windows and hands off key main state":
    let
      app = newApplication()
      first = newWindow("First", frame = rect(0, 0, 240, 160))
      second = newWindow("Second", frame = rect(20, 20, 240, 160))
      third = newWindow("Third", frame = rect(40, 40, 240, 160))

    app.addWindow(first)
    app.addWindow(second)
    app.addWindow(third)

    check app.orderedWindows.len == 3
    check app.orderedWindows[0] == first
    check app.orderedWindows[1] == second
    check app.orderedWindows[2] == third

    app.activateWindow(second)
    check app.keyWindow == second
    check app.mainWindow == second
    check second.isKeyWindow
    check app.orderedWindows[0] == second

    third.orderFront()
    check third.isVisible
    check app.orderedWindows[0] == third
    check app.keyWindow == second
    check not third.isKeyWindow

    third.makeKeyAndOrderFront()
    check app.keyWindow == third
    check app.mainWindow == third
    check third.isKeyWindow

    second.orderBack()
    check app.orderedWindows[^1] == second
    check app.keyWindow == third

    third.orderOut()
    check not third.isVisible
    check app.keyWindow == second
    check app.mainWindow == second
    check not third.isKeyWindow

    second.close()
    check second.isClosed
    check app.keyWindow.isNil
    check app.mainWindow.isNil
    check app.orderedWindows.len == 2
    check second notin app.orderedWindows

  test "window commands validate style and update pure state":
    let
      app = newApplication()
      window = newWindow("Commands", frame = rect(0, 0, 240, 160))
      closeItem = newMenuItem("Close", actionSelector("performClose"))
      miniaturizeItem = newMenuItem("Minimize", actionSelector("performMiniaturize"))
      zoomItem = newMenuItem("Zoom", actionSelector("performZoom"))

    app.addWindow(window)
    app.activateWindow(window)

    check closeItem.validate(Responder(window))
    check miniaturizeItem.validate(Responder(window))
    check zoomItem.validate(Responder(window))

    check miniaturizeItem.perform(Responder(window))
    check window.isMiniaturized
    check not window.isVisible
    check app.keyWindow.isNil
    check not miniaturizeItem.validate(Responder(window))

    window.deminiaturize()
    check not window.isMiniaturized
    check window.isVisible

    check zoomItem.perform(Responder(window))
    check window.isZoomed
    check zoomItem.perform(Responder(window))
    check not window.isZoomed

    window.styleMask = {wsmTitled}
    check not closeItem.validate(Responder(window))
    check not miniaturizeItem.validate(Responder(window))
    check not zoomItem.validate(Responder(window))
    check not closeItem.perform(Responder(window))
    check not window.isClosed

    window.styleMask = {wsmTitled, wsmClosable}
    check closeItem.perform(Responder(window))
    check window.isClosed

  test "modal blocking and termination replies have pure query contracts":
    let
      app = newApplication()
      delegate = AppDelegateSpy()
      first = newWindow("First", frame = rect(0, 0, 240, 160))
      second = newWindow("Second", frame = rect(20, 20, 240, 160))
      sheet = newPanel("Sheet", frame = rect(40, 40, 200, 120))

    initResponder(delegate)
    discard delegate.withProtocol(AppDelegateSpyProtocol)
    app.delegate = delegate
    app.addWindow(first)
    app.addWindow(second)

    let appModal = app.beginModalSession(second)
    check app.windowBlockedByModal(first)
    check not app.windowBlockedByModal(second)
    check app.terminate() == trLater
    app.endModalSession(appModal)

    let sheetModal = app.beginModalSheet(first, sheet)
    check app.windowBlockedByModal(first)
    check not app.windowBlockedByModal(second)
    check not app.windowBlockedByModal(sheet)
    app.endModalSession(sheetModal)

    appDelegateEvents = @[]
    appTerminateReply = trCancel
    check app.terminate() == trCancel
    check not app.isTerminating
    check appDelegateEvents == @["shouldTerminate"]

    appTerminateReply = trLater
    check app.terminate() == trLater
    check app.isTerminating
    app.replyToApplicationShouldTerminate(false)
    check not app.isTerminating

  test "window roles metadata delegates coordinates and sheets":
    let
      window = newWindow("Owner", frame = rect(20, 30, 240, 160))
      sheet = newPanel("Sheet", frame = rect(40, 50, 180, 120))
      delegate = WindowDelegateSpy()
      content = newView(frame = rect(10, 15, 100, 80))

    initResponder(delegate)
    discard delegate.withProtocol(WindowDelegateSpyProtocol)
    windowDelegateEvents = @[]
    windowDelegateShouldClose = false
    window.delegate = delegate
    window.setContentView(content)

    window.makeKeyAndOrderFront()
    check window.isKeyWindow
    check window.isMainWindow
    check windowDelegateEvents == @["key", "main"]

    window.styleMask = {wsmTitled, wsmClosable}
    window.level = wlFloating
    window.minSize = initSize(120, 80)
    window.maxSize = initSize(500, 400)
    window.resizeIncrements = initSize(10, 10)
    window.frameAutosaveName = "owner-frame"
    check window.styleMask == {wsmTitled, wsmClosable}
    check window.level == wlFloating
    check window.minSize == initSize(120, 80)
    check window.maxSize == initSize(500, 400)
    check window.resizeIncrements == initSize(10, 10)
    check window.frameAutosaveName == "owner-frame"

    check window.convertPointToScreen(initPoint(1, 2)) == initPoint(21, 32)
    check window.convertPointFromScreen(initPoint(21, 32)) == initPoint(1, 2)
    check window.convertPointToContent(initPoint(10, 15)) == initPoint(10, 15)
    check window.convertPointFromContent(initPoint(0, 0)) == initPoint(0, 0)

    window.beginSheet(sheet)
    check window.attachedSheet == sheet
    check sheet.sheetParent == window
    window.endSheet()
    check window.attachedSheet.isNil
    check sheet.sheetParent.isNil
    check windowDelegateEvents[^2 .. ^1] == @["willSheet:Sheet", "didSheet:Sheet"]

    window.close()
    check not window.isClosed
    windowDelegateShouldClose = true
    window.close()
    check window.isClosed
    check windowDelegateEvents[^3 .. ^1] == @["shouldClose", "willClose", "didClose"]

    let
      alert = newAlert("Replace file?", "This cannot be undone.", asWarning)
      openPanel = newOpenPanel()
      savePanel = newSavePanel()
    check alert.window.level == wlFloating
    check alert.buttons == @["OK"]
    check openPanel.canChooseFiles
    check savePanel.window.title == "Save"

  test "window content minimum size constrains programmatic resizing":
    let window = newWindow("Minimum", frame = rect(0, 0, 240, 160))

    window.minSize = initSize(100, 70)
    window.contentMinSize = initSize(140, 90)
    window.frame = rect(10, 20, 40, 30)

    check window.minSize == initSize(100, 70)
    check window.contentMinSize == initSize(140, 90)
    check window.frame == rect(10, 20, 140, 90)

  test "window can derive its content minimum from constrained layout":
    let
      window = newWindow("Automatic minimum", frame = rect(0, 0, 80, 60))
      root = newView()
      stack = newStackView(laVertical)
      button = newButton("Initial setting")

    stack.addArrangedSubview(button)
    root.addSubview(stack)
    discard stack.pinEdges(
      toGuide = root.contentLayoutGuide(insets(12.0, 18.0)),
      edges = {leLeft, leTop, leRight, leBottom},
    )
    window.automaticallyAdjustsContentMinSize = true
    window.setContentView(root)

    let initialMinimum = root.fittingSize()
    check window.contentMinSize == initialMinimum
    check window.frame.size.width >= initialMinimum.width
    check window.frame.size.height >= initialMinimum.height

    window.frame = rect(0, 0, 1, 1)
    check window.frame.size == initialMinimum

    let initialGeneration = root.layoutInputGeneration()
    button.title =
      "A substantially longer setting that increases the required window width"
    check root.layoutInputGeneration() == initialGeneration

    let updatedMinimum = window.contentMinSize()
    check root.layoutInputGeneration() == initialGeneration + 1
    check updatedMinimum.width > initialMinimum.width
    check window.frame.size.width == updatedMinimum.width

  test "panels build reusable pure Nim views and validate selections":
    let
      alert = newAlert(
        "Replace file?", "This cannot be undone.", asWarning, ["Replace", "Cancel"]
      )
      accessory = newView(frame = rect(0, 0, 40, 20))

    var alertResponse = -1
    alert.setAccessoryView(accessory)
    check alert.setButtonResponse(0, 42)
    alert.prepareForModal(
      proc(response: int) =
        alertResponse = response
    )

    check alert.contentView() == alert.window.contentView
    check accessory.superview() != nil
    check alert.buttonViews.len == 2
    check Button(alert.buttonViews[0]).title == "Replace"
    check Button(alert.buttonViews[0]).tryToPerform(
      performClick(), DynamicAgent(alert.buttonViews[0])
    )
    check alert.response == 42
    check alertResponse == 42

    let openPanel = newOpenPanel()
    openPanel.allowedFileTypes = @["txt", "md"]
    openPanel.selectUrl("file:///tmp/Notes.txt")
    check openPanel.validateSelection()
    check openPanel.contentView() == openPanel.window.contentView
    check openPanel.buttonViews.len == 2
    check Button(openPanel.buttonViews[0]).enabled

    openPanel.selectUrl("file:///tmp/Image.png")
    check not openPanel.validateSelection()
    discard openPanel.rebuildOpenPanelView()
    check not Button(openPanel.buttonViews[0]).enabled
    TextField(openPanel.urlField).text = "file:///tmp/Fixed.md"
    check Button(openPanel.buttonViews[0]).enabled

    openPanel.selectUrls(["file:///tmp/A.txt", "file:///tmp/B.md"])
    check not openPanel.validateSelection()
    openPanel.allowsMultipleSelection = true
    check openPanel.validateSelection()

    let savePanel = newSavePanel()
    savePanel.directoryUrl = "file:///tmp"
    savePanel.allowedFileTypes = @["md"]
    savePanel.nameFieldStringValue = "Report"
    check savePanel.selectedFileType() == "md"
    check savePanel.selectedUrl() == "file:///tmp/Report.md"
    check savePanel.validateSelection()
    check savePanel.contentView() == savePanel.window.contentView
    check savePanel.buttonViews.len == 2
    check Button(savePanel.buttonViews[0]).enabled

    TextField(savePanel.nameField).text = "Report.txt"
    check not savePanel.validateSelection()
    discard savePanel.rebuildSavePanelView()
    check not Button(savePanel.buttonViews[0]).enabled
    TextField(savePanel.nameField).text = "Report"
    check Button(savePanel.buttonViews[0]).enabled

    var saveResponse = -1
    savePanel.prepareForModal(
      proc(response: int) =
        saveResponse = response
    )
    check Button(savePanel.buttonViews[0]).tryToPerform(
      performClick(), DynamicAgent(savePanel.buttonViews[0])
    )
    check savePanel.response == PanelResponseOk
    check saveResponse == PanelResponseOk

  test "popup menu button opens menu popup and activates items":
    let
      window = newWindow("Popup Menu", frame = rect(0, 0, 320, 180))
      root = newView(frame = rect(0, 0, 320, 180))
      bar = newView(frame = rect(0, 0, 320, 28))
      menu = newMenu("Actions")
      action = actionSelector("popupMenuAction")
      item = newMenuItem("Run", action)
      button = newPopupMenuButton("Actions", menu, rect(8, 2, 80, 24))

    var actionCount = 0

    proc onAction(sender: DynamicAgent) =
      check sender == DynamicAgent(button)
      inc actionCount

    item.target = newActionTarget(action, onAction)
    discard menu.addItem(item)
    button.popupPresentation = ppInline
    bar.addSubview(button)
    root.addSubview(bar)
    window.setContentView(root)

    check not button.popupOpen
    check window.clickAt(initPoint(16, 12))
    check button.popupOpen

    check window.clickAt(initPoint(16, 38))
    check actionCount == 1
    check not button.popupOpen

  test "popup menus skip disabled rows render states and navigate submenus":
    let
      window = newWindow("Popup Menu Keyboard", frame = rect(0, 0, 360, 220))
      root = newView(frame = rect(0, 0, 360, 220))
      menu = newMenu("Actions")
      submenu = newMenu("More")
      disabled = newMenuItem("Disabled", actionSelector("disabledAction"))
      checked = newMenuItem("Checked")
      mixed = newMenuItem("Mixed")
      more = newMenuItem("More")
      leafAction = actionSelector("leafMenuAction")
      leaf = newMenuItem("Leaf", leafAction)
      button = newPopupMenuButton("Actions", menu, rect(8, 2, 90, 24))

    var actionCount = 0

    proc onLeaf(sender: DynamicAgent) =
      inc actionCount

    disabled.enabled = false
    checked.state = bsOn
    mixed.state = bsMixed
    leaf.target = newActionTarget(leafAction, onLeaf)
    discard submenu.addItem(leaf)
    more.submenu = submenu
    discard menu.addItem(disabled)
    discard menu.addSeparator()
    discard menu.addItem(checked)
    discard menu.addItem(mixed)
    discard menu.addItem(more)

    button.popupPresentation = ppInline
    root.addSubview(button)
    window.setContentView(root)
    button.openPopup()

    check button.popupOpen
    check button.highlightedIndex == 2

    let renders = window.buildRenders()
    var
      checkedMarkFound = false
      mixedMarkFound = false

    for node in renders[PopupDrawLevel].nodes:
      if node.kind == nkText:
        if node.renderedText() == "✓":
          checkedMarkFound = true
        elif node.renderedText() == "-":
          mixedMarkFound = true

    check checkedMarkFound
    check mixedMarkFound

    check button.dispatchPopupKeyDown(KeyEvent(key: keyArrowDown))
    check button.highlightedIndex == 3
    check button.dispatchPopupKeyDown(KeyEvent(key: keyArrowDown))
    check button.highlightedIndex == 4
    check button.dispatchPopupKeyDown(KeyEvent(key: keyArrowRight))
    let child = button.activeSubmenuButton()
    check not child.isNil
    check child.popupOpen
    check child.highlightedIndex == 0

    check child.dispatchPopupKeyDown(KeyEvent(key: keyEnter))
    check actionCount == 1
    check not button.popupOpen

  test "cascading view moves through columns from user input":
    let
      window = newWindow("Cascading Input", frame = rect(0, 0, 420, 220))
      root = newView(frame = rect(0, 0, 420, 220))
      browser = newCascadingView(frame = rect(10, 10, 360, 160))

    browser.cascadingItems = [
      cascadeItem("project", "Project"),
      cascadeItem("notes", "Notes", leaf = true),
      cascadeItem("src", "src", parentIdentifier = "project"),
      cascadeItem("tests", "tests", parentIdentifier = "project", leaf = true),
      cascadeItem("main", "main.nim", parentIdentifier = "src", leaf = true),
    ]
    root.addSubview(browser)
    window.setContentView(root)
    discard window.buildRenders()

    let firstColumn = browser.tableViewForColumn(0)
    check window.clickTableRow(firstColumn, 0)
    check window.firstResponder == firstColumn
    check firstColumn.selectedIndex == 0
    check browser.selectedPath == @["project"]
    check browser.columnCount == 2
    check firstColumn.scrollView().contentOffset().x == 0.0'f32
    check browser.scrollView().contentOffset().x == 0.0'f32

    let projectTextX = window.renderedTextX("Project")
    check projectTextX >= 0.0'f32
    check window.pressKey(keyArrowDown)
    check firstColumn.selectedIndex == 1
    check browser.selectedPath == @["notes"]
    check browser.columnCount == 1
    check firstColumn.scrollView().contentOffset().x == 0.0'f32
    check window.renderedTextX("Project") == projectTextX

    check window.pressKey(keyArrowUp)
    check firstColumn.selectedIndex == 0
    check browser.selectedPath == @["project"]
    check browser.columnCount == 2
    check firstColumn.scrollView().contentOffset().x == 0.0'f32
    check window.renderedTextX("Project") == projectTextX

    let secondColumn = browser.tableViewForColumn(1)
    check window.pressKey(keyArrowRight)
    check window.firstResponder == secondColumn
    check secondColumn.selectedIndex == 0
    check browser.selectedPath == @["project", "src"]
    check browser.columnCount == 3
    check browser.scrollView().contentOffset().x > 0.0'f32

    check window.pressKey(keyArrowLeft)
    check window.firstResponder == firstColumn
    check secondColumn.selectedIndex == -1
    check browser.selectedPath == @["project"]
    check browser.columnCount == 2
    check browser.scrollView().contentOffset().x == 0.0'f32

    check window.doubleClickTableRow(firstColumn, 0)
    check not firstColumn.editingState.active
    check window.pressKey(keyEnter)
    check not firstColumn.editingState.active

  test "menu bar presents top-level menu submenus":
    let
      window = newWindow("Menu Bar", frame = rect(0, 0, 320, 180))
      root = newView(frame = rect(0, 0, 320, 180))
      mainMenu = newMenu("Main")
      actionsMenu = newMenu("Actions")
      actionsItem = newMenuItem("Actions")
      action = actionSelector("menuBarAction")
      item = newMenuItem("Run", action)
      menuBar = newMenuBar(mainMenu, rect(0, 0, 320, 28))

    var actionCount = 0

    proc onAction(sender: DynamicAgent) =
      inc actionCount

    item.target = newActionTarget(action, onAction)
    actionsItem.submenu = actionsMenu
    discard actionsMenu.addItem(item)
    discard mainMenu.addItem(actionsItem)
    menuBar.reload()
    window.setPopupPresentation(ppInline)
    root.addSubview(menuBar)
    window.setContentView(root)
    root.layoutSubtreeIfNeeded()

    check window.clickAt(initPoint(18, 12))
    check PopupDrawLevel in window.buildRenders().layers

    check window.clickAt(initPoint(18, 38))
    check actionCount == 1

  test "menu bar highlights top-level items on mouse hover":
    let
      window = newWindow("Menu Bar Hover", frame = rect(0, 0, 320, 180))
      root = newView(frame = rect(0, 0, 320, 180))
      mainMenu = newMenu("Main")
      actionsMenu = newMenu("Actions")
      actionsItem = newMenuItem("Actions")
      menuBar = newMenuBar(mainMenu, rect(0, 0, 320, 28))

    actionsItem.submenu = actionsMenu
    discard mainMenu.addItem(actionsItem)
    menuBar.reload()
    root.addSubview(menuBar)
    window.setContentView(root)
    root.layoutSubtreeIfNeeded()

    check window.mouseMovedAt(initPoint(18, 12))

    let renders = window.buildRenders()
    var hoverFound = false
    for node in renders[DefaultDrawLevel].nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == color(0.76, 0.81, 0.91).rgba:
        hoverFound = true

    check hoverFound

  test "menu bar hover switches the open top-level menu":
    let
      window = newWindow("Menu Bar Switch", frame = rect(0, 0, 360, 180))
      root = newView(frame = rect(0, 0, 360, 180))
      mainMenu = newMenu("Main")
      actionsMenu = newMenu("Actions")
      editMenu = newMenu("Edit")
      actionsItem = newMenuItem("Actions")
      editItem = newMenuItem("Edit")
      menuBar = newMenuBar(mainMenu, rect(0, 0, 360, 28))

    actionsItem.submenu = actionsMenu
    editItem.submenu = editMenu
    discard actionsMenu.addItem(newMenuItem("Run"))
    discard editMenu.addItem(newMenuItem("Copy"))
    discard mainMenu.addItem(actionsItem)
    discard mainMenu.addItem(editItem)
    menuBar.reload()
    root.addSubview(menuBar)
    window.setContentView(root)
    root.layoutSubtreeIfNeeded()

    let
      first = PopupMenuButton(menuBar.subviews[0])
      second = PopupMenuButton(menuBar.subviews[1])

    check window.clickAt(first.frame.origin.offset(6.0, 8.0))
    check first.popupOpen
    check not second.popupOpen

    check window.mouseMovedAt(second.frame.origin.offset(6.0, 8.0))
    check not first.popupOpen
    check second.popupOpen

  test "windows menu modal sheets hide restore and autosave integrate with app":
    let
      app = newApplication()
      first = newWindow("First", frame = rect(10, 20, 240, 160))
      second = newWindow("Second", frame = rect(30, 40, 260, 180))
      sheet = newPanel("Sheet", frame = rect(40, 50, 180, 120))
      windowsMenu = newMenu("Window")

    app.addWindow(first)
    app.addWindow(second)
    app.windowsMenu = windowsMenu

    check windowsMenu.len == 2
    check windowsMenu[0].title == "First"
    check windowsMenu[0].state == bsOn
    check windowsMenu[1].state == bsOff

    app.activateWindow(second)
    check app.keyWindow == second
    check app.mainWindow == second
    check windowsMenu[1].state == bsOn

    check windowsMenu[0].perform(Responder(app))
    check app.keyWindow == first
    check app.mainWindow == first

    first.makeKeyAndOrderFront()
    check first.isVisible
    app.hide()
    check not first.isVisible
    app.unhide()
    check first.isVisible

    let session = app.beginModalSheet(first, sheet)
    check app.modalSession == session
    check session.mode == msmWindowModal
    check first.attachedSheet == sheet
    check app.windowBlockedByModal(first)
    check not app.windowBlockedByModal(sheet)
    check app.terminate() == trLater
    app.stopModal(7)
    check app.runModalSession(session) == 7
    app.endModalSession(session)
    check first.attachedSheet.isNil
    check app.modalSession.isNil

    first.frameAutosaveName = "tnimkit-application-first"
    first.frame = rect(70, 80, 300, 210)
    check first.saveFrameUsingName()
    let restored = newWindow("Restored", frame = rect(0, 0, 120, 90))
    restored.frameAutosaveName = "tnimkit-application-first"
    check restored.frame == rect(70, 80, 300, 210)
    check removeSavedFrameForName("tnimkit-application-first")

  test "raw mouse input converts from reported input size to logical size":
    let logicalSize = siwinshim.vec2(360.0'f32, 220.0'f32)

    check rawInputToLogical(
      siwinshim.vec2(72.0'f32, 108.0'f32),
      siwinshim.ivec2(360'i32, 220'i32),
      logicalSize,
    ) == siwinshim.vec2(72.0'f32, 108.0'f32)
    check rawInputToLogical(
      siwinshim.vec2(108.0'f32, 162.0'f32),
      siwinshim.ivec2(540'i32, 330'i32),
      logicalSize,
    ) == siwinshim.vec2(72.0'f32, 108.0'f32)

  test "application frames deliver threaded Sigils results":
    let
      app = newApplication()
      dispatcher = ThreadPollDispatcher()
      collector = ThreadPollCollector()
      pool = newSigilThreadPool(workers = 1)
    pool.start()
    var worker = ThreadPollWorker()
    let workerProxy = worker.moveToThread(pool)
    connectThreaded(dispatcher, threadPollRequested, workerProxy, processThreadPoll)
    connectThreaded(
      workerProxy,
      threadPollFinished,
      collector,
      ThreadPollCollector.collectThreadPoll(),
    )

    try:
      emit dispatcher.threadPollRequested(42)
      for _ in 0 ..< 1_000:
        discard app.runForFrames(1)
        if collector.value == 42:
          break
        sleep(1)
      check collector.value == 42
    finally:
      pool.stop()
      pool.join()

  test "runForFrames opens and pumps a visible native window":
    block nativeRun:
      let
        app = newApplication()
        window = newWindow("Nimkit Native Test", frame = rect(80, 80, 240, 140))
        root = newView(frame = rect(0, 0, 240, 140))

      root.addSubview(newTextField("Native window", frame = rect(16, 16, 180, 32)))
      window.contentMinSize = initSize(120, 80)
      window.setContentView(root)
      app.addWindow(window)

      check not window.isVisible
      window.makeKeyAndOrderFront()
      check window.isVisible

      try:
        check app.runForFrames(2) == 2
        check window.nativeReady
        check not window.nativeWindowOrNil().isNil
        when compiles(window.nativeWindowOrNil().minSize):
          check window.nativeWindowOrNil().minSize == siwinshim.ivec2(120, 80)
          window.contentMinSize = initSize(150, 90)
          check window.nativeWindowOrNil().minSize == siwinshim.ivec2(150, 90)
      except CatchableError:
        skip()
        break nativeRun
      finally:
        window.close()

  test "native render request follows display dirty state":
    block nativeRenderRequest:
      let
        app = newApplication()
        window =
          newWindow("Nimkit Native Render Request", frame = rect(80, 80, 240, 140))
        root = newView(frame = rect(0, 0, 240, 140))
        child = newView(frame = rect(16, 16, 80, 40))

      root.addSubview(child)
      window.setContentView(root)
      app.addWindow(window)
      window.makeKeyAndOrderFront()

      try:
        check app.runForFrames(1) == 1
        check window.nativeReady
        check not root.needsDisplayUpdateInSubtree()
        check not window.nativeRenderRequested()
        check not window.requestNativeDisplayUpdateIfNeeded()

        let before = window.nativeRenderCount()
        child.background = color(1, 0, 0)
        check root.needsDisplayUpdateInSubtree()
        check window.requestNativeDisplayUpdateIfNeeded()
        check window.nativeRenderRequested()
        check app.runForFrames(1) == 1
        check window.nativeRenderCount() > before
        check not root.needsDisplayUpdateInSubtree()
        check not window.nativeRenderRequested()
      except CatchableError:
        skip()
        break nativeRenderRequest
      finally:
        window.close()

  test "native close marks window closed without releasing during callback":
    block nativeClose:
      let
        app = newApplication()
        window = newWindow("Nimkit Native Close", frame = rect(80, 80, 240, 140))

      window.setContentView(newView(frame = rect(0, 0, 240, 140)))
      app.addWindow(window)
      window.makeKeyAndOrderFront()

      try:
        check app.runForFrames(1) == 1
        let nativeWindow = window.nativeWindowOrNil()
        check not nativeWindow.isNil
        if nativeWindow.isNil:
          break nativeClose
        siwinshim.close(nativeWindow)
        check window.isClosed
        check not window.nativeReady
      except CatchableError:
        skip()
        break nativeClose
      finally:
        window.close()

  test "native escape key does not close ordinary windows":
    block nativeEscape:
      let
        app = newApplication()
        window = newWindow("Nimkit Native Escape", frame = rect(80, 80, 240, 140))

      window.setContentView(newView(frame = rect(0, 0, 240, 140)))
      app.addWindow(window)
      window.makeKeyAndOrderFront()

      try:
        check app.runForFrames(1) == 1
        let nativeWindow = window.nativeWindowOrNil()
        check not nativeWindow.isNil
        if nativeWindow.isNil:
          break nativeEscape
        nativeWindow.eventsHandler.onKey(
          siwinshim.KeyEvent(
            window: nativeWindow, key: siwinshim.Key.escape, pressed: true
          )
        )
        check not window.isClosed
        check window.nativeReady
        check not siwinshim.closed(nativeWindow)
      except CatchableError:
        skip()
        break nativeEscape
      finally:
        window.close()

  test "native combo boxes use popup windows instead of owner-window popup drawing":
    block nativeComboPopup:
      let
        app = newApplication()
        window = newWindow("Nimkit Native Combo Popup", frame = rect(80, 80, 260, 160))
        root = newView(frame = rect(0, 0, 260, 160))
        combo = newComboBox(["Low", "Medium", "High"], frame = rect(16, 16, 140, 24))
        other = newComboBox(["Red", "Green", "Blue"], frame = rect(16, 58, 140, 24))

      root.addSubview(combo)
      root.addSubview(other)
      window.setContentView(root)
      app.addWindow(window)
      window.makeKeyAndOrderFront()

      try:
        check app.runForFrames(1) == 1
        check window.nativeReady
        check window.mouseDownAt(initPoint(24, 24))
        check combo.popupOpen
        check window.hasActiveTransientSession()
        let renders = window.buildRenders()
        check PopupDrawLevel notin renders.layers
        combo.activateItemAtIndex(1)
        combo.closePopup()
        check not window.hasActiveTransientSession()
        check combo.indexOfSelectedItem() == 1
        check combo.stringValue == "Medium"
        check window.firstResponder == combo
        let nativeWindow = window.nativeWindowOrNil()
        check window.isKeyWindow
        check app.keyWindow == window

        check window.mouseDownAt(initPoint(24, 24))
        check combo.popupOpen
        if not nativeWindow.isNil:
          nativeWindow.eventsHandler.onStateBoolChanged(
            siwinshim.StateBoolChangedEvent(
              window: nativeWindow,
              value: true,
              kind: siwinshim.StateBoolChangedEventKind.focus,
            )
          )
        check not combo.popupOpen
        check not window.hasActiveTransientSession()
        check window.transientDismissReason() == tdrFocusChange
        check combo.indexOfSelectedItem() == 1
        check other.indexOfSelectedItem() == -1

        check window.mouseDownAt(initPoint(24, 24))
        check combo.popupOpen
        check window.hasActiveTransientSession()
        check window.mouseDownAt(initPoint(24, 68))
        check window.mouseUpAt(initPoint(24, 68))
        check not combo.popupOpen
        check not window.hasActiveTransientSession()
        check window.transientDismissReason() == tdrOutsideClick
        check not other.popupOpen
        check combo.indexOfSelectedItem() == 1
        check other.indexOfSelectedItem() == -1
        check window.firstResponder == combo
        check window.isKeyWindow
        check app.keyWindow == window
      except CatchableError:
        skip()
        break nativeComboPopup
      finally:
        combo.closePopup()
        window.close()

  test "threaded combo boxes create popup windows on the application thread":
    block threadedComboPopup:
      let
        app = newApplication()
        window = newWindow("Nimkit Pending Combo Popup", frame = rect(80, 80, 260, 160))
        root = newView(frame = rect(0, 0, 260, 160))
        combo = newComboBox(["Low", "Medium", "High"], frame = rect(16, 16, 140, 24))
      var runtime = newThreadRendererRuntime()

      root.addSubview(combo)
      window.setContentView(root)
      app.addWindow(window)
      window.makeKeyAndOrderFront()

      try:
        check app.runForFrames(1) == 1
        check window.nativeReady
        runtime.start()
        window.useThreadRenderer(runtime.client)

        check window.mouseDownAt(initPoint(24, 24))
        check combo.popupOpen
        let popup = window.transientWindow()
        check not popup.isNil
        if popup.isNil:
          break threadedComboPopup
        check not popup.isClosed
        check popup.nativeReady
      except CatchableError:
        skip()
        break threadedComboPopup
      finally:
        combo.closePopup()
        window.useThreadRenderer(nil)
        window.close()
        runtime.stop()
        runtime.join()

  test "native combo boxes can force inline popup drawing":
    block nativeInlineComboPopup:
      let
        app = newApplication()
        window = newWindow("Nimkit Inline Combo Popup", frame = rect(80, 80, 260, 160))
        root = newView(frame = rect(0, 0, 260, 160))
        combo = newComboBox(["Low", "Medium", "High"], frame = rect(16, 16, 140, 24))

      window.setPopupPresentation(ppInline)
      root.addSubview(combo)
      window.setContentView(root)
      app.addWindow(window)
      window.makeKeyAndOrderFront()

      try:
        check app.runForFrames(1) == 1
        check window.nativeReady
        check window.mouseDownAt(initPoint(24, 24))
        check combo.popupOpen
        check window.hasActiveTransientSession()
        let renders = window.buildRenders()
        check PopupDrawLevel in renders.layers
      except CatchableError:
        skip()
        break nativeInlineComboPopup
      finally:
        combo.closePopup()
        window.close()
