import std/unittest

from figdraw/common/fonttypes import GlyphArrangement

import merenda/nimkit/drawing
import merenda/nimkit/foundation/types

proc selectionBounds(layout: GlyphArrangement): tuple[x, y, w, h: float32] =
  if layout.selectionRects.len == 0:
    return

  var
    minX = float32.high
    minY = float32.high
    maxX = -float32.high
    maxY = -float32.high
  for rect in layout.selectionRects:
    minX = min(minX, rect.x)
    minY = min(minY, rect.y)
    maxX = max(maxX, rect.x + rect.w)
    maxY = max(maxY, rect.y + rect.h)

  (minX, minY, maxX - minX, maxY - minY)

suite "nimkit font layout":
  test "centered label layout reports content bounds as local dimensions":
    let
      textRect = initRect(12.0, 0.0, 640.0, 28.0)
      layout = textLayout(
        textRect, "Hello from KNutella/nimkit", initColor(0.09, 0.14, 0.26), taCenter
      )
      content = layout.selectionBounds()

    check content.x > 0.0
    check abs(layout.bounding.x - content.x) <= 0.01
    check abs(layout.bounding.y - content.y) <= 0.01
    check abs(layout.bounding.w - content.w) <= 0.01
    check abs(layout.bounding.h - content.h) <= DefaultFontSize
    check layout.bounding.x + layout.bounding.w <= textRect.size.width + 0.01
