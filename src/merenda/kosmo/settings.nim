## Kosmo-specific application settings.

import ../nimkit as nimkit
import ./moe
import ./shortcuts

export shortcuts

const
  KosmoSettingsTabsIdentifier* = "kosmo.settings.tabs"
  KosmoTerminalSettingsTabIdentifier* = "kosmo.settings.terminal"
  KosmoShortcutsSettingsTabIdentifier* = "kosmo.settings.shortcuts"
  KosmoMoeThemesSettingsTabIdentifier* = "kosmo.settings.moeThemes"
  KosmoOptionAsMetaIdentifier* = "kosmo.settings.terminal.optionAsMeta"
  KosmoShortcutsTableIdentifier* = "kosmo.settings.shortcuts.table"
  KosmoShortcutProfileIdentifier* = "kosmo.settings.shortcuts.profile"
  KosmoEditorInputPolicyIdentifier* = "kosmo.settings.shortcuts.editorInput"
  KosmoMoeThemesTableIdentifier* = "kosmo.settings.moeThemes.table"
  KosmoMoeThemeSelectorIdentifier* = KosmoMoeThemesTableIdentifier
  KosmoShortcutActionColumnIdentifier* = "action"
  KosmoShortcutDescriptionColumnIdentifier* = "description"
  KosmoShortcutKeysColumnIdentifier* = "keys"
  KosmoMoeThemeNameColumnIdentifier* = "theme"
  KosmoMoeThemePreviewColumnIdentifier* = "preview"
  KosmoMoeThemePreviewText* = "let fn = \"text\" #"
  KosmoShortcutActionColumnWidth = 175.0'f32
  KosmoShortcutDescriptionColumnWidth = 310.0'f32
  KosmoShortcutKeysColumnWidth = 155.0'f32

type
  KosmoOptionAsMetaHandler* = proc(enabled: bool) {.closure.}
  KosmoMoeThemeHandler* = proc(identifier: string): bool {.closure.}
  KosmoShortcutProfileHandler* = proc(profile: KosmoShortcutProfile) {.closure.}
  KosmoEditorInputPolicyHandler* = proc(policy: KosmoEditorInputPolicy) {.closure.}

  KosmoShortcutSetting* = object
    action*: string
    description*: string
    keys*: string

  KosmoMoeThemeSetting* = object
    identifier*: string
    name*: string
    preview*: KosmoMoeThemePreview

  KosmoShortcutsTableSource = ref object of nimkit.Responder
    shortcuts: seq[KosmoShortcutSetting]

  KosmoMoeThemePreviewView = ref object of nimkit.View
    preview: KosmoMoeThemePreview

  KosmoMoeThemesTableSource = ref object of nimkit.Responder
    themes: seq[KosmoMoeThemeSetting]
    selectedIdentifier: string
    handler: KosmoMoeThemeHandler

  KosmoSettingsWindow* = ref object of nimkit.Responder
    xWindow: nimkit.Panel
    xContentView: nimkit.View
    xFirstResponder: nimkit.Responder
    xOptionAsMetaButton: nimkit.Button
    xOptionAsMetaHandler: KosmoOptionAsMetaHandler
    xTabs: nimkit.TabView
    xShortcutsTable: nimkit.TableView
    xShortcutsSource: KosmoShortcutsTableSource
    xShortcutProfileChoice: nimkit.ComboBox
    xEditorInputPolicyChoice: nimkit.ComboBox
    xShortcutProfileHandler: KosmoShortcutProfileHandler
    xEditorInputPolicyHandler: KosmoEditorInputPolicyHandler
    xMoeThemesTable: nimkit.TableView
    xMoeThemesSource: KosmoMoeThemesTableSource

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

func nimkitColor(value: KosmoMoeThemeColor): nimkit.Color =
  nimkit.color(
    value.red.float32 / 255.0'f32,
    value.green.float32 / 255.0'f32,
    value.blue.float32 / 255.0'f32,
  )

protocol KosmoMoeThemePreviewDrawing of nimkit.ViewDrawingProtocol:
  method draw(view: KosmoMoeThemePreviewView, context: nimkit.DrawContext) =
    let
      bounds = view.bounds()
      baseStyle = context.appearance.resolveTextStyle(
        nimkit.controlStyle(nimkit.srMonoTextView),
        view.preview.foreground.nimkitColor(),
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
    context.addRectangle(backgroundRect, view.preview.background.nimkitColor())
    var textX = backgroundRect.origin.x + 6.0'f32
    template addSegment(text: string, colorValue: KosmoMoeThemeColor) =
      block:
        var style = baseStyle
        style.color = colorValue.nimkitColor()
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
    preview: KosmoMoeThemePreview
): KosmoMoeThemePreviewView =
  result = KosmoMoeThemePreviewView(preview: preview)
  nimkit.initViewFields(result)
  result.accessibilityLabel = KosmoMoeThemePreviewText
  discard result.withProtocol(KosmoMoeThemePreviewDrawing)

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

