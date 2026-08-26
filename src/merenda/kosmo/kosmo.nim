## A synchronous NimKit frontend for the Moe editor engine.

import std/[math, options, os, strutils, unicode]

import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ./[filetree, moe]
import pkg/celina as celina

export filetree, moe

const
  KosmoOpenFileAction* = "kosmo.openFile"
  KosmoSaveAction* = "kosmo.save"
  KosmoCloseTabAction* = "kosmo.closeTab"
  KosmoQuitAction* = "kosmo.quit"
  KosmoPreviousTabAction* = "kosmo.previousTab"
  KosmoNextTabAction* = "kosmo.nextTab"
  KosmoTabBarHeight* = 34.0'f32
  KosmoStatusBarHeight* = 22.0'f32
  KosmoCommandBarHeight* = 24.0'f32
  KosmoEditorStyleId* = "kosmo.editor"
  KosmoPreviewTabStyleClass* = "kosmo-preview"
  KosmoCursorOpacity = 0.45'f32
  KosmoGridOverscanRows = 1
  KosmoMoeBottomAreaRows = 1
  KosmoTabIdentifierPrefix = "kosmo.buffer."
  KosmoShortcutCommands = [
    KosmoSaveAction, KosmoCloseTabAction, KosmoQuitAction, KosmoPreviousTabAction,
    KosmoNextTabAction,
  ]

type
  KosmoCommandBar* = ref object of nimkit.MonoTextView

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

  KosmoEditorPane* = ref object of nimkit.View
    documentTabs*: nimkit.DocumentTabs
    editorView*: KosmoEditorView
    commandBar*: KosmoCommandBar

  KosmoEditorGroup* = ref object
    identifier*: string
    panel*: nimkit.DockPanel
    pane*: KosmoEditorPane
    editorView*: KosmoEditorView
    workspace*: nimkit.DockView
    window*: nimkit.Window

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
    activeGroup: KosmoEditorGroup
    nextGroupIdentifier: int
    shortcutBindings: nimkit.KeyBindingTable

  KosmoContentView = ref object of nimkit.View
    splitView: nimkit.SplitView
    statusLabel: nimkit.Label
    setInitialDivider: bool
    lastSplitWidth: float32
    fileTreeWidth: float32

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
    splitView*: nimkit.SplitView
    dockView*: nimkit.DockView
    contentView*: nimkit.MenuRootView
    documentView: KosmoContentView
    dockController: KosmoDockController

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
      view.lastTabs.setLen(0)
      return

