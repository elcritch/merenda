import std/unittest

import figdraw/commons
import figdraw/figrender
import pkg/vmath

suite "figdraw text rendering offsets":
  test "glyph draw position includes node screenBox origin":
    let nodeBox = rect(120.0'f32, 40.0'f32, 200.0'f32, 40.0'f32)
    let glyphPos = vec2(10.0'f32, 16.0'f32)
    let drawPos = glyphScreenPos(nodeBox, glyphPos, 12.0'f32)
    check(drawPos.x == 130.0'f32.scaled())
    check(drawPos.y == 44.0'f32.scaled())

  test "selection rect includes node screenBox origin":
    let nodeBox = rect(50.0'f32, 80.0'f32, 100.0'f32, 24.0'f32)
    let localSel = rect(3.0'f32, 4.0'f32, 10.0'f32, 12.0'f32)
    let screenSel = selectionScreenRect(nodeBox, localSel)
    check(screenSel.x == 53.0'f32.scaled())
    check(screenSel.y == 84.0'f32.scaled())
    check(screenSel.w == 10.0'f32.scaled())
    check(screenSel.h == 12.0'f32.scaled())
