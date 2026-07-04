import std/unittest

import merenda/nimkit

suite "nimkit value types":
  test "HTML color parser is re-exported for apps":
    let parsed = parseHtmlColor("#336699")
    check abs(parsed.r - 0.2'f32) < 0.001'f32
    check abs(parsed.g - 0.4'f32) < 0.001'f32
    check abs(parsed.b - 0.6'f32) < 0.001'f32
    check parsed.a == 1.0'f32

  test "rect uses bumpy storage with origin and size compatibility accessors":
    let rect = rect(10, 20, -5, 30)
    check rect.origin == initPoint(10, 20)
    check rect.size.width == -5
    check rect.size.height == 30

  test "contains uses half-open bounds":
    let rect = rect(10, 20, 100, 50)
    check rect.contains(initPoint(10, 20))
    check rect.contains(initPoint(109, 69))
    check not rect.contains(initPoint(110, 69))
    check not rect.contains(initPoint(109, 70))

  test "intersection returns empty rect for disjoint input":
    let
      a = rect(0, 0, 20, 20)
      b = rect(30, 30, 20, 20)
    check a.intersection(b).isEmpty

  test "union covers both non-empty rects":
    let
      a = rect(10, 20, 20, 10)
      b = rect(25, 15, 30, 20)
    check a.union(b) == rect(10, 15, 45, 20)
