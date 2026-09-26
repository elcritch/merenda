## Terminal scrollback search and Kosmo's floating search controls.

import std/unittest

import merenda/nimkit
import merenda/kosmo/kosmo
import fixtures/ui

func center(rect: Rect): Point =
  initPoint(
    rect.origin.x + rect.size.width / 2.0'f32,
    rect.origin.y + rect.size.height / 2.0'f32,
  )

suite "Kosmo terminal search":
  test "find shortcuts start at the bottom and traverse older output first":
    let
      session = newCompactTerminalSession(columns = 20, rows = 4)
      terminal = newKosmoTerminalView(session, frame = rect(0, 0, 640, 320))
      window = newWindow("Terminal find direction", frame = rect(0, 0, 640, 320))
    defer:
      window.close()
    session.processOutput("hit old\r\nhit middle\r\nhit newest")
    window.setContentView(terminal)
    terminal.layoutSubtreeIfNeeded()
    require terminal.showSearch()
    require window.dispatchTextInput("hit")
    check terminal.selectedSearchMatch() == 2
    let
      next = KeyEvent(key: keyG, keyCode: keyG.ord, modifiers: shortcutModifiers())
      previous = KeyEvent(
        key: keyG, keyCode: keyG.ord, modifiers: shortcutModifiers() + {nimkit.kmShift}
      )
    for expected in [1, 0, 2]:
      check window.dispatchKeyDown(next)
      check terminal.selectedSearchMatch() == expected
    for expected in [0, 1, 2]:
      check window.dispatchKeyDown(previous)
      check terminal.selectedSearchMatch() == expected
    check window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check terminal.selectedSearchMatch() == 1
    require window.makeFirstResponder(terminal)
    check window.dispatchKeyDown(next)
    check terminal.selectedSearchMatch() == 0
    check window.dispatchKeyDown(previous)
    check terminal.selectedSearchMatch() == 1

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
    terminal.searchField().checkVisibleIn(terminal)
    check window.dispatchTextInput("alpha")
    check window.dispatchKeyDown(KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord))
    check window.dispatchKeyDown(KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord))
    check terminal.searchField().text() == "alpa"
    check window.dispatchTextInput("h")
    check terminal.searchField().text() == "alpha"
    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord)
    )
    let
      previousButton = terminal.buttonWithLabel("Previous terminal output match")
      nextButton = terminal.buttonWithLabel("Next terminal output match")
      closeButton = terminal.buttonWithLabel("Close terminal output search")
    require not previousButton.isNil
    require not nextButton.isNil
    require not closeButton.isNil
    check not previousButton.bounds().isEmpty
    check not nextButton.bounds().isEmpty
    check not closeButton.bounds().isEmpty
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

    check window.clickAt(previousButton.pointToWindow(previousButton.bounds().center()))
    check terminal.selectedSearchMatch() == 0
    check terminal.selectionText() == "alpha"
    check terminal.scrollPosition() > 0.0'f32

    check window.clickAt(nextButton.pointToWindow(nextButton.bounds().center()))
    check terminal.selectedSearchMatch() == 1
    check terminal.selectionText() == "ALPHA"

    check window.clickAt(closeButton.pointToWindow(closeButton.bounds().center()))
    check not terminal.searchVisible()
    check not terminal.hasSelection()
    check window.firstResponder() == terminal

    check terminal.showSearch()
    check window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
    check not terminal.searchVisible()
    check window.firstResponder() == terminal

  test "the terminal-local Find shortcut opens search in a terminal tab":
    let frontend = newKosmoApplication(
      newApplication("Kosmo Terminal Search Shortcut Test"), monitorsGitStatus = false
    )
    frontend.window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    defer:
      frontend.close()

    let terminal = newKosmoTerminalView()
    require frontend.openDocument(
      newKosmoPaneDocument("search-terminal", "Terminal", terminal)
    )

    check frontend.window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: terminalShortcutModifiers())
    )
    check terminal.searchVisible()
    check frontend.window.fieldEditorClient() == terminal.searchField()
