import std/[monotimes, options, os, strutils, tempfiles, times, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo
import fixtures/ui

const FixtureDirectory = currentSourcePath().parentDir / "fixtures"

type PreviewReselection = ref object of DynamicAgent
  frontend: KosmoApplication
  identifier: string
  triggered: bool
  selected: bool
  closeInstead: bool

proc reselectPreview(spy: PreviewReselection) {.slot.} =
  if not spy.triggered:
    spy.triggered = true
    if spy.closeInstead:
      let index = spy.frontend.documentTabs.indexOfDocumentTabIdentifier(spy.identifier)
      if index >= 0:
        spy.selected = spy.frontend.documentTabs.closeDocumentTabAtIndex(index)
    else:
      spy.selected =
        spy.frontend.documentTabs.selectDocumentTabWithIdentifier(spy.identifier)

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
    let scroll = first.scrollView()
    let wheelPoint = scroll.pointToWindow(
      initPoint(scroll.bounds().size.width / 2, scroll.bounds().size.height / 2)
    )
    require frontend.window.scrollWheelAt(wheelPoint, deltaY = -0.25)
    let normalDistance = scroll.contentOffset().y
    require normalDistance > 0
    scroll.contentOffset = initPoint(0, 0)
    require frontend.window.scrollWheelAt(
      wheelPoint, deltaY = -0.25, modifiers = {nimkit.kmControl}
    )
    check abs(scroll.contentOffset().y - normalDistance * 3) < 0.01
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

  test "budget eviction restores preview folds, selection, scroll, and style":
    let
      root = createTempDir("kosmo-markdown-budget-", "")
      firstPath = root / "first.md"
      secondPath = root / "second.md"
      frontend = newKosmoApplication(
        newApplication("Markdown budget"), monitorsGitStatus = false
      )
    writeFile(
      firstPath,
      "# Main\n\n## Folded\n\nHidden content\n\n## Keep\n\n" &
        "Visible content.\n\n".repeat(80),
    )
    writeFile(secondPath, "# Other\n\nSecond document.\n")
    defer:
      frontend.close()
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 800, 500)
    frontend.contentView.layoutSubtreeIfNeeded()
    frontend.markdownPreviewByteBudget = 0
    check frontend.markdownPreviewByteBudget == 0
    check frontend.isMarkdownPreviewWorkPending()
    require frontend.openPath(firstPath)
    let first = frontend.editorPane.markdownView
    require first.waitForMarkdownParsing()
    require first.waitForMarkdownLayout()
    let fold = first.textView().buttonWithLabel("Folded")
    require not fold.isNil
    require fold.accessibilityPerformAction(AccessibilityActionCollapse)
    require first.waitForMarkdownRendering()
    require first.waitForMarkdownLayout()
    first.textView().selectedRange = initTextRange(1, 2)
    first.scrollView().scrollTo(initPoint(0, 24))
    let
      selected = first.textView().selectedRange()
      offset = first.scrollView().contentOffset()
      style = first.markdownStyle()
      firstTab = frontend.documentTabs.selectedDocumentTabIdentifier
    require offset.y > 0
    require frontend.openPath(secondPath)
    let second = frontend.editorPane.markdownView
    require second.waitForMarkdownParsing()
    let evictionDeadline = getMonoTime() + initDuration(seconds = 30)
    while not first.markdownDocumentOwner().isNil and getMonoTime() < evictionDeadline:
      discard second.pollMarkdownParsing()
      sleep(1)
    require first.markdownDocumentOwner().isNil
    let settledDeadline = getMonoTime() + initDuration(seconds = 30)
    while frontend.isMarkdownPreviewWorkPending() and getMonoTime() < settledDeadline:
      discard second.pollMarkdownParsing()
      second.layoutSubtreeIfNeeded()
      sleep(1)
    check not frontend.isMarkdownPreviewWorkPending()
    require frontend.documentTabs.selectDocumentTabWithIdentifier(firstTab)
    let restored = frontend.editorPane.markdownView
    require restored.waitForMarkdownParsing()
    require restored.waitForMarkdownLayout()
    let restoreDeadline = getMonoTime() + initDuration(seconds = 30)
    while (
      restored.textView().selectedRange() != selected or
      restored.scrollView().contentOffset() != offset
    ) and getMonoTime() < restoreDeadline
    :
      discard restored.pollMarkdownParsing()
      restored.layoutSubtreeIfNeeded()
      sleep(1)
    check restored.textView().selectedRange() == selected
    check restored.scrollView().contentOffset() == offset
    check restored.markdownStyle() == style
    let restoredFold = restored.textView().buttonWithLabel("Folded")
    require not restoredFold.isNil
    check restoredFold.accessibilityValue() == "collapsed"
    check "Hidden content" notin restored.textStorage().stringValue()

  test "reselecting during eviction keeps the replacement preview":
    let
      root = createTempDir("kosmo-markdown-reentrant-", "")
      firstPath = root / "first.md"
      secondPath = root / "second.md"
      frontend = newKosmoApplication(
        newApplication("Reentrant Markdown eviction"), monitorsGitStatus = false
      )
    writeFile(firstPath, "# First document\n")
    writeFile(secondPath, "# Second document\n")
    defer:
      frontend.close()
      removeFile(firstPath)
      removeFile(secondPath)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 800, 500)
    frontend.contentView.layoutSubtreeIfNeeded()
    frontend.markdownPreviewByteBudget = 0
    require frontend.openPath(firstPath)
    let oldView = frontend.editorPane.markdownView
    require oldView.waitForMarkdownParsing()
    let spy = PreviewReselection(
      frontend: frontend,
      identifier: frontend.documentTabs.selectedDocumentTabIdentifier,
    )
    oldView.connect(markdownRetainedCostDidChange, spy, reselectPreview)
    defer:
      oldView.disconnect(markdownRetainedCostDidChange, spy, reselectPreview)
    require frontend.openPath(secondPath)
    let deadline = getMonoTime() + initDuration(seconds = 30)
    while not spy.triggered and getMonoTime() < deadline:
      discard frontend.editorPane.markdownView.pollMarkdownParsing()
      sleep(1)
    require spy.triggered
    require spy.selected
    let replacement = frontend.editorPane.markdownView
    check replacement != oldView
    require replacement.waitForMarkdownParsing()
    check "First document" in replacement.textStorage().stringValue()
    check frontend.documentTabs.selectedDocumentTabIdentifier == spy.identifier

  test "refresh respects reentrant tab selection and close":
    for closeInstead in [false, true]:
      let
        root = createTempDir("kosmo-markdown-refresh-reentrant-", "")
        firstPath = root / "first.md"
        secondPath = root / "second.md"
        frontend = newKosmoApplication(
          newApplication("Reentrant Markdown refresh"), monitorsGitStatus = false
        )
      writeFile(firstPath, "# First original\n")
      writeFile(secondPath, "# Second document\n")
      defer:
        frontend.close()
        removeFile(firstPath)
        removeFile(secondPath)
        removeDir(root)
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.frame = rect(0, 0, 800, 500)
      frontend.contentView.layoutSubtreeIfNeeded()
      require frontend.openPath(firstPath)
      let firstTab = frontend.documentTabs.selectedDocumentTabIdentifier
      require frontend.editorPane.markdownView.waitForMarkdownParsing()
      require frontend.openPath(secondPath)
      let secondTab = frontend.documentTabs.selectedDocumentTabIdentifier
      require frontend.editorPane.markdownView.waitForMarkdownParsing()
      require frontend.documentTabs.selectDocumentTabWithIdentifier(firstTab)
      let first = frontend.editorPane.markdownView
      require first.waitForMarkdownParsing()
      let spy = PreviewReselection(
        frontend: frontend,
        identifier: (if closeInstead: firstTab else: secondTab),
        closeInstead: closeInstead,
      )
      first.connect(markdownRetainedCostDidChange, spy, reselectPreview)
      defer:
        first.disconnect(markdownRetainedCostDidChange, spy, reselectPreview)
      writeFile(firstPath, "# First changed\n")
      frontend.editorView.editor.reloadUnmodifiedFile(firstPath)
      frontend.editorView.refresh()
      let deadline = getMonoTime() + initDuration(seconds = 30)
      while not spy.triggered and getMonoTime() < deadline:
        discard frontend.editorPane.markdownView.pollMarkdownParsing()
        sleep(1)
      require spy.triggered
      require spy.selected
      require frontend.documentTabs.selectedDocumentTabIdentifier == secondTab
      let second = frontend.editorPane.markdownView
      require second.waitForMarkdownParsing()
      check "Second document" in second.textStorage().stringValue()

  test "split previews share a document while keeping pane state independent":
    let
      root = createTempDir("kosmo-markdown-shared-", "")
      path = root / "shared.md"
      frontend = newKosmoApplication(
        newApplication("Shared Markdown previews"), monitorsGitStatus = false
      )
    writeFile(path, "# Shared\n\n" & "Visible text.\n\n".repeat(40))
    defer:
      frontend.close()
      removeFile(path)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 1000, 600)
    frontend.contentView.layoutSubtreeIfNeeded()
    frontend.markdownPreviewByteBudget = 0
    require frontend.openPath(path)
    let first = frontend.editorPane.markdownView
    require first.waitForMarkdownParsing()
    require frontend.window.makeFirstResponder(first)
    discard frontend.window.sendAction(actionSelector(KosmoSplitVerticalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    let groups = frontend.editorGroups()
    require groups.len == 2
    for group in groups:
      group.editorView.refresh()
      require group.pane.contentView == View(group.pane.markdownView)
      require group.pane.markdownView.waitForMarkdownParsing()
    let
      left = groups[0].pane.markdownView
      right = groups[1].pane.markdownView
    check left != right
    require not left.markdownDocumentOwner().isNil
    check left.markdownDocumentOwner() == right.markdownDocumentOwner()
    left.textView().selectedRange = initTextRange(1, 2)
    right.textView().selectedRange = initTextRange(5, 3)
    check left.textView().selectedRange == initTextRange(1, 2)
    check right.textView().selectedRange == initTextRange(5, 3)
    discard left.pollMarkdownParsing()
    discard right.pollMarkdownParsing()
    check not left.markdownDocumentOwner().isNil
    check left.markdownDocumentOwner() == right.markdownDocumentOwner()

  test "closing a pending preview cannot restore stale content on reopen":
    let
      root = createTempDir("kosmo-markdown-pending-close-", "")
      path = root / "pending.md"
      frontend = newKosmoApplication(
        newApplication("Pending Markdown preview"), monitorsGitStatus = false
      )
    writeFile(path, "# Old content\n\n" & "Old paragraph.\n\n".repeat(3000))
    defer:
      frontend.close()
      removeFile(path)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 800, 500)
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.openPath(path)
    let
      oldView = frontend.editorPane.markdownView
      oldOwner = oldView.markdownDocumentOwner()
    require not oldOwner.isNil
    require oldOwner.markdownOwnerRetention().pending
    check frontend.isMarkdownPreviewWorkPending()
    require frontend.documentTabs.closeDocumentTabAtIndex(0)
    if oldOwner.markdownOwnerRetention().pending:
      check frontend.isMarkdownPreviewWorkPending()
    writeFile(path, "# New content\n\nFresh document.\n")
    require frontend.openPath(path)
    let reopened = frontend.editorPane.markdownView
    require reopened.waitForMarkdownParsing()
    let deadline = getMonoTime() + initDuration(seconds = 30)
    while oldOwner.markdownOwnerRetention().pending and getMonoTime() < deadline:
      discard reopened.pollMarkdownParsing()
      sleep(1)
    require not oldOwner.markdownOwnerRetention().pending
    check reopened.markdownDocumentOwner() != oldOwner
    check "New content" in reopened.textStorage().stringValue()
    check "Old content" notin reopened.textStorage().stringValue()

  test "custom Markdown parser falls back when the document changes":
    let
      root = createTempDir("kosmo-markdown-custom-parser-", "")
      path = root / "custom.md"
      frontend = newKosmoApplication(
        newApplication("Custom Markdown parser"), monitorsGitStatus = false
      )
    writeFile(path, "# Original\n")
    defer:
      frontend.close()
      removeFile(path)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 800, 500)
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.openPath(path)
    let preview = frontend.editorPane.markdownView
    require preview.waitForMarkdownParsing()
    let config = initMarkdownParserConfig()
    swap(config.blockParsers[1], config.blockParsers[2])
    preview.markdownConfig = config
    writeFile(path, "# Updated\n")
    frontend.editorView.editor.reloadUnmodifiedFile(path)
    frontend.editorView.refresh()
    require preview.waitForMarkdownParsing()
    check preview.markdownDocumentOwner().isNil
    check "Updated" in preview.textStorage().stringValue()

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

  test "cached preview follows edits and reload while unchanged refresh keeps state":
    let
      root = createTempDir("kosmo-markdown-version-", "")
      path = root / "version.md"
      frontend = newKosmoApplication(
        newApplication("Markdown version"), monitorsGitStatus = false
      )
    writeFile(path, "# Original heading\n\nFirst version.\n")
    defer:
      frontend.close()
      removeFile(path)
      removeDir(root)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 800, 600)
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.openPath(path)
    let
      preview = frontend.editorPane.markdownView
      editor = frontend.editorView.editor
      id = editor.tabs()[0].id
      initialVersion = editor.bufferContentVersion(id)
    require initialVersion.isSome
    require preview.waitForMarkdownParsing()
    preview.textView().selectedRange = initTextRange(1, 3)
    for iteration in 0 ..< 3:
      discard iteration
      frontend.editorView.refresh()
      check editor.bufferContentVersion(id) == initialVersion
      check frontend.editorPane.markdownView == preview
      check not preview.isMarkdownParsing()
      check preview.textView().selectedRange == initTextRange(1, 3)

    frontend.contentView.layoutSubtreeIfNeeded()
    let
      button = frontend.editorPane.markdownControls.increaseFontButton
      oldSize = preview.markdownStyle().bodyFontSize
      bounds = button.bounds()
    require frontend.window.clickAt(
      button.pointToWindow(initPoint(bounds.size.width / 2, bounds.size.height / 2))
    )
    require preview.waitForMarkdownParsing()
    require preview.waitForMarkdownLayout()
    check preview.markdownStyle().bodyFontSize > oldSize
    check "Original heading" in preview.textStorage().stringValue()
    check editor.bufferContentVersion(id) == initialVersion

    writeFile(path, "# Reloaded heading\n\nChanged on disk.\n")
    editor.reloadUnmodifiedFile(path)
    require editor.bufferContentVersion(id).isSome
    check editor.bufferContentVersion(id) != initialVersion
    frontend.editorView.refresh()
    require preview.waitForMarkdownParsing()
    check "Reloaded heading" in preview.textStorage().stringValue()

    require frontend.documentTabs.closeDocumentTabAtIndex(0)
    check editor.bufferContentVersion(id).isNone
    require frontend.openPath(path)
    let reopened = frontend.editorPane.markdownView
    require reopened.waitForMarkdownParsing()
    check "Reloaded heading" in reopened.textStorage().stringValue()
    check editor.tabs()[0].id != id

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
