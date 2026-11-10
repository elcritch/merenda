## Kosmo-specific application settings.

import std/[algorithm, os, strutils]

import ../nimkit as nimkit
import ./themetargets
export themetargets

import ./moe
import ./shortcuts
import ./terminalinput
import ./vscodegrammars as vscodeGrammars

export vscodeGrammars

export shortcuts
export terminalinput.KosmoTerminalInputPolicy

const
  KosmoNimdexSettingsTabIdentifier* = "kosmo.settings.nimdex"
  KosmoSettingsTabsIdentifier* = "kosmo.settings.tabs"
  KosmoTerminalSettingsTabIdentifier* = "kosmo.settings.terminal"
  KosmoShortcutsSettingsTabIdentifier* = "kosmo.settings.shortcuts"
  KosmoMoeThemesSettingsTabIdentifier* = "kosmo.settings.moeThemes"
  KosmoTextMateGrammarsSettingsTabIdentifier* = "kosmo.settings.textMateGrammars"
  KosmoPreferEditorPanesIdentifier* = "kosmo.settings.terminal.preferEditorPanes"
  KosmoOptionAsMetaIdentifier* = "kosmo.settings.terminal.optionAsMeta"
  KosmoTerminalLinksIdentifier* = "kosmo.settings.terminal.links"
  KosmoTerminalInputPolicyIdentifier* = "kosmo.settings.terminal.inputPolicy"
  KosmoShortcutsTableIdentifier* = "kosmo.settings.shortcuts.table"
  KosmoShortcutProfileIdentifier* = "kosmo.settings.shortcuts.profile"
  KosmoEditorInputPolicyIdentifier* = "kosmo.settings.shortcuts.editorInput"
  KosmoForceInputModeIdentifier* = "kosmo.settings.shortcuts.forceInputMode"
  KosmoResetThemesIdentifier* = "kosmo.settings.themes.reset"
  KosmoSelectAllThemesIdentifier* = "kosmo.settings.themes.selectAll"
  KosmoSelectRichTextThemesIdentifier* = "kosmo.settings.themes.selectRichText"
  KosmoThemeItems = [
    KosmoThemeTarget.Moe, KosmoThemeTarget.Terminal, KosmoThemeTarget.Markdown,
    KosmoThemeTarget.GitDiff, KosmoThemeTarget.GitHub,
  ]
  KosmoThemeItemNames = ["Editor", "Terminal", "Markdown", "Git Diff", "GitHub"]
  KosmoThemeTargetIdentifier* = "kosmo.settings.themes.target"
  KosmoMoeThemesTableIdentifier* = "kosmo.settings.moeThemes.table"
  KosmoMoeThemeSelectorIdentifier* = KosmoMoeThemesTableIdentifier
  KosmoTextMateGrammarsTableIdentifier* = "kosmo.settings.textMateGrammars.table"
  KosmoShortcutActionColumnIdentifier* = "action"
  KosmoShortcutDescriptionColumnIdentifier* = "description"
  KosmoShortcutKeysColumnIdentifier* = "keys"
  KosmoMoeThemeNameColumnIdentifier* = "theme"
  KosmoMoeThemeAppearanceColumnIdentifier* = "appearance"
  KosmoMoeThemePreviewColumnIdentifier* = "preview"
  KosmoTextMateGrammarNameColumnIdentifier* = "grammar"
  KosmoTextMateGrammarScopeColumnIdentifier* = "scope"
  KosmoTextMateGrammarOriginColumnIdentifier* = "origin"
  KosmoVscodeGrammarSearchFieldIdentifier* = "kosmo.settings.textMateGrammars.search"
  KosmoVscodeGrammarSearchButtonIdentifier* =
    "kosmo.settings.textMateGrammars.searchButton"
  KosmoVscodeGrammarInstallButtonIdentifier* =
    "kosmo.settings.textMateGrammars.installButton"
  KosmoVscodeGrammarSearchTableIdentifier* =
    "kosmo.settings.textMateGrammars.searchResults"
  KosmoInstallMoreGrammarsIdentifier* = "kosmo.settings.textMateGrammars.installMore"
  KosmoGrammarInstallerDoneIdentifier* = "kosmo.settings.textMateGrammars.done"
  KosmoVscodeGrammarStatusIdentifier* = "kosmo.settings.textMateGrammars.status"
  KosmoVscodeGrammarLanguageColumnIdentifier* = "language"
  KosmoVscodeGrammarExtensionsColumnIdentifier* = "extensions"
  KosmoVscodeGrammarPublisherColumnIdentifier* = "publisher"
  KosmoVscodeGrammarScopeColumnIdentifier* = "scope"
  KosmoMoeThemePreviewText* = "let fn = \"text\" #"
  KosmoSettingsMinimumWidth* = 620.0'f32
  KosmoSettingsMinimumHeight* = 340.0'f32
  KosmoShortcutActionColumnWidth = 175.0'f32
  KosmoShortcutDescriptionColumnWidth = 310.0'f32
  KosmoShortcutKeysColumnWidth = 155.0'f32

type
  KosmoOptionAsMetaHandler* = proc(enabled: bool) {.closure.}
  KosmoTerminalLinksHandler* = proc(enabled: bool) {.closure.}
  KosmoTerminalInputPolicyHandler* = proc(policy: KosmoTerminalInputPolicy) {.closure.}
  KosmoMoeThemeHandler* =
    proc(identifier: string, target: KosmoThemeTarget): bool {.closure.}
  KosmoShortcutProfileHandler* = proc(profile: KosmoShortcutProfile) {.closure.}
  KosmoEditorInputPolicyHandler* = proc(policy: KosmoEditorInputPolicy) {.closure.}
  KosmoForceInputModeHandler* = proc(enabled: bool) {.closure.}
  KosmoVscodeGrammarInstalledHandler* = proc() {.closure.}

  KosmoShortcutSetting* = object
    action*: string
    description*: string
    keys*: string

  KosmoMoeThemeSetting* = object
    identifier*: string
    name*: string
    preview*: ContentThemePalette

  KosmoShortcutsTableSource = ref object of nimkit.Responder
    shortcuts: seq[KosmoShortcutSetting]

  KosmoMoeThemePreviewView = ref object of nimkit.View
    preview: ContentThemePalette

  KosmoMoeThemesTableSource = ref object of nimkit.Responder
    themes: seq[KosmoMoeThemeSetting]
    sortColumn: string
    sortDirection: nimkit.TableSortDirection
    selectedIdentifier: string
    identifiers, openingIdentifiers: array[KosmoThemeTarget, string]
    resetButton: nimkit.Button
    targetsTable, themesTable: nimkit.TableView
    selectionStatus: nimkit.Label
    synchronizing: bool
    handler: KosmoMoeThemeHandler

  KosmoThemeTargetsTableSource = ref object of nimkit.Responder
    themes: KosmoMoeThemesTableSource

  KosmoTextMateGrammarsTableSource = ref object of nimkit.Responder
    grammars: seq[KosmoTextMateGrammar]

  KosmoVscodeGrammarSearchTableSource = ref object of nimkit.Responder
    candidates: seq[VscodeGrammarCandidate]

  KosmoSettingsWindow* = ref object of nimkit.Responder
    xWindow: nimkit.Panel
    xContentView: nimkit.View
    xFirstResponder: nimkit.Responder
    xPreferEditorPanesButton: nimkit.Button
    xPreferEditorPanesHandler: proc(enabled: bool) {.closure.}
    xOptionAsMetaButton: nimkit.Button
    xOptionAsMetaHandler: KosmoOptionAsMetaHandler
    xTerminalLinksButton: nimkit.Button
    xTerminalLinksHandler: KosmoTerminalLinksHandler
    xTerminalInputPolicyChoice: nimkit.ComboBox
    xTerminalInputPolicyHandler: KosmoTerminalInputPolicyHandler
    xTabs: nimkit.TabView
    xNimdexMode: nimkit.ComboBox
    xNimdexLocal, xNimdexAddress: nimkit.TextField
    xNimdexDelegate: nimkit.BackRef[nimkit.Responder]
    xNimdexStatus: nimkit.Label
    xNimdexStatusError: bool
    xShortcutsTable: nimkit.TableView
    xShortcutsSource: KosmoShortcutsTableSource
    xShortcutProfileChoice: nimkit.ComboBox
    xEditorInputPolicyChoice: nimkit.ComboBox
    xForceInputModeButton: nimkit.Button
    xShortcutProfileHandler: KosmoShortcutProfileHandler
    xEditorInputPolicyHandler: KosmoEditorInputPolicyHandler
    xForceInputModeHandler: KosmoForceInputModeHandler
    xMoeThemesTable: nimkit.TableView
    xMoeThemesSource: KosmoMoeThemesTableSource
    xThemeTargetsSource: KosmoThemeTargetsTableSource
    xGrammarInstaller: nimkit.Panel
    xTextMateGrammarsTable: nimkit.TableView
    xTextMateGrammarsSource: KosmoTextMateGrammarsTableSource
    xVscodeGrammarCatalog: KosmoVscodeGrammarCatalog
    xVscodeGrammarInstalledHandler: KosmoVscodeGrammarInstalledHandler
    xVscodeGrammarSearchField: nimkit.TextField
    xVscodeGrammarSearchButton: nimkit.Button
    xVscodeGrammarInstallButton: nimkit.Button
    xVscodeGrammarSearchStatus: nimkit.Label
    xVscodeGrammarSearchTable: nimkit.TableView
    xVscodeGrammarSearchSource: KosmoVscodeGrammarSearchTableSource

