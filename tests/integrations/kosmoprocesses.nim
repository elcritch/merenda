## Kosmo behaviors that need live shells or child-process teardown.
import std/[monotimes, os, strutils, tempfiles, times, unittest]

import sigils/threads
import merenda/nimkit
import merenda/kosmo/[kosmo, cli]

proc pollUntilText(
    session: TerminalViewSession, expected: string, timeout = initDuration(seconds = 10)
): bool =
  let deadline = getMonoTime() + timeout
  while getMonoTime() < deadline:
    discard session.poll()
    if expected in session.screen().plainText().splitWhitespace().join(" "):
      return true
    sleep(5)

proc terminalCellPoint(view: TerminalView, row, column: int): Point =
  let metrics = view.monoTextMetrics()
  view.pointToWindow(
    initPoint(
      view.padding() + metrics.cellWidth * (column.float32 + 0.5'f32),
      view.padding() + metrics.lineHeight * (row.float32 + 0.5'f32),
    )
  )

suite "Kosmo live terminal clipboard":
  when defined(posix):
    test "Edit menu copy and paste target the focused terminal":
      let
        app = newApplication("Kosmo Terminal Clipboard Test")
        frontend = newKosmoApplication(app, monitorsGitStatus = false)
        session = spawnCompactTerminalSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf 'copy target\\nready\\n'; " &
              "dd bs=1 count=6 2>/dev/null | od -An -tx1"
          ),
          columns = 40,
          rows = 4,
        )
        terminal = newTerminalView(session, frame = rect(0, 0, 400, 120))
        pasteboard = generalPasteboard()
        previousClipboard = pasteboard.plainText()
      defer:
        terminal.close()
        discard pasteboard.setPlainText(previousClipboard)
        frontend.close()
        frontend.window.close()

      frontend.application.addWindow(frontend.window)
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.layoutSubtreeIfNeeded()
      check frontend.openDocument(
        newKosmoPaneDocument(
          "kosmo.test.terminal",
          "Terminal",
          terminal,
          onClose = proc(document: KosmoPaneDocument): bool =
            discard document
            terminal.close()
            true,
        )
      )
      frontend.contentView.layoutSubtreeIfNeeded()
      require frontend.window.firstResponder() == Responder(terminal)
      require session.pollUntilText("ready")
      discard terminal.poll()

      let
        dragStart = terminal.terminalCellPoint(0, 0)
        dragEnd = terminal.terminalCellPoint(0, 3)
        primary = frontend.shortcutProfile().primaryModifiers()
        copyEvent = KeyEvent(key: keyC, keyCode: keyC.ord, modifiers: primary)
        pasteEvent = KeyEvent(key: keyV, keyCode: keyV.ord, modifiers: primary)
      check frontend.window.mouseDownAt(dragStart)
      check frontend.window.mouseDraggedAt(dragEnd)
      check frontend.window.mouseUpAt(dragEnd)
      require terminal.selectionText() == "copy"

      check frontend.application.performMenuKeyEquivalent(copyEvent)
      check pasteboard.plainText() == "copy"

      terminal.clearSelection()
      discard pasteboard.setPlainText("unchanged")
      check frontend.application.performMenuKeyEquivalent(copyEvent)
      check pasteboard.plainText() == "unchanged"

      discard pasteboard.setPlainText("paste")
      check frontend.application.performMenuKeyEquivalent(pasteEvent)
      check frontend.window.dispatchKeyDown(
        KeyEvent(key: keyC, keyCode: keyC.ord, modifiers: {kmControl})
      )
      require session.pollUntilText("70 61 73 74 65 03")
      check "70 61 73 74 65 03" in
        session.screen().plainText().splitWhitespace().join(" ")

    test "new terminals inherit the current terminal directory and follow it":
      let
        root = createTempDir("merenda-kosmo-terminal-cwd-", "")
        nested = root / "nested"
        app = newApplication("Kosmo Terminal Directory Test")
        frontend = newKosmoApplication(app, filePath = root, monitorsGitStatus = false)
      createDir(nested)
      let expectedDirectory = expandFilename(nested)
      defer:
        frontend.close()
        removeDir(root)
      app.addWindow(frontend.window)
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.layoutSubtreeIfNeeded()
      app.activateWindow(frontend.window)
      require frontend.window.makeFirstResponder(frontend.editorView)

      require frontend.newTerminal()
      require frontend.editorPane.contentView of TerminalView
      let firstTerminal = TerminalView(frontend.editorPane.contentView)
      let firstIdentifier = frontend.documentTabs.selectedDocumentTabIdentifier
      firstTerminal.session().processOutput(
        "\x1b]7;file://kosmo-test-host" & nested & "\x07"
      )
      check firstTerminal.session().screenInfo().currentDirectory ==
        "file://kosmo-test-host" & nested

      require frontend.newTerminal()
      require frontend.editorPane.contentView of TerminalView
      let secondTerminal = TerminalView(frontend.editorPane.contentView)
      let secondIdentifier = frontend.documentTabs.selectedDocumentTabIdentifier
      let firstIndex =
        frontend.documentTabs.indexOfDocumentTabIdentifier(firstIdentifier)
      let secondIndex =
        frontend.documentTabs.indexOfDocumentTabIdentifier(secondIdentifier)
      check secondIndex == firstIndex + 1
      let checkDirectoryCommand =
        "if [ \"$PWD\" = " & quoteShell(expectedDirectory) &
        " ]; then printf KOSMO_CWD_MATCH; else printf KOSMO_CWD_MISMATCH; fi\n"
      require secondTerminal.sendInput(checkDirectoryCommand)
      check secondTerminal.session().pollUntilText("KOSMO_CWD_MATCH")

