import std/[options, os, strutils, tempfiles, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

const FixtureDirectory = currentSourcePath().parentDir / "fixtures"

suite "Kosmo Markdown activation":
  test "returning to an unchanged Markdown tab reuses its rendered preview":
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
    check firstScrollOffset.y > 0
    let identifier = frontend.documentTabs.selectedDocumentTabIdentifier
    require frontend.openPath(secondPath)
    let second = frontend.editorPane.markdownView
    let distinctPreviews = second != first
    require distinctPreviews
    require second.waitForMarkdownParsing()
    discard buildRenders(second)
    for iteration in 0 ..< 3:
      discard iteration
      require frontend.documentTabs.selectDocumentTabWithIdentifier(identifier)
      check not frontend.editorPane.markdownView.isMarkdownParsing()
      let restoredFirstPreview = frontend.editorPane.markdownView == first
      check restoredFirstPreview
      check first.textView().selectedRange == initTextRange(2, 3)
      check first.scrollView().contentOffset() == firstScrollOffset
      require frontend.editorPane.markdownView.waitForMarkdownParsing()
      discard buildRenders(frontend.editorPane.markdownView)
      for tab in frontend.editorView.editor.tabs():
        check not tab.modified
      require frontend.documentTabs.selectDocumentTabAtIndex(1)
      let restoredSecondPreview = frontend.editorPane.markdownView == second
      check restoredSecondPreview
      check not frontend.editorPane.markdownView.isMarkdownParsing()
      require frontend.editorPane.markdownView.waitForMarkdownParsing()
    require frontend.documentTabs.selectDocumentTabWithIdentifier(identifier)
    require frontend.documentTabs.closeDocumentTabAtIndex(0)
    check first.markdown == ""
    require first.waitForMarkdownParsing()
    check second.markdown.len > 0

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

  test "each pane retains its three most recently used previews":
    let
      root = createTempDir("kosmo-markdown-lru-", "")
      frontend =
        newKosmoApplication(newApplication("Markdown LRU"), monitorsGitStatus = false)
    var paths: seq[string]
    for index in 0 ..< 4:
      let path = root / ("preview-" & $index & ".md")
      writeFile(path, "# Preview " & $index & "\n")
      paths.add path
    defer:
      frontend.close()
      for path in paths:
        removeFile(path)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    var
      identifiers: seq[string]
      previews: seq[MarkdownView]
    for index in 0 ..< 3:
      require frontend.openPath(paths[index])
      identifiers.add frontend.documentTabs.selectedDocumentTabIdentifier
      previews.add frontend.editorPane.markdownView
      require previews[^1].waitForMarkdownParsing()
    require frontend.documentTabs.selectDocumentTabWithIdentifier(identifiers[0])
    let promotedFirst = frontend.editorPane.markdownView == previews[0]
    check promotedFirst
    require frontend.openPath(paths[3])
    identifiers.add frontend.documentTabs.selectedDocumentTabIdentifier
    previews.add frontend.editorPane.markdownView
    require previews[^1].waitForMarkdownParsing()
    check previews[1].markdown == ""
    check previews[0].markdown.len > 0
    check previews[2].markdown.len > 0
    require frontend.documentTabs.selectDocumentTabWithIdentifier(identifiers[0])
    let restoredPromotedPreview = frontend.editorPane.markdownView == previews[0]
    check restoredPromotedPreview
    check not frontend.editorPane.markdownView.isMarkdownParsing()
    require frontend.documentTabs.selectDocumentTabWithIdentifier(identifiers[2])
    let restoredRecentPreview = frontend.editorPane.markdownView == previews[2]
    check restoredRecentPreview
    check not frontend.editorPane.markdownView.isMarkdownParsing()
    require frontend.documentTabs.selectDocumentTabWithIdentifier(identifiers[1])
    let recreatedEvictedPreview = frontend.editorPane.markdownView != previews[1]
    check recreatedEvictedPreview
    check frontend.editorPane.markdownView.isMarkdownParsing()
    require frontend.editorPane.markdownView.waitForMarkdownParsing()
    check frontend.editorPane.markdownView.markdown.strip() == "# Preview 1"

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
    let preview = frontend.editorPane.markdownView
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
    let reusedPreview = frontend.editorPane.markdownView == preview
    check reusedPreview
    require preview.waitForMarkdownParsing()
    check "Updated" in preview.markdown
    discard frontend.window.sendAction(actionSelector(KosmoSaveAction))
    check not frontend.editorView.editor.tabs()[0].modified
    check "Updated" in readFile(path)
