import std/[algorithm, hashes, options, unicode]

from figdraw/common/fonttypes import
  CaretInside, CaretLeading, CaretTrailing, GlyphArrangement, GlyphFont,
  TextCaretAffinity, caretPositionsFor, glyphIndexAt, glyphRangeFor,
  nearestSourceRuneForCaretPoint, selectionRectsFor, sourceRuneRangeAt
from pkg/vmath import vec2, x, y

import ../drawing
import ./textstorage
import ./texttypes
import ../themes
import ../foundation/types

type
  GlyphIndex* = distinct Natural
  TextLineIndex* = distinct Natural

  GlyphRange* = object
    location*: GlyphIndex
    length*: Natural

  TextLineRange* = object
    location*: TextLineIndex
    length*: Natural

  TextCaretPositionKind* = enum
    tcpLeading
    tcpInside
    tcpTrailing

  TextCaretPosition* = object
    textIndex*: TextIndex
    glyphIndex*: Option[GlyphIndex]
    lineIndex*: TextLineIndex
    kind*: TextCaretPositionKind
    rect*: Rect

  TextLineFragment* = object
    lineIndex*: TextLineIndex
    glyphRange*: GlyphRange
    textRange*: TextRange
    fragmentRect*: Rect
    usedRect*: Rect
    baseline*: float32
    ascent*: float32
    descent*: float32
    leading*: float32
    hardBreak*: bool
    wrapped*: bool

  TextLayoutSnapshot* = object
    textHash*: Hash
    layoutHash*: Hash
    containerRect*: Rect
    lineFragments*: seq[TextLineFragment]
    glyphCount*: Natural
    usedRect*: Rect
    contentSize*: Size

  TextContainer* = object
    size*: Size
    insets*: EdgeInsets
    wraps*: bool

  TextLayoutManager* = ref object
    xTextStorage: TextStorage
    xTextContainer: TextContainer
    xTextStyle: TextStyle
    xAlignment: TextAlignment
    xLayout: GlyphArrangement
    xLayoutRect: Rect
    xHasLayout: bool

proc `==`*(a, b: GlyphIndex): bool {.borrow.}
proc `$`*(index: GlyphIndex): string {.borrow.}
proc `==`*(a, b: TextLineIndex): bool {.borrow.}
proc `$`*(index: TextLineIndex): string {.borrow.}

func initGlyphIndex*(value: int): GlyphIndex =
  GlyphIndex(max(value, 0).Natural)

func toInt*(index: GlyphIndex): int =
  system.int(Natural(index))

func initGlyphRange*(location, length: int): GlyphRange =
  GlyphRange(location: initGlyphIndex(location), length: max(length, 0).Natural)

func maxIndex*(range: GlyphRange): int =
  range.location.toInt + int(range.length)

func isEmpty*(range: GlyphRange): bool =
  range.length == 0

func initTextLineIndex*(value: int): TextLineIndex =
  TextLineIndex(max(value, 0).Natural)

func toInt*(index: TextLineIndex): int =
  system.int(Natural(index))

func initTextLineRange*(location, length: int): TextLineRange =
  TextLineRange(location: initTextLineIndex(location), length: max(length, 0).Natural)

func maxIndex*(range: TextLineRange): int =
  range.location.toInt + int(range.length)

func isEmpty*(range: TextLineRange): bool =
  range.length == 0

func initTextContainer*(
    size = initSize(0.0, 0.0), insets = insets(0.0), wraps = false
): TextContainer =
  TextContainer(size: size, insets: insets, wraps: wraps)

proc initTextLayoutManagerFields*(
    manager: TextLayoutManager,
    storage: TextStorage = nil,
    container = initTextContainer(),
    alignment = taLeft,
    style = initAppearance().resolveTextStyle(
        controlStyle(srTextView), initColor(0.08, 0.09, 0.11, 1.0), insets(0.0)
      ),
) =
  manager.xTextStorage = storage
  manager.xTextContainer = container
  manager.xTextStyle = style
  manager.xAlignment = alignment

