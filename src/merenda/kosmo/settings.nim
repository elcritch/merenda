## Kosmo-specific application settings.

import ../nimkit as nimkit

const
  KosmoSettingsTabsIdentifier* = "kosmo.settings.tabs"
  KosmoTerminalSettingsTabIdentifier* = "kosmo.settings.terminal"
  KosmoShortcutsSettingsTabIdentifier* = "kosmo.settings.shortcuts"
  KosmoMoeThemesSettingsTabIdentifier* = "kosmo.settings.moeThemes"
  KosmoOptionAsMetaIdentifier* = "kosmo.settings.terminal.optionAsMeta"
  KosmoShortcutsTableIdentifier* = "kosmo.settings.shortcuts.table"
  KosmoMoeThemeSelectorIdentifier* = "kosmo.settings.moeThemes.selector"
  KosmoShortcutActionColumnIdentifier* = "action"
  KosmoShortcutDescriptionColumnIdentifier* = "description"
  KosmoShortcutKeysColumnIdentifier* = "keys"

type
  KosmoOptionAsMetaHandler* = proc(enabled: bool) {.closure.}
  KosmoMoeThemeHandler* = proc(identifier: string): bool {.closure.}

  KosmoShortcutSetting* = object
    action*: string
    description*: string
    keys*: string

  KosmoMoeThemeSetting* = object
    identifier*: string
    name*: string

  KosmoShortcutsTableSource = ref object of nimkit.Responder
    shortcuts: seq[KosmoShortcutSetting]

  KosmoSettingsWindow* = ref object of nimkit.Responder
    xWindow: nimkit.Panel
    xContentView: nimkit.View
    xFirstResponder: nimkit.Responder
    xOptionAsMetaButton: nimkit.Button
    xOptionAsMetaHandler: KosmoOptionAsMetaHandler
    xTabs: nimkit.TabView
    xShortcutsTable: nimkit.TableView
    xShortcutsSource: KosmoShortcutsTableSource
    xMoeThemeSelector: nimkit.ComboBox
    xMoeThemes: seq[KosmoMoeThemeSetting]
    xMoeThemeIdentifier: string
    xMoeThemeHandler: KosmoMoeThemeHandler

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

proc newSettingsPage(): tuple[view: nimkit.View, stack: nimkit.StackView] =
  result.view = nimkit.newView()
  result.stack = nimkit.newStackView(nimkit.laVertical)
  result.stack.spacing = 12.0
  result.stack.alignment = nimkit.svaFill
  result.view.addSubview(result.stack)
  discard result.stack.pinEdges(
    toGuide = result.view.contentLayoutGuide(nimkit.insets(18.0, 20.0)),
    edges = {nimkit.leLeft, nimkit.leTop, nimkit.leRight, nimkit.leBottom},
  )

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

proc selectedMoeThemeIdentifier*(settings: KosmoSettingsWindow): string =
  ## Return the theme selected in the Moe Themes settings tab.
  if not settings.isNil:
    result = settings.xMoeThemeIdentifier

proc updateMoeThemes*(
    settings: KosmoSettingsWindow,
    themes: openArray[KosmoMoeThemeSetting],
    selectedIdentifier: string,
) =
  ## Replace the available Moe themes and synchronize the current selection.
  if settings.isNil or settings.xMoeThemeSelector.isNil:
    return
  settings.xMoeThemes = @themes
  var options = newSeqOfCap[nimkit.ComboBoxOption](themes.len)
  for theme in themes:
    options.add nimkit.initComboBoxOption(
      identifier = theme.identifier, displayText = theme.name
    )
  settings.xMoeThemeSelector.setOptions(options)
  settings.xMoeThemeIdentifier = selectedIdentifier
  settings.xMoeThemeSelector.selectedOptionIdentifier = selectedIdentifier
  if settings.xMoeThemeSelector.selectedIndex < 0 and themes.len > 0:
    settings.xMoeThemeSelector.selectedIndex = 0
    settings.xMoeThemeIdentifier = themes[0].identifier

