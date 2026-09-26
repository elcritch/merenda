import std/[strutils, unittest]

import merenda/nimkit
import merenda/kosmo/kosmo

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
      pasteboard.declareTypes([PasteboardTypeTextStorage])
      discard pasteboard.setAttributedString(newAttributedString("stale selection"))
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
      check pasteboard.availableTypeFromArray(
        [PasteboardTypeTextStorage, PasteboardTypeString]
      ) == PasteboardTypeString
