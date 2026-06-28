import std/[options, unittest]

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

  test "layout lifecycle and scalar queries expose current cached layout":
    let manager = newTextLayoutManager(
      newTextStorage("Alpha\nBeta"),
      initTextContainer(initSize(160.0, 80.0), insets(4.0), wraps = false),
    )

    check not manager.hasValidLayout()
    manager.updateLayout()
    check manager.hasValidLayout()
    check manager.glyphCount() > 0
    check manager.lineCount() >= 2
    checkClose(manager.layoutBounds().origin.x, 4.0)
    checkClose(manager.layoutBounds().origin.y, 4.0)
    check manager.usedRect().size.height > 0.0
    check manager.contentSize().height > 0.0

    manager.invalidateLayout(initTextRange(1, 2))
    check not manager.hasValidLayout()
    discard manager.layoutSnapshot()
    check manager.hasValidLayout()

  test "text and glyph range queries round trip through typed ranges":
    let manager = newTextLayoutManager(
      newTextStorage("Alpha Beta"),
      initTextContainer(initSize(200.0, 60.0), insets(3.0), wraps = false),
    )
    let
      textRange = initTextRange(1, 4)
      glyphRange = manager.glyphRangeForTextRange(textRange)
      roundTrip = manager.textRangeForGlyphRange(glyphRange)
      emptyEnd = manager.glyphRangeForTextRange(initTextRange(20, 0))

    check not glyphRange.isEmpty
    check glyphRange.location.toInt >= 0
    check glyphRange.maxIndex <= int(manager.glyphCount())
    check int(roundTrip.location) <= int(textRange.location)
    check roundTrip.maxIndex >= textRange.maxIndex
    check manager.textRangeForGlyphRange(emptyEnd).location == 10
    check manager.textRangeForGlyphRange(emptyEnd).isEmpty

  test "point queries return glyph, text range, and insertion index":
    let manager = newTextLayoutManager(
      newTextStorage("Alpha Beta"),
      initTextContainer(initSize(200.0, 60.0), insets(5.0), wraps = false),
    )
    let
      rect = manager.characterRect(2)
      point = initPoint(rect.origin.x + rect.size.width * 0.5, rect.origin.y + 1.0)
      glyphIndex = manager.glyphIndexAtPoint(point)
      textRange = manager.textRangeAtPoint(point)

    check glyphIndex.isSome
    check glyphIndex.get().toInt >= 0
    check int(textRange.location) <= 2
    check textRange.maxIndex > 2
    check manager.textIndexAtPoint(point) >= 0

  test "visual line fragment queries cover indexes and ranges":
    let manager = newTextLayoutManager(
      newTextStorage("one two three four five six"),
      initTextContainer(initSize(36.0, 160.0), insets(0.0), wraps = true),
    )
    let
      fragments = manager.lineFragments()
      firstLine = manager.lineFragment(0)
      textLine = manager.lineFragmentForTextIndex(0)
      glyphLine = manager.lineFragmentForGlyphIndex(0)
      textRangeLines = manager.lineFragmentsForTextRange(initTextRange(0, 12))
      lineRange = manager.lineRangeForTextRange(initTextRange(0, 12))

    check fragments.len > 1
    check firstLine.isSome
    check firstLine.get().lineIndex.toInt == 0
    check textLine.isSome
    check textLine.get().lineIndex.toInt == 0
    check glyphLine.isSome
    check glyphLine.get().lineIndex.toInt == 0
    check textRangeLines.len >= 1
    check lineRange.location.toInt == 0
    check lineRange.length >= 1
    check manager.lineFragment(999).isNone

    var iterated = 0
    for fragment in manager.lineFragmentItems():
      check fragment.lineIndex.toInt == iterated
      inc iterated
    check iterated == fragments.len

  test "geometry queries expose caret, selection, and glyph bounds":
    let manager = newTextLayoutManager(
      newTextStorage("Alpha Beta"),
      initTextContainer(initSize(220.0, 80.0), insets(6.0), wraps = false),
    )
    let
      caret = manager.caretRect(2)
      positions = manager.caretPositions(2)
      selection = manager.selectionRects(initTextRange(1, 4))
      firstRect = manager.firstRectForTextRange(initTextRange(1, 4))
      emptyFirstRect = manager.firstRectForTextRange(initTextRange(2, 0))
      textBounds = manager.textRangeBounds(initTextRange(1, 4))
      glyphBounds =
        manager.boundsForGlyphRange(manager.glyphRangeForTextRange(initTextRange(1, 4)))

    check caret.size.height > 0.0
    check positions.len > 0
    check positions[0].textIndex.toInt == 2
    check positions[0].rect.origin.x >= manager.layoutBounds().origin.x
    check selection.len > 0
    check not firstRect.isEmpty
    check not emptyFirstRect.isEmpty
    check not textBounds.isEmpty
    check not glyphBounds.isEmpty