proc newTextLayoutManager*(
    storage: TextStorage = nil,
    container = initTextContainer(),
    alignment = taLeft,
    style = initAppearance().resolveTextStyle(
        controlStyle(srTextView), initColor(0.08, 0.09, 0.11, 1.0), insets(0.0)
      ),
): TextLayoutManager =
  result = TextLayoutManager()
  initTextLayoutManagerFields(result, storage, container, alignment, style)

proc invalidateLayout*(manager: TextLayoutManager) =
  if not manager.isNil:
    manager.xHasLayout = false

proc invalidateLayout*(manager: TextLayoutManager, range: TextRange) =
  discard range
  manager.invalidateLayout()

proc hasValidLayout*(manager: TextLayoutManager): bool =
  not manager.isNil and manager.xHasLayout

proc textStorage*(manager: TextLayoutManager): TextStorage =
  if manager.isNil: nil else: manager.xTextStorage

proc `textStorage=`*(manager: TextLayoutManager, storage: TextStorage) =
  if manager.isNil:
    return
  manager.xTextStorage = storage
  manager.invalidateLayout()

proc textContainer*(manager: TextLayoutManager): TextContainer =
  if manager.isNil:
    initTextContainer()
  else:
    manager.xTextContainer

proc `textContainer=`*(manager: TextLayoutManager, container: TextContainer) =
  if manager.isNil:
    return
  manager.xTextContainer = container
  manager.invalidateLayout()

proc textStyle*(manager: TextLayoutManager): TextStyle =
  if manager.isNil:
    initAppearance().resolveTextStyle(
      controlStyle(srTextView), initColor(0.08, 0.09, 0.11, 1.0), insets(0.0)
    )
  else:
    manager.xTextStyle

proc `textStyle=`*(manager: TextLayoutManager, style: TextStyle) =
  if manager.isNil or manager.xTextStyle == style:
    return
  manager.xTextStyle = style
  manager.invalidateLayout()

proc alignment*(manager: TextLayoutManager): TextAlignment =
  if manager.isNil: taLeft else: manager.xAlignment

proc `alignment=`*(manager: TextLayoutManager, alignment: TextAlignment) =
  if manager.isNil or manager.xAlignment == alignment:
    return
  manager.xAlignment = alignment
  manager.invalidateLayout()

proc layoutRect(manager: TextLayoutManager): Rect =
  let container = manager.xTextContainer
  initRect(0.0, 0.0, container.size.width, container.size.height).inset(
    container.insets
  )

func clampTextRange(total: int, range: TextRange): TextRange =
  let
    start = max(0, min(int(range.location), total))
    length = max(0, min(int(range.length), total - start))
  initTextRange(start, length)

func sourceSlice(range: TextRange): Slice[int] =
  if range.length == 0:
    return 0 .. -1
  int(range.location) .. range.maxIndex - 1

func sourceLength(layout: GlyphArrangement): int =
  if layout.sourceRunes.len > 0: layout.sourceRunes.len else: layout.runes.len

func glyphCount(layout: GlyphArrangement): int =
  if layout.arrangedGlyphs.len > 0: layout.arrangedGlyphs.len else: layout.runes.len

func glyphRect(layout: GlyphArrangement, glyphIndex: int): Rect =
  if glyphIndex < 0:
    return initRect(0.0, 0.0, 0.0, 0.0)
  if layout.arrangedGlyphs.len > 0:
    if glyphIndex < layout.arrangedGlyphs.len:
      let rect = layout.arrangedGlyphs[glyphIndex].rect
      return initRect(rect.x, rect.y, rect.w, rect.h)
  elif glyphIndex < layout.selectionRects.len:
    let rect = layout.selectionRects[glyphIndex]
    return initRect(rect.x, rect.y, rect.w, rect.h)
  initRect(0.0, 0.0, 0.0, 0.0)

func sourceRangeForGlyph(layout: GlyphArrangement, glyphIndex: int): TextRange =
  if glyphIndex < 0:
    return initTextRange(0, 0)
  if layout.arrangedGlyphs.len > 0 and glyphIndex < layout.arrangedGlyphs.len:
    let source = layout.arrangedGlyphs[glyphIndex].source
    return initTextRange(source.runeStart, source.runeEnd - source.runeStart)
  if glyphIndex < layout.runes.len:
    return initTextRange(glyphIndex, 1)
  initTextRange(0, 0)