proc newKosmoSettingsWindow*(
    optionAsMeta = true,
    optionAsMetaHandler: KosmoOptionAsMetaHandler = nil,
    shortcuts: openArray[KosmoShortcutSetting] = [],
    moeThemes: openArray[KosmoMoeThemeSetting] = [],
    selectedMoeThemeIdentifier = "",
    moeThemeHandler: KosmoMoeThemeHandler = nil,
): KosmoSettingsWindow =
  ## Create Kosmo's settings panel, which intentionally contains no Merenda settings.
  let shortcutsSource = newKosmoShortcutsTableSource(shortcuts)
  result = KosmoSettingsWindow(
    xWindow: nimkit.newPanel("Kosmo Settings", nimkit.rect(180, 160, 760, 420)),
    xContentView: nimkit.newView(),
    xOptionAsMetaHandler: optionAsMetaHandler,
    xShortcutsSource: shortcutsSource,
    xMoeThemes: @moeThemes,
    xMoeThemeIdentifier: selectedMoeThemeIdentifier,
    xMoeThemeHandler: moeThemeHandler,
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
    shortcutsTable = nimkit.newTableView()
    moeThemeSelector = nimkit.newComboBox()
    optionChanged = nimkit.actionSelector("kosmo.optionAsMetaChanged")
    moeThemeChanged = nimkit.actionSelector("kosmo.moeThemeChanged")
  result.xOptionAsMetaButton = optionButton
  result.xFirstResponder = optionButton
  result.xTabs = tabs
  result.xShortcutsTable = shortcutsTable
  result.xMoeThemeSelector = moeThemeSelector

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

  shortcutsTable.identifier = KosmoShortcutsTableIdentifier
  shortcutsTable.accessibilityLabel = "Active Kosmo shortcuts"
  shortcutsTable.selectionMode = nimkit.tsmNone
  shortcutsTable.usesAlternatingRowBackgrounds = true
  shortcutsTable.showsRowSeparators = true
  shortcutsTable.addColumn(
    nimkit.newTableColumn(KosmoShortcutActionColumnIdentifier, "Action", width = 175.0)
  )
  shortcutsTable.addColumn(
    nimkit.newTableColumn(
      KosmoShortcutDescriptionColumnIdentifier, "Description", width = 310.0
    )
  )
  shortcutsTable.addColumn(
    nimkit.newTableColumn(
      KosmoShortcutKeysColumnIdentifier, "Shortcut Keys", width = 155.0
    )
  )
  shortcutsTable.dataSource = shortcutsSource
  shortcutsTable.delegate = shortcutsSource
  shortcutsTable.setHuggingPriority(nimkit.LayoutPriorityLow, nimkit.laVertical)
  shortcutsTable.setCompressionPriority(
    nimkit.LayoutPriorityRequired, nimkit.laVertical
  )
  shortcutsPage.stack.addArrangedSubview(
    nimkit.newHeadingLabel("Active Shortcuts"),
    nimkit.newLabel("These shortcuts are active in Kosmo and are read-only for now."),
    shortcutsTable,
  )

  moeThemeSelector.identifier = KosmoMoeThemeSelectorIdentifier
  moeThemeSelector.accessibilityLabel = "Moe editor theme"
  settings.updateMoeThemes(moeThemes, selectedMoeThemeIdentifier)
  moeThemeSelector.target = nimkit.newActionTarget(moeThemeChanged) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    let identifier = moeThemeSelector.selectedOptionIdentifier
    if identifier.len == 0 or identifier == settings.xMoeThemeIdentifier:
      return
    let previousIdentifier = settings.xMoeThemeIdentifier
    var applied = true
    if not settings.xMoeThemeHandler.isNil:
      applied = settings.xMoeThemeHandler(identifier)
    if applied:
      settings.xMoeThemeIdentifier = identifier
    else:
      moeThemeSelector.selectedOptionIdentifier = previousIdentifier
  moeThemeSelector.action = moeThemeChanged
  moeThemesPage.stack.addArrangedSubview(
    nimkit.newHeadingLabel("Moe Theme"),
    nimkit.newLabel(
      "Choose a bundled theme or a TOML theme installed in ~/.config/moe/themes."
    ),
    moeThemeSelector,
  )
  moeThemesPage.stack.addFlexibleSpacer()

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
  tabs.setHuggingPriority(nimkit.LayoutPriorityLow, nimkit.laVertical)
  tabs.setCompressionPriority(nimkit.LayoutPriorityRequired, nimkit.laVertical)

  layout.spacing = 12.0
  layout.alignment = nimkit.svaFill
  layout.addArrangedSubview(nimkit.newTitleLabel("Kosmo Settings"), tabs)
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
