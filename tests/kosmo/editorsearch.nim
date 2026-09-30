## Moe-backed search through Kosmo's shared floating search controls.

import std/[options, strutils, unittest]

import celina/core/colors
import merenda/nimkit
import merenda/kosmo/kosmo
import fixtures/ui

proc isFocused(window: Window, control: View): bool =
  not control.isNil and
    (window.firstResponder() == control or window.fieldEditorClient() == control)

suite "Kosmo editor search":
  test "search tab navigation does not reach the active editor input mode":
    let frontend = newKosmoApplication(
      newApplication("Search tab navigation"), monitorsGitStatus = false
    )
    defer:
      frontend.close()
    let
      window = frontend.window
      view = frontend.editorView
      editor = view.editor
      tab = KeyEvent(text: "\t", key: keyTab, keyCode: keyTab.ord)
      backtab =
        KeyEvent(text: "\t", key: keyTab, keyCode: keyTab.ord, modifiers: {kmShift})
    window.setContentView(frontend.contentView)
    frontend.contentView.layoutSubtreeIfNeeded()
    require window.makeFirstResponder(view)
    require editor.handleKey("i")
    require editor.handleTextInput("cat cat")
    require editor.handleKey("Esc")
    let bufferId = editor.tabs()[0].id

    for modeKey in ["i", "R", ":"]:
      checkpoint "Editor mode entered with " & modeKey
      require editor.handleKey(modeKey)
      let mode = editor.mode()
      require mode in
        {KosmoEditorMode.Insert, KosmoEditorMode.Replace, KosmoEditorMode.Command}
      require view.showSearch(replacing = true)
      require window.dispatchTextInput("cat")
      let regex = view.buttonWithLabel("Use Reni regular expressions")
      require not regex.isNil

      require window.dispatchKeyDown(tab)
      check window.isFocused(regex)
      require window.dispatchKeyDown(tab)
      check window.isFocused(view.replacementField())
      require window.dispatchKeyDown(backtab)
      check window.isFocused(regex)
      require window.dispatchKeyDown(backtab)
      check window.isFocused(view.searchField())
      require window.dispatchKeyDown(tab)
      require window.dispatchKeyDown(tab)
      require window.dispatchKeyDown(tab)
      check window.isFocused(view.buttonWithLabel("Replace match"))
      require window.dispatchKeyDown(tab)
      check window.isFocused(view.buttonWithLabel("Replace all matches"))
      require window.dispatchKeyDown(backtab)
      require window.dispatchKeyDown(backtab)
      check window.isFocused(view.replacementField())
      check view.searchField().text == "cat"
      check view.replacementField().text == ""
      check editor.bufferText(bufferId).get == "cat cat"
      check editor.mode() == mode
      view.dismissSearch()
      require editor.handleKey("Esc")

  test "overlay clicks stay in the panel and tab reaches regex before replacement":
    let
      editor = newKosmoEditor(text = "cat cat")
      view = newKosmoEditorView(editor)
      window = newWindow("Search focus", frame = rect(0, 0, 640, 360))
    defer:
      window.close()
      editor.close()
    window.setContentView(view)
    view.layoutSubtreeIfNeeded()
    view.refresh()
    require view.showSearch(replacing = true)
    let
      regex = view.buttonWithLabel("Use Reni regular expressions")
      replace = view.buttonWithLabel("Replace match")
      replaceAll = view.buttonWithLabel("Replace all matches")
      tab = KeyEvent(key: keyTab, keyCode: keyTab.ord)
      backtab = KeyEvent(key: keyTab, keyCode: keyTab.ord, modifiers: {kmShift})
    require window.dispatchTextInput("cat")
    require window.dispatchKeyDown(tab)
    check window.firstResponder() == regex
    require window.dispatchKeyDown(tab)
    check window.fieldEditorClient() == view.replacementField()
    require window.dispatchKeyDown(backtab)
    check window.firstResponder() == regex
    require window.dispatchKeyDown(tab)
    require window.dispatchKeyDown(tab)
    check window.firstResponder() == replace
    require window.dispatchKeyDown(tab)
    check window.firstResponder() == replaceAll

    let cursor = editor.bufferCursor()
    let panel = view.searchField().superview().superview()
    let paddingPoint = panel.pointToWindow(initPoint(2, 2))
    require window.mouseDownAt(paddingPoint)
    require window.mouseUpAt(paddingPoint)
    check window.firstResponder() == replaceAll
    check editor.bufferCursor() == cursor

    require view.showSearch()
    view.searchField().text = ""
    require window.makeFirstResponder(view)
    let queryPoint = view.searchField().pointToWindow(initPoint(40, 16))
    require window.mouseDownAt(queryPoint)
    discard window.mouseUpAt(queryPoint)
    check window.fieldEditorClient() == view.searchField()
    require window.dispatchTextInput("missing")
    require window.dispatchKeyDown(tab)
    check window.firstResponder() == regex
    require window.dispatchKeyDown(tab)
    check window.firstResponder() == view.buttonWithLabel("Close editor text search")
    check editor.bufferText(editor.tabs()[0].id).get == "cat cat"

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

    check not editor.searchFrom("[", editor.bufferCursor(), regularExpression = true)
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
    check view.replacementField().hidden
    check not view.buttonWithLabel("Show replacement controls").isNil
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
    check editor.replaceSearch("[0-9]+", "x\ny", all = true, regularExpression = true) ==
      2
    check editor.bufferText(id).get == "ax\ny bx\ny\nlast"
    require editor.undo()
    check editor.replaceSearch("[0-9]+", "", all = true, regularExpression = true) == 2
    check editor.bufferText(id).get == "a b\nlast"
    check editor.replaceSearch("[", "broken", all = true, regularExpression = true) == 0
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
    require view.showSearch(replacing = true)
    require window.dispatchTextInput("cat")
    let replacementPoint = view.replacementField().pointToWindow(initPoint(40, 16))
    require window.mouseDownAt(replacementPoint)
    discard window.mouseUpAt(replacementPoint)
    require window.fieldEditorClient() == view.replacementField()
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

  test "search defaults stay compact and replacement is explicitly expanded":
    let editor = newKosmoEditor(text = "cat cat")
    let view = newKosmoEditorView(editor)
    let window = newWindow("Search modes", frame = rect(0, 0, 640, 360))
    defer:
      window.close()
      editor.close()
    window.setContentView(view)
    view.layoutSubtreeIfNeeded()
    view.refresh()
    require view.showSearch()
    require window.dispatchTextInput("cat")
    let cursor = editor.bufferCursor()
    let toggle = view.buttonWithLabel("Show replacement controls")
    require not toggle.isNil
    toggle.checkVisibleIn(view)
    let point = toggle.pointToWindow(
      initPoint(toggle.bounds().size.width / 2, toggle.bounds().size.height / 2)
    )
    require window.mouseDownAt(point)
    require window.mouseUpAt(point)
    view.replacementField().checkVisibleIn(view)
    check view.searchField().text() == "cat"
    check editor.bufferCursor() == cursor
    require window.makeFirstResponder(view.replacementField())
    require window.dispatchTextInput("dog")

    let find =
      KeyEvent(key: keyF, keyCode: keyF.ord, modifiers: editorSearchShortcutModifiers())
    let replace = KeyEvent(
      key: keyF,
      keyCode: keyF.ord,
      modifiers: editorSearchShortcutModifiers() + {nimkit.kmOption},
    )
    require window.dispatchKeyDown(find)
    check view.replacementField().hidden
    check view.buttonWithLabel("Replace all matches").hidden
    check window.fieldEditorClient() == view.searchField()
    check view.searchField().text() == "cat"
    check editor.bufferCursor() == cursor

    require window.dispatchKeyDown(replace)
    view.replacementField().checkVisibleIn(view)
    check view.replacementField().text() == "dog"
    check view.searchField().text() == "cat"
    require window.mouseDownAt(point)
    require window.mouseUpAt(point)
    check view.replacementField().hidden
    check window.fieldEditorClient() == view.searchField()
    require window.makeFirstResponder(view)
    require window.dispatchKeyDown(replace)
    view.replacementField().checkVisibleIn(view)
    view.dismissSearch()
    require window.dispatchKeyDown(find)
    check view.replacementField().hidden

  test "zero width replacements advance and replace all visits each original match once":
    let editor = newKosmoEditor(text = "one\ntwo")
    defer:
      editor.close()
    let id = editor.tabs()[0].id
    check editor.replaceSearch("^", ">", all = true, regularExpression = true) == 2
    check editor.bufferText(id).get == ">one\n>two"
    require editor.undo()
    require editor.revealLocation(0, 0)
    check editor.replaceSearch("^", "", regularExpression = true) == 0
    check editor.bufferText(id).get == "one\ntwo"

  test "Reni capture replacements preserve Unicode and stay undoable":
    let editor = newKosmoEditor(text = "λcat cat\ncat")
    defer:
      editor.close()
    let id = editor.tabs()[0].id
    require editor.searchFrom(
      r"λ\K(?<animal>cat)",
      KosmoBufferCursor(line: 0, column: 0),
      regularExpression = true,
    )
    check editor.bufferCursor() == KosmoBufferCursor(line: 0, column: 1)
    check editor.replaceSearch(
      r"λ\K(?<animal>cat)", "${animal}-$0-$$", regularExpression = true
    ) == 1
    check editor.bufferText(id).get == "λcat-cat-$ cat\ncat"
    require editor.undo()
    check editor.bufferText(id).get == "λcat cat\ncat"
    check editor.replaceSearch("(cat)", "$2", all = true, regularExpression = true) == 0
    check editor.searchError().len > 0
    check editor.bufferText(id).get == "λcat cat\ncat"
    check editor.replaceSearch("(cat)", "$1!", all = true, regularExpression = true) == 3
    check editor.bufferText(id).get == "λcat! cat!\ncat!"
    require editor.undo()
    check editor.replaceSearch(r"(?=.)", ">", all = true, regularExpression = true) == 11
    check editor.bufferText(id).get == ">λ>c>a>t> >c>a>t\n>c>a>t"

  test "end-of-line matches navigate and replace beyond the normal cursor":
    let editor = newKosmoEditor(text = "λcat\ndog")
    defer:
      editor.close()
    let id = editor.tabs()[0].id
    require editor.searchFrom(
      "$", KosmoBufferCursor(line: 0, column: 0), regularExpression = true
    )
    check editor.bufferCursor().line == 0
    require editor.searchFrom("$", editor.bufferCursor(), regularExpression = true)
    check editor.bufferCursor().line == 1
    check editor.replaceSearch("$", "!", regularExpression = true) == 1
    check editor.bufferText(id).get == "λcat\ndog!"
    check editor.replaceSearch("$", "?", regularExpression = true) == 1
    check editor.bufferText(id).get == "λcat?\ndog!"
    require editor.undo()
    require editor.undo()
    check editor.bufferText(id).get == "λcat\ndog"

  test "editor expression toggle controls search and capture replacement together":
    let editor = newKosmoEditor(text = "a.b axb")
    let view = newKosmoEditorView(editor)
    let window = newWindow("Reni controls", frame = rect(0, 0, 640, 360))
    defer:
      window.close()
      editor.close()
    window.setContentView(view)
    view.layoutSubtreeIfNeeded()
    view.refresh()
    require view.showSearch(replacing = true)
    require window.dispatchTextInput("a.b")
    check editor.bufferCursor().column == 0
    let toggle = view.buttonWithLabel("Use Reni regular expressions")
    require not toggle.isNil
    toggle.checkVisibleIn(view)
    check toggle.state == bsOff
    let point = toggle.pointToWindow(
      initPoint(toggle.bounds().size.width / 2, toggle.bounds().size.height / 2)
    )
    require window.mouseDownAt(point)
    require window.mouseUpAt(point)
    check toggle.state == bsOn
    view.findNext()
    check editor.bufferCursor().column == 4
    view.replacementField().text = "$0!"
    check view.replaceMatch(all = true) == 2
    check editor.bufferText(editor.tabs()[0].id).get == "a.b! axb!"
    require editor.undo()
    require window.mouseDownAt(point)
    require window.mouseUpAt(point)
    check toggle.state == bsOff
    check view.replaceMatch(all = true) == 1
    check editor.bufferText(editor.tabs()[0].id).get == "$0! axb"

  test "Reni highlights follow Unicode, tabs, and wrapping without coloring empty cells":
    let editor = newKosmoEditor(text = "λ\t猫 " & repeat("cat", 18))
    defer:
      editor.close()
    var buffer = newRenderBuffer(32, 12)
    editor.render(buffer)
    require editor.searchFrom(
      r"(?<=\t)猫|cat", KosmoBufferCursor(line: 0, column: 0), regularExpression = true
    )
    editor.render(buffer)
    let cursor = editor.cursor()
    require buffer.cell(cursor.column, cursor.row).symbol == "猫"
    let highlight = buffer.cell(cursor.column, cursor.row).style.bg
    var highlightedCells = 0
    var lastMatchRow = -1
    for row in 0 ..< buffer.height - 1:
      for column in 0 ..< buffer.width:
        let cell = buffer.cell(column, row)
        if cell.symbol in ["猫", "c", "a", "t"]:
          check cell.style.bg == highlight
          inc highlightedCells
          lastMatchRow = row
        elif cell.symbol == " " or cell.symbol == "λ":
          check cell.style.bg != highlight
    check highlightedCells == 55
    check lastMatchRow > cursor.row
    editor.clearSearch()
    editor.render(buffer)
    check buffer.cell(cursor.column, cursor.row).style.bg != highlight
