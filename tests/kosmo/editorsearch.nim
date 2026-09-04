## Moe-backed search through Kosmo's shared floating search controls.

import std/unittest

import merenda/nimkit
import merenda/kosmo/kosmo

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
    let searchFieldFrame =
      view.searchField().rectToView(view.searchField().bounds(), view)
    check searchFieldFrame.origin.x > 100.0'f32
    check searchFieldFrame.origin.y <= 40.0'f32
    check searchFieldFrame.size.width > 300.0'f32

    check window.dispatchTextInput("alpha")
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