protocol KosmoNimdexSettingsDelegate {.selectorScope: protocol.}:
  method nimdexSettingsAction*(command: string, connect: bool): string

  method nimdexSettingsStatus*(): string

  method nimdexSettingsAutoStart*(enabled: bool)

protocol KosmoShortcutsTableDataSource of nimkit.TableViewDataSource:
  method numberOfRows(
      source: KosmoShortcutsTableSource, tableView: nimkit.TableView
  ): int =
    discard tableView
    source.shortcuts.len

  method textForCell(
      source: KosmoShortcutsTableSource,
      tableView: nimkit.TableView,
      row: int,
      column: nimkit.TableColumn,
  ): string =
    discard tableView
    if row notin 0 ..< source.shortcuts.len:
      return
    let shortcut = source.shortcuts[row]
    case column.identifier()
    of KosmoShortcutActionColumnIdentifier: shortcut.action
    of KosmoShortcutDescriptionColumnIdentifier: shortcut.description
    of KosmoShortcutKeysColumnIdentifier: shortcut.keys
    else: ""

protocol KosmoShortcutsTableDelegate of nimkit.TableViewDelegate:
  method shouldSelectTableRow(
      source: KosmoShortcutsTableSource, tableView: nimkit.TableView, row: int
  ): bool =
    discard source
    discard tableView
    discard row
    false

  method shouldEditCell(
      source: KosmoShortcutsTableSource,
      tableView: nimkit.TableView,
      row: int,
      column: nimkit.TableColumn,
  ): bool =
    discard source
    discard tableView
    discard row
    discard column
    false

proc newKosmoShortcutsTableSource(
    shortcuts: openArray[KosmoShortcutSetting]
): KosmoShortcutsTableSource =
  result = KosmoShortcutsTableSource(shortcuts: @shortcuts)
  nimkit.initResponder(result)
  discard result.withProtocol(KosmoShortcutsTableDataSource)
  discard result.withProtocol(KosmoShortcutsTableDelegate)

