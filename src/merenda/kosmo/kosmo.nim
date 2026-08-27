## A synchronous NimKit frontend for the Moe editor engine.

import std/[math, options, os, strutils, unicode]

import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ./[filesearchpanel, filetree, moe, panedocuments]
import pkg/celina as celina

export filesearchpanel, filetree, moe, panedocuments

const
  KosmoOpenFileAction* = "kosmo.openFile"
  KosmoNewTerminalAction* = "kosmo.newTerminal"
  KosmoSaveAction* = "kosmo.save"
  KosmoCloseTabAction* = "kosmo.closeTab"
  KosmoQuitAction* = "kosmo.quit"
  KosmoPreviousTabAction* = "kosmo.previousTab"
  KosmoNextTabAction* = "kosmo.nextTab"
  KosmoFindInFilesAction* = "kosmo.findInFiles"
  KosmoTabBarHeight* = 34.0'f32
  KosmoStatusBarHeight* = 22.0'f32
  KosmoCommandBarHeight* = 24.0'f32
  KosmoEditorStyleId* = "kosmo.editor"
  KosmoPreviewTabStyleClass* = "kosmo-preview"
  KosmoActivePaneStyleClass* = "kosmo-active-pane"
  KosmoInactivePaneStyleClass* = "kosmo-inactive-pane"
  KosmoCursorOpacity = 0.45'f32
  KosmoPaneAccentOpacity = 0.82'f32
  KosmoPaneOutlineOpacity = 0.38'f32
  KosmoInactiveTabAccentOpacity = 0.18'f32
  KosmoInactiveTabTextOpacity = 0.72'f32
  KosmoPaneAccentHeight = 2.0'f32
  KosmoPaneOutlineWidth = 1.0'f32
  KosmoGridOverscanRows = 1
  KosmoMoeBottomAreaRows = 1
  KosmoTabIdentifierPrefix = "kosmo.buffer."
  KosmoTerminalIdentifierPrefix = "kosmo.terminal."
  KosmoShortcutCommands = [
    KosmoSaveAction, KosmoCloseTabAction, KosmoQuitAction, KosmoPreviousTabAction,
    KosmoNextTabAction, KosmoFindInFilesAction,
  ]
  KosmoFilesTabIdentifier* = "kosmo.sidebar.files"
  KosmoFindTabIdentifier* = "kosmo.sidebar.find"
  KosmoFilesIconSvg =
    """<svg width="24" height="24" viewBox="0 0 24 24"><path fill="#000" d="M2 5h8l2 2h10v13H2z"/></svg>"""
  KosmoFindIconSvg =
    """<svg width="24" height="24" viewBox="0 0 24 24"><circle cx="10" cy="10" r="6" fill="none" stroke="#000" stroke-width="2.4"/><path fill="#000" d="M14.2 13l7 7-1.7 1.7-7-7z"/></svg>"""

type
  KosmoCommandBar* = ref object of nimkit.MonoTextView

  KosmoPaneIndicator = ref object of nimkit.View

  KosmoEditorView* = ref object of nimkit.MonoTextView
    editor*: KosmoEditor
    documentTabs*: nimkit.DocumentTabs
    renderBuffer: RenderBuffer
    statusLabel: nimkit.Label
    commandBar: KosmoCommandBar
    scrollOffsetRows: float32
    lastTabs: seq[KosmoTab]
    syncingTabs: bool
    tabsDelegate: KosmoEditorTabsHandler
    usesBufferSubset: bool
    bufferIds: seq[KosmoBufferId]
    selectedBufferId: Option[KosmoBufferId]
    viewStates: seq[KosmoEditorViewState]
    dockGroup: WeakRef[KosmoEditorGroup]

  KosmoEditorTabsHandler = ref object of nimkit.Responder
    editorView: WeakRef[KosmoEditorView]
    dockController: WeakRef[KosmoDockController]
    appearanceWindow: WeakRef[nimkit.Window]

  KosmoEditorPane* = ref object of nimkit.View
    documentTabs*: nimkit.DocumentTabs
    editorView*: KosmoEditorView
    commandBar*: KosmoCommandBar
    contentView*: nimkit.View
    activeIndicator: KosmoPaneIndicator
    dockGroup: WeakRef[KosmoEditorGroup]

  KosmoEditorGroup* = ref object
    identifier*: string
    panel*: nimkit.DockPanel
    pane*: KosmoEditorPane
    editorView*: KosmoEditorView
    workspace*: nimkit.DockView
    window*: nimkit.Window
    documents: seq[KosmoPaneDocument]
    tabOrder: seq[string]
    selectedTabIdentifier: string

  KosmoDockHost = ref object
    workspace: nimkit.DockView
    window: nimkit.Window
    contentView: nimkit.View
    statusLabel: nimkit.Label
    primary: bool

  KosmoDockController = ref object
    frontend: WeakRef[KosmoApplication]
    editor: KosmoEditor
    groups: seq[KosmoEditorGroup]
    hosts: seq[KosmoDockHost]
    xActiveGroup: KosmoEditorGroup
    nextGroupIdentifier: int
    nextDocumentIdentifier: int
    shortcutBindings: nimkit.KeyBindingTable

  KosmoContentView = ref object of nimkit.View
    splitView: nimkit.SplitView
    statusLabel: nimkit.Label
    setInitialDivider: bool
    lastSplitWidth: float32
    fileTreeWidth: float32
    onFindInFiles: proc() {.closure.}

  KosmoDetachedContentView = ref object of nimkit.View
    workspace: nimkit.DockView
    statusLabel: nimkit.Label

  KosmoApplication* = ref object
    application*: nimkit.Application
    window*: nimkit.Window
    editorView*: KosmoEditorView
    editorPane*: KosmoEditorPane
    documentTabs*: nimkit.DocumentTabs
    statusLabel*: nimkit.Label
    fileTree*: KosmoFileTree
    sidebarTabs*: nimkit.CompactTabView
    searchPanel*: KosmoFileSearchPanel
    splitView*: nimkit.SplitView
    dockView*: nimkit.DockView
    contentView*: nimkit.MenuRootView
    documentView: KosmoContentView
    dockController: KosmoDockController

proc updateActivePaneStyle(group: KosmoEditorGroup, active: bool) =
  if group.isNil or group.pane.isNil:
    return
  let tabs = group.pane.documentTabs
  if active:
    tabs.removeStyleClass(KosmoInactivePaneStyleClass)
    tabs.addStyleClass(KosmoActivePaneStyleClass)
  else:
    tabs.removeStyleClass(KosmoActivePaneStyleClass)
    tabs.addStyleClass(KosmoInactivePaneStyleClass)
  if not group.pane.activeIndicator.isNil:
    group.pane.activeIndicator.hidden = not active

func activeGroup(controller: KosmoDockController): KosmoEditorGroup =
  controller.xActiveGroup

proc `activeGroup=`(controller: KosmoDockController, group: KosmoEditorGroup) =
  if controller.xActiveGroup == group:
    return
  controller.xActiveGroup = group
  for candidate in controller.groups:
    candidate.updateActivePaneStyle(candidate == group)

