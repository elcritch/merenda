# Kosmo content views, window management, and application lifecycle.

protocol KosmoContentCommandDispatch of nimkit.ResponderCommandDispatchProtocol:
  method dispatchCommand(
      content: KosmoContentView, args: nimkit.TryToPerformArgs
  ): bool =
    let panelNumber = args.selector.focusPanelNumber()
    if panelNumber > 0:
      if content.onFocusPanel.isNil:
        return false
      content.onFocusPanel(panelNumber)
      return true
    case $args.selector.name
    of KosmoNewTerminalAction:
      if content.onNewTerminal.isNil:
        return false
      content.onNewTerminal()
    of KosmoShowFileExplorerAction:
      if content.onShowFileExplorer.isNil:
        return false
      content.onShowFileExplorer()
    of KosmoRevealActiveFileAction:
      if content.onRevealActiveFile.isNil:
        return false
      content.onRevealActiveFile()
    of KosmoFindInFilesAction:
      if content.onFindInFiles.isNil:
        return false
      content.onFindInFiles()
    of KosmoQuickOpenAction:
      if content.onQuickOpen.isNil:
        return false
      content.onQuickOpen()
    else:
      return false
    true

proc newKosmoContentView(
    splitView: nimkit.SplitView,
    statusLabel: nimkit.Label,
    quickOpenPanel: KosmoQuickOpenPanel,
): KosmoContentView =
  result = KosmoContentView(
    splitView: splitView, statusLabel: statusLabel, quickOpenPanel: quickOpenPanel
  )
  result.initViewFields()
  result.addSubview(splitView)
  result.addSubview(statusLabel)
  result.addSubview(quickOpenPanel)
  discard result.withProtocol(KosmoContentLayout)
  discard result.withProtocol(KosmoContentCommandDispatch)

proc showFileExplorer*(frontend: KosmoApplication): bool {.discardable.} =
  ## Select the files sidebar tab and focus its tree.
  if frontend.isNil or not frontend.hasFileBrowser() or frontend.sidebarTabs.isNil or
      frontend.fileTree.isNil:
    return
  if not frontend.sidebarTabs.selectCompactTabAtIndex(0):
    return
  result = frontend.window.makeFirstResponder(frontend.fileTree)
  if result:
    frontend.dockController.activatePanelWindow(frontend.window)

proc revealActiveFile*(frontend: KosmoApplication): bool {.discardable.} =
  ## Reveal the selected editor tab when it is visible in the file-browser scope.
  if frontend.isNil or not frontend.hasFileBrowser() or frontend.fileTree.isNil or
      frontend.sidebarTabs.isNil or frontend.dockController.isNil:
    return
  let
    controller = frontend.dockController
    group = controller.activePaneGroup()
  if group.isNil:
    return
  var bufferId: KosmoBufferId
  if not group.selectedTabIdentifier.parseTabIdentifier(bufferId):
    return
  for tab in controller.editor.tabs():
    if tab.id == bufferId and tab.filePath.isSome:
      let path =
        resolvedEditorFilePath(tab.filePath.get, controller.editor.workingDirectory())
      if frontend.fileTree.revealPath(path):
        result = frontend.showFileExplorer()
      return

proc showFindInFiles*(frontend: KosmoApplication): bool {.discardable.} =
  ## Select the find sidebar tab and focus its search query.
  if frontend.isNil or not frontend.hasFileBrowser() or frontend.sidebarTabs.isNil or
      frontend.searchPanel.isNil:
    return
  frontend.searchPanel.rootPaths = frontend.fileTree.rootPaths
  if not frontend.sidebarTabs.selectCompactTabAtIndex(1):
    return
  result = frontend.searchPanel.focusQuery()
  if result:
    frontend.dockController.activatePanelWindow(frontend.window)

proc showQuickOpen*(frontend: KosmoApplication): bool {.discardable.} =
  ## Present the fuzzy project-file picker and open its selected file.
  if frontend.isNil or frontend.quickOpenPanel.isNil or frontend.fileTree.isNil:
    return
  let weakFrontend = frontend.unsafeWeakRef()
  result = frontend.quickOpenPanel.present(
    frontend.window,
    frontend.fileTree.rootPaths,
    proc(path: string) =
      if weakFrontend.isNil:
        return
      let activeView = weakFrontend[].dockController.activeEditorView()
      if not activeView.isNil:
        discard activeView.openFile(path)
    ,
  )

func terminalOptionAsMeta*(frontend: KosmoApplication): bool =
  ## Return whether Kosmo terminals use Option/Alt as the Meta modifier.
  not frontend.isNil and frontend.xTerminalOptionAsMeta

proc `terminalOptionAsMeta=`*(frontend: KosmoApplication, enabled: bool) =
  ## Apply the Option/Alt-as-Meta preference to current and future terminals.
  if frontend.isNil:
    return
  frontend.xTerminalOptionAsMeta = enabled
  if not frontend.xSettingsWindow.isNil:
    frontend.xSettingsWindow.optionAsMeta = enabled
  if frontend.dockController.isNil:
    return
  for group in frontend.dockController.groups:
    for document in group.documents:
      if document.contentView of nimkit.TerminalView:
        nimkit.TerminalView(document.contentView).optionAsMeta = enabled

func terminalLinksEnabled*(frontend: KosmoApplication): bool =
  ## Return whether modifier-hover and modifier-click terminal links are enabled.
  not frontend.isNil and frontend.xTerminalLinksEnabled

proc `terminalLinksEnabled=`*(frontend: KosmoApplication, enabled: bool) =
  ## Apply terminal link activation to current and future terminals.
  if frontend.isNil:
    return
  frontend.xTerminalLinksEnabled = enabled
  if not frontend.xSettingsWindow.isNil:
    frontend.xSettingsWindow.terminalLinksEnabled = enabled
  if frontend.dockController.isNil:
    return
  for group in frontend.dockController.groups:
    for document in group.documents:
      if document.contentView of nimkit.TerminalView:
        nimkit.TerminalView(document.contentView).allowsLinkActivation = enabled

func moeThemeSettings(themes: openArray[KosmoMoeTheme]): seq[KosmoMoeThemeSetting] =
  for theme in themes:
    result.add KosmoMoeThemeSetting(
      identifier: theme.identifier, name: theme.name, preview: theme.preview
    )