protocol KosmoMoeThemePreviewDrawing of nimkit.ViewDrawingProtocol:
  method draw(view: KosmoMoeThemePreviewView, context: nimkit.DrawContext) =
    let
      bounds = view.bounds()
      baseStyle = context.appearance.resolveTextStyle(
        nimkit.controlStyle(nimkit.srMonoTextView),
        view.preview.foreground.toColor(),
        nimkit.insets(0.0),
      )
      textSize = KosmoMoeThemePreviewText.textNaturalSize(baseStyle)
      backgroundRect = nimkit.rect(
        4.0,
        max((bounds.size.height - textSize.height - 4.0'f32) * 0.5'f32, 0.0'f32),
        min(textSize.width + 12.0'f32, max(bounds.size.width - 8.0'f32, 0.0'f32)),
        min(textSize.height + 4.0'f32, bounds.size.height),
      )
      textY = max((bounds.size.height - textSize.height) * 0.5'f32, 0.0'f32)
    context.addRectangle(backgroundRect, view.preview.background.toColor())
    var textX = backgroundRect.origin.x + 6.0'f32
    template addSegment(text: string, colorValue: ContentThemeColor) =
      block:
        var style = baseStyle
        style.color = colorValue.toColor()
        let segmentSize = text.textNaturalSize(style)
        context.addText(
          nimkit.rect(textX, textY, segmentSize.width, textSize.height), text, style
        )
        textX += segmentSize.width

    addSegment("let", view.preview.keyword)
    addSegment(" ", view.preview.foreground)
    addSegment("fn", view.preview.functionName)
    addSegment(" = ", view.preview.foreground)
    addSegment("\"text\"", view.preview.stringLiteral)
    addSegment(" ", view.preview.foreground)
    addSegment("#", view.preview.comment)

proc newKosmoMoeThemePreviewView(
    preview: ContentThemePalette
): KosmoMoeThemePreviewView =
  result = KosmoMoeThemePreviewView(preview: preview)
  nimkit.initViewFields(result)
  result.accessibilityLabel = KosmoMoeThemePreviewText
  discard result.withProtocol(KosmoMoeThemePreviewDrawing)

func themeAppearance(theme: KosmoMoeThemeSetting): string =
  let color = theme.preview.background
  if 2126 * color.red.int + 7152 * color.green.int + 722 * color.blue.int >= 1_280_000:
    "Light"
  else:
    "Dark"

proc sortThemes(source: KosmoMoeThemesTableSource) =
  if source.sortDirection == nimkit.tsdNone:
    return
  let column = source.sortColumn
  let direction = source.sortDirection
  source.themes.sort(
    proc(a, b: KosmoMoeThemeSetting): int =
      if column == KosmoMoeThemeAppearanceColumnIdentifier:
        result = cmp(a.themeAppearance(), b.themeAppearance())
      if result == 0:
        result = cmpIgnoreCase(a.name, b.name)
      if direction == nimkit.tsdDescending:
        result = -result
  )

protocol KosmoMoeThemesTableDataSource of nimkit.TableViewDataSource:
  method numberOfRows(
      source: KosmoMoeThemesTableSource, tableView: nimkit.TableView
  ): int =
    discard tableView
    source.themes.len

  method textForCell(
      source: KosmoMoeThemesTableSource,
      tableView: nimkit.TableView,
      row: int,
      column: nimkit.TableColumn,
  ): string =
    discard tableView
    if row notin 0 ..< source.themes.len:
      return
    case column.identifier()
    of KosmoMoeThemeNameColumnIdentifier:
      source.themes[row].name
    of KosmoMoeThemeAppearanceColumnIdentifier:
      source.themes[row].themeAppearance()
    of KosmoMoeThemePreviewColumnIdentifier:
      KosmoMoeThemePreviewText
    else:
      ""

  method identifierForRow(
      source: KosmoMoeThemesTableSource, tableView: nimkit.TableView, row: int
  ): string =
    discard tableView
    if row in 0 ..< source.themes.len:
      source.themes[row].identifier
    else:
      ""

  method rowForIdentifier(
      source: KosmoMoeThemesTableSource, tableView: nimkit.TableView, identifier: string
  ): int =
    discard tableView
    for row, theme in source.themes:
      if theme.identifier == identifier:
        return row
    -1

protocol KosmoThemeTargetsTableDataSource of nimkit.TableViewDataSource:
  method numberOfRows(
      source: KosmoThemeTargetsTableSource, tableView: nimkit.TableView
  ): int =
    KosmoThemeItems.len

  method textForCell(
      source: KosmoThemeTargetsTableSource,
      tableView: nimkit.TableView,
      row: int,
      column: nimkit.TableColumn,
  ): string =
    if row notin 0 ..< KosmoThemeItems.len:
      return
    case column.identifier()
    of "item":
      KosmoThemeItemNames[row]
    of "theme":
      let identifier = source.themes.identifiers[KosmoThemeItems[row]]
      for theme in source.themes.themes:
        if theme.identifier == identifier:
          return theme.name
      if identifier.len == 0: "Default" else: identifier
    else:
      ""

  method identifierForRow(
      source: KosmoThemeTargetsTableSource, tableView: nimkit.TableView, row: int
  ): string =
    if row in 0 ..< KosmoThemeItems.len:
      $KosmoThemeItems[row]
    else:
      ""

  method rowForIdentifier(
      source: KosmoThemeTargetsTableSource,
      tableView: nimkit.TableView,
      identifier: string,
  ): int =
    for row, item in KosmoThemeItems:
      if $item == identifier:
        return row
    -1

proc newKosmoThemeTargetsTableSource(
    themes: KosmoMoeThemesTableSource
): KosmoThemeTargetsTableSource =
  result = KosmoThemeTargetsTableSource(themes: themes)
  nimkit.initResponder(result)
  discard result.withProtocol(KosmoThemeTargetsTableDataSource)

func targetIdentifier(source: KosmoMoeThemesTableSource): string =
  var first = true
  for row in source.targetsTable.selectedIndexes:
    let identifier = source.identifiers[KosmoThemeItems[row]]
    if first:
      result = identifier
      first = false
    elif result != identifier:
      return ""

proc themeTargetsDidChange(
    source: KosmoMoeThemesTableSource, sender: nimkit.DynamicAgent
) {.slot.} =
  discard sender
  if source.synchronizing:
    return
  source.synchronizing = true
  defer:
    source.synchronizing = false
  source.selectedIdentifier = source.targetIdentifier()
  source.themesTable.selectedIndex =
    source.themesTable.tableRowIndexForIdentifier(source.selectedIdentifier)
  source.resetButton.enabled = false
  for row in source.targetsTable.selectedIndexes:
    let item = KosmoThemeItems[row]
    if source.identifiers[item] != source.openingIdentifiers[item]:
      source.resetButton.enabled = true
  let count = source.targetsTable.selectedIndexes.len
  source.selectionStatus.text =
    if count == 0:
      "Select items to change their theme."
    elif source.selectedIdentifier.len == 0:
      $count & " selected · Mixed themes"
    else:
      $count & " selected"

proc resetSelectedThemes(source: KosmoMoeThemesTableSource) =
  source.synchronizing = true
  for row in source.targetsTable.selectedIndexes:
    let item = KosmoThemeItems[row]
    let identifier = source.openingIdentifiers[item]
    if source.identifiers[item] != identifier:
      if source.handler.isNil or source.handler(identifier, item):
        source.identifiers[item] = identifier
  source.targetsTable.reloadData()
  source.synchronizing = false
  source.themeTargetsDidChange(source.targetsTable)

protocol KosmoMoeThemesTableDelegate of nimkit.TableViewDelegate:
  method sortDescriptorsDidChange(
      source: KosmoMoeThemesTableSource,
      tableView: nimkit.TableView,
      column: nimkit.TableColumn,
      direction: nimkit.TableSortDirection,
  ) =
    source.sortColumn = column.identifier()
    source.sortDirection = direction
    source.sortThemes()
    source.synchronizing = true
    tableView.reloadData()
    source.synchronizing = false
    source.themeTargetsDidChange(tableView)

  method viewForCell(
      source: KosmoMoeThemesTableSource,
      tableView: nimkit.TableView,
      row: int,
      column: nimkit.TableColumn,
  ): nimkit.View =
    discard tableView
    if row in 0 ..< source.themes.len and
        column.identifier() == KosmoMoeThemePreviewColumnIdentifier:
      return source.themes[row].preview.newKosmoMoeThemePreviewView()

  method didSelectTableRow(
      source: KosmoMoeThemesTableSource, tableView: nimkit.TableView, row: int
  ) =
    if source.synchronizing:
      return
    if row notin 0 ..< source.themes.len:
      return
    let identifier = source.themes[row].identifier
    source.synchronizing = true
    for targetRow in source.targetsTable.selectedIndexes:
      let item = KosmoThemeItems[targetRow]
      if source.identifiers[item] != identifier:
        if source.handler.isNil or source.handler(identifier, item):
          source.identifiers[item] = identifier
    source.targetsTable.reloadData()
    source.synchronizing = false
    source.themeTargetsDidChange(tableView)

  method shouldEditCell(
      source: KosmoMoeThemesTableSource,
      tableView: nimkit.TableView,
      row: int,
      column: nimkit.TableColumn,
  ): bool =
    discard source
    discard tableView
    discard row
    discard column
    false

proc newKosmoMoeThemesTableSource(
    handler: KosmoMoeThemeHandler
): KosmoMoeThemesTableSource =
  result = KosmoMoeThemesTableSource(handler: handler)
  nimkit.initResponder(result)
  discard result.withProtocol(KosmoMoeThemesTableDataSource)
  discard result.withProtocol(KosmoMoeThemesTableDelegate)

protocol KosmoTextMateGrammarsTableDataSource of nimkit.TableViewDataSource:
  method numberOfRows(
      source: KosmoTextMateGrammarsTableSource, tableView: nimkit.TableView
  ): int =
    discard tableView
    source.grammars.len

  method textForCell(
      source: KosmoTextMateGrammarsTableSource,
      tableView: nimkit.TableView,
      row: int,
      column: nimkit.TableColumn,
  ): string =
    discard tableView
    if row notin 0 ..< source.grammars.len:
      return
    let grammar = source.grammars[row]
    case column.identifier()
    of KosmoTextMateGrammarNameColumnIdentifier:
      grammar.name
    of KosmoTextMateGrammarScopeColumnIdentifier:
      grammar.scopeName
    of KosmoTextMateGrammarOriginColumnIdentifier:
      grammar.origin.title()
    else:
      ""

protocol KosmoTextMateGrammarsTableDelegate of nimkit.TableViewDelegate:
  method shouldSelectTableRow(
      source: KosmoTextMateGrammarsTableSource, tableView: nimkit.TableView, row: int
  ): bool =
    discard source
    discard tableView
    discard row
    false

  method shouldEditCell(
      source: KosmoTextMateGrammarsTableSource,
      tableView: nimkit.TableView,
      row: int,
      column: nimkit.TableColumn,
  ): bool =
    discard source
    discard tableView
    discard row
    discard column
    false

proc newKosmoTextMateGrammarsTableSource(
    grammars: openArray[KosmoTextMateGrammar]
): KosmoTextMateGrammarsTableSource =
  result = KosmoTextMateGrammarsTableSource(grammars: @grammars)
  nimkit.initResponder(result)
  discard result.withProtocol(KosmoTextMateGrammarsTableDataSource)
  discard result.withProtocol(KosmoTextMateGrammarsTableDelegate)

protocol KosmoVscodeGrammarSearchTableDataSource of nimkit.TableViewDataSource:
  method numberOfRows(
      source: KosmoVscodeGrammarSearchTableSource, tableView: nimkit.TableView
  ): int =
    discard tableView
    source.candidates.len

  method textForCell(
      source: KosmoVscodeGrammarSearchTableSource,
      tableView: nimkit.TableView,
      row: int,
      column: nimkit.TableColumn,
  ): string =
    discard tableView
    if row notin 0 ..< source.candidates.len:
      return
    let candidate = source.candidates[row]
    case column.identifier()
    of KosmoVscodeGrammarLanguageColumnIdentifier:
      candidate.name
    of KosmoVscodeGrammarExtensionsColumnIdentifier:
      candidate.extensions.join(" ")
    of KosmoVscodeGrammarPublisherColumnIdentifier:
      candidate.extensionFolder
    of KosmoVscodeGrammarScopeColumnIdentifier:
      candidate.scopeName
    else:
      ""

  method identifierForRow(
      source: KosmoVscodeGrammarSearchTableSource, tableView: nimkit.TableView, row: int
  ): string =
    discard tableView
    if row in 0 ..< source.candidates.len:
      result = source.candidates[row].id

protocol KosmoVscodeGrammarSearchTableDelegate of nimkit.TableViewDelegate:
  method shouldSelectTableRow(
      source: KosmoVscodeGrammarSearchTableSource, tableView: nimkit.TableView, row: int
  ): bool =
    discard source
    discard tableView
    discard row
    true

  method shouldEditCell(
      source: KosmoVscodeGrammarSearchTableSource,
      tableView: nimkit.TableView,
      row: int,
      column: nimkit.TableColumn,
  ): bool =
    discard source
    discard tableView
    discard row
    discard column
    false

proc newKosmoVscodeGrammarSearchTableSource(): KosmoVscodeGrammarSearchTableSource =
  result = KosmoVscodeGrammarSearchTableSource()
  nimkit.initResponder(result)
  discard result.withProtocol(KosmoVscodeGrammarSearchTableDataSource)
  discard result.withProtocol(KosmoVscodeGrammarSearchTableDelegate)

proc updateVscodeGrammarSearchControls(settings: KosmoSettingsWindow) =
  if settings.isNil or settings.xVscodeGrammarCatalog.isNil:
    return
  let selectedRow =
    if settings.xVscodeGrammarSearchTable.isNil:
      -1
    else:
      settings.xVscodeGrammarSearchTable.selectedIndex
  settings.xVscodeGrammarInstallButton.enabled = false
  if selectedRow in 0 ..< settings.xVscodeGrammarSearchSource.candidates.len and
      not settings.xVscodeGrammarCatalog.isBusy:
    let candidate = settings.xVscodeGrammarSearchSource.candidates[selectedRow]
    settings.xVscodeGrammarInstallButton.enabled =
      not isVscodeGrammarInstalled(candidate.id)
  settings.xVscodeGrammarSearchStatus.text = settings.xVscodeGrammarCatalog.status()

proc vscodeGrammarCatalogDidUpdate(settings: KosmoSettingsWindow) {.slot.} =
  if settings.isNil or settings.xVscodeGrammarCatalog.isNil:
    return
  settings.xVscodeGrammarSearchSource.candidates =
    settings.xVscodeGrammarCatalog.candidates()
  settings.xVscodeGrammarSearchTable.reloadData()
  settings.xVscodeGrammarSearchTable.selectedIndex =
    if settings.xVscodeGrammarSearchSource.candidates.len > 0: 0 else: -1
  settings.updateVscodeGrammarSearchControls()

proc vscodeGrammarDidInstall(
    settings: KosmoSettingsWindow, directory: string
) {.slot.} =
  discard directory
  if settings.isNil:
    return
  if not settings.xVscodeGrammarInstalledHandler.isNil:
    settings.xVscodeGrammarInstalledHandler()
  settings.updateVscodeGrammarSearchControls()

proc vscodeGrammarSelectionDidChange(
    settings: KosmoSettingsWindow, sender: nimkit.DynamicAgent
) {.slot.} =
  discard sender
  settings.updateVscodeGrammarSearchControls()

proc searchVscodeGrammars(
    settings: KosmoSettingsWindow, sender: nimkit.DynamicAgent
) {.slot.} =
  discard sender
  if not settings.isNil and not settings.xVscodeGrammarCatalog.isNil:
    settings.xVscodeGrammarCatalog.search(settings.xVscodeGrammarSearchField.text)

proc installSelectedVscodeGrammar(
    settings: KosmoSettingsWindow, sender: nimkit.DynamicAgent
) {.slot.} =
  discard sender
  if settings.isNil or settings.xVscodeGrammarCatalog.isNil or
      settings.xVscodeGrammarSearchTable.isNil:
    return
  let row = settings.xVscodeGrammarSearchTable.selectedIndex
  if row in 0 ..< settings.xVscodeGrammarSearchSource.candidates.len:
    settings.xVscodeGrammarCatalog.install(
      settings.xVscodeGrammarSearchSource.candidates[row].id
    )

proc showGrammarInstaller(settings: KosmoSettingsWindow) =
  let responder = settings.xWindow.nextResponder()
  if not (responder of nimkit.Application):
    return
  let app = nimkit.Application(responder)
  if settings.xWindow.attachedSheet() == settings.xGrammarInstaller:
    app.activateWindow(settings.xGrammarInstaller)
    return
  let parentFrame = settings.xWindow.frame()
  let size = settings.xGrammarInstaller.frame().size
  settings.xGrammarInstaller.frame = nimkit.rect(
    parentFrame.origin.x + (parentFrame.size.width - size.width) / 2,
    parentFrame.origin.y + (parentFrame.size.height - size.height) / 2,
    size.width,
    size.height,
  )
  discard app.beginModalSheet(settings.xWindow, settings.xGrammarInstaller)
  discard
    settings.xGrammarInstaller.makeFirstResponder(settings.xVscodeGrammarSearchField)

proc vscodeGrammarCatalog*(settings: KosmoSettingsWindow): KosmoVscodeGrammarCatalog =
  if not settings.isNil:
    result = settings.xVscodeGrammarCatalog

proc `vscodeGrammarInstalledHandler=`*(
    settings: KosmoSettingsWindow, handler: KosmoVscodeGrammarInstalledHandler
) =
  if not settings.isNil:
    settings.xVscodeGrammarInstalledHandler = handler

proc close*(settings: KosmoSettingsWindow) =
  ## Release the network worker owned by the settings controller.
  if not settings.isNil:
    settings.xGrammarInstaller.close()
    settings.xVscodeGrammarCatalog.close()

proc newSettingsPage(): tuple[view: nimkit.View, stack: nimkit.StackView] =
  result.stack = nimkit.newStackView(nimkit.laVertical)
  result.stack.spacing = 10.0
  result.stack.alignment = nimkit.svaFill
  result.stack.edgeInsets = nimkit.insets(14.0, 16.0)
  result.view = result.stack

proc pageHeightRequirement(page: nimkit.View): float32 =
  ## Return the height a settings page needs so a vertical stack cannot
  ## squeeze its arranged text below the natural line height of the resolved
  ## UI font. A page that can shed a vertical shortfall into a flexible or
  ## low-compression arranged child never squeezes its remaining children, so
  ## it imposes no requirement and only fills the window through the shared
  ## minimum; every other page needs its full fitting height.
  if page of nimkit.StackView:
    let stack = nimkit.StackView(page)
    for child in stack.arrangedSubviews():
      if stack.arrangedSubviewSizingPolicy(child) == nimkit.svspFillAvailableSpace or
          child.compressionPriority(nimkit.laVertical) < nimkit.LayoutPriorityHigh:
        return
  page.fittingSize().height

proc settingsContentMinimumHeight(content: nimkit.View, tabs: nimkit.TabView): float32 =
  ## Derive the settings window's minimum content height from the built
  ## pages, so no page squeezes its text at the minimum size whatever font
  ## the UI resolves. The measured content height carries the window chrome
  ## (title, tab bar, insets) around the tallest page; swapping that page's
  ## natural height for the tallest page's requirement keeps the chrome while
  ## counting only the heights pages actually need.
  var tallestPage = 0.0'f32
  var tallestRequirement = 0.0'f32
  for item in tabs.items():
    let page = item.view()
    tallestPage = max(tallestPage, page.fittingSize().height)
    tallestRequirement = max(tallestRequirement, pageHeightRequirement(page))
  content.fittingSize().height - tallestPage + tallestRequirement

proc preferEditorPanes*(settings: KosmoSettingsWindow): bool =
  ## Return the editor pane preference shown in settings.
  not settings.isNil and settings.xPreferEditorPanesButton.state == nimkit.bsOn

proc `preferEditorPanes=`*(settings: KosmoSettingsWindow, enabled: bool) =
  ## Update the editor pane preference shown in settings.
  if not settings.isNil:
    settings.xPreferEditorPanesButton.state = if enabled: nimkit.bsOn else: nimkit.bsOff

proc optionAsMeta*(settings: KosmoSettingsWindow): bool =
  ## Return the current terminal Option/Alt-as-Meta selection.
  not settings.isNil and settings.xOptionAsMetaButton.state == nimkit.bsOn

proc `optionAsMeta=`*(settings: KosmoSettingsWindow, enabled: bool) =
  ## Update the terminal Option/Alt-as-Meta selection without invoking its action.
  if not settings.isNil:
    settings.xOptionAsMetaButton.state = if enabled: nimkit.bsOn else: nimkit.bsOff

proc terminalLinksEnabled*(settings: KosmoSettingsWindow): bool =
  ## Return whether modifier-hover and modifier-click terminal links are enabled.
  not settings.isNil and settings.xTerminalLinksButton.state == nimkit.bsOn

proc `terminalLinksEnabled=`*(settings: KosmoSettingsWindow, enabled: bool) =
  ## Synchronize terminal link activation without invoking its action.
  if not settings.isNil:
    settings.xTerminalLinksButton.state = if enabled: nimkit.bsOn else: nimkit.bsOff

proc terminalInputPolicy*(settings: KosmoSettingsWindow): KosmoTerminalInputPolicy =
  ## Return the selected terminal Control shortcut policy.
  if not settings.isNil and settings.xTerminalInputPolicyChoice.selectedIndex == 1:
    KosmoTerminalInputPolicy.Raw
  else:
    KosmoTerminalInputPolicy.Hybrid

proc `terminalInputPolicy=`*(
    settings: KosmoSettingsWindow, policy: KosmoTerminalInputPolicy
) =
  ## Synchronize the terminal input selector without invoking its action.
  if not settings.isNil:
    settings.xTerminalInputPolicyChoice.selectedIndex =
      if policy == KosmoTerminalInputPolicy.Raw: 1 else: 0

proc `shortcuts=`*(
    settings: KosmoSettingsWindow, shortcuts: openArray[KosmoShortcutSetting]
) =
  ## Replace the read-only shortcut list with Kosmo's currently active bindings.
  if settings.isNil or settings.xShortcutsSource.isNil:
    return
  settings.xShortcutsSource.shortcuts = @shortcuts
  settings.xShortcutsTable.reloadData()

proc shortcutProfile*(settings: KosmoSettingsWindow): KosmoShortcutProfile =
  ## Return the shortcut profile selected in Settings.
  if not settings.isNil and not settings.xShortcutProfileChoice.isNil and
      settings.xShortcutProfileChoice.selectedIndex == 1:
    KosmoShortcutProfile.MacOS
  else:
    KosmoShortcutProfile.Platform

proc `shortcutProfile=`*(settings: KosmoSettingsWindow, profile: KosmoShortcutProfile) =
  ## Synchronize the shortcut profile control without invoking its action.
  if not settings.isNil and not settings.xShortcutProfileChoice.isNil:
    settings.xShortcutProfileChoice.selectedIndex =
      case profile
      of KosmoShortcutProfile.Platform: 0
      of KosmoShortcutProfile.MacOS: 1

proc editorInputPolicy*(settings: KosmoSettingsWindow): KosmoEditorInputPolicy =
  ## Return the Moe input-routing policy selected in Settings.
  if settings.isNil or settings.xEditorInputPolicyChoice.isNil:
    return defaultKosmoEditorInputPolicy()
  case settings.xEditorInputPolicyChoice.selectedIndex
  of 0: KosmoEditorInputPolicy.Vim
  of 1: KosmoEditorInputPolicy.Native
  else: KosmoEditorInputPolicy.Hybrid

proc `editorInputPolicy=`*(
    settings: KosmoSettingsWindow, policy: KosmoEditorInputPolicy
) =
  ## Synchronize the editor input control without invoking its action.
  if not settings.isNil and not settings.xEditorInputPolicyChoice.isNil:
    settings.xEditorInputPolicyChoice.selectedIndex =
      case policy
      of KosmoEditorInputPolicy.Vim: 0
      of KosmoEditorInputPolicy.Native: 1
      of KosmoEditorInputPolicy.Hybrid: 2

proc forceInputMode*(settings: KosmoSettingsWindow): bool =
  ## Return whether editable Moe buffers are kept in Input mode.
  not settings.isNil and not settings.xForceInputModeButton.isNil and
    settings.xForceInputModeButton.state == nimkit.bsOn

proc `forceInputMode=`*(settings: KosmoSettingsWindow, enabled: bool) =
  ## Synchronize the forced Input mode control without invoking its action.
  if not settings.isNil and not settings.xForceInputModeButton.isNil:
    settings.xForceInputModeButton.state = if enabled: nimkit.bsOn else: nimkit.bsOff

proc selectedMoeThemeIdentifier*(settings: KosmoSettingsWindow): string =
  ## Return the theme selected in the Moe Themes settings tab.
  if not settings.isNil and not settings.xMoeThemesSource.isNil:
    result = settings.xMoeThemesSource.selectedIdentifier

proc updateMoeThemes*(
    settings: KosmoSettingsWindow,
    themes: openArray[KosmoMoeThemeSetting],
    selectedIdentifier: string,
    terminalIdentifier = "",
    markdownIdentifier = "",
    gitDiffIdentifier = "",
    gitHubIdentifier = "",
) =
  ## Replace the available Moe themes and synchronize the current selection.
  if settings.isNil or settings.xMoeThemesSource.isNil or settings.xMoeThemesTable.isNil:
    return
  settings.xMoeThemesSource.synchronizing = true
  settings.xMoeThemesSource.themes = @themes
  let source = settings.xMoeThemesSource
  source.sortThemes()
  source.identifiers[KosmoThemeTarget.Moe] = selectedIdentifier
  source.identifiers[KosmoThemeTarget.Terminal] =
    if terminalIdentifier.len > 0:
      terminalIdentifier
    else:
      KosmoMoeDefaultThemeIdentifier
  source.identifiers[KosmoThemeTarget.Markdown] = markdownIdentifier
  source.identifiers[KosmoThemeTarget.GitDiff] = gitDiffIdentifier
  source.identifiers[KosmoThemeTarget.GitHub] = gitHubIdentifier
  if not settings.xWindow.isVisible():
    source.openingIdentifiers = source.identifiers
  settings.xMoeThemesTable.reloadData()
  source.targetsTable.reloadData()
  source.synchronizing = false
  source.themeTargetsDidChange(settings.xMoeThemesTable)

proc `textMateGrammars=`*(
    settings: KosmoSettingsWindow, grammars: openArray[KosmoTextMateGrammar]
) =
  ## Replace the read-only list of TextMate grammars available to Kosmo.
  if settings.isNil or settings.xTextMateGrammarsSource.isNil or
      settings.xTextMateGrammarsTable.isNil:
    return
  settings.xTextMateGrammarsSource.grammars = @grammars
  settings.xTextMateGrammarsTable.reloadData()

proc newKosmoSettingsWindow*(
    nimdexCommand = "",
    nimdexAutoStart = false,
    nimdexDelegate: nimkit.Responder = nil,
    preferEditorPanes = true,
    preferEditorPanesHandler: proc(enabled: bool) {.closure.} = nil,
    optionAsMeta = nimkit.DefaultTerminalOptionAsMeta,
    optionAsMetaHandler: KosmoOptionAsMetaHandler = nil,
    terminalLinksEnabled = true,
    terminalLinksHandler: KosmoTerminalLinksHandler = nil,
    terminalInputPolicy = KosmoTerminalInputPolicy.Hybrid,
    terminalInputPolicyHandler: KosmoTerminalInputPolicyHandler = nil,
    shortcutProfile = defaultKosmoShortcutProfile(),
    shortcutProfileHandler: KosmoShortcutProfileHandler = nil,
    editorInputPolicy = defaultKosmoEditorInputPolicy(),
    editorInputPolicyHandler: KosmoEditorInputPolicyHandler = nil,
    forceInputMode = false,
    forceInputModeHandler: KosmoForceInputModeHandler = nil,
    shortcuts: openArray[KosmoShortcutSetting] = [],
    moeThemes: openArray[KosmoMoeThemeSetting] = [],
    selectedMoeThemeIdentifier = "",
    selectedTerminalThemeIdentifier = "",
    selectedMarkdownThemeIdentifier = "",
    selectedGitDiffThemeIdentifier = "",
    selectedGitHubThemeIdentifier = "",
    moeThemeHandler: KosmoMoeThemeHandler = nil,
    textMateGrammars: openArray[KosmoTextMateGrammar] = [],
): KosmoSettingsWindow =
  ## Create Kosmo's settings panel, which intentionally contains no Merenda settings.
  let
    shortcutsSource = newKosmoShortcutsTableSource(shortcuts)
    moeThemesSource = newKosmoMoeThemesTableSource(moeThemeHandler)
    textMateGrammarsSource = newKosmoTextMateGrammarsTableSource(textMateGrammars)
    vscodeGrammarSearchSource = newKosmoVscodeGrammarSearchTableSource()
  result = KosmoSettingsWindow(
    xWindow: nimkit.newPanel("Kosmo Settings", nimkit.rect(180, 160, 760, 420)),
    xGrammarInstaller:
      nimkit.newPanel("Install grammars", nimkit.rect(180, 160, 700, 420)),
    xContentView: nimkit.newView(),
    xPreferEditorPanesHandler: preferEditorPanesHandler,
    xOptionAsMetaHandler: optionAsMetaHandler,
    xTerminalLinksHandler: terminalLinksHandler,
    xTerminalInputPolicyHandler: terminalInputPolicyHandler,
    xShortcutProfileHandler: shortcutProfileHandler,
    xEditorInputPolicyHandler: editorInputPolicyHandler,
    xForceInputModeHandler: forceInputModeHandler,
    xShortcutsSource: shortcutsSource,
    xMoeThemesSource: moeThemesSource,
    xThemeTargetsSource: newKosmoThemeTargetsTableSource(moeThemesSource),
    xTextMateGrammarsSource: textMateGrammarsSource,
    xVscodeGrammarCatalog: newKosmoVscodeGrammarCatalog(),
    xVscodeGrammarSearchSource: vscodeGrammarSearchSource,
  )
  nimkit.initResponder(result)
  result.xNimdexDelegate{} = nimdexDelegate
  let
    settings = result
    layout = nimkit.newStackView(nimkit.laVertical)
    tabs = nimkit.newTabView()
    terminalPage = newSettingsPage()
    nimdexPage = newSettingsPage()
    nimdexForm = nimkit.newFormView()
    nimdexAutoStartButton = nimkit.newCheckBox("Start Nimdex automatically")
    nimdexMode = nimkit.newComboBox(["Launch locally", "Connect to daemon"])
    nimdexLocal = nimkit.newTextField()
    nimdexAddress = nimkit.newTextField()
    nimdexStatusLabel = nimkit.newLabel("Disconnected")
    nimdexConnect = nimkit.newButton("Start / Connect")
    nimdexDisconnect = nimkit.newButton("Stop / Disconnect")
    nimdexButtons = nimkit.newStackView(nimkit.laHorizontal)
    shortcutsPage = newSettingsPage()
    moeThemesPage = newSettingsPage()
    textMateGrammarsPage = newSettingsPage()
    grammarInstallerPage = newSettingsPage()
    grammarInstallerButtons = nimkit.newStackView(nimkit.laHorizontal)
    installMoreGrammars = nimkit.newButton("Install more…")
    grammarInstallerDone = nimkit.newButton("Done")
    vscodeGrammarSearchControls = nimkit.newStackView(nimkit.laHorizontal)
    preferEditorPanesButton =
      nimkit.newCheckBox("Prefer panes not displaying terminals for editor tabs")
    optionButton = nimkit.newCheckBox("Use Option/Alt as Meta")
    terminalInputPolicyChoice = nimkit.newComboBox(["Hybrid", "Raw shortcuts"])
    terminalForm = nimkit.newFormView()
    terminalLinksButton = nimkit.newCheckBox(
      when defined(macosx) or defined(macos):
        "Open terminal links with Command-click"
      else:
        "Open terminal links with Control-click"
    )
    shortcutProfileChoice = nimkit.newComboBox(["Platform", "macOS-style"])
    editorInputPolicyChoice = nimkit.newComboBox(["Vim", "Native", "Hybrid"])
    forceInputModeButton = nimkit.newCheckBox("Force input mode")
    shortcutsForm = nimkit.newFormView()
    shortcutsTable = nimkit.newTableView()
    moeThemesTable = nimkit.newTableView()
    themeTargets = nimkit.newTableView()
    themeLists = nimkit.newSplitView(nimkit.laHorizontal)
    themeSelectionStatus = nimkit.newLabel("")
    selectAllThemes = nimkit.newButton("Select all")
    selectRichTextThemes = nimkit.newButton("Select rich text")
    resetThemes = nimkit.newButton("Reset")
    themeButtons = nimkit.newStackView(nimkit.laHorizontal)
    textMateGrammarsTable = nimkit.newTableView()
    vscodeGrammarSearchField = nimkit.newTextField()
    vscodeGrammarSearchButton = nimkit.newButton("Search")
    vscodeGrammarInstallButton = nimkit.newButton("Install Selected")
    vscodeGrammarSearchStatus =
      nimkit.newLabel("Search Open VSX for a language or extension.")
    vscodeGrammarSearchTable = nimkit.newTableView()
    optionChanged = nimkit.actionSelector("kosmo.optionAsMetaChanged")
    terminalLinksChanged = nimkit.actionSelector("kosmo.terminalLinksChanged")
    terminalInputPolicyChanged =
      nimkit.actionSelector("kosmo.terminalInputPolicyChanged")
    shortcutProfileChanged = nimkit.actionSelector("kosmo.shortcutProfileChanged")
    editorInputPolicyChanged = nimkit.actionSelector("kosmo.editorInputPolicyChanged")
    vscodeGrammarSearchAction = nimkit.actionSelector("kosmo.searchVscodeGrammars")
    vscodeGrammarInstallAction = nimkit.actionSelector("kosmo.installVscodeGrammar")
  result.xPreferEditorPanesButton = preferEditorPanesButton
  result.xOptionAsMetaButton = optionButton
  result.xTerminalLinksButton = terminalLinksButton
  result.xTerminalInputPolicyChoice = terminalInputPolicyChoice
  result.xFirstResponder = optionButton
  result.xTabs = tabs
  result.xShortcutsTable = shortcutsTable
  result.xShortcutProfileChoice = shortcutProfileChoice
  result.xEditorInputPolicyChoice = editorInputPolicyChoice
  result.xForceInputModeButton = forceInputModeButton
  result.xMoeThemesTable = moeThemesTable
  result.xTextMateGrammarsTable = textMateGrammarsTable
  result.xVscodeGrammarSearchField = vscodeGrammarSearchField
  result.xVscodeGrammarSearchButton = vscodeGrammarSearchButton
  result.xVscodeGrammarInstallButton = vscodeGrammarInstallButton
  result.xVscodeGrammarSearchStatus = vscodeGrammarSearchStatus
  result.xVscodeGrammarSearchTable = vscodeGrammarSearchTable

  vscodeGrammarSearchField.identifier = KosmoVscodeGrammarSearchFieldIdentifier
  vscodeGrammarSearchField.accessibilityLabel = "Search Open VSX language grammars"
  vscodeGrammarSearchButton.identifier = KosmoVscodeGrammarSearchButtonIdentifier
  vscodeGrammarSearchButton.accessibilityLabel = "Search Open VSX"
  vscodeGrammarSearchButton.target = nimkit.newActionTarget(
    vscodeGrammarSearchAction, settings
  ) do(settings: KosmoSettingsWindow, sender: DynamicAgent):
    settings.searchVscodeGrammars(sender)
  vscodeGrammarSearchButton.action = vscodeGrammarSearchAction
  vscodeGrammarSearchField.target = vscodeGrammarSearchButton.target
  vscodeGrammarSearchField.action = vscodeGrammarSearchAction
  vscodeGrammarInstallButton.identifier = KosmoVscodeGrammarInstallButtonIdentifier
  vscodeGrammarInstallButton.accessibilityLabel = "Install selected Open VSX grammar"
  vscodeGrammarInstallButton.enabled = false
  vscodeGrammarInstallButton.target = nimkit.newActionTarget(
    vscodeGrammarInstallAction, settings
  ) do(settings: KosmoSettingsWindow, sender: DynamicAgent):
    settings.installSelectedVscodeGrammar(sender)
  vscodeGrammarInstallButton.action = vscodeGrammarInstallAction

  vscodeGrammarSearchStatus.identifier = KosmoVscodeGrammarStatusIdentifier
  vscodeGrammarSearchTable.identifier = KosmoVscodeGrammarSearchTableIdentifier
  vscodeGrammarSearchTable.accessibilityLabel = "Open VSX grammar search results"
  vscodeGrammarSearchTable.columnSizing = nimkit.tvcsFill
  vscodeGrammarSearchTable.selectionMode = nimkit.tsmSingle
  vscodeGrammarSearchTable.visibleRows = 3
  vscodeGrammarSearchTable.usesAlternatingRowBackgrounds = true
  vscodeGrammarSearchTable.showsRowSeparators = true
  vscodeGrammarSearchTable.addColumn(
    nimkit.newTableColumn(
      KosmoVscodeGrammarLanguageColumnIdentifier,
      "Language",
      width = 170.0,
      minWidth = 125.0,
      sizingPolicy = nimkit.tcspFlexible,
    )
  )
  vscodeGrammarSearchTable.addColumn(
    nimkit.newTableColumn(
      KosmoVscodeGrammarExtensionsColumnIdentifier,
      "Extensions",
      width = 145.0,
      minWidth = 95.0,
      sizingPolicy = nimkit.tcspFlexible,
    )
  )
  vscodeGrammarSearchTable.addColumn(
    nimkit.newTableColumn(
      KosmoVscodeGrammarScopeColumnIdentifier,
      "TextMate Scope",
      width = 265.0,
      minWidth = 180.0,
      sizingPolicy = nimkit.tcspFlexible,
    )
  )
  vscodeGrammarSearchTable.addColumn(
    nimkit.newTableColumn(
      KosmoVscodeGrammarPublisherColumnIdentifier,
      "Extension",
      width = 180.0,
      minWidth = 140.0,
      sizingPolicy = nimkit.tcspFlexible,
    )
  )
  vscodeGrammarSearchTable.dataSource = vscodeGrammarSearchSource
  vscodeGrammarSearchTable.delegate = vscodeGrammarSearchSource
  vscodeGrammarSearchTable.connect(
    nimkit.selectionDidChange, settings, vscodeGrammarSelectionDidChange
  )
  settings.xVscodeGrammarCatalog.connect(
    vscodeGrammars.vscodeGrammarCatalogDidUpdate, settings,
    vscodeGrammarCatalogDidUpdate,
  )
  settings.xVscodeGrammarCatalog.connect(
    vscodeGrammars.vscodeGrammarDidInstall, settings, vscodeGrammarDidInstall
  )

  optionButton.identifier = KosmoOptionAsMetaIdentifier
  optionButton.accessibilityLabel = "Use Option or Alt as Meta"
  preferEditorPanesButton.identifier = KosmoPreferEditorPanesIdentifier
  preferEditorPanesButton.accessibilityLabel =
    "Prefer panes not displaying terminals for editor tabs"
  settings.preferEditorPanes = preferEditorPanes
  preferEditorPanesButton.target = nimkit.newActionTarget(
    nimkit.actionSelector("kosmo.preferEditorPanesChanged"), settings
  ) do(settings: KosmoSettingsWindow, sender: DynamicAgent):
    if not settings.xPreferEditorPanesHandler.isNil:
      settings.xPreferEditorPanesHandler(settings.preferEditorPanes())
  preferEditorPanesButton.action =
    nimkit.actionSelector("kosmo.preferEditorPanesChanged")

  optionButton.state = if optionAsMeta: nimkit.bsOn else: nimkit.bsOff
  optionButton.target = nimkit.newActionTarget(optionChanged, settings) do(
    settings: KosmoSettingsWindow, sender: DynamicAgent
  ):
    if not settings.xOptionAsMetaHandler.isNil:
      settings.xOptionAsMetaHandler(settings.optionAsMeta())
  optionButton.action = optionChanged

  terminalLinksButton.identifier = KosmoTerminalLinksIdentifier
  terminalLinksButton.accessibilityLabel = "Open links from terminal output"
  terminalLinksButton.state = if terminalLinksEnabled: nimkit.bsOn else: nimkit.bsOff
  terminalLinksButton.target = nimkit.newActionTarget(terminalLinksChanged, settings) do(
    settings: KosmoSettingsWindow, sender: DynamicAgent
  ):
    if not settings.xTerminalLinksHandler.isNil:
      settings.xTerminalLinksHandler(settings.terminalLinksEnabled())
  terminalLinksButton.action = terminalLinksChanged

  terminalInputPolicyChoice.identifier = KosmoTerminalInputPolicyIdentifier
  terminalInputPolicyChoice.accessibilityLabel = "Terminal input policy"
  settings.terminalInputPolicy = terminalInputPolicy
  terminalInputPolicyChoice.target = nimkit.newActionTarget(
    terminalInputPolicyChanged, settings
  ) do(settings: KosmoSettingsWindow, sender: DynamicAgent):
    if not settings.xTerminalInputPolicyHandler.isNil:
      settings.xTerminalInputPolicyHandler(settings.terminalInputPolicy())
  terminalInputPolicyChoice.action = terminalInputPolicyChanged
  terminalForm.edgeInsets = nimkit.insets(0.0)
  terminalForm.addRow(nimkit.newFormLabel("Terminal input"), terminalInputPolicyChoice)

  terminalPage.stack.addArrangedSubview(
    nimkit.newHeadingLabel("Terminal"),
    terminalForm,
    nimkit.newLabel("Hybrid: Ctrl-W manages panes; Raw sends Control keys directly."),
    nimkit.newLabel(
      "Use Ctrl-\\ before a shortcut to send it to the terminal in Hybrid mode."
    ),
    preferEditorPanesButton,
    optionButton,
    nimkit.newLabel("Use Option/Alt-B and Option/Alt-F to move by words in Bash."),
    terminalLinksButton,
    nimkit.newLabel(
      "Hold the platform link modifier while hovering a URL to reveal and open it."
    ),
  )
  terminalPage.stack.addFlexibleSpacer()

  shortcutProfileChoice.identifier = KosmoShortcutProfileIdentifier
  shortcutProfileChoice.accessibilityLabel = "Shortcut profile"
  shortcutProfileChoice.selectedIndex =
    case shortcutProfile
    of KosmoShortcutProfile.Platform: 0
    of KosmoShortcutProfile.MacOS: 1
  shortcutProfileChoice.target = nimkit.newActionTarget(
    shortcutProfileChanged, settings
  ) do(settings: KosmoSettingsWindow, sender: DynamicAgent):
    if not settings.xShortcutProfileHandler.isNil:
      settings.xShortcutProfileHandler(settings.shortcutProfile())
  shortcutProfileChoice.action = shortcutProfileChanged

  editorInputPolicyChoice.identifier = KosmoEditorInputPolicyIdentifier
  editorInputPolicyChoice.accessibilityLabel = "Editor input policy"
  editorInputPolicyChoice.selectedIndex =
    case editorInputPolicy
    of KosmoEditorInputPolicy.Vim: 0
    of KosmoEditorInputPolicy.Native: 1
    of KosmoEditorInputPolicy.Hybrid: 2
  editorInputPolicyChoice.target = nimkit.newActionTarget(
    editorInputPolicyChanged, settings
  ) do(settings: KosmoSettingsWindow, sender: DynamicAgent):
    if not settings.xEditorInputPolicyHandler.isNil:
      settings.xEditorInputPolicyHandler(settings.editorInputPolicy())
  editorInputPolicyChoice.action = editorInputPolicyChanged

  forceInputModeButton.identifier = KosmoForceInputModeIdentifier
  forceInputModeButton.accessibilityLabel = "Force input mode"
  forceInputModeButton.state = if forceInputMode: nimkit.bsOn else: nimkit.bsOff
  forceInputModeButton.target = nimkit.newActionTarget(
    nimkit.actionSelector("kosmo.forceInputModeChanged"), settings
  ) do(settings: KosmoSettingsWindow, sender: DynamicAgent):
    if not settings.xForceInputModeHandler.isNil:
      settings.xForceInputModeHandler(settings.forceInputMode())
  forceInputModeButton.action = nimkit.actionSelector("kosmo.forceInputModeChanged")

  shortcutsTable.identifier = KosmoShortcutsTableIdentifier
  shortcutsTable.accessibilityLabel = "Active Kosmo shortcuts"
  shortcutsTable.columnSizing = nimkit.tvcsFill
  shortcutsTable.selectionMode = nimkit.tsmNone
  shortcutsTable.usesAlternatingRowBackgrounds = true
  shortcutsTable.showsRowSeparators = true
  shortcutsTable.addColumn(
    nimkit.newTableColumn(
      KosmoShortcutActionColumnIdentifier,
      "Action",
      width = KosmoShortcutActionColumnWidth,
      sizingPolicy = nimkit.tcspFixed,
    )
  )
  shortcutsTable.addColumn(
    nimkit.newTableColumn(
      KosmoShortcutDescriptionColumnIdentifier,
      "Description",
      width = KosmoShortcutDescriptionColumnWidth,
      minWidth = KosmoShortcutDescriptionColumnWidth,
      sizingPolicy = nimkit.tcspFlexible,
    )
  )
  shortcutsTable.addColumn(
    nimkit.newTableColumn(
      KosmoShortcutKeysColumnIdentifier,
      "Shortcut Keys",
      width = KosmoShortcutKeysColumnWidth,
      sizingPolicy = nimkit.tcspFixed,
    )
  )
  shortcutsTable.dataSource = shortcutsSource
  shortcutsTable.delegate = shortcutsSource
  shortcutsForm.edgeInsets = nimkit.insets(0.0)
  shortcutsForm.spacing[nimkit.dcol] = 12.0
  shortcutsForm.spacing[nimkit.drow] = 8.0
  shortcutsForm.minFieldWidth = 180.0
  shortcutsForm.addRow(nimkit.newFormLabel("Shortcut profile"), shortcutProfileChoice)
  shortcutsForm.addRow(nimkit.newFormLabel("Editor input"), editorInputPolicyChoice)
  shortcutsPage.stack.addArrangedSubview(
    nimkit.newHeadingLabel("Active Shortcuts"),
    shortcutsForm,
    forceInputModeButton,
    nimkit.newLabel(
      "Keep editable buffers in input mode; use Ctrl-O to open Moe's command line."
    ),
    nimkit.newLabel("Changes apply immediately; edit bindings in keybindings.json."),
  )
  shortcutsPage.stack.fillAvailableSpace(shortcutsTable)

  moeThemesTable.identifier = KosmoMoeThemesTableIdentifier
  moeThemesTable.accessibilityLabel = "Themes"
  moeThemesTable.selectionMode = nimkit.tsmSingle
  moeThemesTable.columnSizing = nimkit.tvcsFill
  moeThemesTable.usesAlternatingRowBackgrounds = true
  moeThemesTable.showsRowSeparators = true
  moeThemesTable.addColumn(
    nimkit.newTableColumn(
      KosmoMoeThemeNameColumnIdentifier,
      "Theme",
      width = 140.0,
      minWidth = 110.0,
      sizingPolicy = nimkit.tcspFlexible,
    )
  )
  moeThemesTable.addColumn(
    nimkit.newTableColumn(
      KosmoMoeThemeAppearanceColumnIdentifier,
      "Appearance",
      width = 100.0,
      sizingPolicy = nimkit.tcspFixed,
    )
  )
  moeThemesTable.addColumn(
    nimkit.newTableColumn(
      KosmoMoeThemePreviewColumnIdentifier,
      "Colors",
      width = 190.0,
      minWidth = 170.0,
      sizingPolicy = nimkit.tcspFlexible,
    )
  )
  moeThemesTable.dataSource = moeThemesSource
  moeThemesTable.delegate = moeThemesSource
  moeThemesSource.targetsTable = themeTargets
  moeThemesSource.themesTable = moeThemesTable
  moeThemesSource.selectionStatus = themeSelectionStatus
  moeThemesSource.resetButton = resetThemes
  themeTargets.identifier = KosmoThemeTargetIdentifier
  themeTargets.accessibilityLabel = "Items and current themes"
  themeTargets.selectionMode = nimkit.tsmMultiple
  themeTargets.visibleRows = 5
  themeTargets.columnSizing = nimkit.tvcsFill
  themeTargets.usesAlternatingRowBackgrounds = true
  themeTargets.addColumn(nimkit.newTableColumn("item", "Item", width = 80.0))
  themeTargets.addColumn(
    nimkit.newTableColumn(
      "theme", "Current theme", width = 165.0, sizingPolicy = nimkit.tcspFlexible
    )
  )
  themeTargets.dataSource = settings.xThemeTargetsSource
  themeTargets.connect(
    nimkit.selectionDidChange, moeThemesSource, themeTargetsDidChange
  )
  selectAllThemes.identifier = KosmoSelectAllThemesIdentifier
  selectRichTextThemes.identifier = KosmoSelectRichTextThemesIdentifier
  let selectAllAction = nimkit.actionSelector("kosmo.themes.selectAll")
  selectAllThemes.target = nimkit.newActionTarget(selectAllAction, settings) do(
    settings: KosmoSettingsWindow, sender: DynamicAgent
  ):
    settings.xMoeThemesSource.targetsTable.selectedIndexes = @[0, 1, 2, 3, 4]
  selectAllThemes.action = selectAllAction
  let selectRichTextAction = nimkit.actionSelector("kosmo.themes.selectRichText")
  selectRichTextThemes.target = nimkit.newActionTarget(selectRichTextAction, settings) do(
    settings: KosmoSettingsWindow, sender: DynamicAgent
  ):
    settings.xMoeThemesSource.targetsTable.selectedIndexes = @[2, 3, 4]
  selectRichTextThemes.action = selectRichTextAction
  resetThemes.identifier = KosmoResetThemesIdentifier
  resetThemes.accessibilityLabel =
    "Restore selected items to their themes when Settings opened"
  resetThemes.action = nimkit.actionSelector("kosmo.themes.reset")
  resetThemes.target = nimkit.newActionTarget(resetThemes.action, settings) do(
    settings: KosmoSettingsWindow, sender: DynamicAgent
  ):
    settings.xMoeThemesSource.resetSelectedThemes()
  themeButtons.spacing = 8
  themeButtons.alignment = nimkit.svaCenter
  themeButtons.addArrangedSubview(
    selectAllThemes, selectRichTextThemes, resetThemes, themeSelectionStatus
  )
  settings.updateMoeThemes(
    moeThemes, selectedMoeThemeIdentifier, selectedTerminalThemeIdentifier,
    selectedMarkdownThemeIdentifier, selectedGitDiffThemeIdentifier,
    selectedGitHubThemeIdentifier,
  )
  moeThemesTable.requestSort(
    moeThemesTable.columnWithIdentifier(KosmoMoeThemeAppearanceColumnIdentifier),
    nimkit.tsdAscending,
  )
  themeTargets.selectedIndexes = @[0]
  moeThemesPage.stack.spacing = 4
  moeThemesPage.stack.addArrangedSubview(
    nimkit.newHeadingLabel("Themes"),
    nimkit.newLabel("Select items on the left, then choose a theme on the right."),
    themeButtons,
  )
  themeLists.identifier = "kosmo.settings.themes.lists"
  themeLists.addPane(themeTargets, minSize = 200)
  themeLists.addPane(moeThemesTable, minSize = 260)
  themeLists.restoreState(nimkit.SplitViewState(fractions: @[0.32'f32, 0.68'f32]))
  moeThemesPage.stack.fillAvailableSpace(themeLists)

  textMateGrammarsTable.identifier = KosmoTextMateGrammarsTableIdentifier
  textMateGrammarsTable.accessibilityLabel = "Installed grammars"
  textMateGrammarsTable.columnSizing = nimkit.tvcsFill
  textMateGrammarsTable.selectionMode = nimkit.tsmNone
  textMateGrammarsTable.usesAlternatingRowBackgrounds = true
  textMateGrammarsTable.showsRowSeparators = true
  textMateGrammarsTable.addColumn(
    nimkit.newTableColumn(
      KosmoTextMateGrammarNameColumnIdentifier,
      "Grammar",
      width = 250.0,
      minWidth = 180.0,
      sizingPolicy = nimkit.tcspFlexible,
    )
  )
  textMateGrammarsTable.addColumn(
    nimkit.newTableColumn(
      KosmoTextMateGrammarScopeColumnIdentifier,
      "Scope",
      width = 330.0,
      minWidth = 220.0,
      sizingPolicy = nimkit.tcspFlexible,
    )
  )
  textMateGrammarsTable.addColumn(
    nimkit.newTableColumn(
      KosmoTextMateGrammarOriginColumnIdentifier,
      "Origin",
      width = 100.0,
      sizingPolicy = nimkit.tcspFixed,
    )
  )
  textMateGrammarsTable.dataSource = textMateGrammarsSource
  textMateGrammarsTable.delegate = textMateGrammarsSource
  vscodeGrammarSearchControls.spacing = 8.0
  vscodeGrammarSearchControls.alignment = nimkit.svaCenter
  vscodeGrammarSearchControls.fillAvailableWidth(vscodeGrammarSearchField)
  vscodeGrammarSearchControls.addArrangedSubview(vscodeGrammarSearchButton)
  grammarInstallerButtons.spacing = 8
  grammarInstallerButtons.alignment = nimkit.svaCenter
  grammarInstallerButtons.addFlexibleSpacer()
  grammarInstallerButtons.addArrangedSubview(
    vscodeGrammarInstallButton, grammarInstallerDone
  )
  grammarInstallerPage.stack.addArrangedSubview(
    nimkit.newHeadingLabel("Install grammars"),
    nimkit.newLabel("Find TextMate grammars on Open VSX."),
    vscodeGrammarSearchControls,
    vscodeGrammarSearchStatus,
  )
  grammarInstallerPage.stack.fillAvailableSpace(vscodeGrammarSearchTable)
  grammarInstallerPage.stack.addArrangedSubview(grammarInstallerButtons)
  settings.xGrammarInstaller.setContentView(grammarInstallerPage.view)
  settings.xGrammarInstaller.styleMask =
    settings.xGrammarInstaller.styleMask + {nimkit.wsmResizable}
  settings.xGrammarInstaller.contentMinSize = nimkit.initSize(560, 300)
  grammarInstallerDone.identifier = KosmoGrammarInstallerDoneIdentifier
  grammarInstallerDone.action = nimkit.actionSelector("kosmo.closeGrammarInstaller")
  grammarInstallerDone.target = nimkit.newActionTarget(
    grammarInstallerDone.action, settings
  ) do(settings: KosmoSettingsWindow, sender: DynamicAgent):
    settings.xGrammarInstaller.close()
  installMoreGrammars.identifier = KosmoInstallMoreGrammarsIdentifier
  installMoreGrammars.action = nimkit.actionSelector("kosmo.showGrammarInstaller")
  installMoreGrammars.target = nimkit.newActionTarget(
    installMoreGrammars.action, settings
  ) do(settings: KosmoSettingsWindow, sender: DynamicAgent):
    settings.showGrammarInstaller()
  textMateGrammarsPage.stack.addArrangedSubview(
    nimkit.newHeadingLabel("Installed grammars")
  )
  textMateGrammarsPage.stack.fillAvailableSpace(textMateGrammarsTable)
  let grammarActions = nimkit.newStackView(nimkit.laHorizontal)
  grammarActions.alignment = nimkit.svaCenter
  grammarActions.addFlexibleSpacer()
  grammarActions.addArrangedSubview(installMoreGrammars)
  textMateGrammarsPage.stack.addArrangedSubview(grammarActions)

  nimdexAutoStartButton.identifier = "kosmo.settings.nimdex.autostart"
  nimdexAutoStartButton.state = if nimdexAutoStart: nimkit.bsOn else: nimkit.bsOff
  nimdexAutoStartButton.target = nimkit.newActionTarget(
    nimkit.actionSelector("kosmo.nimdex.autoStartChanged"), settings
  ) do(settings: KosmoSettingsWindow, sender: DynamicAgent):
    let delegate = settings.xNimdexDelegate{}
    if not delegate.isNil:
      delegate.nimdexSettingsAutoStart(nimkit.Button(sender).state == nimkit.bsOn)
  nimdexAutoStartButton.action = nimkit.actionSelector("kosmo.nimdex.autoStartChanged")
  nimdexMode.identifier = "kosmo.settings.nimdex.mode"
  nimdexLocal.identifier = "kosmo.settings.nimdex.local"
  nimdexAddress.identifier = "kosmo.settings.nimdex.address"
  nimdexStatusLabel.identifier = "kosmo.settings.nimdex.status"
  nimdexConnect.identifier = "kosmo.settings.nimdex.connect"
  nimdexDisconnect.identifier = "kosmo.settings.nimdex.disconnect"
  nimdexMode.selectedIndex = if nimdexCommand.startsWith("tcp://"): 1 else: 0
  nimdexLocal.text = if nimdexMode.selectedIndex == 0: nimdexCommand else: ""
  nimdexAddress.text =
    if nimdexMode.selectedIndex == 1: nimdexCommand else: "tcp://127.0.0.1:9257"
  settings.xNimdexMode = nimdexMode
  settings.xNimdexLocal = nimdexLocal
  settings.xNimdexAddress = nimdexAddress
  settings.xNimdexStatus = nimdexStatusLabel
  nimdexForm.edgeInsets = nimkit.insets(0.0)
  nimdexForm.spacing[nimkit.dcol] = 12.0
  nimdexForm.spacing[nimkit.drow] = 8.0
  nimdexForm.addRow(nimkit.newFormLabel("Mode"), nimdexMode)
  nimdexForm.addRow(nimkit.newFormLabel("Executable or command"), nimdexLocal)
  nimdexForm.addRow(nimkit.newFormLabel("Daemon address"), nimdexAddress)
  nimdexButtons.spacing = 8.0
  nimdexButtons.alignment = nimkit.svaCenter
  nimdexButtons.addArrangedSubview(nimdexConnect, nimdexDisconnect)
  nimdexConnect.target = nimkit.newActionTarget(
    nimkit.actionSelector("kosmo.nimdex.connect"), settings
  ) do(settings: KosmoSettingsWindow, sender: DynamicAgent):
    var command =
      if settings.xNimdexMode.selectedIndex == 1:
        settings.xNimdexAddress.text.strip()
      else:
        settings.xNimdexLocal.text.strip()
    if settings.xNimdexMode.selectedIndex == 0 and command.len > 0 and
        (fileExists(command) or not command.contains(' ')):
      command = quoteShell(command) & " daemon"
    let delegate = settings.xNimdexDelegate{}
    if not delegate.isNil:
      let error = delegate.nimdexSettingsAction(command, true)
      settings.xNimdexStatusError = error.len > 0
      settings.xNimdexStatus.text = if error.len > 0: error else: "Connecting…"
  nimdexConnect.action = nimkit.actionSelector("kosmo.nimdex.connect")
  nimdexDisconnect.target = nimkit.newActionTarget(
    nimkit.actionSelector("kosmo.nimdex.disconnect"), settings
  ) do(settings: KosmoSettingsWindow, sender: DynamicAgent):
    let delegate = settings.xNimdexDelegate{}
    if not delegate.isNil:
      let error = delegate.nimdexSettingsAction("", false)
      settings.xNimdexStatusError = error.len > 0
      settings.xNimdexStatus.text = if error.len > 0: error else: "Disconnected"
  nimdexDisconnect.action = nimkit.actionSelector("kosmo.nimdex.disconnect")
  nimdexPage.stack.spacing = 4.0
  nimdexPage.stack.edgeInsets = nimkit.insets(10.0, 16.0)
  nimdexPage.stack.addArrangedSubview(
    nimkit.newHeadingLabel("Nimdex server"),
    nimdexForm,
    nimdexAutoStartButton,
    nimdexButtons,
    nimdexStatusLabel,
    nimkit.newLabel(
      "Local mode starts Nimdex for this editor; daemon mode connects to an existing listener."
    ),
  )
  if not nimdexDelegate.isNil:
    nimdexStatusLabel.text = nimdexDelegate.nimdexSettingsStatus()

  tabs.identifier = KosmoSettingsTabsIdentifier
  discard tabs.addTabViewItem(
    nimkit.newTabViewItem(
      "Terminal", terminalPage.view, KosmoTerminalSettingsTabIdentifier
    )
  )
  discard tabs.addTabViewItem(
    nimkit.newTabViewItem(
      "Shortcuts", shortcutsPage.view, KosmoShortcutsSettingsTabIdentifier
    )
  )
  discard tabs.addTabViewItem(
    nimkit.newTabViewItem(
      "Themes", moeThemesPage.view, KosmoMoeThemesSettingsTabIdentifier
    )
  )
  discard tabs.addTabViewItem(
    nimkit.newTabViewItem(
      "TextMate Grammars", textMateGrammarsPage.view,
      KosmoTextMateGrammarsSettingsTabIdentifier,
    )
  )
  discard tabs.addTabViewItem(
    nimkit.newTabViewItem("LSP", nimdexPage.view, KosmoNimdexSettingsTabIdentifier)
  )
  layout.spacing = 12.0
  layout.alignment = nimkit.svaFill
  layout.addArrangedSubview(nimkit.newTitleLabel("Kosmo Settings"))
  layout.fillAvailableSpace(tabs)
  result.xContentView.addSubview(layout)
  discard layout.pinEdges(
    toGuide = result.xContentView.contentLayoutGuide(nimkit.insets(22.0, 24.0)),
    edges = {nimkit.leLeft, nimkit.leTop, nimkit.leRight, nimkit.leBottom},
  )
  result.xWindow.styleMask = result.xWindow.styleMask + {nimkit.wsmResizable}
  result.xWindow.contentMinSize = nimkit.initSize(
    KosmoSettingsMinimumWidth,
    max(
      KosmoSettingsMinimumHeight,
      settingsContentMinimumHeight(result.xContentView, tabs),
    ),
  )

proc refreshNimdexStatus*(settings: KosmoSettingsWindow) =
  ## Refresh the connection indicator from the editor worker.
  if not settings.isNil and not settings.xNimdexStatusError:
    let delegate = settings.xNimdexDelegate{}
    if delegate.isNil:
      return
    let status = delegate.nimdexSettingsStatus()
    if settings.xNimdexStatus.text != status:
      settings.xNimdexStatus.text = status

proc window*(settings: KosmoSettingsWindow): nimkit.Panel =
  ## Return the settings panel window.
  settings.xWindow

proc contentView*(settings: KosmoSettingsWindow): nimkit.View =
  ## Return the settings panel root view.
  settings.xContentView

proc firstResponder*(settings: KosmoSettingsWindow): nimkit.Responder =
  ## Return the control that should receive initial keyboard focus.
  settings.xFirstResponder
