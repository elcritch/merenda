import std/[unicode, unittest]

import figdraw

import merenda/nimkit
import merenda/kosmo/kosmo
import fixtures/ui

proc renderedText(node: Fig): string =
  for glyphIndex in 0 ..< node.textLayout.glyphCount():
    result.add node.textLayout.displayRune(glyphIndex)

template checkVisibleText(view: View, expected: openArray[string]) =
  block:
    let renders = buildRenders(view)
    require DefaultDrawLevel in renders
    for text in expected:
      var found = false
      for index, node in renders[DefaultDrawLevel].nodes:
        if node.kind != nkText or node.renderedText() != text:
          continue
        found = true
        require node.textLayout.spanColors.len > 0
        check node.textLayout.spanColors[0].color.a > 0'u8
        check node.textLayout.bounding.x >= -0.1'f32
        check node.textLayout.bounding.y >= -0.1'f32
        check node.textLayout.bounding.x + node.textLayout.bounding.w <=
          node.screenBox.w + 0.1'f32
        check node.textLayout.bounding.y + node.textLayout.bounding.h <=
          node.screenBox.h + 0.1'f32
      if not found:
        checkpoint "Missing rendered settings text: " & text
      check found

suite "Kosmo settings layout":
  test "settings action controls do not retain their controller":
    var observed: BackRef[Responder]
    var option: Button
    var changes = 0
    block:
      let settings = newKosmoSettingsWindow(
        optionAsMetaHandler = proc(enabled: bool) =
          inc changes
      )
      observed{} = Responder(settings)
      option =
        Button(settings.contentView().viewWithIdentifier(KosmoOptionAsMetaIdentifier))
      check option.target() of ActionAdapter
      check not (option.target() of ClosureTarget)
      check option.sendAction()
      check changes == 1
      settings.close()
      settings.window().close()
    check observed.isNil
    check option.target() of ActionAdapter
    check option.sendAction()
    check changes == 1

  test "uses a compact stable minimum and keeps every page legible":
    let settings = newKosmoSettingsWindow(
      shortcuts = [
        KosmoShortcutSetting(
          action: "Save", description: "Save the active document", keys: "Ctrl+S"
        )
      ],
      textMateGrammars = [
        KosmoTextMateGrammar(
          name: "Nim",
          scopeName: "source.nim",
          origin: KosmoTextMateGrammarOrigin.BuiltIn,
        )
      ],
    )
    defer:
      settings.window().close()

    let window = settings.window()
    window.setContentView(settings.contentView())
    let minimumSize = window.contentMinSize()

    let comfortableSize = initSize(minimumSize.width + 20, minimumSize.height + 20)
    window.frame = rect(initPoint(180, 160), comfortableSize)
    settings.contentView().layoutSubtreeIfNeeded()
    check window.frame().size == comfortableSize
    check settings.contentView().frame().size == comfortableSize

    let tabsView =
      settings.contentView().viewWithIdentifier(KosmoSettingsTabsIdentifier)
    require not tabsView.isNil
    require tabsView of TabView
    let tabs = TabView(tabsView)

    let expectedPageText = @[
      (KosmoNimdexSettingsTabIdentifier, @["Nimdex server"]),
      (KosmoTerminalSettingsTabIdentifier, @["Terminal"]),
      (KosmoShortcutsSettingsTabIdentifier, @["Active Shortcuts"]),
      (KosmoMoeThemesSettingsTabIdentifier, @["Themes"]),
      (
        KosmoTextMateGrammarsSettingsTabIdentifier,
        @["Installed grammars", "Install more…"],
      ),
    ]
    for (identifier, pageText) in expectedPageText:
      require tabs.selectPage(identifier)
      settings.contentView().layoutSubtreeIfNeeded()
      check tabs[tabs.selectedIndex].view().frame().size.width > 0.0'f32
      check tabs[tabs.selectedIndex].view().frame().size.height > 0.0'f32
      settings.contentView().checkVisibleText(pageText)

    check tabs.selectPage(KosmoTextMateGrammarsSettingsTabIdentifier)
    let installed =
      settings.contentView().viewWithIdentifier(KosmoTextMateGrammarsTableIdentifier)
    require installed of TableView
    installed.checkVisibleIn(settings.contentView())
    check settings
      .contentView()
      .viewWithIdentifier(KosmoVscodeGrammarSearchFieldIdentifier).isNil
    check not settings.vscodeGrammarCatalog().isBusy

    let largerSize = initSize(minimumSize.width + 100, minimumSize.height + 100)
    window.frame = rect(initPoint(180, 160), largerSize)
    check window.frame().size == largerSize
    window.frame = rect(180, 160, minimumSize.width - 20, minimumSize.height - 20)
    check window.frame().size == minimumSize

  test "theme selection preserves rejected targets and refreshes current choices":
    var applied: seq[KosmoThemeTarget]
    let themes = [
      KosmoMoeThemeSetting(identifier: "first", name: "First"),
      KosmoMoeThemeSetting(identifier: "second", name: "Second"),
    ]
    let settings = newKosmoSettingsWindow(
      moeThemes = themes,
      selectedMoeThemeIdentifier = "first",
      selectedTerminalThemeIdentifier = "first",
      selectedMarkdownThemeIdentifier = "first",
      selectedGitDiffThemeIdentifier = "first",
      selectedGitHubThemeIdentifier = "first",
      moeThemeHandler = proc(identifier: string, target: KosmoThemeTarget): bool =
        applied.add target
        target != KosmoThemeTarget.Terminal,
    )
    defer:
      settings.window().close()
    let tabs =
      TabView(settings.contentView().viewWithIdentifier(KosmoSettingsTabsIdentifier))
    require tabs.selectPage(KosmoMoeThemesSettingsTabIdentifier)
    let targets =
      TableView(settings.contentView().viewWithIdentifier(KosmoThemeTargetIdentifier))
    let choices = TableView(
      settings.contentView().viewWithIdentifier(KosmoMoeThemesTableIdentifier)
    )
    require not targets.isNil and not choices.isNil
    targets.selectedIndexes = @[0, 1]
    check applied.len == 0
    choices.selectedIndex = choices.tableRowIndexForIdentifier("second")
    check applied == @[KosmoThemeTarget.Moe, KosmoThemeTarget.Terminal]
    let current = targets.columnWithIdentifier("theme")
    check targets.tableCellText(0, current) == "Second"
    check targets.tableCellText(1, current) == "First"
    check targets.tableCellText(2, current) == "First"
    check choices.selectedIndex == -1
    settings.updateMoeThemes(themes, "second", "second", "first", "first", "first")
    check applied.len == 2
    check targets.selectedIndexes == @[0, 1]
    check choices.tableRowIdentifier(choices.selectedIndex) == "second"

  test "Reset restores opening themes only for selected items":
    let themes = [
      KosmoMoeThemeSetting(identifier: "first", name: "First"),
      KosmoMoeThemeSetting(identifier: "second", name: "Second"),
      KosmoMoeThemeSetting(identifier: "third", name: "Third"),
    ]
    let settings = newKosmoSettingsWindow(
      moeThemes = themes,
      selectedMoeThemeIdentifier = "first",
      selectedTerminalThemeIdentifier = "second",
    )
    let window = settings.window()
    window.setContentView(settings.contentView())
    window.orderFront()
    defer:
      window.close()
    let tabs =
      TabView(settings.contentView().viewWithIdentifier(KosmoSettingsTabsIdentifier))
    require tabs.selectPage(KosmoMoeThemesSettingsTabIdentifier)
    let targets =
      TableView(settings.contentView().viewWithIdentifier(KosmoThemeTargetIdentifier))
    let choices = TableView(
      settings.contentView().viewWithIdentifier(KosmoMoeThemesTableIdentifier)
    )
    let reset =
      Button(settings.contentView().viewWithIdentifier(KosmoResetThemesIdentifier))
    let current = targets.columnWithIdentifier("theme")
    check not reset.enabled
    targets.selectedIndexes = @[0, 1]
    choices.selectedIndex = choices.tableRowIndexForIdentifier("third")
    choices.selectedIndex = choices.tableRowIndexForIdentifier("second")
    check reset.enabled
    targets.selectedIndexes = @[1]
    choices.selectedIndex = choices.tableRowIndexForIdentifier("third")
    targets.selectedIndexes = @[0]
    require reset.sendAction()
    check targets.tableCellText(0, current) == "First"
    check targets.tableCellText(1, current) == "Third"
    check not reset.enabled
    targets.selectedIndexes = @[1]
    choices.selectedIndex = choices.tableRowIndexForIdentifier("third")
    targets.selectedIndexes = @[]
    check not reset.enabled
    targets.selectedIndexes = @[1]
    settings.updateMoeThemes(themes, "first", "third")
    require reset.sendAction()
    check targets.tableCellText(1, current) == "Second"
    # A newly opened settings session captures a new baseline.
    window.close()
    settings.updateMoeThemes(themes, "third", "second")
    window.orderFront()
    targets.selectedIndexes = @[0]
    choices.selectedIndex = choices.tableRowIndexForIdentifier("first")
    require reset.sendAction()
    check targets.tableCellText(0, current) == "Third"

  test "theme tables and selection shortcuts remain usable when resized":
    let settings = newKosmoSettingsWindow()
    defer:
      settings.window().close()
    let window = settings.window()
    window.setContentView(settings.contentView())
    let tabs =
      TabView(settings.contentView().viewWithIdentifier(KosmoSettingsTabsIdentifier))
    require tabs.selectPage(KosmoMoeThemesSettingsTabIdentifier)
    for height in [KosmoSettingsMinimumHeight, 420.0'f32, 700.0'f32]:
      window.frame = rect(180, 160, KosmoSettingsMinimumWidth, height)
      settings.contentView().layoutSubtreeIfNeeded()
      for identifier in [KosmoThemeTargetIdentifier, KosmoMoeThemesTableIdentifier]:
        let table = TableView(settings.contentView().viewWithIdentifier(identifier))
        table.checkVisibleIn(settings.contentView())
        check table.frame().size.height >= 55
      let targets =
        settings.contentView().viewWithIdentifier(KosmoThemeTargetIdentifier)
      let themes =
        settings.contentView().viewWithIdentifier(KosmoMoeThemesTableIdentifier)
      check targets.frame().size.width >= 200
      check themes.frame().size.width >= 260
      check targets.frame().maxX <= themes.frame().origin.x
      check targets.frame().origin.y == themes.frame().origin.y
      settings.contentView().checkVisibleText(
        ["Select all", "Select rich text", "Reset"]
      )
    window.frame = rect(180, 160, 760, 420)
    discard window.buildRenders()
    let targets = settings.contentView().viewWithIdentifier(KosmoThemeTargetIdentifier)
    let themes = TableView(
      settings.contentView().viewWithIdentifier(KosmoMoeThemesTableIdentifier)
    )
    let totalWidth = targets.frame().size.width + themes.frame().size.width
    check abs(targets.frame().size.width / totalWidth - 0.32) < 0.01
    let preview = themes.columnWithIdentifier(KosmoMoeThemePreviewColumnIdentifier)
    check themes.tableHeaderColumnRect(preview).maxX <= themes.bounds().size.width

  test "Nimdex action buttons retain their control height when resized":
    let settings = newKosmoSettingsWindow()
    defer:
      settings.window().close()
    let window = settings.window()
    window.setContentView(settings.contentView())
    let tabs =
      TabView(settings.contentView().viewWithIdentifier(KosmoSettingsTabsIdentifier))
    require tabs.selectPage(KosmoNimdexSettingsTabIdentifier)
    let connect =
      settings.contentView().viewWithIdentifier("kosmo.settings.nimdex.connect")
    let disconnect =
      settings.contentView().viewWithIdentifier("kosmo.settings.nimdex.disconnect")
    let autoStart =
      settings.contentView().viewWithIdentifier("kosmo.settings.nimdex.autostart")
    require connect of Button
    require disconnect of Button
    require autoStart of Button
    for height in [KosmoSettingsMinimumHeight, 360.0'f32, 500.0'f32, 700.0'f32]:
      window.frame = rect(180, 160, KosmoSettingsMinimumWidth, height)
      settings.contentView().layoutSubtreeIfNeeded()
      settings.contentView().checkVisibleText(
        ["Nimdex server", "Start Nimdex automatically"]
      )
      autoStart.checkVisibleIn(settings.contentView())
      connect.checkVisibleIn(settings.contentView())
      disconnect.checkVisibleIn(settings.contentView())
      check connect.frame().size.height <= 36.0'f32
      check disconnect.frame().size.height <= 36.0'f32
      check connect.frame().size.height > 0
      check disconnect.frame().size.height > 0

  test "Install more opens a reusable sheet and returns to installed grammars":
    let app = newApplication("Grammar installer test")
    let settings = newKosmoSettingsWindow()
    let window = settings.window()
    window.setContentView(settings.contentView())
    app.addWindow(window)
    defer:
      settings.close()
      window.close()
    let tabs =
      TabView(settings.contentView().viewWithIdentifier(KosmoSettingsTabsIdentifier))
    require tabs.selectPage(KosmoTextMateGrammarsSettingsTabIdentifier)
    discard window.buildRenders()
    let installMore = Button(
      settings.contentView().viewWithIdentifier(KosmoInstallMoreGrammarsIdentifier)
    )
    require not installMore.isNil
    require installMore.sendAction()
    let sheet = window.attachedSheet()
    require not sheet.isNil
    check sheet.title == "Install grammars"
    require not app.modalSession().isNil
    check app.modalSession().parentWindow == window
    let content = sheet.contentView()
    let search =
      TextField(content.viewWithIdentifier(KosmoVscodeGrammarSearchFieldIdentifier))
    let install =
      Button(content.viewWithIdentifier(KosmoVscodeGrammarInstallButtonIdentifier))
    let done = Button(content.viewWithIdentifier(KosmoGrammarInstallerDoneIdentifier))
    require not search.isNil and not install.isNil and not done.isNil
    check sheet.fieldEditorClient() == search
    check not install.enabled
    check not settings.vscodeGrammarCatalog().isBusy
    search.text = "nim"
    for size in [initSize(560, 300), initSize(700, 420)]:
      sheet.frame = rect(initPoint(180, 160), size)
      discard sheet.buildRenders()
      content.checkVisibleText(
        ["Install grammars", "Search", "Install Selected", "Done"]
      )
      for identifier in [
        KosmoVscodeGrammarSearchFieldIdentifier,
        KosmoVscodeGrammarSearchTableIdentifier,
        KosmoVscodeGrammarInstallButtonIdentifier, KosmoGrammarInstallerDoneIdentifier,
      ]:
        content.viewWithIdentifier(identifier).checkVisibleIn(content)
    require done.sendAction()
    check window.attachedSheet().isNil
    check app.modalSession().isNil
    require installMore.sendAction()
    check window.attachedSheet() == sheet
    check search.text == "nim"
    sheet.close()
    check window.attachedSheet().isNil
    check app.modalSession().isNil
    require installMore.sendAction()
    window.close()
    check sheet.isClosed
    check app.modalSession().isNil

  test "TextMate grammar table follows its dragged column border":
    let settings = newKosmoSettingsWindow(
      textMateGrammars = [
        KosmoTextMateGrammar(
          name: "Nim",
          scopeName: "source.nim",
          origin: KosmoTextMateGrammarOrigin.BuiltIn,
        ),
        KosmoTextMateGrammar(
          name: "Markdown",
          scopeName: "text.html.markdown",
          origin: KosmoTextMateGrammarOrigin.BuiltIn,
        ),
      ]
    )
    defer:
      settings.window().close()

    let window = settings.window()
    window.setContentView(settings.contentView())
    let tabsView =
      settings.contentView().viewWithIdentifier(KosmoSettingsTabsIdentifier)
    require not tabsView.isNil
    require tabsView of TabView
    let tabs = TabView(tabsView)
    check tabs.selectPage(KosmoTextMateGrammarsSettingsTabIdentifier)
    discard window.buildRenders()

    let tableView =
      settings.contentView().viewWithIdentifier(KosmoTextMateGrammarsTableIdentifier)
    require not tableView.isNil
    require tableView of TableView
    let grammarTable = TableView(tableView)
    let scopeColumn =
      grammarTable.columnWithIdentifier(KosmoTextMateGrammarScopeColumnIdentifier)
    require not scopeColumn.isNil

    let
      initialHeader = grammarTable.tableHeaderColumnRect(scopeColumn)
      start = grammarTable.pointToWindow(
        initPoint(
          initialHeader.maxX - 1.0'f32,
          initialHeader.origin.y + initialHeader.size.height * 0.5'f32,
        )
      )
      stop = initPoint(start.x + 40.0'f32, start.y)

    check window.mouseDownAt(start)
    check window.mouseDraggedAt(stop)
    discard window.buildRenders()
    let finalHeader = grammarTable.tableHeaderColumnRect(scopeColumn)
    check abs(finalHeader.origin.x - initialHeader.origin.x) < 0.1'f32
    check abs(finalHeader.maxX - initialHeader.maxX - 40.0'f32) < 0.1'f32
    check window.mouseUpAt(stop)