protocol KosmoMoeThemesTableDelegate of nimkit.TableViewDelegate:
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
    if row notin 0 ..< source.themes.len:
      return
    let identifier = source.themes[row].identifier
    if identifier == source.selectedIdentifier:
      return
    let previousIdentifier = source.selectedIdentifier
    var applied = true
    if not source.handler.isNil:
      applied = source.handler(identifier)
    if applied:
      source.selectedIdentifier = identifier
    else:
      tableView.selectedIndex = tableView.tableRowIndexForIdentifier(previousIdentifier)

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

proc newSettingsPage(): tuple[view: nimkit.View, stack: nimkit.StackView] =
  result.stack = nimkit.newStackView(nimkit.laVertical)
  result.stack.spacing = 12.0
  result.stack.alignment = nimkit.svaFill
  result.stack.edgeInsets = nimkit.insets(18.0, 20.0)
  result.view = result.stack

proc optionAsMeta*(settings: KosmoSettingsWindow): bool =
  ## Return the current terminal Option/Alt-as-Meta selection.
  not settings.isNil and settings.xOptionAsMetaButton.state == nimkit.bsOn

proc `optionAsMeta=`*(settings: KosmoSettingsWindow, enabled: bool) =
  ## Update the terminal Option/Alt-as-Meta selection without invoking its action.
  if not settings.isNil:
    settings.xOptionAsMetaButton.state = if enabled: nimkit.bsOn else: nimkit.bsOff

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

proc selectedMoeThemeIdentifier*(settings: KosmoSettingsWindow): string =
  ## Return the theme selected in the Moe Themes settings tab.
  if not settings.isNil and not settings.xMoeThemesSource.isNil:
    result = settings.xMoeThemesSource.selectedIdentifier

proc updateMoeThemes*(
    settings: KosmoSettingsWindow,
    themes: openArray[KosmoMoeThemeSetting],
    selectedIdentifier: string,
) =
  ## Replace the available Moe themes and synchronize the current selection.
  if settings.isNil or settings.xMoeThemesSource.isNil or settings.xMoeThemesTable.isNil:
    return
  settings.xMoeThemesSource.themes = @themes
  settings.xMoeThemesTable.reloadData()
  var selectedRow =
    settings.xMoeThemesTable.tableRowIndexForIdentifier(selectedIdentifier)
  if selectedRow < 0 and themes.len > 0:
    selectedRow = 0
  settings.xMoeThemesSource.selectedIdentifier =
    if selectedRow >= 0:
      themes[selectedRow].identifier
    else:
      ""
  settings.xMoeThemesTable.selectedIndex = selectedRow