func fontForGlyph(layout: GlyphArrangement, glyphIndex: int): GlyphFont =
  for fontIndex, span in layout.spans:
    if glyphIndex in span and fontIndex < layout.fonts.len:
      return layout.fonts[fontIndex]
  if layout.fonts.len > 0:
    return layout.fonts[0]

func normalizedGlyphLine(layout: GlyphArrangement, line: Slice[int]): Slice[int] =
  let count = layout.glyphCount()
  if count == 0:
    return 0 .. -1
  result = max(line.a, 0) .. min(line.b, count - 1)
  if result.a > result.b:
    result = 0 .. -1

func textRangeForGlyphLine(layout: GlyphArrangement, line: Slice[int]): TextRange =
  if line.a > line.b:
    return initTextRange(0, 0)
  var
    found = false
    start = high(int)
    stop = 0
  for glyphIndex in line:
    let source = layout.sourceRangeForGlyph(glyphIndex)
    if source.length == 0:
      continue
    start = min(start, int(source.location))
    stop = max(stop, source.maxIndex)
    found = true
  if found:
    initTextRange(start, stop - start)
  else:
    initTextRange(0, 0)

func containsHardBreak(runes: openArray[Rune], range: TextRange): bool =
  if runes.len == 0:
    return false
  let
    start = int(range.location)
    stop = range.maxIndex
  if stop > start and stop - 1 < runes.len and runes[stop - 1] == Rune('\n'):
    return true
  stop < runes.len and runes[stop] == Rune('\n')

func textRangeIntersects(a, b: TextRange): bool =
  int(a.location) < b.maxIndex and int(b.location) < a.maxIndex

func toTextCaretPositionKind(affinity: TextCaretAffinity): TextCaretPositionKind =
  case affinity
  of CaretLeading: tcpLeading
  of CaretInside: tcpInside
  of CaretTrailing: tcpTrailing

proc updateLayout*(manager: TextLayoutManager) =
  if manager.isNil or manager.xHasLayout:
    return
  let rect = manager.layoutRect()
  manager.xLayoutRect = rect
  manager.xLayout = textLayout(
    rect, manager.xTextStorage, manager.xTextStyle, manager.xAlignment,
    manager.xTextContainer.wraps,
  )
  manager.xHasLayout = true

proc glyphArrangement*(manager: TextLayoutManager): GlyphArrangement =
  if manager.isNil:
    return GlyphArrangement()
  manager.updateLayout()
  manager.xLayout

proc layoutBounds*(manager: TextLayoutManager): Rect =
  if manager.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  manager.updateLayout()
  manager.xLayoutRect

proc glyphCount*(manager: TextLayoutManager): Natural =
  if manager.isNil:
    return 0.Natural
  manager.updateLayout()
  manager.xLayout.glyphCount().Natural

proc containerRect(rect: Rect, layoutRect: Rect): Rect =
  initRect(
    layoutRect.origin.x + rect.origin.x,
    layoutRect.origin.y + rect.origin.y,
    rect.size.width,
    rect.size.height,
  )

