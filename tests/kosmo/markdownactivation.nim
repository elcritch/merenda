import std/[options, os, strutils, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo
import fixtures/ui

const FixtureDirectory = currentSourcePath().parentDir / "fixtures"

suite "Kosmo Markdown activation":
  test "switching Markdown tabs preserves selection and scroll position":
    let
      root = createTempDir("kosmo-markdown-activation-", "")
      secondPath = root / "second.md"
      frontend = newKosmoApplication(
        newApplication("Markdown activation"), monitorsGitStatus = false
      )
    writeFile(secondPath, "# Second preview\n\nA separate cached document.\n")
    defer:
      frontend.close()
      removeFile(secondPath)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 1000, 700)
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.openPath(FixtureDirectory / "markdown-activation.md")
    let first = frontend.editorPane.markdownView
    require first.waitForMarkdownParsing()
    discard buildRenders(first)
    first.textView().selectedRange = initTextRange(2, 3)
    first.scrollView().scrollTo(initPoint(0, 24))
    let firstScrollOffset = first.scrollView().contentOffset()
    let firstText = first.textStorage().stringValue()
    check firstScrollOffset.y > 0
    let identifier = frontend.documentTabs.selectedDocumentTabIdentifier
    require frontend.openPath(secondPath)
    let second = frontend.editorPane.markdownView
    require second.waitForMarkdownParsing()
    discard buildRenders(second)
    for iteration in 0 ..< 3:
      discard iteration
      require frontend.documentTabs.selectDocumentTabWithIdentifier(identifier)
      let restored = frontend.editorPane.markdownView
      require restored.waitForMarkdownParsing()
      check restored.textStorage().stringValue() == firstText
      check restored.textView().selectedRange == initTextRange(2, 3)
      check restored.scrollView().contentOffset() == firstScrollOffset
      for tab in frontend.editorView.editor.tabs():
        check not tab.modified
      require frontend.documentTabs.selectDocumentTabAtIndex(1)
      require frontend.editorPane.markdownView.waitForMarkdownParsing()
      check "Second preview" in
        frontend.editorPane.markdownView.textStorage().stringValue()
    require frontend.documentTabs.selectDocumentTabWithIdentifier(identifier)
    require frontend.documentTabs.closeDocumentTabAtIndex(0)
    require frontend.editorPane.markdownView.waitForMarkdownParsing()
    check "Second preview" in
      frontend.editorPane.markdownView.textStorage().stringValue()

  test "preview edit commands cannot modify hidden Markdown source":
    let
      root = createTempDir("kosmo-markdown-editing-", "")
      path = root / "preview.md"
      frontend = newKosmoApplication(
        newApplication("Markdown editing"), monitorsGitStatus = false
      )
      pasteboard = generalPasteboard()
      previousClipboard = pasteboard.plainText()
    writeFile(path, "# Preview\n\nUnchanged source\n")
    defer:
      discard pasteboard.setPlainText(previousClipboard)
      frontend.close()
      removeFile(path)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    require frontend.openPath(path)
    require frontend.editorPane.markdownView.waitForMarkdownParsing()
    let
      id = frontend.editorView.editor.tabs()[0].id
      original = frontend.editorView.editor.bufferText(id).get
    require frontend.editorView.editor.handleKey("i")
    discard pasteboard.setPlainText("unexpected edit")
    let primary = frontend.shortcutProfile().primaryModifiers()
    for target in [
      Responder(frontend.editorPane.markdownView),
      Responder(frontend.editorPane.markdownView.textView()),
    ]:
      require frontend.window.makeFirstResponder(target)
      discard frontend.window.sendAction(actionSelector(KosmoPasteAction))
      for key in [keyA, keyC, keyX, keyV, keyZ]:
        discard frontend.window.dispatchKeyDown(
          KeyEvent(key: key, keyCode: key.ord, modifiers: primary)
        )
      check "Preview" in pasteboard.plainText()
      discard frontend.window.dispatchKeyDown(
        KeyEvent(text: "q", key: keyQ, keyCode: keyQ.ord)
      )
      for action in ["selectAll", "cut", "paste", "undo", "redo"]:
        discard frontend.window.sendAction(actionSelector(action))
      check frontend.editorView.editor.bufferText(id).get == original
      check not frontend.editorView.editor.tabs()[0].modified

  test "revisiting many Markdown tabs always displays the selected document":
    let
      root = createTempDir("kosmo-markdown-revisit-", "")
      frontend = newKosmoApplication(
        newApplication("Markdown tab navigation"), monitorsGitStatus = false
      )
    defer:
      frontend.close()
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    var identifiers: seq[string]
    for index in 0 ..< 6:
      let path = root / ("preview-" & $index & ".md")
      writeFile(path, "# Preview " & $index & "\n")
      require frontend.openPath(path)
      identifiers.add frontend.documentTabs.selectedDocumentTabIdentifier
      require frontend.editorPane.markdownView.waitForMarkdownParsing()
    for index in [0, 4, 2, 5, 1, 3, 0]:
      require frontend.documentTabs.selectDocumentTabWithIdentifier(identifiers[index])
      let preview = frontend.editorPane.markdownView
      require preview.waitForMarkdownParsing()
      check preview.textStorage().stringValue().strip() == "Preview " & $index
      check frontend.documentTabs.documentTabModels().len == identifiers.len
      for tab in frontend.editorView.editor.tabs():
        check not tab.modified

  test "source edits refresh the cached preview and save normally":
    let
      root = createTempDir("kosmo-markdown-save-", "")
      path = root / "preview.md"
      frontend =
        newKosmoApplication(newApplication("Markdown save"), monitorsGitStatus = false)
    writeFile(path, "# Original\n")
    defer:
      frontend.close()
      removeFile(path)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 700, 500)
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.openPath(path)
    let buttonBounds = frontend.editorPane.markdownControls.modeButton.bounds()
    let buttonPoint =
      initPoint(buttonBounds.size.width / 2, buttonBounds.size.height / 2)
    require frontend.window.clickAt(
      frontend.editorPane.markdownControls.modeButton.pointToWindow(buttonPoint)
    )
    require frontend.editorView.editor.handleKey("i")
    require frontend.editorView.editor.handleTextInput("Updated ")
    require frontend.editorView.editor.handleKey("Esc")
    frontend.editorView.refresh()
    check frontend.editorView.editor.tabs()[0].modified
    require frontend.window.clickAt(
      frontend.editorPane.markdownControls.modeButton.pointToWindow(buttonPoint)
    )
    let preview = frontend.editorPane.markdownView
    require preview.waitForMarkdownParsing()
    check "Updated" in preview.textStorage().stringValue()
    discard frontend.window.sendAction(actionSelector(KosmoSaveAction))
    check not frontend.editorView.editor.tabs()[0].modified
    check "Updated" in readFile(path)

  test "Markdown toolbar keeps zoom controls on the trailing side":
    let frontend = newKosmoApplication(
      newApplication("Markdown toolbar layout"), monitorsGitStatus = false
    )
    defer:
      frontend.close()
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 1000, 700)
    require frontend.openPath(FixtureDirectory / "markdown-activation.md")
    require frontend.editorPane.markdownView.waitForMarkdownParsing()
    frontend.contentView.layoutSubtreeIfNeeded()
    let controls = frontend.editorPane.markdownControls
    for width in [640.0'f32, 1000.0'f32]:
      frontend.contentView.frame = rect(0, 0, width, 700)
      frontend.contentView.layoutSubtreeIfNeeded()
      for button in [
        controls.modeButton, controls.colorModeButton, controls.decreaseFontButton,
        controls.increaseFontButton,
      ]:
        button.checkVisibleIn(controls)
      let
        mode = controls.modeButton.rectToView(controls.modeButton.bounds(), controls)
        color = controls.colorModeButton.rectToView(
          controls.colorModeButton.bounds(), controls
        )
        decrease = controls.decreaseFontButton.rectToView(
          controls.decreaseFontButton.bounds(), controls
        )
        increase = controls.increaseFontButton.rectToView(
          controls.increaseFontButton.bounds(), controls
        )
      check mode.maxX <= color.minX
      check color.maxX < decrease.minX
      check decrease.maxX <= increase.minX