proc setMoeTheme*(frontend: KosmoApplication, identifier: string): bool =
  ## Apply an available Moe theme and repaint every editor pane.
  if frontend.isNil or frontend.dockController.isNil:
    return
  for theme in frontend.dockController.editor.availableMoeThemes():
    if theme.identifier != identifier:
      continue
    let outcome = frontend.dockController.editor.applyMoeTheme(theme)
    for group in frontend.dockController.groups:
      group.editorView.refresh()
    if not outcome.applied and not frontend.statusLabel.isNil:
      frontend.statusLabel.text = outcome.message
    if outcome.applied and not frontend.xWindowManager.isNil:
      let manager = frontend.xWindowManager[]
      manager.config.moeTheme = identifier
      discard manager.config.saveKosmoConfig(manager.configPath)
    return outcome.applied

proc menuItemWithIdentifier(menu: nimkit.Menu, identifier: string): nimkit.MenuItem =
  if menu.isNil:
    return
  for item in menu.items():
    if item.identifier() == identifier:
      return item
    let nested = item.submenu().menuItemWithIdentifier(identifier)
    if not nested.isNil:
      return nested

proc synchronizeKosmoMenuBindings(frontend: KosmoApplication) =
  if frontend.isNil or frontend.dockController.isNil:
    return
  let menu = frontend.application.mainMenu()
  for action in kosmoActions():
    let item = menu.menuItemWithIdentifier(action.identifier)
    if item.isNil:
      continue
    var found = false
    for binding in frontend.dockController.shortcutBindings.bindings:
      if binding.selector == nimkit.actionSelector(action.identifier) and
          binding.sequence.strokes.len == 1:
        let stroke = binding.sequence.strokes[0]
        item.setKeyEquivalent(stroke.key, stroke.modifiers)
        found = true
        break
    if not found:
      item.setKeyEquivalent("")

proc updateShortcutSettingsWindow(frontend: KosmoApplication) =
  if frontend.isNil or frontend.xSettingsWindow.isNil:
    return
  let controller = frontend.dockController
  frontend.xSettingsWindow.shortcutProfile = controller.shortcutProfile
  frontend.xSettingsWindow.editorInputPolicy = controller.editorInputPolicy
  frontend.xSettingsWindow.shortcuts =
    controller.shortcutBindings.kosmoShortcutSettings()

proc setShortcutProfile*(frontend: KosmoApplication, profile: KosmoShortcutProfile) =
  ## Apply a shortcut profile immediately to every Kosmo window and menu.
  if frontend.isNil or frontend.dockController.isNil or
      frontend.dockController.shortcutProfile == profile:
    return
  let controller = frontend.dockController
  controller.shortcutProfile = profile
  controller.shortcutBindings = initKosmoKeyBindings(profile)
  for host in controller.hosts:
    controller.installShortcutBindings(host.window)
  frontend.synchronizeKosmoMenuBindings()
  frontend.updateShortcutSettingsWindow()

func shortcutProfile*(frontend: KosmoApplication): KosmoShortcutProfile =
  if frontend.isNil or frontend.dockController.isNil:
    defaultKosmoShortcutProfile()
  else:
    frontend.dockController.shortcutProfile

proc setEditorInputPolicy*(frontend: KosmoApplication, policy: KosmoEditorInputPolicy) =
  ## Apply Moe/native key routing immediately to every editor pane.
  if frontend.isNil or frontend.dockController.isNil:
    return
  frontend.dockController.editorInputPolicy = policy
  frontend.updateShortcutSettingsWindow()

func editorInputPolicy*(frontend: KosmoApplication): KosmoEditorInputPolicy =
  if frontend.isNil or frontend.dockController.isNil:
    defaultKosmoEditorInputPolicy()
  else:
    frontend.dockController.editorInputPolicy

func settingsWindow*(frontend: KosmoApplication): KosmoSettingsWindow =
  ## Return Kosmo's settings controller after the panel has been created.
  if not frontend.isNil:
    result = frontend.xSettingsWindow

proc showSettings*(frontend: KosmoApplication): bool {.discardable.} =
  ## Present Kosmo's application settings without Merenda's global settings pages.
  if frontend.isNil or frontend.application.isNil:
    return
  let
    shortcuts = frontend.dockController.shortcutBindings.kosmoShortcutSettings()
    moeThemes = frontend.dockController.editor.availableMoeThemes()
    moeThemeSettings = moeThemes.moeThemeSettings()
    textMateGrammars = frontend.dockController.editor.availableTextMateGrammars()
    selectedMoeThemeIdentifier =
      frontend.dockController.editor.activeMoeThemeIdentifier()
  if frontend.xSettingsWindow.isNil or frontend.xSettingsWindow.window.isClosed():
    let weakFrontend = frontend.unsafeWeakRef()
    frontend.xSettingsWindow = newKosmoSettingsWindow(
      optionAsMeta = frontend.xTerminalOptionAsMeta,
      optionAsMetaHandler = proc(enabled: bool) =
        if not weakFrontend.isNil:
          weakFrontend[].terminalOptionAsMeta = enabled
      ,
      terminalLinksEnabled = frontend.xTerminalLinksEnabled,
      terminalLinksHandler = proc(enabled: bool) =
        if not weakFrontend.isNil:
          weakFrontend[].terminalLinksEnabled = enabled
      ,
      shortcutProfile = frontend.dockController.shortcutProfile,
      shortcutProfileHandler = proc(profile: KosmoShortcutProfile) =
        if not weakFrontend.isNil:
          weakFrontend[].setShortcutProfile(profile)
      ,
      editorInputPolicy = frontend.dockController.editorInputPolicy,
      editorInputPolicyHandler = proc(policy: KosmoEditorInputPolicy) =
        if not weakFrontend.isNil:
          weakFrontend[].setEditorInputPolicy(policy)
      ,
      shortcuts = shortcuts,
      moeThemes = moeThemeSettings,
      selectedMoeThemeIdentifier = selectedMoeThemeIdentifier,
      moeThemeHandler = proc(identifier: string): bool =
        if not weakFrontend.isNil:
          return weakFrontend[].setMoeTheme(identifier)
      ,
      textMateGrammars = textMateGrammars,
    )
  else:
    frontend.xSettingsWindow.optionAsMeta = frontend.xTerminalOptionAsMeta
    frontend.xSettingsWindow.terminalLinksEnabled = frontend.xTerminalLinksEnabled
    frontend.updateShortcutSettingsWindow()
    frontend.xSettingsWindow.updateMoeThemes(
      moeThemeSettings, selectedMoeThemeIdentifier
    )
    frontend.xSettingsWindow.textMateGrammars = textMateGrammars
  result =
    not frontend.application.showWindow(
      frontend.xSettingsWindow.window, frontend.xSettingsWindow.contentView,
      frontend.xSettingsWindow.firstResponder,
    ).isNil

