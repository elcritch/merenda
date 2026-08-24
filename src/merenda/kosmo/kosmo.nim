## A synchronous NimKit frontend for the Moe editor engine.

import std/[math, os, strutils]

import ../nimkit as nimkit
from ../nimkit/view/viewgeometry import setFrameFromLayout
import ./[filetree, moe]
import pkg/celina as celina

export filetree, moe

const
  KosmoOpenFileAction* = "kosmo.openFile"
  KosmoTabBarHeight* = 34.0'f32
  KosmoStatusBarHeight* = 22.0'f32
  KosmoEditorStyleId* = "kosmo.editor"
  KosmoCursorOpacity = 0.45'f32
  KosmoTabIdentifierPrefix = "kosmo.buffer."

type
  KosmoEditorView* = ref object of nimkit.MonoTextView
    editor*: KosmoEditor
    documentTabs*: nimkit.DocumentTabs
    renderBuffer: RenderBuffer
    statusLabel: nimkit.Label
    scrollRemainder: float32
    lastTabs: seq[KosmoTab]
    syncingTabs: bool
    tabsDelegate: KosmoEditorTabsHandler

  KosmoEditorTabsHandler = ref object of nimkit.Responder
    editorView: WeakRef[KosmoEditorView]

  KosmoEditorPane* = ref object of nimkit.View
    documentTabs*: nimkit.DocumentTabs
    editorView*: KosmoEditorView

  KosmoContentView = ref object of nimkit.View
    splitView: nimkit.SplitView
    statusLabel: nimkit.Label
    setInitialDivider: bool

  KosmoApplication* = ref object
    application*: nimkit.Application
    window*: nimkit.Window
    editorView*: KosmoEditorView
    editorPane*: KosmoEditorPane
    documentTabs*: nimkit.DocumentTabs
    statusLabel*: nimkit.Label
    fileTree*: KosmoFileTree
    splitView*: nimkit.SplitView
    contentView*: nimkit.MenuRootView
    documentView: KosmoContentView

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

proc syncTabs(view: KosmoEditorView, tabs: seq[KosmoTab]) =
  if view.documentTabs.isNil or tabs == view.lastTabs:
    return
  var models: seq[nimkit.DocumentTabModel]
  for tab in tabs:
    models.add nimkit.initDocumentTabModel(
      identifier = tab.id.tabIdentifier,
      title = tab.title,
      closeable = true,
      modified = tab.modified,
      tooltip = tab.filePath.get(tab.title),
    )
  view.syncingTabs = true
  defer:
    view.syncingTabs = false
  view.documentTabs.documentTabModels = models
  for tab in tabs:
    if tab.active:
      view.documentTabs.selectedDocumentTabIdentifier = tab.id.tabIdentifier
      break
  view.lastTabs = tabs

proc syncChrome(view: KosmoEditorView) =
  let tabs = view.editor.tabs()
  view.syncTabs(tabs)
  if not view.statusLabel.isNil:
    let text = view.editor.status().statusText(tabs)
    if view.statusLabel.text != text:
      view.statusLabel.text = text
  let cursor = view.editor.cursor()
  view.setCursorPosition(cursor.row, cursor.column)
  view.cursorVisible = cursor.visible

proc applyKosmoEditorStyle(view: KosmoEditorView, base: nimkit.Appearance) =
  var appearance = base
  let selector =
    nimkit.initStyleSelector(nimkit.srMonoTextView, id = KosmoEditorStyleId)
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
  view.styleId = KosmoEditorStyleId
  view.appearance = appearance

proc refresh*(view: KosmoEditorView) =
  ## Render the current editor state into the synchronous cell-grid view.
  let metrics = view.monoTextMetrics()
  if metrics.cellWidth <= 0.0'f32 or metrics.lineHeight <= 0.0'f32:
    return
  let
    bounds = view.bounds()
    columns = max(int(bounds.size.width / metrics.cellWidth), 1)
    rows = max(int(bounds.size.height / metrics.lineHeight), 1)
  if view.renderBuffer.width != columns or view.renderBuffer.height != rows:
    view.renderBuffer.resize(columns.Natural, rows.Natural)
  view.editor.render(view.renderBuffer)
  var cells = newSeq[nimkit.MonoTextCell](rows * columns)
  for row in 0 ..< rows:
    for column in 0 ..< columns:
      cells[row * columns + column] = view.renderBuffer.cell(column, row).toMonoTextCell
  view.replaceGrid(rows, columns, cells)
  view.syncChrome()

proc openFile*(view: KosmoEditorView, path: string): bool {.discardable.} =
  ## Load a file selected by the frontend and refresh the cell grid.
  let outcome = view.editor.openFile(path)
  if outcome.loaded:
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
  ## Accumulate a wheel/trackpad delta and dispatch complete physical rows to Moe.
  view.scrollRemainder -= deltaY
  let rows =
    if view.scrollRemainder >= 1.0'f32:
      int(floor(view.scrollRemainder))
    elif view.scrollRemainder <= -1.0'f32:
      int(ceil(view.scrollRemainder))
    else:
      0
  if rows == 0:
    return
  view.scrollRemainder -= rows.float32
  result = view.editor.handleScrollInput(
    initScrollInput(row, column, rows, modifiers.toMoeModifiers)
  )
  view.refresh()

