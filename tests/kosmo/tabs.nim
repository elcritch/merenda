import
  std/[monotimes, options, os, osproc, strutils, tempfiles, times, unicode, unittest]

import figdraw
import sigils/threads

import merenda/nimkit
import merenda/nimkit/text/monotextviews as monoTextViews
import merenda/kosmo/kosmo

func center(rect: Rect): Point =
  initPoint(
    rect.origin.x + rect.size.width / 2.0'f32,
    rect.origin.y + rect.size.height / 2.0'f32,
  )

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add(rune)

proc renderedTexts(view: View): seq[string] =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkText:
      result.add node.renderedText()

suite "Kosmo":
  test "recognizes conventional Markdown file extensions":
    for path in ["README.md", "guide.MARKDOWN", "notes.mkd", "manual.mdtext"]:
      check path.isMarkdownFilePath
    for path in ["readme.txt", "markdown.nim", "document.html"]:
      check not path.isMarkdownFilePath

  test "repeated window resizing preserves the chosen file tree width":
    let frontend = newKosmoApplication(newApplication("Kosmo Resize Test"))
    defer:
      frontend.close()
    frontend.contentView.frame = rect(0, 0, 720, 480)
    frontend.contentView.layoutSubtreeIfNeeded()
    frontend.splitView.setPositionOfDivider(0, 230.0'f32)
    frontend.contentView.layoutSubtreeIfNeeded()
    let fileTreeWidth = frontend.fileTree.frame().size.width

    for width in [1040.0'f32, 760.0'f32, 1180.0'f32, 820.0'f32, 960.0'f32]:
      frontend.contentView.frame = rect(0, 0, width, 480)
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

  test "Markdown tabs preview live Moe buffers and toggle to syntax":
    let
      root = createTempDir("merenda-kosmo-markdown-tabs-", "")
      markdownPath = root / "README.md"
      textPath = root / "notes.txt"
      source = "# Kosmo\n\n| Feature | State |\n| --- | --- |\n| Preview | Ready |\n"
    writeFile(markdownPath, source)
    writeFile(textPath, "ordinary text")
    defer:
      removeFile(markdownPath)
      removeFile(textPath)
      removeDir(root)

    let app = newApplication("Kosmo Markdown Tabs Test")
    app.setAppearance(initAppearance(initAquaTheme()))
    let frontend = newKosmoApplication(app)
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 720, 480)
    frontend.contentView.layoutSubtreeIfNeeded()

    check frontend.openPath(markdownPath)
    let markdownId = frontend.editorView.editor.tabs()[0].id
    check frontend.editorView.markdownMode(markdownId) == kmmPreview
    check frontend.editorPane.contentView == View(frontend.editorPane.markdownView)
    check frontend.editorPane.markdownView.markdown.strip() == source.strip()
    require frontend.editorPane.markdownView.waitForMarkdownParsing()
    check "Kosmo" in frontend.editorPane.markdownView.textStorage.stringValue()
    check "Preview" in frontend.editorPane.markdownView.textStorage.stringValue()

    let controls = frontend.editorPane.markdownControls
    frontend.editorPane.layoutSubtreeIfNeeded()
    controls.layoutSubtreeIfNeeded()
    check not controls.hidden
    check controls.modeButton.title == "</>"
    check controls.colorModeButton.title == "Dark"
    check controls.markdownColorMode == kmcmLight
    check controls.markdownFontSize == KosmoMarkdownDefaultFontSize
    check controls.frame().maxX < frontend.editorPane.bounds().maxX
    check controls.frame().minY > KosmoTabBarHeight
    let controlTitles = View(controls).renderedTexts()
    for title in ["</>", "Dark", "-", "+"]:
      check title in controlTitles
    check "…" notin controlTitles

    let lightBackground = frontend.editorPane.markdownView.markdownStyle.backgroundColor
    frontend.window.setAppearance(initAppearance(initDarkBSDTheme()))
    check controls.markdownColorMode == kmcmDark
    check controls.colorModeButton.title == "Light"
    check frontend.editorPane.markdownView.markdownStyle.backgroundColor !=
      lightBackground
    frontend.window.setAppearance(initAppearance(initAquaTheme()))
    check controls.markdownColorMode == kmcmLight
    check controls.colorModeButton.title == "Dark"
    check frontend.editorPane.markdownView.markdownStyle.backgroundColor ==
      lightBackground

    check frontend.window.clickAt(
      controls.colorModeButton.pointToWindow(controls.colorModeButton.bounds().center())
    )
    check controls.markdownColorMode == kmcmDark
    check controls.colorModeButton.title == "Light"
    check "Light" in View(controls).renderedTexts()
    check frontend.editorPane.markdownView.markdownStyle.backgroundColor !=
      lightBackground

    check frontend.window.clickAt(
      controls.increaseFontButton.pointToWindow(
        controls.increaseFontButton.bounds().center()
      )
    )
    check controls.markdownFontSize == KosmoMarkdownDefaultFontSize + 1.0'f32
    check frontend.editorPane.markdownView.markdownStyle.bodyFontSize ==
      controls.markdownFontSize
    check frontend.window.clickAt(
      controls.decreaseFontButton.pointToWindow(
        controls.decreaseFontButton.bounds().center()
      )
    )
    check controls.markdownFontSize == KosmoMarkdownDefaultFontSize

    check frontend.window.clickAt(
      controls.modeButton.pointToWindow(controls.modeButton.bounds().center())
    )
    check frontend.editorView.markdownMode(markdownId) == kmmSyntax
    check frontend.editorPane.contentView == View(frontend.editorView)
    check not controls.hidden
    check controls.modeButton.title == "MD"

    check frontend.editorView.editor.handleKey("i")
    check frontend.editorView.editor.handleTextInput("## Unsaved\n")
    check frontend.editorView.editor.handleKey("Esc")
    frontend.editorView.refresh()
    check "## Unsaved" in frontend.editorView.editor.bufferText(markdownId).get

    check frontend.window.clickAt(
      controls.modeButton.pointToWindow(controls.modeButton.bounds().center())
    )
    check frontend.editorView.markdownMode(markdownId) == kmmPreview
    check frontend.editorPane.contentView == View(frontend.editorPane.markdownView)
    check "## Unsaved" in frontend.editorPane.markdownView.markdown
    check "## Unsaved" notin readFile(markdownPath)

    check frontend.openPath(textPath)
    check frontend.editorPane.contentView == View(frontend.editorView)
    check controls.hidden

  test "application shortcuts save close and cycle the focused editor tabs":
    let
      root = createTempDir("merenda-kosmo-shortcuts-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

    let frontend = newKosmoApplication(newApplication("Kosmo Shortcuts Test"))
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)
    check frontend.editorView.editor.tabs()[1].active

    check frontend.window.dispatchKeyDown(
      KeyEvent(
        key: keyLeftBracket,
        keyCode: keyLeftBracket.ord,
        modifiers: {kmCommand, kmShift},
      )
    )
    check frontend.editorView.editor.tabs()[0].active
    check frontend.window.dispatchKeyDown(
      KeyEvent(
        key: keyRightBracket,
        keyCode: keyRightBracket.ord,
        modifiers: {kmCommand, kmShift},
      )
    )
    check frontend.editorView.editor.tabs()[1].active

    check frontend.editorView.editor.handleKey("i")
    check frontend.editorView.editor.handleTextInput("!")
    check frontend.editorView.editor.handleKey("Esc")
    check frontend.editorView.editor.tabs()[1].modified
    check frontend.application.mainMenu().performKeyEquivalent(
      KeyEvent(key: keyS, keyCode: keyS.ord, modifiers: shortcutModifiers()),
      Responder(frontend.editorView),
    )
    check not frontend.editorView.editor.tabs()[1].modified
    check "!" in readFile(secondPath)

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
    )
    check frontend.editorView.editor.tabs().len == 2
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
    )
    check frontend.editorView.editor.tabs().len == 1
    check frontend.editorView.editor.tabs()[0].title == "first.txt"

    when defined(macosx) or defined(macos):
      check frontend.openPath(secondPath)
      check frontend.editorView.editor.tabs().len == 2
      check frontend.window.dispatchKeyDown(
        KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmCommand})
      )
      check frontend.editorView.editor.tabs().len == 1
      check frontend.editorView.editor.tabs()[0].title == "first.txt"

  test "JSON can customize Kosmo application shortcuts":
    let
      root = createTempDir("merenda-kosmo-shortcut-config-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
      bindingsPath = root / "keybindings.json"
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    writeFile(bindingsPath, """{"kosmo.nextTab": "ctrl-w ctrl-j"}""")
    defer:
      removeFile(firstPath)
      removeFile(secondPath)
      removeFile(bindingsPath)
      removeDir(root)

    let frontend = newKosmoApplication(
      newApplication("Kosmo Shortcut Config Test"), keyBindingsPath = bindingsPath
    )
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)
    check frontend.openPath(firstPath)
    check frontend.openPath(secondPath)

    check frontend.window
    .keyBindings()
    .commandFor(
      KeyEvent(
        key: keyRightBracket,
        keyCode: keyRightBracket.ord,
        modifiers: {kmCommand, kmShift},
      )
    ).isNone
    check frontend.editorView.editor.tabs()[1].active
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
    )
    check frontend.editorView.editor.tabs()[1].active
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyJ, keyCode: keyJ.ord, modifiers: {kmControl})
    )
    check frontend.editorView.editor.tabs()[0].active

  test "Command-Q terminates Kosmo through the application lifecycle":
    let
      app = newApplication("Kosmo Quit Shortcut Test")
      frontend = newKosmoApplication(app)
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    check frontend.window.makeFirstResponder(frontend.editorView)
    check not app.isTerminating

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyQ, keyCode: keyQ.ord, modifiers: {kmCommand})
    )
    check app.isTerminating

  test "Command-number shortcuts focus the file browser and editor panels":
    let
      root = createTempDir("merenda-kosmo-panel-shortcuts-", "")
      firstPath = root / "first.txt"
      secondPath = root / "second.txt"
      frontend = newKosmoApplication(newApplication("Kosmo Panel Shortcuts Test"))
    writeFile(firstPath, "first")
    writeFile(secondPath, "second")
    defer:
      frontend.close()
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)

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
    require groups.len == 2
    check frontend.window.dispatchKeyDown(
      KeyEvent(key: key2, keyCode: key2.ord, modifiers: {kmCommand})
    )
    check frontend.window.firstResponder == groups[0].editorView
    check not groups[0].pane.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: key1, keyCode: key1.ord, modifiers: {kmCommand})
    )
    check frontend.sidebarTabs.selectedIndex == 0
    check frontend.window.firstResponder == frontend.fileTree

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: key3, keyCode: key3.ord, modifiers: {kmCommand})
    )
    check frontend.window.firstResponder == groups[1].editorView
    check not groups[1].pane.documentTabs.hasStyleClass(KosmoInactivePaneStyleClass)