suite "Kosmo terminal focus input":
  when defined(posix):
    test "numbered panel switches restore focus reporting and shell input":
      let
        app = newApplication("Kosmo Live Terminal Focus Test")
        frontend = newKosmoApplication(app, monitorsGitStatus = false)
        session = spawnCompactTerminalSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf ready; " &
              "dd bs=1 count=8 2>/dev/null | od -An -tx1"
          )
        )
        terminal = newKosmoTerminalView(session)
      defer:
        terminal.close()
        frontend.close()
        frontend.window.close()
      app.addWindow(frontend.window)
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.layoutSubtreeIfNeeded()
      app.activateWindow(frontend.window)
      require frontend.openDocument(
        newKosmoPaneDocument("kosmo.test.focus-terminal", "Terminal", terminal)
      )
      require session.pollUntilText("ready")
      session.processOutput("\x1b[?1004h")

      let primary = frontend.shortcutProfile().primaryModifiers()
      require app.performMenuKeyEquivalent(
        KeyEvent(key: key1, keyCode: key1.ord, modifiers: primary)
      )
      require app.performMenuKeyEquivalent(
        KeyEvent(key: key2, keyCode: key2.ord, modifiers: primary)
      )
      let terminalFocused = frontend.window.firstResponder() == Responder(terminal)
      check terminalFocused
      require frontend.window.dispatchTextInput("x")
      require frontend.window.dispatchKeyDown(
        KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
      )
      # Focus-out, focus-in, x, and the shell's Control-W arrive exactly once.
      check session.pollUntilText("1b 5b 4f 1b 5b 49 78 17")

suite "Kosmo terminal split lifecycle":
  when defined(posix):
    test "terminal shortcut opens a tab that can create an independent split pane":
      let frontend = newKosmoApplication(newApplication("Kosmo Terminal Split Test"))
      defer:
        frontend.close()
      frontend.window.setContentView(frontend.contentView)
      frontend.contentView.layoutSubtreeIfNeeded()
      check frontend.window.makeFirstResponder(frontend.editorView)
      check frontend.window.dispatchKeyDown(
        KeyEvent(
          key: keyT,
          keyCode: keyT.ord,
          modifiers: shortcutModifiers() + {nimkit.kmShift},
        )
      )

      let
        terminalView = TerminalView(frontend.editorPane.contentView)
        sourceTabs = frontend.documentTabs
        tabRect = sourceTabs.documentTabRect(sourceTabs.selectedIndex())
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

      let groups = frontend.editorGroups()
      check groups.len == 2
      check groups[1].pane.contentView == View(terminalView)
      check groups[1].pane.documentTabs.len == 1
      check terminalView.session().running()

      frontend.contentView.layoutSubtreeIfNeeded()
      let editorPoint =
        groups[0].editorView.pointToWindow(initPoint(12.0'f32, 12.0'f32))
      check frontend.window.mouseDownAt(editorPoint)
      check frontend.window.mouseUpAt(editorPoint)
      check frontend.window.firstResponder() == Responder(groups[0].editorView)

      let terminalPoint = terminalView.pointToWindow(initPoint(12.0'f32, 12.0'f32))
      check frontend.window.mouseDownAt(terminalPoint)
      check frontend.window.mouseUpAt(terminalPoint)
      check frontend.window.firstResponder() == Responder(terminalView)
      check groups[1].pane.documentTabs.selectedDocumentTabIdentifier.startsWith(
        "kosmo.terminal."
      )

      check frontend.window.dispatchKeyDown(
        KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
      )
      check frontend.editorGroups().len == 2
      check frontend.window.sendAction(
        actionSelector(KosmoSplitVerticalAction), DynamicAgent(terminalView)
      )

      let splitGroups = frontend.editorGroups()
      require splitGroups.len == 3
      let
        duplicatedGroup = splitGroups[^1]
        duplicatedTerminal = TerminalView(duplicatedGroup.pane.contentView)
      check duplicatedGroup.documents[0].identifier != groups[1].documents[0].identifier
      check duplicatedTerminal != terminalView
      check terminalView.session().running()
      check duplicatedTerminal.session().running()

      check duplicatedGroup.pane.documentTabs.closeDocumentTabAtIndex(0)
      check frontend.editorGroups().len == 2
      check duplicatedTerminal.session().state() == tssClosed

      check groups[1].pane.documentTabs.closeDocumentTabAtIndex(0)
      check frontend.editorGroups().len == 1
      check frontend.dockView.len == 1
      check terminalView.session().state() == tssClosed

suite "Kosmo Git process lifecycle":
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
          discard getCurrentSigilThread().pollAll(NonBlocking)
          sleep(5)
        require fileExists(marker)
        let started = getMonoTime()
        panel.close()
        check (getMonoTime() - started).inMilliseconds < 2000

suite "Kosmo background launch":
  when not defined(windows):
    test "detached launcher preserves the requested directory and arguments":
      let root = createTempDir("merenda-kosmo-bg-", "")
      defer:
        removeDir(root)
      let
        helperPath = root / "record.sh"
        outputPath = root / "output.txt"
        commandLine = parseKosmoCommandLine(
          @[helperPath, outputPath, "argument with spaces", "--bg"]
        )
      writeFile(
        helperPath,
        """#!/bin/sh
printf '%s\n' "$PWD" > "$1.tmp"
printf '%s\n' "$2" >> "$1.tmp"
mv "$1.tmp" "$1"
""",
      )
      launchKosmoInBackground("/bin/sh", commandLine.arguments, root)

      let deadline = getMonoTime() + initDuration(seconds = 60)
      while not fileExists(outputPath) and getMonoTime() < deadline:
        sleep(10)
      require fileExists(outputPath)
      check readFile(outputPath) == expandFilename(root) & "\nargument with spaces\n"
