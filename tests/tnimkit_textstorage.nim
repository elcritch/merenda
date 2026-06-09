import std/unittest

import merenda/nimkit

suite "nimkit text storage":
  test "text storage replaces text and preserves surrounding attribute runs":
    let
      storage = newTextStorage("abcdef")
      red = defaultTextAttributes(initColor(1.0, 0.0, 0.0))
      blue = defaultTextAttributes(initColor(0.0, 0.0, 1.0))

    storage.setAttributes(initTextRange(0, 3), red)
    storage.replace(initTextRange(2, 2), "XYZ", blue)

    check storage.stringValue == "abXYZef"
    check storage.len == 7
    check storage.substring(initTextRange(2, 3)) == "XYZ"
    check storage.attributesAt(0) == red
    check storage.attributesAt(2) == blue
    check storage.attributesAt(5) == defaultTextAttributes()

  test "text storage uses rune ranges for unicode text":
    let storage = newTextStorage("ałpha")

    storage.replace(initTextRange(1, 1), "L")

    check storage.stringValue == "aLpha"
    check storage.len == 5
    check storage.substring(initTextRange(1, 2)) == "Lp"

  test "adjacent equal attribute runs are normalized":
    let
      storage = newTextStorage("abcd")
      accent = defaultTextAttributes(initColor(0.2, 0.4, 0.8))

    storage.setAttributes(initTextRange(0, 2), accent)
    storage.setAttributes(initTextRange(2, 2), accent)

    var count = 0
    for run in storage.runs:
      inc count
      check run.range == initTextRange(0, 4)
      check run.attributes == accent
    check count == 1
