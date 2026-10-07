## Terminal scrollback search and Kosmo's floating search controls.

import std/[strutils, unicode, unittest]
import ../support/terminalhelpers

import merenda/nimkit
import merenda/kosmo/kosmo
import merenda/nimkit/foundation/textsearch
import fixtures/ui

func center(rect: Rect): Point =
  initPoint(
    rect.origin.x + rect.size.width / 2.0'f32,
    rect.origin.y + rect.size.height / 2.0'f32,
  )

suite "Kosmo terminal search":
  test "search centers older output and keeps the latest matches at the history end":
    let
      session = newTerminalViewSession(columns = 20, rows = 5)
      terminal = newKosmoTerminalView(session)
      metrics = terminal.monoTextMetrics()
      padding = terminal.padding()
      frame = rect(
        0,
        0,
        padding * 2 + metrics.cellWidth * 20.25,
        padding * 2 + metrics.lineHeight * 5.25,
      )
      window = newWindow("Centered terminal search", frame = frame)
    defer:
      window.close()
    terminal.frame = frame
    window.setContentView(terminal)
    terminal.layoutSubtreeIfNeeded()
    session.waitForCommands()
    var output: string
    for row in 0 ..< 20:
      if row > 0:
        output.add "\r\n"
      output.add(if row in [10, 19]: "hit " else: "row ")
      output.add align($row, 2, '0')
    session.processOutput(output)
    discard terminal.pollSettled()
    require session.screenInfo().rows == 5
    require terminal.showSearch()
    require window.dispatchTextInput("hit")
    check terminal.selectionText() == "hit"
    check terminal.selection().anchor.row == 19
    check terminal.scrollPosition() == 0
    terminal.findPrevious()
    check terminal.selection().anchor.row == 10
    let info = session.screenInfo()
    let start = info.totalLineCount - info.rows - int(terminal.scrollPosition())
    check terminal.selection().anchor.row - start == info.rows div 2
    terminal.findNext()
    check terminal.selection().anchor.row == 19
    check terminal.scrollPosition() == 0

  test "Reni matches keep Unicode cells and cross wrapped output":
    let session = newTerminalViewSession(columns = 6, rows = 4)
    session.processOutput("λ猫catDOG\r\nend")
    session.waitForCommands()
    let matches =
      terminalSearchMatches(session, r"λ\K猫catdog", regularExpression = true)
    require matches.len == 1
    check matches[0] ==
      TerminalSelection(
        anchor: initTerminalPosition(0, 1), extent: initTerminalPosition(1, 3)
      )
    let positions = terminalSearchMatches(session, r"(?=猫)", regularExpression = true)
    require positions.len == 1
    check positions[0].anchor == initTerminalPosition(0, 1)
    check positions[0].extent == positions[0].anchor
    let wide = terminalSearchMatches(session, "猫", regularExpression = true)
    require wide.len == 1
    check wide[0].extent == initTerminalPosition(0, 3)
    check terminalSearchMatches(session, r"cat|end", regularExpression = true).len == 2
    check terminalSearchMatches(session, "[").len == 0
    check terminalSearchMatches(session, "", regularExpression = true).len == 0
    expect TextSearchError:
      discard terminalSearchMatches(session, "[", regularExpression = true)

  test "terminal expression controls recover from invalid queries":
    let
      session = newTerminalViewSession(columns = 20, rows = 3)
      terminal = newKosmoTerminalView(session, frame = rect(0, 0, 640, 320))
      window = newWindow("Terminal regex", frame = rect(0, 0, 640, 320))
    defer:
      window.close()
    session.processOutput("a.b axb\r\nλcat cat")
    session.waitForCommands()
    window.setContentView(terminal)
    terminal.layoutSubtreeIfNeeded()
    require terminal.showSearch()
    require window.dispatchTextInput("a.b")
    check terminal.searchMatchCount() == 1
    let toggle = terminal.buttonWithLabel("Use Reni regular expressions")
    require not toggle.isNil
    toggle.checkVisibleIn(terminal)
    require window.clickAt(toggle.pointToWindow(initPoint(14, 14)))
    check terminal.searchMatchCount() == 2
    check terminal.selectionText() == "axb"
    terminal.searchField().selectedRange = initTextRange(0, 3)
    require window.dispatchTextInput(r"λ\Kcat")
    check terminal.searchMatchCount() == 1
    check terminal.selectionText() == "cat"
    terminal.searchField().selectedRange =
      initTextRange(0, terminal.searchField().text().runeLen)
    require window.dispatchTextInput("[")
    check terminal.searchMatchCount() == 0
    check not terminal.hasSelection()
    check not terminal.buttonWithLabel("Next terminal output match").enabled
    terminal.searchField().selectedRange = initTextRange(0, 1)
    require window.dispatchTextInput("cat")
    check terminal.searchMatchCount() == 2
    check terminal.selectionText() == "cat"
    require window.clickAt(toggle.pointToWindow(initPoint(14, 14)))
    check toggle.state == bsOff
    check terminal.searchMatchCount() == 2

  test "find shortcuts start at the bottom and traverse older output first":
    let
      session = newTerminalViewSession(columns = 20, rows = 4)
      terminal = newKosmoTerminalView(session, frame = rect(0, 0, 640, 320))
      window = newWindow("Terminal find direction", frame = rect(0, 0, 640, 320))
    defer:
      window.close()
    session.processOutput("hit old\r\nhit middle\r\nhit newest")
    session.waitForCommands()
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
    let session = newTerminalViewSession(columns = 12, rows = 3)
    session.processOutput("alpha one\r\nbeta\r\nALPHA two")
    session.waitForCommands()

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
      session = newTerminalViewSession(columns = 12, rows = 2)
      terminal = newKosmoTerminalView(session, frame = rect(0, 0, 640, 320))
      window = newWindow("Kosmo Terminal Search Test", frame = rect(0, 0, 640, 320))
    session.processOutput("alpha old\r\nmiddle\r\nALPHA new")
    session.waitForCommands()
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
