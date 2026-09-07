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
  test "summary and expanded files share wheel scrolling":
    let root = createTempDir("kosmo-diff-scroll-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "one.nim", "let value = 1\n".repeat(100))
    writeFile(root / "two.nim", "let other = 2\n")
    let window = newWindow("Git Diff Scrolling", frame = rect(0, 0, 700, 280))
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
      window.close()
    panel.frame = rect(0, 0, 700, 280)
    window.setContentView(panel)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    require panel.snapshot.errorMessage == ""
    require panel.snapshot.files.len == 2
    panel.layoutSubtreeIfNeeded()
    check not panel.markdownView.scrollView().hasVerticalScroller()
    check panel.markdownView.scrollView().maximumContentOffset().y == 0
    require panel.scrollView.maximumContentOffset().y > 0
    require window.scrollWheelAt(initPoint(100, 150), deltaY = -3)
    check panel.scrollView.contentOffset().y > 0
    check panel.markdownView.scrollView().contentOffset().y == 0
    panel.toggleFile(0)
    require panel.waitForDiff()
    panel.layoutSubtreeIfNeeded()
    let code = panel.textViewForFile(0)
    panel.scrollView.contentOffset = initPoint(0, code.frame().origin.y)
    let before = panel.scrollView.contentOffset().y
    require window.scrollWheelAt(initPoint(100, 150), deltaY = -3)
    check panel.scrollView.contentOffset().y > before
    let after = panel.scrollView.contentOffset().y
    require window.scrollWheelAt(initPoint(100, 150), deltaY = 2)
    check panel.scrollView.contentOffset().y < after
    let momentumStart = panel.scrollView.contentOffset().y
    require window.dispatchScrollWheel(
      ScrollEvent(location: initPoint(100, 150), deltaY: -2, momentumPhase: sepBegan)
    )
    require window.dispatchScrollWheel(
      ScrollEvent(location: initPoint(100, 150), deltaY: -2, momentumPhase: sepChanged)
    )
    discard window.dispatchScrollWheel(
      ScrollEvent(location: initPoint(100, 150), momentumPhase: sepEnded)
    )
    check panel.scrollView.contentOffset().y > momentumStart
    panel.scrollView.contentOffset = initPoint(0, 0)
    require window.scrollWheelAt(initPoint(100, 150), deltaY = -3)
    check panel.scrollView.contentOffset().y > 0
    check panel.markdownView.scrollView().contentOffset().y == 0

  test "standard hunks retain syntax from omitted full-file context":
    let root = createTempDir("kosmo-diff-hunks-", "")
    defer:
      removeDir(root)
    initRepository(root)
    var original = "#[\n"
    for index in 0 ..< 60:
      original.add "comment line " & $index & "\n"
    original.add "]#\n"
    writeFile(root / "source.nim", original)
    git(root, "add", ".")
    git(root, "commit", "-qm", "base")
    writeFile(
      root / "source.nim",
      original.replace("comment line 20\n", "changed twenty\n").replace(
        "comment line 45\n", "changed forty five\n"
      ),
    )
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 700, 500)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    require panel.snapshot.files.len == 1
    check panel.isFileCollapsed(0)
    let storage = panel.textViewForFile(0).textStorage()
    let shown = storage.stringValue()
    check "comment line 0\n" notin shown
    check " #[\n" notin shown
    check "+changed twenty" in shown
    check "+changed forty five" in shown
    let at = shown[0 ..< shown.find("changed twenty")].runeLen
    check storage.attributesAt(at).foregroundColor ==
      panel.markdownView.markdownStyle().syntaxTokenColors[stcComment]
    panel.toggleFile(0)
    require panel.waitForDiff()
    check panel.textViewForFile(0).layoutManager().snapshotBuildThreadId() !=
      getThreadId()

  test "file sections are retained independently and new files start collapsed":
    let root = createTempDir("kosmo-diff-sections-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "one.nim", "let one = 1\n")
    writeFile(root / "two.nim", "let two = 2\n")
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 700, 500)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    check panel.isFileCollapsed(0)
    check panel.isFileCollapsed(1)
    let retained = panel.textViewForFile(1).textStorage()
    panel.toggleFile(0)
    require panel.waitForDiff()
    writeFile(root / "one.nim", "let one = 3\n")
    panel.refresh()
    require panel.waitForDiff()
    check not panel.isFileCollapsed(0)
    check panel.isFileCollapsed(1)
    check panel.textViewForFile(1).textStorage() == retained
    check panel.highlightBuildCount() == 3
  test "closing one diff does not stop shared Markdown and highlighting workers":
    let root = createTempDir("kosmo-diff-shared-workers-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "one.nim", "let one = 1\n")
    let closedPanel = newKosmoGitDiffPanel(root)
    closedPanel.close()
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    let markdown = newMarkdownView("```go\nfunc main() {}\n```")
    require panel.waitForDiff()
    require markdown.waitForMarkdownParsing()
    check panel.highlightBuildCount() == 1
    check panel.highlightThreadId() != getThreadId()
    check markdown.markdownParseWorkerThreadId() != getThreadId()
    check closedPanel.snapshot.files.len == 0

  test "diff highlighting is reused across collapse theme and unchanged refresh":
    let root = createTempDir("kosmo-diff-cache-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "one.nim", "let one = 1\n")
    writeFile(root / "two.nim", "let two = 2\r\n")
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 600, 400)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    let initialCount = panel.highlightBuildCount()
    check initialCount == 2
    check panel.highlightThreadId() != 0
    check panel.highlightThreadId() != getThreadId()
    panel.toggleFile(0)
    require panel.waitForDiff()
    panel.toggleFile(0)
    require panel.waitForDiff()
    check panel.highlightBuildCount() == initialCount
    var style = panel.markdownView.markdownStyle()
    style.syntaxTokenColors[stcKeyword] = color(0.2, 0.7, 0.3, 1)
    panel.markdownStyle = style
    require panel.waitForDiff()
    check panel.highlightBuildCount() == initialCount
    panel.refresh()
    require panel.waitForDiff()
    check panel.highlightBuildCount() == initialCount
    writeFile(root / "one.nim", "let one = 10\n")
    panel.refresh()
    require panel.waitForDiff()
    check panel.highlightBuildCount() == initialCount + 1

  test "Matter highlights both file versions independently beneath diff tints":
    let root = createTempDir("kosmo-diff-matter-", "")
    defer:
      removeDir(root)
    initRepository(root)
    writeFile(root / "source.nim", "let text = \"\"\"\nold café\n\"\"\"\n")
    git(root, "add", ".")
    git(root, "commit", "-qm", "Initial")
    writeFile(root / "source.nim", "let text = 42\n")
    let panel = newKosmoGitDiffPanel(root)
    defer:
      panel.close()
    panel.frame = rect(0, 0, 600, 500)
    panel.layoutSubtreeIfNeeded()
    require panel.waitForDiff()
    let
      storage = panel.textViewForFile(0).textStorage()
      text = storage.stringValue()
      style = panel.markdownView.markdownStyle()
    for (needle, token) in [
      ("+let", stcKeyword), ("42", stcNumber), ("old café", stcString)
    ]:
      let location = text.find(needle)
      require location >= 0
      let index = text[0 ..< location].runeLen + (if needle[0] == '+': 1 else: 0)
      check storage.attributesAt(index).foregroundColor == style.syntaxTokenColors[
        token
      ]
      check storage.attributesAt(index).lineBackgroundColor.a > 0

  test "standard hunks include staged unstaged untracked deleted and binary files":
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
        check " first line" notin file.patch
        check " first line" in file.syntaxPatch
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

  test "native file headings collapse and expand retained highlighted sections":
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
    check panel.snapshot.errorMessage == ""
    require panel.snapshot.files.len == 1
    check panel.isFileCollapsed(0)
    panel.toggleFile(0)
    require panel.waitForDiff()
    let rendered = panel.textViewForFile(0).textStorage().stringValue()
    check "-old text" in rendered
    check "+new text" in rendered
    let addedIndex = rendered[0 ..< rendered.find("+new text")].runeLen
    let deletedIndex = rendered[0 ..< rendered.find("-old text")].runeLen
    let addedTint = panel
      .textViewForFile(0)
      .textStorage()
      .attributesAt(addedIndex).lineBackgroundColor
    let deletedTint = panel
      .textViewForFile(0)
      .textStorage()
      .attributesAt(deletedIndex).lineBackgroundColor
    check addedTint.a > 0
    check addedTint.g > addedTint.r
    check deletedTint.a > 0
    check deletedTint.r > deletedTint.g
    check panel.disclosureButtonForFile(0).accessibilityPerformAction(
      AccessibilityActionPress
    )
    require panel.waitForDiff()
    check panel.isFileCollapsed(0)
    check panel.textViewForFile(0).hidden
    let collapsedDisclosure = panel.disclosureButtonForFile(0)
    require not collapsedDisclosure.isNil
    check collapsedDisclosure.accessibilityRole() == arDisclosureButton
    check collapsedDisclosure.accessibilityLabel() == "source.txt"
    check collapsedDisclosure.accessibilityValue() == "collapsed"
    check collapsedDisclosure.accessibilitySupportsAction(AccessibilityActionPress)
    check collapsedDisclosure.accessibilitySupportsAction(AccessibilityActionExpand)
    check collapsedDisclosure.accessibilityPerformAction(AccessibilityActionExpand)
    require panel.waitForDiff()
    check not panel.isFileCollapsed(0)
    check "+new text" in panel.textViewForFile(0).textStorage().stringValue()
    let expandedDisclosure = panel.disclosureButtonForFile(0)
    require not expandedDisclosure.isNil
    check expandedDisclosure.accessibilityValue() == "expanded"
    check expandedDisclosure.accessibilitySupportsAction(AccessibilityActionCollapse)
    check expandedDisclosure.performKeyEquivalentInChain(
      KeyEvent(key: keySpace, keyCode: keySpace.ord)
    )
    require panel.waitForDiff()
    check panel.isFileCollapsed(0)
    let keyboardDisclosure = panel.disclosureButtonForFile(0)
    require not keyboardDisclosure.isNil
    check keyboardDisclosure.performKeyEquivalentInChain(
      KeyEvent(key: keyEnter, keyCode: keyEnter.ord)
    )
    require panel.waitForDiff()
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
    require panel.snapshot.files.len == 2
    panel.toggleFile(0)
    require panel.waitForDiff()
    let
      firstDisclosure = panel.disclosureButtonForFile(0)
      secondDisclosure = panel.disclosureButtonForFile(1)
      textView = panel.markdownView.textView()
    require not firstDisclosure.isNil
    require not secondDisclosure.isNil
    check secondDisclosure
    .frame()
    .intersection(panel.documentView.visibleRect()).isEmpty
    window.recalculateKeyViewLoop()
    require window.makeFirstResponder(firstDisclosure)
    require window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check window.firstResponderIs(secondDisclosure)
    check not secondDisclosure
    .frame()
    .intersection(panel.documentView.visibleRect()).isEmpty
    writeFile(root / "aardvark.txt", "new first\n")
    panel.refresh()
    require panel.waitForDiff()
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
