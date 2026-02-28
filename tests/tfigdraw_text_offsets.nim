import std/unittest

import figdraw/commons
import pkg/vmath

proc glyphDrawPos(glyphPos: Vec2, descent: float32): Vec2 =
  vec2(glyphPos.x.scaled(), (glyphPos.y - descent).scaled())

proc selectionDrawRect(localRect: Rect): Rect =
  localRect.scaled()

suite "figdraw text rendering offsets":
  test "glyph draw position uses local glyph coordinates":
    let glyphPos = vec2(10.0'f32, 16.0'f32)
    let drawPos = glyphDrawPos(glyphPos, 12.0'f32)
    check(drawPos.x == 10.0'f32.scaled())
    check(drawPos.y == 4.0'f32.scaled())

  test "selection rect uses local coordinates":
    let localSel = rect(3.0'f32, 4.0'f32, 10.0'f32, 12.0'f32)
    let drawSel = selectionDrawRect(localSel)
    check(drawSel.x == 3.0'f32.scaled())
    check(drawSel.y == 4.0'f32.scaled())
    check(drawSel.w == 10.0'f32.scaled())
    check(drawSel.h == 12.0'f32.scaled())