proc showGitDiffSnapshot(
    frontend: KosmoApplication, snapshot: GitDiffSnapshot, refreshesRepository: bool
): bool =
  if frontend.isNil or frontend.dockController.isNil:
    return
  let controller = frontend.dockController
  for group in controller.groups:
    let document = group.documentForIdentifier(KosmoGitDiffTabIdentifier)
    if not document.isNil:
      if not group.window.isNil and not group.window.isClosed():
        if document.contentView of KosmoGitDiffPanel:
          frontend.gitDiffPanel = KosmoGitDiffPanel(document.contentView)
          if refreshesRepository:
            frontend.gitDiffPanel.displayRepositoryDiff(snapshot.rootPath)
          else:
            frontend.gitDiffPanel.displayDiff(snapshot)
        controller.activatePanelWindow(group.window)
        controller.activatePaneTab(group, document.identifier)
        return true
      discard document.close()
      let documentIndex = group.documentIndex(document.identifier)
      if documentIndex >= 0:
        group.documents.delete(documentIndex)
      let orderIndex = group.tabOrder.find(document.identifier)
      if orderIndex >= 0:
        group.tabOrder.delete(orderIndex)

  let group = controller.activePaneGroup()
  if group.isNil:
    return
  let
    panel =
      if refreshesRepository:
        newKosmoGitDiffPanel(
          snapshot.rootPath, group.pane.markdownControls.markdownPresentationStyle()
        )
      else:
        newKosmoGitDiffPanel(
          snapshot, group.pane.markdownControls.markdownPresentationStyle()
        )
    weakFrontend = frontend.unsafeWeakRef()
    weakPanel = panel.unsafeWeakRef()
    document = newKosmoPaneDocument(
      identifier = KosmoGitDiffTabIdentifier,
      title = "Git Diff",
      contentView = panel,
      preferredFirstResponder = panel.markdownView.textView(),
      tooltip = if refreshesRepository: "Current Git diff" else: "Piped Git diff",
      onClose = proc(document: KosmoPaneDocument): bool =
        discard document
        panel.close()
        if not weakFrontend.isNil and weakFrontend[].gitDiffPanel == panel:
          weakFrontend[].gitDiffPanel = nil
        true,
    )
  panel.keyEquivalentHandler = proc(event: nimkit.KeyEvent): bool =
    if weakFrontend.isNil or weakPanel.isNil or weakFrontend[].dockController.isNil:
      return
    for candidate in weakFrontend[].dockController.groups:
      let candidateDocument = candidate.documentForIdentifier(KosmoGitDiffTabIdentifier)
      if not candidateDocument.isNil and
          candidateDocument.contentView == nimkit.View(weakPanel[]):
        return candidate.editorView.handlePaneKey(event)
  frontend.gitDiffPanel = panel
  if controller.openPaneDocument(group, document):
    return true
  panel.close()
  frontend.gitDiffPanel = nil

proc showGitDiff*(frontend: KosmoApplication): bool {.discardable.} =
  ## Show full-file Git changes for the active project's repository.
  if frontend.isNil:
    return
  let root =
    if frontend.fileTree.rootPath.len > 0:
      frontend.fileTree.rootPath
    else:
      getCurrentDir()
  frontend.showGitDiffSnapshot(
    GitDiffSnapshot(source: gdsRepository, rootPath: root), refreshesRepository = true
  )

proc showPipedGitDiff*(
    frontend: KosmoApplication, content, workingDirectory: string
): bool {.discardable.} =
  ## Show a static unified diff received through standard input.
  frontend.showGitDiffSnapshot(
    parseGitDiff(content, workingDirectory), refreshesRepository = false
  )

func ownsWindow(frontend: KosmoApplication, window: nimkit.Window): bool =
  if frontend.isNil or window.isNil or frontend.dockController.isNil:
    return
  for host in frontend.dockController.hosts:
    if host.window == window:
      return true

proc activeFrontend(manager: KosmoWindowManager): KosmoApplication =
  if manager.isNil:
    return
  let keyWindow = manager.application.keyWindow()
  for frontend in manager.frontends:
    if not frontend.xClosed and frontend.ownsWindow(keyWindow):
      return frontend
  let mainWindow = manager.application.mainWindow()
  for frontend in manager.frontends:
    if not frontend.xClosed and frontend.ownsWindow(mainWindow):
      return frontend
  if manager.frontends.len > 0:
    for index in countdown(manager.frontends.high, 0):
      if not manager.frontends[index].xClosed:
        return manager.frontends[index]

proc unregister(manager: KosmoWindowManager, frontend: KosmoApplication) =
  if manager.isNil:
    return
  let index = manager.frontends.find(frontend)
  if index >= 0:
    manager.frontends.delete(index)

protocol KosmoWindowLifecycleDelegate of nimkit.WindowDelegateProtocol:
  method windowDidClose(lifecycle: KosmoWindowLifecycle, window: nimkit.Window) =
    discard window
    if not lifecycle.frontend.isNil:
      lifecycle.frontend[].close()

proc newKosmoWindowManager*(
    app = nimkit.sharedApplication(),
    keyBindingsPath = "",
    configPath = "",
    assetCacheDirectory = "",
): KosmoWindowManager =
  ## Create the owner for all project and file windows in a Kosmo session.
  let config = loadKosmoConfig(configPath)
  app.configureKosmoApplicationAssets(config, assetCacheDirectory)
  KosmoWindowManager(
    application: app,
    keyBindingsPath: keyBindingsPath,
    configPath: configPath,
    config: config,
  )

func hasFileBrowser*(frontend: KosmoApplication): bool =
  ## Return whether this window displays a project file browser.
  not frontend.isNil and frontend.xHasFileBrowser

func cliWindowId*(frontend: KosmoApplication): string =
  ## Return the private routing identifier inherited by terminals from this window.
  if not frontend.isNil:
    result = frontend.xCliWindowId

