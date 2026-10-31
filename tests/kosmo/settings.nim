import std/[options, os, strutils, tempfiles, unicode, unittest]

import figdraw
import merenda/nimkit
import merenda/kosmo/kosmo
import fixtures/ui

proc renderedFigText(node: Fig): string =
  for glyphIndex in 0 ..< node.textLayout.glyphCount():
    result.add node.textLayout.displayRune(glyphIndex).toUTF8()

suite "Kosmo settings":
  setup:
    let app = newApplication("Kosmo Settings Test")
    let frontend = newKosmoApplication(app, monitorsGitStatus = false)
    defer:
      frontend.close()
    app.addWindow(frontend.window)
    require frontend.showSettings()
    let settingsPanel = frontend.settingsWindow().window()
    let tabsView =
      settingsPanel.contentView().viewWithIdentifier(KosmoSettingsTabsIdentifier)
    require tabsView of TabView
    let settingsTabs = TabView(tabsView)
    discard settingsPanel.buildRenders()

  test "application menus expose document actions and both settings windows":
    for action in [
      KosmoNewFileAction, KosmoOpenFileAction, KosmoOpenProjectAction,
      KosmoNewTerminalAction, KosmoShowTerminalAction, KosmoShowSettingsAction,
      "showMerendaSettings",
    ]:
      let item = app.mainMenu().menuItemForAction(action)
      require not item.isNil
      check item.title.len > 0
    let settingsItem = app.mainMenu().menuItemForAction(KosmoShowSettingsAction)
    require settingsItem.perform(Responder(frontend.editorView))
    check app.windows[^1] == settingsPanel
    check settingsPanel.title == "Kosmo Settings"
    for identifier in [
      KosmoNimdexSettingsTabIdentifier, KosmoTerminalSettingsTabIdentifier,
      KosmoShortcutsSettingsTabIdentifier, KosmoMoeThemesSettingsTabIdentifier,
      KosmoTextMateGrammarsSettingsTabIdentifier,
    ]:
      require settingsTabs.selectPage(identifier)
      settingsPanel.contentView().layoutSubtreeIfNeeded()
      settingsTabs.checkVisibleIn(settingsPanel.contentView())

  test "close shortcuts target Merenda Settings before the editor":
    let tabCount = frontend.editorView.editor.tabs().len
    for action in [KosmoCloseTabAction, KosmoCloseWindowAction]:
      let item = app.mainMenu().menuItemForAction(action)
      require not item.isNil
      require item.hasKeyEquivalent()
      let stroke = item.keyEquivalent()
      app.showMerendaSettings()
      let panel = app.windows[^1]
      require panel.title == "Merenda Settings"
      app.activateWindow(panel)
      require app.keyWindow() == panel
      require app.performMenuKeyEquivalent(
        nimkit.KeyEvent(
          key: stroke.key,
          keyCode: stroke.keyCode,
          text: stroke.text,
          modifiers: stroke.modifiers,
        )
      )
      check panel.isClosed
      check frontend.editorView.editor.tabs().len == tabCount
      check not frontend.window.isClosed
      check not settingsPanel.isClosed

  test "Close Tab menu action closes the focused Kosmo settings panel":
    app.activateWindow(settingsPanel)
    require app.keyWindow() == settingsPanel
    let closeItem = app.mainMenu().menuItemForAction(KosmoCloseTabAction)
    require not closeItem.isNil
    require closeItem.perform(Responder(settingsPanel))
    check settingsPanel.isClosed
    check not frontend.window.isClosed

  test "About identifies the application and credits Moe":
    let info = app.aboutInfo()
    check not app.icon().isNil
    check info.version == KosmoVersion
    check info.buildVersion == KosmoGitHash
    check "Moe" in info.credits
    check "GPL-3.0" in info.credits
    check ApplicationAboutLink(text: KosmoMoeUrl, url: KosmoMoeUrl) in info.creditLinks

  test "Nimdex settings connect and disconnect using the selected mode":
    var command = ""
    var connected = false
    let panel = newKosmoSettingsWindow(
      nimdexAction = proc(value: string, connect: bool): string =
        command = value
        connected = connect
    )
    defer:
      panel.close()
    let root = panel.contentView()
    let tabs = TabView(root.viewWithIdentifier(KosmoSettingsTabsIdentifier))
    require not tabs.isNil
    require tabs.selectPage(KosmoNimdexSettingsTabIdentifier)
    let mode = ComboBox(root.viewWithIdentifier("kosmo.settings.nimdex.mode"))
    let local = TextField(root.viewWithIdentifier("kosmo.settings.nimdex.local"))
    let address = TextField(root.viewWithIdentifier("kosmo.settings.nimdex.address"))
    let start = Button(root.viewWithIdentifier("kosmo.settings.nimdex.connect"))
    let stop = Button(root.viewWithIdentifier("kosmo.settings.nimdex.disconnect"))
    require not mode.isNil and not local.isNil and not address.isNil
    require not start.isNil and not stop.isNil
    local.text = "nimdex"
    mode.selectedIndex = 0
    require start.tryToPerform(performClick(), DynamicAgent(start))
    check connected
    check command.contains("nimdex") and command.endsWith(" daemon")
    mode.selectedIndex = 1
    address.text = "tcp://127.0.0.1:9257"
    require start.tryToPerform(performClick(), DynamicAgent(start))
    check command == "tcp://127.0.0.1:9257"
    require stop.tryToPerform(performClick(), DynamicAgent(stop))
    check not connected

  test "Nimdex status button opens settings when no command is configured":
    let toggle = frontend.contentView.viewWithIdentifier("kosmo.nimdex.toggle")
    require toggle of Button
    check Button(toggle).toolTip == "Start Nimdex"
    require settingsTabs.selectPage(KosmoTerminalSettingsTabIdentifier)
    require Button(toggle).tryToPerform(performClick(), DynamicAgent(toggle))
    check settingsTabs.selectedTabViewItem().identifier() ==
      KosmoNimdexSettingsTabIdentifier
    check not frontend.editorView.editor.nimdexRequested()

  test "status bar keymode popup switches editing and follows settings":
    frontend.window.setContentView(frontend.contentView)
    let choiceView =
      frontend.contentView.viewWithIdentifier(KosmoKeyModeSelectorIdentifier)
    require choiceView of PopupMenuButton
    let progress = frontend.contentView.viewWithIdentifier("kosmo.nimdex.progress")
    let percentage =
      frontend.contentView.viewWithIdentifier("kosmo.nimdex.progress.percentage")
    let spinner =
      frontend.contentView.viewWithIdentifier("kosmo.nimdex.progress.spinner")
    let nimdexButton = frontend.contentView.viewWithIdentifier("kosmo.nimdex.toggle")
    require spinner of ProgressIndicator
    check spinner.hidden
    check ProgressIndicator(spinner).progressIndicatorStyle == pisSpinning
    require progress of ProgressIndicator
    require percentage of Label
    require nimdexButton of Button
    check progress.hidden
    check percentage.hidden
    percentage.hidden = false
    progress.hidden = false
    Label(percentage).text = "100.00%"
    frontend.contentView.layoutSubtreeIfNeeded()
    percentage.superview().setNeedsLayout()
    frontend.contentView.layoutSubtreeIfNeeded()
    check percentage.frame().size.width >= Label(percentage).sizeThatFits().width
    check progress.frame().maxX <= percentage.frame().minX
    check percentage.frame().maxX <= nimdexButton.frame().minX
    check nimdexButton.frame().maxX <= choiceView.frame().minX
    percentage.hidden = true
    progress.hidden = true
    let choice = PopupMenuButton(choiceView)
    check choice.menu().len == 2
    check choice.menu()[0].title == "moe (vim)"
    check choice.menu()[1].title == "normal"
    check choice.title == "moe (vim)"
    frontend.setEditorInputPolicy(KosmoEditorInputPolicy.Vim)
    check choice.title == "moe (vim)"
    check choice.menu()[0].state == bsOn
    choice.popupPresentation = ppInline

    for width in [640.0'f32, 1000.0'f32]:
      frontend.contentView.frame = rect(0, 0, width, 480)
      frontend.contentView.layoutSubtreeIfNeeded()
      let choiceFrame = choice.rectToView(choice.bounds(), frontend.contentView)
      check abs(choiceFrame.maxX - (width - 4)) <= 1
      check abs(choiceFrame.maxY - 476) <= 1
      check choiceFrame.size.width <= 100
      check choiceFrame.size.height <= 20
      choice.checkVisibleIn(frontend.contentView)
      check frontend.statusLabel.frame().maxX < choice.frame().minX
      choice.openPopup()
      let popup = choice.superview().popupIn()
      require not popup.isNil
      check popup.rectToView(popup.bounds(), frontend.contentView).maxY <=
        choiceFrame.minY
      choice.closePopup()

    require frontend.newEditorTab()
    require frontend.window.makeFirstResponder(frontend.editorView)
    let editor = frontend.editorView.editor
    var bufferId: KosmoBufferId
    for tab in editor.tabs():
      if tab.active:
        bufferId = tab.id
    choice.openPopup()
    require choice.dispatchPopupKeyDown(KeyEvent(key: keyArrowDown))
    require choice.dispatchPopupKeyDown(KeyEvent(key: keyEnter))
    check not choice.popupOpen()
    check frontend.editorInputPolicy() == KosmoEditorInputPolicy.Native
    check frontend.forceInputMode()
    check frontend.settingsWindow().editorInputPolicy() == KosmoEditorInputPolicy.Native
    check frontend.settingsWindow().forceInputMode()
    require frontend.window.dispatchTextInput("hello")
    check editor.bufferText(bufferId).get() == "hello"
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )
    check editor.mode() == KosmoEditorMode.Insert

    require choice.menu()[0].perform(frontend.editorView)
    check frontend.editorInputPolicy() == KosmoEditorInputPolicy.Vim
    check not frontend.forceInputMode()
    check editor.handleKey("Esc")
    check editor.mode() == KosmoEditorMode.Normal
    check editor.bufferText(bufferId).get() == "hello"

    frontend.setForceInputMode(true)
    check choice.title == "moe (vim)"
    check choice.menu()[0].state == bsOn
    check choice.menu()[1].state == bsOff
    frontend.setEditorInputPolicy(KosmoEditorInputPolicy.Native)
    check choice.title == "normal"
    check choice.menu()[1].state == bsOn
    frontend.setEditorInputPolicy(KosmoEditorInputPolicy.Vim)
    check choice.title == "moe (vim)"
    frontend.setForceInputMode(false)
    check choice.title == "moe (vim)"
    check choice.menu()[0].state == bsOn

  test "loading shortcut configuration immediately updates the keymode preset":
    let
      root = createTempDir("kosmo-keymode-reload-", "")
      path = root / "keybindings.json"
      choice = PopupMenuButton(
        frontend.contentView.viewWithIdentifier(KosmoKeyModeSelectorIdentifier)
      )
    defer:
      removeFile(path)
      removeDir(root)
    require choice.menu()[1].perform(frontend.editorView)
    check choice.title == "normal"
    writeFile(path, """{"editorInput": "vim"}""")
    check frontend.loadKosmoKeyBindings(path).errors.len == 0
    check choice.title == "moe (vim)"
    check choice.menu()[0].state == bsOn
    check choice.menu()[1].state == bsOff
    writeFile(path, """{"editorInput": "native"}""")
    check frontend.loadKosmoKeyBindings(path).errors.len == 0
    check choice.title == "normal"
    check choice.menu()[1].state == bsOn

  test "reader tabs preserve the global editor keymode":
    let choice = PopupMenuButton(
      frontend.contentView.viewWithIdentifier(KosmoKeyModeSelectorIdentifier)
    )
    frontend.window.setContentView(frontend.contentView)
    for policy in KosmoEditorInputPolicy:
      frontend.setEditorInputPolicy(policy)
      let expectedIndex = if policy == KosmoEditorInputPolicy.Native: 1 else: 0
      for forced in [false, true]:
        frontend.setForceInputMode(forced)
        require frontend.showGitDiff()
        frontend.contentView.layoutSubtreeIfNeeded()
        frontend.editorView.refresh()
        check choice.title == choice.menu()[expectedIndex].title()
        check choice.menu()[expectedIndex].state == bsOn
        check frontend.editorInputPolicy() == policy
        check frontend.forceInputMode() == forced
        require frontend.openDocument(
          newKosmoPaneDocument("mode-reader", "Reader", newMarkdownView())
        )
        check choice.title == choice.menu()[expectedIndex].title()
        check choice.menu()[expectedIndex].state == bsOn
        check frontend.editorInputPolicy() == policy
        check frontend.forceInputMode() == forced
        require frontend.newEditorTab()
        check choice.title == choice.menu()[expectedIndex].title()
        check choice.menu()[expectedIndex].state == bsOn
        check frontend.editorInputPolicy() == policy
        check frontend.forceInputMode() == forced

  test "shortcut settings update input behavior and show readable bindings":
    require settingsTabs.selectPage(KosmoShortcutsSettingsTabIdentifier)
    discard settingsPanel.buildRenders()
    let
      shortcutProfileView =
        settingsPanel.contentView().viewWithIdentifier(KosmoShortcutProfileIdentifier)
      editorInputPolicyView =
        settingsPanel.contentView().viewWithIdentifier(KosmoEditorInputPolicyIdentifier)
      forceInputModeView =
        settingsPanel.contentView().viewWithIdentifier(KosmoForceInputModeIdentifier)
    require not shortcutProfileView.isNil
    require shortcutProfileView of ComboBox
    require not editorInputPolicyView.isNil
    require editorInputPolicyView of ComboBox
    require not forceInputModeView.isNil
    require forceInputModeView of Button
    let
      shortcutProfileChoice = ComboBox(shortcutProfileView)
      editorInputPolicyChoice = ComboBox(editorInputPolicyView)
      forceInputModeButton = Button(forceInputModeView)
    check shortcutProfileChoice.selectedIndex ==
      (if frontend.shortcutProfile() == KosmoShortcutProfile.MacOS: 1 else: 0)
    check editorInputPolicyChoice.selectedIndex == 2
    check frontend.editorInputPolicy() == KosmoEditorInputPolicy.Hybrid
    check not frontend.forceInputMode()
    check forceInputModeButton.state == bsOff

    shortcutProfileChoice.activateItemAtIndex(1)
    check frontend.shortcutProfile() == KosmoShortcutProfile.MacOS
    shortcutProfileChoice.activateItemAtIndex(0)
    check frontend.shortcutProfile() == KosmoShortcutProfile.Platform

    editorInputPolicyChoice.activateItemAtIndex(0)
    check frontend.editorInputPolicy() == KosmoEditorInputPolicy.Vim
    editorInputPolicyChoice.activateItemAtIndex(1)
    check frontend.editorInputPolicy() == KosmoEditorInputPolicy.Native
    editorInputPolicyChoice.activateItemAtIndex(2)
    check frontend.editorInputPolicy() == KosmoEditorInputPolicy.Hybrid

    check forceInputModeButton.tryToPerform(
      performClick(), DynamicAgent(forceInputModeButton)
    )
    check forceInputModeButton.state == bsOn
    check frontend.forceInputMode()
    check frontend.editorView.editor.mode() == KosmoEditorMode.Insert
    check forceInputModeButton.tryToPerform(
      performClick(), DynamicAgent(forceInputModeButton)
    )
    check forceInputModeButton.state == bsOff
    check not frontend.forceInputMode()

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
    require not actionColumn.isNil
    require not descriptionColumn.isNil
    require not keysColumn.isNil
    check actionColumn.title == "Action"
    check descriptionColumn.title == "Description"
    check keysColumn.title == "Shortcut Keys"
    check shortcutsTable.rowCount == kosmoActions().len
    let
      initialShortcutsWidth = shortcutsTable.frame.size.width
      initialDescriptionWidth = descriptionColumn.width
      initialSettingsFrame = settingsPanel.frame
    settingsPanel.frame = rect(
      initialSettingsFrame.origin,
      initSize(
        initialSettingsFrame.size.width + 240.0'f32,
        initialSettingsFrame.size.height + 120.0'f32,
      ),
    )
    settingsPanel.contentView().layoutSubtreeIfNeeded()
    discard settingsPanel.buildRenders()
    check shortcutsTable.frame.size.width > initialShortcutsWidth
    check descriptionColumn.width > initialDescriptionWidth
    shortcutsTable.checkVisibleIn(settingsPanel.contentView())

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
    when defined(macosx) or defined(macos):
      check shortcutsTable.tableCellText(saveRow, keysColumn) == "Cmd+S"
    else:
      check shortcutsTable.tableCellText(saveRow, keysColumn) == "Ctrl+S"
    check shortcutsTable.tableCellText(horizontalSplitRow, keysColumn) ==
      "Ctrl+W S / Ctrl+W Ctrl+S"
    check shortcutsTable.tableCellText(verticalSplitRow, keysColumn) ==
      "Ctrl+W V / Ctrl+W Ctrl+V"
    check not shortcutsTable.beginEditingCell(saveRow, keysColumn)

  test "selecting a theme updates the editor and displays a color preview":
    require settingsTabs.selectPage(KosmoMoeThemesSettingsTabIdentifier)
    discard settingsPanel.buildRenders()
    let moeThemeView =
      settingsPanel.contentView().viewWithIdentifier(KosmoMoeThemesTableIdentifier)
    require not moeThemeView.isNil
    require moeThemeView of TableView
    let
      moeThemesTable = TableView(moeThemeView)
      themeColumn =
        moeThemesTable.columnWithIdentifier(KosmoMoeThemeNameColumnIdentifier)
      previewColumn =
        moeThemesTable.columnWithIdentifier(KosmoMoeThemePreviewColumnIdentifier)
    require not themeColumn.isNil
    require not previewColumn.isNil
    check themeColumn.title == "Theme"
    check previewColumn.title == "Colors"
    check moeThemesTable.rowCount >= 2
    let defaultThemeRow =
      moeThemesTable.tableRowIndexForIdentifier(KosmoMoeDefaultThemeIdentifier)
    require defaultThemeRow >= 0
    var catppuccinRow = -1
    for expectedName in [
      "Catppuccin Latte", "Catppuccin Mocha", "Cyberdream Dark", "Cyberdream Light",
      "Dayfox", "Everforest Dark", "Everforest Light", "GitHub Dark", "GitHub Light",
      "Gruvbox Material Dark", "Gruvbox Material Light", "Kanagawa Lotus",
      "Kanagawa Wave", "Nightfox", "One Dark", "One Light", "Rose Pine",
      "Rose Pine Dawn", "Solarized Dark", "Solarized Light", "Tokyo Night Day",
      "Tokyo Night Moon",
    ]:
      var matchingRow = -1
      for row in 0 ..< moeThemesTable.rowCount:
        if moeThemesTable.tableCellText(row, themeColumn) == expectedName:
          matchingRow = row
          break
      check matchingRow >= 0
      if expectedName == "Catppuccin Mocha":
        catppuccinRow = matchingRow
    require catppuccinRow >= 0
    check moeThemesTable.tableCellText(catppuccinRow, previewColumn) ==
      KosmoMoeThemePreviewText
    let previewView = moeThemesTable.tableCellView(catppuccinRow, previewColumn)
    require not previewView.isNil
    check previewView.accessibilityLabel == KosmoMoeThemePreviewText
    previewView.frame = rect(0, 0, previewColumn.width, moeThemesTable.rowHeight)
    let previewRenders = previewView.buildRenders()[DefaultDrawLevel]
    var
      hasPreviewBackground = false
      renderedPreview = ""
    for node in previewRenders.nodes:
      if node.kind == nkRectangle:
        hasPreviewBackground = true
      elif node.kind == nkText:
        renderedPreview.add node.renderedFigText()
    check hasPreviewBackground
    check renderedPreview == KosmoMoeThemePreviewText
    let initialEditorTheme = frontend.editorView.editor.activeMoeThemeIdentifier()
    if initialEditorTheme == KosmoMoeDefaultThemeIdentifier:
      check moeThemesTable.tableRowIdentifier(moeThemesTable.selectedIndex) ==
        initialEditorTheme
    else:
      check moeThemesTable.selectedIndex == -1
    discard settingsPanel.buildRenders()
    let catppuccinRect = moeThemesTable.rowItemRect(catppuccinRow)
    let catppuccinPoint = moeThemesTable.pointToWindow(
      initPoint(
        catppuccinRect.origin.x + catppuccinRect.size.width * 0.5'f32,
        catppuccinRect.origin.y + catppuccinRect.size.height * 0.5'f32,
      )
    )
    check settingsPanel.mouseDownAt(catppuccinPoint)
    check settingsPanel.mouseUpAt(catppuccinPoint)
    check frontend.editorView.editor.activeMoeThemeIdentifier() ==
      moeThemesTable.tableRowIdentifier(catppuccinRow)
    let defaultThemeRect = moeThemesTable.rowItemRect(defaultThemeRow)
    let defaultThemePoint = moeThemesTable.pointToWindow(
      initPoint(
        defaultThemeRect.origin.x + defaultThemeRect.size.width * 0.5'f32,
        defaultThemeRect.origin.y + defaultThemeRect.size.height * 0.5'f32,
      )
    )
    check settingsPanel.mouseDownAt(defaultThemePoint)
    check settingsPanel.mouseUpAt(defaultThemePoint)
    check frontend.editorView.editor.activeMoeThemeIdentifier() ==
      KosmoMoeDefaultThemeIdentifier
    discard settingsPanel.buildRenders()

  test "theme targets keep editor and terminal choices independent":
    require settingsTabs.selectPage(KosmoMoeThemesSettingsTabIdentifier)
    let terminal = newKosmoTerminalView()
    defer:
      terminal.close()
    require frontend.openDocument(
      newKosmoPaneDocument("theme-terminal", "Terminal", terminal)
    )
    let initialPalette = terminal.palette
    let initialEditorTheme = frontend.editorView.editor.activeMoeThemeIdentifier()
    let table = TableView(
      settingsPanel.contentView().viewWithIdentifier(KosmoMoeThemesTableIdentifier)
    )
    let target = ComboBox(
      settingsPanel.contentView().viewWithIdentifier(KosmoThemeTargetIdentifier)
    )
    require not target.isNil
    check target.selectedIndex == KosmoThemeTarget.All.ord
    let themes = frontend.editorView.editor.availableMoeThemes()
    require themes.len >= 3
    proc selectTheme(identifier: string) =
      discard settingsPanel.buildRenders()
      let row = table.tableRowIndexForIdentifier(identifier)
      require row >= 0
      let bounds = table.rowItemRect(row)
      let point = table.pointToWindow(
        initPoint(bounds.origin.x + 20, bounds.origin.y + bounds.size.height / 2)
      )
      require settingsPanel.mouseDownAt(point)
      require settingsPanel.mouseUpAt(point)

    target.activateItemAtIndex(KosmoThemeTarget.Terminal.ord)
    selectTheme(themes[1].identifier)
    check frontend.editorView.editor.activeMoeThemeIdentifier() == initialEditorTheme
    check terminal.palette != initialPalette
    let terminalPalette = terminal.palette
    target.activateItemAtIndex(KosmoThemeTarget.Moe.ord)
    selectTheme(themes[2].identifier)
    check frontend.editorView.editor.activeMoeThemeIdentifier() == themes[2].identifier
    check terminal.palette == terminalPalette
    target.activateItemAtIndex(KosmoThemeTarget.All.ord)
    check table.selectedIndex == -1
    selectTheme(themes[1].identifier)
    check frontend.editorView.editor.activeMoeThemeIdentifier() == themes[1].identifier
    check terminal.palette == terminalPalette
    target.activateItemAtIndex(KosmoThemeTarget.Terminal.ord)
    check table.tableRowIdentifier(table.selectedIndex) == themes[1].identifier

    let controls = frontend.editorPane.markdownControls
    let allStyle = controls.markdownPresentationStyle(KosmoThemeTarget.Markdown)
    check controls.markdownPresentationStyle(KosmoThemeTarget.GitDiff) == allStyle
    check controls.markdownPresentationStyle(KosmoThemeTarget.GitHub) == allStyle
    target.activateItemAtIndex(KosmoThemeTarget.GitDiff.ord)
    selectTheme(themes[2].identifier)
    check controls.markdownPresentationStyle(KosmoThemeTarget.Markdown) == allStyle
    check controls.markdownPresentationStyle(KosmoThemeTarget.GitDiff) != allStyle
    check controls.markdownPresentationStyle(KosmoThemeTarget.GitHub) == allStyle
    target.activateItemAtIndex(KosmoThemeTarget.RichText.ord)
    check table.selectedIndex == -1
    selectTheme(themes[2].identifier)
    let richStyle = controls.markdownPresentationStyle(KosmoThemeTarget.Markdown)
    check richStyle != allStyle
    check controls.markdownPresentationStyle(KosmoThemeTarget.GitDiff) == richStyle
    check controls.markdownPresentationStyle(KosmoThemeTarget.GitHub) == richStyle
    target.activateItemAtIndex(KosmoThemeTarget.GitHub.ord)
    selectTheme(themes[1].identifier)
    check controls.markdownPresentationStyle(KosmoThemeTarget.GitHub) == allStyle
    check controls.markdownPresentationStyle(KosmoThemeTarget.GitDiff) == richStyle
    check controls.markdownPresentationStyle(KosmoThemeTarget.Markdown) == richStyle

  test "grammar settings list built-in and newly added languages":
    require settingsTabs.selectPage(KosmoTextMateGrammarsSettingsTabIdentifier)
    discard settingsPanel.buildRenders()
    let textMateGrammarsView = settingsPanel.contentView().viewWithIdentifier(
        KosmoTextMateGrammarsTableIdentifier
      )
    require not textMateGrammarsView.isNil
    require textMateGrammarsView of TableView
    let
      textMateGrammarsTable = TableView(textMateGrammarsView)
      grammarColumn = textMateGrammarsTable.columnWithIdentifier(
        KosmoTextMateGrammarNameColumnIdentifier
      )
      scopeColumn = textMateGrammarsTable.columnWithIdentifier(
        KosmoTextMateGrammarScopeColumnIdentifier
      )
      originColumn = textMateGrammarsTable.columnWithIdentifier(
        KosmoTextMateGrammarOriginColumnIdentifier
      )
      availableGrammars = frontend.editorView.editor.availableTextMateGrammars()
    check textMateGrammarsTable.rowCount == availableGrammars.len
    require not grammarColumn.isNil
    require not scopeColumn.isNil
    require not originColumn.isNil
    check grammarColumn.title == "Grammar"
    check scopeColumn.title == "Scope"
    check originColumn.title == "Origin"
    var foundTerraform, foundNif: bool
    for row in 0 ..< textMateGrammarsTable.rowCount:
      check textMateGrammarsTable.tableCellText(row, grammarColumn).len > 0
      check textMateGrammarsTable.tableCellText(row, scopeColumn).len > 0
      check textMateGrammarsTable.tableCellText(row, originColumn) ==
        availableGrammars[row].origin.title()
      if textMateGrammarsTable.tableCellText(row, scopeColumn) == "source.hcl.terraform":
        check textMateGrammarsTable.tableCellText(row, grammarColumn) == "Terraform"
        foundTerraform = true
      if textMateGrammarsTable.tableCellText(row, scopeColumn) == "source.nif":
        check textMateGrammarsTable.tableCellText(row, grammarColumn) == "NIF"
        check textMateGrammarsTable.tableCellText(row, originColumn) == "Built-in"
        foundNif = true
    check foundTerraform
    check foundNif

    var grammarsWithAddition = availableGrammars
    grammarsWithAddition.add KosmoTextMateGrammar(
      name: "Example Added Grammar",
      scopeName: "source.example-added",
      origin: KosmoTextMateGrammarOrigin.Added,
    )
    frontend.settingsWindow().textMateGrammars = grammarsWithAddition
    check textMateGrammarsTable.rowCount == availableGrammars.len + 1
    check textMateGrammarsTable.tableCellText(
      textMateGrammarsTable.rowCount - 1, originColumn
    ) == "Added"

  test "terminal settings immediately affect an open terminal":
    require settingsTabs.selectPage(KosmoTerminalSettingsTabIdentifier)
    let optionView =
      settingsPanel.contentView().viewWithIdentifier(KosmoOptionAsMetaIdentifier)
    require not optionView.isNil
    require optionView of Button
    let
      optionButton = Button(optionView)
      terminalLinksView =
        settingsPanel.contentView().viewWithIdentifier(KosmoTerminalLinksIdentifier)
    require not terminalLinksView.isNil
    require terminalLinksView of Button
    let terminalLinksButton = Button(terminalLinksView)
    check frontend.terminalOptionAsMeta
    check optionButton.state == bsOn
    check frontend.terminalLinksEnabled
    check terminalLinksButton.state == bsOn

    let terminalView = newTerminalView()
    check frontend.openDocument(
      newKosmoPaneDocument("kosmo.test.terminal", "Terminal", terminalView)
    )
    check terminalView.optionAsMeta
    check terminalView.allowsLinkActivation
    check optionButton.tryToPerform(performClick(), DynamicAgent(optionButton))
    check optionButton.state == bsOff
    check not frontend.terminalOptionAsMeta
    check not terminalView.optionAsMeta
    check terminalLinksButton.tryToPerform(
      performClick(), DynamicAgent(terminalLinksButton)
    )
    check terminalLinksButton.state == bsOff
    check not frontend.terminalLinksEnabled
    check not terminalView.allowsLinkActivation