proc syncTabs(view: KosmoEditorView, tabs: seq[KosmoTab]) =
  let visibleTabs = view.visibleTabs(tabs)
  if view.documentTabs.isNil or visibleTabs == view.lastTabs:
    return
  var models: seq[nimkit.DocumentTabModel]
  for tab in visibleTabs:
    let styleClasses =
      if tab.temporary:
        @[KosmoPreviewTabStyleClass]
      else:
        @[]
    models.add nimkit.initDocumentTabModel(
      identifier = tab.id.tabIdentifier,
      title = tab.title,
      closeable = true,
      modified = tab.modified,
      styleClasses = styleClasses,
      tooltip = tab.filePath.get(tab.title),
    )
  view.syncingTabs = true
  defer:
    view.syncingTabs = false
  view.documentTabs.documentTabModels = models
  if view.usesBufferSubset and view.selectedBufferId.isSome:
    view.documentTabs.selectedDocumentTabIdentifier =
      view.selectedBufferId.get.tabIdentifier
  else:
    for tab in visibleTabs:
      if tab.active:
        view.documentTabs.selectedDocumentTabIdentifier = tab.id.tabIdentifier
        break
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
  let selector =
    nimkit.initStyleSelector(nimkit.srMonoTextView, id = KosmoEditorStyleId)
  let previewTabSelector = nimkit.initStyleSelector(
    nimkit.srDocumentTab, classes = @[KosmoPreviewTabStyleClass]
  )
  let cursorColor =
    base.resolveMonoTextStyle(nimkit.controlStyle(nimkit.srMonoTextView)).cursorColor
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
  view.styleId = KosmoEditorStyleId
  view.appearance = appearance
  if not view.documentTabs.isNil:
    view.documentTabs.appearance = appearance
  if not view.commandBar.isNil:
    view.commandBar.appearance = appearance

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
    if not item.identifier.parseTabIdentifier(id):
      return
    let outcome = view.closeTab(id)
    outcome.closed

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
    if item.identifier.parseTabIdentifier(id):
      if view.usesBufferSubset:
        let fromBufferIndex = view.bufferIds.find(id)
        if fromBufferIndex >= 0:
          view.bufferIds.delete(fromBufferIndex)
          view.bufferIds.insert(id, min(toIndex, view.bufferIds.len))
          view.syncEditorTabOrder()
      elif not view.editor.moveTab(id, toIndex.Natural):
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
    pane.editorView.setFrameFromLayout(
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
    pane.editorView.refresh()

proc newKosmoEditorPane(editorView: KosmoEditorView): KosmoEditorPane =
  let commandBar = newKosmoCommandBar(editorView)
  result = KosmoEditorPane(
    documentTabs: editorView.documentTabs,
    editorView: editorView,
    commandBar: commandBar,
  )
  editorView.commandBar = commandBar
  result.initViewFields()
  result.addSubview(result.documentTabs)
  result.addSubview(editorView)
  result.addSubview(commandBar)
  discard result.withProtocol(KosmoEditorPaneLayout)

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

proc activeEditorView(controller: KosmoDockController): KosmoEditorView =
  if not controller.activeGroup.isNil:
    return controller.activeGroup.editorView
  if controller.groups.len > 0:
    return controller.groups[0].editorView

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
  view.tabsDelegate.dockController = controller.unsafeWeakRef()
  let host = controller.hostForWorkspace(group.workspace)
  if not host.isNil:
    view.statusLabel = host.statusLabel
  if not controller.frontend.isNil:
    view.applyKosmoEditorStyle(controller.frontend[].application.effectiveAppearance())
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

proc removeBuffer(group: KosmoEditorGroup, id: KosmoBufferId) =
  let index = group.editorView.bufferIds.find(id)
  if index < 0:
    return
  group.editorView.bufferIds.delete(index)
  group.editorView.removeViewState(id)
  group.editorView.selectedBufferId = none(KosmoBufferId)
  group.editorView.lastTabs.setLen(0)

proc addBuffer(group: KosmoEditorGroup, id: KosmoBufferId) =
  if id notin group.editorView.bufferIds:
    group.editorView.bufferIds.add id
  group.editorView.selectedBufferId = some(id)
  group.editorView.lastTabs.setLen(0)

proc removeGroup(controller: KosmoDockController, group: KosmoEditorGroup) =
  if group.isNil:
    return
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
  if view.bufferIds.len == 0 and group.workspace.len > 1:
    let wasActive = controller.activeGroup == group
    controller.removeGroup(group)
    if wasActive and not controller.activeGroup.isNil:
      let replacement = controller.activeGroup
      controller.activateGroup(replacement.editorView)
      discard replacement.window.makeFirstResponder(replacement.editorView)
      replacement.editorView.refresh()
    return
  if view.bufferIds.len == 0:
    view.adoptActiveBuffer()
  view.lastTabs.setLen(0)
  view.refresh()

proc closeCurrentTab(controller: KosmoDockController, view: KosmoEditorView) =
  let tabs = view.visibleTabs(view.editor.tabs())
  var id = none(KosmoBufferId)
  if view.selectedBufferId.isSome:
    for tab in tabs:
      if tab.id == view.selectedBufferId.get:
        id = view.selectedBufferId
        break
  if id.isNone:
    for tab in tabs:
      if tab.active:
        id = some(tab.id)
        break
  if id.isNone and tabs.len > 0:
    id = some(tabs[^1].id)
  view.editor.dismissCommandLine()
  if id.isNone:
    view.refresh()
    return
  let outcome = view.closeTab(id.get)
  if outcome.closed:
    controller.finishTabClose(view)
  else:
    view.refresh()

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

proc finishBufferMove(
    controller: KosmoDockController, source, target: KosmoEditorGroup, id: KosmoBufferId
) =
  if source != target:
    target.addBuffer(id)
    source.removeBuffer(id)
    if source.editorView.bufferIds.len == 0:
      controller.removeGroup(source)
    else:
      source.editorView.refresh()
  controller.activeGroup = target
  target.editorView.selectVisibleBuffer(
    target.editorView.visibleTabs(target.editorView.editor.tabs())
  )
  target.editorView.refresh()

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

proc detachBuffer(
    controller: KosmoDockController,
    source: KosmoEditorGroup,
    id: KosmoBufferId,
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
  let group = controller.newEditorGroup(workspace, window, [id], addToWorkspace = true)
  controller.finishBufferMove(source, group, id)
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
  var id: KosmoBufferId
  if not item.identifier().parseTabIdentifier(id):
    return

  if resolved.target.valid():
    let target = controller.groupForPanel(resolved.target.panel)
    if target.isNil:
      return
    if resolved.target.position == nimkit.dpCenter:
      if target != source:
        controller.finishBufferMove(source, target, id)
    else:
      let next = controller.newEditorGroup(resolved.workspace, target.window, [id])
      if resolved.workspace.splitPanel(
        target.panel, next.panel, resolved.target.position
      ):
        controller.finishBufferMove(source, next, id)
      else:
        controller.removeGroup(next)
  else:
    controller.detachBuffer(source, id, point)

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

proc newKosmoContentView(
    splitView: nimkit.SplitView, statusLabel: nimkit.Label
): KosmoContentView =
  result = KosmoContentView(splitView: splitView, statusLabel: statusLabel)
  result.initViewFields()
  result.addSubview(splitView)
  result.addSubview(statusLabel)
  discard result.withProtocol(KosmoContentLayout)

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
  if app.runModal(panel) == nimkit.PanelResponseOk:
    discard view.openPath(tree, nimkit.filePathFromUrl(panel.selectedUrl()))

proc newKosmoApplication*(
    app = nimkit.sharedApplication(), filePath = "", keyBindingsPath = ""
): KosmoApplication =
  let
    editorView = newKosmoEditorView()
    editorPane = newKosmoEditorPane(editorView)
    fileTree = newKosmoFileTree(getCurrentDir())
    splitView = nimkit.newSplitView(nimkit.laHorizontal)
    dockView = nimkit.newDockView()
    mainMenu = nimkit.newMenu("Main")
    fileMenu = nimkit.newMenu("File")
    fileItem = nimkit.newMenuItem("File")
    openItem = nimkit.newMenuItem(
      "Open…", nimkit.actionSelector(KosmoOpenFileAction), "o", {nimkit.kmCommand}
    )
  editorView.applyKosmoEditorStyle(app.effectiveAppearance())
  openItem.identifier = KosmoOpenFileAction
  fileItem.submenu = fileMenu
  discard fileMenu.addItem(openItem)
  discard mainMenu.addItem(fileItem)
  app.mainMenu = mainMenu

  splitView.addPane(fileTree, minSize = 160.0'f32, maxSize = 420.0'f32)
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
  if filePath.len > 0:
    discard result.dockController.activeEditorView().openPath(fileTree, filePath)
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
  frontend.dockController.activeEditorView().openPath(frontend.fileTree, path)

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
    let hosts = frontend.dockController.hosts
    for host in hosts:
      if not host.primary and not host.window.isNil and not host.window.isClosed():
        host.window.close()
  if not frontend.editorView.isNil:
    frontend.editorView.editor.close()

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
