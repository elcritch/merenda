import std/unittest

import merenda/nimkit

const TextLayoutEpsilon = 0.01'f32

proc checkClose(actual, expected: float32) =
  check abs(actual - expected) <= TextLayoutEpsilon

proc hasLineStart(snapshot: TextLayoutSnapshot, index: int): bool =
  for fragment in snapshot.lineFragments:
    if int(fragment.textRange.location) == index:
      return true

suite "nimkit text layout":
  test "layout snapshot exposes typed glyph and line fragments":
    let manager = newTextLayoutManager(
      newTextStorage("Alpha\nBeta"),
      initTextContainer(initSize(160.0, 80.0), insets(4.0), wraps = false),
    )
    let snapshot = manager.layoutSnapshot()

    check snapshot.textHash != 0
    check snapshot.layoutHash != 0
    check snapshot.glyphCount > 0
    check snapshot.lineFragments.len >= 2
    checkClose(snapshot.containerRect.origin.x, 4.0)
    checkClose(snapshot.containerRect.origin.y, 4.0)

    let first = snapshot.lineFragments[0]
    check first.lineIndex.toInt == 0
    check first.glyphRange.location.toInt >= 0
    check first.glyphRange.maxIndex <= int(snapshot.glyphCount)
    check first.textRange.location == 0
    check first.textRange.length > 0
    check first.hardBreak
    check not first.wrapped
    checkClose(first.fragmentRect.origin.x, snapshot.containerRect.origin.x)
    checkClose(first.fragmentRect.size.width, snapshot.containerRect.size.width)
    check first.usedRect.origin.x >= snapshot.containerRect.origin.x
    check first.baseline > first.fragmentRect.origin.y
    check first.ascent > 0.0
    check first.descent >= 0.0
    check first.leading >= 0.0

    let second = snapshot.lineFragments[1]
    check second.lineIndex.toInt == 1
    check not second.hardBreak
    check not second.wrapped
    check second.textRange.location >= first.textRange.location

    check snapshot.usedRect.size.height > 0.0
    check snapshot.contentSize.height > 0.0

  test "layout snapshot marks wrapped visual lines":
    let manager = newTextLayoutManager(
      newTextStorage("one two three four five six"),
      initTextContainer(initSize(36.0, 160.0), insets(0.0), wraps = true),
    )
    let snapshot = manager.layoutSnapshot()

    var foundWrapped = false
    for fragment in snapshot.lineFragments:
      if fragment.wrapped:
        foundWrapped = true

    check snapshot.lineFragments.len > 1
    check foundWrapped

  test "layout snapshot includes an empty visual line for empty text":
    let manager = newTextLayoutManager(
      newTextStorage(""),
      initTextContainer(initSize(120.0, 40.0), insets(2.0), wraps = false),
    )
    let snapshot = manager.layoutSnapshot()

    check snapshot.glyphCount == 0
    check snapshot.lineFragments.len == 1
    check snapshot.lineFragments[0].lineIndex.toInt == 0
    check snapshot.lineFragments[0].glyphRange.isEmpty
    check snapshot.lineFragments[0].textRange.isEmpty
    check snapshot.lineFragments[0].fragmentRect.size.height > 0.0

  test "layout snapshot preserves blank and trailing hard-break lines":
    let manager = newTextLayoutManager(
      newTextStorage("A\n\nB\n"),
      initTextContainer(initSize(120.0, 120.0), insets(0.0), wraps = false),
    )
    let snapshot = manager.layoutSnapshot()

    check snapshot.lineFragments.len >= 4
    check snapshot.hasLineStart(0)
    check snapshot.hasLineStart(2)
    check snapshot.hasLineStart(3)
    check snapshot.hasLineStart(5)
    check snapshot.lineFragments[^1].textRange.location == 5
    check snapshot.lineFragments[^1].glyphRange.isEmpty