proc lineFragment(
    manager: TextLayoutManager, visualIndex: int, line: Slice[int], lineCount: int
): TextLineFragment =
  let
    layout = manager.xLayout
    textRange = layout.textRangeForGlyphLine(line)
    glyphRange = initGlyphRange(line.a, line.b - line.a + 1)
    sourceRunes = if layout.sourceRunes.len > 0: layout.sourceRunes else: layout.runes
    hardBreak = containsHardBreak(sourceRunes, textRange)
    wrapped =
      manager.xTextContainer.wraps and not hardBreak and visualIndex < lineCount - 1

  var
    usedRect = initRect(0.0, 0.0, 0.0, 0.0)
    hasUsedRect = false
    lineHeight = 0.0'f32
    baselineOffset = 0.0'f32

  for glyphIndex in line:
    let
      glyphRect = layout.glyphRect(glyphIndex).containerRect(manager.xLayoutRect)
      font = layout.fontForGlyph(glyphIndex)
    if not glyphRect.isEmpty:
      if hasUsedRect:
        usedRect = usedRect.union(glyphRect)
      else:
        usedRect = glyphRect
        hasUsedRect = true
    lineHeight = max(lineHeight, max(font.lineHeight, glyphRect.size.height))
    baselineOffset = max(baselineOffset, font.descentAdj)

  if lineHeight <= 0.0'f32:
    lineHeight = defaultFontSize()
  if baselineOffset <= 0.0'f32:
    baselineOffset = min(lineHeight, lineHeight * 0.8'f32)

  let lineTop = if hasUsedRect: usedRect.origin.y else: manager.xLayoutRect.origin.y
  let fragmentRect = initRect(
    manager.xLayoutRect.origin.x,
    lineTop,
    manager.xLayoutRect.size.width,
    max(lineHeight, usedRect.size.height),
  )
  let ascent = min(max(baselineOffset, 0.0'f32), fragmentRect.size.height)

  TextLineFragment(
    lineIndex: initTextLineIndex(visualIndex),
    glyphRange: glyphRange,
    textRange: textRange,
    fragmentRect: fragmentRect,
    usedRect: usedRect,
    baseline: fragmentRect.origin.y + ascent,
    ascent: ascent,
    descent: max(fragmentRect.size.height - ascent, 0.0'f32),
    leading: 0.0'f32,
    hardBreak: hardBreak,
    wrapped: wrapped,
  )

proc emptyLineFragment(
    manager: TextLayoutManager, visualIndex: int, sourceIndex: int
): TextLineFragment =
  let
    caret = caretRect(manager.xLayoutRect, manager.xLayout, sourceIndex)
    lineHeight = max(caret.size.height, defaultFontSize())
  let fragmentRect = initRect(
    manager.xLayoutRect.origin.x, caret.origin.y, manager.xLayoutRect.size.width,
    lineHeight,
  )
  let ascent = min(lineHeight, lineHeight * 0.8'f32)
  TextLineFragment(
    lineIndex: initTextLineIndex(visualIndex),
    glyphRange: initGlyphRange(0, 0),
    textRange: initTextRange(sourceIndex, 0),
    fragmentRect: fragmentRect,
    usedRect: initRect(fragmentRect.origin, initSize(0.0, lineHeight)),
    baseline: fragmentRect.origin.y + ascent,
    ascent: ascent,
    descent: max(lineHeight - ascent, 0.0'f32),
    leading: 0.0'f32,
  )

func startsAtTextIndex(fragments: openArray[TextLineFragment], index: int): bool =
  for fragment in fragments:
    if int(fragment.textRange.location) == index:
      return true

proc reindexLineFragments(fragments: var seq[TextLineFragment]) =
  fragments.sort(
    proc(a, b: TextLineFragment): int =
      result = cmp(a.fragmentRect.origin.y, b.fragmentRect.origin.y)
      if result == 0:
        result = cmp(a.fragmentRect.origin.x, b.fragmentRect.origin.x)
  )
  for index in 0 ..< fragments.len:
    fragments[index].lineIndex = initTextLineIndex(index)

proc lineFragments*(manager: TextLayoutManager): seq[TextLineFragment] =
  if manager.isNil:
    return
  manager.updateLayout()

  let count = manager.xLayout.glyphCount()
  if count == 0:
    result.add manager.emptyLineFragment(0, 0)
    return

  var lines = manager.xLayout.lines
  if lines.len == 0:
    lines.add 0 .. count - 1

  for visualIndex, rawLine in lines:
    let line = manager.xLayout.normalizedGlyphLine(rawLine)
    if line.a <= line.b:
      result.add manager.lineFragment(visualIndex, line, lines.len)

  if not manager.xTextStorage.isNil:
    var index = 0
    for rune in manager.xTextStorage.stringValue().runes:
      if rune == Rune('\n'):
        let nextIndex = index + 1
        if not result.startsAtTextIndex(nextIndex):
          result.add manager.emptyLineFragment(result.len, nextIndex)
      inc index
  result.reindexLineFragments()

iterator lineFragmentItems*(manager: TextLayoutManager): TextLineFragment =
  for fragment in manager.lineFragments():
    yield fragment

proc lineCount*(manager: TextLayoutManager): Natural =
  manager.lineFragments().len.Natural

proc layoutSnapshot*(manager: TextLayoutManager): TextLayoutSnapshot =
  if manager.isNil:
    return
  manager.updateLayout()
  result.textHash =
    if manager.xTextStorage.isNil:
      hash("")
    else:
      hash(manager.xTextStorage.stringValue())
  result.layoutHash = manager.xLayout.contentHash
  result.containerRect = manager.xLayoutRect
  result.glyphCount = manager.xLayout.glyphCount().Natural
  result.lineFragments = manager.lineFragments()

  var hasUsedRect = false
  for fragment in result.lineFragments:
    if not fragment.usedRect.isEmpty:
      if hasUsedRect:
        result.usedRect = result.usedRect.union(fragment.usedRect)
      else:
        result.usedRect = fragment.usedRect
        hasUsedRect = true

  if not hasUsedRect:
    result.usedRect = initRect(result.containerRect.origin, initSize(0.0, 0.0))

  var
    contentWidth = max(manager.xLayout.maxSize.x, manager.xLayout.bounding.w)
    contentHeight = max(manager.xLayout.maxSize.y, manager.xLayout.bounding.h)
  if hasUsedRect:
    contentWidth = max(contentWidth, result.usedRect.size.width)
    contentHeight =
      max(contentHeight, result.usedRect.maxY - result.containerRect.origin.y)
  elif result.lineFragments.len > 0:
    contentHeight =
      max(contentHeight, result.lineFragments[^1].fragmentRect.size.height)
  result.contentSize = initSize(max(contentWidth, 0.0'f32), max(contentHeight, 0.0'f32))

proc usedRect*(manager: TextLayoutManager): Rect =
  manager.layoutSnapshot().usedRect

proc contentSize*(manager: TextLayoutManager): Size =
  manager.layoutSnapshot().contentSize

proc emptyGlyphRangeForTextIndex(
    manager: TextLayoutManager, sourceIndex, count: int
): GlyphRange =
  if sourceIndex <= 0:
    return initGlyphRange(0, 0)
  if sourceIndex >= manager.xLayout.sourceLength:
    return initGlyphRange(count, 0)

  for glyphIndex in 0 ..< count:
    let source = manager.xLayout.sourceRangeForGlyph(glyphIndex)
    if sourceIndex <= source.maxIndex:
      return initGlyphRange(glyphIndex, 0)
  initGlyphRange(count, 0)

proc glyphRangeForTextRange*(manager: TextLayoutManager, range: TextRange): GlyphRange =
  if manager.isNil:
    return initGlyphRange(0, 0)
  manager.updateLayout()
  let
    count = manager.xLayout.glyphCount()
    clamped = clampTextRange(manager.xLayout.sourceLength, range)
  if clamped.length == 0 or count == 0:
    return manager.emptyGlyphRangeForTextIndex(int(clamped.location), count)

  let glyphRange = manager.xLayout.glyphRangeFor(clamped.sourceSlice)
  if glyphRange.a > glyphRange.b:
    return initGlyphRange(0, 0)
  initGlyphRange(glyphRange.a, glyphRange.b - glyphRange.a + 1)

proc textRangeForGlyphRange*(manager: TextLayoutManager, range: GlyphRange): TextRange =
  if manager.isNil:
    return initTextRange(0, 0)
  manager.updateLayout()
  let
    count = manager.xLayout.glyphCount()
    start = max(0, min(range.location.toInt, count))
    stop = max(start, min(range.maxIndex, count))
  if range.length == 0:
    if start >= count:
      return initTextRange(manager.xLayout.sourceLength, 0)
    return initTextRange(int(manager.xLayout.sourceRangeForGlyph(start).location), 0)

  var
    found = false
    textStart = high(int)
    textStop = 0
  for glyphIndex in start ..< stop:
    let source = manager.xLayout.sourceRangeForGlyph(glyphIndex)
    if source.length > 0:
      textStart = min(textStart, int(source.location))
      textStop = max(textStop, source.maxIndex)
      found = true
  if found:
    initTextRange(textStart, textStop - textStart)
  else:
    initTextRange(0, 0)

proc glyphIndexAtPoint*(manager: TextLayoutManager, point: Point): Option[GlyphIndex] =
  if manager.isNil:
    return none(GlyphIndex)
  manager.updateLayout()
  let localPoint = initPoint(
    point.x - manager.xLayoutRect.origin.x, point.y - manager.xLayoutRect.origin.y
  )
  let glyphIndex = manager.xLayout.glyphIndexAt(vec2(localPoint.x, localPoint.y))
  if glyphIndex < 0:
    none(GlyphIndex)
  else:
    some(initGlyphIndex(glyphIndex))

proc textIndexAtPoint*(manager: TextLayoutManager, point: Point): int

proc textRangeAtPoint*(manager: TextLayoutManager, point: Point): TextRange =
  if manager.isNil:
    return initTextRange(0, 0)
  manager.updateLayout()
  let localPoint = initPoint(
    point.x - manager.xLayoutRect.origin.x, point.y - manager.xLayoutRect.origin.y
  )
  let sourceRange = manager.xLayout.sourceRuneRangeAt(vec2(localPoint.x, localPoint.y))
  if sourceRange.a <= sourceRange.b:
    return initTextRange(sourceRange.a, sourceRange.b - sourceRange.a + 1)
  initTextRange(manager.textIndexAtPoint(point), 0)

proc lineFragment*(
    manager: TextLayoutManager, index: TextLineIndex
): Option[TextLineFragment] =
  let fragments = manager.lineFragments()
  let lineIndex = index.toInt
  if lineIndex < 0 or lineIndex >= fragments.len:
    none(TextLineFragment)
  else:
    some(fragments[lineIndex])

proc lineFragment*(manager: TextLayoutManager, index: int): Option[TextLineFragment] =
  if index < 0:
    none(TextLineFragment)
  else:
    manager.lineFragment(initTextLineIndex(index))

func textIndexInFragment(fragment: TextLineFragment, index, textLength: int): bool =
  let
    start = int(fragment.textRange.location)
    stop = fragment.textRange.maxIndex
  if fragment.textRange.length == 0:
    return index == start
  if index == textLength and stop == textLength:
    return true
  index >= start and index < stop

proc lineFragmentForTextIndex*(
    manager: TextLayoutManager, index: TextIndex
): Option[TextLineFragment] =
  if manager.isNil:
    return none(TextLineFragment)
  let
    textLength = if manager.xTextStorage.isNil: 0 else: manager.xTextStorage.len
    textIndex = max(0, min(index.toInt, textLength))
    fragments = manager.lineFragments()
  for fragment in fragments:
    if int(fragment.textRange.location) == textIndex:
      return some(fragment)
  for fragment in fragments:
    if fragment.textIndexInFragment(textIndex, textLength):
      return some(fragment)
  if fragments.len > 0:
    some(fragments[^1])
  else:
    none(TextLineFragment)

proc lineFragmentForTextIndex*(
    manager: TextLayoutManager, index: int
): Option[TextLineFragment] =
  manager.lineFragmentForTextIndex(initTextIndex(index))

proc lineFragmentForGlyphIndex*(
    manager: TextLayoutManager, index: GlyphIndex
): Option[TextLineFragment] =
  if manager.isNil:
    return none(TextLineFragment)
  let
    glyphIndex = index.toInt
    fragments = manager.lineFragments()
  for fragment in fragments:
    if fragment.glyphRange.length > 0 and
        glyphIndex >= fragment.glyphRange.location.toInt and
        glyphIndex < fragment.glyphRange.maxIndex:
      return some(fragment)
  if fragments.len == 1 and fragments[0].glyphRange.isEmpty and glyphIndex == 0:
    some(fragments[0])
  else:
    none(TextLineFragment)

proc lineFragmentForGlyphIndex*(
    manager: TextLayoutManager, index: int
): Option[TextLineFragment] =
  if index < 0:
    none(TextLineFragment)
  else:
    manager.lineFragmentForGlyphIndex(initGlyphIndex(index))

proc lineFragmentsForTextRange*(
    manager: TextLayoutManager, range: TextRange
): seq[TextLineFragment] =
  if manager.isNil:
    return
  let
    textLength = if manager.xTextStorage.isNil: 0 else: manager.xTextStorage.len
    clamped = clampTextRange(textLength, range)
  if clamped.length == 0:
    let fragment = manager.lineFragmentForTextIndex(int(clamped.location))
    if fragment.isSome:
      result.add fragment.get()
    return

  for fragment in manager.lineFragments():
    if fragment.textRange.length == 0:
      let location = int(fragment.textRange.location)
      if location >= int(clamped.location) and location <= clamped.maxIndex:
        result.add fragment
    elif fragment.textRange.textRangeIntersects(clamped):
      result.add fragment

proc lineRangeForTextRange*(
    manager: TextLayoutManager, range: TextRange
): TextLineRange =
  let fragments = manager.lineFragmentsForTextRange(range)
  if fragments.len == 0:
    return initTextLineRange(0, 0)
  let
    first = fragments[0].lineIndex.toInt
    last = fragments[^1].lineIndex.toInt
  initTextLineRange(first, last - first + 1)

proc caretRect*(manager: TextLayoutManager, insertionPoint: int): Rect =
  if manager.isNil:
    return initRect(0.0, 0.0, 1.0, defaultFontSize())
  manager.updateLayout()
  caretRect(manager.xLayoutRect, manager.xLayout, insertionPoint)

proc caretPositions*(
    manager: TextLayoutManager, insertionPoint: int
): seq[TextCaretPosition] =
  if manager.isNil:
    return
  manager.updateLayout()
  let
    sourceCount = manager.xLayout.sourceLength
    index = max(0, min(insertionPoint, sourceCount))
  for caret in manager.xLayout.caretPositionsFor(index):
    result.add TextCaretPosition(
      textIndex: initTextIndex(caret.sourceRune),
      glyphIndex:
        if caret.glyphIndex >= 0:
          some(initGlyphIndex(caret.glyphIndex))
        else:
          none(GlyphIndex),
      lineIndex: initTextLineIndex(caret.lineIndex),
      kind: caret.affinity.toTextCaretPositionKind(),
      rect: initRect(
        manager.xLayoutRect.origin.x + caret.rect.x,
        manager.xLayoutRect.origin.y + caret.rect.y,
        caret.rect.w,
        caret.rect.h,
      ),
    )
  if result.len == 0:
    result.add TextCaretPosition(
      textIndex: initTextIndex(index),
      glyphIndex: none(GlyphIndex),
      lineIndex: initTextLineIndex(0),
      kind: tcpInside,
      rect: manager.caretRect(index),
    )

proc selectionRects*(manager: TextLayoutManager, range: TextRange): seq[Rect] =
  if manager.isNil or range.length == 0:
    return @[]
  manager.updateLayout()
  let clamped = clampTextRange(manager.xLayout.sourceLength, range)
  for rect in manager.xLayout.selectionRectsFor(clamped.sourceSlice):
    result.add initRect(
      manager.xLayoutRect.origin.x + rect.x,
      manager.xLayoutRect.origin.y + rect.y,
      rect.w,
      rect.h,
    )

proc firstRectForTextRange*(manager: TextLayoutManager, range: TextRange): Rect =
  if manager.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  if range.length == 0:
    return manager.caretRect(int(range.location))
  let rects = manager.selectionRects(range)
  if rects.len > 0:
    rects[0]
  else:
    manager.caretRect(int(range.location))

proc textRangeBounds*(manager: TextLayoutManager, range: TextRange): Rect =
  for rect in manager.selectionRects(range):
    if result.isEmpty:
      result = rect
    else:
      result = result.union(rect)

proc characterRect*(manager: TextLayoutManager, index: int): Rect =
  if manager.isNil or manager.xTextStorage.isNil:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let total = manager.xTextStorage.len
  if index < 0 or index >= total:
    return initRect(0.0, 0.0, 0.0, 0.0)
  result = manager.textRangeBounds(initTextRange(index, 1))
  if result.isEmpty:
    result = manager.caretRect(index)

proc boundsForGlyphRange*(manager: TextLayoutManager, range: GlyphRange): Rect =
  if manager.isNil or range.length == 0:
    return initRect(0.0, 0.0, 0.0, 0.0)
  manager.updateLayout()
  let
    count = manager.xLayout.glyphCount()
    start = max(0, min(range.location.toInt, count))
    stop = max(start, min(range.maxIndex, count))
  for glyphIndex in start ..< stop:
    let rect = manager.xLayout.glyphRect(glyphIndex).containerRect(manager.xLayoutRect)
    if result.isEmpty:
      result = rect
    else:
      result = result.union(rect)

proc lineRange*(manager: TextLayoutManager, line: int): TextRange =
  if manager.isNil or manager.xTextStorage.isNil or line < 0:
    return initTextRange(0, 0)
  let text = manager.xTextStorage.stringValue()
  var
    currentLine = 0
    start = 0
    index = 0
  for rune in text.runes:
    if currentLine == line and rune == Rune('\n'):
      return initTextRange(start, index - start)
    if rune == Rune('\n'):
      inc currentLine
      start = index + 1
    inc index
  if currentLine == line:
    return initTextRange(start, index - start)
  initTextRange(0, 0)

proc lineForIndex*(manager: TextLayoutManager, index: int): int =
  if manager.isNil or manager.xTextStorage.isNil:
    return -1
  let
    total = manager.xTextStorage.len
    target = max(0, min(index, total))
  result = 0
  var current = 0
  for rune in manager.xTextStorage.stringValue().runes:
    if current >= target:
      return
    if rune == Rune('\n'):
      inc result
    inc current

proc lineBounds*(manager: TextLayoutManager, line: int): Rect =
  if manager.isNil or manager.xTextStorage.isNil or line < 0:
    return initRect(0.0, 0.0, 0.0, 0.0)
  let range = manager.lineRange(line)
  if range.length > 0:
    return manager.textRangeBounds(range)
  if line == manager.lineForIndex(int(range.location)):
    return manager.caretRect(int(range.location))
  initRect(0.0, 0.0, 0.0, 0.0)

proc emptyLineIndexAtPoint(manager: TextLayoutManager, point: Point): int =
  if manager.isNil or manager.xTextStorage.isNil:
    return -1

  let runes = manager.xTextStorage.stringValue().toRunes()
  for index, rune in runes:
    if rune != Rune('\n'):
      continue
    let nextIndex = index + 1
    if nextIndex < runes.len and runes[nextIndex] != Rune('\n'):
      continue

    let
      caret = manager.caretRect(nextIndex)
      lineHeight = max(caret.size.height, defaultFontSize())
      caretY = caret.origin.y - manager.xLayoutRect.origin.y
    if point.y >= caretY and point.y < caretY + lineHeight:
      return nextIndex

  -1

proc lineBoundedIndexAtPoint(manager: TextLayoutManager, point: Point): int =
  if manager.isNil or manager.xTextStorage.isNil:
    return -1

  let total = manager.xTextStorage.stringValue().runeLen
  var firstIndex = -1
  var lastIndex = -1
  var closestIndex = -1
  var minX = high(float32)
  var maxX = -high(float32)
  var closestDistance = high(float32)

  for index in 0 .. total:
    let
      caret = manager.caretRect(index)
      lineHeight = max(caret.size.height, defaultFontSize())
      caretX = caret.origin.x - manager.xLayoutRect.origin.x
      caretY = caret.origin.y - manager.xLayoutRect.origin.y

    if point.y < caretY or point.y >= caretY + lineHeight:
      continue

    if firstIndex < 0 or index < firstIndex:
      firstIndex = index
    if index > lastIndex:
      lastIndex = index
    minX = min(minX, caretX)
    maxX = max(maxX, caretX)

    let distance = abs(point.x - caretX)
    if distance < closestDistance:
      closestDistance = distance
      closestIndex = index

  if closestIndex < 0:
    return -1
  if point.x <= minX:
    return firstIndex
  if point.x >= maxX:
    return lastIndex
  closestIndex

proc textIndexAtPoint*(manager: TextLayoutManager, point: Point): int =
  if manager.isNil:
    return 0
  manager.updateLayout()
  let localPoint = initPoint(
    point.x - manager.xLayoutRect.origin.x, point.y - manager.xLayoutRect.origin.y
  )
  let emptyLineIndex = manager.emptyLineIndexAtPoint(localPoint)
  if emptyLineIndex >= 0:
    return emptyLineIndex
  let lineBoundedIndex = manager.lineBoundedIndexAtPoint(localPoint)
  if lineBoundedIndex >= 0:
    return lineBoundedIndex
  let nearest =
    manager.xLayout.nearestSourceRuneForCaretPoint(vec2(localPoint.x, localPoint.y))
  max(0, min(nearest, manager.xTextStorage.len))
