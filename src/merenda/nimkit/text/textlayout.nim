import std/[algorithm, hashes, unicode]

from figdraw/common/fonttypes import
  GlyphArrangement, GlyphFont, nearestSourceRuneForCaretPoint
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

proc ensureLayout(manager: TextLayoutManager) =
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
  manager.ensureLayout()
  manager.xLayout

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
  manager.ensureLayout()

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

proc layoutSnapshot*(manager: TextLayoutManager): TextLayoutSnapshot =
  if manager.isNil:
    return
  manager.ensureLayout()
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

proc caretRect*(manager: TextLayoutManager, insertionPoint: int): Rect =
  if manager.isNil:
    return initRect(0.0, 0.0, 1.0, defaultFontSize())
  manager.ensureLayout()
  caretRect(manager.xLayoutRect, manager.xLayout, insertionPoint)

proc selectionRects*(manager: TextLayoutManager, range: TextRange): seq[Rect] =
  if manager.isNil or range.length == 0:
    return @[]
  manager.ensureLayout()
  let
    first = max(0, min(int(range.location), manager.xLayout.selectionRects.len))
    last = max(first, min(range.maxIndex, manager.xLayout.selectionRects.len))
  for index in first ..< last:
    let rect = manager.xLayout.selectionRects[index]
    result.add initRect(
      manager.xLayoutRect.origin.x + rect.x,
      manager.xLayoutRect.origin.y + rect.y,
      rect.w,
      rect.h,
    )

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
  manager.ensureLayout()
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
