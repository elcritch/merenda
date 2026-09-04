## Terminal scrollback search and Kosmo's floating search controls.

import std/unittest

import merenda/nimkit
import merenda/kosmo/kosmo

suite "Kosmo terminal search":
  test "matching is case insensitive and retains terminal cell positions":
    let session = newCompactTerminalSession(columns = 12, rows = 3)
    session.processOutput("alpha one\r\nbeta\r\nALPHA two")

    let matches = terminalSearchMatches(session, "Alpha")

    require matches.len == 2
    check matches[0] ==
      TerminalSelection(
        anchor: initTerminalPosition(0, 0), extent: initTerminalPosition(0, 5)
      )
    check matches[1] ==
      TerminalSelection(
        anchor: initTerminalPosition(2, 0), extent: initTerminalPosition(2, 5)
      )

  test "the search field navigates, wraps, reveals scrollback, and dismisses":
    let
      session = newCompactTerminalSession(columns = 12, rows = 2)
      terminal = newKosmoTerminalView(session, frame = rect(0, 0, 640, 320))
      window = newWindow("Kosmo Terminal Search Test", frame = rect(0, 0, 640, 320))
    session.processOutput("alpha old\r\nmiddle\r\nALPHA new")
    window.setContentView(terminal)
    terminal.layoutSubtreeIfNeeded()
    defer:
      window.close()

    check window.makeFirstResponder(terminal)
    check terminal.showSearch()
    check terminal.searchVisible()
    check window.fieldEditorClient() == terminal.searchField()
    let searchFieldFrame =
      terminal.searchField().rectToView(terminal.searchField().bounds(), terminal)
    check searchFieldFrame.origin.x > 100.0'f32
    check searchFieldFrame.origin.y <= 40.0'f32
    check searchFieldFrame.size.width > 300.0'f32
    check window.dispatchTextInput("alpha")
    check terminal.searchMatchCount() == 2
    check terminal.selectedSearchMatch() == 1
    check terminal.selectionText() == "ALPHA"
    check terminal.scrollPosition() == 0.0'f32

    check window.dispatchKeyDown(KeyEvent(key: keyArrowUp, keyCode: keyArrowUp.ord))
    check terminal.selectedSearchMatch() == 0
    check terminal.selectionText() == "alpha"
    check terminal.scrollPosition() > 0.0'f32

    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check terminal.selectedSearchMatch() == 1
    check terminal.selectionText() == "ALPHA"

    check window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
    check not terminal.searchVisible()
    check not terminal.hasSelection()
    check window.firstResponder() == terminal

  test "the terminal-local Find shortcut opens search in a terminal tab":
    let frontend = newKosmoApplication(
      newApplication("Kosmo Terminal Search Shortcut Test"), monitorsGitStatus = false
    )
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    defer:
      frontend.close()

    require frontend.newTerminal()
    require frontend.editorPane.contentView of KosmoTerminalView
    let terminal = KosmoTerminalView(frontend.editorPane.contentView)

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: terminalShortcutModifiers())
    )
    check terminal.searchVisible()
    check frontend.window.fieldEditorClient() == terminal.searchField()
