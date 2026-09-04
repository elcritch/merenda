## Terminal scrollback search and Kosmo's floating search controls.

import std/[unicode, unittest]

import figdraw

import merenda/nimkit
import merenda/kosmo/kosmo

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add rune

proc rendersText(view: View, text: string): bool =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkText and node.renderedText() == text:
      return true

proc rendersBackdropBlur(view: View): bool =
  let renders = buildRenders(view)
  if DefaultDrawLevel notin renders:
    return
  for node in renders[DefaultDrawLevel].nodes:
    if node.kind == nkBackdropBlur and node.backdropBlur.blur > 0.0'f32:
      return true

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
    check searchFieldFrame.size.height >= 30.0'f32
    check window.dispatchTextInput("alpha")
    check terminal.searchField().selectedRange() == initTextRange(5, 0)
    check window.dispatchKeyDown(KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord))
    check terminal.searchField().selectedRange() == initTextRange(4, 0)
    check window.dispatchKeyDown(KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord))
    check terminal.searchField().text() == "alpa"
    check terminal.searchField().selectedRange() == initTextRange(3, 0)
    check window.dispatchTextInput("h")
    check terminal.searchField().text() == "alpha"
    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord)
    )
    check terminal.searchField().selectedRange() == initTextRange(5, 0)
    check terminal.rendersText("^")
    check terminal.rendersText("v")
    check terminal.rendersText("×")
    check terminal.rendersBackdropBlur()
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
