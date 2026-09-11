# Kosmo editor views, Markdown controls, and pane presentation.

proc updateActivePaneIndicator(group: KosmoEditorGroup, active: bool) =
  if group.isNil or group.pane.isNil:
    return
  if active:
    group.pane.documentTabs.removeStyleClass(KosmoInactivePaneStyleClass)
  else:
    group.pane.documentTabs.addStyleClass(KosmoInactivePaneStyleClass)
  if not group.pane.activeIndicator.isNil:
    group.pane.activeIndicator.hidden = not active

func activeGroup(controller: KosmoDockController): KosmoEditorGroup =
  controller.xActiveGroup

proc `activeGroup=`(controller: KosmoDockController, group: KosmoEditorGroup) =
  if controller.xActiveGroup == group:
    return
  controller.xActiveGroup = group
  if not group.isNil:
    for host in controller.hosts:
      if host.workspace == group.workspace:
        host.activeGroup = group
  for candidate in controller.groups:
    candidate.updateActivePaneIndicator(
      candidate == group and not controller.xSidebarFocused
    )

proc `sidebarFocused=`(controller: KosmoDockController, focused: bool) =
  if controller.isNil or controller.xSidebarFocused == focused:
    return
  controller.xSidebarFocused = focused
  for group in controller.groups:
    group.updateActivePaneIndicator(
      group == controller.activeGroup and not controller.xSidebarFocused
    )

proc showFileExplorer*(frontend: KosmoApplication): bool {.discardable.}
proc revealActiveFile*(frontend: KosmoApplication): bool {.discardable.}
proc showFindInFiles*(frontend: KosmoApplication): bool {.discardable.}
func hasFileBrowser*(frontend: KosmoApplication): bool
proc showQuickOpen*(frontend: KosmoApplication): bool {.discardable.}
proc showGitDiff*(frontend: KosmoApplication, path = ""): bool {.discardable.}
proc newEditorTab*(frontend: KosmoApplication): bool {.discardable.}
proc newTerminal*(frontend: KosmoApplication): bool {.discardable.}
proc showSettings*(frontend: KosmoApplication): bool {.discardable.}
proc openPath*(frontend: KosmoApplication, path: string): bool {.discardable.}
proc show*(frontend: KosmoApplication)
proc close*(frontend: KosmoApplication)
proc activateGroup(controller: KosmoDockController, view: KosmoEditorView)
proc focusPanel(controller: KosmoDockController, panelNumber: int): bool
proc focusGroup(controller: KosmoDockController, group: KosmoEditorGroup): bool
proc preferredPaneResponder(group: KosmoEditorGroup): nimkit.Responder
proc groupForView(
  controller: KosmoDockController, view: KosmoEditorView
): KosmoEditorGroup

proc chooseFile(frontend: KosmoApplication)
proc chooseFile(manager: KosmoWindowManager)
proc chooseProject(manager: KosmoWindowManager)
func isEditingAction(action: string): bool

proc splitCurrentPaneTab(
  controller: KosmoDockController,
  source: KosmoEditorGroup,
  position: nimkit.DockPosition,
): bool

proc performPaneCommand(
  controller: KosmoDockController, source: KosmoEditorGroup, command: KosmoPaneCommand
): bool

func tabIdentifier(id: KosmoBufferId): string =
  KosmoTabIdentifierPrefix & $id

proc parseTabIdentifier(identifier: string, id: var KosmoBufferId): bool =
  if not identifier.startsWith(KosmoTabIdentifierPrefix):
    return
  try:
    id = KosmoBufferId(parseInt(identifier[KosmoTabIdentifierPrefix.len .. ^1]))
    return true
  except ValueError:
    discard

func isMarkdownFilePath*(path: string): bool =
  ## Return whether `path` uses a conventional Markdown-family extension.
  splitFile(path).ext.toLowerAscii() in
    [".md", ".markdown", ".mdown", ".mkd", ".mkdn", ".mdwn", ".mdtxt", ".mdtext"]

func isMarkdownTab(tab: KosmoTab): bool =
  tab.filePath.isSome and tab.filePath.get.isMarkdownFilePath()

func markdownMode*(view: KosmoEditorView, id: KosmoBufferId): KosmoMarkdownMode =
  ## Return the pane-local presentation mode for a Markdown buffer.
  if not view.isNil and id in view.markdownSyntaxBufferIds: kmmSyntax else: kmmPreview

func markdownColorMode*(controls: KosmoMarkdownControls): KosmoMarkdownColorMode =
  ## Return the pane-local Markdown preview color mode.
  if controls.isNil: kmcmLight else: controls.xColorMode

func markdownFontSize*(controls: KosmoMarkdownControls): float32 =
  ## Return the pane-local Markdown preview base font size.
  if controls.isNil: KosmoMarkdownDefaultFontSize else: controls.xFontSize

proc syncMarkdownColorButton(controls: KosmoMarkdownControls) =
  if controls.isNil or controls.colorModeButton.isNil:
    return
  controls.colorModeButton.title =
    if controls.xColorMode == kmcmLight: "Dark" else: "Light"
  controls.colorModeButton.accessibilityLabel =
    if controls.xColorMode == kmcmLight:
      "Use dark Markdown preview"
    else:
      "Use light Markdown preview"
  controls.colorModeButton.toolTip = controls.colorModeButton.accessibilityLabel()

func markdownColorMode(appearance: nimkit.Appearance): KosmoMarkdownColorMode =
  let
    context = nimkit.controlStyle(nimkit.srView)
    fallback = appearance.resolveColor(
      context, nimkit.StyleBackgroundColor, nimkit.color(1.0, 1.0, 1.0, 1.0)
    )
    background = appearance
      .resolveFill(context, nimkit.fill(fallback), nimkit.StyleBackgroundFill)
      .centerColor()
    luminance =
      0.2126'f32 * background.r + 0.7152'f32 * background.g + 0.0722'f32 * background.b
  if luminance < 0.5'f32: kmcmDark else: kmcmLight

proc syncMarkdownColorMode(
    controls: KosmoMarkdownControls, appearance: nimkit.Appearance
) =
  if controls.isNil:
    return
  let mode = appearance.markdownColorMode()
  if controls.xColorMode == controls.xThemeColorMode:
    controls.xColorMode = mode
  controls.xThemeColorMode = mode
  controls.syncMarkdownColorButton()

proc markdownPresentationStyle*(controls: KosmoMarkdownControls): nimkit.MarkdownStyle =
  result = nimkit.initMarkdownStyle()
  if not controls.isNil and controls.xColorMode == kmcmDark:
    result.backgroundColor = nimkit.color(0.055, 0.065, 0.085, 1.0)
    result.textColor = nimkit.color(0.84, 0.86, 0.90, 1.0)
    result.headingColor = nimkit.color(0.96, 0.97, 0.99, 1.0)
    result.strongColor = nimkit.color(0.96, 0.97, 0.99, 1.0)
    result.emphasisColor = nimkit.color(0.80, 0.65, 0.96, 1.0)
    result.linkColor = nimkit.color(0.40, 0.69, 0.98, 1.0)
    result.codeColor = nimkit.color(0.96, 0.53, 0.64, 1.0)
    result.quoteColor = nimkit.color(0.67, 0.72, 0.82, 1.0)
    result.mutedColor = nimkit.color(0.56, 0.61, 0.70, 1.0)
    result.ruleColor = nimkit.color(0.35, 0.40, 0.49, 1.0)
    result.codeBlockStyle.backgroundColor = nimkit.color(0.08, 0.10, 0.14, 1.0)
    result.codeBlockStyle.outlineColor = nimkit.color(0.28, 0.33, 0.42, 1.0)
    for tokenClass in nimkit.SyntaxTokenClass:
      result.syntaxTokenColors[tokenClass] = result.codeColor
    result.syntaxTokenColors[nimkit.stcKeyword] = nimkit.color(0.80, 0.65, 0.96, 1.0)
    result.syntaxTokenColors[nimkit.stcIdentifier] = nimkit.color(0.54, 0.71, 0.98, 1.0)
    result.syntaxTokenColors[nimkit.stcString] = nimkit.color(0.65, 0.89, 0.63, 1.0)
    result.syntaxTokenColors[nimkit.stcNumber] = nimkit.color(0.98, 0.70, 0.53, 1.0)
    result.syntaxTokenColors[nimkit.stcComment] = result.mutedColor
    result.syntaxTokenColors[nimkit.stcOperator] = nimkit.color(0.54, 0.71, 0.98, 1.0)
    result.syntaxTokenColors[nimkit.stcPunctuation] =
      nimkit.color(0.58, 0.60, 0.70, 1.0)
    result.syntaxTokenColors[nimkit.stcPreprocessor] =
      nimkit.color(0.80, 0.65, 0.96, 1.0)

  let
    fontSize = if controls.isNil: KosmoMarkdownDefaultFontSize else: controls.xFontSize
    scale = fontSize / KosmoMarkdownDefaultFontSize
  result.bodyFontSize = fontSize
  if not controls.isNil:
    let
      appearance = controls.effectiveAppearance()
      interfaceFaces = appearance.fontFaces(nimkit.frUI)
      monospaceFaces = appearance.fontFaces(nimkit.frMonospace)
    result.bodyFontName = appearance.fontName(nimkit.frUI)
    result.bodyFontFace = interfaceFaces.regular
    result.emphasisFontName = result.bodyFontName
    result.emphasisFontFace = interfaceFaces.italic
    result.strongFontName = result.bodyFontName
    result.strongFontFace = interfaceFaces.bold
    result.codeFontName = appearance.fontName(nimkit.frMonospace)
    result.codeFontFace = monospaceFaces.regular
    result.emphasisCodeFontName = result.codeFontName
    result.emphasisCodeFontFace =
      if monospaceFaces.italic.file.path.len > 0:
        monospaceFaces.italic
      else:
        monospaceFaces.regular
    result.strongCodeFontName = result.codeFontName
    result.strongCodeFontFace =
      if monospaceFaces.bold.file.path.len > 0:
        monospaceFaces.bold
      else:
        monospaceFaces.regular
  for size in result.headingFontSizes.mitems:
    size *= scale

proc syncMarkdownControls(pane: KosmoEditorPane, visible: bool, mode = kmmPreview) =
  if pane.isNil or pane.markdownControls.isNil:
    return
  let controls = pane.markdownControls
  controls.hidden = not visible
  if not visible:
    return
  controls.modeButton.title = if mode == kmmPreview: "</>" else: "MD"
  controls.modeButton.accessibilityLabel =
    if mode == kmmPreview: "Edit Markdown source" else: "Preview Markdown"
  controls.modeButton.toolTip = controls.modeButton.accessibilityLabel()
  controls.syncMarkdownColorButton()
  controls.decreaseFontButton.enabled =
    controls.xFontSize > KosmoMarkdownMinimumFontSize
  controls.increaseFontButton.enabled =
    controls.xFontSize < KosmoMarkdownMaximumFontSize

proc forgetMarkdownMode(view: KosmoEditorView, id: KosmoBufferId) =
  let index = view.markdownSyntaxBufferIds.find(id)
  if index >= 0:
    view.markdownSyntaxBufferIds.delete(index)

proc documentIndex(group: KosmoEditorGroup, identifier: string): int =
  if group.isNil:
    return -1
  for index, document in group.documents:
    if document.identifier == identifier:
      return index
  -1

