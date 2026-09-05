import std/[monotimes, os, strutils, times, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

proc pollUntilText(
    session: TerminalViewSession, expected: string, timeout = initDuration(seconds = 3)
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

suite "Kosmo terminal clipboard commands":
  when defined(posix):
    test "Edit menu copy rejoins a wrapped terminal line":
      let
        app = newApplication("Kosmo Wrapped Terminal Clipboard Test")
        frontend = newKosmoApplication(app, monitorsGitStatus = false)
        session = newCompactTerminalSession(columns = 12, rows = 4)
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
        newKosmoPaneDocument("kosmo.test.wrapped-terminal", "Terminal", terminal)
      )
      frontend.contentView.layoutSubtreeIfNeeded()
      require frontend.window.firstResponder() == Responder(terminal)

      let
        columns = session.screenInfo().columns
        originalLine = repeat('a', columns) & "tail"
      session.processOutput(originalLine)
      discard terminal.poll()

      let
        dragStart = terminal.terminalCellPoint(0, 0)
        dragEnd = terminal.terminalCellPoint(1, 3)
        copyEvent = KeyEvent(
          key: keyC,
          keyCode: keyC.ord,
          modifiers: frontend.shortcutProfile().primaryModifiers(),
        )
      check frontend.window.mouseDownAt(dragStart)
      check frontend.window.mouseDraggedAt(dragEnd)
      check frontend.window.mouseUpAt(dragEnd)

      check frontend.application.performMenuKeyEquivalent(copyEvent)
      check pasteboard.plainText() == originalLine

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
