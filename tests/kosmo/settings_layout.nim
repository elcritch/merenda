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
      (KosmoNimdexSettingsTabIdentifier, @["Nimdex"]),
      (KosmoTerminalSettingsTabIdentifier, @["Terminal"]),
      (KosmoShortcutsSettingsTabIdentifier, @["Active Shortcuts"]),
      (KosmoMoeThemesSettingsTabIdentifier, @["Themes"]),
      (
        KosmoTextMateGrammarsSettingsTabIdentifier,
        @["Find a Language", "Available TextMate Grammars"],
      ),
    ]
    for (identifier, pageText) in expectedPageText:
      require tabs.selectPage(identifier)
      settings.contentView().layoutSubtreeIfNeeded()
      check tabs[tabs.selectedIndex].view().frame().size.width > 0.0'f32
      check tabs[tabs.selectedIndex].view().frame().size.height > 0.0'f32
      settings.contentView().checkVisibleText(pageText)

    check tabs.selectPage(KosmoTextMateGrammarsSettingsTabIdentifier)
    let
      searchField = settings.contentView().viewWithIdentifier(
          KosmoVscodeGrammarSearchFieldIdentifier
        )
      searchButton = settings.contentView().viewWithIdentifier(
          KosmoVscodeGrammarSearchButtonIdentifier
        )
      resultsTable = settings.contentView().viewWithIdentifier(
          KosmoVscodeGrammarSearchTableIdentifier
        )
    require searchField of TextField
    require searchButton of Button
    require resultsTable of TableView
    resultsTable.checkVisibleIn(settings.contentView())
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
      settings.contentView().checkVisibleText(["Select all", "Select rich text"])

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
    require connect of Button
    require disconnect of Button
    for height in [360.0'f32, 500.0'f32, 700.0'f32]:
      window.frame = rect(180, 160, 760, height)
      settings.contentView().layoutSubtreeIfNeeded()
      check connect.frame().size.height <= 36.0'f32
      check disconnect.frame().size.height <= 36.0'f32
      check connect.frame().size.height > 0
      check disconnect.frame().size.height > 0

  test "TextMate search results and available grammars share a draggable divider":
    let settings = newKosmoSettingsWindow()
    defer:
      settings.window().close()
    let window = settings.window()
    window.setContentView(settings.contentView())
    window.frame = rect(180, 160, 760, 650)
    let tabs =
      TabView(settings.contentView().viewWithIdentifier(KosmoSettingsTabsIdentifier))
    require tabs.selectPage(KosmoTextMateGrammarsSettingsTabIdentifier)
    discard window.buildRenders()
    let splitView =
      settings.contentView().viewWithIdentifier(KosmoGrammarListsSplitIdentifier)
    require splitView of SplitView
    let split = SplitView(splitView)
    let results =
      settings.contentView().viewWithIdentifier(KosmoVscodeGrammarSearchTableIdentifier)
    let available =
      settings.contentView().viewWithIdentifier(KosmoTextMateGrammarsTableIdentifier)
    require not results.isNil and not available.isNil
    let
      initialResultsHeight = results.frame().size.height
      initialAvailableHeight = available.frame().size.height
      divider = split.dividerRect(0)
      start = split.pointToWindow(
        initPoint(
          divider.origin.x + divider.size.width * 0.5,
          divider.origin.y + divider.size.height * 0.5,
        )
      )
      stop = initPoint(start.x, start.y + 40.0'f32)
    check window.mouseDownAt(start)
    check window.mouseDraggedAt(stop)
    discard window.buildRenders()
    check results.frame().size.height > initialResultsHeight + 30.0'f32
    check available.frame().size.height < initialAvailableHeight - 30.0'f32
    check window.mouseUpAt(stop)

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
