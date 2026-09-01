import std/[monotimes, options, os, osproc, strutils, tempfiles, times, unittest]

import figdraw
import sigils/threads

import merenda/nimkit
import merenda/nimkit/text/monotextviews as monoTextViews
import merenda/kosmo/kosmo

proc renderedText(buffer: RenderBuffer): string =
  for row in 0 ..< buffer.height:
    for column in 0 ..< buffer.width:
      result.add buffer.cell(column, row).symbol
    result.add '\n'

proc displayedText(view: KosmoEditorView): string =
  monoTextViews.stringValue(MonoTextView(view))

proc gridPoint(view: KosmoEditorView, row, column: int): Point =
  let metrics = view.monoTextMetrics()
  view.pointToWindow(
    initPoint(
      (column.float32 + 0.5'f32) * metrics.cellWidth,
      (row.float32 + 0.5'f32) * metrics.lineHeight,
    )
  )

proc pointForBufferPosition(
    view: KosmoEditorView, line, column: int
): tuple[point: Point, cursor: KosmoCursor] =
  discard view.editor.revealLocation(line, column)
  view.refresh()
  result.cursor = view.editor.cursor()
  result.point = view.gridPoint(result.cursor.row, result.cursor.column)

suite "Kosmo":
  test "pane documents adapt arbitrary views to native document tabs":
    let
      content = newView()
      document = newKosmoPaneDocument(
        "kosmo.preview.readme", "README Preview", content, tooltip = "README.md"
      )
      model = document.documentTabModel()

    check document.contentView == content
    check document.preferredFirstResponder == content
    check model.identifier == "kosmo.preview.readme"
    check model.title == "README Preview"
    check model.tooltip == "README.md"
    check document.close()
    check not document.save()
    check document.duplicate().isNil

  test "pane documents can create independent split instances":
    var duplicateCount = 0
    let document = newKosmoPaneDocument(
      "kosmo.preview.readme",
      "README Preview",
      newView(),
      onDuplicate = proc(document: KosmoPaneDocument): KosmoPaneDocument =
        inc duplicateCount
        newKosmoPaneDocument(document.identifier & ".copy", document.title, newView()),
    )

    let duplicate = document.duplicate()

    check duplicateCount == 1
    require not duplicate.isNil
    check duplicate.identifier == "kosmo.preview.readme.copy"
    check duplicate.title == document.title
    check duplicate.contentView != document.contentView

  test "view-backed documents use the shared pane tab lifecycle":
    let
      frontend = newKosmoApplication(newApplication("Kosmo Generic Document Test"))
      content = newView()
      initialTabCount = frontend.documentTabs.len
    var closeCount = 0
    let document = newKosmoPaneDocument(
      "kosmo.preview.readme",
      "README Preview",
      content,
      onClose = proc(document: KosmoPaneDocument): bool =
        discard document
        inc closeCount
        true,
    )
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()

    check frontend.openDocument(document)
    check frontend.documentTabs.len == initialTabCount + 1
    check frontend.editorPane.contentView == content
    check frontend.documentTabs.selectedDocumentTabItem().title == "README Preview"
    check frontend.documentTabs.closeDocumentTabAtIndex(
      frontend.documentTabs.selectedIndex()
    )
    check closeCount == 1
    check frontend.documentTabs.len == initialTabCount
    check frontend.editorPane.contentView == View(frontend.editorView)

  test "renders initial text into a cell grid":
    let editor = newKosmoEditor(text = "hello")
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    check "hello" in buffer.renderedText
    check "NORMAL" notin buffer.renderedText
    check "No Name" notin buffer.renderedText
    editor.close()

  test "discovers and applies Moe TOML themes":
    let
      root = createTempDir("merenda-kosmo-moe-themes-", "")
      lightPath = root / "soft-light.toml"
      vividPath = root / "vivid.toml"
    writeFile(
      lightPath, "[Colors]\nforeground = \"#101010\"\nbackground = \"#f8f8f8\"\n"
    )
    writeFile(
      vividPath, "[Colors]\nforeground = \"#ffdd66\"\nbackground = \"#160022\"\n"
    )
    defer:
      removeFile(lightPath)
      removeFile(vividPath)
      removeDir(root)

    let themes = discoverMoeThemes(root)
    check themes.len == 3
    check themes[0].identifier == KosmoMoeDefaultThemeIdentifier
    check themes[0].name == "Default"
    check themes[1].name == "Soft Light"
    check themes[2].name == "Vivid"
    check themes[1].preview.foreground ==
      KosmoMoeThemeColor(red: 16, green: 16, blue: 16)
    check themes[1].preview.background ==
      KosmoMoeThemeColor(red: 248, green: 248, blue: 248)
    check themes[2].preview.foreground ==
      KosmoMoeThemeColor(red: 255, green: 221, blue: 102)
    check themes[2].preview.background == KosmoMoeThemeColor(
      red: 22, green: 0, blue: 34
    )

    let editor = newKosmoEditor(text = "themed")
    let outcome = editor.applyMoeTheme(themes[1])
    check outcome.applied
    check outcome.message == "Theme changed to: Soft Light"
    check editor.activeMoeThemeIdentifier() == themes[1].identifier
    check editor.applyMoeTheme(themes[0]).applied
    check editor.activeMoeThemeIdentifier() == KosmoMoeDefaultThemeIdentifier
    editor.close()

  test "bundled Neovim-inspired themes load through Moe":
    let editor = newKosmoEditor(text = "themed")
    let themes = editor.availableMoeThemes()
    for expectedName in [
      "Catppuccin Latte", "Catppuccin Mocha", "Kanagawa Wave", "One Dark",
      "Tokyo Night Moon",
    ]:
      var matchingIndex = -1
      for index, theme in themes:
        if theme.name == expectedName:
          matchingIndex = index
          break
      require matchingIndex >= 0
      if expectedName == "Catppuccin Mocha":
        let preview = themes[matchingIndex].preview
        check preview.foreground == KosmoMoeThemeColor(red: 205, green: 214, blue: 244)
        check preview.background == KosmoMoeThemeColor(red: 30, green: 30, blue: 46)
        check preview.keyword == KosmoMoeThemeColor(red: 203, green: 166, blue: 247)
        check preview.functionName == KosmoMoeThemeColor(
          red: 137, green: 180, blue: 250
        )
        check preview.stringLiteral ==
          KosmoMoeThemeColor(red: 166, green: 227, blue: 161)
        check preview.comment == KosmoMoeThemeColor(red: 108, green: 112, blue: 134)
      let outcome = editor.applyMoeTheme(themes[matchingIndex])
      check outcome.applied
      check editor.activeMoeThemeIdentifier() == themes[matchingIndex].identifier
    check editor.applyMoeTheme(themes[0]).applied
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

    let accelerated =
      view.scrollBy(-1.0'f32, row = 2, column = 2, modifiers = {nimkit.kmControl})
    check accelerated.requestedRows == 3
    check accelerated.appliedRows == 3

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

  test "native pointer gestures select and repaint Moe text":
    let
      frontend = newKosmoApplication(newApplication("Kosmo Pointer Selection Test"))
      view = frontend.editorView
      editor = view.editor
    defer:
      frontend.close()

    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check editor.handleKey("i")
    check editor.handleTextInput("alpha beta\nsecond line")
    check editor.handleKey("Esc")
    view.refresh()
    check editor.currentSelection().isNone
    check editor.selectedText().len == 0

    let
      start = view.pointForBufferPosition(0, 1)
      startCell = view.cellAt(start.cursor.row, start.cursor.column)
      finish = view.pointForBufferPosition(1, 5)
    check frontend.window.mouseDownAt(start.point, clickCount = 1)
    check frontend.window.mouseDraggedAt(finish.point)
    check frontend.window.mouseUpAt(finish.point, clickCount = 1)

    let dragSelection = editor.currentSelection()
    require dragSelection.isSome
    check dragSelection.get.kind == KosmoSelectionKind.Character
    check dragSelection.get.anchor == KosmoBufferCursor(line: 0, column: 1)
    check dragSelection.get.focus == KosmoBufferCursor(line: 1, column: 5)
    check dragSelection.get.first == dragSelection.get.anchor
    check dragSelection.get.last == dragSelection.get.focus
    check editor.selectedText() == "lpha beta\nsecond"
    let selectedCell = view.cellAt(start.cursor.row, start.cursor.column)
    check selectedCell.backgroundColor != startCell.backgroundColor

    let word = view.pointForBufferPosition(0, 7)
    check frontend.window.mouseDownAt(word.point, clickCount = 2)
    check frontend.window.mouseUpAt(word.point, clickCount = 2)
    let wordSelection = editor.currentSelection()
    require wordSelection.isSome
    check wordSelection.get.kind == KosmoSelectionKind.Character
    check editor.selectedText() == "beta"

    let line = view.pointForBufferPosition(1, 2)
    check frontend.window.mouseDownAt(line.point, clickCount = 3)
    check frontend.window.mouseUpAt(line.point, clickCount = 3)
    let lineSelection = editor.currentSelection()
    require lineSelection.isSome
    check lineSelection.get.kind == KosmoSelectionKind.Line
    check editor.selectedText() == "second line"

    let caret = view.pointForBufferPosition(0, 2)
    check frontend.window.mouseDownAt(caret.point, clickCount = 1)
    check frontend.window.mouseUpAt(caret.point, clickCount = 1)
    check editor.currentSelection().isNone
    let extension = view.gridPoint(caret.cursor.row, caret.cursor.column + 5)
    check frontend.window.mouseDownAt(
      extension, clickCount = 1, modifiers = {nimkit.kmShift}
    )
    check frontend.window.mouseUpAt(
      extension, clickCount = 1, modifiers = {nimkit.kmShift}
    )
    let extendedSelection = editor.currentSelection()
    require extendedSelection.isSome
    check extendedSelection.get.anchor == KosmoBufferCursor(line: 0, column: 2)
    check extendedSelection.get.focus == KosmoBufferCursor(line: 0, column: 7)
    check editor.selectedText() == "pha be"

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

  test "rejects binary previews misdetected as UTF-16 text":
    let path = getTempDir() / "merenda-kosmo-binary-utf16-file"
    writeFile(path, "\xCF\xFA\xED\xFE\xD8\x00\x41\x00\x00\x00")
    defer:
      if fileExists(path):
        removeFile(path)

    let
      editor = newKosmoEditor()
      outcome = editor.previewFile(path)
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    check not outcome.loaded
    check "binary file" in outcome.message
    check editor.tabs().len == 1
    check editor.tabs()[0].filePath.isNone
    editor.close()

  test "opens UTF-16 text without treating encoded zero bytes as binary":
    let path = getTempDir() / "merenda-kosmo-utf16-file"
    writeFile(path, "\xFF\xFE\x48\x00\x65\x00\x6C\x00\x6C\x00\x6F\x00\x0A\x00")
    defer:
      if fileExists(path):
        removeFile(path)

    let
      editor = newKosmoEditor()
      outcome = editor.openFile(path)
    var buffer = newRenderBuffer(24, 8)
    editor.render(buffer)

    check outcome.loaded
    check "Hello" in buffer.renderedText
    editor.close()