proc documentForIdentifier(
    group: KosmoEditorGroup, identifier: string
): KosmoPaneDocument =
  let index = group.documentIndex(identifier)
  if index >= 0:
    result = group.documents[index]

proc markdownViewForBuffer(pane: KosmoEditorPane, id: KosmoBufferId): KosmoMarkdownView

proc removeMarkdownPreview(pane: KosmoEditorPane, id: KosmoBufferId) =
  if pane.isNil:
    return
  for index, preview in pane.markdownPreviews:
    if preview.bufferId == id:
      preview.view.markdown = ""
      pane.markdownPreviews.delete(index)
      return

proc pruneMarkdownPreviews(pane: KosmoEditorPane, tabs: openArray[KosmoTab]) =
  if pane.isNil:
    return
  var index = pane.markdownPreviews.high
  while index >= 0:
    var retained = false
    for tab in tabs:
      if tab.id == pane.markdownPreviews[index].bufferId:
        retained = true
        break
    if not retained:
      pane.removeMarkdownPreview(pane.markdownPreviews[index].bufferId)
    dec index

proc clearMarkdownPreviews(pane: KosmoEditorPane) =
  if pane.isNil:
    return
  for preview in pane.markdownPreviews:
    preview.view.markdown = ""
  pane.markdownPreviews.setLen(0)

func documents*(group: KosmoEditorGroup): lent seq[KosmoPaneDocument] =
  ## Return the non-Moe documents currently owned by this pane group.
  group.documents

proc setContentView(pane: KosmoEditorPane, contentView: nimkit.View)

proc selectEditorContent(view: KosmoEditorView, id: KosmoBufferId) =
  if view.dockGroup.isNil:
    return
  let group = view.dockGroup[]
  group.selectedTabIdentifier = id.tabIdentifier
  group.pane.setContentView(view)

proc resolvedEditorFilePath(path, workingDirectory: string): string =
  let basePath =
    if workingDirectory.len > 0:
      absolutePath(workingDirectory)
    else:
      getCurrentDir()
  normalizedPath(absolutePath(path, basePath))

proc statusText(
    status: KosmoStatus, tabs: openArray[KosmoTab], workingDirectory: string
): string =
  var parts: seq[string]
  var activeFilePath: Option[string]
  if status.modeLabel.len > 0:
    parts.add status.modeLabel
  for tab in tabs:
    if tab.active:
      parts.add tab.title
      activeFilePath = tab.filePath
      break
  if status.message.len > 0:
    parts.add status.message
  if status.gitBranch.len > 0:
    var git = "Git: " & status.gitBranch
    if status.gitAdded != 0:
      git.add " +" & $status.gitAdded
    if status.gitModified != 0:
      git.add " ~" & $status.gitModified
    if status.gitDeleted != 0:
      git.add " -" & $status.gitDeleted
    parts.add git
  if activeFilePath.isSome:
    parts.add resolvedEditorFilePath(activeFilePath.get, workingDirectory)
  parts.join("  •  ")

proc visibleTabs(view: KosmoEditorView, tabs: openArray[KosmoTab]): seq[KosmoTab] =
  if not view.usesBufferSubset:
    return @tabs
  var visibleIds: seq[KosmoBufferId]
  for id in view.bufferIds:
    for tab in tabs:
      if tab.id == id:
        result.add tab
        visibleIds.add id
        break
  view.bufferIds = visibleIds

proc syncEditorTabOrder(view: KosmoEditorView) =
  let tabs = view.editor.tabs()
  if tabs.len != view.bufferIds.len:
    var
      desiredIds = newSeqOfCap[KosmoBufferId](tabs.len)
      groupIndex = 0
    for tab in tabs:
      if tab.id in view.bufferIds:
        desiredIds.add view.bufferIds[groupIndex]
        inc groupIndex
      else:
        desiredIds.add tab.id
    for index, id in desiredIds:
      discard view.editor.moveTab(id, index.Natural)
  else:
    for index, id in view.bufferIds:
      discard view.editor.moveTab(id, index.Natural)

proc viewStateIndex(view: KosmoEditorView, id: KosmoBufferId): int =
  for index, state in view.viewStates:
    if state.bufferId == some(id):
      return index
  -1

proc saveViewState(view: KosmoEditorView) =
  if not view.usesBufferSubset or view.selectedBufferId.isNone:
    return
  let state = view.editor.captureViewState()
  if state.bufferId != view.selectedBufferId:
    return
  let index = view.viewStateIndex(view.selectedBufferId.get)
  if index >= 0:
    view.viewStates[index] = state
  else:
    view.viewStates.add state

proc removeViewState(view: KosmoEditorView, id: KosmoBufferId) =
  let index = view.viewStateIndex(id)
  if index >= 0:
    view.viewStates.delete(index)

proc closeTab(view: KosmoEditorView, id: KosmoBufferId): KosmoTabCloseResult =
  result = view.editor.closeTab(id)
  if result.closed:
    view.forgetMarkdownMode(id)
  if result.closed and view.usesBufferSubset:
    let bufferIndex = view.bufferIds.find(id)
    if bufferIndex >= 0:
      view.bufferIds.delete(bufferIndex)
    view.removeViewState(id)
    view.selectedBufferId = none(KosmoBufferId)
  elif not result.closed and not view.statusLabel.isNil:
    view.statusLabel.text = result.message

proc bufferIsVisibleOutside(
    controller: KosmoDockController, source: KosmoEditorGroup, id: KosmoBufferId
): bool =
  for group in controller.groups:
    if group != source and id in group.editorView.bufferIds:
      return true

proc selectVisibleBuffer(view: KosmoEditorView, tabs: openArray[KosmoTab]) =
  if not view.usesBufferSubset:
    return
  view.saveViewState()
  var selectedIsVisible = false
  if view.selectedBufferId.isSome:
    for tab in tabs:
      if tab.id == view.selectedBufferId.get:
        selectedIsVisible = true
        break
  if not selectedIsVisible:
    view.selectedBufferId =
      if tabs.len > 0:
        some(tabs[^1].id)
      else:
        none(KosmoBufferId)
  if view.selectedBufferId.isSome:
    let index = view.viewStateIndex(view.selectedBufferId.get)
    if index >= 0:
      discard view.editor.restoreViewState(view.viewStates[index])
    else:
      discard view.editor.selectTab(view.selectedBufferId.get)

proc adoptActiveBuffer(view: KosmoEditorView) =
  if not view.usesBufferSubset:
    return
  for tab in view.editor.tabs():
    if tab.active:
      if tab.id notin view.bufferIds:
        view.bufferIds.add tab.id
      view.selectedBufferId = some(tab.id)
      view.selectEditorContent(tab.id)
      view.lastTabs.setLen(0)
      return

proc syncTabs(view: KosmoEditorView, tabs: seq[KosmoTab]) =
  let visibleTabs = view.visibleTabs(tabs)
  if view.documentTabs.isNil:
    return
  var editorModels: seq[nimkit.DocumentTabModel]
  for tab in visibleTabs:
    let styleClasses =
      if tab.temporary:
        @[KosmoPreviewTabStyleClass]
      else:
        @[]
    editorModels.add nimkit.initDocumentTabModel(
      identifier = tab.id.tabIdentifier,
      title = tab.title,
      closeable = true,
      modified = tab.modified,
      styleClasses = styleClasses,
      tooltip = tab.filePath.get(tab.title),
    )
  var
    models = editorModels
    selectedIdentifier = ""
  if not view.dockGroup.isNil:
    let group = view.dockGroup[]
    var currentIdentifiers = newSeqOfCap[string](editorModels.len + group.documents.len)
    for model in editorModels:
      currentIdentifiers.add model.identifier
    for document in group.documents:
      currentIdentifiers.add document.identifier

    var reconciledOrder = newSeqOfCap[string](currentIdentifiers.len)
    for identifier in group.tabOrder:
      if identifier in currentIdentifiers and identifier notin reconciledOrder:
        reconciledOrder.add identifier
    for identifier in currentIdentifiers:
      if identifier notin reconciledOrder:
        reconciledOrder.add identifier
    group.tabOrder = reconciledOrder

    models.setLen(0)
    for identifier in group.tabOrder:
      var found = false
      for model in editorModels:
        if model.identifier == identifier:
          models.add model
          found = true
          break
      if not found:
        let document = group.documentForIdentifier(identifier)
        if not document.isNil:
          models.add document.documentTabModel()
    if group.selectedTabIdentifier in currentIdentifiers:
      selectedIdentifier = group.selectedTabIdentifier
    elif currentIdentifiers.len > 0:
      selectedIdentifier = currentIdentifiers[^1]
      group.selectedTabIdentifier = selectedIdentifier
  elif view.usesBufferSubset and view.selectedBufferId.isSome:
    selectedIdentifier = view.selectedBufferId.get.tabIdentifier
  else:
    for tab in visibleTabs:
      if tab.active:
        selectedIdentifier = tab.id.tabIdentifier
        break

  if visibleTabs == view.lastTabs and models == view.documentTabs.documentTabModels() and
      selectedIdentifier == view.documentTabs.selectedDocumentTabIdentifier:
    return
  view.syncingTabs = true
  defer:
    view.syncingTabs = false
  view.documentTabs.documentTabModels = models
  view.documentTabs.selectedDocumentTabIdentifier = selectedIdentifier
  view.lastTabs = visibleTabs

proc isActiveEditorGroup(view: KosmoEditorView): bool =
  if view.tabsDelegate.isNil or view.tabsDelegate.dockController.isNil:
    return true
  let controller = view.tabsDelegate.dockController[]
  controller.activeGroup.isNil or controller.activeGroup.editorView == view