proc newKosmoSettingsWindow*(
    optionAsMeta = true,
    optionAsMetaHandler: KosmoOptionAsMetaHandler = nil,
    shortcutProfile = defaultKosmoShortcutProfile(),
    shortcutProfileHandler: KosmoShortcutProfileHandler = nil,
    editorInputPolicy = defaultKosmoEditorInputPolicy(),
    editorInputPolicyHandler: KosmoEditorInputPolicyHandler = nil,
    shortcuts: openArray[KosmoShortcutSetting] = [],
    moeThemes: openArray[KosmoMoeThemeSetting] = [],
    selectedMoeThemeIdentifier = "",
    moeThemeHandler: KosmoMoeThemeHandler = nil,
): KosmoSettingsWindow =
  ## Create Kosmo's settings panel, which intentionally contains no Merenda settings.
  let
    shortcutsSource = newKosmoShortcutsTableSource(shortcuts)
    moeThemesSource = newKosmoMoeThemesTableSource(moeThemeHandler)
  result = KosmoSettingsWindow(
    xWindow: nimkit.newPanel("Kosmo Settings", nimkit.rect(180, 160, 760, 420)),
    xContentView: nimkit.newView(),
    xOptionAsMetaHandler: optionAsMetaHandler,
    xShortcutProfileHandler: shortcutProfileHandler,
    xEditorInputPolicyHandler: editorInputPolicyHandler,
    xShortcutsSource: shortcutsSource,
    xMoeThemesSource: moeThemesSource,
  )
  nimkit.initResponder(result)
  let
    settings = result
    layout = nimkit.newStackView(nimkit.laVertical)
    tabs = nimkit.newTabView()
    terminalPage = newSettingsPage()
    shortcutsPage = newSettingsPage()
    moeThemesPage = newSettingsPage()
    optionButton = nimkit.newCheckBox("Use Option/Alt as Meta")
    shortcutProfileChoice = nimkit.newComboBox(["Platform", "macOS-style"])
    editorInputPolicyChoice = nimkit.newComboBox(["Vim", "Native", "Hybrid"])
    shortcutsTable = nimkit.newTableView()
    moeThemesTable = nimkit.newTableView()
    optionChanged = nimkit.actionSelector("kosmo.optionAsMetaChanged")
    shortcutProfileChanged = nimkit.actionSelector("kosmo.shortcutProfileChanged")
    editorInputPolicyChanged = nimkit.actionSelector("kosmo.editorInputPolicyChanged")
  result.xOptionAsMetaButton = optionButton
  result.xFirstResponder = optionButton
  result.xTabs = tabs
  result.xShortcutsTable = shortcutsTable
  result.xShortcutProfileChoice = shortcutProfileChoice
  result.xEditorInputPolicyChoice = editorInputPolicyChoice
  result.xMoeThemesTable = moeThemesTable

  optionButton.identifier = KosmoOptionAsMetaIdentifier
  optionButton.accessibilityLabel = "Use Option or Alt as Meta"
  optionButton.state = if optionAsMeta: nimkit.bsOn else: nimkit.bsOff
  optionButton.target = nimkit.newActionTarget(optionChanged) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    if not settings.xOptionAsMetaHandler.isNil:
      settings.xOptionAsMetaHandler(settings.optionAsMeta())
  optionButton.action = optionChanged

  terminalPage.stack.addArrangedSubview(
    nimkit.newHeadingLabel("Terminal"),
    optionButton,
    nimkit.newLabel(
      "Send Option/Alt-B and Option/Alt-F as Bash backward-word and forward-word " &
        "shortcuts."
    ),
  )
  terminalPage.stack.addFlexibleSpacer()

  shortcutProfileChoice.identifier = KosmoShortcutProfileIdentifier
  shortcutProfileChoice.accessibilityLabel = "Shortcut profile"
  shortcutProfileChoice.selectedIndex =
    case shortcutProfile
    of KosmoShortcutProfile.Platform: 0
    of KosmoShortcutProfile.MacOS: 1
  shortcutProfileChoice.target = nimkit.newActionTarget(shortcutProfileChanged) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
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
  editorInputPolicyChoice.target = nimkit.newActionTarget(editorInputPolicyChanged) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    if not settings.xEditorInputPolicyHandler.isNil:
      settings.xEditorInputPolicyHandler(settings.editorInputPolicy())
  editorInputPolicyChoice.action = editorInputPolicyChanged

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
  shortcutsPage.stack.addArrangedSubview(
    nimkit.newHeadingLabel("Active Shortcuts"),
    nimkit.newLabel("Shortcut profile"),
    shortcutProfileChoice,
    nimkit.newLabel("Editor input"),
    editorInputPolicyChoice,
    nimkit.newLabel(
      "Profiles and input routing apply immediately. Individual bindings are " &
        "configured in keybindings.json."
    ),
  )
  shortcutsPage.stack.fillAvailableSpace(shortcutsTable)

  moeThemesTable.identifier = KosmoMoeThemesTableIdentifier
  moeThemesTable.accessibilityLabel = "Moe editor themes"
  moeThemesTable.selectionMode = nimkit.tsmSingle
  moeThemesTable.usesAlternatingRowBackgrounds = true
  moeThemesTable.showsRowSeparators = true
  moeThemesTable.addColumn(
    nimkit.newTableColumn(KosmoMoeThemeNameColumnIdentifier, "Theme", width = 285.0)
  )
  moeThemesTable.addColumn(
    nimkit.newTableColumn(KosmoMoeThemePreviewColumnIdentifier, "Colors", width = 280.0)
  )
  moeThemesTable.dataSource = moeThemesSource
  moeThemesTable.delegate = moeThemesSource
  settings.updateMoeThemes(moeThemes, selectedMoeThemeIdentifier)
  moeThemesPage.stack.addArrangedSubview(
    nimkit.newHeadingLabel("Moe Theme"),
    nimkit.newLabel(
      "Choose a bundled theme or a TOML theme installed in ~/.config/moe/themes."
    ),
  )
  moeThemesPage.stack.fillAvailableSpace(moeThemesTable)

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
      "Moe Themes", moeThemesPage.view, KosmoMoeThemesSettingsTabIdentifier
    )
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
  result.xWindow.automaticallyAdjustsContentMinSize = true

proc window*(settings: KosmoSettingsWindow): nimkit.Panel =
  ## Return the settings panel window.
  settings.xWindow

proc contentView*(settings: KosmoSettingsWindow): nimkit.View =
  ## Return the settings panel root view.
  settings.xContentView

proc firstResponder*(settings: KosmoSettingsWindow): nimkit.Responder =
  ## Return the control that should receive initial keyboard focus.
  settings.xFirstResponder
