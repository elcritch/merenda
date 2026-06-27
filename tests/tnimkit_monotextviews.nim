import std/[strutils, unicode, unittest]

import figdraw/fignodes

import merenda/nimkit

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add $rune

suite "nimkit mono text views":
  test "plain text API stores lines and exposes grid cells":
    let view = newMonoTextViewer("alpha\nbeta")

    check view.lineCount == 2
    check view.lines == @["alpha", "beta"]
    check view.stringValue == "alpha\nbeta"
    check view.maxColumnCount == 5
    check view.cellAt(1, 1).text == "e"

    view.setGridSize(3, 4)
    check view.lineCount == 3
    check view.maxColumnCount == 4
    view.replaceCells(
      1,
      1,
      [
        styledMonoTextCell("X", initColor(0.9, 0.1, 0.1)),
        styledMonoTextCell("Y", initColor(0.9, 0.1, 0.1)),
      ],
    )
    check view.cellAt(1, 1).text == "X"
    check view.cellAt(1, 2).foregroundColor == initColor(0.9, 0.1, 0.1)

  test "editor handles cursor movement insertion and deletion":
    let
      window = newWindow("Mono editor", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      editor = newMonoTextEditor("abc\ndef", frame = initRect(0, 0, 200, 90))

    root.addSubview(editor)
    window.setContentView(root)
    check window.makeFirstResponder(editor)

    editor.setCursorPosition(0, 1)
    check window.dispatchKeyDown(KeyEvent(text: "Z", key: keyZ))
    check editor.stringValue == "aZbc\ndef"
    check editor.cursorRow == 0
    check editor.cursorColumn == 2

    check window.dispatchKeyDown(KeyEvent(key: keyEnter))
    check editor.lines == @["aZ", "bc", "def"]
    check editor.cursorRow == 1
    check editor.cursorColumn == 0

    check window.dispatchKeyDown(KeyEvent(key: keyBackspace))
    check editor.lines == @["aZbc", "def"]
    check editor.cursorRow == 0
    check editor.cursorColumn == 2

  test "raw event forwarding can consume key and mouse input":
    let
      window = newWindow("Mono raw", frame = initRect(0, 0, 240, 120))
      root = newView(frame = initRect(0, 0, 240, 120))
      view = newMonoTextEditor("abcdef", frame = initRect(0, 0, 200, 90))

    var forwarded: seq[MonoTextRawEvent]
    view.rawEventHandler = proc(event: MonoTextRawEvent): bool =
      forwarded.add event
      true

    root.addSubview(view)
    window.setContentView(root)
    check window.makeFirstResponder(view)

    check window.dispatchKeyDown(KeyEvent(key: keyA, modifiers: {kmControl}))
    check forwarded.len == 1
    check forwarded[0].kind == mtreKeyDown
    check forwarded[0].input == "<C-a>"
    check view.stringValue == "abcdef"

    let point = view.pointToWindow(initPoint(view.padding + 2.0, view.padding + 2.0))
    check window.mouseDownAt(point, clickCount = 2)
    check forwarded.len == 2
    check forwarded[1].kind == mtreMouseDown
    check forwarded[1].row == 0
    check forwarded[1].column == 0
    check forwarded[1].input == "<2-LeftMouse><0,0>"

  test "rendering only emits visible monospace rows":
    var lines: seq[string]
    for index in 0 ..< 80:
      lines.add "line" & $index

    let view = newMonoTextViewer(lines.join("\n"), frame = initRect(0, 0, 260, 90))
    let metrics = view.monoTextMetrics()
    view.bounds = initRect(0, view.padding + metrics.lineHeight * 30.0'f32, 260, 90)

    let list = buildRenders(view)[DefaultDrawLevel]

    var
      textCount = 0
      sawVisibleRow = false
      sawFirstRow = false
    for node in list.nodes:
      if node.kind == nkText:
        inc textCount
        let text = node.renderedText()
        if text == "line30":
          sawVisibleRow = true
        if text == "line0":
          sawFirstRow = true

    check textCount > 0
    check textCount < 12
    check sawVisibleRow
    check not sawFirstRow
