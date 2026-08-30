import std/[monotimes, options, os, osproc, strutils, tempfiles, times, unittest]

import figdraw
import sigils/threads

import merenda/nimkit
import merenda/nimkit/text/monotextviews as monoTextViews
import merenda/kosmo/kosmo

proc hasSidebarPaneOutline(
    view: View, outlineColor: Color, outlineWidth: float32
): bool =
  let renders = buildRenders(view)[DefaultDrawLevel]
  for node in renders.nodes:
    if node.kind == nkRectangle and node.stroke.weight == outlineWidth and
        node.stroke.fill.kind == flColor and node.stroke.fill.color == outlineColor.rgba:
      return true

suite "Kosmo":
  test "frontend installs Kosmo settings with terminal Meta enabled by default":
    let app = newApplication("Kosmo Test")
    let frontend = newKosmoApplication(app)
    defer:
      frontend.close()
    let
      mainMenu = app.mainMenu()
      applicationMenu = mainMenu[0].submenu()
      fileMenu = mainMenu[1].submenu()
      windowMenu = mainMenu[3].submenu()
      settingsItem = applicationMenu[2]
    let openItem = fileMenu.menuItemWithIdentifier(KosmoOpenFileAction)
    let terminalItem = fileMenu.menuItemWithIdentifier(KosmoNewTerminalAction)

    check mainMenu.len == 5
    check mainMenu[0].title == "Kosmo Test"
    check mainMenu[1].title == "File"
    check mainMenu[2].title == "Edit"
    check mainMenu[3].title == "Window"
    check mainMenu[4].title == "Help"
    check settingsItem.title == "Settings…"
    check settingsItem.action().name == actionSelector(KosmoShowSettingsAction).name
    var includesMerendaSettings = false
    for item in windowMenu.items():
      if item.action().name == actionSelector("showMerendaSettings").name:
        includesMerendaSettings = true
    check not includesMerendaSettings
    check not openItem.isNil
    check openItem.title == "Open…"
    check not terminalItem.isNil
    check terminalItem.title == "New Terminal"
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.contentView.menuBar().hidden() == app.usesNativeMainMenu()
    if app.usesNativeMainMenu():
      check frontend.contentView.contentView().frame().origin.y == 0.0'f32
    check frontend.splitView.panes() ==
      @[View(frontend.sidebarPane), View(frontend.dockView)]
    check frontend.sidebarTabs.len == 2
    check frontend.sidebarTabs[0].identifier == KosmoFilesTabIdentifier
    check frontend.sidebarTabs[1].identifier == KosmoFindTabIdentifier

    app.addWindow(frontend.window)
    check settingsItem.perform(Responder(frontend.editorView))
    check app.windows.len == 2
    let settingsPanel = app.windows[^1]
    check settingsPanel.title == "Kosmo Settings"
    check settingsPanel.contentView().viewWithIdentifier("settings-theme-picker").isNil
    let tabsView =
      settingsPanel.contentView().viewWithIdentifier(KosmoSettingsTabsIdentifier)
    require not tabsView.isNil
    require tabsView of TabView
    let settingsTabs = TabView(tabsView)
    check settingsTabs.len == 3
    check settingsTabs[0].label == "Terminal"
    check settingsTabs[0].identifier == KosmoTerminalSettingsTabIdentifier
    check settingsTabs[1].label == "Shortcuts"
    check settingsTabs[1].identifier == KosmoShortcutsSettingsTabIdentifier
    check settingsTabs[2].label == "Moe Themes"
    check settingsTabs[2].identifier == KosmoMoeThemesSettingsTabIdentifier
    check settingsTabs.selectedIndex == 0
    check settingsTabs.selectTabViewItemAtIndex(1)

    let shortcutsView =
      settingsPanel.contentView().viewWithIdentifier(KosmoShortcutsTableIdentifier)
    require not shortcutsView.isNil
    require shortcutsView of TableView
    let
      shortcutsTable = TableView(shortcutsView)
      actionColumn =
        shortcutsTable.columnWithIdentifier(KosmoShortcutActionColumnIdentifier)
      descriptionColumn =
        shortcutsTable.columnWithIdentifier(KosmoShortcutDescriptionColumnIdentifier)
      keysColumn =
        shortcutsTable.columnWithIdentifier(KosmoShortcutKeysColumnIdentifier)
    check shortcutsTable.columnCount == 3
    require not actionColumn.isNil
    require not descriptionColumn.isNil
    require not keysColumn.isNil
    check actionColumn.title == "Action"
    check descriptionColumn.title == "Description"
    check keysColumn.title == "Shortcut Keys"
    check shortcutsTable.rowCount == initKosmoKeyBindings().bindings.len
    check shortcutsTable.selectionMode == tsmNone

    var
      saveRow = -1
      horizontalSplitRow = -1
      verticalSplitRow = -1
    for row in 0 ..< shortcutsTable.rowCount:
      let action = shortcutsTable.tableCellText(row, actionColumn)
      check shortcutsTable.tableCellText(row, descriptionColumn).len > 0
      check shortcutsTable.tableCellText(row, keysColumn).len > 0
      case action
      of KosmoSaveAction:
        saveRow = row
      of KosmoSplitHorizontalAction:
        horizontalSplitRow = row
      of KosmoSplitVerticalAction:
        verticalSplitRow = row
      else:
        discard
    require saveRow >= 0
    require horizontalSplitRow >= 0
    require verticalSplitRow >= 0
    check shortcutsTable.tableCellText(saveRow, keysColumn) == "Cmd+S"
    check shortcutsTable.tableCellText(horizontalSplitRow, keysColumn) == "Ctrl+W Ctrl+S"
    check shortcutsTable.tableCellText(verticalSplitRow, keysColumn) == "Ctrl+W Ctrl+V"
    check not shortcutsTable.beginEditingCell(saveRow, keysColumn)
    check settingsTabs.selectTabViewItemAtIndex(2)

    let moeThemeView =
      settingsPanel.contentView().viewWithIdentifier(KosmoMoeThemeSelectorIdentifier)
    require not moeThemeView.isNil
    require moeThemeView of ComboBox
    let moeThemeSelector = ComboBox(moeThemeView)
    check moeThemeSelector.numberOfItems() >= 2
    let defaultThemeIndex =
      moeThemeSelector.indexOfOptionIdentifier(KosmoMoeDefaultThemeIdentifier)
    require defaultThemeIndex >= 0
    for expectedName in [
      "Catppuccin Latte", "Catppuccin Mocha", "Kanagawa Wave", "One Dark",
      "Tokyo Night Moon",
    ]:
      check moeThemeSelector.indexOfItem(expectedName) >= 0
    check moeThemeSelector.selectedOptionIdentifier ==
      frontend.editorView.editor.activeMoeThemeIdentifier()
    let catppuccinIndex = moeThemeSelector.indexOfItem("Catppuccin Mocha")
    require catppuccinIndex >= 0
    moeThemeSelector.activateItemAtIndex(catppuccinIndex)
    check frontend.editorView.editor.activeMoeThemeIdentifier() ==
      moeThemeSelector.selectedOptionIdentifier
    check frontend.settingsWindow().selectedMoeThemeIdentifier() ==
      moeThemeSelector.selectedOptionIdentifier
    moeThemeSelector.activateItemAtIndex(defaultThemeIndex)
    check frontend.editorView.editor.activeMoeThemeIdentifier() ==
      KosmoMoeDefaultThemeIdentifier
    check frontend.settingsWindow().selectedMoeThemeIdentifier() ==
      KosmoMoeDefaultThemeIdentifier
    check settingsTabs.selectTabViewItemAtIndex(0)

    let optionView =
      settingsPanel.contentView().viewWithIdentifier(KosmoOptionAsMetaIdentifier)
    require not optionView.isNil
    require optionView of Button
    let optionButton = Button(optionView)
    check frontend.terminalOptionAsMeta
    check optionButton.state == bsOn

    let terminalView = newTerminalView()
    check frontend.openDocument(
      newKosmoPaneDocument("kosmo.test.terminal", "Terminal", terminalView)
    )
    check terminalView.optionAsMeta
    check optionButton.tryToPerform(performClick(), DynamicAgent(optionButton))
    check optionButton.state == bsOff
    check not frontend.terminalOptionAsMeta
    check not terminalView.optionAsMeta
    settingsPanel.close()
    frontend.window.close()

  test "sidebar focus highlights file and search panes with the pane accent outline":
    let frontend = newKosmoApplication(newApplication("Kosmo Sidebar Focus Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 760, 520)
    frontend.contentView.layoutSubtreeIfNeeded()

    let
      paneIndicatorContext = controlStyle(srBox, id = KosmoPaneIndicatorStyleId)
      paneAppearance = frontend.editorView.effectiveAppearance()
      paneOutlineColor = paneAppearance.resolveColor(
        paneIndicatorContext, StyleBorderColor, color(0.0, 0.0, 0.0, 0.0)
      )
      paneOutlineWidth =
        paneAppearance.resolveLength(paneIndicatorContext, StyleBorderWidth, 0.0'f32)
    check paneOutlineColor.a > 0.0'f32
    check paneOutlineColor.a < 1.0'f32
    check paneOutlineWidth > 0.0'f32

    check frontend.window.makeFirstResponder(frontend.editorView)
    frontend.fileTree.selectedItemIdentifier = frontend.fileTree.rootPath
    check not frontend.fileTree.showsFocusedRowHighlight
    check not frontend.searchPanel.resultsView.showsFocusedRowHighlight
    check not frontend.sidebarPane.hasSidebarPaneOutline(
      paneOutlineColor, paneOutlineWidth
    )

    check frontend.showFileExplorer()
    check frontend.window.firstResponder == frontend.fileTree
    check frontend.fileTree.showsFocusedRowHighlight
    check frontend.searchPanel.resultsView.showsFocusedRowHighlight
    check frontend.sidebarPane.hasSidebarPaneOutline(paneOutlineColor, paneOutlineWidth)
    check frontend.editorPane.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)

    check frontend.window.makeFirstResponder(frontend.editorView)
    check not frontend.fileTree.showsFocusedRowHighlight
    check not frontend.searchPanel.resultsView.showsFocusedRowHighlight
    check not frontend.sidebarPane.hasSidebarPaneOutline(
      paneOutlineColor, paneOutlineWidth
    )
    check not frontend.editorPane.documentTabs.hasStyleClass(
      KosmoInactivePaneStyleClass
    )

    check frontend.showFindInFiles()
    check frontend.window.firstResponder == frontend.window.fieldEditor()
    check frontend.window.fieldEditorClient() == frontend.searchPanel.queryField
    check frontend.fileTree.showsFocusedRowHighlight
    check frontend.searchPanel.resultsView.showsFocusedRowHighlight
    check frontend.sidebarPane.hasSidebarPaneOutline(paneOutlineColor, paneOutlineWidth)
    check frontend.editorPane.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)

    check frontend.window.makeFirstResponder(frontend.searchPanel.resultsView)
    check frontend.sidebarPane.hasSidebarPaneOutline(paneOutlineColor, paneOutlineWidth)
    check frontend.window.makeFirstResponder(frontend.editorView)
    check not frontend.sidebarPane.hasSidebarPaneOutline(
      paneOutlineColor, paneOutlineWidth
    )

  test "sidebar shortcuts focus the explorer and open clicked search results":
    let
      root = createTempDir("merenda-kosmo-find-sidebar-", "")
      alphaPath = root / "alpha.txt"
      betaPath = root / "beta.nim"
      frontend = newKosmoApplication(newApplication("Kosmo Find Sidebar Test"))
    var alphaContents = ""
    for line in 1 .. 80:
      if line == 41:
        alphaContents.add "second λ needle\n"
      else:
        alphaContents.add "alpha line " & $line & "\n"
    writeFile(alphaPath, alphaContents)
    writeFile(betaPath, "let needleValue = 1\n")
    defer:
      frontend.close()
      removeFile(alphaPath)
      removeFile(betaPath)
      removeDir(root)

    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 760, 520)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(root)
    check frontend.sidebarTabs.selectedIndex == 0
    check not frontend.fileTree.hidden
    check frontend.searchPanel.hidden
    let findTabPoint = frontend.sidebarTabs.pointToWindow(
      initPoint(
        frontend.sidebarTabs.tabWidth * 1.5'f32,
        frontend.sidebarTabs.tabBarHeight * 0.5'f32,
      )
    )
    check frontend.window.mouseDownAt(findTabPoint)
    check frontend.window.mouseUpAt(findTabPoint)
    check frontend.sidebarTabs.selectedIndex == 1
    let filesTabPoint = frontend.sidebarTabs.pointToWindow(
      initPoint(
        frontend.sidebarTabs.tabWidth * 0.5'f32,
        frontend.sidebarTabs.tabBarHeight * 0.5'f32,
      )
    )
    check frontend.window.mouseDownAt(filesTabPoint)
    check frontend.window.mouseUpAt(filesTabPoint)
    check frontend.sidebarTabs.selectedIndex == 0
    check frontend.window.makeFirstResponder(frontend.editorView)

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: {kmCommand, kmShift})
    )
    check frontend.sidebarTabs.selectedIndex == 1
    check frontend.fileTree.hidden
    check not frontend.searchPanel.hidden
    check frontend.searchPanel.queryField.isEditing
    check frontend.window.firstResponder == frontend.window.fieldEditor()

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyE, keyCode: keyE.ord, modifiers: {kmCommand, kmShift})
    )
    check frontend.sidebarTabs.selectedIndex == 0
    check not frontend.fileTree.hidden
    check frontend.searchPanel.hidden
    check frontend.window.firstResponder == frontend.fileTree

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: {kmCommand, kmShift})
    )
    check frontend.sidebarTabs.selectedIndex == 1
    check frontend.searchPanel.queryField.isEditing

    check frontend.window.dispatchTextInput("needle")
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
    )
    check not frontend.searchPanel.progressIndicator.hidden
    check frontend.searchPanel.progressIndicator.animating
    check not frontend.searchPanel.cancelButton.hidden
    check frontend.searchPanel.waitForSearch(timeoutMilliseconds = 10_000)
    check frontend.searchPanel.progressIndicator.hidden
    check not frontend.searchPanel.progressIndicator.animating
    check frontend.searchPanel.cancelButton.hidden
    check frontend.searchPanel.resultsView.matches.len == 2
    check frontend.searchPanel.resultsView.rowCount == 4
    check frontend.searchPanel.statusLabel.text == "2 results"

    let
      firstResultIdentifier = frontend.searchPanel.resultsView.matchIdentifier(0)
      firstFileIdentifier =
        frontend.searchPanel.resultsView.parentIdentifierForItem(firstResultIdentifier)
      firstFileItem =
        frontend.searchPanel.resultsView.outlineItemWithIdentifier(firstFileIdentifier)
    check firstFileIdentifier.len > 0
    check firstFileItem.title == "alpha.txt"
    check firstFileItem.decoration.badge == "1"
    check frontend.searchPanel.resultsView.isItemExpanded(firstFileIdentifier)

    frontend.contentView.layoutSubtreeIfNeeded()
    discard frontend.window.buildRenders()
    let
      resultRow = frontend.searchPanel.resultsView.rowForItem(firstResultIdentifier)
      resultRect = frontend.searchPanel.resultsView.rowItemRect(resultRow)
      resultPoint = frontend.searchPanel.resultsView.pointToWindow(
        initPoint(
          resultRect.origin.x + resultRect.size.width * 0.5'f32,
          resultRect.origin.y + resultRect.size.height * 0.5'f32,
        )
      )
    check frontend.window.mouseDownAt(resultPoint)
    check frontend.window.mouseUpAt(resultPoint)
    let tabs = frontend.editorView.editor.tabs()
    check tabs.len == 1
    check tabs[0].title == "alpha.txt"
    check tabs[0].temporary
    check frontend.editorView.editor.bufferCursor() ==
      KosmoBufferCursor(line: 40, column: 9)
    check abs(
      frontend.editorView.editor.cursor().row - frontend.editorView.lineCount div 2
    ) <= 1
    check frontend.window.mouseDownAt(resultPoint, clickCount = 2)
    check frontend.window.mouseUpAt(resultPoint, clickCount = 2)
    check not frontend.editorView.editor.tabs()[0].temporary

  test "find sidebar cancel button stops an active search":
    let
      root = createTempDir("merenda-kosmo-find-cancel-", "")
      path = root / "search.txt"
      panel = newKosmoFileSearchPanel(root)
      window = newWindow("Kosmo Find Cancel Test", rect(0, 0, 280, 320))
    writeFile(path, "needle\n")
    defer:
      panel.close()
      window.close()
      removeFile(path)
      removeDir(root)

    window.setContentView(panel)
    panel.frame = window.contentView().bounds()
    panel.layoutSubtreeIfNeeded()
    check window.makeFirstResponder(panel.queryField)
    check window.dispatchTextInput("needle")
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    let handle = panel.activeSearch()
    check not handle.isNil
    check not panel.progressIndicator.hidden
    check panel.progressIndicator.animating
    check not panel.cancelButton.hidden

    panel.layoutSubtreeIfNeeded()
    let cancelPoint = panel.cancelButton.pointToWindow(
      initPoint(
        panel.cancelButton.bounds().size.width * 0.5'f32,
        panel.cancelButton.bounds().size.height * 0.5'f32,
      )
    )
    check window.mouseDownAt(cancelPoint)
    check window.mouseUpAt(cancelPoint)
    check handle.cancelRequested
    check not panel.cancelButton.enabled
    check panel.statusLabel.text == "Cancelling…"
    check panel.waitForSearch(timeoutMilliseconds = 10_000)
    check panel.statusLabel.text == "Search cancelled"
    check panel.progressIndicator.hidden
    check not panel.progressIndicator.animating
    check panel.cancelButton.hidden

  test "find sidebar streams results while recursive search remains active":
    let
      root = createTempDir("merenda-kosmo-find-stream-", "")
      nested = root / "nested"
      latePath = nested / "late.txt"
      panel = newKosmoFileSearchPanel(root)
      window = newWindow("Kosmo Find Stream Test", rect(0, 0, 320, 420))
    createDir(nested)
    writeFile(root / "first.txt", "needle\n" & repeat('x', 8 * 1024 * 1024))
    defer:
      panel.close()
      window.close()
      removeDir(root)

    window.setContentView(panel)
    panel.frame = window.contentView().bounds()
    panel.layoutSubtreeIfNeeded()
    check window.makeFirstResponder(panel.queryField)
    check window.dispatchTextInput("needle")
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    let handle = panel.activeSearch()

    let deadline = getMonoTime() + initDuration(seconds = 10)
    while panel.resultsView.matches.len == 0 and getMonoTime() < deadline:
      discard getCurrentSigilThread().pollAll(NonBlocking)
      if panel.resultsView.matches.len == 0:
        sleep(1)

    let
      streamedMatchCount = panel.resultsView.matches.len
      streamedRowCount = panel.resultsView.rowCount
      searchWasFinished = handle.isFinished()
      streamedStatus = panel.statusLabel.text
    writeFile(latePath, "late needle\n")

    check streamedMatchCount == 1
    check streamedRowCount == 2
    check not searchWasFinished
    check streamedStatus == "1 result…"
    check panel.waitForSearch(timeoutMilliseconds = 10_000)
    check panel.resultsView.matches.len == 2
    check panel.resultsView.matches[1].path == latePath

  test "find results group by file and reveal more matches in fixed-size pages":
    let
      root = createTempDir("merenda-kosmo-find-groups-", "")
      path = root / "many.txt"
      panel = newKosmoFileSearchPanel(root)
      window = newWindow("Kosmo Find Groups Test", rect(0, 0, 320, 420))
    var contents = ""
    for line in 1 .. 65:
      contents.add "needle " & $line & "\n"
    writeFile(path, contents)
    defer:
      panel.close()
      window.close()
      removeFile(path)
      removeDir(root)

    var
      openedLine = 0
      openDisposition = fodPermanent
    panel.onOpenResult = proc(
        match: FileSearchMatch, disposition: FileTreeOpenDisposition
    ) =
      openedLine = match.line
      openDisposition = disposition
    window.setContentView(panel)
    panel.frame = window.contentView().bounds()
    panel.layoutSubtreeIfNeeded()
    check window.makeFirstResponder(panel.queryField)
    check window.dispatchTextInput("needle")
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check panel.waitForSearch(timeoutMilliseconds = 10_000)

    let
      results = panel.resultsView
      firstResultIdentifier = results.matchIdentifier(0)
      fileIdentifier = results.parentIdentifierForItem(firstResultIdentifier)
      fileItem = results.outlineItemWithIdentifier(fileIdentifier)
    check results.matches.len == 65
    check results.rowCount == 32
    check fileItem.title == "many.txt"
    check fileItem.decoration.badge == "65"
    check results.isItemExpanded(fileIdentifier)

    proc clickSearchRow(identifier: string): bool =
      if not results.selectItemWithIdentifier(identifier):
        return false
      discard window.buildRenders()
      let
        row = results.rowForItem(identifier)
        rowRect = results.rowItemRect(row)
        point = results.pointToWindow(
          initPoint(
            rowRect.origin.x + rowRect.size.width * 0.5'f32,
            rowRect.origin.y + rowRect.size.height * 0.5'f32,
          )
        )
      window.mouseDownAt(point, clickCount = 1) and
        window.mouseUpAt(point, clickCount = 1)

    check clickSearchRow(fileIdentifier)
    check results.rowCount == 1
    check not results.isItemExpanded(fileIdentifier)
    check clickSearchRow(fileIdentifier)
    check results.rowCount == 32

    var loadMoreIdentifier = results.itemIdentifierForRow(results.rowCount - 1)
    check results.outlineItemWithIdentifier(loadMoreIdentifier).title.startsWith(
      "Load 30"
    )
    check clickSearchRow(loadMoreIdentifier)
    check results.rowCount == 62

    loadMoreIdentifier = results.itemIdentifierForRow(results.rowCount - 1)
    check results.outlineItemWithIdentifier(loadMoreIdentifier).title.startsWith(
      "Load 5"
    )
    check clickSearchRow(loadMoreIdentifier)
    check results.rowCount == 66

    let lastResultIdentifier = results.matchIdentifier(64)
    check results.rowForItem(lastResultIdentifier) == 65
    check clickSearchRow(lastResultIdentifier)
    check openedLine == 65
    check openDisposition == fodTemporary

  test "selecting a result stays responsive at the search result limit":
    let
      root = createTempDir("merenda-kosmo-find-limit-", "")
      frontend = newKosmoApplication(newApplication("Kosmo Find Limit Test"))
      contents = "needle\n".repeat(1_000)
    for index in 0 ..< 10:
      writeFile(root / (align($index, 2, '0') & ".txt"), contents)
    defer:
      frontend.close()
      removeDir(root)

    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 760, 520)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(root)
    check frontend.window.makeFirstResponder(frontend.editorView)
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: {kmCommand, kmShift})
    )
    check frontend.window.dispatchTextInput("needle")
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
    )
    check frontend.searchPanel.waitForSearch(timeoutMilliseconds = 10_000)
    check frontend.searchPanel.resultsView.matches.len == DefaultFileSearchMaxResults

    frontend.contentView.layoutSubtreeIfNeeded()
    discard frontend.window.buildRenders()
    let
      resultIdentifier = frontend.searchPanel.resultsView.matchIdentifier(10)
      resultRow = frontend.searchPanel.resultsView.rowForItem(resultIdentifier)
      resultRect = frontend.searchPanel.resultsView.rowItemRect(resultRow)
      resultPoint = frontend.searchPanel.resultsView.pointToWindow(
        initPoint(
          resultRect.origin.x + resultRect.size.width * 0.5'f32,
          resultRect.origin.y + resultRect.size.height * 0.5'f32,
        )
      )
      started = getMonoTime()
    check frontend.window.mouseDownAt(resultPoint)
    check frontend.window.mouseUpAt(resultPoint)
    let activationTime = getMonoTime() - started

    check activationTime.inMilliseconds < 750
    check frontend.editorView.editor.bufferCursor() ==
      KosmoBufferCursor(line: 10, column: 0)
    check frontend.editorView.editor.tabs()[0].temporary

  when defined(posix):
    test "File menu opens a terminal as a fully managed pane tab":
      let
        frontend = newKosmoApplication(newApplication("Kosmo Terminal Tab Test"))
        fileMenu = frontend.application.mainMenu()[1].submenu()
        terminalItem = fileMenu.menuItemWithIdentifier(KosmoNewTerminalAction)
        initialTabCount = frontend.documentTabs.len
      defer:
        frontend.close()
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.layoutSubtreeIfNeeded()
      check frontend.window.makeFirstResponder(frontend.editorView)

      check frontend.terminalOptionAsMeta
      frontend.terminalOptionAsMeta = false
      check terminalItem.perform(Responder(frontend.editorView))
      check frontend.editorGroups().len == 1
      check frontend.editorGroups()[0].documents.len == 1
      check frontend.documentTabs.len == initialTabCount + 1
      check frontend.documentTabs.selectedDocumentTabItem().title == "Terminal 1"
      check frontend.editorPane.contentView of TerminalView
      let terminalView = TerminalView(frontend.editorPane.contentView)
      check not terminalView.optionAsMeta
      check terminalView.session().running()
      check frontend.window.firstResponder() == Responder(terminalView)
      check terminalView.focusVisible
      check terminalView.focusRingType == frtNone

      check frontend.window.dispatchKeyDown(
        KeyEvent(
          key: keyLeftBracket,
          keyCode: keyLeftBracket.ord,
          modifiers: {kmCommand, kmShift},
        )
      )
      check frontend.editorPane.contentView == View(frontend.editorView)
      check frontend.window.dispatchKeyDown(
        KeyEvent(
          key: keyRightBracket,
          keyCode: keyRightBracket.ord,
          modifiers: {kmCommand, kmShift},
        )
      )
      check frontend.editorPane.contentView == View(terminalView)

      check frontend.window.dispatchKeyDown(
        KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
      )
      check frontend.documentTabs.len == initialTabCount + 1
      check frontend.window.dispatchKeyDown(
        KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
      )
      check frontend.editorGroups()[0].documents.len == 0
      check frontend.documentTabs.len == initialTabCount
      check frontend.editorPane.contentView == View(frontend.editorView)
      check terminalView.session().state() == tssClosed
      check frontend.window.firstResponder() == Responder(frontend.editorView)
