import std/unittest

import knutella/nimkit

suite "nimkit value types":
  test "rect clamps negative size":
    let rect = initRect(10, 20, -5, 30)
    check rect.origin == initPoint(10, 20)
    check rect.size == initSize(0, 30)

  test "contains uses half-open bounds":
    let rect = initRect(10, 20, 100, 50)
    check rect.contains(initPoint(10, 20))
    check rect.contains(initPoint(109, 69))
    check not rect.contains(initPoint(110, 69))
    check not rect.contains(initPoint(109, 70))

  test "intersection returns empty rect for disjoint input":
    let
      a = initRect(0, 0, 20, 20)
      b = initRect(30, 30, 20, 20)
    check a.intersection(b).isEmpty