proc showFindInFiles*(frontend: KosmoApplication): bool {.discardable.}

func initKosmoKeyBindings*(): nimkit.KeyBindingTable =
  ## Return Kosmo's macOS-style application shortcut defaults.
  result.bindKey(
    nimkit.keyS, {nimkit.kmCommand}, nimkit.actionSelector(KosmoSaveAction)
  )
  result.bindKey(
    nimkit.keyW, {nimkit.kmCommand}, nimkit.actionSelector(KosmoCloseTabAction)
  )
  result.bindKey(
    nimkit.keyQ, {nimkit.kmCommand}, nimkit.actionSelector(KosmoQuitAction)
  )
  result.bindKey(
    nimkit.keyLeftBracket,
    {nimkit.kmCommand, nimkit.kmShift},
    nimkit.actionSelector(KosmoPreviousTabAction),
  )
  result.bindKey(
    nimkit.keyRightBracket,
    {nimkit.kmCommand, nimkit.kmShift},
    nimkit.actionSelector(KosmoNextTabAction),
  )
  result.bindKey(
    nimkit.keyF,
    {nimkit.kmCommand, nimkit.kmShift},
    nimkit.actionSelector(KosmoFindInFilesAction),
  )

func defaultKosmoKeyBindingsPath*(): string =
  ## Return the standalone editor's user key bindings file path.
  getConfigDir() / "kosmo" / "keybindings.json"

func toMoeModifiers(modifiers: set[nimkit.KeyModifier]): set[moe.KeyModifier] =
  if nimkit.kmControl in modifiers:
    result.incl moe.kmControl
  if nimkit.kmOption in modifiers:
    result.incl moe.kmAlt
  if nimkit.kmShift in modifiers:
    result.incl moe.kmShift
  if nimkit.kmCommand in modifiers:
    result.incl moe.kmMeta

func toPointerButton(button: nimkit.MouseButton): PointerButton =
  case button
  of nimkit.mbPrimary: pbPrimary
  of nimkit.mbSecondary: pbSecondary
  of nimkit.mbOther: pbOther

func keyName(event: nimkit.KeyEvent): string =
  if event.key >= nimkit.keyA and event.key <= nimkit.keyZ:
    return $char(ord('a') + ord(event.key) - ord(nimkit.keyA))
  if event.key >= nimkit.key0 and event.key <= nimkit.key9:
    return $char(ord('0') + ord(event.key) - ord(nimkit.key0))
  case event.key
  of nimkit.keySpace: "Space"
  of nimkit.keyEscape: "Esc"
  of nimkit.keyEnter: "Enter"
  of nimkit.keyTab: "Tab"
  of nimkit.keyBackspace: "Backspace"
  of nimkit.keyDelete: "Delete"
  of nimkit.keyArrowUp: "Up"
  of nimkit.keyArrowDown: "Down"
  of nimkit.keyArrowLeft: "Left"
  of nimkit.keyArrowRight: "Right"
  of nimkit.keyPageUp: "PageUp"
  of nimkit.keyPageDown: "PageDown"
  of nimkit.keyHome: "Home"
  of nimkit.keyEnd: "End"
  of nimkit.keyMinus: "-"
  of nimkit.keyEqual: "="
  of nimkit.keySlash: "/"
  of nimkit.keyDot: "."
  of nimkit.keyComma: ","
  of nimkit.keySemicolon: ";"
  of nimkit.keyQuote: "'"
  of nimkit.keyBackslash: "\\"
  else: event.text

func keyNotation(event: nimkit.KeyEvent): string =
  let key = event.keyName()
  if key.len == 0:
    return
  var parts: seq[string]
  if nimkit.kmControl in event.modifiers:
    parts.add "C"
  if nimkit.kmOption in event.modifiers or nimkit.kmCommand in event.modifiers:
    parts.add "M"
  if nimkit.kmShift in event.modifiers:
    parts.add "S"
  parts.add key
  parts.join("-")

func awaitsCommittedText(event: nimkit.KeyEvent): bool =
  if event.modifiers - {nimkit.kmShift} != {}:
    return false
  case event.key
  of nimkit.keyA .. nimkit.keyZ,
      nimkit.keyTilde,
      nimkit.key1 .. nimkit.key0,
      nimkit.keyMinus,
      nimkit.keyEqual,
      nimkit.keyLeftBracket,
      nimkit.keyRightBracket,
      nimkit.keySpace,
      nimkit.keySlash,
      nimkit.keyDot,
      nimkit.keyComma,
      nimkit.keySemicolon,
      nimkit.keyQuote,
      nimkit.keyBackslash,
      nimkit.keyNumpad0 .. nimkit.keyNumpad9,
      nimkit.keyNumpadDot,
      nimkit.keyAdd,
      nimkit.keySubtract,
      nimkit.keyMultiply,
      nimkit.keyDivide:
    true
  else:
    false

func toNimkitColor(color: celina.ColorValue): nimkit.Color =
  let rgb = celina.toRgb(color)
  return nimkit.color(
    float32(rgb.r) / 255.0'f32,
    float32(rgb.g) / 255.0'f32,
    float32(rgb.b) / 255.0'f32,
    1.0'f32,
  )

func toMonoTextCell(cell: RenderCell): nimkit.MonoTextCell =
  var
    foreground = cell.style.fg
    background = cell.style.bg
  if celina.Reversed in cell.style.modifiers:
    swap foreground, background
  nimkit.initMonoTextCell(
    cell.symbol,
    foreground.toNimkitColor,
    background.toNimkitColor,
    foreground.kind != celina.Default,
    background.kind != celina.Default,
  )

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

func statusText(status: KosmoStatus, tabs: openArray[KosmoTab]): string =
  var parts: seq[string]
  if status.modeLabel.len > 0:
    parts.add status.modeLabel
  for tab in tabs:
    if tab.active:
      parts.add tab.title
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
  if result.closed and view.usesBufferSubset:
    let bufferIndex = view.bufferIds.find(id)
    if bufferIndex >= 0:
      view.bufferIds.delete(bufferIndex)
    view.removeViewState(id)
    view.selectedBufferId = none(KosmoBufferId)
  elif not result.closed and not view.statusLabel.isNil:
    view.statusLabel.text = result.message

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
    let text = view.editor.status().statusText(tabs)
    if view.statusLabel.text != text:
      view.statusLabel.text = text
  let command = view.editor.commandLine()
  view.syncCommandBar(command)
  let cursor = view.editor.cursor()
  view.setCursorPosition(cursor.row, cursor.column)
  view.cursorVisible = cursor.visible and not command.visible

