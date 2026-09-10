import std/[strutils, unittest]

import figdraw

import merenda/nimkit
import merenda/nimkit/text/monotextviews as monoTextViews

suite "Terminal geometry":
  test "partial cell space stays outside the terminal grid and wrap boundary":
    let view = newTerminalView(frame = rect(0, 0, 120, 80))
    let metrics = view.monoTextMetrics()
    let padding = view.padding()
    view.frame = rect(
      0,
      0,
      padding * 2 + metrics.cellWidth * 10.25,
      padding * 2 + metrics.lineHeight * 3.25,
    )
    view.resizeToFit()
    let session = view.session()
    check session.screenInfo().columns == 10
    check session.screenInfo().rows == 3
    session.processOutput("0123456789X\r\nbottom")
    discard view.poll()
    check view.cellAt(0, 9).text == "9"
    check view.cellAt(1, 0).text == "X"
    check view.cellAt(2, 0).text == "b"
    check padding + view.lineCount.float32 * metrics.lineHeight <= view.bounds().h
    check padding + view.maxColumnCount.float32 * metrics.cellWidth <= view.bounds().w
    check view.backgroundColor() == view.palette().background

  test "terminal palette controls the whole surface under Aqua chrome":
    let view = newTerminalView(frame = rect(0, 0, 243, 107))
    let appearance = initAppearance(initAquaTheme())
    for background in [color(0.06, 0.07, 0.09), color(0.8, 0.7, 0.6)]:
      var palette = view.palette()
      palette.background = background
      view.palette = palette
      let list = buildRenders(view, appearance)[DefaultDrawLevel]
      var foundSurface = false
      for node in list.nodes:
        if node.kind == nkRectangle and node.stroke.weight > 0:
          foundSurface = true
          check node.fill.kind == flColor
          check node.fill.color == background.rgba
      check foundSurface

suite "Terminal scrollback stability":
  test "output preserves visible history before and after the buffer fills":
    for capacity in [4, 20]:
      let
        session =
          newCompactTerminalSession(columns = 16, rows = 3, maxScrollback = capacity)
        view = newTerminalView(session, frame = rect(0, 0, 180, 60))
      defer:
        view.close()
      session.processOutput("row0\r\nrow1\r\nrow2\r\nrow3\r\nrow4\r\nrow5\r\nrow6")
      discard view.poll()
      view.selectTerminalRange(
        TerminalSelection(
          anchor: initTerminalPosition(1, 0), extent: initTerminalPosition(1, 4)
        )
      )
      let visible = monoTextViews.stringValue(view)
      let offset = view.scrollPosition()
      session.processOutput("\r\nrow7")
      discard view.poll()
      check monoTextViews.stringValue(view) == visible
      check view.scrollPosition() == offset + 1
      check view.selectionText() == "row1"
      session.processOutput("\r\nrow8")
      discard view.poll()
      if capacity == 4:
        check monoTextViews.stringValue(view).startsWith("row2")
        check not view.hasSelection()
      else:
        check monoTextViews.stringValue(view) == visible
      session.processOutput("\e[3J")
      discard view.poll()
      check view.scrollPosition() == 0

  test "live terminal output continues to follow the prompt":
    let
      session = newCompactTerminalSession(columns = 16, rows = 2, maxScrollback = 2)
      view = newTerminalView(session)
    defer:
      view.close()
    session.processOutput("one\r\ntwo\r\nthree\r\nfour")
    discard view.poll()
    check view.scrollPosition() == 0
    session.processOutput("\r\nfive")
    discard view.poll()
    check view.scrollPosition() == 0
    check monoTextViews.stringValue(view).startsWith("four")