proc handleRawEvent(view: KosmoEditorView, event: nimkit.MonoTextRawEvent): bool =
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
    if keyEvent.text.len > 0 and keyEvent.modifiers - {nimkit.kmShift} == {}:
      discard view.editor.handleTextInput(keyEvent.text)
    else:
      let notation = keyEvent.keyNotation()
      if notation.len > 0:
        discard view.editor.handleKey(notation)
    view.refresh()
    true
  of nimkit.mtreFlagsChanged:
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
      if not view.editor.selectTab(id):
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
    let outcome = view.editor.closeTab(id)
    if not outcome.closed and not view.statusLabel.isNil:
      view.statusLabel.text = outcome.message
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
      view.refresh()

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
    if not item.identifier.parseTabIdentifier(id) or
        not view.editor.moveTab(id, toIndex.Natural):
      view.lastTabs.setLen(0)
    view.refresh()

proc newKosmoEditorView*(editor = newKosmoEditor()): KosmoEditorView =
  result = KosmoEditorView(
    editor: editor,
    documentTabs: nimkit.newDocumentTabs(),
    renderBuffer: newRenderBuffer(80, 24),
  )
  result.initMonoTextViewFields(editable = true)
  result.padding = 0.0'f32
  result.fontName = nimkit.DefaultMonoFontName
  result.fontSize = 14.0'f32
  result.textColor = nimkit.color(0.88, 0.9, 0.94, 1.0)
  result.backgroundColor = nimkit.color(0.04, 0.05, 0.07, 1.0)
  result.applyKosmoEditorStyle(result.effectiveAppearance())
  result.rawEventPolicy =
    nimkit.initMonoTextRawEventPolicy(capturedEvents = nimkit.AllMonoTextRawEvents)
  let editorView = result
  result.rawEventHandler = proc(event: nimkit.MonoTextRawEvent): bool =
    editorView.handleRawEvent(event)
  result.tabsDelegate = KosmoEditorTabsHandler(editorView: result.unsafeWeakRef())
  discard result.tabsDelegate.withProtocol(KosmoEditorTabsDelegate)
  result.documentTabs.delegate = result.tabsDelegate
  result.syncChrome()

protocol KosmoEditorPaneLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(pane: KosmoEditorPane) =
    let bounds = pane.bounds()
    pane.documentTabs.setFrameFromLayout(
      nimkit.rect(0, 0, bounds.size.width, min(KosmoTabBarHeight, bounds.size.height))
    )
    pane.editorView.setFrameFromLayout(
      nimkit.rect(
        0,
        min(KosmoTabBarHeight, bounds.size.height),
        bounds.size.width,
        max(bounds.size.height - KosmoTabBarHeight, 1.0'f32),
      )
    )
    pane.editorView.refresh()

proc newKosmoEditorPane(editorView: KosmoEditorView): KosmoEditorPane =
  result =
    KosmoEditorPane(documentTabs: editorView.documentTabs, editorView: editorView)
  result.initViewFields()
  result.addSubview(result.documentTabs)
  result.addSubview(editorView)
  discard result.withProtocol(KosmoEditorPaneLayout)

protocol KosmoContentLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(content: KosmoContentView) =
    let bounds = content.bounds()
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
    content.splitView.layoutSubtreeIfNeeded()

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
    app = nimkit.sharedApplication(), filePath = ""
): KosmoApplication =
  let
    editorView = newKosmoEditorView()
    editorPane = newKosmoEditorPane(editorView)
    fileTree = newKosmoFileTree(getCurrentDir())
    splitView = nimkit.newSplitView(nimkit.laHorizontal)
    mainMenu = nimkit.newMenu("Main")
    fileMenu = nimkit.newMenu("File")
    fileItem = nimkit.newMenuItem("File")
    openItem = nimkit.newMenuItem(
      "Open…", nimkit.actionSelector(KosmoOpenFileAction), "o", {nimkit.kmCommand}
    )
  editorView.applyKosmoEditorStyle(app.effectiveAppearance())
  openItem.identifier = KosmoOpenFileAction
  openItem.target = nimkit.newActionTarget(nimkit.actionSelector(KosmoOpenFileAction)) do(
    sender: nimkit.DynamicAgent
  ):
    discard sender
    editorView.chooseFile(fileTree, app)
  fileItem.submenu = fileMenu
  discard fileMenu.addItem(openItem)
  discard mainMenu.addItem(fileItem)
  app.mainMenu = mainMenu

  fileTree.onOpenFile = proc(path: string) =
    discard editorView.openFile(path)
  splitView.addPane(fileTree, minSize = 160.0'f32, maxSize = 420.0'f32)
  splitView.addPane(editorPane, minSize = 320.0'f32)

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
    contentView: contentView,
    documentView: documentView,
  )
  if filePath.len > 0:
    discard editorView.openPath(fileTree, filePath)

proc openPath*(frontend: KosmoApplication, path: string): bool {.discardable.} =
  ## Open a file or replace the file-tree root with a directory.
  if frontend.isNil:
    return
  frontend.editorView.openPath(frontend.fileTree, path)

proc show*(frontend: KosmoApplication) =
  ## Present the Kosmo window and make the editor its first responder.
  if not frontend.isNil:
    discard frontend.application.showWindow(
      frontend.window, frontend.contentView, frontend.editorView
    )

proc close*(frontend: KosmoApplication) =
  ## Release the editor resources held by the frontend.
  if not frontend.isNil and not frontend.editorView.isNil:
    frontend.editorView.editor.close()

proc runKosmo*(filePath = "") =
  ## Run Kosmo as a standalone NimKit text-editor application.
  let frontend = newKosmoApplication(filePath = filePath)
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
