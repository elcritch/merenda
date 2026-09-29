## Moe-backed search through Kosmo's shared floating search controls.

import std/[options, unittest]

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

  test "matches center their rows when searching in either direction":
    var source = ""
    for line in 0 ..< 160:
      source.add (if line in [40, 100]: "needle" else: "line") & "\n"
    let editor = newKosmoEditor(text = source)
    let view = newKosmoEditorView(editor)
    let window = newWindow("Search centering", frame = rect(0, 0, 640, 360))
    defer:
      window.close()
      editor.close()
    window.setContentView(view)
    view.layoutSubtreeIfNeeded()
    view.refresh()
    require view.showSearch()
    require window.dispatchTextInput("needle")
    check editor.bufferCursor().line == 40
    check abs(editor.cursor().row - view.lineCount div 2) <= 1
    view.findNext()
    check editor.bufferCursor().line == 100
    check abs(editor.cursor().row - view.lineCount div 2) <= 1
    view.findPrevious()
    check editor.bufferCursor().line == 40
    check abs(editor.cursor().row - view.lineCount div 2) <= 1
    require window.makeFirstResponder(view)
    require window.dispatchKeyDown(
      KeyEvent(key: keyG, keyCode: keyG.ord, modifiers: editorSearchShortcutModifiers())
    )
    check editor.bufferCursor().line == 100
    check abs(editor.cursor().row - view.lineCount div 2) <= 1

  test "literal replacements handle Unicode, adjacent matches, and undo groups":
    let editor = newKosmoEditor(text = "λ catcat\nCAT\ncat")
    defer:
      editor.close()
    let id = editor.tabs()[0].id
    require editor.revealLocation(0, 2)
    check editor.replaceSearch("cat", "dog") == 1
    check editor.bufferText(id).get == "λ dogcat\nCAT\ncat"
    check editor.bufferCursor() == KosmoBufferCursor(line: 0, column: 5)
    check editor.replaceSearch("cat", "$1\\literal", all = true) == 3
    check editor.bufferText(id).get == "λ dog$1\\literal\n$1\\literal\n$1\\literal"
    require editor.undo()
    check editor.bufferText(id).get == "λ dogcat\nCAT\ncat"
    require editor.undo()
    check editor.bufferText(id).get == "λ catcat\nCAT\ncat"
    require editor.redo()
    check editor.bufferText(id).get == "λ dogcat\nCAT\ncat"

  test "replacement supports deletion, multiline text, and regex matches":
    let editor = newKosmoEditor(text = "a12 b34\nlast")
    defer:
      editor.close()
    let id = editor.tabs()[0].id
    check editor.replaceSearch("[0-9]+", "x\ny", all = true) == 2
    check editor.bufferText(id).get == "ax\ny bx\ny\nlast"
    require editor.undo()
    check editor.replaceSearch("[0-9]+", "", all = true) == 2
    check editor.bufferText(id).get == "a b\nlast"
    check editor.replaceSearch("[", "broken", all = true) == 0
    check editor.replaceSearch("", "broken", all = true) == 0
    check editor.bufferText(id).get == "a b\nlast"

  test "replacement field Enter replaces and Escape restores editor focus":
    let editor = newKosmoEditor(text = "cat cat cat")
    let view = newKosmoEditorView(editor)
    let window = newWindow("Replace controls", frame = rect(0, 0, 640, 360))
    defer:
      window.close()
      editor.close()
    window.setContentView(view)
    view.layoutSubtreeIfNeeded()
    view.refresh()
    require editor.revealLocation(0, 0)
    require view.showSearch()
    require window.dispatchTextInput("cat")
    require window.makeFirstResponder(view.replacementField())
    view.replacementField().checkVisibleIn(view)
    require window.dispatchTextInput("dog")
    require window.dispatchKeyDown(KeyEvent(key: keyEnter, keyCode: keyEnter.ord))
    check editor.bufferText(editor.tabs()[0].id).get == "cat dog cat"
    check editor.bufferCursor().column == 8
    let replaceAll = view.buttonWithLabel("Replace all matches")
    require not replaceAll.isNil
    replaceAll.checkVisibleIn(view)
    let point = replaceAll.pointToWindow(
      initPoint(
        replaceAll.bounds().size.width * 0.5'f32,
        replaceAll.bounds().size.height * 0.5'f32,
      )
    )
    require window.mouseDownAt(point)
    require window.mouseUpAt(point)
    check editor.bufferText(editor.tabs()[0].id).get == "dog dog dog"
    require window.dispatchKeyDown(KeyEvent(key: keyEscape, keyCode: keyEscape.ord))
    check not view.searchVisible()
    check window.firstResponder() == view

  test "zero width replacements advance and replace all visits each original match once":
    let editor = newKosmoEditor(text = "one\ntwo")
    defer:
      editor.close()
    let id = editor.tabs()[0].id
    check editor.replaceSearch("^", ">", all = true) == 2
    check editor.bufferText(id).get == ">one\n>two"
    require editor.undo()
    require editor.revealLocation(0, 0)
    check editor.replaceSearch("^", "") == 0
    check editor.bufferText(id).get == "one\ntwo"
