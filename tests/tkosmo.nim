import std/[os, strutils, tempfiles, unittest]

import merenda/nimkit
import merenda/nimkit/text/monotextviews as monoTextViews
import merenda/kosmo/kosmo

proc renderedText(buffer: RenderBuffer): string =
  for row in 0 ..< buffer.height:
    for column in 0 ..< buffer.width:
      result.add buffer.cell(column, row).symbol
    result.add '\n'

proc numberedLines(prefix: string, count: Natural): string =
  var lines = newSeqOfCap[string](count)
  for index in 0 ..< count:
    lines.add prefix & " row " & $index
  lines.join("\n")

proc displayedText(view: KosmoEditorView): string =
  monoTextViews.stringValue(MonoTextView(view))

suite "Kosmo":
  test "renders initial text into a cell grid":
    let editor = newKosmoEditor(text = "hello")
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    check "hello" in buffer.renderedText
    check "NORMAL" notin buffer.renderedText
    check "No Name" notin buffer.renderedText
    editor.close()

  test "text input and physical keys use Moe's frontend API":
    let editor = newKosmoEditor()
    var buffer = newRenderBuffer(24, 8)

    check editor.handleKey("i")
    check editor.handleTextInput("λ")
    check editor.handleKey("Esc")
    check not editor.handleKey("S-'")
    editor.render(buffer)

    check "λ" in buffer.renderedText
    editor.close()

  test "native shifted text enters Moe command mode without invalid key notation":
    let frontend = newKosmoApplication(newApplication("Kosmo Command Input Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)

    check not frontend.window.dispatchKeyDown(
      KeyEvent(key: keyQuote, keyCode: keyQuote.ord, modifiers: {kmShift})
    )
    check frontend.window.dispatchTextInput("\"")
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyEscape, keyCode: keyEscape.ord)
    )

    check not frontend.window.dispatchKeyDown(
      KeyEvent(key: keySemicolon, keyCode: keySemicolon.ord, modifiers: {kmShift})
    )
    check frontend.window.dispatchTextInput(":")
    check "COMMAND" in frontend.statusLabel.text
    check frontend.editorView.editor.commandLine().visible
    check not frontend.editorPane.commandBar.hidden()
    check frontend.editorPane.commandBar.frame().maxY ==
      frontend.editorPane.bounds().maxY
    check frontend.editorPane.commandBar.frame().minY >= frontend.editorView.frame().minY
    check frontend.window.dispatchTextInput("set number")
    check ":set number" in frontend.editorView.displayedText()
    check ":set number" in
      monoTextViews.stringValue(MonoTextView(frontend.editorPane.commandBar))
    check frontend.window.dispatchKeyDown(
      KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
    )
    check not frontend.editorView.editor.commandLine().visible
    check frontend.editorPane.commandBar.hidden()
    check "NORMAL" in frontend.statusLabel.text
    check "number" in frontend.statusLabel.text

  test "scroll input reports a frontend-neutral outcome":
    let editor = newKosmoEditor(text = "one\ntwo\nthree")
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    let outcome = editor.handleScrollInput(initScrollInput(2, 2, 1))
    check outcome.requestedRows == 1
    check outcome.region.rows >= 0
    check outcome.region.columns >= 0
    editor.close()

  test "fractional wheel deltas accumulate into physical rows":
    var lines: seq[string]
    for index in 0 ..< 40:
      lines.add "line " & $index
    let
      editor = newKosmoEditor(text = lines.join("\n"))
      view = newKosmoEditorView(editor)
    view.frame = rect(0, 0, 240, 120)
    view.refresh()

    for _ in 0 ..< 3:
      let outcome = view.scrollBy(-0.25'f32, row = 2, column = 2)
      check outcome.handled
      check outcome.requestedRows == 0
      check view.gridOffset.y < 0.0'f32
    let outcome = view.scrollBy(-0.25'f32, row = 2, column = 2)
    check outcome.handled
    check outcome.requestedRows == 1
    check outcome.appliedRows == 1
    check view.gridOffset.y == 0.0'f32
    check not editor.cursor().visible
    check not view.cursorVisible

    let
      toBottom = view.scrollBy(-100.0'f32, row = 2, column = 2)
      pastBottom = view.scrollBy(-1.0'f32, row = 2, column = 2)
    check toBottom.appliedRows > 0
    check pastBottom.handled
    check pastBottom.appliedRows == 0
    check not editor.cursor().visible
    check not view.cursorVisible
    editor.close()

  test "editor grid overscans partial rows and columns":
    let
      editor = newKosmoEditor(text = "one\ntwo\nthree\nfour\nfive")
      view = newKosmoEditorView(editor)
      metrics = view.monoTextMetrics()
    view.frame = rect(0, 0, metrics.cellWidth * 5.5'f32, metrics.lineHeight * 3.5'f32)
    view.refresh()

    check view.maxColumnCount == 6
    check view.lineCount == 6
    check view.clipsToBounds
    editor.close()

  test "editor view follows Moe's rendered cursor position":
    let
      editor = newKosmoEditor(text = "hello")
      view = newKosmoEditorView(editor)
    view.frame = rect(0, 0, 240, 120)
    view.refresh()

    var cursor = editor.cursor()
    let initialColumn = cursor.column
    check cursor.visible
    check initialColumn > 0
    check view.cursorRow == cursor.row
    check view.cursorColumn == cursor.column
    check view.cursorVisible == cursor.visible

    check editor.handleKey("h")
    view.refresh()
    cursor = editor.cursor()
    check view.cursorColumn == cursor.column
    check view.cursorColumn < initialColumn
    editor.close()

  test "opens a file through the Moe facade":
    let path = getTempDir() / "merenda-kosmo-open-file.txt"
    writeFile(path, "opened from disk")
    defer:
      if fileExists(path):
        removeFile(path)

    let editor = newKosmoEditor()
    let outcome = editor.openFile(path)
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    check outcome.loaded
    check "opened from disk" in buffer.renderedText
    editor.close()

  test "facade exposes ordered tabs and rejects closing modified buffers":
    let
      root = createTempDir("merenda-kosmo-tabs-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let editor = newKosmoEditor()
    check editor.openFile(firstPath).loaded
    check editor.openFile(secondPath).loaded

    var tabs = editor.tabs()
    check tabs.len == 2
    check tabs[0].title == "first.txt"
    check tabs[1].title == "second.txt"
    check tabs[1].active
    check editor.selectTab(tabs[0].id)
    check editor.tabs()[0].active
    check editor.moveTab(tabs[1].id, 0)
    tabs = editor.tabs()
    check tabs[0].title == "second.txt"

    check editor.selectTab(tabs[1].id)
    check editor.handleKey("i")
    check editor.handleTextInput("changed")
    check editor.handleKey("Esc")
    let closeResult = editor.closeTab(tabs[1].id)
    check not closeResult.closed
    check "No write since last change" in closeResult.message
    editor.close()

  test "file previews replace one another until promoted":
    let
      root = createTempDir("merenda-kosmo-previews-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
      thirdPath = root / "third.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    writeFile(thirdPath, "third")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeFile(thirdPath)
      removeDir(root)

    let editor = newKosmoEditor()
    check editor.previewFile(firstPath).loaded
    var tabs = editor.tabs()
    check tabs.len == 1
    check tabs[0].title == "first.txt"
    check tabs[0].temporary

    check editor.previewFile(secondPath).loaded
    tabs = editor.tabs()
    check tabs.len == 1
    check tabs[0].title == "second.txt"
    check tabs[0].temporary

    check editor.openFile(secondPath).loaded
    tabs = editor.tabs()
    check tabs.len == 1
    check not tabs[0].temporary

    check editor.previewFile(firstPath).loaded
    tabs = editor.tabs()
    check tabs.len == 2
    check tabs[1].title == "first.txt"
    check tabs[1].temporary

    check editor.previewFile(secondPath).loaded
    tabs = editor.tabs()
    check tabs[0].title == "second.txt"
    check tabs[0].active
    check tabs[1].temporary

    check editor.previewFile(firstPath).loaded
    check editor.handleKey("i")
    check editor.handleTextInput("changed")
    check editor.handleKey("Esc")
    tabs = editor.tabs()
    check tabs[1].modified
    check not tabs[1].temporary

    check editor.previewFile(thirdPath).loaded
    tabs = editor.tabs()
    check tabs.len == 3
    check tabs[1].title == "first.txt"
    check tabs[1].modified
    check tabs[2].title == "third.txt"
    check tabs[2].temporary
    editor.close()

  test "preview tabs use the Kosmo preview style class":
    let path = getTempDir() / "merenda-kosmo-preview-style.txt"
    writeFile(path, "preview")
    defer:
      if fileExists(path):
        removeFile(path)

    let
      editor = newKosmoEditor()
      view = newKosmoEditorView(editor)
    view.frame = rect(0, 0, 240, 120)
    check view.previewFile(path)

    var model = view.documentTabs.documentTabModels()[0]
    let previewStyle = view.documentTabs.effectiveAppearance.resolveTextStyle(
      controlStyle(srDocumentTab, classes = model.styleClasses),
      color(0.0, 0.0, 0.0, 1.0),
      insets(0.0),
    )
    check KosmoPreviewTabStyleClass in model.styleClasses
    check previewStyle.fontSlant == fsItalic

    check view.openFile(path)
    model = view.documentTabs.documentTabModels()[0]
    check KosmoPreviewTabStyleClass notin model.styleClasses
    editor.close()

  test "rejects binary files before rendering them as text":
    let path = getTempDir() / "merenda-kosmo-binary-file"
    writeFile(path, "\xCF\xFA\xED\xFE" & "\0".repeat(64))
    defer:
      if fileExists(path):
        removeFile(path)

    let
      editor = newKosmoEditor()
      outcome = editor.openFile(path)
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    check not outcome.loaded
    check "binary file" in outcome.message
    editor.close()

  test "frontend adds an Open command to the File menu":
    let app = newApplication("Kosmo Test")
    let frontend = newKosmoApplication(app)
    let fileMenu = app.mainMenu()[0].submenu()
    let openItem = fileMenu.menuItemWithIdentifier(KosmoOpenFileAction)

    check not openItem.isNil
    check openItem.title == "Open…"
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.contentView.menuBar().hidden() == app.usesNativeMainMenu()
    if app.usesNativeMainMenu():
      check frontend.contentView.contentView().frame().origin.y == 0.0'f32
    check frontend.splitView.panes() ==
      @[View(frontend.fileTree), View(frontend.dockView)]
    frontend.editorView.editor.close()

  test "window resizing preserves the chosen file tree width":
    let frontend = newKosmoApplication(newApplication("Kosmo Resize Test"))
    defer:
      frontend.close()
    frontend.contentView.frame = rect(0, 0, 720, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    frontend.splitView.setPositionOfDivider(0, 230.0'f32)
    frontend.contentView.layoutSubtreeIfNeeded()
    let fileTreeWidth = frontend.fileTree.frame().size.width

    frontend.contentView.frame = rect(0, 0, 1040, 480)
    frontend.contentView.layoutSubtreeIfNeeded()

    check abs(frontend.fileTree.frame().size.width - fileTreeWidth) < 0.01'f32

  test "native tabs select, reorder, and close Moe buffers":
    let
      root = createTempDir("merenda-kosmo-native-tabs-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Tabs Test"))
    defer:
      frontend.close()
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)

    let models = frontend.documentTabs.documentTabModels()
    check models.len == 2
    check models[0].title == "first.txt"
    check models[1].title == "second.txt"
    check frontend.documentTabs.selectedDocumentTabIdentifier == models[1].identifier
    check frontend.documentTabs.selectDocumentTabWithIdentifier(models[0].identifier)
    check frontend.editorView.editor.tabs()[0].active
    check frontend.documentTabs.moveDocumentTabItem(0, 1)
    check frontend.editorView.editor.tabs()[1].title == "first.txt"
    check frontend.documentTabs.closeDocumentTabAtIndex(1)
    check frontend.editorView.editor.tabs().len == 1
    check frontend.documentTabs.documentTabModels().len == 1
    check "NORMAL" in frontend.statusLabel.text
    check "second.txt" in frontend.statusLabel.text

  test "dragging a document tab to an editor edge creates a split group":
    let
      root = createTempDir("merenda-kosmo-dock-split-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Dock Split Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)

    let
      sourceTabs = frontend.documentTabs
      tabRect = sourceTabs.documentTabRect(0)
      start = sourceTabs.pointToWindow(
        initPoint(
          tabRect.minX + tabRect.size.width * 0.5'f32,
          tabRect.minY + tabRect.size.height * 0.5'f32,
        )
      )
      drop = frontend.dockView.pointToWindow(
        initPoint(
          frontend.dockView.bounds().maxX - 4.0'f32,
          frontend.dockView.bounds().minY +
            frontend.dockView.bounds().size.height * 0.5'f32,
        )
      )
      bufferCount = frontend.editorView.editor.tabs().len

    check frontend.window.mouseDownAt(start)
    check frontend.window.mouseDraggedAt(drop)
    check frontend.dockView.dropTarget().position == dpRight
    check frontend.window.mouseUpAt(drop)

    let groups = frontend.editorGroups()
    check groups.len == 2
    check frontend.dockView.rootView() of SplitView
    check SplitView(frontend.dockView.rootView()).splitAxis == laHorizontal
    check groups[0].editorView.documentTabs.len == 1
    check groups[1].editorView.documentTabs.len == 1
    check frontend.editorView.editor.tabs().len == bufferCount

    check groups[1].editorView.documentTabs.closeDocumentTabAtIndex(0)
    check frontend.editorGroups().len == 1
    check frontend.dockView.len == 1
    check frontend.dockView.rootView() == groups[0].panel
    check not (frontend.dockView.rootView() of SplitView)

  test "q and x commands close the active tab and its empty split":
    let
      root = createTempDir("merenda-kosmo-command-close-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Command Close Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)

    let
      sourceTabs = frontend.documentTabs
      tabRect = sourceTabs.documentTabRect(0)
      start = sourceTabs.pointToWindow(
        initPoint(
          tabRect.minX + tabRect.size.width * 0.5'f32,
          tabRect.minY + tabRect.size.height * 0.5'f32,
        )
      )
      drop = frontend.dockView.pointToWindow(
        initPoint(
          frontend.dockView.bounds().maxX - 4.0'f32,
          frontend.dockView.bounds().minY +
            frontend.dockView.bounds().size.height * 0.5'f32,
        )
      )

    check frontend.window.mouseDownAt(start)
    check frontend.window.mouseDraggedAt(drop)
    check frontend.window.mouseUpAt(drop)
    frontend.contentView.layoutSubtreeIfNeeded()

    let groups = frontend.editorGroups()
    check groups.len == 2
    let commandGroupPoint = groups[1].editorView.pointToWindow(initPoint(12, 12))
    check frontend.window.mouseDownAt(commandGroupPoint)
    check not frontend.window.dispatchKeyDown(
      KeyEvent(key: keySemicolon, keyCode: keySemicolon.ord, modifiers: {kmShift})
    )
    check frontend.window.dispatchTextInput(":")
    check frontend.window.dispatchTextInput("q")
    check frontend.window.dispatchKeyDown(
      KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
    )

    check frontend.editorGroups().len == 1
    check frontend.dockView.len == 1
    check not (frontend.dockView.rootView() of SplitView)
    check frontend.editorView.editor.tabs().len == 1
    check frontend.editorView.editor.tabs()[0].title == "second.txt"

    check frontend.openPath(firstPath)
    check frontend.editorView.editor.tabs().len == 2
    check not frontend.window.dispatchKeyDown(
      KeyEvent(key: keySemicolon, keyCode: keySemicolon.ord, modifiers: {kmShift})
    )
    check frontend.window.dispatchTextInput(":")
    check frontend.window.dispatchTextInput("x")
    check frontend.window.dispatchKeyDown(
      KeyEvent(text: "\n", key: keyEnter, keyCode: keyEnter.ord)
    )

    check frontend.editorGroups().len == 1
    check frontend.editorView.editor.tabs().len == 1
    check frontend.editorView.editor.tabs()[0].title == "second.txt"

  test "split editor groups keep independent cursor scroll and motion state":
    let
      root = createTempDir("merenda-kosmo-split-state-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, numberedLines("first", 80))
    writeFile(secondPath, numberedLines("second", 80))
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Split State Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)

    let
      sourceTabs = frontend.documentTabs
      tabRect = sourceTabs.documentTabRect(0)
      start = sourceTabs.pointToWindow(
        initPoint(
          tabRect.minX + tabRect.size.width * 0.5'f32,
          tabRect.minY + tabRect.size.height * 0.5'f32,
        )
      )
      drop = frontend.dockView.pointToWindow(
        initPoint(
          frontend.dockView.bounds().maxX - 4.0'f32,
          frontend.dockView.bounds().minY +
            frontend.dockView.bounds().size.height * 0.5'f32,
        )
      )

    check frontend.window.mouseDownAt(start)
    check frontend.window.mouseDraggedAt(drop)
    check frontend.window.mouseUpAt(drop)
    frontend.contentView.layoutSubtreeIfNeeded()

    let groups = frontend.editorGroups()
    check groups.len == 2
    check groups[0].editorView.documentTabs.documentTabModels()[0].title == "second.txt"
    check groups[1].editorView.documentTabs.documentTabModels()[0].title == "first.txt"

    groups[0].editorView.refresh()
    check groups[0].editorView.keyDown(
      KeyEvent(text: "j", key: keyJ, keyCode: keyJ.ord)
    )
    let firstCursor = frontend.editorView.editor.cursor()
    groups[1].editorView.refresh()
    check groups[1].editorView.keyDown(
      KeyEvent(text: "j", key: keyJ, keyCode: keyJ.ord)
    )
    check groups[1].editorView.keyDown(
      KeyEvent(text: "j", key: keyJ, keyCode: keyJ.ord)
    )
    groups[0].editorView.refresh()
    check frontend.editorView.editor.cursor() == firstCursor

    let scroll = groups[0].editorView.scrollBy(-8.0'f32, row = 2, column = 2)
    check scroll.appliedRows == 8
    let firstScrolledGrid = groups[0].editorView.displayedText()
    check "second row 8" in firstScrolledGrid

    groups[1].editorView.refresh()
    groups[0].editorView.refresh()
    check groups[0].editorView.displayedText() == firstScrolledGrid

    let secondScroll = groups[1].editorView.scrollBy(-3.0'f32, row = 2, column = 2)
    check secondScroll.appliedRows == 3
    let secondScrolledGrid = groups[1].editorView.displayedText()
    check "first row 3" in secondScrolledGrid

    groups[0].editorView.refresh()
    check groups[0].editorView.displayedText() == firstScrolledGrid
    groups[1].editorView.refresh()
    check groups[1].editorView.displayedText() == secondScrolledGrid

    let secondFocusPoint = groups[1].editorView.pointToWindow(initPoint(12, 12))
    check frontend.window.mouseDownAt(secondFocusPoint)
    check "first.txt" in frontend.statusLabel.text
    groups[0].editorView.refresh()
    check "first.txt" in frontend.statusLabel.text
    let firstFocusPoint = groups[0].editorView.pointToWindow(initPoint(12, 12))
    check frontend.window.mouseDownAt(firstFocusPoint)
    check "second.txt" in frontend.statusLabel.text
    groups[1].editorView.refresh()
    check "second.txt" in frontend.statusLabel.text

    let inactiveGridBeforeCommand = groups[1].editorView.displayedText()
    check not frontend.window.dispatchKeyDown(
      KeyEvent(key: keySemicolon, keyCode: keySemicolon.ord, modifiers: {kmShift})
    )
    check frontend.window.dispatchTextInput(":")
    check frontend.window.dispatchTextInput("set")
    check not groups[0].pane.commandBar.hidden()
    check groups[1].pane.commandBar.hidden()
    check frontend.window.mouseDownAt(secondFocusPoint)
    check groups[0].pane.commandBar.hidden()
    check groups[1].pane.commandBar.hidden()
    check not frontend.editorView.editor.commandLine().visible
    check groups[1].editorView.displayedText() == inactiveGridBeforeCommand

    groups[0].editorView.refresh()
    let firstCursorBeforePageMotion = frontend.editorView.editor.cursor()
    groups[1].editorView.refresh()
    check groups[1].editorView.keyDown(
      KeyEvent(text: "f", key: keyF, keyCode: keyF.ord, modifiers: {kmControl})
    )
    groups[0].editorView.refresh()
    check frontend.editorView.editor.cursor() == firstCursorBeforePageMotion

    groups[1].editorView.refresh()
    check groups[1].editorView.keyDown(
      KeyEvent(text: "b", key: keyB, keyCode: keyB.ord, modifiers: {kmControl})
    )
    groups[0].editorView.refresh()
    check frontend.editorView.editor.cursor() == firstCursorBeforePageMotion

    let inactiveGridBeforeCompletion = groups[0].editorView.displayedText()
    let
      metrics = groups[1].editorView.monoTextMetrics()
      focusPoint = groups[1].editorView.pointToWindow(
        initPoint(metrics.cellWidth * 12.0'f32, metrics.lineHeight * 2.0'f32)
      )
    check frontend.window.mouseDownAt(focusPoint)
    check groups[1].editorView.keyDown(
      KeyEvent(text: "a", key: keyA, keyCode: keyA.ord)
    )
    check groups[1].editorView.keyDown(
      KeyEvent(text: " ", key: keySpace, keyCode: keySpace.ord)
    )
    check groups[1].editorView.keyDown(
      KeyEvent(text: "f", key: keyF, keyCode: keyF.ord)
    )
    check groups[1].editorView.keyDown(
      KeyEvent(text: "p", key: keyP, keyCode: keyP.ord, modifiers: {kmControl})
    )
    check frontend.editorView.editor.completionPopupVisible()
    groups[0].editorView.refresh()
    check groups[0].editorView.displayedText() == inactiveGridBeforeCompletion

  test "dragging a document tab outside every workspace creates a window":
    let
      root = createTempDir("merenda-kosmo-dock-window-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Dock Window Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)

    let
      sourceTabs = frontend.documentTabs
      tabRect = sourceTabs.documentTabRect(0)
      start = sourceTabs.pointToWindow(
        initPoint(
          tabRect.minX + tabRect.size.width * 0.5'f32,
          tabRect.minY + tabRect.size.height * 0.5'f32,
        )
      )
      drop = initPoint(
        frontend.window.frame().size.width + 180.0'f32,
        frontend.window.frame().size.height + 180.0'f32,
      )

    check frontend.window.mouseDownAt(start)
    check frontend.window.mouseDraggedAt(drop)
    check frontend.window.mouseUpAt(drop)
    check frontend.editorGroups().len == 2
    check frontend.detachedEditorWindows().len == 1
    let detachedWindow = frontend.detachedEditorWindows()[0]
    check detachedWindow.contentView() != nil
    check frontend.editorView.editor.tabs().len == 2

  test "native tab bar sits above the editor grid":
    let frontend = newKosmoApplication(newApplication("Kosmo Tabs Layout Test"))
    defer:
      frontend.close()
    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()

    check frontend.documentTabs.frame().origin.y == 0.0'f32
    check frontend.documentTabs.frame().size.height == KosmoTabBarHeight
    check frontend.editorView.frame().origin.y == KosmoTabBarHeight
    check frontend.editorView.frame().size.height ==
      frontend.editorPane.bounds().size.height - KosmoTabBarHeight

    let editorStyle = frontend.editorView.effectiveAppearance.resolveMonoTextStyle(
      controlStyle(srMonoTextView, id = frontend.editorView.styleId)
    )
    check editorStyle.cursorColor.a == 0.45'f32
    check editorStyle.box.focusRingWidth == 0.0'f32
    check editorStyle.box.focusRingInset == 0.0'f32
    check editorStyle.box.cornerRadius == 0.0'f32
    check editorStyle.box.cornerRadii.isZero

  test "settled editor refresh does not re-dirty its containing layout":
    let frontend = newKosmoApplication(newApplication("Kosmo Layout Test"))
    defer:
      frontend.close()

    frontend.contentView.frame = rect(0, 0, 640, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    frontend.contentView.layoutSubtreeIfNeeded()

    check not frontend.contentView.needsLayout()
    check not frontend.contentView.contentView().needsLayout()

  test "file tree lazily exposes folders before files":
    let
      root = createTempDir("merenda-kosmo-tree-", "")
      folder = root / "folder"
      nestedFile = folder / "nested.txt"
      rootFile = root / "root.txt"
    createDir(folder)
    writeFile(nestedFile, "nested")
    writeFile(rootFile, "root")
    defer:
      removeFile(nestedFile)
      removeFile(rootFile)
      removeDir(folder)
      removeDir(root)

    let tree = newKosmoFileTree(root)
    check tree.rootPath == absolutePath(root)
    check tree.rowCount() == 3
    check tree.itemAtRow(1).identifier == folder
    check tree.outlineItemWithIdentifier(rootFile).leaf

    tree.expandItem(folder)
    check tree.rowCount() == 4
    check tree.outlineItemWithIdentifier(nestedFile).leaf

  test "file tree activates files without entering inline editing":
    let
      root = createTempDir("merenda-kosmo-tree-activation-", "")
      filePath = root / "document.txt"
    writeFile(filePath, "document body")
    let
      window = newWindow("Kosmo File Tree Activation", frame = rect(0, 0, 300, 120))
      tree = newKosmoFileTree(root, frame = rect(0, 0, 300, 120))
    defer:
      removeFile(filePath)
      removeDir(root)

    var openRequests: seq[tuple[path: string, disposition: FileTreeOpenDisposition]]
    tree.onOpenFile = proc(path: string, disposition: FileTreeOpenDisposition) =
      openRequests.add (path, disposition)
    window.setContentView(tree)
    discard buildRenders(tree)

    let
      row = tree.rowForItem(filePath)
      rowRect = tree.rowItemRect(row)
      point = tree.pointToWindow(
        initPoint(
          rowRect.origin.x + rowRect.size.width * 0.5'f32,
          rowRect.origin.y + rowRect.size.height * 0.5'f32,
        )
      )
    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check not tree.editingState.active
    check openRequests == @[(filePath, fodTemporary)]

    check window.mouseDownAt(point, clickCount = 2)
    check window.mouseUpAt(point, clickCount = 2)
    check not tree.editingState.active
    check openRequests == @[(filePath, fodTemporary), (filePath, fodPermanent)]

    openRequests.setLen(0)
    check tree.keyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check not tree.editingState.active
    check openRequests == @[(filePath, fodPermanent)]

  test "double clicking a file tree folder toggles it":
    let
      root = createTempDir("merenda-kosmo-tree-folder-", "")
      folder = root / "folder"
      nestedFile = folder / "nested.txt"
    createDir(folder)
    writeFile(nestedFile, "nested")
    let
      window = newWindow("Kosmo Folder Activation", frame = rect(0, 0, 300, 120))
      tree = newKosmoFileTree(root, frame = rect(0, 0, 300, 120))
    defer:
      removeFile(nestedFile)
      removeDir(folder)
      removeDir(root)

    window.setContentView(tree)
    discard buildRenders(tree)
    let
      rowRect = tree.rowItemRect(tree.rowForItem(folder))
      point = tree.pointToWindow(
        initPoint(
          rowRect.origin.x + rowRect.size.width * 0.5'f32,
          rowRect.origin.y + rowRect.size.height * 0.5'f32,
        )
      )

    check window.mouseDownAt(point)
    check window.mouseUpAt(point)
    check not tree.isItemExpanded(folder)

    check window.mouseDownAt(point, clickCount = 2)
    check window.mouseUpAt(point, clickCount = 2)
    check tree.isItemExpanded(folder)
    check tree.rowForItem(nestedFile) >= 0

    check window.mouseDownAt(point, clickCount = 2)
    check window.mouseUpAt(point, clickCount = 2)
    check not tree.isItemExpanded(folder)
    check tree.rowForItem(nestedFile) < 0

  test "opening files and folders updates the file-tree root":
    let
      root = createTempDir("merenda-kosmo-open-path-", "")
      folder = root / "folder"
      filePath = root / "document.txt"
    createDir(folder)
    writeFile(filePath, "document body")
    defer:
      removeFile(filePath)
      removeDir(folder)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Open Path Test"))
    check frontend.openPath(filePath)
    check frontend.fileTree.rootPath == absolutePath(root)

    check frontend.openPath(folder)
    check frontend.fileTree.rootPath == absolutePath(folder)
    frontend.close()

  test "open panel action buttons keep their natural height":
    let panel = newOpenPanel()
    let folder = createTempDir("merenda-kosmo-panel-folder-", "")
    defer:
      removeDir(folder)
    panel.canChooseDirectories = true
    panel.selectUrl(folder)
    let content = panel.contentView()
    content.layoutSubtreeIfNeeded()
    let button = Button(panel.buttonViews[0])

    check panel.validateSelection()
    check button.frame().size.height == button.sizeThatFits().height
    check button.frame().size.height < content.bounds().size.height / 2.0'f32
