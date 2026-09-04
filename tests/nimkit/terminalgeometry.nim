import std/unittest

import figdraw

import merenda/nimkit

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
