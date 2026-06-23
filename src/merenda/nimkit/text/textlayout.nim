from figdraw/common/fonttypes import GlyphArrangement

import ../drawing
import ./textstorage
import ./texttypes
import ../themes
import ../foundation/types

type
  TextContainer* = object
    size*: Size
    insets*: EdgeInsets
    wraps*: bool

  TextLayoutManager* = ref object
    xTextStorage: TextStorage
    xTextContainer: TextContainer
    xAlignment: TextAlignment
    xLayout: GlyphArrangement
    xLayoutRect: Rect
    xHasLayout: bool

func initTextContainer*(
    size = initSize(0.0, 0.0), insets = initEdgeInsets(0.0), wraps = false
): TextContainer =
  TextContainer(size: size, insets: insets, wraps: wraps)

proc initTextLayoutManagerFields*(
    manager: TextLayoutManager,
    storage: TextStorage = nil,
    container = initTextContainer(),
    alignment = taLeft,
) =
  manager.xTextStorage = storage
  manager.xTextContainer = container
  manager.xAlignment = alignment

proc newTextLayoutManager*(
    storage: TextStorage = nil, container = initTextContainer(), alignment = taLeft
): TextLayoutManager =
  result = TextLayoutManager()
  initTextLayoutManagerFields(result, storage, container, alignment)

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

proc ensureLayout(manager: TextLayoutManager) =
  if manager.isNil or manager.xHasLayout:
    return
  let rect = manager.layoutRect()
  manager.xLayoutRect = rect
  manager.xLayout = textLayout(
    rect, manager.xTextStorage, manager.xAlignment, manager.xTextContainer.wraps
  )
  manager.xHasLayout = true

proc glyphArrangement*(manager: TextLayoutManager): GlyphArrangement =
  if manager.isNil:
    return GlyphArrangement()
  manager.ensureLayout()
  manager.xLayout

proc caretRect*(manager: TextLayoutManager, insertionPoint: int): Rect =
  if manager.isNil:
    return initRect(0.0, 0.0, 1.0, DefaultFontSize)
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

proc textIndexAtPoint*(manager: TextLayoutManager, point: Point): int =
  if manager.isNil:
    return 0
  manager.ensureLayout()
  let localPoint = initPoint(
    point.x - manager.xLayoutRect.origin.x, point.y - manager.xLayoutRect.origin.y
  )
  for index, rect in manager.xLayout.selectionRects:
    if localPoint.y >= rect.y and localPoint.y < rect.y + rect.h:
      if localPoint.x < rect.x + rect.w * 0.5'f32:
        return index
      if localPoint.x < rect.x + rect.w:
        return index + 1
  manager.xTextStorage.len
