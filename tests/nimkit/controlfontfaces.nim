import std/[os, unittest]

import figdraw
import figdraw/common/typefaces

import merenda/nimkit

suite "NimKit control font faces":
  test "derived control text styles retain the exact interface face":
    let
      fontPath = getCurrentDir() / "data/Ubuntu.ttf"
      exactFace = initSystemTypeface(fontPath)
      expectedTypefaceId = exactFace.fontWithSize(14.0'f32).typefaceId
      root = newView(frame = rect(0, 0, 300, 120))
      button = newButton("Button", frame = rect(10, 10, 100, 28))
      stepper = newStepper(0.0, 10.0, 5.0, frame = rect(120, 10, 52, 28))
      label = newIconLabel("+", "Add", frame = rect(10, 50, 120, 28))

    var builder = initThemeBuilder(initTheme())
    builder.setFontName(frUI, "__missing_exact_interface_face__")
    builder.setFontFace(frUI, exactFace)
    builder[srButton, StyleTextHighlightColor] = color(1.0, 1.0, 1.0, 0.5)
    builder[srButton, StyleTextShadowColor] = color(0.0, 0.0, 0.0, 0.5)
    let appearance = initAppearance(builder.finish())

    root.addSubview(button)
    root.addSubview(stepper)
    root.addSubview(label)
    let renderList = root.buildRenders(appearance)[DefaultDrawLevel]

    var textNodeCount = 0
    for node in renderList.nodes:
      if node.kind == nkText and node.textLayout.arrangedGlyphs.len > 0:
        inc textNodeCount
        for glyph in node.textLayout.arrangedGlyphs:
          check getFigFont(glyph.fontId).typefaceId == expectedTypefaceId
    check textNodeCount >= 5