func projectWindowTitle(rootPaths: openArray[string]): string =
  result = "Kosmo"
  if rootPaths.len > 0:
    result.add " (" & nimkit.fileBrowserDisplayName(rootPaths[0])
    if rootPaths.len > 1:
      result.add " + " & $(rootPaths.len - 1)
    result.add ")"

proc updateProjectWindowTitle(frontend: KosmoApplication) =
  if not frontend.isNil and not frontend.window.isNil and not frontend.fileTree.isNil:
    frontend.window.title = projectWindowTitle(frontend.fileTree.rootPaths)

proc managedWindows*(manager: KosmoWindowManager): seq[KosmoApplication] =
  ## Return the live Kosmo windows owned by this session.
  if manager.isNil:
    return
  for frontend in manager.frontends:
    if not frontend.xClosed:
      result.add frontend

proc configureKosmoSettingsMenu(frontend: KosmoApplication) =
  let mainMenu = frontend.application.mainMenu()
  if mainMenu.isNil or mainMenu.len == 0:
    return
  let applicationMenu = mainMenu[0].submenu()
  if not applicationMenu.isNil and applicationMenu.len > 2:
    let settingsItem = applicationMenu[2]
    let manager =
      if frontend.xWindowManager.isNil:
        nil
      else:
        frontend.xWindowManager[]
    settingsItem.identifier = KosmoShowSettingsAction
    settingsItem.action = nimkit.actionSelector(KosmoShowSettingsAction)
    settingsItem.target = nimkit.newActionTarget(
      nimkit.actionSelector(KosmoShowSettingsAction)
    ) do(sender: nimkit.DynamicAgent):
      discard sender
      if not manager.isNil:
        let active = manager.activeFrontend()
        if not active.isNil:
          discard active.showSettings()

proc configureKosmoStandardActionMenus(frontend: KosmoApplication) =
  let mainMenu = frontend.application.mainMenu()
  if mainMenu.isNil or mainMenu.len < 3:
    return
  let editMenu = mainMenu[2].submenu()
  if not editMenu.isNil:
    for item in editMenu.items():
      let action = item.action()
      var identifier = ""
      if action.name == nimkit.undo().name:
        identifier = KosmoUndoAction
      elif action.name == nimkit.redo().name:
        identifier = KosmoRedoAction
      elif action.name == nimkit.cut().name:
        identifier = KosmoCutAction
      elif action.name == nimkit.copy().name:
        identifier = KosmoCopyAction
      elif action.name == nimkit.paste().name:
        identifier = KosmoPasteAction
      elif action.name == nimkit.selectAll().name:
        identifier = KosmoSelectAllAction
      if identifier.len > 0:
        item.identifier = identifier

  let applicationMenu = mainMenu[0].submenu()
  if applicationMenu.isNil:
    return
  for item in applicationMenu.items():
    if item.action().name == nimkit.terminate().name:
      let app = frontend.application
      item.identifier = KosmoQuitAction
      item.action = nimkit.actionSelector(KosmoQuitAction)
      let quitTarget = nimkit.newActionTarget(nimkit.actionSelector(KosmoQuitAction)) do(
        sender: nimkit.DynamicAgent
      ):
        discard sender
        discard app.terminate()
      item.target = quitTarget
      break

proc configureKosmoWorkspaceMenu(frontend: KosmoApplication) =
  let windowMenu = frontend.application.windowsMenu()
  if windowMenu.isNil or not windowMenu.menuItemWithIdentifier(KosmoNextTabAction).isNil:
    return
  let manager =
    if frontend.xWindowManager.isNil:
      nil
    else:
      frontend.xWindowManager[]

  proc addAction(title, identifier: string) =
    let item = nimkit.newMenuItem(title, nimkit.actionSelector(identifier))
    item.identifier = identifier
    item.target = nimkit.newActionTarget(nimkit.actionSelector(identifier)) do(
      sender: nimkit.DynamicAgent
    ):
      discard sender
      if manager.isNil:
        return
      let active = manager.activeFrontend()
      if active.isNil:
        return
      let
        controller = active.dockController
        group = controller.activePaneGroup()
      case identifier
      of KosmoPreviousTabAction:
        controller.selectRelativePaneTab(group, -1)
      of KosmoNextTabAction:
        controller.selectRelativePaneTab(group, 1)
      of KosmoSplitHorizontalAction:
        discard controller.splitCurrentPaneTab(group, nimkit.dpBottom)
      of KosmoSplitVerticalAction:
        discard controller.splitCurrentPaneTab(group, nimkit.dpRight)
      of KosmoShowFileExplorerAction:
        discard active.showFileExplorer()
      of KosmoRevealActiveFileAction:
        discard active.revealActiveFile()
      of KosmoFindInFilesAction:
        discard active.showFindInFiles()
      else:
        if identifier.startsWith(KosmoFocusPanelActionPrefix):
          discard
            controller.focusPanel(nimkit.actionSelector(identifier).focusPanelNumber())
    discard windowMenu.addItem(item)

  windowMenu.addSeparator()
  addAction("Previous Tab", KosmoPreviousTabAction)
  addAction("Next Tab", KosmoNextTabAction)
  windowMenu.addSeparator()
  addAction("Split Below", KosmoSplitHorizontalAction)
  addAction("Split Right", KosmoSplitVerticalAction)
  windowMenu.addSeparator()
  addAction("Show Files", KosmoShowFileExplorerAction)
  addAction("Reveal Active File", KosmoRevealActiveFileAction)
  addAction("Find in Files", KosmoFindInFilesAction)

  let
    focusMenu = nimkit.newMenu("Focus Panel")
    focusMenuItem = nimkit.newMenuItem("Focus Panel")
  focusMenuItem.submenu = focusMenu
  for panelNumber in 1 .. KosmoMaxFocusPanelShortcut:
    let
      targetPanelNumber = panelNumber
      identifier = targetPanelNumber.focusPanelAction()
    let item = nimkit.newMenuItem(
      "Panel " & $targetPanelNumber, nimkit.actionSelector(identifier)
    )
    item.identifier = identifier
    item.target = nimkit.newActionTarget(nimkit.actionSelector(identifier)) do(
      sender: nimkit.DynamicAgent
    ):
      if manager.isNil or not (sender of nimkit.MenuItem):
        return
      let
        panelNumber = nimkit.MenuItem(sender).action().focusPanelNumber()
        active = manager.activeFrontend()
      if panelNumber > 0 and not active.isNil:
        discard active.dockController.focusPanel(panelNumber)
    discard focusMenu.addItem(item)
  discard windowMenu.addItem(focusMenuItem)