proc syncCommandBar(view: KosmoEditorView, command: KosmoCommandLine) =
  let bar = view.commandBar
  if bar.isNil:
    return
  let visible = command.visible and view.isActiveEditorGroup()
  bar.hidden = not visible
  if not visible:
    return

  var runes: seq[Rune]
  for rune in command.text.runes:
    runes.add rune
  let
    cursor = command.cursor.clamp(0, runes.len)
    columns = max(runes.len, cursor + 1)
    cursorColor = bar.cursorColor()
  var cells = newSeq[nimkit.MonoTextCell](columns)
  for column in 0 ..< columns:
    let rune =
      if column < runes.len:
        runes[column]
      else:
        Rune(' ')
    cells[column] = nimkit.initMonoTextCell(
      rune, backgroundColor = cursorColor, hasBackgroundColor = column == cursor
    )
  bar.replaceGrid(1, columns, cells)

  let metrics = bar.monoTextMetrics()
  if metrics.cellWidth > 0.0'f32:
    let visibleColumns = max(int(floor(bar.bounds().size.width / metrics.cellWidth)), 1)
    let firstColumn = max(cursor - visibleColumns + 1, 0)
    bar.gridOffset = nimkit.initPoint(-firstColumn.float32 * metrics.cellWidth, 0.0'f32)

proc syncChrome(view: KosmoEditorView) =
  let tabs = view.visibleTabs(view.editor.tabs())
  view.syncTabs(tabs)
  if not view.statusLabel.isNil and view.isActiveEditorGroup():
    let text = view.editor.status().statusText(tabs, view.editor.workingDirectory())
    if view.statusLabel.text != text:
      view.statusLabel.text = text
  let command = view.editor.commandLine()
  view.syncCommandBar(command)
  let cursor = view.editor.cursor()
  view.setCursorPosition(cursor.row, cursor.column)
  view.cursorVisible = cursor.visible and not command.visible

func kosmoPaneOutlineColor(base: nimkit.Appearance): nimkit.Color =
  let accentColor = base.resolveColor(
    nimkit.controlStyle(nimkit.srDocumentTab),
    nimkit.StyleMarkColor,
    nimkit.color(0.20, 0.45, 0.92, 1.0),
  )
  nimkit.color(
    accentColor.r, accentColor.g, accentColor.b, accentColor.a * KosmoPaneOutlineOpacity
  )

proc installKosmoPaneIndicatorStyle(
    appearance: var nimkit.Appearance, base: nimkit.Appearance
) =
  let selector = nimkit.initStyleSelector(nimkit.srBox, id = KosmoPaneIndicatorStyleId)
  appearance.setStyle(selector, nimkit.StyleBorderColor, base.kosmoPaneOutlineColor())
  appearance.setStyle(selector, nimkit.StyleBorderWidth, KosmoPaneOutlineWidth)
  appearance.setStyle(selector, nimkit.StyleCornerRadius, 0.0'f32)

proc installKosmoMarkdownControlsStyle(appearance: var nimkit.Appearance) =
  let
    controlsSelector =
      nimkit.initStyleSelector(nimkit.srBox, id = KosmoMarkdownControlsStyleId)
    buttonSelector = nimkit.initStyleSelector(
      nimkit.srButton, classes = @[KosmoMarkdownControlButtonStyleClass]
    )
  appearance.setStyle(controlsSelector, nimkit.StylePadding, nimkit.insets(4.0'f32))
  appearance.setStyle(controlsSelector, nimkit.StyleBorderWidth, 0.0'f32)
  appearance.setStyle(controlsSelector, nimkit.StyleCornerRadius, 0.0'f32)
  appearance.setStyle(
    controlsSelector, nimkit.StyleBoxShadows, newSeq[nimkit.BoxShadow]()
  )
  appearance.setStyle(
    buttonSelector, nimkit.StyleTextInsets, nimkit.insets(0.0'f32, 2.0'f32)
  )

proc refresh*(view: KosmoEditorView)

proc stopMatterHighlightRefresh(view: KosmoEditorView) =
  if not view.isNil:
    view.matterRefreshActive = false
    view.matterRefreshPending = false

proc refreshMatterHighlighting(view: KosmoEditorView) {.slot.} =
  ## Completion can arrive after the last input/layout refresh. Coalesce a
  ## retained-grid update onto the next application frame without re-entering
  ## rendering from inside Sigils result delivery.
  if not view.matterRefreshActive or view.matterRefreshPending:
    return
  view.matterRefreshPending = true
  # The main-thread queue owns this reference until the callback runs. Sigils'
  # WeakRef is intentionally non-retaining but also non-invalidating, so it is
  # not safe for work that can outlive a detached pane.
  let owner = view
  scheduleMainThreadWork do() -> bool:
    owner.matterRefreshPending = false
    if owner.matterRefreshActive:
      owner.refresh()

proc applyKosmoEditorStyle(view: KosmoEditorView, base: nimkit.Appearance) =
  var appearance = base
  let
    selector = nimkit.initStyleSelector(nimkit.srMonoTextView, id = KosmoEditorStyleId)
    previewTabSelector = nimkit.initStyleSelector(
      nimkit.srDocumentTab, classes = @[KosmoPreviewTabStyleClass]
    )
    inactiveTabSelector = nimkit.initStyleSelector(
      nimkit.srDocumentTab,
      {nimkit.ssSelected},
      classes = @[KosmoInactivePaneStyleClass],
    )
    tabContext = nimkit.controlStyle(nimkit.srDocumentTab)
    cursorColor =
      base.resolveMonoTextStyle(nimkit.controlStyle(nimkit.srMonoTextView)).cursorColor
    accentColor = base.resolveColor(
      tabContext, nimkit.StyleMarkColor, nimkit.color(0.20, 0.45, 0.92, 1.0)
    )
    normalTabFill =
      base.resolveFill(tabContext, nimkit.fill(nimkit.color(0.16, 0.18, 0.22, 1.0)))
    normalTabTextColor = base.resolveColor(
      tabContext, nimkit.StyleTextColor, nimkit.color(0.72, 0.74, 0.80, 1.0)
    )
    inactiveAccentColor = nimkit.color(
      accentColor.r,
      accentColor.g,
      accentColor.b,
      accentColor.a * KosmoInactiveTabAccentOpacity,
    )
    inactiveTabTextColor = nimkit.color(
      normalTabTextColor.r,
      normalTabTextColor.g,
      normalTabTextColor.b,
      normalTabTextColor.a * KosmoInactiveTabTextOpacity,
    )
  appearance.setStyle(
    selector,
    nimkit.StyleCursorColor,
    nimkit.color(cursorColor.r, cursorColor.g, cursorColor.b, KosmoCursorOpacity),
  )
  appearance.setStyle(selector, nimkit.StyleFocusRingWidth, 0.0'f32)
  appearance.setStyle(selector, nimkit.StyleFocusRingInset, 0.0'f32)
  appearance.setStyle(selector, nimkit.StyleCornerRadius, 0.0'f32)
  appearance.setStyle(selector, nimkit.StyleCornerRadiusTopLeft, 0.0'f32)
  appearance.setStyle(selector, nimkit.StyleCornerRadiusTopRight, 0.0'f32)
  appearance.setStyle(selector, nimkit.StyleCornerRadiusBottomLeft, 0.0'f32)
  appearance.setStyle(selector, nimkit.StyleCornerRadiusBottomRight, 0.0'f32)
  appearance.setStyle(
    previewTabSelector, nimkit.StyleFontSlant, nimkit.styleKeyword(nimkit.fsItalic)
  )
  appearance.setStyle(inactiveTabSelector, nimkit.StyleFill, normalTabFill)
  appearance.setStyle(inactiveTabSelector, nimkit.StyleTextColor, inactiveTabTextColor)
  appearance.setStyle(
    inactiveTabSelector,
    nimkit.StyleSelectionIndicatorFill,
    nimkit.fill(inactiveAccentColor),
  )
  appearance.installKosmoPaneIndicatorStyle(base)
  appearance.installKosmoMarkdownControlsStyle()
  view.styleId = KosmoEditorStyleId
  view.appearance = appearance
  if not view.documentTabs.isNil:
    view.documentTabs.appearance = appearance
  if not view.commandBar.isNil:
    view.commandBar.appearance = appearance
  if not view.dockGroup.isNil:
    let pane = view.dockGroup[].pane
    if not pane.activeIndicator.isNil:
      pane.activeIndicator.appearance = appearance
    if not pane.markdownControls.isNil:
      pane.markdownControls.syncMarkdownColorMode(base)
      pane.markdownControls.appearance = appearance

protocol KosmoEditorAppearanceObserver of nimkit.WindowAppearanceEvents:
  proc didChangeEffectiveAppearance(
      handler: KosmoEditorTabsHandler, appearance: nimkit.Appearance
  ) {.slot.} =
    if not handler.editorView.isNil:
      handler.editorView[].applyKosmoEditorStyle(appearance)
      handler.editorView[].refresh()

protocol KosmoEditorFocusObserver of nimkit.WindowFocusEvents:
  proc didResignKeyWindow(handler: KosmoEditorTabsHandler) {.slot.} =
    if not handler.editorView.isNil:
      handler.editorView[].pendingPanePrefix = false

  proc didChangeFirstResponder(
      handler: KosmoEditorTabsHandler, previous: nimkit.Responder
  ) {.slot.} =
    discard previous
    if handler.editorView.isNil or handler.dockController.isNil:
      return
    let
      view = handler.editorView[]
      controller = handler.dockController[]
    view.pendingPanePrefix = false
    if view.dockGroup.isNil:
      return
    let group = view.dockGroup[]
    var responder = group.window.firstResponder()
    while not responder.isNil:
      if responder == nimkit.Responder(group.pane):
        controller.activateGroup(view)
        return
      responder = responder.nextResponder()

proc stopObservingWindow(handler: KosmoEditorTabsHandler) =
  if handler.isNil or handler.appearanceWindow.isNil:
    return
  handler.unobserveProtocol(handler.appearanceWindow[], nimkit.WindowAppearanceEvents)
  handler.unobserveProtocol(handler.appearanceWindow[], nimkit.WindowFocusEvents)
  handler.appearanceWindow = default(WeakRef[nimkit.Window])

proc observeAppearance(handler: KosmoEditorTabsHandler, window: nimkit.Window) =
  handler.stopObservingWindow()
  if window.isNil:
    return
  handler.appearanceWindow = window.unsafeWeakRef()
  handler.observeProtocol(window, nimkit.WindowAppearanceEvents)
  handler.observeProtocol(window, nimkit.WindowFocusEvents)

proc syncSelectedEditorContent(
    view: KosmoEditorView, tabs: openArray[KosmoTab]
): KosmoEditorContentKind =
  if view.dockGroup.isNil:
    return keckSyntax
  let group = view.dockGroup[]
  group.pane.pruneMarkdownPreviews(tabs)
  var selectedId: KosmoBufferId
  if not group.selectedTabIdentifier.parseTabIdentifier(selectedId):
    group.pane.syncMarkdownControls(false)
    let document = group.documentForIdentifier(group.selectedTabIdentifier)
    if not document.isNil and document.contentView of KosmoGitDiffPanel:
      KosmoGitDiffPanel(document.contentView).markdownStyle =
        group.pane.markdownControls.markdownPresentationStyle()
    return keckOther
  for tab in tabs:
    if tab.id != selectedId:
      continue
    if not tab.isMarkdownTab:
      group.pane.syncMarkdownControls(false)
      group.pane.setContentView(view)
      return keckSyntax
    let mode = view.markdownMode(selectedId)
    group.pane.syncMarkdownControls(true, mode)
    if mode == kmmPreview:
      let source = view.editor.bufferText(selectedId)
      if source.isNone:
        group.pane.setContentView(view)
        return keckSyntax
      let markdownView = group.pane.markdownViewForBuffer(selectedId)
      group.pane.markdownView = markdownView
      markdownView.imageBasePath = tab.filePath.get.parentDir
      markdownView.markdownStyle =
        group.pane.markdownControls.markdownPresentationStyle()
      markdownView.markdown = source.get
      group.pane.setContentView(markdownView)
      return keckMarkdownPreview
    group.pane.setContentView(view)
    return keckSyntax
  group.pane.syncMarkdownControls(false)
  keckOther

proc refresh*(view: KosmoEditorView) =
  ## Render the current editor state into the synchronous cell-grid view.
  if (view.editor.completionPopupVisible() or view.editor.commandLine().visible) and
      not view.isActiveEditorGroup():
    return
  let tabs = view.visibleTabs(view.editor.tabs())
  view.selectVisibleBuffer(tabs)
  case view.syncSelectedEditorContent(tabs)
  of keckMarkdownPreview:
    view.syncChrome()
    view.cursorVisible = false
    if not view.commandBar.isNil:
      view.commandBar.hidden = true
    return
  of keckOther:
    view.syncChrome()
    return
  of keckSyntax:
    discard
  let metrics = view.monoTextMetrics()
  if metrics.cellWidth <= 0.0'f32 or metrics.lineHeight <= 0.0'f32:
    return
  let
    bounds = view.bounds()
    columns = max(int(ceil(bounds.size.width / metrics.cellWidth)), 1)
    rows = max(
      int(ceil(bounds.size.height / metrics.lineHeight)) + KosmoGridOverscanRows +
        KosmoMoeBottomAreaRows,
      1,
    )
  if view.renderBuffer.width != columns or view.renderBuffer.height != rows:
    view.renderBuffer.resize(columns.Natural, rows.Natural)
  view.editor.render(view.renderBuffer, view.editor.captureViewState())
  view.saveViewState()
  var cells = newSeq[nimkit.MonoTextCell](rows * columns)
  for row in 0 ..< rows:
    for column in 0 ..< columns:
      cells[row * columns + column] = view.renderBuffer.cell(column, row).toMonoTextCell
  view.replaceGrid(rows, columns, cells)
  view.gridOffset =
    nimkit.initPoint(0.0'f32, -view.scrollOffsetRows * metrics.lineHeight)
  view.syncChrome()

proc toggleMarkdownMode(view: KosmoEditorView, id: KosmoBufferId): bool =
  for tab in view.editor.tabs():
    if tab.id != id or not tab.isMarkdownTab:
      continue
    if view.markdownMode(id) == kmmPreview:
      view.markdownSyntaxBufferIds.add id
    else:
      view.forgetMarkdownMode(id)
    view.lastTabs.setLen(0)
    view.refresh()
    return true

proc openFile*(view: KosmoEditorView, path: string): bool {.discardable.} =
  ## Load a file selected by the frontend and refresh the cell grid.
  view.saveViewState()
  let outcome = view.editor.openFile(path)
  if outcome.loaded:
    view.adoptActiveBuffer()
    view.refresh()
    return true
  if not view.statusLabel.isNil:
    view.statusLabel.text = outcome.message

proc previewFile*(view: KosmoEditorView, path: string): bool {.discardable.} =
  ## Load `path` as the replaceable file-tree preview and refresh the grid.
  view.saveViewState()
  let outcome = view.editor.previewFile(path)
  if outcome.loaded:
    view.adoptActiveBuffer()
    view.refresh()
    return true
  if not view.statusLabel.isNil:
    view.statusLabel.text = outcome.message

proc bufferColumn(match: nimkit.FileSearchMatch): int =
  let byteColumn = clamp(match.column - 1, 0, match.lineText.len)
  if byteColumn > 0:
    result = match.lineText[0 ..< byteColumn].runeLen

proc openSearchResult(
    view: KosmoEditorView,
    match: nimkit.FileSearchMatch,
    disposition: FileTreeOpenDisposition,
): bool =
  view.saveViewState()
  let outcome =
    case disposition
    of fodTemporary:
      view.editor.previewFile(match.path)
    of fodPermanent:
      view.editor.openFile(match.path)
  if outcome.loaded:
    view.adoptActiveBuffer()
    discard view.editor.revealLocation(
      max(match.line - 1, 0), match.bufferColumn(), centered = true
    )
    view.refresh()
    return true
  if not view.statusLabel.isNil:
    view.statusLabel.text = outcome.message

proc scrollBy*(
    view: KosmoEditorView,
    deltaY: float32,
    row = 0,
    column = 0,
    modifiers: set[nimkit.KeyModifier] = {},
): ScrollOutcome =
  ## Translate fractional wheel input and accelerate Control-modified scrolling.
  view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
  let multiplier =
    if nimkit.kmControl in modifiers: KosmoControlScrollMultiplier else: 1.0'f32
  view.scrollOffsetRows -= deltaY * multiplier
  let rows = int(floor(view.scrollOffsetRows))
  if rows == 0:
    result.handled = true
    let metrics = view.monoTextMetrics()
    view.gridOffset =
      nimkit.initPoint(0.0'f32, -view.scrollOffsetRows * metrics.lineHeight)
    return
  view.scrollOffsetRows -= rows.float32
  result = view.editor.handleScrollInput(
    initScrollInput(row, column, rows, modifiers.toMoeModifiers)
  )
  if result.appliedRows != rows:
    view.scrollOffsetRows = 0.0'f32
  view.refresh()

proc closeCurrentTab(controller: KosmoDockController, view: KosmoEditorView)
proc finishTabClose(controller: KosmoDockController, view: KosmoEditorView)
proc saveCurrentTab(
  controller: KosmoDockController,
  view: KosmoEditorView,
  savePanel: nimkit.SavePanel = nil,
): bool {.discardable.}

proc selectRelativeTab(
  controller: KosmoDockController, view: KosmoEditorView, offset: int
)

proc activatePaneTab(
  controller: KosmoDockController,
  group: KosmoEditorGroup,
  identifier: string,
  focus = true,
)

proc closeCurrentPaneTab(controller: KosmoDockController, group: KosmoEditorGroup)

proc saveCurrentPaneTab(
  controller: KosmoDockController,
  group: KosmoEditorGroup,
  savePanel: nimkit.SavePanel = nil,
): bool {.discardable.}

proc removeBuffer(group: KosmoEditorGroup, id: KosmoBufferId)

proc openPaneDocument(
  controller: KosmoDockController,
  group: KosmoEditorGroup,
  document: KosmoPaneDocument,
  insertAfterSelected = false,
): bool

proc selectRelativePaneTab(
  controller: KosmoDockController, group: KosmoEditorGroup, offset: int
)

proc updateDockTarget(
  controller: KosmoDockController, tabs: nimkit.DocumentTabs, location: nimkit.Point
)

proc finishDockDrag(
  controller: KosmoDockController,
  tabs: nimkit.DocumentTabs,
  item: nimkit.DocumentTabItem,
  location: nimkit.Point,
)

proc sendKeyDownToMoe(view: KosmoEditorView, keyEvent: nimkit.KeyEvent): bool =
  var keyOutcome: KosmoKeyOutcome
  if keyEvent.key == nimkit.keyEnter:
    keyOutcome = view.editor.handleKeyOutcome("Enter")
  elif keyEvent.text.len > 0 and keyEvent.modifiers - {nimkit.kmShift} == {}:
    discard view.editor.handleTextInput(keyEvent.text)
  elif keyEvent.awaitsCommittedText():
    return false
  else:
    let notation = keyEvent.keyNotation()
    if notation.len > 0:
      keyOutcome = view.editor.handleKeyOutcome(notation)
  if keyOutcome.closeTabRequested and not view.tabsDelegate.dockController.isNil:
    view.tabsDelegate.dockController[].closeCurrentTab(view)
    return true
  view.refresh()
  true

proc paneCommand(event: nimkit.KeyEvent): KosmoPaneCommand =
  let modifiers = event.modifiers
  if modifiers - {nimkit.kmControl, nimkit.kmShift} != {}:
    return
  if event.key >= nimkit.keyA and event.key <= nimkit.keyZ:
    let letter = char(ord('a') + ord(event.key) - ord(nimkit.keyA))
    case letter
    of 's':
      if nimkit.kmShift notin modifiers:
        return kpcSplitBelow
    of 'v':
      if nimkit.kmShift notin modifiers:
        return kpcSplitRight
    of 'n':
      if nimkit.kmShift notin modifiers:
        return kpcNewBelow
    of 'w':
      if nimkit.kmShift notin modifiers:
        return kpcFocusNext
    of 'h':
      if nimkit.kmShift notin modifiers:
        return kpcFocusLeft
    of 'j':
      if nimkit.kmShift notin modifiers:
        return kpcFocusBelow
    of 'k':
      if nimkit.kmShift notin modifiers:
        return kpcFocusAbove
    of 'l':
      if nimkit.kmShift notin modifiers:
        return kpcFocusRight
    of 'c':
      if nimkit.kmShift notin modifiers:
        return kpcClose
    else:
      discard
    return
  case event.key
  of nimkit.keyEqual:
    if nimkit.kmShift in modifiers or event.text == "+": kpcGrowHeight else: kpcEqualize
  of nimkit.keyMinus:
    kpcShrinkHeight
  of nimkit.keyComma:
    if nimkit.kmShift in modifiers or event.text == "<": kpcShrinkWidth else: kpcNone
  of nimkit.keyDot:
    if nimkit.kmShift in modifiers or event.text == ">": kpcGrowWidth else: kpcNone
  else:
    kpcNone

proc handlePendingPaneKey(view: KosmoEditorView, event: nimkit.KeyEvent): bool =
  if not view.pendingPanePrefix:
    return false
  view.pendingPanePrefix = false
  if event.key == nimkit.keyEscape:
    return true
  let command = event.paneCommand()
  if command != kpcNone and not view.tabsDelegate.dockController.isNil and
      not view.dockGroup.isNil:
    discard
      view.tabsDelegate.dockController[].performPaneCommand(view.dockGroup[], command)
    return true

  # Preserve Moe mappings for continuations Kosmo does not claim.
  discard view.editor.handleKeyOutcome("C-w")
  discard view.sendKeyDownToMoe(event)
  true

proc handlePaneKey(editorView: KosmoEditorView, event: nimkit.KeyEvent): bool =
  ## Route scoped pane commands from focused non-editor pane content.
  if editorView.isNil:
    return
  if editorView.tabsDelegate.isNil or editorView.tabsDelegate.dockController.isNil or
      editorView.dockGroup.isNil:
    return
  if editorView.pendingPanePrefix:
    editorView.pendingPanePrefix = false
    if event.key == nimkit.keyEscape:
      return true
    let command = event.paneCommand()
    if command != kpcNone:
      discard editorView.tabsDelegate.dockController[].performPaneCommand(
        editorView.dockGroup[], command
      )
      return true
    return false
  if event.key == nimkit.keyForText("w") and event.modifiers == {nimkit.kmControl}:
    editorView.pendingPanePrefix = true
    return true

proc handleMarkdownPaneKey(view: KosmoMarkdownView, event: nimkit.KeyEvent): bool =
  ## Route scoped pane commands from a focused Markdown preview.
  if view.isNil or view.editorView.isNil:
    return
  view.editorView[].handlePaneKey(event)

proc handleRawEvent(view: KosmoEditorView, event: nimkit.MonoTextRawEvent): bool =
  if event.kind == nimkit.mtreMouseDown and not view.tabsDelegate.dockController.isNil:
    view.tabsDelegate.dockController[].activateGroup(view)
  view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
  case event.kind
  of nimkit.mtreMouseDown, nimkit.mtreMouseDragged, nimkit.mtreMouseUp:
    if event.kind == nimkit.mtreMouseDown:
      let window = view.window()
      if window of nimkit.Window:
        discard nimkit.Window(window).makeFirstResponder(view)
    let action =
      case event.kind
      of nimkit.mtreMouseDown: paPress
      of nimkit.mtreMouseDragged: paDrag
      of nimkit.mtreMouseUp: paRelease
      else: paMove
    discard view.editor.handlePointerInput(
      initPointerInput(
        event.row,
        event.column,
        event.mouseEvent.button.toPointerButton,
        action,
        max(event.mouseEvent.clickCount, 1).Natural,
        event.mouseEvent.modifiers.toMoeModifiers,
      )
    )
    view.refresh()
    true
  of nimkit.mtreScrollWheel:
    discard view.scrollBy(
      event.scrollEvent.deltaY, event.row, event.column, event.scrollEvent.modifiers
    )
    true
  of nimkit.mtreKeyDown:
    let keyEvent = event.keyEvent
    if view.handlePendingPaneKey(keyEvent):
      return true
    view.sendKeyDownToMoe(keyEvent)
  of nimkit.mtreFlagsChanged:
    true

protocol KosmoEditorInput of nimkit.TextInputProtocol:
  method insertText(view: KosmoEditorView, text: string) =
    if text.len > 0:
      view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
      discard view.editor.handleTextInput(text)
      view.refresh()

proc editorCopy(view: KosmoEditorView) =
  if view.editor.currentSelection().isSome:
    discard nimkit.generalPasteboard().setPlainText(view.editor.copySelection())
    view.refresh()

proc editorCut(view: KosmoEditorView) =
  if view.editor.currentSelection().isSome:
    discard nimkit.generalPasteboard().setPlainText(view.editor.cutSelection())
    view.refresh()

proc editorPaste(view: KosmoEditorView) =
  discard view.editor.handlePaste(nimkit.generalPasteboard().plainText())
  view.refresh()

proc refreshEditorSearch(
    view: KosmoEditorView,
    start: KosmoBufferCursor,
    direction = KosmoSearchDirection.Forward,
) =
  let query = view.searchBar.query()
  if query.len == 0:
    discard view.editor.revealLocation(view.searchOrigin.line, view.searchOrigin.column)
    view.editor.clearSearch()
    view.searchBar.hasMatches = false
  else:
    view.searchBar.hasMatches = view.editor.searchFrom(query, start, direction)
  view.refresh()

proc editorSearchQueryDidChange(view: KosmoEditorView, query: string) =
  discard query
  view.refreshEditorSearch(view.searchOrigin)

proc findPrevious*(view: KosmoEditorView) =
  ## Find the previous Moe match while retaining the floating search field.
  if not view.isNil and not view.searchBar.isNil:
    view.refreshEditorSearch(view.editor.bufferCursor(), KosmoSearchDirection.Backward)

proc findNext*(view: KosmoEditorView) =
  ## Find the next Moe match while retaining the floating search field.
  if not view.isNil and not view.searchBar.isNil:
    view.refreshEditorSearch(view.editor.bufferCursor())

proc dismissSearch*(view: KosmoEditorView) =
  ## Hide editor search, clear Moe's highlights, and return focus to the editor.
  if view.isNil or view.searchBar.isNil:
    return
  view.searchBar.hidden = true
  view.editor.clearSearch()
  view.refresh()
  let owner = view.window()
  if owner of nimkit.Window:
    discard nimkit.Window(owner).makeFirstResponder(view)

proc showSearch*(view: KosmoEditorView): bool {.discardable.} =
  ## Show the editor search widget and focus its query field.
  if view.isNil or view.searchBar.isNil:
    return
  let owner = view.window()
  if not (owner of nimkit.Window):
    return
  if view.searchBar.hidden():
    view.searchOrigin = view.editor.bufferCursor()
    view.searchBar.query = ""
    view.editor.clearSearch()
    view.searchBar.hasMatches = false
    view.searchBar.hidden = false
    view.setNeedsLayout()
    view.layoutSubtreeIfNeeded()
  else:
    view.searchBar.queryField().selectedRange =
      nimkit.initTextRange(0, view.searchBar.query().runeLen)
  result = nimkit.Window(owner).makeFirstResponder(view.searchBar.queryField())

func searchField*(view: KosmoEditorView): nimkit.TextField =
  if not view.isNil and not view.searchBar.isNil:
    result = view.searchBar.queryField()

proc searchVisible*(view: KosmoEditorView): bool =
  not view.isNil and not view.searchBar.isNil and not view.searchBar.hidden()

func editorSearchShortcutModifiers*(): set[nimkit.KeyModifier] =
  ## Return the platform-native Find modifiers used by Moe editor panes.
  when defined(macosx) or defined(macos):
    {nimkit.kmCommand}
  else:
    {nimkit.kmControl}

protocol KosmoEditorEditingCommands of nimkit.TextEditingCommandProtocol:
  method copy(view: KosmoEditorView, args: nimkit.ActionArgs) =
    discard args
    view.editorCopy()

  method cut(view: KosmoEditorView, args: nimkit.ActionArgs) =
    discard args
    view.editorCut()

  method paste(view: KosmoEditorView, args: nimkit.ActionArgs) =
    discard args
    view.editorPaste()

  method selectAll(view: KosmoEditorView, args: nimkit.ActionArgs) =
    discard args
    discard view.editor.selectAll()
    view.refresh()

  method undo(view: KosmoEditorView, args: nimkit.ActionArgs) =
    discard args
    discard view.editor.undo()
    view.refresh()

  method redo(view: KosmoEditorView, args: nimkit.ActionArgs) =
    discard args
    discard view.editor.redo()
    view.refresh()

func isEditingAction(action: string): bool =
  action.kosmoAction().kind == KosmoActionKind.Editing

proc handleKosmoKeyEquivalent(view: KosmoEditorView, event: nimkit.KeyEvent): bool =
  if view.handlePendingPaneKey(event):
    return true
  if event.key == nimkit.keyF and event.modifiers == editorSearchShortcutModifiers():
    return view.showSearch()
  if view.tabsDelegate.isNil or view.tabsDelegate.dockController.isNil:
    return false
  let controller = view.tabsDelegate.dockController[]
  if event.key == nimkit.keyTab and event.modifiers - {nimkit.kmShift} == {} and
      view.editor.mode() in {KosmoEditorMode.Insert, KosmoEditorMode.Replace}:
    return view.sendKeyDownToMoe(event)
  if event.key == nimkit.keyForText("w") and event.modifiers == {nimkit.kmControl} and
      controller.editorInputPolicy != KosmoEditorInputPolicy.Native:
    if view.editor.mode() == KosmoEditorMode.Normal:
      view.pendingPanePrefix = true
      return true
    return view.sendKeyDownToMoe(event)

  let selector = controller.shortcutBindings.commandFor(event)
  if selector.isNone or not ($selector.get.name).isEditingAction():
    return false
  let sendToMoe =
    case controller.editorInputPolicy
    of KosmoEditorInputPolicy.Vim:
      true
    of KosmoEditorInputPolicy.Native:
      false
    of KosmoEditorInputPolicy.Hybrid:
      view.editor.mode() notin
        {KosmoEditorMode.Insert, KosmoEditorMode.Replace, KosmoEditorMode.Visual}
  if sendToMoe:
    return view.sendKeyDownToMoe(event)
  false

protocol KosmoEditorCommandDispatch of nimkit.ResponderCommandDispatchProtocol:
  method dispatchCommand(view: KosmoEditorView, args: nimkit.TryToPerformArgs): bool =
    if view.tabsDelegate.isNil or view.tabsDelegate.dockController.isNil:
      return false
    let controller = view.tabsDelegate.dockController[]
    let panelNumber = args.selector.focusPanelNumber()
    if panelNumber > 0:
      discard controller.focusPanel(panelNumber)
      return true
    case $args.selector.name
    of KosmoNewFileAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].newEditorTab()
    of KosmoOpenFileAction:
      if not controller.frontend.isNil:
        controller.frontend[].chooseFile()
    of KosmoOpenProjectAction:
      if not controller.frontend.isNil and not controller.frontend[].xWindowManager.isNil:
        controller.frontend[].xWindowManager[].chooseProject()
    of KosmoQuickOpenAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showQuickOpen()
    of KosmoNewTerminalAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].newTerminal()
    of KosmoShowGitDiffAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showGitDiff()
    of KosmoSaveAction:
      controller.saveCurrentTab(view)
    of KosmoCloseTabAction:
      controller.closeCurrentTab(view)
    of KosmoCloseWindowAction:
      let group = controller.groupForView(view)
      if not group.isNil:
        group.window.close()
    of KosmoQuitAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].application.terminate()
    of KosmoPreviousTabAction:
      controller.selectRelativeTab(view, -1)
    of KosmoNextTabAction:
      controller.selectRelativeTab(view, 1)
    of KosmoSplitHorizontalAction:
      discard
        controller.splitCurrentPaneTab(controller.groupForView(view), nimkit.dpBottom)
    of KosmoSplitVerticalAction:
      discard
        controller.splitCurrentPaneTab(controller.groupForView(view), nimkit.dpRight)
    of KosmoShowFileExplorerAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showFileExplorer()
    of KosmoRevealActiveFileAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].revealActiveFile()
    of KosmoFindInFilesAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showFindInFiles()
    of KosmoShowSettingsAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showSettings()
    of KosmoCopyAction:
      view.editorCopy()
    of KosmoCutAction:
      view.editorCut()
    of KosmoPasteAction:
      view.editorPaste()
    of KosmoSelectAllAction:
      discard view.editor.selectAll()
      view.refresh()
    of KosmoUndoAction:
      discard view.editor.undo()
      view.refresh()
    of KosmoRedoAction:
      discard view.editor.redo()
      view.refresh()
    else:
      return false
    true

proc targetView(handler: KosmoEditorTabsHandler): KosmoEditorView =
  if not handler.editorView.isNil:
    return handler.editorView[]

protocol KosmoEditorTabsDelegate of nimkit.DocumentTabsDelegate:
  method didSelectDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      item: nimkit.DocumentTabItem,
  ) =
    discard tabs
    let view = handler.targetView()
    if view.isNil:
      return
    if view.syncingTabs:
      return
    if not handler.dockController.isNil and not view.dockGroup.isNil:
      handler.dockController[].activatePaneTab(view.dockGroup[], item.identifier())
      return
    var id: KosmoBufferId
    if item.identifier.parseTabIdentifier(id):
      view.saveViewState()
      view.editor.dismissCompletionPopup()
      view.editor.dismissCommandLine()
      if view.usesBufferSubset:
        view.selectedBufferId = some(id)
      if not handler.dockController.isNil:
        handler.dockController[].activateGroup(view)
      if view.usesBufferSubset:
        view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
      elif not view.editor.selectTab(id):
        view.lastTabs.setLen(0)
      view.refresh()

  method didDoubleClickDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      item: nimkit.DocumentTabItem,
  ) =
    discard tabs
    let view = handler.targetView()
    if view.isNil or view.syncingTabs:
      return
    var id: KosmoBufferId
    if not item.identifier.parseTabIdentifier(id):
      return
    for tab in view.editor.tabs():
      if tab.id == id and tab.temporary and tab.filePath.isSome:
        discard view.openFile(tab.filePath.get)
        return

  method shouldCloseDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      item: nimkit.DocumentTabItem,
      index: int,
  ): bool =
    discard tabs
    discard index
    let view = handler.targetView()
    if view.isNil:
      return
    if view.syncingTabs:
      return
    var id: KosmoBufferId
    if item.identifier.parseTabIdentifier(id):
      if not handler.dockController.isNil and not view.dockGroup.isNil:
        let
          controller = handler.dockController[]
          group = view.dockGroup[]
        if controller.bufferIsVisibleOutside(group, id):
          group.removeBuffer(id)
          return true
      let outcome = view.closeTab(id)
      return outcome.closed
    if view.dockGroup.isNil:
      return
    let
      group = view.dockGroup[]
      documentIndex = group.documentIndex(item.identifier())
    if documentIndex < 0 or not group.documents[documentIndex].close():
      return
    group.documents.delete(documentIndex)
    let orderIndex = group.tabOrder.find(item.identifier())
    if orderIndex >= 0:
      group.tabOrder.delete(orderIndex)
    true

  method didCloseDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      item: nimkit.DocumentTabItem,
      index: int,
  ) =
    discard tabs
    discard item
    discard index
    let view = handler.targetView()
    if not view.isNil:
      if handler.dockController.isNil:
        view.refresh()
      else:
        handler.dockController[].finishTabClose(view)

  method didMoveDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      item: nimkit.DocumentTabItem,
      fromIndex: int,
      toIndex: int,
  ) =
    discard tabs
    discard fromIndex
    let view = handler.targetView()
    if view.isNil:
      return
    var id: KosmoBufferId
    if not view.dockGroup.isNil:
      let group = view.dockGroup[]
      let orderIndex = group.tabOrder.find(item.identifier())
      if orderIndex >= 0:
        group.tabOrder.delete(orderIndex)
        group.tabOrder.insert(item.identifier(), min(toIndex, group.tabOrder.len))
      if item.identifier.parseTabIdentifier(id) and view.usesBufferSubset:
        var bufferIds: seq[KosmoBufferId]
        for identifier in group.tabOrder:
          var bufferId: KosmoBufferId
          if identifier.parseTabIdentifier(bufferId):
            bufferIds.add bufferId
        view.bufferIds = bufferIds
        view.syncEditorTabOrder()
    elif item.identifier.parseTabIdentifier(id):
      if not view.editor.moveTab(id, toIndex.Natural):
        view.lastTabs.setLen(0)
    view.refresh()

  method didBeginDraggingDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      info: nimkit.DocumentTabDragInfo,
  ) =
    if not handler.dockController.isNil:
      handler.dockController[].updateDockTarget(tabs, info.location)

  method didDragDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      info: nimkit.DocumentTabDragInfo,
  ) =
    if not handler.dockController.isNil:
      handler.dockController[].updateDockTarget(tabs, info.location)

  method didEndDraggingDocumentTab(
      handler: KosmoEditorTabsHandler,
      tabs: nimkit.DocumentTabs,
      info: nimkit.DocumentTabDragInfo,
  ) =
    if not handler.dockController.isNil:
      handler.dockController[].finishDockDrag(tabs, info.item, info.location)

protocol KosmoEditorViewLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(view: KosmoEditorView) =
    if not view.searchBar.isNil:
      view.searchBar.layoutInBounds(view.bounds())

proc newKosmoEditorView*(editor = newKosmoEditor()): KosmoEditorView =
  result = KosmoEditorView(
    editor: editor,
    documentTabs: nimkit.newDocumentTabs(),
    renderBuffer: newRenderBuffer(80, 24),
    matterRefreshActive: true,
  )
  result.initMonoTextViewFields(editable = true)
  result.clipsToBounds = true
  result.padding = 0.0'f32
  result.fontSize = 14.0'f32
  result.textColor = nimkit.color(0.88, 0.9, 0.94, 1.0)
  result.backgroundColor = nimkit.color(0.04, 0.05, 0.07, 1.0)
  result.applyKosmoEditorStyle(result.effectiveAppearance())
  result.rawEventPolicy = nimkit.initMonoTextRawEventPolicy(
    capturedEvents = nimkit.AllMonoTextRawEvents - {nimkit.mtreKeyDown}
  )
  let editorView = result
  result.rawEventHandler = proc(event: nimkit.MonoTextRawEvent): bool =
    editorView.handleRawEvent(event)
  discard result.withProtocol(KosmoEditorInput)
  discard result.withProtocol(KosmoEditorEditingCommands)
  discard result.withProtocol(KosmoEditorCommandDispatch)
  discard result.withProtocol(KosmoEditorViewLayout)
  let keyEquivalentMethod: nimkit.DynamicMethod = proc(
      self: nimkit.DynamicAgent, invocation: var nimkit.Invocation
  ) =
    let event = invocation.argsAs(nimkit.KeyEvent)
    invocation.setResult(KosmoEditorView(self).handleKosmoKeyEquivalent(event))
  discard
    result.replaceMethod(nimkitSelectors.performKeyEquivalent(), keyEquivalentMethod)
  result.tabsDelegate = KosmoEditorTabsHandler(editorView: result.unsafeWeakRef())
  discard result.tabsDelegate.withProtocol(KosmoEditorTabsDelegate)
  result.documentTabs.delegate = result.tabsDelegate
  connect(
    result.editor.matterHighlightingController(),
    matterHighlightCompleted,
    result,
    KosmoEditorView.refreshMatterHighlighting(),
  )
  let
    searchOwner = result.unsafeWeakRef()
    onQueryChanged: KosmoSearchQueryAction = proc(query: string) =
      if not searchOwner.isNil:
        searchOwner[].editorSearchQueryDidChange(query)
    onPrevious: KosmoSearchAction = proc() =
      if not searchOwner.isNil:
        searchOwner[].findPrevious()
    onNext: KosmoSearchAction = proc() =
      if not searchOwner.isNil:
        searchOwner[].findNext()
    onClose: KosmoSearchAction = proc() =
      if not searchOwner.isNil:
        searchOwner[].dismissSearch()
  result.searchBar =
    newKosmoSearchBar("editor text", onQueryChanged, onPrevious, onNext, onClose)
  result.addSubview(result.searchBar)
  result.syncChrome()

protocol KosmoCommandBarHitTesting of nimkit.ViewProtocol:
  method pointInside(bar: KosmoCommandBar, point: nimkit.Point): bool =
    discard bar
    discard point

proc newKosmoCommandBar(view: KosmoEditorView): KosmoCommandBar =
  result = KosmoCommandBar()
  result.initMonoTextViewFields()
  result.clipsToBounds = true
  result.padding = 0.0'f32
  result.fontSize = view.fontSize()
  result.textColor = nimkit.color(0.88, 0.9, 0.94, 1.0)
  result.cursorVisible = false
  result.styleId = KosmoEditorStyleId
  result.appearance = view.effectiveAppearance()
  result.hidden = true
  discard result.withProtocol(KosmoCommandBarHitTesting)

protocol KosmoPaneIndicatorDrawing of nimkit.ViewDrawingProtocol:
  method draw(indicator: KosmoPaneIndicator, context: nimkit.DrawContext) =
    let bounds = indicator.bounds()
    if bounds.isEmpty:
      return
    let
      styleContext = nimkit.controlStyle(nimkit.srBox, id = KosmoPaneIndicatorStyleId)
      outlineColor = context.appearance.resolveColor(
        styleContext,
        nimkit.StyleBorderColor,
        nimkit.color(0.20, 0.45, 0.92, KosmoPaneOutlineOpacity),
      )
      outlineWidth = context.appearance.resolveLength(
        styleContext, nimkit.StyleBorderWidth, KosmoPaneOutlineWidth
      )
      cornerRadius = context.appearance.resolveLength(
        styleContext, nimkit.StyleCornerRadius, 0.0'f32
      )
      inset = outlineWidth * 0.5'f32
      outlineRect = nimkit.rect(
        bounds.minX + inset,
        bounds.minY + inset,
        max(bounds.size.width - outlineWidth, 0.0'f32),
        max(bounds.size.height - outlineWidth, 0.0'f32),
      )
    discard context.addRenderRectangle(
      context.renderRectFor(outlineRect),
      nimkit.fill(nimkit.color(0.0, 0.0, 0.0, 0.0)),
      outlineColor,
      outlineWidth,
      cornerRadius,
    )

protocol KosmoPaneIndicatorHitTesting of nimkit.ViewProtocol:
  method pointInside(indicator: KosmoPaneIndicator, point: nimkit.Point): bool =
    discard indicator
    discard point

proc newKosmoPaneIndicator(): KosmoPaneIndicator =
  result = KosmoPaneIndicator()
  result.initViewFields()
  result.background = nimkit.color(0.0, 0.0, 0.0, 0.0)
  result.styleId = KosmoPaneIndicatorStyleId
  result.hidden = true
  discard result.withProtocol(KosmoPaneIndicatorDrawing)
  discard result.withProtocol(KosmoPaneIndicatorHitTesting)

proc selectedMarkdownBufferId(controls: KosmoMarkdownControls): Option[KosmoBufferId] =
  if controls.isNil or controls.editorView.isNil:
    return
  let view = controls.editorView[]
  if view.dockGroup.isNil:
    return
  var id: KosmoBufferId
  if not view.dockGroup[].selectedTabIdentifier.parseTabIdentifier(id):
    return
  for tab in view.editor.tabs():
    if tab.id == id and tab.isMarkdownTab:
      return some(id)

proc focusMarkdownContent(controls: KosmoMarkdownControls) =
  if controls.isNil or controls.editorView.isNil:
    return
  let view = controls.editorView[]
  if view.dockGroup.isNil:
    return
  let group = view.dockGroup[]
  if not group.window.isNil:
    discard group.window.makeFirstResponder(nimkit.Responder(group.pane.contentView))

proc toggleSelectedMarkdownMode(controls: KosmoMarkdownControls) =
  let id = controls.selectedMarkdownBufferId()
  if id.isNone or controls.editorView.isNil:
    return
  if controls.editorView[].toggleMarkdownMode(id.get):
    controls.focusMarkdownContent()

proc toggleMarkdownColorMode(controls: KosmoMarkdownControls) =
  if controls.isNil:
    return
  controls.xColorMode = if controls.xColorMode == kmcmLight: kmcmDark else: kmcmLight
  if not controls.editorView.isNil:
    controls.editorView[].refresh()

proc changeMarkdownFontSize(controls: KosmoMarkdownControls, delta: float32) =
  if controls.isNil:
    return
  let nextSize = clamp(
    controls.xFontSize + delta,
    KosmoMarkdownMinimumFontSize,
    KosmoMarkdownMaximumFontSize,
  )
  if abs(nextSize - controls.xFontSize) <= 0.001'f32:
    return
  controls.xFontSize = nextSize
  if not controls.editorView.isNil:
    controls.editorView[].refresh()

proc newKosmoMarkdownControls(view: KosmoEditorView): KosmoMarkdownControls =
  let
    colorMode = view.effectiveAppearance().markdownColorMode()
    modeButton = nimkit.newButton("</>")
    colorModeButton = nimkit.newButton(if colorMode == kmcmLight: "Dark" else: "Light")
    decreaseFontButton = nimkit.newButton("-")
    increaseFontButton = nimkit.newButton("+")
    row = nimkit.newStackView(nimkit.laHorizontal)
  result = KosmoMarkdownControls(
    modeButton: modeButton,
    colorModeButton: colorModeButton,
    decreaseFontButton: decreaseFontButton,
    increaseFontButton: increaseFontButton,
    editorView: view.unsafeWeakRef(),
    xColorMode: colorMode,
    xThemeColorMode: colorMode,
    xFontSize: KosmoMarkdownDefaultFontSize,
  )
  result.initBoxFields()
  result.styleId = KosmoMarkdownControlsStyleId
  result.accessibilityLabel = "Markdown preview controls"
  result.hidden = true

  modeButton.reservedTitles = ["</>", "MD"]
  modeButton.accessibilityLabel = "Edit Markdown source"
  modeButton.toolTip = "Edit Markdown source"
  colorModeButton.reservedTitles = ["Dark", "Light"]
  result.syncMarkdownColorButton()
  decreaseFontButton.accessibilityLabel = "Decrease Markdown font size"
  decreaseFontButton.toolTip = "Decrease Markdown font size"
  increaseFontButton.accessibilityLabel = "Increase Markdown font size"
  increaseFontButton.toolTip = "Increase Markdown font size"
  for button in [modeButton, colorModeButton, decreaseFontButton, increaseFontButton]:
    button.addStyleClass(KosmoMarkdownControlButtonStyleClass)
    button.setHuggingPriority(nimkit.LayoutPriorityHigh, nimkit.laHorizontal)

  row.spacing = 2.0'f32
  row.distribution = nimkit.svdNatural
  row.addArrangedSubview(modeButton, colorModeButton)
  row.addFlexibleSpacer()
  row.addArrangedSubview(decreaseFontButton, increaseFontButton)
  result.contentView = row

  let weakControls = result.unsafeWeakRef()
  let modeAction = nimkit.actionSelector("kosmo.toggleMarkdownMode")
  modeButton.target = nimkit.newActionTarget(
    modeAction,
    proc(sender: nimkit.DynamicAgent) =
      discard sender
      if not weakControls.isNil:
        weakControls[].toggleSelectedMarkdownMode()
    ,
  )
  modeButton.action = modeAction

  let colorModeAction = nimkit.actionSelector("kosmo.toggleMarkdownColorMode")
  colorModeButton.target = nimkit.newActionTarget(
    colorModeAction,
    proc(sender: nimkit.DynamicAgent) =
      discard sender
      if not weakControls.isNil:
        weakControls[].toggleMarkdownColorMode()
    ,
  )
  colorModeButton.action = colorModeAction

  let decreaseFontAction = nimkit.actionSelector("kosmo.decreaseMarkdownFontSize")
  decreaseFontButton.target = nimkit.newActionTarget(
    decreaseFontAction,
    proc(sender: nimkit.DynamicAgent) =
      discard sender
      if not weakControls.isNil:
        weakControls[].changeMarkdownFontSize(-KosmoMarkdownFontSizeIncrement)
    ,
  )
  decreaseFontButton.action = decreaseFontAction

  let increaseFontAction = nimkit.actionSelector("kosmo.increaseMarkdownFontSize")
  increaseFontButton.target = nimkit.newActionTarget(
    increaseFontAction,
    proc(sender: nimkit.DynamicAgent) =
      discard sender
      if not weakControls.isNil:
        weakControls[].changeMarkdownFontSize(KosmoMarkdownFontSizeIncrement)
    ,
  )
  increaseFontButton.action = increaseFontAction

proc applyKosmoSidebarStyle(pane: KosmoSidebarPane, base: nimkit.Appearance) =
  var appearance = base
  let
    tabContext = nimkit.controlStyle(nimkit.srTab)
    selectedTabContext = nimkit.controlStyle(nimkit.srTab, {nimkit.ssSelected})
    inactiveTabSelector = nimkit.initStyleSelector(nimkit.srTab, {nimkit.ssSelected})
    activeTabSelector =
      nimkit.initStyleSelector(nimkit.srTab, {nimkit.ssSelected, nimkit.ssFocused})
    cancelButtonSelector =
      nimkit.initStyleSelector(nimkit.srButton, id = KosmoCancelSearchButtonStyleId)
    highlightedCancelButtonSelector = nimkit.initStyleSelector(
      nimkit.srButton, {nimkit.ssHighlighted}, id = KosmoCancelSearchButtonStyleId
    )
    normalTabFill =
      base.resolveFill(tabContext, nimkit.fill(nimkit.color(0.16, 0.18, 0.22, 1.0)))
    normalTabTextColor = base.resolveColor(
      tabContext, nimkit.StyleTextColor, nimkit.color(0.72, 0.74, 0.80, 1.0)
    )
    selectedTabFill = base.resolveFill(
      selectedTabContext, nimkit.fill(nimkit.color(0.18, 0.42, 0.88, 0.18))
    )
    selectedTabTextColor = base.resolveColor(
      selectedTabContext, nimkit.StyleTextColor, nimkit.color(0.22, 0.50, 0.92, 1.0)
    )
    selectedTabIndicatorFill = base.resolveFill(
      selectedTabContext,
      nimkit.fill(selectedTabTextColor),
      nimkit.StyleSelectionIndicatorFill,
    )
    inactiveTabTextColor = nimkit.color(
      normalTabTextColor.r,
      normalTabTextColor.g,
      normalTabTextColor.b,
      normalTabTextColor.a * KosmoInactiveTabTextOpacity,
    )
    inactiveTabIndicatorColor = nimkit.color(
      selectedTabTextColor.r,
      selectedTabTextColor.g,
      selectedTabTextColor.b,
      selectedTabTextColor.a * KosmoInactiveTabAccentOpacity,
    )
  appearance.setStyle(inactiveTabSelector, nimkit.StyleFill, normalTabFill)
  appearance.setStyle(inactiveTabSelector, nimkit.StyleTextColor, inactiveTabTextColor)
  appearance.setStyle(
    inactiveTabSelector,
    nimkit.StyleSelectionIndicatorFill,
    nimkit.fill(inactiveTabIndicatorColor),
  )
  appearance.setStyle(activeTabSelector, nimkit.StyleFill, selectedTabFill)
  appearance.setStyle(activeTabSelector, nimkit.StyleTextColor, selectedTabTextColor)
  appearance.setStyle(
    activeTabSelector, nimkit.StyleSelectionIndicatorFill, selectedTabIndicatorFill
  )
  appearance.setStyle(
    cancelButtonSelector,
    nimkit.StyleFill,
    nimkit.fill(nimkit.color(0.12, 0.13, 0.16, 1.0)),
  )
  appearance.setStyle(
    cancelButtonSelector, nimkit.StyleBorderColor, nimkit.color(0.38, 0.40, 0.46, 1.0)
  )
  appearance.setStyle(
    cancelButtonSelector, nimkit.StyleTextColor, nimkit.color(0.88, 0.89, 0.92, 1.0)
  )
  appearance.setStyle(cancelButtonSelector, nimkit.StyleBorderWidth, 1.0'f32)
  appearance.setStyle(cancelButtonSelector, nimkit.StyleCornerRadius, 10.0'f32)
  appearance.setStyle(
    cancelButtonSelector,
    nimkit.StyleChrome,
    nimkit.styleKeyword(nimkit.DefaultChromeName),
  )
  appearance.setStyle(
    highlightedCancelButtonSelector,
    nimkit.StyleFill,
    nimkit.fill(nimkit.color(0.22, 0.23, 0.27, 1.0)),
  )
  appearance.installKosmoPaneIndicatorStyle(base)
  pane.activeIndicator.appearance = appearance
  pane.tabs.appearance = appearance
  pane.searchPanel.cancelButton.appearance = appearance

proc containsResponder(pane: KosmoSidebarPane, candidate: nimkit.Responder): bool =
  var responder = candidate
  while not responder.isNil:
    if responder == nimkit.Responder(pane):
      return true
    responder = responder.nextResponder()

proc hasSidebarFocus(pane: KosmoSidebarPane): bool =
  if pane.isNil or pane.observedWindow.isNil:
    return
  let window = pane.observedWindow[]
  if pane.containsResponder(window.firstResponder()):
    return true
  pane.containsResponder(window.fieldEditorClient())

proc updateSidebarFocus(pane: KosmoSidebarPane) =
  if pane.isNil:
    return
  let focused = pane.hasSidebarFocus()
  pane.tabs.focused = focused
  pane.activeIndicator.hidden = not focused
  pane.fileTree.showsFocusedRowHighlight = focused
  pane.searchPanel.resultsView.showsFocusedRowHighlight = focused
  if not pane.dockController.isNil:
    pane.dockController[].sidebarFocused = focused

protocol KosmoSidebarAppearanceObserver of nimkit.WindowAppearanceEvents:
  proc didChangeEffectiveAppearance(
      pane: KosmoSidebarPane, appearance: nimkit.Appearance
  ) {.slot.} =
    pane.applyKosmoSidebarStyle(appearance)

protocol KosmoSidebarFocusObserver of nimkit.WindowFocusEvents:
  proc didChangeFirstResponder(
      pane: KosmoSidebarPane, previous: nimkit.Responder
  ) {.slot.} =
    discard previous
    pane.updateSidebarFocus()

proc stopObservingWindow(pane: KosmoSidebarPane) =
  if pane.isNil or pane.observedWindow.isNil:
    return
  pane.unobserveProtocol(pane.observedWindow[], nimkit.WindowAppearanceEvents)
  pane.unobserveProtocol(pane.observedWindow[], nimkit.WindowFocusEvents)
  pane.observedWindow = default(WeakRef[nimkit.Window])

proc observeWindow(pane: KosmoSidebarPane, window: nimkit.Window) =
  pane.stopObservingWindow()
  if window.isNil:
    return
  pane.observedWindow = window.unsafeWeakRef()
  pane.observeProtocol(window, nimkit.WindowAppearanceEvents)
  pane.observeProtocol(window, nimkit.WindowFocusEvents)
  pane.applyKosmoSidebarStyle(window.effectiveAppearance())
  pane.updateSidebarFocus()

protocol KosmoSidebarBrowserLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(area: KosmoSidebarBrowserArea) =
    let
      bounds = area.bounds()
      tabHeight = min(area.tabs.tabBarHeight, bounds.size.height)
    area.tabs.setFrameFromLayout(bounds)
    area.activeIndicator.setFrameFromLayout(
      nimkit.rect(
        0, tabHeight, bounds.size.width, max(bounds.size.height - tabHeight, 0)
      )
    )

protocol KosmoSidebarPaneLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(pane: KosmoSidebarPane) =
    let
      bounds = pane.bounds()
      previousHeight = pane.splitView.bounds().size.height
      contextHeight =
        if pane.setInitialDivider:
          pane.splitView.positionOfDivider(0)
        else:
          pane.contextPanel.preferredHeight()
    pane.splitView.setFrameFromLayout(bounds)
    if bounds.size.height > 0 and
        (
          not pane.setInitialDivider or
          abs(previousHeight - bounds.size.height) > 0.001'f32
        ):
      pane.splitView.setPositionOfDivider(0, contextHeight)
      pane.setInitialDivider = true

proc newKosmoSidebarPane(
    tabs: nimkit.CompactTabView,
    fileTree: KosmoFileTree,
    searchPanel: KosmoFileSearchPanel,
): KosmoSidebarPane =
  let
    activeIndicator = newKosmoPaneIndicator()
    contextPanel = newKosmoContextPanel()
    splitView = nimkit.newSplitView(nimkit.laVertical)
    browserArea = KosmoSidebarBrowserArea(tabs: tabs, activeIndicator: activeIndicator)
  browserArea.initViewFields()
  browserArea.clipsToBounds = true
  browserArea.addSubview(tabs)
  browserArea.addSubview(activeIndicator)
  discard browserArea.withProtocol(KosmoSidebarBrowserLayout)
  splitView.addPane(
    contextPanel,
    minSize = KosmoContextPanelHeaderHeight,
    maxSize = KosmoContextPanelHeaderHeight,
  )
  splitView.addPane(browserArea, minSize = 160.0'f32)
  result = KosmoSidebarPane(
    contextPanel: contextPanel,
    splitView: splitView,
    tabs: tabs,
    fileTree: fileTree,
    searchPanel: searchPanel,
    activeIndicator: activeIndicator,
  )
  result.initViewFields()
  result.clipsToBounds = true
  result.addSubview(splitView)
  discard result.withProtocol(KosmoSidebarPaneLayout)
  result.updateSidebarFocus()

protocol KosmoEditorPaneLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(pane: KosmoEditorPane) =
    let
      bounds = pane.bounds()
      tabHeight = min(KosmoTabBarHeight, bounds.size.height)
      markdownToolbarVisible =
        not pane.markdownControls.isNil and not pane.markdownControls.hidden
      markdownToolbarHeight =
        if markdownToolbarVisible:
          min(KosmoMarkdownControlsHeight, max(bounds.size.height - tabHeight, 0.0'f32))
        else:
          0.0'f32
      contentTop = tabHeight + markdownToolbarHeight
      contentHeight = max(bounds.size.height - contentTop, 1.0'f32)
      commandBarHeight = min(KosmoCommandBarHeight, contentHeight)
    pane.documentTabs.setFrameFromLayout(
      nimkit.rect(0, 0, bounds.size.width, tabHeight)
    )
    if not pane.contentView.isNil:
      pane.contentView.setFrameFromLayout(
        nimkit.rect(0, contentTop, bounds.size.width, contentHeight)
      )
    pane.commandBar.setFrameFromLayout(
      nimkit.rect(
        0,
        max(contentTop, bounds.size.height - commandBarHeight),
        bounds.size.width,
        commandBarHeight,
      )
    )
    pane.activeIndicator.setFrameFromLayout(
      nimkit.rect(0, contentTop, bounds.size.width, contentHeight)
    )
    if not pane.markdownControls.isNil:
      pane.markdownControls.setFrameFromLayout(
        nimkit.rect(0, tabHeight, bounds.size.width, markdownToolbarHeight)
      )
    if pane.contentView == nimkit.View(pane.editorView):
      pane.editorView.refresh()

proc setContentView(pane: KosmoEditorPane, contentView: nimkit.View) =
  if pane.isNil or contentView.isNil or pane.contentView == contentView:
    return
  let owner = pane.window()
  var transferFocus = false
  if owner of nimkit.Window and not pane.contentView.isNil:
    var responder = nimkit.Window(owner).firstResponder()
    while not responder.isNil:
      if responder == nimkit.Responder(pane.contentView):
        transferFocus = true
        break
      responder = responder.nextResponder()
  if pane.contentView.isNil:
    pane.addSubview(contentView, positioned = nimkit.svpBelow)
  elif not pane.replaceSubview(pane.contentView, contentView):
    pane.addSubview(contentView, positioned = nimkit.svpBelow)
  pane.contentView = contentView
  if contentView != nimkit.View(pane.editorView):
    pane.commandBar.hidden = true
  pane.setNeedsLayout()
  if transferFocus:
    var responder = nimkit.Responder(contentView)
    if not pane.dockGroup.isNil:
      let group = pane.dockGroup[]
      let document = group.documentForIdentifier(group.selectedTabIdentifier)
      if not document.isNil and document.contentView == contentView and
          not document.preferredFirstResponder.isNil:
        responder = nimkit.Responder(document.preferredFirstResponder)
    discard nimkit.Window(owner).makeFirstResponder(responder)

protocol KosmoEditorPaneCommandDispatch of nimkit.ResponderCommandDispatchProtocol:
  method dispatchCommand(pane: KosmoEditorPane, args: nimkit.TryToPerformArgs): bool =
    if pane.dockGroup.isNil:
      return false
    let group = pane.dockGroup[]
    if group.editorView.tabsDelegate.isNil or
        group.editorView.tabsDelegate.dockController.isNil:
      return false
    let controller = group.editorView.tabsDelegate.dockController[]
    if pane.contentView == nimkit.View(pane.markdownView):
      let firstResponder = group.window.firstResponder()
      let previewTextView =
        if firstResponder of nimkit.TextView:
          nimkit.TextView(firstResponder)
        else:
          pane.markdownView.textView()
      case $args.selector.name
      of KosmoCopyAction, "copy":
        discard previewTextView.copyText()
        return true
      of KosmoCutAction, KosmoPasteAction, KosmoUndoAction, KosmoRedoAction, "cut",
          "paste", "undo", "redo":
        return true
      of KosmoSelectAllAction, "selectAll":
        previewTextView.selectAllText()
        return true
      else:
        discard
    let panelNumber = args.selector.focusPanelNumber()
    if panelNumber > 0:
      discard controller.focusPanel(panelNumber)
      return true
    case $args.selector.name
    of KosmoNewFileAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].newEditorTab()
    of KosmoOpenFileAction:
      if not controller.frontend.isNil:
        controller.frontend[].chooseFile()
    of KosmoOpenProjectAction:
      if not controller.frontend.isNil and not controller.frontend[].xWindowManager.isNil:
        controller.frontend[].xWindowManager[].chooseProject()
    of KosmoQuickOpenAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showQuickOpen()
    of KosmoNewTerminalAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].newTerminal()
    of KosmoShowGitDiffAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showGitDiff()
    of KosmoSaveAction:
      controller.saveCurrentPaneTab(group)
    of KosmoCloseTabAction:
      controller.closeCurrentPaneTab(group)
    of KosmoCloseWindowAction:
      group.window.close()
    of KosmoQuitAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].application.terminate()
    of KosmoPreviousTabAction:
      controller.selectRelativePaneTab(group, -1)
    of KosmoNextTabAction:
      controller.selectRelativePaneTab(group, 1)
    of KosmoSplitHorizontalAction:
      discard controller.splitCurrentPaneTab(group, nimkit.dpBottom)
    of KosmoSplitVerticalAction:
      discard controller.splitCurrentPaneTab(group, nimkit.dpRight)
    of KosmoShowFileExplorerAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showFileExplorer()
    of KosmoRevealActiveFileAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].revealActiveFile()
    of KosmoFindInFilesAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showFindInFiles()
    of KosmoShowSettingsAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showSettings()
    of KosmoCopyAction:
      group.editorView.editorCopy()
    of KosmoCutAction:
      group.editorView.editorCut()
    of KosmoPasteAction:
      group.editorView.editorPaste()
    of KosmoSelectAllAction:
      discard group.editorView.editor.selectAll()
      group.editorView.refresh()
    of KosmoUndoAction:
      discard group.editorView.editor.undo()
      group.editorView.refresh()
    of KosmoRedoAction:
      discard group.editorView.editor.redo()
      group.editorView.refresh()
    else:
      return false
    true

proc localMarkdownLinkPath(pane: KosmoEditorPane, link: string): string =
  let url = nimkit.initUrl(link)
  if not url.isFileUrl() or (not url.hasScheme() and url.host().len > 0):
    return
  let path = url.localFilePath(pane.markdownView.imageBasePath)
  if path.len > 0:
    result = absolutePath(path)

protocol KosmoMarkdownLinkDelegate of nimkit.TextViewDelegateProtocol:
  method tvClickedLink(
      pane: KosmoEditorPane,
      textView: nimkit.TextView,
      link: string,
      range: nimkit.TextRange,
  ): bool =
    if textView.attachmentAtIndex(int(range.location)).attachment.identifier.len > 0:
      return true
    let path = pane.localMarkdownLinkPath(link)
    if path.len == 0:
      return link.len > 0
    if not fileExists(path) and not dirExists(path):
      return false
    if pane.dockGroup.isNil:
      return false
    let group = pane.dockGroup[]
    if group.editorView.tabsDelegate.dockController.isNil:
      return false
    let controller = group.editorView.tabsDelegate.dockController[]
    if controller.frontend.isNil:
      return false
    controller.frontend[].openPath(path)

proc newKosmoMarkdownView(editorView: KosmoEditorView): KosmoMarkdownView =
  result = KosmoMarkdownView()
  result.initMarkdownViewFields(syntaxHighlighter = nimkit.matterSyntaxHighlighter)
  result.editorView = editorView.unsafeWeakRef()
  let keyEquivalentMethod: nimkit.DynamicMethod = proc(
      self: nimkit.DynamicAgent, invocation: var nimkit.Invocation
  ) =
    let event = invocation.argsAs(nimkit.KeyEvent)
    let markdownView = KosmoMarkdownView(self)
    if markdownView.handleMarkdownPaneKey(event):
      invocation.setResult(true)
    else:
      invocation.setResult(markdownView.handleMarkdownNavigationKey(event))
  discard
    result.replaceMethod(nimkitSelectors.performKeyEquivalent(), keyEquivalentMethod)

proc markdownViewForBuffer(
    pane: KosmoEditorPane, id: KosmoBufferId
): KosmoMarkdownView =
  for index in 0 ..< pane.markdownPreviews.len:
    if pane.markdownPreviews[index].bufferId == id:
      let cached = pane.markdownPreviews[index]
      result = cached.view
      pane.markdownPreviews.delete(index)
      pane.markdownPreviews.add cached
      return
  if pane.markdownPreviews.len >= KosmoMarkdownPreviewCacheLimit:
    pane.markdownPreviews[0].view.markdown = ""
    pane.markdownPreviews.delete(0)
  if pane.markdownPreviews.len == 0:
    result = pane.markdownView
  else:
    result = newKosmoMarkdownView(pane.editorView)
    result.textView().delegate = nimkit.DynamicAgent(pane)
  pane.markdownPreviews.add KosmoMarkdownPreview(bufferId: id, view: result)

proc newKosmoEditorPane(editorView: KosmoEditorView): KosmoEditorPane =
  let
    commandBar = newKosmoCommandBar(editorView)
    markdownView = newKosmoMarkdownView(editorView)
    markdownControls = newKosmoMarkdownControls(editorView)
    activeIndicator = newKosmoPaneIndicator()
  result = KosmoEditorPane(
    documentTabs: editorView.documentTabs,
    editorView: editorView,
    commandBar: commandBar,
    markdownView: markdownView,
    markdownControls: markdownControls,
    contentView: editorView,
    activeIndicator: activeIndicator,
  )
  editorView.commandBar = commandBar
  result.initViewFields()
  result.addSubview(result.documentTabs)
  result.addSubview(editorView)
  result.addSubview(commandBar)
  result.addSubview(activeIndicator)
  result.addSubview(markdownControls)
  discard result.withProtocol(KosmoEditorPaneLayout)
  discard result.withProtocol(KosmoEditorPaneCommandDispatch)
  discard result.withProtocol(KosmoMarkdownLinkDelegate)
  result.markdownView.textView().delegate = nimkit.DynamicAgent(result)

proc groupForView(
    controller: KosmoDockController, view: KosmoEditorView
): KosmoEditorGroup =
  for group in controller.groups:
    if group.editorView == view:
      return group
