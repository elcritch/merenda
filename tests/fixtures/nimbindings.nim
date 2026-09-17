## Generated native declarations shared by the Matter highlighting tests.

import std/strutils

const NimBindingDeclarations* =
  """proc caretPositionsFor*(arrangement: GlyphArrangement; sourceRune: int): seq[TextCaretPosition] {.importc: "caretPositionsFor_u0__OOZOOZOOZOOZsrcZfigdrawZcommonZfonttypes".}

proc nearestSourceRuneForCaretPoint*(arrangement: GlyphArrangement; point: Vec2): int {.importc: "nearestSourceRuneForCaretPoint_u0__OOZOOZOOZOOZsrcZfigdrawZcommonZfonttypes".}

proc typesetStyled*(box: Rect; uiSpans: openArray[NativeAbit18_1416635713_fonzt2lm91]; hAlign: FontHorizontal; vAlign: FontVertical; minContent: bool; wrap: bool): GlyphArrangement {.importc: "typesetStyled_u0__OOZOOZOOZOOZsrcZfigdrawZcommonZfontutils".}

proc typesetStyledForMeasurement*(box: Rect; uiSpans: openArray[NativeAbit18_1799409862_fonzt2lm91]; hAlign: FontHorizontal; vAlign: FontVertical; minContent: bool; wrap: bool): GlyphArrangement {.importc: "typesetStyledForMeasurement_u0__OOZOOZOOZOOZsrcZfigdrawZcommonZfontutils".}

proc placeStyledGlyphs*(style: FontStyle; glyphs: openArray[NativeAbit18_1363474072_fonzt2lm91]; origin: GlyphOrigin): GlyphArrangement {.importc: "placeStyledGlyphs_u0__OOZOOZOOZOOZsrcZfigdrawZcommonZfontutils".}
"""

const NimBindingMaximumLineBytes* = block:
  var maximum: int
  for line in NimBindingDeclarations.splitLines():
    maximum = max(maximum, line.len)
  maximum
