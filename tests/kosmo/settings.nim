import std/[strutils, unicode, unittest]

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
      KosmoNewTerminalAction, KosmoShowSettingsAction, "showMerendaSettings",
    ]:
      let item = app.mainMenu().menuItemForAction(action)
      require not item.isNil
      check item.title.len > 0
    let settingsItem = app.mainMenu().menuItemForAction(KosmoShowSettingsAction)
    require settingsItem.perform(Responder(frontend.editorView))
    check app.windows[^1] == settingsPanel
    check settingsPanel.title == "Kosmo Settings"
    for identifier in [
      KosmoTerminalSettingsTabIdentifier, KosmoShortcutsSettingsTabIdentifier,
      KosmoMoeThemesSettingsTabIdentifier, KosmoTextMateGrammarsSettingsTabIdentifier,
    ]:
      require settingsTabs.selectPage(identifier)
      settingsPanel.contentView().layoutSubtreeIfNeeded()
      settingsTabs.checkVisibleIn(settingsPanel.contentView())

  test "About identifies the application and credits Moe":
    let info = app.aboutInfo()
    check not app.icon().isNil
    check info.version == KosmoVersion
    check info.buildVersion == KosmoGitHash
    check "Moe" in info.credits
    check "GPL-3.0" in info.credits
    check ApplicationAboutLink(text: KosmoMoeUrl, url: KosmoMoeUrl) in info.creditLinks

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
      "Catppuccin Latte", "Catppuccin Mocha", "Kanagawa Wave", "One Dark",
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
    check moeThemesTable.tableRowIdentifier(moeThemesTable.selectedIndex) ==
      frontend.editorView.editor.activeMoeThemeIdentifier()
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
    var foundTerraform = false
    for row in 0 ..< textMateGrammarsTable.rowCount:
      check textMateGrammarsTable.tableCellText(row, grammarColumn).len > 0
      check textMateGrammarsTable.tableCellText(row, scopeColumn).len > 0
      check textMateGrammarsTable.tableCellText(row, originColumn) ==
        availableGrammars[row].origin.title()
      if textMateGrammarsTable.tableCellText(row, scopeColumn) == "source.hcl.terraform":
        check textMateGrammarsTable.tableCellText(row, grammarColumn) == "Terraform"
        foundTerraform = true
    check foundTerraform

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