proc applyKosmoEditorStyle(view: KosmoEditorView, base: nimkit.Appearance) =
  var appearance = base
  let
    selector = nimkit.initStyleSelector(nimkit.srMonoTextView, id = KosmoEditorStyleId)
    previewTabSelector = nimkit.initStyleSelector(
      nimkit.srDocumentTab, classes = @[KosmoPreviewTabStyleClass]
    )
    activeTabSelector = nimkit.initStyleSelector(
      nimkit.srDocumentTab, {nimkit.ssSelected}, classes = @[KosmoActivePaneStyleClass]
    )
    inactiveTabSelector = nimkit.initStyleSelector(
      nimkit.srDocumentTab,
      {nimkit.ssSelected},
      classes = @[KosmoInactivePaneStyleClass],
    )
    activeTabBarSelector = nimkit.initStyleSelector(
      nimkit.srDocumentTabBar, classes = @[KosmoActivePaneStyleClass]
    )
    inactiveTabBarSelector = nimkit.initStyleSelector(
      nimkit.srDocumentTabBar, classes = @[KosmoInactivePaneStyleClass]
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
    activeAccentColor = nimkit.color(
      accentColor.r,
      accentColor.g,
      accentColor.b,
      accentColor.a * KosmoPaneAccentOpacity,
    )
    paneOutlineColor = nimkit.color(
      accentColor.r,
      accentColor.g,
      accentColor.b,
      accentColor.a * KosmoPaneOutlineOpacity,
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
  appearance.setStyle(
    activeTabSelector,
    nimkit.StyleSelectionIndicatorFill,
    nimkit.fill(activeAccentColor),
  )
  appearance.setStyle(
    activeTabSelector, nimkit.StyleSelectionIndicatorSize, KosmoPaneAccentHeight
  )
  appearance.setStyle(inactiveTabSelector, nimkit.StyleFill, normalTabFill)
  appearance.setStyle(inactiveTabSelector, nimkit.StyleTextColor, inactiveTabTextColor)
  appearance.setStyle(
    inactiveTabSelector,
    nimkit.StyleSelectionIndicatorFill,
    nimkit.fill(inactiveAccentColor),
  )
  appearance.setStyle(activeTabBarSelector, nimkit.StyleBorderColor, paneOutlineColor)
  appearance.setStyle(
    activeTabBarSelector, nimkit.StyleBorderWidth, KosmoPaneOutlineWidth
  )
  appearance.setStyle(activeTabBarSelector, nimkit.StyleCornerRadius, 0.0'f32)
  appearance.setStyle(inactiveTabBarSelector, nimkit.StyleCornerRadius, 0.0'f32)
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

protocol KosmoEditorAppearanceObserver of nimkit.WindowAppearanceEvents:
  proc didChangeEffectiveAppearance(
      handler: KosmoEditorTabsHandler, appearance: nimkit.Appearance
  ) {.slot.} =
    if not handler.editorView.isNil:
      handler.editorView[].applyKosmoEditorStyle(appearance)

proc stopObservingAppearance(handler: KosmoEditorTabsHandler) =
  if handler.isNil or handler.appearanceWindow.isNil:
    return
  handler.unobserveProtocol(handler.appearanceWindow[], nimkit.WindowAppearanceEvents)
  handler.appearanceWindow = default(WeakRef[nimkit.Window])

proc observeAppearance(handler: KosmoEditorTabsHandler, window: nimkit.Window) =
  handler.stopObservingAppearance()
  if window.isNil:
    return
  handler.appearanceWindow = window.unsafeWeakRef()
  handler.observeProtocol(window, nimkit.WindowAppearanceEvents)

proc refresh*(view: KosmoEditorView) =
  ## Render the current editor state into the synchronous cell-grid view.
  if (view.editor.completionPopupVisible() or view.editor.commandLine().visible) and
      not view.isActiveEditorGroup():
    return
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
  let tabs = view.visibleTabs(view.editor.tabs())
  view.selectVisibleBuffer(tabs)
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

proc scrollBy*(
    view: KosmoEditorView,
    deltaY: float32,
    row = 0,
    column = 0,
    modifiers: set[nimkit.KeyModifier] = {},
): ScrollOutcome =
  ## Translate fractional wheel input and commit complete physical rows to Moe.
  view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
  view.scrollOffsetRows -= deltaY
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

proc activateGroup(controller: KosmoDockController, view: KosmoEditorView)
proc closeCurrentTab(controller: KosmoDockController, view: KosmoEditorView)
proc finishTabClose(controller: KosmoDockController, view: KosmoEditorView)
proc saveCurrentTab(controller: KosmoDockController, view: KosmoEditorView)
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

proc saveCurrentPaneTab(controller: KosmoDockController, group: KosmoEditorGroup)

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
  of nimkit.mtreFlagsChanged:
    true

protocol KosmoEditorInput of nimkit.TextInputProtocol:
  method insertText(view: KosmoEditorView, text: string) =
    if text.len > 0:
      view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
      discard view.editor.handleTextInput(text)
      view.refresh()

protocol KosmoEditorCommandDispatch of nimkit.ResponderCommandDispatchProtocol:
  method dispatchCommand(view: KosmoEditorView, args: nimkit.TryToPerformArgs): bool =
    if view.tabsDelegate.isNil or view.tabsDelegate.dockController.isNil:
      return false
    let controller = view.tabsDelegate.dockController[]
    case $args.selector.name
    of KosmoSaveAction:
      controller.saveCurrentTab(view)
    of KosmoCloseTabAction:
      controller.closeCurrentTab(view)
    of KosmoQuitAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].application.terminate()
    of KosmoPreviousTabAction:
      controller.selectRelativeTab(view, -1)
    of KosmoNextTabAction:
      controller.selectRelativeTab(view, 1)
    of KosmoFindInFilesAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showFindInFiles()
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

proc newKosmoEditorView*(editor = newKosmoEditor()): KosmoEditorView =
  result = KosmoEditorView(
    editor: editor,
    documentTabs: nimkit.newDocumentTabs(),
    renderBuffer: newRenderBuffer(80, 24),
  )
  result.initMonoTextViewFields(editable = true)
  result.clipsToBounds = true
  result.padding = 0.0'f32
  result.fontName = nimkit.DefaultMonoFontName
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
  discard result.withProtocol(KosmoEditorCommandDispatch)
  result.tabsDelegate = KosmoEditorTabsHandler(editorView: result.unsafeWeakRef())
  discard result.tabsDelegate.withProtocol(KosmoEditorTabsDelegate)
  result.documentTabs.delegate = result.tabsDelegate
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
  result.fontName = view.fontName()
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
      tabContext = nimkit.controlStyle(nimkit.srDocumentTab)
      accent = context.appearance.resolveColor(
        tabContext, nimkit.StyleMarkColor, nimkit.color(0.20, 0.45, 0.92, 1.0)
      )
      accentColor =
        nimkit.color(accent.r, accent.g, accent.b, accent.a * KosmoPaneAccentOpacity)
      outlineColor =
        nimkit.color(accent.r, accent.g, accent.b, accent.a * KosmoPaneOutlineOpacity)
      inset = KosmoPaneOutlineWidth * 0.5'f32
      outlineRect = nimkit.rect(
        bounds.minX + inset,
        bounds.minY + inset,
        max(bounds.size.width - KosmoPaneOutlineWidth, 0.0'f32),
        max(bounds.size.height - KosmoPaneOutlineWidth, 0.0'f32),
      )
      accentRect = nimkit.rect(
        bounds.minX + KosmoPaneOutlineWidth,
        bounds.minY + KosmoPaneOutlineWidth,
        max(bounds.size.width - KosmoPaneOutlineWidth * 2.0'f32, 0.0'f32),
        min(
          KosmoPaneAccentHeight,
          max(bounds.size.height - KosmoPaneOutlineWidth * 2.0'f32, 0.0'f32),
        ),
      )
    discard context.addRenderRectangle(
      context.renderRectFor(outlineRect),
      nimkit.fill(nimkit.color(0.0, 0.0, 0.0, 0.0)),
      outlineColor,
      KosmoPaneOutlineWidth,
      0.0'f32,
    )
    discard context.addRectangle(accentRect, nimkit.fill(accentColor))

protocol KosmoPaneIndicatorHitTesting of nimkit.ViewProtocol:
  method pointInside(indicator: KosmoPaneIndicator, point: nimkit.Point): bool =
    discard indicator
    discard point

proc newKosmoPaneIndicator(): KosmoPaneIndicator =
  result = KosmoPaneIndicator()
  result.initViewFields()
  result.background = nimkit.color(0.0, 0.0, 0.0, 0.0)
  result.hidden = true
  discard result.withProtocol(KosmoPaneIndicatorDrawing)
  discard result.withProtocol(KosmoPaneIndicatorHitTesting)

protocol KosmoEditorPaneLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(pane: KosmoEditorPane) =
    let
      bounds = pane.bounds()
      tabHeight = min(KosmoTabBarHeight, bounds.size.height)
      editorHeight = max(bounds.size.height - KosmoTabBarHeight, 1.0'f32)
      commandBarHeight = min(KosmoCommandBarHeight, editorHeight)
    pane.documentTabs.setFrameFromLayout(
      nimkit.rect(0, 0, bounds.size.width, tabHeight)
    )
    if not pane.contentView.isNil:
      pane.contentView.setFrameFromLayout(
        nimkit.rect(0, tabHeight, bounds.size.width, editorHeight)
      )
    pane.commandBar.setFrameFromLayout(
      nimkit.rect(
        0,
        max(tabHeight, bounds.size.height - commandBarHeight),
        bounds.size.width,
        commandBarHeight,
      )
    )
    pane.activeIndicator.setFrameFromLayout(bounds)
    if pane.contentView == nimkit.View(pane.editorView):
      pane.editorView.refresh()

proc setContentView(pane: KosmoEditorPane, contentView: nimkit.View) =
  if pane.isNil or contentView.isNil or pane.contentView == contentView:
    return
  if pane.contentView.isNil:
    pane.addSubview(contentView, positioned = nimkit.svpBelow)
  elif not pane.replaceSubview(pane.contentView, contentView):
    pane.addSubview(contentView, positioned = nimkit.svpBelow)
  pane.contentView = contentView
  if contentView != nimkit.View(pane.editorView):
    pane.commandBar.hidden = true
  pane.setNeedsLayout()

protocol KosmoEditorPaneCommandDispatch of nimkit.ResponderCommandDispatchProtocol:
  method dispatchCommand(pane: KosmoEditorPane, args: nimkit.TryToPerformArgs): bool =
    if pane.dockGroup.isNil:
      return false
    let group = pane.dockGroup[]
    if group.editorView.tabsDelegate.isNil or
        group.editorView.tabsDelegate.dockController.isNil:
      return false
    let controller = group.editorView.tabsDelegate.dockController[]
    case $args.selector.name
    of KosmoSaveAction:
      controller.saveCurrentPaneTab(group)
    of KosmoCloseTabAction:
      controller.closeCurrentPaneTab(group)
    of KosmoQuitAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].application.terminate()
    of KosmoPreviousTabAction:
      controller.selectRelativePaneTab(group, -1)
    of KosmoNextTabAction:
      controller.selectRelativePaneTab(group, 1)
    of KosmoFindInFilesAction:
      if not controller.frontend.isNil:
        discard controller.frontend[].showFindInFiles()
    else:
      return false
    true

proc newKosmoEditorPane(editorView: KosmoEditorView): KosmoEditorPane =
  let
    commandBar = newKosmoCommandBar(editorView)
    activeIndicator = newKosmoPaneIndicator()
  result = KosmoEditorPane(
    documentTabs: editorView.documentTabs,
    editorView: editorView,
    commandBar: commandBar,
    contentView: editorView,
    activeIndicator: activeIndicator,
  )
  editorView.commandBar = commandBar
  result.initViewFields()
  result.addSubview(result.documentTabs)
  result.addSubview(editorView)
  result.addSubview(commandBar)
  result.addSubview(activeIndicator)
  discard result.withProtocol(KosmoEditorPaneLayout)
  discard result.withProtocol(KosmoEditorPaneCommandDispatch)

proc groupForView(
    controller: KosmoDockController, view: KosmoEditorView
): KosmoEditorGroup =
  for group in controller.groups:
    if group.editorView == view:
      return group

proc groupForTabs(
    controller: KosmoDockController, tabs: nimkit.DocumentTabs
): KosmoEditorGroup =
  for group in controller.groups:
    if group.editorView.documentTabs == tabs:
      return group

proc groupForPanel(
    controller: KosmoDockController, panel: nimkit.DockPanel
): KosmoEditorGroup =
  for group in controller.groups:
    if group.panel == panel:
      return group

proc hostForWorkspace(
    controller: KosmoDockController, workspace: nimkit.DockView
): KosmoDockHost =
  for host in controller.hosts:
    if host.workspace == workspace:
      return host

proc focusedEditorGroup(controller: KosmoDockController): KosmoEditorGroup =
  if controller.isNil or controller.frontend.isNil:
    return
  let window = controller.frontend[].application.keyWindow()
  if window.isNil:
    return
  var responder = window.firstResponder()
  while not responder.isNil:
    for group in controller.groups:
      if responder == nimkit.Responder(group.pane):
        return group
    responder = responder.nextResponder()

proc activePaneGroup(controller: KosmoDockController): KosmoEditorGroup =
  result = controller.focusedEditorGroup()
  if result.isNil:
    result = controller.activeGroup
  if result.isNil and controller.groups.len > 0:
    result = controller.groups[0]

proc activeEditorView(controller: KosmoDockController): KosmoEditorView =
  let group = controller.activePaneGroup()
  if not group.isNil:
    result = group.editorView

proc installShortcutBindings(controller: KosmoDockController, window: nimkit.Window) =
  var bindings = window.keyBindings()
  for command in KosmoShortcutCommands:
    discard bindings.remove(nimkit.actionSelector(command))
  for binding in controller.shortcutBindings.bindings:
    bindings.add(binding.stroke, binding.selector)
  window.setKeyBindings(bindings)

proc activateGroup(controller: KosmoDockController, view: KosmoEditorView) =
  if controller.isNil or view.isNil:
    return
  let group = controller.groupForView(view)
  if not group.isNil:
    if controller.activeGroup != group:
      let previous = controller.activeGroup
      controller.editor.dismissCompletionPopup()
      controller.editor.dismissCommandLine()
      if not previous.isNil:
        previous.editorView.refresh()
    controller.activeGroup = group
    view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
    view.syncChrome()

proc activatePaneTab(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    identifier: string,
    focus = true,
) =
  if controller.isNil or group.isNil:
    return
  group.selectedTabIdentifier = identifier
  controller.activateGroup(group.editorView)
  var id: KosmoBufferId
  if identifier.parseTabIdentifier(id):
    group.pane.setContentView(group.editorView)
    group.editorView.saveViewState()
    group.editorView.editor.dismissCompletionPopup()
    group.editorView.editor.dismissCommandLine()
    group.editorView.selectedBufferId = some(id)
    group.editorView.selectVisibleBuffer(
      group.editorView.visibleTabs(group.editorView.editor.tabs())
    )
    group.editorView.refresh()
    if focus:
      discard group.window.makeFirstResponder(group.editorView)
    return

  let document = group.documentForIdentifier(identifier)
  if document.isNil:
    return
  group.editorView.editor.dismissCompletionPopup()
  group.editorView.editor.dismissCommandLine()
  group.pane.setContentView(document.contentView)
  group.editorView.syncTabs(group.editorView.editor.tabs())
  if not group.editorView.statusLabel.isNil:
    group.editorView.statusLabel.text = document.title
  group.pane.layoutSubtreeIfNeeded()
  if focus and not document.preferredFirstResponder.isNil:
    discard group.window.makeFirstResponder(document.preferredFirstResponder)

proc initialBufferIds(editor: KosmoEditor): seq[KosmoBufferId] =
  for tab in editor.tabs():
    result.add tab.id

proc configureGroupView(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    bufferIds: openArray[KosmoBufferId],
) =
  let view = group.editorView
  view.usesBufferSubset = true
  view.bufferIds = @bufferIds
  view.selectedBufferId =
    if bufferIds.len > 0:
      some(bufferIds[^1])
    else:
      none(KosmoBufferId)
  view.lastTabs.setLen(0)
  view.dockGroup = group.unsafeWeakRef()
  group.pane.dockGroup = group.unsafeWeakRef()
  group.tabOrder.setLen(0)
  for id in bufferIds:
    group.tabOrder.add id.tabIdentifier
  group.selectedTabIdentifier =
    if bufferIds.len > 0:
      bufferIds[^1].tabIdentifier
    else:
      ""
  view.tabsDelegate.dockController = controller.unsafeWeakRef()
  let host = controller.hostForWorkspace(group.workspace)
  if not host.isNil:
    view.statusLabel = host.statusLabel
  if not controller.frontend.isNil:
    view.applyKosmoEditorStyle(controller.frontend[].application.effectiveAppearance())
  view.tabsDelegate.observeAppearance(group.window)
  view.refresh()

proc newEditorGroup(
    controller: KosmoDockController,
    workspace: nimkit.DockView,
    window: nimkit.Window,
    bufferIds: openArray[KosmoBufferId],
    editorView: KosmoEditorView = nil,
    editorPane: KosmoEditorPane = nil,
    addToWorkspace = false,
): KosmoEditorGroup =
  let
    view =
      if editorView.isNil:
        newKosmoEditorView(controller.editor)
      else:
        editorView
    pane =
      if editorPane.isNil:
        newKosmoEditorPane(view)
      else:
        editorPane
    panel = nimkit.newDockPanel(pane)
  inc controller.nextGroupIdentifier
  result = KosmoEditorGroup(
    identifier: "kosmo.group." & $controller.nextGroupIdentifier,
    panel: panel,
    pane: pane,
    editorView: view,
    workspace: workspace,
    window: window,
  )
  controller.groups.add result
  controller.configureGroupView(result, bufferIds)
  if addToWorkspace:
    discard workspace.addPanel(panel)
  if controller.activeGroup.isNil:
    controller.activeGroup = result
  else:
    result.updateActivePaneStyle(false)

proc removeBuffer(group: KosmoEditorGroup, id: KosmoBufferId) =
  let index = group.editorView.bufferIds.find(id)
  if index < 0:
    return
  group.editorView.bufferIds.delete(index)
  group.editorView.removeViewState(id)
  group.editorView.selectedBufferId = none(KosmoBufferId)
  group.editorView.lastTabs.setLen(0)
  let orderIndex = group.tabOrder.find(id.tabIdentifier)
  if orderIndex >= 0:
    group.tabOrder.delete(orderIndex)

proc addBuffer(group: KosmoEditorGroup, id: KosmoBufferId) =
  if id notin group.editorView.bufferIds:
    group.editorView.bufferIds.add id
  group.editorView.selectedBufferId = some(id)
  group.editorView.lastTabs.setLen(0)
  if id.tabIdentifier notin group.tabOrder:
    group.tabOrder.add id.tabIdentifier

proc removeGroup(controller: KosmoDockController, group: KosmoEditorGroup) =
  if group.isNil:
    return
  group.editorView.tabsDelegate.stopObservingAppearance()
  let wasActive = controller.activeGroup == group
  discard group.workspace.removePanel(group.panel)
  let index = controller.groups.find(group)
  if index >= 0:
    controller.groups.delete(index)
  let host = controller.hostForWorkspace(group.workspace)
  if not host.isNil and group.workspace.len == 0 and not host.primary:
    host.window.close()
  if wasActive:
    controller.activeGroup = nil
    for candidate in controller.groups:
      if controller.activeGroup.isNil and candidate.workspace == group.workspace:
        controller.activeGroup = candidate
    if controller.activeGroup.isNil and controller.groups.len > 0:
      controller.activeGroup = controller.groups[0]

proc finishTabClose(controller: KosmoDockController, view: KosmoEditorView) =
  let group = controller.groupForView(view)
  if group.isNil:
    view.refresh()
    return
  if view.bufferIds.len == 0 and group.documents.len == 0 and group.workspace.len > 1:
    let wasActive = controller.activeGroup == group
    controller.removeGroup(group)
    if wasActive and not controller.activeGroup.isNil:
      let replacement = controller.activeGroup
      controller.activateGroup(replacement.editorView)
      discard replacement.window.makeFirstResponder(replacement.editorView)
      replacement.editorView.refresh()
    return
  let selectedItem = view.documentTabs.selectedDocumentTabItem()
  if not selectedItem.isNil:
    controller.activatePaneTab(group, selectedItem.identifier())
    return
  if view.bufferIds.len == 0 and group.documents.len == 0:
    view.adoptActiveBuffer()
  view.lastTabs.setLen(0)
  view.refresh()

proc closeCurrentPaneTab(controller: KosmoDockController, group: KosmoEditorGroup) =
  if controller.isNil or group.isNil:
    return
  controller.activeGroup = group
  group.editorView.editor.dismissCommandLine()
  let index =
    group.pane.documentTabs.indexOfDocumentTabIdentifier(group.selectedTabIdentifier)
  if index >= 0:
    discard group.pane.documentTabs.closeDocumentTabAtIndex(index)
  else:
    group.editorView.refresh()

proc closeCurrentTab(controller: KosmoDockController, view: KosmoEditorView) =
  let group = controller.groupForView(view)
  if not group.isNil:
    controller.closeCurrentPaneTab(group)
    return
  view.editor.dismissCommandLine()
  view.refresh()

proc saveCurrentPaneTab(controller: KosmoDockController, group: KosmoEditorGroup) =
  if controller.isNil or group.isNil:
    return
  let document = group.documentForIdentifier(group.selectedTabIdentifier)
  if not document.isNil:
    controller.activeGroup = group
    discard document.save()
    return
  controller.saveCurrentTab(group.editorView)

proc saveCurrentTab(controller: KosmoDockController, view: KosmoEditorView) =
  controller.activateGroup(view)
  view.selectVisibleBuffer(view.visibleTabs(view.editor.tabs()))
  let outcome = view.editor.save()
  view.lastTabs.setLen(0)
  view.refresh()
  if not outcome.saved and not view.statusLabel.isNil:
    view.statusLabel.text = outcome.message

proc selectRelativeTab(
    controller: KosmoDockController, view: KosmoEditorView, offset: int
) =
  let group = controller.groupForView(view)
  if not group.isNil:
    controller.selectRelativePaneTab(group, offset)
    return
  controller.activateGroup(view)
  let tabs = view.visibleTabs(view.editor.tabs())
  if tabs.len == 0:
    return
  var selectedIndex = 0
  if view.selectedBufferId.isSome:
    for index, tab in tabs:
      if tab.id == view.selectedBufferId.get:
        selectedIndex = index
        break
  let targetIndex = (selectedIndex + offset + tabs.len) mod tabs.len
  discard view.documentTabs.selectDocumentTabWithIdentifier(
    tabs[targetIndex].id.tabIdentifier
  )

proc selectRelativePaneTab(
    controller: KosmoDockController, group: KosmoEditorGroup, offset: int
) =
  if controller.isNil or group.isNil or group.pane.documentTabs.len == 0:
    return
  controller.activeGroup = group
  var selectedIndex =
    group.pane.documentTabs.indexOfDocumentTabIdentifier(group.selectedTabIdentifier)
  if selectedIndex < 0:
    selectedIndex = 0
  let targetIndex =
    (selectedIndex + offset + group.pane.documentTabs.len) mod
    group.pane.documentTabs.len
  discard group.pane.documentTabs.selectDocumentTabAtIndex(targetIndex)

proc finishPaneTabMove(
    controller: KosmoDockController,
    source, target: KosmoEditorGroup,
    identifier: string,
) =
  if source != target:
    var id: KosmoBufferId
    if identifier.parseTabIdentifier(id):
      target.addBuffer(id)
      source.removeBuffer(id)
    else:
      let documentIndex = source.documentIndex(identifier)
      if documentIndex < 0:
        return
      let document = source.documents[documentIndex]
      source.documents.delete(documentIndex)
      let orderIndex = source.tabOrder.find(identifier)
      if orderIndex >= 0:
        source.tabOrder.delete(orderIndex)
      target.documents.add document
      if identifier notin target.tabOrder:
        target.tabOrder.add identifier
    if source.editorView.bufferIds.len == 0 and source.documents.len == 0:
      controller.removeGroup(source)
    else:
      source.editorView.lastTabs.setLen(0)
      source.editorView.refresh()
      let fallback = source.pane.documentTabs.selectedDocumentTabItem()
      if not fallback.isNil:
        controller.activatePaneTab(source, fallback.identifier(), focus = false)
  controller.activeGroup = target
  target.selectedTabIdentifier = identifier
  target.editorView.lastTabs.setLen(0)
  target.editorView.refresh()
  controller.activatePaneTab(target, identifier)

proc screenPoint(tabs: nimkit.DocumentTabs, location: nimkit.Point): nimkit.Point =
  let owner = tabs.window()
  if owner of nimkit.Window:
    return nimkit.Window(owner).convertPointToScreen(tabs.pointToWindow(location))
  tabs.pointToWindow(location)

proc targetAtScreenPoint(
    controller: KosmoDockController, point: nimkit.Point
): tuple[workspace: nimkit.DockView, target: nimkit.DockDropTarget] =
  for host in controller.hosts:
    if not host.window.isNil and not host.window.isClosed():
      let
        windowPoint = host.window.convertPointFromScreen(point)
        workspacePoint = host.workspace.pointFromWindow(windowPoint)
      if host.workspace.bounds().contains(workspacePoint):
        var target = host.workspace.dropTargetAtPoint(workspacePoint)
        if target.valid():
          let group = controller.groupForPanel(target.panel)
          if not group.isNil:
            let tabPoint = group.editorView.documentTabs.pointFromView(
              workspacePoint, host.workspace
            )
            if group.editorView.documentTabs.bounds().contains(tabPoint):
              let panelRect =
                target.panel.rectToView(target.panel.bounds(), host.workspace)
              target = nimkit.DockDropTarget(
                panel: target.panel, position: nimkit.dpCenter, rect: panelRect
              )
          return (host.workspace, target)

proc clearDockTargets(controller: KosmoDockController) =
  for host in controller.hosts:
    host.workspace.clearDropTarget()

proc updateDockTarget(
    controller: KosmoDockController, tabs: nimkit.DocumentTabs, location: nimkit.Point
) =
  if controller.isNil:
    return
  controller.clearDockTargets()
  let resolved = controller.targetAtScreenPoint(tabs.screenPoint(location))
  if not resolved.workspace.isNil and resolved.target.valid():
    resolved.workspace.dropTarget = resolved.target

protocol KosmoDetachedContentLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(content: KosmoDetachedContentView) =
    let bounds = content.bounds()
    content.statusLabel.setFrameFromLayout(
      nimkit.rect(
        0,
        max(bounds.size.height - KosmoStatusBarHeight, 0.0'f32),
        bounds.size.width,
        KosmoStatusBarHeight,
      )
    )
    content.workspace.setFrameFromLayout(
      nimkit.rect(
        0, 0, bounds.size.width, max(bounds.size.height - KosmoStatusBarHeight, 1.0'f32)
      )
    )

proc newKosmoDetachedContentView(
    workspace: nimkit.DockView, statusLabel: nimkit.Label
): KosmoDetachedContentView =
  result = KosmoDetachedContentView(workspace: workspace, statusLabel: statusLabel)
  result.initViewFields()
  result.addSubview(workspace)
  result.addSubview(statusLabel)
  discard result.withProtocol(KosmoDetachedContentLayout)

proc detachPaneTab(
    controller: KosmoDockController,
    source: KosmoEditorGroup,
    identifier: string,
    screenLocation: nimkit.Point,
) =
  if controller.frontend.isNil:
    return
  let
    frontend = controller.frontend[]
    workspace = nimkit.newDockView()
    statusLabel = nimkit.newStatusLabel("Ready")
    contentView = newKosmoDetachedContentView(workspace, statusLabel)
    window = nimkit.newWindow(
      "Kosmo",
      nimkit.rect(screenLocation.x - 360.0'f32, screenLocation.y - 24.0'f32, 720, 520),
    )
    host = KosmoDockHost(
      workspace: workspace,
      window: window,
      contentView: contentView,
      statusLabel: statusLabel,
    )
  controller.hosts.add host
  controller.installShortcutBindings(window)
  var
    id: KosmoBufferId
    bufferIds: seq[KosmoBufferId]
  if identifier.parseTabIdentifier(id):
    bufferIds.add id
  let group =
    controller.newEditorGroup(workspace, window, bufferIds, addToWorkspace = true)
  controller.finishPaneTabMove(source, group, identifier)
  window.setContentView(contentView)
  frontend.application.addWindow(window)
  if frontend.application.isRunning():
    frontend.application.activateWindow(window)

proc finishDockDrag(
    controller: KosmoDockController,
    tabs: nimkit.DocumentTabs,
    item: nimkit.DocumentTabItem,
    location: nimkit.Point,
) =
  if controller.isNil or item.isNil:
    return
  let
    point = tabs.screenPoint(location)
    resolved = controller.targetAtScreenPoint(point)
    source = controller.groupForTabs(tabs)
  controller.clearDockTargets()
  if source.isNil:
    return
  let identifier = item.identifier()
  var id: KosmoBufferId
  if not identifier.parseTabIdentifier(id) and
      source.documentForIdentifier(identifier).isNil:
    return

  if resolved.target.valid():
    let target = controller.groupForPanel(resolved.target.panel)
    if target.isNil:
      return
    if resolved.target.position == nimkit.dpCenter:
      if target != source:
        controller.finishPaneTabMove(source, target, identifier)
    else:
      let bufferIds =
        if identifier.parseTabIdentifier(id):
          @[id]
        else:
          @[]
      let next = controller.newEditorGroup(resolved.workspace, target.window, bufferIds)
      if resolved.workspace.splitPanel(
        target.panel, next.panel, resolved.target.position
      ):
        controller.finishPaneTabMove(source, next, identifier)
      else:
        controller.removeGroup(next)
  else:
    controller.detachPaneTab(source, identifier, point)

proc openPaneDocument(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    document: KosmoPaneDocument,
): bool =
  if controller.isNil or group.isNil or document.isNil or document.identifier.len == 0 or
      document.contentView.isNil:
    return
  var bufferId: KosmoBufferId
  if document.identifier.parseTabIdentifier(bufferId):
    return
  for candidate in controller.groups:
    if not candidate.documentForIdentifier(document.identifier).isNil:
      controller.activatePaneTab(candidate, document.identifier)
      return true
  if document.preferredFirstResponder.isNil:
    document.preferredFirstResponder = document.contentView
  group.documents.add document
  group.tabOrder.add document.identifier
  group.selectedTabIdentifier = document.identifier
  group.editorView.lastTabs.setLen(0)
  group.editorView.refresh()
  controller.activatePaneTab(group, document.identifier)
  true

proc openTerminal(
    controller: KosmoDockController,
    group: KosmoEditorGroup,
    options: nimkit.TerminalSpawnOptions,
): bool =
  if controller.isNil or group.isNil:
    return
  let terminalView = nimkit.newTerminalView()
  try:
    terminalView.start(options)
  except nimkit.TerminalSessionError as error:
    terminalView.close()
    if not group.editorView.statusLabel.isNil:
      group.editorView.statusLabel.text = error.msg
    return

  inc controller.nextDocumentIdentifier
  let document = newKosmoPaneDocument(
    identifier = KosmoTerminalIdentifierPrefix & $controller.nextDocumentIdentifier,
    title = "Terminal " & $controller.nextDocumentIdentifier,
    contentView = terminalView,
    tooltip = "Terminal",
    onClose = proc(document: KosmoPaneDocument): bool =
      discard document
      terminalView.close()
      true,
  )
  if controller.openPaneDocument(group, document):
    return true
  terminalView.close()

protocol KosmoContentLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(content: KosmoContentView) =
    let
      bounds = content.bounds()
      panes = content.splitView.panes()
      splitWidthChanged =
        content.setInitialDivider and
        abs(bounds.size.width - content.lastSplitWidth) > 0.001'f32
    content.statusLabel.setFrameFromLayout(
      nimkit.rect(
        0,
        max(bounds.size.height - KosmoStatusBarHeight, 0.0'f32),
        bounds.size.width,
        KosmoStatusBarHeight,
      )
    )
    content.splitView.setFrameFromLayout(
      nimkit.rect(
        0, 0, bounds.size.width, max(bounds.size.height - KosmoStatusBarHeight, 1.0'f32)
      )
    )
    if not content.setInitialDivider and bounds.size.width > 0.0'f32:
      content.splitView.setPositionOfDivider(0, min(bounds.size.width * 0.25, 260.0))
      content.setInitialDivider = true
    elif splitWidthChanged:
      content.splitView.setPositionOfDivider(0, content.fileTreeWidth)
    content.lastSplitWidth = bounds.size.width
    content.splitView.layoutSubtreeIfNeeded()
    if panes.len > 0:
      content.fileTreeWidth = panes[0].frame().size.width

protocol KosmoContentCommandDispatch of nimkit.ResponderCommandDispatchProtocol:
  method dispatchCommand(
      content: KosmoContentView, args: nimkit.TryToPerformArgs
  ): bool =
    if $args.selector.name != KosmoFindInFilesAction or content.onFindInFiles.isNil:
      return false
    content.onFindInFiles()
    true

proc newKosmoContentView(
    splitView: nimkit.SplitView, statusLabel: nimkit.Label
): KosmoContentView =
  result = KosmoContentView(splitView: splitView, statusLabel: statusLabel)
  result.initViewFields()
  result.addSubview(splitView)
  result.addSubview(statusLabel)
  discard result.withProtocol(KosmoContentLayout)
  discard result.withProtocol(KosmoContentCommandDispatch)

proc openPath(view: KosmoEditorView, tree: KosmoFileTree, path: string): bool =
  if dirExists(path):
    tree.rootPath = path
    if not view.statusLabel.isNil:
      view.statusLabel.text = tree.rootPath
    return true
  result = view.openFile(path)
  if result:
    tree.rootPath = absolutePath(path).parentDir()

proc chooseFile(view: KosmoEditorView, tree: KosmoFileTree, app: nimkit.Application) =
  let panel = nimkit.newOpenPanel()
  panel.message = "Open a text file or folder in Kosmo."
  panel.canChooseDirectories = true
  panel.directoryUrl = tree.rootPath
  if app.runModal(panel) == nimkit.PanelResponseOk:
    discard view.openPath(tree, nimkit.filePathFromUrl(panel.selectedUrl()))

proc showFindInFiles*(frontend: KosmoApplication): bool {.discardable.} =
  ## Select the find sidebar tab and focus its search query.
  if frontend.isNil or frontend.sidebarTabs.isNil or frontend.searchPanel.isNil:
    return
  frontend.searchPanel.rootPath = frontend.fileTree.rootPath
  if not frontend.sidebarTabs.selectCompactTabAtIndex(1):
    return
  result = frontend.searchPanel.focusQuery()

proc newKosmoApplication*(
    app = nimkit.sharedApplication(), filePath = "", keyBindingsPath = ""
): KosmoApplication =
  let existingMainMenu = app.mainMenu()
  if existingMainMenu.isNil or existingMainMenu.len < 5 or
      existingMainMenu[1].title != "File" or existingMainMenu[2].title != "Edit" or
      existingMainMenu[3].title != "Window" or existingMainMenu[4].title != "Help":
    app.installStandardMainMenu()
  let
    editorView = newKosmoEditorView()
    editorPane = newKosmoEditorPane(editorView)
    fileTree = newKosmoFileTree(getCurrentDir())
    searchPanel = newKosmoFileSearchPanel(fileTree.rootPath)
    sidebarTabs = nimkit.newCompactTabView(
      [
        nimkit.initCompactTabItem(
          KosmoFilesTabIdentifier,
          "Files",
          nimkit.newSvgMtsdfResource(KosmoFilesIconSvg, "kosmo-files"),
          fileTree,
        ),
        nimkit.initCompactTabItem(
          KosmoFindTabIdentifier,
          "Find",
          nimkit.newSvgMtsdfResource(KosmoFindIconSvg, "kosmo-find"),
          searchPanel,
        ),
      ]
    )
    splitView = nimkit.newSplitView(nimkit.laHorizontal)
    dockView = nimkit.newDockView()
    mainMenu = app.mainMenu()
    fileMenu = nimkit.newMenu("File")
    fileItem = mainMenu[1]
    openItem = nimkit.newMenuItem(
      "Open…", nimkit.actionSelector(KosmoOpenFileAction), "o", {nimkit.kmCommand}
    )
    terminalItem =
      nimkit.newMenuItem("New Terminal", nimkit.actionSelector(KosmoNewTerminalAction))
  editorView.applyKosmoEditorStyle(app.effectiveAppearance())
  openItem.identifier = KosmoOpenFileAction
  terminalItem.identifier = KosmoNewTerminalAction
  fileItem.submenu = fileMenu
  discard fileMenu.addItem(openItem)
  discard fileMenu.addItem(terminalItem)
  fileMenu.addSeparator()
  discard fileMenu.addItem(
    "Close Window",
    nimkit.actionSelector("performClose"),
    "w",
    nimkit.shortcutModifiers(),
  )

  splitView.addPane(sidebarTabs, minSize = 160.0'f32, maxSize = 420.0'f32)
  splitView.addPane(dockView, minSize = 320.0'f32)

  let
    statusLabel = nimkit.newStatusLabel("Ready")
    documentView = newKosmoContentView(splitView, statusLabel)
    contentView = nimkit.newMenuRootView(mainMenu, documentView)
  editorView.statusLabel = statusLabel
  editorView.syncChrome()
  result = KosmoApplication(
    application: app,
    window: nimkit.newWindow("Kosmo", nimkit.rect(120, 100, 1024, 720)),
    editorView: editorView,
    editorPane: editorPane,
    documentTabs: editorView.documentTabs,
    statusLabel: statusLabel,
    fileTree: fileTree,
    sidebarTabs: sidebarTabs,
    searchPanel: searchPanel,
    splitView: splitView,
    dockView: dockView,
    contentView: contentView,
    documentView: documentView,
  )
  let
    controller = KosmoDockController(
      editor: editorView.editor, shortcutBindings: initKosmoKeyBindings()
    )
    mainHost = KosmoDockHost(
      workspace: dockView,
      window: result.window,
      contentView: contentView,
      statusLabel: statusLabel,
      primary: true,
    )
  result.dockController = controller
  controller.frontend = result.unsafeWeakRef()
  documentView.onFindInFiles = proc() =
    if not controller.frontend.isNil:
      discard controller.frontend[].showFindInFiles()
  controller.hosts.add mainHost
  var keyBindingResult: nimkit.KeyBindingJsonResult
  if keyBindingsPath.len > 0:
    keyBindingResult = controller.shortcutBindings.loadKeyBindingOverridesJson(
      keyBindingsPath, KosmoShortcutCommands
    )
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
  openItem.target = nimkit.newActionTarget(nimkit.actionSelector(KosmoOpenFileAction)) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    if not frontend.isNil:
      frontend[].dockController.activeEditorView().chooseFile(fileTree, app)
      searchPanel.rootPath = fileTree.rootPath
  terminalItem.target = nimkit.newActionTarget(
    nimkit.actionSelector(KosmoNewTerminalAction)
  ) do(sender: nimkit.DynamicAgent):
    discard sender
    if frontend.isNil:
      return
    let
      controller = frontend[].dockController
      group = controller.activePaneGroup()
      options = nimkit.initTerminalSpawnOptions(workingDirectory = fileTree.rootPath)
    discard controller.openTerminal(group, options)
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
  searchPanel.onOpenFile = fileTree.onOpenFile
  if filePath.len > 0:
    discard result.dockController.activeEditorView().openPath(fileTree, filePath)
    searchPanel.rootPath = fileTree.rootPath
  if keyBindingResult.errors.len > 0:
    statusLabel.text = keyBindingResult.errors.join("; ")

proc loadKosmoKeyBindings*(
    frontend: KosmoApplication, path: string
): nimkit.KeyBindingJsonResult =
  ## Reset Kosmo shortcuts to their defaults, then apply overrides from `path`.
  if frontend.isNil or frontend.dockController.isNil:
    result.errors.add "The Kosmo frontend is closed"
    return
  var bindings = initKosmoKeyBindings()
  result = bindings.loadKeyBindingOverridesJson(path, KosmoShortcutCommands)
  frontend.dockController.shortcutBindings = bindings
  for host in frontend.dockController.hosts:
    frontend.dockController.installShortcutBindings(host.window)

proc openPath*(frontend: KosmoApplication, path: string): bool {.discardable.} =
  ## Open a file or replace the file-tree root with a directory.
  if frontend.isNil:
    return
  result = frontend.dockController.activeEditorView().openPath(frontend.fileTree, path)
  if result and not frontend.searchPanel.isNil:
    frontend.searchPanel.rootPath = frontend.fileTree.rootPath

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
  if frontend.isNil:
    return
  if not frontend.dockController.isNil:
    for group in frontend.dockController.groups:
      group.editorView.tabsDelegate.stopObservingAppearance()
      for document in group.documents:
        discard document.close()
    let hosts = frontend.dockController.hosts
    for host in hosts:
      if not host.primary and not host.window.isNil and not host.window.isClosed():
        host.window.close()
  if not frontend.editorView.isNil:
    frontend.editorView.editor.close()
  if not frontend.searchPanel.isNil:
    frontend.searchPanel.close()

proc runKosmo*(filePath = "") =
  ## Run Kosmo as a standalone NimKit text-editor application.
  let keyBindingsPath = defaultKosmoKeyBindingsPath()
  let frontend = newKosmoApplication(
    filePath = filePath,
    keyBindingsPath = if fileExists(keyBindingsPath): keyBindingsPath else: "",
  )
  defer:
    frontend.close()
  frontend.show()
  frontend.application.run()

when isMainModule:
  let filePath =
    if paramCount() > 0:
      paramStr(1)
    else:
      ""
  runKosmo(filePath)
