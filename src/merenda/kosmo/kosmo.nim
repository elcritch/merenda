## A synchronous NimKit frontend for the Moe editor engine.

import std/[math, os, strutils]

import ../nimkit as nimkit
import ./[filetree, moe]
import pkg/celina as celina

export filetree, moe

const KosmoOpenFileAction* = "kosmo.openFile"

type
  KosmoEditorView* = ref object of nimkit.MonoTextView
    editor*: KosmoEditor
    renderBuffer: RenderBuffer
    statusLabel: nimkit.Label
    scrollRemainder: float32

  KosmoContentView = ref object of nimkit.View
    splitView: nimkit.SplitView
    editorView: KosmoEditorView
    statusLabel: nimkit.Label
    setInitialDivider: bool

  KosmoApplication* = ref object
    application*: nimkit.Application
    window*: nimkit.Window
    editorView*: KosmoEditorView
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
  view.setGridSize(rows, columns)
  view.editor.render(view.renderBuffer)
  for row in 0 ..< rows:
    var cells = newSeq[nimkit.MonoTextCell](columns)
    for column in 0 ..< columns:
      cells[column] = view.renderBuffer.cell(column, row).toMonoTextCell
    view.replaceCells(row, 0, cells)

proc openFile*(view: KosmoEditorView, path: string): bool {.discardable.} =
  ## Load a file selected by the frontend and refresh the cell grid.
  let outcome = view.editor.openFile(path)
  if outcome.loaded:
    if not view.statusLabel.isNil:
      view.statusLabel.text = path
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

proc newKosmoEditorView*(editor = newKosmoEditor()): KosmoEditorView =
  result = KosmoEditorView(editor: editor, renderBuffer: newRenderBuffer(80, 24))
  result.initMonoTextViewFields(editable = true)
  result.padding = 0.0'f32
  result.fontName = nimkit.DefaultMonoFontName
  result.fontSize = 14.0'f32
  result.textColor = nimkit.color(0.88, 0.9, 0.94, 1.0)
  result.backgroundColor = nimkit.color(0.04, 0.05, 0.07, 1.0)
  result.rawEventPolicy =
    nimkit.initMonoTextRawEventPolicy(capturedEvents = nimkit.AllMonoTextRawEvents)
  let editorView = result
  result.rawEventHandler = proc(event: nimkit.MonoTextRawEvent): bool =
    editorView.handleRawEvent(event)

protocol KosmoContentLayout of nimkit.ViewLayoutProtocol:
  method layoutSubviews(content: KosmoContentView) =
    let bounds = content.bounds()
    const statusHeight = 22.0'f32
    content.statusLabel.frame = nimkit.rect(
      0,
      max(bounds.size.height - statusHeight, 0.0'f32),
      bounds.size.width,
      statusHeight,
    )
    content.splitView.frame = nimkit.rect(
      0, 0, bounds.size.width, max(bounds.size.height - statusHeight, 1.0'f32)
    )
    if not content.setInitialDivider and bounds.size.width > 0.0'f32:
      content.splitView.setPositionOfDivider(0, min(bounds.size.width * 0.25, 260.0))
      content.setInitialDivider = true
    content.splitView.layoutSubtreeIfNeeded()
    content.editorView.refresh()

proc newKosmoContentView(
    splitView: nimkit.SplitView, editorView: KosmoEditorView, statusLabel: nimkit.Label
): KosmoContentView =
  result = KosmoContentView(
    splitView: splitView, editorView: editorView, statusLabel: statusLabel
  )
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
    fileTree = newKosmoFileTree(getCurrentDir())
    splitView = nimkit.newSplitView(nimkit.laHorizontal)
    mainMenu = nimkit.newMenu("Main")
    fileMenu = nimkit.newMenu("File")
    fileItem = nimkit.newMenuItem("File")
    openItem = nimkit.newMenuItem(
      "Open…", nimkit.actionSelector(KosmoOpenFileAction), "o", {nimkit.kmCommand}
    )
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
  splitView.addPane(editorView, minSize = 320.0'f32)

  let
    statusLabel = nimkit.newStatusLabel("Ready")
    documentView = newKosmoContentView(splitView, editorView, statusLabel)
    contentView = nimkit.newMenuRootView(mainMenu, documentView)
  editorView.statusLabel = statusLabel
  result = KosmoApplication(
    application: app,
    window: nimkit.newWindow("Kosmo", nimkit.rect(120, 100, 1024, 720)),
    editorView: editorView,
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
