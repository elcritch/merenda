import std/[strutils, unicode, unittest]

import figdraw

import merenda/nimkit

proc renderedText(node: Fig): string =
  for rune in node.textLayout.runes:
    result.add $rune

proc clickView(window: Window, view: View): bool =
  let bounds = view.bounds()
  window.clickAt(
    view.pointToWindow(initPoint(bounds.size.width / 2.0, bounds.size.height / 2.0))
  )

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
        styledMonoTextCell("X", color(0.9, 0.1, 0.1)),
        styledMonoTextCell("Y", color(0.9, 0.1, 0.1)),
      ],
    )
    check view.cellAt(1, 1).text == "X"
    check view.cellAt(1, 2).foregroundColor == color(0.9, 0.1, 0.1)

  test "editor handles cursor movement insertion and deletion":
    let
      window = newWindow("Mono editor", frame = rect(0, 0, 240, 120))
      root = newView(frame = rect(0, 0, 240, 120))
      editor = newMonoTextEditor("abc\ndef", frame = rect(0, 0, 200, 90))

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
      window = newWindow("Mono raw", frame = rect(0, 0, 240, 120))
      root = newView(frame = rect(0, 0, 240, 120))
      view = newMonoTextEditor("abcdef", frame = rect(0, 0, 200, 90))

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

  test "raw event policy controls forwarding and capture separately":
    let
      window = newWindow("Mono raw policy", frame = rect(0, 0, 240, 120))
      root = newView(frame = rect(0, 0, 240, 120))
      view = newMonoTextEditor("abcdef", frame = rect(0, 0, 200, 90))

    var forwarded: seq[MonoTextRawEventKind]
    view.rawEventPolicy = initMonoTextRawEventPolicy(
      forwardedEvents = {mtreKeyDown}, capturedEvents = {mtreKeyDown}
    )
    view.rawEventHandler = proc(event: MonoTextRawEvent): bool =
      forwarded.add event.kind
      false

    root.addSubview(view)
    window.setContentView(root)
    check window.makeFirstResponder(view)

    view.setCursorPosition(0, 0)
    check window.dispatchKeyDown(KeyEvent(text: "Z", key: keyZ))
    check forwarded == @[mtreKeyDown]
    check view.stringValue == "abcdef"

    view.capturedRawEvents = {}
    check window.dispatchKeyDown(KeyEvent(text: "Y", key: keyY))
    check forwarded == @[mtreKeyDown, mtreKeyDown]
    check view.stringValue == "Yabcdef"

    let point = view.pointToWindow(initPoint(view.padding + 2.0, view.padding + 2.0))
    check window.mouseDownAt(point)
    check forwarded == @[mtreKeyDown, mtreKeyDown]

  test "raw event policy checkboxes drive synthesized user input":
    let
      window = newWindow("Mono policy controls", frame = rect(0, 0, 420, 180))
      root = newView(frame = rect(0, 0, 420, 180))
      forwardKeys = newCheckBox("Forward key events", frame = rect(10, 10, 140, 28))
      captureKeys = newCheckBox("Capture key events", frame = rect(155, 10, 140, 28))
      forwardMouse = newCheckBox("Forward mouse events", frame = rect(300, 10, 110, 28))
      editor = newMonoTextEditor("abc", frame = rect(10, 55, 240, 90))
      policyAction = actionSelector("monoTextPolicyCheckboxChanged")

    proc applyPolicy() =
      var
        forwarded: MonoTextRawEventKinds = {}
        captured: MonoTextRawEventKinds = {}
      if forwardKeys.state == bsOn:
        forwarded = forwarded + {mtreKeyDown, mtreFlagsChanged}
      if captureKeys.state == bsOn:
        captured = captured + {mtreKeyDown, mtreFlagsChanged}
      if forwardMouse.state == bsOn:
        forwarded =
          forwarded + {mtreMouseDown, mtreMouseDragged, mtreMouseUp, mtreScrollWheel}
      editor.rawEventPolicy = initMonoTextRawEventPolicy(
        forwardedEvents = forwarded, capturedEvents = captured
      )

    let policyTarget = newActionTarget(policyAction) do(sender: DynamicAgent):
      discard sender
      applyPolicy()
      let owner = editor.window()
      if owner of Window:
        discard Window(owner).makeFirstResponder(editor)

    var forwarded: seq[MonoTextRawEventKind]
    editor.rawEventHandler = proc(event: MonoTextRawEvent): bool =
      forwarded.add event.kind
      false

    forwardKeys.state = bsOn
    forwardMouse.state = bsOff
    for checkbox in [forwardKeys, captureKeys, forwardMouse]:
      checkbox.target = policyTarget
      checkbox.action = policyAction
      root.addSubview(checkbox)
    root.addSubview(editor)
    window.setContentView(root)
    applyPolicy()
    check window.makeFirstResponder(editor)

    editor.setCursorPosition(0, 0)
    check window.dispatchKeyDown(KeyEvent(text: "Z", key: keyZ, keyCode: keyZ.ord))
    check window.dispatchTextInput("Z")
    check forwarded == @[mtreKeyDown]
    check editor.stringValue == "Zabc"

    check window.clickView(captureKeys)
    check captureKeys.state == bsOn
    check window.firstResponder == editor
    check window.dispatchKeyDown(KeyEvent(key: keyY, keyCode: keyY.ord))
    check window.dispatchTextInput("Y")
    check forwarded == @[mtreKeyDown, mtreKeyDown]
    check editor.stringValue == "Zabc"

    check window.clickView(captureKeys)
    check captureKeys.state == bsOff
    discard window.dispatchKeyDown(KeyEvent(key: keyX, keyCode: keyX.ord))
    check window.dispatchTextInput("X")
    check forwarded == @[mtreKeyDown, mtreKeyDown, mtreKeyDown]
    check editor.stringValue == "ZXabc"

    check window.clickView(forwardKeys)
    check forwardKeys.state == bsOff
    discard window.dispatchKeyDown(KeyEvent(key: keyQ, keyCode: keyQ.ord))
    check window.dispatchTextInput("Q")
    check forwarded == @[mtreKeyDown, mtreKeyDown, mtreKeyDown]
    check editor.stringValue == "ZXQabc"

    let editorPoint =
      editor.pointToWindow(initPoint(editor.padding + 2.0, editor.padding + 2.0))
    check window.mouseDownAt(editorPoint)
    check forwarded == @[mtreKeyDown, mtreKeyDown, mtreKeyDown]

    check window.clickView(forwardMouse)
    check forwardMouse.state == bsOn
    check window.mouseDownAt(editorPoint)
    check forwarded == @[mtreKeyDown, mtreKeyDown, mtreKeyDown, mtreMouseDown]

  test "captured raw tab key bypasses key view navigation":
    let
      window = newWindow("Mono raw tab", frame = rect(0, 0, 260, 120))
      root = newView(frame = rect(0, 0, 260, 120))
      view = newMonoTextEditor("abcdef", frame = rect(0, 0, 160, 80))
      next = newButton("Next", frame = rect(170, 0, 70, 28))

    var forwarded: seq[string]
    view.rawEventPolicy = initMonoTextRawEventPolicy(
      forwardedEvents = {mtreKeyDown}, capturedEvents = {mtreKeyDown}
    )
    view.rawEventHandler = proc(event: MonoTextRawEvent): bool =
      forwarded.add event.input
      false

    root.addSubview(view)
    root.addSubview(next)
    window.setContentView(root)
    check window.makeFirstResponder(view)

    check window.dispatchKeyDown(KeyEvent(key: keyTab, keyCode: keyTab.ord))
    check forwarded == @["<Tab>"]
    check window.firstResponder() == view
    check view.stringValue == "abcdef"

  test "theme drives mono text chrome surface":
    let
      surfaceFill = color(0.12, 0.16, 0.20, 1.0)
      surfaceBorder = color(0.70, 0.80, 0.90, 1.0)
      view = newMonoTextViewer("theme", frame = rect(0, 0, 220, 80))
    var theme = initTheme()
    theme[srMonoTextView, StyleFill] = fill(surfaceFill)
    theme[srMonoTextView, StyleBorderColor] = surfaceBorder
    theme[srMonoTextView, StyleBorderWidth] = 2.0
    theme[srMonoTextView, StyleCornerRadius] = 5.0
    theme[srMonoTextView, StyleChrome] = styleKeyword(DefaultChromeName)

    let list = buildRenders(view, initAppearance(theme))[DefaultDrawLevel]

    var foundSurface = false
    for node in list.nodes:
      if node.kind == nkRectangle and node.fill.kind == flColor and
          node.fill.color == surfaceFill.rgba:
        foundSurface = true
        check node.stroke.weight == 2.0
        check node.stroke.fill.kind == flColor
        check node.stroke.fill.color == surfaceBorder.rgba

    check foundSurface

  test "rendering only emits visible monospace rows":
    var lines: seq[string]
    for index in 0 ..< 80:
      lines.add "line" & $index

    let view = newMonoTextViewer(lines.join("\n"), frame = rect(0, 0, 260, 90))
    let metrics = view.monoTextMetrics()
    view.bounds = rect(0, view.padding + metrics.lineHeight * 30.0'f32, 260, 90)

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