proc newKosmoApplication*(
    manager: KosmoWindowManager,
    filePath = "",
    hasFileBrowser = true,
    monitorsGitStatus = true,
): KosmoApplication =
  ## Create an unpresented Kosmo window owned by `manager`.
  ## Disable `monitorsGitStatus` for short-lived frontends that do not need repository
  ## decorations.
  let
    app = manager.application
    keyBindingsPath = manager.keyBindingsPath
  var shortcutConfiguration = initKosmoShortcutConfiguration()
  var keyBindingErrors: seq[string]
  if keyBindingsPath.len > 0:
    let loaded = loadKosmoShortcutConfiguration(keyBindingsPath, shortcutConfiguration)
    shortcutConfiguration = loaded.configuration
    keyBindingErrors = loaded.errors
  let existingMainMenu = app.mainMenu()
  if existingMainMenu.isNil or existingMainMenu.len < 5 or
      existingMainMenu[1].title != "File" or existingMainMenu[2].title != "Edit" or
      existingMainMenu[3].title != "Window" or existingMainMenu[4].title != "Help":
    app.installStandardMainMenu()
  let
    initialRootPath =
      if not hasFileBrowser:
        ""
      elif dirExists(filePath):
        absolutePath(filePath)
      elif getCurrentDir().isFilesystemRoot():
        ""
      else:
        getCurrentDir()
    editorWorkingDirectory =
      if initialRootPath.len > 0:
        initialRootPath
      elif fileExists(filePath):
        absolutePath(filePath).parentDir()
      else:
        getCurrentDir()
    editorView =
      newKosmoEditorView(newKosmoEditor(workingDirectory = editorWorkingDirectory))
    editorPane = newKosmoEditorPane(editorView)
    fileTree = newKosmoFileTree(initialRootPath)
    fileBrowserPanel = newKosmoFileBrowserPanel(fileTree)
    searchPanel = newKosmoFileSearchPanel(fileTree.rootPath)
    quickOpenPanel = newKosmoQuickOpenPanel(fileTree.rootPath, fileTree.workspaceFiles)
    sidebarTabs = nimkit.newCompactTabView(
      [
        nimkit.initCompactTabItem(
          KosmoFilesTabIdentifier,
          "Files",
          nimkit.newSvgMtsdfResource(KosmoFilesIconSvg, "kosmo-files"),
          fileBrowserPanel,
        ),
        nimkit.initCompactTabItem(
          KosmoFindTabIdentifier,
          "Find",
          nimkit.newSvgMtsdfResource(KosmoFindIconSvg, "kosmo-find"),
          searchPanel,
        ),
      ]
    )
    sidebarPane = newKosmoSidebarPane(sidebarTabs, fileTree, searchPanel)
    splitView = nimkit.newSplitView(nimkit.laHorizontal)
    dockView = nimkit.newDockView()
    mainMenu = app.mainMenu()
    fileMenu = nimkit.newMenu("File")
    fileItem = mainMenu[1]
    newItem = nimkit.newMenuItem("New…", nimkit.actionSelector(KosmoNewFileAction))
    openItem = nimkit.newMenuItem("Open…", nimkit.actionSelector(KosmoOpenFileAction))
    openProjectItem = nimkit.newMenuItem(
      "Open Project…", nimkit.actionSelector(KosmoOpenProjectAction)
    )
    quickOpenItem =
      nimkit.newMenuItem("Open Quickly…", nimkit.actionSelector(KosmoQuickOpenAction))
    terminalItem =
      nimkit.newMenuItem("New Terminal", nimkit.actionSelector(KosmoNewTerminalAction))
    gitDiffItem =
      nimkit.newMenuItem("Show Git Diff", nimkit.actionSelector(KosmoShowGitDiffAction))
    saveItem = nimkit.newMenuItem("Save", nimkit.actionSelector(KosmoSaveAction))
    closeTabItem =
      nimkit.newMenuItem("Close Tab", nimkit.actionSelector(KosmoCloseTabAction))
    closeWindowItem =
      nimkit.newMenuItem("Close Window", nimkit.actionSelector(KosmoCloseWindowAction))
  editorView.applyKosmoEditorStyle(app.effectiveAppearance())
  newItem.identifier = KosmoNewFileAction
  openItem.identifier = KosmoOpenFileAction
  openProjectItem.identifier = KosmoOpenProjectAction
  quickOpenItem.identifier = KosmoQuickOpenAction
  terminalItem.identifier = KosmoNewTerminalAction
  gitDiffItem.identifier = KosmoShowGitDiffAction
  gitDiffItem.validates = false
  saveItem.identifier = KosmoSaveAction
  closeTabItem.identifier = KosmoCloseTabAction
  closeWindowItem.identifier = KosmoCloseWindowAction
  fileItem.submenu = fileMenu
  discard fileMenu.addItem(newItem)
  discard fileMenu.addItem(openItem)
  discard fileMenu.addItem(openProjectItem)
  fileMenu.addSeparator()
  discard fileMenu.addItem(quickOpenItem)
  discard fileMenu.addItem(terminalItem)
  discard fileMenu.addItem(gitDiffItem)
  fileMenu.addSeparator()
  discard fileMenu.addItem(saveItem)
  fileMenu.addSeparator()
  discard fileMenu.addItem(closeTabItem)
  discard fileMenu.addItem(closeWindowItem)

  if hasFileBrowser:
    splitView.addPane(sidebarPane, minSize = 160.0'f32, maxSize = 420.0'f32)
  splitView.addPane(dockView, minSize = 320.0'f32)

  let
    statusLabel = nimkit.newStatusLabel("Ready")
    documentView = newKosmoContentView(splitView, statusLabel, quickOpenPanel)
    contentView = nimkit.newMenuRootView(mainMenu, documentView)
  editorView.statusLabel = statusLabel
  editorView.syncChrome()
  result = KosmoApplication(
    application: app,
    window: nimkit.newWindow(
      projectWindowTitle(fileTree.rootPaths), nimkit.rect(120, 100, 1024, 720)
    ),
    editorView: editorView,
    editorPane: editorPane,
    documentTabs: editorView.documentTabs,
    statusLabel: statusLabel,
    fileTree: fileTree,
    fileBrowserPanel: fileBrowserPanel,
    sidebarPane: sidebarPane,
    sidebarTabs: sidebarTabs,
    searchPanel: searchPanel,
    quickOpenPanel: quickOpenPanel,
    splitView: splitView,
    dockView: dockView,
    contentView: contentView,
    documentView: documentView,
    xTerminalOptionAsMeta: true,
    xTerminalLinksEnabled: true,
    xWindowManager: manager.unsafeWeakRef(),
    xHasFileBrowser: hasFileBrowser,
    xCliWindowId: randomIdentifier(),
  )
  let
    controller = KosmoDockController(
      editor: editorView.editor,
      shortcutBindings: shortcutConfiguration.bindings,
      shortcutProfile: shortcutConfiguration.profile,
      editorInputPolicy: shortcutConfiguration.editorInput,
    )
    mainHost = KosmoDockHost(
      workspace: dockView,
      window: result.window,
      contentView: contentView,
      statusLabel: statusLabel,
      primary: true,
    )
  result.dockController = controller
  result.xWindowLifecycle = KosmoWindowLifecycle(frontend: result.unsafeWeakRef())
  nimkit.initResponder(result.xWindowLifecycle)
  discard result.xWindowLifecycle.withProtocol(KosmoWindowLifecycleDelegate)
  result.window.delegate = result.xWindowLifecycle
  manager.frontends.add result
  controller.frontend = result.unsafeWeakRef()
  sidebarPane.dockController = controller.unsafeWeakRef()
  sidebarPane.observeWindow(result.window)
  quickOpenPanel.observeWindow(result.window)
  documentView.onShowFileExplorer = proc() =
    if not controller.frontend.isNil:
      discard controller.frontend[].showFileExplorer()
  documentView.onRevealActiveFile = proc() =
    if not controller.frontend.isNil:
      discard controller.frontend[].revealActiveFile()
  documentView.onFindInFiles = proc() =
    if not controller.frontend.isNil:
      discard controller.frontend[].showFindInFiles()
  documentView.onQuickOpen = proc() =
    if not controller.frontend.isNil:
      discard controller.frontend[].showQuickOpen()
  documentView.onNewTerminal = proc() =
    if not controller.frontend.isNil:
      discard controller.frontend[].newTerminal()
  documentView.onFocusPanel = proc(panelNumber: int) =
    discard controller.focusPanel(panelNumber)
  controller.hosts.add mainHost
  controller.installShortcutBindings(result.window)
  discard controller.newEditorGroup(
    dockView,
    result.window,
    editorView.editor.initialBufferIds(),
    editorView,
    editorPane,
    addToWorkspace = true,
  )

  let frontend = result.unsafeWeakRef()
  result.configureKosmoSettingsMenu()
  result.configureKosmoStandardActionMenus()
  result.configureKosmoWorkspaceMenu()
  result.synchronizeKosmoMenuBindings()
  newItem.target = nimkit.newActionTarget(nimkit.actionSelector(KosmoNewFileAction)) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      discard active.newEditorTab()
  openItem.target = nimkit.newActionTarget(nimkit.actionSelector(KosmoOpenFileAction)) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    manager.chooseFile()
  openProjectItem.target = nimkit.newActionTarget(
    nimkit.actionSelector(KosmoOpenProjectAction)
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    manager.chooseProject()
  quickOpenItem.target = nimkit.newActionTarget(
    nimkit.actionSelector(KosmoQuickOpenAction)
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      discard active.showQuickOpen()
  terminalItem.target = nimkit.newActionTarget(
    nimkit.actionSelector(KosmoNewTerminalAction)
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      discard active.newTerminal()
  gitDiffItem.target = nimkit.newActionTarget(
    nimkit.actionSelector(KosmoShowGitDiffAction)
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      discard active.showGitDiff()
  saveItem.target = nimkit.newActionTarget(nimkit.actionSelector(KosmoSaveAction)) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      let controller = active.dockController
      controller.saveCurrentPaneTab(controller.activePaneGroup())
  closeTabItem.target = nimkit.newActionTarget(
    nimkit.actionSelector(KosmoCloseTabAction)
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      let controller = active.dockController
      controller.closeCurrentPaneTab(controller.activePaneGroup())
  closeWindowItem.target = nimkit.newActionTarget(
    nimkit.actionSelector(KosmoCloseWindowAction)
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    let active = manager.activeFrontend()
    if not active.isNil:
      let group = active.dockController.activePaneGroup()
      if not group.isNil:
        group.window.close()
  fileTree.onOpenFile = proc(path: string, disposition: FileTreeOpenDisposition) =
    if frontend.isNil:
      return
    let activeView = frontend[].dockController.activeEditorView()
    if activeView.isNil:
      return
    case disposition
    of fodTemporary:
      discard activeView.previewFile(path)
    of fodPermanent:
      discard activeView.openFile(path)
  searchPanel.onOpenResult = proc(
      match: nimkit.FileSearchMatch, disposition: FileTreeOpenDisposition
  ) =
    if frontend.isNil:
      return
    let activeView = frontend[].dockController.activeEditorView()
    if not activeView.isNil:
      discard activeView.openSearchResult(match, disposition)
  if fileExists(filePath):
    discard result.dockController.activeEditorView().openFile(filePath)
  elif dirExists(filePath):
    statusLabel.text = absolutePath(filePath)
  if keyBindingErrors.len > 0:
    statusLabel.text = keyBindingErrors.join("; ")
  if manager.config.moeTheme.len > 0:
    discard result.setMoeTheme(manager.config.moeTheme)
  if monitorsGitStatus:
    result.dockController.editor.useEventDrivenGit()
    fileTree.workspaceFiles.connect(
      workspaceRepositoryDidChange, result.xWindowLifecycle, workspaceGitChanged
    )
    fileTree.workspaceFiles.connect(
      workspacePulse, result.xWindowLifecycle, pollWorkspaceGit
    )
    discard fileTree.startGitStatusMonitoring()

proc newKosmoApplication*(
    app = nimkit.sharedApplication(),
    filePath = "",
    keyBindingsPath = "",
    hasFileBrowser = true,
    monitorsGitStatus = true,
    configPath = "",
): KosmoApplication =
  let manager = newKosmoWindowManager(
    app, keyBindingsPath = keyBindingsPath, configPath = configPath
  )
  result = newKosmoApplication(manager, filePath, hasFileBrowser, monitorsGitStatus)

proc openProject*(
    manager: KosmoWindowManager, path: string
): KosmoApplication {.discardable.} =
  ## Create and show a project window rooted at `path`.
  if manager.isNil or path.len == 0 or not dirExists(path):
    return
  result = newKosmoApplication(manager, absolutePath(path), hasFileBrowser = true)
  result.show()

proc openProject*(
    frontend: KosmoApplication, path: string
): KosmoApplication {.discardable.} =
  ## Create a project window in the same application session as `frontend`.
  if frontend.isNil or frontend.xWindowManager.isNil:
    return
  result = frontend.xWindowManager[].openProject(path)

proc openFileWindow(
    manager: KosmoWindowManager, path: string
): KosmoApplication {.discardable.} =
  if manager.isNil or not fileExists(path):
    return
  result = newKosmoApplication(manager, absolutePath(path), hasFileBrowser = false)
  result.show()

proc openPath*(manager: KosmoWindowManager, path: string): bool {.discardable.} =
  ## Apply Open… semantics to the active window, creating one when necessary.
  if manager.isNil:
    return
  let frontend = manager.activeFrontend()
  if not frontend.isNil:
    return frontend.openPath(path)
  if dirExists(path):
    result = not manager.openProject(path).isNil
  elif fileExists(path):
    result = not manager.openFileWindow(path).isNil

proc chooseFile(frontend: KosmoApplication) =
  if frontend.isNil:
    return
  let panel = nimkit.newOpenPanel()
  defer:
    panel.window.close()
  panel.message = "Open a file or add a folder to this window."
  panel.canChooseDirectories = true
  panel.directoryUrl = frontend.fileTree.rootPath
  if frontend.application.runModal(panel) == nimkit.PanelResponseOk:
    discard frontend.openPath(nimkit.filePathFromUrl(panel.selectedUrl()))

proc chooseFile(manager: KosmoWindowManager) =
  if manager.isNil:
    return
  let frontend = manager.activeFrontend()
  if not frontend.isNil:
    frontend.chooseFile()
    return
  let panel = nimkit.newOpenPanel()
  defer:
    panel.window.close()
  panel.message = "Open a file or folder in Kosmo."
  panel.canChooseDirectories = true
  panel.directoryUrl = getCurrentDir()
  if manager.application.runModal(panel) != nimkit.PanelResponseOk:
    return
  discard manager.openPath(nimkit.filePathFromUrl(panel.selectedUrl()))

proc chooseProject(manager: KosmoWindowManager) =
  if manager.isNil:
    return
  let
    frontend = manager.activeFrontend()
    panel = nimkit.newOpenPanel()
  defer:
    panel.window.close()
  panel.window.title = "Open Project"
  panel.message = "Choose a folder to open in a new Kosmo window."
  panel.prompt = "Open Project"
  panel.canChooseFiles = false
  panel.canChooseDirectories = true
  panel.directoryUrl =
    if frontend.isNil or frontend.fileTree.rootPath.len == 0:
      getCurrentDir()
    else:
      frontend.fileTree.rootPath
  if manager.application.runModal(panel) == nimkit.PanelResponseOk:
    discard manager.openProject(nimkit.filePathFromUrl(panel.selectedUrl()))

proc loadKosmoKeyBindings*(
    frontend: KosmoApplication, path: string
): nimkit.KeyBindingJsonResult =
  ## Reset Kosmo shortcuts to their defaults, then apply overrides from `path`.
  if frontend.isNil or frontend.dockController.isNil:
    result.errors.add "The Kosmo frontend is closed"
    return
  let loaded = loadKosmoShortcutConfiguration(path)
  result.applied = loaded.applied
  result.errors = loaded.errors
  frontend.dockController.shortcutBindings = loaded.configuration.bindings
  frontend.dockController.shortcutProfile = loaded.configuration.profile
  frontend.dockController.editorInputPolicy = loaded.configuration.editorInput
  for host in frontend.dockController.hosts:
    frontend.dockController.installShortcutBindings(host.window)
  frontend.synchronizeKosmoMenuBindings()
  frontend.updateShortcutSettingsWindow()

proc openPath*(frontend: KosmoApplication, path: string): bool {.discardable.} =
  ## Open a file here, or add a folder to this window's visible browser.
  if frontend.isNil or frontend.xClosed or frontend.dockController.isNil:
    return
  if dirExists(path):
    if not frontend.hasFileBrowser():
      if frontend.xWindowManager.isNil:
        return
      return not frontend.xWindowManager[].openProject(path).isNil
    let root = normalizedPath(absolutePath(path))
    result = root in frontend.fileTree.rootPaths or frontend.fileTree.addRootPath(root)
  elif fileExists(path) or (not dirExists(path) and dirExists(path.parentDir())):
    let view = frontend.dockController.activeEditorView()
    if not view.isNil:
      result = view.openFile(path)
  if result and dirExists(path):
    frontend.updateProjectWindowTitle()
    if not frontend.searchPanel.isNil:
      frontend.searchPanel.rootPaths = frontend.fileTree.rootPaths

proc frontendForCliRequest(
    manager: KosmoWindowManager, originWindow: string
): KosmoApplication =
  if originWindow.len > 0:
    for frontend in manager.frontends:
      if not frontend.xClosed and frontend.xCliWindowId == originWindow:
        return frontend
  manager.activeFrontend()

proc openCliRequest(
    manager: KosmoWindowManager, request: KosmoCliOpenRequest
): KosmoCliOpenResponse =
  if manager.isNil:
    result.errors.add "Kosmo has no active window manager"
    return
  if request.kind == kcrOpenStdin:
    var destination = manager.frontendForCliRequest(request.originWindow)
    if destination.isNil:
      destination = newKosmoApplication(manager, hasFileBrowser = false)
    let controller = destination.dockController
    let group = controller.activePaneGroup()
    let id = controller.editor.newStdinBuffer(
      request.stdinName, request.stdinText, request.workingDirectory
    )
    if id.isNone:
      result.errors.add "Kosmo could not create the stdin buffer"
    else:
      group.addBuffer(id.get)
      controller.activatePaneTab(group, id.get.tabIdentifier)
      destination.show()
    result.delivered = true
    return
  if request.kind == kcrShowDiff:
    var destination = manager.frontendForCliRequest(request.originWindow)
    if destination.isNil:
      destination = newKosmoApplication(manager, hasFileBrowser = false)
      destination.show()
    let snapshot = parseGitDiff(request.diffText, request.workingDirectory)
    if not destination.showGitDiffSnapshot(snapshot, refreshesRepository = false):
      result.errors.add "Kosmo could not open the piped Git diff"
    elif snapshot.errorMessage.len > 0:
      result.errors.add snapshot.errorMessage
    result.delivered = true
    return
  var
    folders: seq[string]
    files: seq[string]
  for path in request.paths:
    if dirExists(path):
      folders.add path
    elif fileExists(path) or dirExists(path.parentDir()):
      files.add path
    else:
      result.errors.add "Kosmo cannot open path: " & path

  var destination: KosmoApplication
  if folders.len > 0:
    destination = manager.openProject(folders[0])
    if destination.isNil:
      result.errors.add "Kosmo could not open project folder: " & folders[0]
    else:
      for index in 1 ..< folders.len:
        if not destination.openPath(folders[index]):
          result.errors.add "Kosmo could not add project folder: " & folders[index]
  elif files.len > 0:
    destination = manager.frontendForCliRequest(request.originWindow)
    if destination.isNil:
      destination = newKosmoApplication(manager, hasFileBrowser = false)

  if not destination.isNil:
    for path in files:
      if not destination.openPath(path):
        result.errors.add "Kosmo could not open file: " & path
    destination.show()
  result.delivered = true

when defined(merendaTests):
  proc openCliRequestForTesting*(
      manager: KosmoWindowManager, request: KosmoCliOpenRequest
  ): KosmoCliOpenResponse =
    manager.openCliRequest(request)

  proc saveActiveTabForTesting*(
      frontend: KosmoApplication, panel: nimkit.SavePanel
  ): bool {.discardable.} =
    if frontend.isNil or frontend.dockController.isNil:
      return
    frontend.dockController.saveCurrentPaneTab(
      frontend.dockController.activePaneGroup(), panel
    )

proc openDocument*(
    frontend: KosmoApplication, document: KosmoPaneDocument
): bool {.discardable.} =
  ## Open any view-backed document in the currently focused pane.
  if frontend.isNil or frontend.dockController.isNil:
    return
  let group = frontend.dockController.activePaneGroup()
  frontend.dockController.openPaneDocument(group, document)

proc openTerminal*(
    frontend: KosmoApplication, options = nimkit.initTerminalSpawnOptions()
): bool {.discardable.} =
  ## Open a terminal document in the currently focused pane.
  if frontend.isNil or frontend.dockController.isNil:
    return
  var resolvedOptions = options
  if resolvedOptions.workingDirectory.len == 0:
    resolvedOptions.workingDirectory = frontend.fileTree.rootPath
  let group = frontend.dockController.activePaneGroup()
  frontend.dockController.openTerminal(group, resolvedOptions)

proc editorGroups*(frontend: KosmoApplication): seq[KosmoEditorGroup] =
  ## Return the editor groups currently hosted by Kosmo dock workspaces.
  if not frontend.isNil and not frontend.dockController.isNil:
    result = frontend.dockController.groups

proc detachedEditorWindows*(frontend: KosmoApplication): seq[nimkit.Window] =
  ## Return the live windows created by detaching document tabs.
  if frontend.isNil or frontend.dockController.isNil:
    return
  for host in frontend.dockController.hosts:
    if not host.primary and not host.window.isNil and not host.window.isClosed():
      result.add host.window

proc show*(frontend: KosmoApplication) =
  ## Present the Kosmo window and make the editor its first responder.
  if not frontend.isNil:
    discard frontend.application.showWindow(
      frontend.window, frontend.contentView, frontend.dockController.activeEditorView()
    )

proc close*(frontend: KosmoApplication) =
  ## Release the editor resources held by the frontend.
  if frontend.isNil or frontend.xClosed:
    return
  frontend.xClosed = true
  if not frontend.quickOpenPanel.isNil and frontend.quickOpenPanel.isOpen():
    frontend.quickOpenPanel.dismiss()
  if not frontend.xSettingsWindow.isNil and
      not frontend.xSettingsWindow.window.isClosed():
    frontend.xSettingsWindow.window.close()
  if not frontend.dockController.isNil:
    for group in frontend.dockController.groups:
      group.editorView.stopMatterHighlightRefresh()
      group.editorView.tabsDelegate.stopObservingWindow()
      group.pane.clearMarkdownPreviews()
      for document in group.documents:
        discard document.close()
    let hosts = frontend.dockController.hosts
    for host in hosts:
      if not host.primary and not host.window.isNil and not host.window.isClosed():
        host.window.close()
  if not frontend.sidebarPane.isNil:
    frontend.sidebarPane.stopObservingWindow()
  if not frontend.quickOpenPanel.isNil:
    frontend.quickOpenPanel.stopObservingWindow()
  if not frontend.editorView.isNil:
    frontend.editorView.editor.close()
  if not frontend.searchPanel.isNil:
    frontend.searchPanel.close()
  if not frontend.fileTree.isNil:
    frontend.fileTree.stopGitStatusMonitoring()
    frontend.fileTree.workspaceFiles.close()
  if not frontend.xWindowManager.isNil:
    frontend.xWindowManager[].unregister(frontend)

proc close*(manager: KosmoWindowManager) =
  ## Release every live frontend owned by this Kosmo session.
  if manager.isNil:
    return
  let frontends = manager.frontends
  manager.frontends.setLen(0)
  for frontend in frontends:
    frontend.close()

proc runKosmoRequest*(initialRequest: Option[KosmoCliOpenRequest]) =
  let
    app = nimkit.sharedApplication()
    keyBindingsPath = defaultKosmoKeyBindingsPath()
    configPath = defaultKosmoConfigPath()
    manager = newKosmoWindowManager(
      app,
      keyBindingsPath = if fileExists(keyBindingsPath): keyBindingsPath else: "",
      configPath = configPath,
    )
  defer:
    manager.close()
  try:
    manager.cliServer = startKosmoCliOpenServer(
      proc(request: KosmoCliOpenRequest): KosmoCliOpenResponse =
        manager.openCliRequest(request)
    )
  except CatchableError as error:
    stderr.writeLine("Kosmo CLI routing is unavailable: " & error.msg)
  defer:
    if not manager.cliServer.isNil:
      manager.cliServer.close()

  if initialRequest.isNone:
    newKosmoApplication(manager).show()
  else:
    let response = manager.openCliRequest(initialRequest.get())
    for message in response.errors:
      stderr.writeLine(message)
  app.run()
