## Moe-backed search through Kosmo's shared floating search controls.

import std/unittest

import merenda/nimkit
import merenda/kosmo/kosmo
import fixtures/ui

suite "Kosmo editor search":
  test "the Moe facade searches, wraps, reverses, and owns highlight state":
    let editor = newKosmoEditor(text = "alpha one\nbeta\nalpha two")
    defer:
      editor.close()

    check editor.searchFrom("alpha", KosmoBufferCursor(line: 0, column: 0))
    check editor.bufferCursor() == KosmoBufferCursor(line: 2, column: 0)
    check editor.searchQuery() == "alpha"

    check editor.searchFrom(
      "alpha", editor.bufferCursor(), KosmoSearchDirection.Forward
    )
    check editor.bufferCursor() == KosmoBufferCursor(line: 0, column: 0)

    check editor.searchFrom(
      "alpha", editor.bufferCursor(), KosmoSearchDirection.Backward
    )
    check editor.bufferCursor() == KosmoBufferCursor(line: 2, column: 0)

    editor.clearSearch()
    check editor.searchQuery().len == 0

    check not editor.searchFrom("[", editor.bufferCursor())
    check editor.searchQuery().len == 0

  test "the editor Find shortcut opens and drives the floating search widget":
    let
      editor = newKosmoEditor(text = "alpha one\nbeta\nalpha two")
      view = newKosmoEditorView(editor)
      window = newWindow("Kosmo Editor Search Test", frame = rect(0, 0, 640, 320))
    window.setContentView(view)
    view.layoutSubtreeIfNeeded()
    view.refresh()
    defer:
      window.close()
      editor.close()

    check window.makeFirstResponder(view)
    check window.dispatchKeyDown(
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: editorSearchShortcutModifiers())
    )
    check view.searchVisible()
    check window.fieldEditorClient() == view.searchField()
    view.searchField().checkVisibleIn(view)
    check window.dispatchTextInput("alpha")
    check window.dispatchKeyDown(KeyEvent(key: keyArrowLeft, keyCode: keyArrowLeft.ord))
    check window.dispatchKeyDown(KeyEvent(key: keyBackspace, keyCode: keyBackspace.ord))
    check view.searchField().text() == "alpa"
    check window.dispatchTextInput("h")
    check view.searchField().text() == "alpha"
    check window.dispatchKeyDown(
      KeyEvent(key: keyArrowRight, keyCode: keyArrowRight.ord)
    )
    check editor.searchQuery() == "alpha"
    check editor.bufferCursor() == KosmoBufferCursor(line: 2, column: 0)

    check window.dispatchKeyDown(KeyEvent(key: keyArrowUp, keyCode: keyArrowUp.ord))
    check editor.bufferCursor() == KosmoBufferCursor(line: 0, column: 0)

    check window.dispatchKeyDown(KeyEvent(key: keyArrowDown, keyCode: keyArrowDown.ord))
    check editor.bufferCursor() == KosmoBufferCursor(line: 2, column: 0)

    check window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
    check not view.searchVisible()
    check editor.searchQuery().len == 0
    check window.firstResponder() == view
