## Hybrid terminal routing against a live PTY, with bounded readiness and teardown.

import std/[monotimes, options, os, strutils, tempfiles, times, unittest]
import sigils/threads
import merenda/nimkit
import merenda/kosmo/kosmo
import ../support/terminalhelpers

proc waitForTerminalText(view: TerminalView, text: string): bool =
  let deadline = getMonoTime() + initDuration(seconds = 10)
  while getMonoTime() < deadline:
    discard getCurrentSigilThread().pollAll(NonBlocking)
    discard view.poll()
    if text in view.session().screen().plainText().splitWhitespace().join(" "):
      return true
    sleep(1)

suite "Kosmo terminal shortcut PTY input":
  when defined(posix):
    test "new terminals restore the saved theme":
      let
        root = createTempDir("kosmo-terminal-theme-", "")
        path = root / "config.json"
        app = newApplication("Kosmo Terminal Theme")
        manager = newKosmoWindowManager(app, configPath = path)
        frontend = newKosmoApplication(manager, monitorsGitStatus = false)
        themes = frontend.editorView.editor.availableMoeThemes()
      var terminal: KosmoTerminalView
      defer:
        manager.close()
        if not terminal.isNil:
          terminal.session().waitForCommands()
        removeDir(root)
      require themes.len > 1
      require frontend.setTerminalTheme(themes[1].identifier)
      check loadKosmoConfig(path).terminalTheme == themes[1].identifier
      let second = newKosmoApplication(manager, monitorsGitStatus = false)
      require second.newTerminal()
      require second.editorGroups()[0].pane.contentView of KosmoTerminalView
      terminal = KosmoTerminalView(second.editorGroups()[0].pane.contentView)
      check terminal.palette.background ==
        color(
          themes[1].preview.background.red.float32 / 255,
          themes[1].preview.background.green.float32 / 255,
          themes[1].preview.background.blue.float32 / 255,
          1.0,
        )
      check terminal.palette != initTerminalPalette()

    test "terminal search edits stay in the focused field until it is dismissed":
      let
        session = spawnTerminalViewSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf 'SEARCH_READY\\r\\nalpha\\r\\n'; " &
              "dd bs=1 count=2 2>/dev/null | od -An -tx1"
          ),
          columns = 80,
          rows = 4,
        )
        terminal = newKosmoTerminalView(session, frame = rect(0, 0, 800, 160))
        frontend = newKosmoApplication(
          newApplication("Terminal Search Input"), monitorsGitStatus = false
        )
        window = frontend.window
      defer:
        frontend.close()
        terminal.close()
        session.waitForCommands()
        window.close()
      window.setContentView(frontend.contentView)
      frontend.contentView.frame = rect(0, 0, 1000, 700)
      frontend.contentView.layoutSubtreeIfNeeded()
      require terminal.waitForTerminalText("SEARCH_READY")
      require frontend.openDocument(
        newKosmoPaneDocument("search-input-terminal", "Terminal", terminal)
      )
      require window.makeFirstResponder(terminal)
      require window.dispatchKeyDown(
        KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: terminalShortcutModifiers())
      )
      require window.fieldEditorClient() == terminal.searchField()
      require window.dispatchTextInput("alpha")
      let backspace = KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord)
      require window.dispatchKeyDown(backspace)
      check terminal.searchField().text() == "alph"
      require window.dispatchKeyDown(
        KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord)
      )
      require window.dispatchKeyDown(backspace)
      check terminal.searchField().text() == "alh"
      terminal.searchField().selectedRange = initTextRange(0, 3)
      require window.dispatchKeyDown(backspace)
      check terminal.searchField().text() == ""
      require window.dispatchKeyDown(backspace)
      check terminal.searchField().text() == ""
      check window.fieldEditorClient() == terminal.searchField()

      require window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
      require window.firstResponder() == Responder(terminal)
      require window.dispatchTextInput("x")
      require window.dispatchKeyDown(backspace)
      # Only input sent after dismissing search may reach the PTY.
      require terminal.waitForTerminalText("78 7f")

    test "modifier-click opens a terminal source location in Kosmo":
      for extension in ["nim", "md"]:
        let
          root = createTempDir("kosmo-terminal-source-click-", "")
          filename = "source." & extension
          path = root / filename
          originalShell = getEnv("SHELL")
        putEnv("SHELL", "/bin/sh")
        writeFile(path, "first line\nsecond line\nthird line\n")
        let
          app = newApplication("Kosmo Terminal Source Link")
          frontend = newKosmoApplication(app, root, monitorsGitStatus = false)
          window = frontend.window
        var terminal: KosmoTerminalView
        defer:
          frontend.close()
          if not terminal.isNil:
            terminal.session().waitForCommands()
          window.close()
          putEnv("SHELL", originalShell)
          removeDir(root)
        app.addWindow(window)
        window.setContentView(frontend.contentView)
        frontend.contentView.frame = rect(0, 0, 1200, 720)
        frontend.contentView.layoutSubtreeIfNeeded()
        require frontend.newTerminal()
        frontend.contentView.layoutSubtreeIfNeeded()
        let group = frontend.editorGroups()[0]
        require group.pane.contentView of KosmoTerminalView
        terminal = KosmoTerminalView(group.pane.contentView)
        terminal.session().write(
          "stty -echo; printf '\\033[2J\\033[H%s.%s:2:4' source " & extension &
            "; read merenda_wait\r"
        )
        require terminal.waitForTerminalText(filename & ":2:4")
        let
          metrics = terminal.monoTextMetrics()
          point = terminal.pointToWindow(
            initPoint(
              terminal.padding() + metrics.cellWidth * 3.5'f32,
              terminal.padding() + metrics.lineHeight * 0.5'f32,
            )
          )
        require window.mouseDownAt(point, modifiers = terminalLinkModifiers())
        require window.mouseUpAt(point, modifiers = terminalLinkModifiers())
        var activePath: Option[string]
        for tab in group.editorView.editor.tabs():
          if tab.active:
            activePath = tab.filePath
        check activePath == some(path)
        check group.editorView.editor.bufferCursor() ==
          KosmoBufferCursor(line: 1, column: 3)
        check window.firstResponder() == Responder(group.editorView)

    test "show terminal shortcut creates a right split or reuses the nearest right pane":
      let originalShell = getEnv("SHELL")
      putEnv("SHELL", "/bin/sh")
      defer:
        putEnv("SHELL", originalShell)
      for rightPaneCount in 0 .. 2:
        let
          app = newApplication("Kosmo Right Terminal Shortcut")
          frontend = newKosmoApplication(app, monitorsGitStatus = false)
          window = frontend.window
          shortcut =
            KeyEvent(key: keyJ, keyCode: keyJ.ord, modifiers: shortcutModifiers())
        var terminal: KosmoTerminalView
        defer:
          frontend.close()
          if not terminal.isNil:
            terminal.session().waitForCommands()
          window.close()
        app.addWindow(window)
        window.setContentView(frontend.contentView)
        frontend.contentView.frame = rect(0, 0, 1200, 720)
        frontend.contentView.layoutSubtreeIfNeeded()
        app.activateWindow(window)
        require window.makeFirstResponder(frontend.editorView)
        if rightPaneCount > 0:
          require window.sendAction(actionSelector(KosmoSplitVerticalAction))
        if rightPaneCount > 1:
          require window.sendAction(actionSelector(KosmoSplitHorizontalAction))
        let
          beforeGroups = frontend.editorGroups()
          source = beforeGroups[0]
          sourceTabCount = source.pane.documentTabs.len
          bufferCount = frontend.editorView.editor.tabs().len
        require window.makeFirstResponder(source.editorView)
        require window.dispatchKeyDown(shortcut)
        frontend.contentView.layoutSubtreeIfNeeded()
        let groups = frontend.editorGroups()
        require groups.len == max(rightPaneCount + 1, 2)
        let target = groups[1]
        require target.pane.contentView of KosmoTerminalView
        terminal = KosmoTerminalView(target.pane.contentView)
        terminal.session().write("printf 'KOSMO_%s\\n' TERMINAL_READY\r")
        require terminal.waitForTerminalText("KOSMO_TERMINAL_READY")
        check window.firstResponder() == Responder(terminal)
        check source.pane.documentTabs.len == sourceTabCount
        check source.documents.len == 0
        check target.documents.len == 1
        check frontend.editorView.editor.tabs().len == bufferCount
        let
          sourceRect = source.panel.rectToView(source.panel.bounds(), frontend.dockView)
          targetRect = target.panel.rectToView(target.panel.bounds(), frontend.dockView)
        check sourceRect.maxX <= targetRect.minX
        if rightPaneCount == 0:
          check target.pane.documentTabs.len == 1
        if rightPaneCount == 2:
          check groups[2].documents.len == 0
        require window.dispatchKeyDown(shortcut)
        check window.firstResponder() == Responder(terminal)
        require window.makeFirstResponder(source.editorView)
        require window.dispatchKeyDown(shortcut)
        check window.firstResponder() == Responder(terminal)
        check target.documents.len == 1

    test "editor pane shortcuts do not leak text into the destination PTY":
      let
        session = spawnTerminalViewSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf 'READY\\n'; dd bs=1 count=2 2>/dev/null | od -An -tx1"
          ),
          columns = 80,
          rows = 4,
        )
        terminal = newKosmoTerminalView(session, frame = rect(0, 0, 800, 160))
        frontend = newKosmoApplication(
          newApplication("Editor to Terminal Shortcuts"), monitorsGitStatus = false
        )
        window = frontend.window
      defer:
        frontend.close()
        terminal.close()
        session.waitForCommands()
        window.close()
      window.setContentView(frontend.contentView)
      frontend.contentView.frame = rect(0, 0, 1000, 700)
      frontend.contentView.layoutSubtreeIfNeeded()
      require terminal.waitForTerminalText("READY")
      require frontend.openDocument(
        newKosmoPaneDocument("shortcut-terminal", "Terminal", terminal)
      )
      let prefix = KeyEvent(key: keyW, keyCode: keyW.ord, modifiers: {kmControl})
      require window.dispatchKeyDown(prefix)
      require window.dispatchKeyDown(KeyEvent(key: keyV, keyCode: keyV.ord))
      frontend.contentView.layoutSubtreeIfNeeded()
      let groups = frontend.editorGroups()
      require groups.len == 2
      for text in ["l", ""]:
        require window.makeFirstResponder(groups[0].editorView)
        require window.dispatchKeyDown(prefix)
        require window.dispatchKeyDown(
          KeyEvent(key: keyL, keyCode: keyL.ord, text: text)
        )
        let terminalFocused = window.firstResponder() == Responder(terminal)
        require terminalFocused
        require window.dispatchTextInput(if text.len > 0: text else: "λ")
      for key in [keyX, keyZ]:
        discard window.dispatchKeyDown(KeyEvent(key: key, keyCode: key.ord))
        require window.dispatchTextInput(if key == keyX: "x" else: "z")
      # Only the two ordinary characters should reach the PTY: no l or λ.
      require terminal.waitForTerminalText("78 7a")

    test "quoted and raw shortcuts reach the PTY exactly once":
      let
        session = spawnTerminalViewSession(
          initTerminalSpawnOptions(
            command =
              "stty raw -echo; printf 'READY\\n'; dd bs=1 count=8 2>/dev/null | od -An -tx1"
          ),
          columns = 80,
          rows = 4,
        )
        terminal = newKosmoTerminalView(session, frame = rect(0, 0, 800, 160))
        window = newWindow("Quoted Terminal Shortcuts", frame = rect(0, 0, 800, 160))
      defer:
        terminal.close()
        session.waitForCommands()
        window.close()
      var paneCommands: seq[KosmoPaneCommand]
      terminal.paneCommandHandler = proc(command: KosmoPaneCommand): bool =
        paneCommands.add command
        true
      window.setContentView(terminal)
      require window.makeFirstResponder(terminal)
      require terminal.waitForTerminalText("READY")
      let control = proc(key: Key): KeyEvent =
        KeyEvent(key: key, keyCode: key.ord, modifiers: {kmControl})
      require window.dispatchKeyDown(control(keyW))
      require window.dispatchKeyDown(KeyEvent(key: keyV, keyCode: keyV.ord))
      # Native physical events omit text; the commit can follow a different layout.
      require window.dispatchTextInput("ν")
      check paneCommands == @[kpcSplitRight]
      for key in [keyC, keyV, keyW]:
        require window.dispatchKeyDown(control(keyBackslash))
        require window.dispatchKeyDown(control(key))
      require window.dispatchKeyDown(control(keyV))
      terminal.terminalInputPolicy = KosmoTerminalInputPolicy.Raw
      for key in [keyBackslash, keyW, keyC, keyV]:
        require window.dispatchKeyDown(control(key))
      require terminal.waitForTerminalText("03 16 17 16 1c 17 03 16")
      check paneCommands == @[kpcSplitRight]
