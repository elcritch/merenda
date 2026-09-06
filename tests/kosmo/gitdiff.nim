import std/[monotimes, os, osproc, strutils, tempfiles, times, unicode, unittest]
import merenda/nimkit
import merenda/kosmo/kosmo

proc git(root: string, args: varargs[string]) =
  var arguments = @["-C", root]
  arguments.add args
  let process = startProcess("git", args = arguments, options = {poUsePath})
  defer:
    process.close()
  doAssert process.waitForExit() == 0

proc initRepository(root: string) =
  git(root, "init", "-q")
  git(root, "config", "user.name", "Kosmo Diff Test")
  git(root, "config", "user.email", "kosmo-test@example.invalid")

proc firstResponderIs(window: Window, expected: Responder): bool =
  window.firstResponder == expected

suite "Kosmo Git diff":
  test "full context includes staged unstaged untracked deleted and binary files":
    let root = createTempDir("kosmo-git-diff-", "")
    defer:
      removeDir(root)
    initRepository(root)
    let original = "first line\n" & "context\n".repeat(30) & "old value\nlast line\n"
    writeFile(root / "source.nim", original)
    writeFile(root / "deleted.txt", "deleted content\n")
    writeFile(root / "binary.dat", "\0before")
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    git(root, "branch", "-M", "diff-preview")
    writeFile(root / "source.nim", original.replace("old value", "new value"))
    writeFile(root / "staged.txt", "staged content\n")
    git(root, "add", "staged.txt")
    writeFile(root / "new [file].txt", "untracked\n```\n# not a heading\n")
    writeFile(root / "binary.dat", "\0after")
    removeFile(root / "deleted.txt")
    let snapshot = readGitDiff(root)
    check snapshot.errorMessage == ""
    check snapshot.files.len == 5
    check snapshot.branch == "diff-preview"
    for file in snapshot.files:
      case file.path
      of "source.nim":
        check file.additions == 1
        check file.deletions == 1
        check " first line" in file.patch
        check " last line" in file.patch
        check "-old value" in file.patch
        check "+new value" in file.patch
      of "deleted.txt":
        check "-deleted content" in file.patch
      of "staged.txt":
        check "+staged content" in file.patch
      of "new [file].txt":
        check file.additions == 3
        check file.deletions == 0
        check "+untracked" in file.patch
      of "binary.dat":
        check file.binary
        check file.additions == 0
        check "Binary files" in file.patch
      else:
        check false

  test "empty clean and non-repository states are explicit":
    let root = createTempDir("kosmo-git-diff-empty-", "")
    defer:
      removeDir(root)
    check readGitDiff(root).errorMessage.len > 0
    initRepository(root)
    check readGitDiff(root).files.len == 0
    writeFile(root / "first.txt", "first commit content\n")
    git(root, "add", ".")
    let initial = readGitDiff(root)
    check initial.errorMessage == ""
    require initial.files.len == 1
    check "+first commit content" in initial.files[0].patch
    check initial.branch.len > 0
    check initial.files[0].additions == 1
    git(root, "commit", "-qm", "Initial")
    let clean = readGitDiff(root)
    check clean.errorMessage == ""
    check clean.files.len == 0
    git(root, "checkout", "--detach", "-q")
    check readGitDiff(root).branch.startsWith("Detached HEAD · ")

  test "file heading links collapse and expand complete highlighted code blocks":
    let root = createTempDir("kosmo-git-diff-panel-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "source.txt", "old text\n")
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    writeFile(root / "source.txt", "new text\n")
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 800, 600)
    panel.layoutSubtreeIfNeeded()
    panel.frame = rect(0, 0, 300, 600)
    panel.layoutSubtreeIfNeeded()
    check panel.collapseButton.frame().maxX <= panel.bounds().maxX
    require panel.waitForDiff()
    require panel.markdownView.waitForMarkdownParsing()
    check panel.snapshot.errorMessage == ""
    require panel.snapshot.files.len == 1
    let rendered = panel.markdownView.textStorage().stringValue()
    check "-old text" in rendered
    check "+new text" in rendered
    let addedIndex = rendered[0 ..< rendered.find("+new text")].runeLen
    let deletedIndex = rendered[0 ..< rendered.find("-old text")].runeLen
    check panel.markdownView.textStorage().attributesAt(addedIndex).foregroundColor ==
      panel.markdownView.markdownStyle().syntaxTokenColors[stcString]
    check panel.markdownView.textStorage().attributesAt(deletedIndex).foregroundColor ==
      panel.markdownView.markdownStyle().syntaxTokenColors[stcKeyword]
    let headingIndex = rendered[0 ..< rendered.find("source.txt")].runeLen
    check panel.markdownView.textView().openLinkAtIndex(headingIndex)
    require panel.markdownView.waitForMarkdownParsing()
    check panel.isFileCollapsed(0)
    check "new text" notin panel.markdownView.textStorage().stringValue()
    let collapsedDisclosure = panel.disclosureButtonForFile(0)
    require not collapsedDisclosure.isNil
    check collapsedDisclosure.accessibilityRole() == arDisclosureButton
    check collapsedDisclosure.accessibilityLabel() == "source.txt"
    check collapsedDisclosure.accessibilityValue() == "collapsed"
    check collapsedDisclosure.accessibilitySupportsAction(AccessibilityActionPress)
    check collapsedDisclosure.accessibilitySupportsAction(AccessibilityActionExpand)
    check collapsedDisclosure.accessibilityPerformAction(AccessibilityActionExpand)
    require panel.markdownView.waitForMarkdownParsing()
    check not panel.isFileCollapsed(0)
    check "+new text" in panel.markdownView.textStorage().stringValue()
    let expandedDisclosure = panel.disclosureButtonForFile(0)
    require not expandedDisclosure.isNil
    check expandedDisclosure.accessibilityValue() == "expanded"
    check expandedDisclosure.accessibilitySupportsAction(AccessibilityActionCollapse)
    check expandedDisclosure.performKeyEquivalentInChain(
      KeyEvent(key: keySpace, keyCode: keySpace.ord)
    )
    require panel.markdownView.waitForMarkdownParsing()
    check panel.isFileCollapsed(0)
    let keyboardDisclosure = panel.disclosureButtonForFile(0)
    require not keyboardDisclosure.isNil
    check keyboardDisclosure.performKeyEquivalentInChain(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
    )
    require panel.markdownView.waitForMarkdownParsing()
    check not panel.isFileCollapsed(0)
    writeFile(root / "source.txt", "refreshed text\n")
    panel.refresh()
    require panel.waitForDiff()
    check "+refreshed text" in panel.snapshot.files[0].patch

  test "File menu exposes the Git diff action":
    let root = createTempDir("kosmo-git-diff-menu-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "menu.txt", "menu diff\n")
    let
      app = newApplication("Kosmo Diff Menu")
      frontend = newKosmoApplication(app, filePath = root, monitorsGitStatus = false)
    defer:
      frontend.close()
    app.addWindow(frontend.window)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.frame = rect(0, 0, 1000, 700)
    frontend.contentView.layoutSubtreeIfNeeded()
    app.activateWindow(frontend.window)
    let item =
      app.mainMenu()[1].submenu().menuItemWithIdentifier(KosmoShowGitDiffAction)
    require not item.isNil
    check item.title == "Show Git Diff"
    check item.keyEquivalent().key == keyG
    check item.modifierMask() == shortcutModifiers() + {nimkit.kmShift}
    check not item.target.isNil
    check item.perform(frontend.window)
    require not frontend.gitDiffPanel.isNil
    require frontend.gitDiffPanel.waitForDiff()

    check frontend.documentTabs.selectedDocumentTabIdentifier ==
      KosmoGitDiffTabIdentifier
    check frontend.editorPane.contentView == View(frontend.gitDiffPanel)
    check frontend.gitDiffPanel.snapshot.files.len == 1
    let
      originalPanel = frontend.gitDiffPanel
      expectedStyle = frontend.editorPane.markdownControls.markdownPresentationStyle()
      actualStyle = originalPanel.markdownView.markdownStyle()
    check actualStyle.backgroundColor == expectedStyle.backgroundColor
    check actualStyle.textColor == expectedStyle.textColor
    check actualStyle.headingFontSizes[1] == expectedStyle.bodyFontSize
    check actualStyle.syntaxTokenColors[stcString] ==
      expectedStyle.syntaxTokenColors[stcString]
    check actualStyle.syntaxTokenColors[stcKeyword] ==
      expectedStyle.syntaxTokenColors[stcKeyword]
    app.setAppearance(initAppearance(initMacOSDarkTheme()))
    let darkStyle = frontend.editorPane.markdownControls.markdownPresentationStyle()
    check originalPanel.markdownView.markdownStyle().backgroundColor ==
      darkStyle.backgroundColor
    check originalPanel.markdownView.markdownStyle().headingFontSizes[1] ==
      darkStyle.bodyFontSize
    check originalPanel.markdownView.markdownStyle().syntaxTokenColors[stcString] ==
      darkStyle.syntaxTokenColors[stcString]
    check item.perform(frontend.window)
    check frontend.gitDiffPanel == originalPanel
    require frontend.gitDiffPanel.waitForDiff()
    let closeItem =
      app.mainMenu()[1].submenu().menuItemWithIdentifier(KosmoCloseTabAction)
    check closeItem.perform(frontend.window)
    check frontend.gitDiffPanel.isNil
    check not frontend.window.isClosed()
    check frontend.window.dispatchKeyDown(
      KeyEvent(
        key: keyG, keyCode: keyG.ord, modifiers: shortcutModifiers() + {nimkit.kmShift}
      )
    )
    require not frontend.gitDiffPanel.isNil
    check frontend.gitDiffPanel != originalPanel
    check frontend.documentTabs.selectedDocumentTabIdentifier ==
      KosmoGitDiffTabIdentifier
    require frontend.gitDiffPanel.waitForDiff()

    let tabIndex =
      frontend.documentTabs.indexOfDocumentTabIdentifier(KosmoGitDiffTabIdentifier)
    require tabIndex >= 0
    let
      tabBounds = frontend.documentTabs.documentTabRect(tabIndex)
      dragStart = frontend.documentTabs.pointToWindow(
        initPoint(tabBounds.minX + 30, tabBounds.minY + 12)
      )
      dragEnd = initPoint(
        frontend.window.frame().size.width + 180,
        frontend.window.frame().size.height + 180,
      )
      detachedPanel = frontend.gitDiffPanel
    require frontend.window.mouseDownAt(dragStart)
    require frontend.window.mouseDraggedAt(dragEnd)
    require frontend.window.mouseUpAt(dragEnd)
    require frontend.detachedEditorWindows().len == 1
    let detachedWindow = frontend.detachedEditorWindows()[0]
    app.activateWindow(frontend.window)
    check item.perform(frontend.window)
    check app.keyWindow() == detachedWindow
    check frontend.gitDiffPanel == detachedPanel
    detachedWindow.close()
    check frontend.gitDiffPanel.isNil
    check frontend.detachedEditorWindows().len == 0
    app.activateWindow(frontend.window)
    check item.perform(frontend.window)
    require not frontend.gitDiffPanel.isNil
    check frontend.gitDiffPanel != detachedPanel
    check frontend.documentTabs.selectedDocumentTabIdentifier ==
      KosmoGitDiffTabIdentifier
    require frontend.gitDiffPanel.waitForDiff()

  test "Git diff tab participates in control-W pane navigation":
    let root = createTempDir("kosmo-git-diff-pane-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "pane.txt", "pane diff\n")
    let
      app = newApplication("Kosmo Diff Pane Navigation")
      frontend = newKosmoApplication(app, filePath = root, monitorsGitStatus = false)
    defer:
      frontend.close()
    app.addWindow(frontend.window)
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    app.activateWindow(frontend.window)
    require frontend.window.makeFirstResponder(frontend.editorView)
    require frontend.window.sendAction(actionSelector(KosmoSplitVerticalAction))
    frontend.contentView.layoutSubtreeIfNeeded()
    require frontend.editorGroups().len == 2
    require frontend.showGitDiff()
    let groups = frontend.editorGroups()
    var
      diffGroup: KosmoEditorGroup
      otherGroup: KosmoEditorGroup
    for group in groups:
      if group.pane.contentView == View(frontend.gitDiffPanel):
        diffGroup = group
      else:
        otherGroup = group
    require not diffGroup.isNil
    require not otherGroup.isNil
    require frontend.window.makeFirstResponder(
      frontend.gitDiffPanel.markdownView.textView()
    )
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
    )
    require frontend.window.dispatchKeyDown(
      KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
    )
    check frontend.window.firstResponder == otherGroup.editorView

  test "keyboard focus reveals disclosure headings in long diffs":
    let root = createTempDir("kosmo-git-diff-disclosure-focus-", "")
    defer:
      removeDir(root)
    initRepository(root)
    let original = "old value\n" & "context line\n".repeat(160)
    writeFile(root / "aardvark.txt", "unchanged first\n")
    writeFile(root / "first.txt", original)
    writeFile(root / "second.txt", "old second\n")
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    writeFile(root / "first.txt", original.replace("old value", "new value"))
    writeFile(root / "second.txt", "new second\n")
    let
      window = newWindow("Git Diff Disclosure Focus", frame = rect(0, 0, 600, 280))
      panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
      window.close()
    panel.frame = rect(0, 0, 600, 280)
    window.setContentView(panel)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    require panel.markdownView.waitForMarkdownParsing()
    require panel.snapshot.files.len == 2
    let
      firstDisclosure = panel.disclosureButtonForFile(0)
      secondDisclosure = panel.disclosureButtonForFile(1)
      textView = panel.markdownView.textView()
    require not firstDisclosure.isNil
    require not secondDisclosure.isNil
    check secondDisclosure.frame().intersection(textView.visibleRect()).isEmpty
    window.recalculateKeyViewLoop()
    require window.makeFirstResponder(firstDisclosure)
    require window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check window.firstResponderIs(secondDisclosure)
    check not secondDisclosure.frame().intersection(textView.visibleRect()).isEmpty
    writeFile(root / "aardvark.txt", "new first\n")
    panel.refresh()
    require panel.waitForDiff()
    require panel.markdownView.waitForMarkdownParsing()
    check window.firstResponderIs(secondDisclosure)
    require panel.snapshot.files.len == 3
    check panel.snapshot.files[0].path == "aardvark.txt"
    let newFirstDisclosure = panel.disclosureButtonForFile(0)
    require not newFirstDisclosure.isNil
    require window.makeFirstResponder(textView)
    window.recalculateKeyViewLoop()
    require window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check window.firstResponderIs(newFirstDisclosure)

  when defined(posix):
    test "closing interrupts an in-flight Git process":
      let
        root = createTempDir("kosmo-git-diff-cancel-", "")
        marker = root / "started"
        originalPath = getEnv("PATH")
      defer:
        putEnv("PATH", originalPath)
        removeDir(root)
      putEnv("PATH", root & ":" & originalPath)
      for closeOutput in [false, true]:
        if fileExists(marker):
          removeFile(marker)
        writeFile(
          root / "git",
          "#!/bin/sh\nprintf started > " & quoteShell(marker) & "\n" &
            (if closeOutput: "exec 1>&- 2>&-\n" else: "") & "exec /bin/sleep 30\n",
        )
        setFilePermissions(root / "git", {fpUserRead, fpUserWrite, fpUserExec})
        let panel = newKosmoGitDiffPanel(root)
        defer:
          panel.close()
        let deadline = getMonoTime() + initDuration(seconds = 5)
        while not fileExists(marker) and getMonoTime() < deadline:
          sleep(5)
        require fileExists(marker)
        let started = getMonoTime()
        panel.close()
        check (getMonoTime() - started).inMilliseconds < 2000
