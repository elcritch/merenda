import std/[algorithm, hashes, options, sets, unicode]

import sigils/core

when defined(useNativeDynlib):
  import figdraw/dynlib except Hash
else:
  import figdraw
  from figdraw/common/typefaces import getFigFont
from pkg/vmath import vec2, x, y

import ../drawing
import ../foundation/selectors
import ./textstorage
import ./texttypes
import ../themes
import ../foundation/types

type
  GlyphIndex* = distinct Natural
  TextLineIndex* = distinct Natural
  TextContainerIndex* = distinct Natural

  GlyphRange* = object
    location*: GlyphIndex
    length*: Natural

  TextLineRange* = object
    location*: TextLineIndex
    length*: Natural

  GlyphProperty* = enum
    gpControl
    gpElastic
    gpAttachment
    gpNull

  GlyphProperties* = set[GlyphProperty]

  TextGlyphPropertyRun* = object
    range*: GlyphRange
    properties*: GlyphProperties

  TextLayoutInvalidationKind* = enum
    tlikCharacters
    tlikGlyphs
    tlikLayout
    tlikDisplay
    tlikContainer

  TextLayoutInvalidation* = object
    kind*: TextLayoutInvalidationKind
    textRange*: TextRange
    glyphRange*: GlyphRange
    containerIndex*: Option[TextContainerIndex]

  TextCaretPositionKind* = enum
    tcpLeading
    tcpInside
    tcpTrailing

  TextCaretPosition* = object
    textIndex*: TextIndex
    glyphIndex*: Option[GlyphIndex]
    lineIndex*: TextLineIndex
    containerIndex*: TextContainerIndex
    kind*: TextCaretPositionKind
    rect*: Rect

  TextLineFragment* = object
    lineIndex*: TextLineIndex
    containerIndex*: TextContainerIndex
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

  TextLineFragmentMetrics* = object
    fragment*: TextLineFragment
    lineSpacing*: float32
    paragraphSpacingBefore*: float32
    paragraphSpacingAfter*: float32
    extraLineFragment*: bool

  TextGlyph* = object
    index*: GlyphIndex
    textRange*: TextRange
    properties*: GlyphProperties
    bounds*: Rect
    lineIndex*: TextLineIndex
    containerIndex*: TextContainerIndex

  TextLayoutSnapshot* = object
    textHash*: Hash
    layoutHash*: Hash
    containerRect*: Rect
    containers*: seq[TextContainer]
    containerRects*: seq[Rect]
    lineFragments*: seq[TextLineFragment]
    glyphCount*: Natural
    usedRect*: Rect
    contentSize*: Size

  TextContainer* = object
    origin*: Point
    size*: Size
    insets*: EdgeInsets
    lineFragmentPadding*: float32
    widthTracksTextView*: bool
    heightTracksTextView*: bool
    maximumNumberOfLines*: Natural
    lineBreakMode*: TextLineBreakMode
    wraps*: bool
    exclusionPaths*: seq[Rect]

  TextHitTestResult* = object
    point*: Point
    textIndex*: TextIndex
    textRange*: TextRange
    glyphIndex*: Option[GlyphIndex]
    lineIndex*: Option[TextLineIndex]
    containerIndex*: Option[TextContainerIndex]

  TextLayoutBackend* = ref object of DynamicAgent

  FigDrawTextTypesetter* = ref object of TextLayoutBackend

  TextLayoutRequest* = object
    storage*: TextStorage
    container*: TextContainer
    containers*: seq[TextContainer]
    style*: TextStyle
    alignment*: TextAlignment
    wraps*: bool
    invalidatedRanges*: seq[TextRange]
    invalidatedGlyphRanges*: seq[GlyphRange]
    invalidatedContainers*: seq[TextContainerIndex]
    invalidations*: seq[TextLayoutInvalidation]

  TextLayoutResult* = object
    snapshot*: TextLayoutSnapshot
    arrangement: GlyphArrangement
    fontRefs: seq[FontRef]

  TextLayoutManager* = ref object of DynamicAgent
    xTextStorage: TextStorage
    xTextContainer: TextContainer
    xTextContainers: seq[TextContainer]
    xTextStyle: TextStyle
    xAlignment: TextAlignment
    xBackend: TextLayoutBackend
    xClient: DynamicAgent
    xDelegate: DynamicAgent
    xLayout: GlyphArrangement
    xFontRefs: seq[FontRef]
    xLayoutRect: Rect
    xSnapshot: TextLayoutSnapshot
    xInvalidatedRanges: seq[TextRange]
    xInvalidatedGlyphRanges: seq[GlyphRange]
    xInvalidatedContainers: seq[TextContainerIndex]
    xInvalidations: seq[TextLayoutInvalidation]
    xTemporaryAttributes: seq[TextAttributeRun]
    xGlyphProperties: seq[TextGlyphPropertyRun]
    xUsesBackgroundLayout: bool
    xAllowsNonContiguousLayout: bool
    xHasNonContiguousLayout: bool
    xHasLayout: bool

proc `==`*(a, b: GlyphIndex): bool {.borrow.}
proc `$`*(index: GlyphIndex): string {.borrow.}
proc `==`*(a, b: TextLineIndex): bool {.borrow.}
proc `$`*(index: TextLineIndex): string {.borrow.}
proc `==`*(a, b: TextContainerIndex): bool {.borrow.}
proc `$`*(index: TextContainerIndex): string {.borrow.}

proc defaultUpdateLayout(manager: TextLayoutManager)
proc defaultInvalidateLayout(manager: TextLayoutManager, range: TextRange)
proc defaultInvalidateCharacters(manager: TextLayoutManager, range: TextRange)
proc defaultInvalidateGlyphs(manager: TextLayoutManager, range: GlyphRange)
proc defaultInvalidateDisplay(manager: TextLayoutManager, range: TextRange)
proc defaultInvalidateContainer(manager: TextLayoutManager, index: TextContainerIndex)
proc defaultHasValidLayout(manager: TextLayoutManager): bool
proc currentGlyphCount(manager: TextLayoutManager): int
proc defaultLineFragments(manager: TextLayoutManager): seq[TextLineFragment]
proc defaultLayoutSnapshot(manager: TextLayoutManager): TextLayoutSnapshot
proc defaultCaretRect(manager: TextLayoutManager, insertionPoint: int): Rect
proc defaultSelectionRects(manager: TextLayoutManager, range: TextRange): seq[Rect]
proc defaultTextIndexAtPoint(manager: TextLayoutManager, point: Point): int
proc snapshotFromCurrentLayout(manager: TextLayoutManager): TextLayoutSnapshot
proc buildFigDrawTextLayout(request: TextLayoutRequest): TextLayoutResult
proc updateLayout*(manager: TextLayoutManager)
proc textRangeForGlyphRange*(manager: TextLayoutManager, range: GlyphRange): TextRange

protocol TextLayoutEvents:
  proc layoutDidInvalidate*(
    manager: TextLayoutManager, ranges: seq[TextRange]
  ) {.signal.}

  proc textLayoutDidInvalidate*(
    manager: TextLayoutManager, invalidations: seq[TextLayoutInvalidation]
  ) {.signal.}

  proc containersDidChange*(
    manager: TextLayoutManager, containers: seq[TextContainer]
  ) {.signal.}

  proc containerDidInvalidate*(
    manager: TextLayoutManager, index: TextContainerIndex, container: TextContainer
  ) {.signal.}

  proc layoutDidComplete*(
    manager: TextLayoutManager, snapshot: TextLayoutSnapshot
  ) {.signal.}

  proc layoutGeometryDidChange*(
    manager: TextLayoutManager,
    oldUsedRect: Rect,
    oldContentSize: Size,
    snapshot: TextLayoutSnapshot,
  ) {.signal.}

protocol TextLayoutBackendProtocol {.selectorScope: protocol.} from TextLayoutBackend:
  method layoutText*(
      backend: TextLayoutBackend, request: TextLayoutRequest
  ): TextLayoutResult =
    discard backend
    discard request
    TextLayoutResult()

protocol FigDrawTextTypesetterProtocol of TextLayoutBackendProtocol:
  method layoutText*(
      typesetter: FigDrawTextTypesetter, request: TextLayoutRequest
  ): TextLayoutResult =
    discard typesetter
    buildFigDrawTextLayout(request)

protocol TextLayoutClientProtocol {.selectorScope: protocol.}:
  method textLayoutStorage*(manager: TextLayoutManager): TextStorage {.optional.}
  method textLayoutContainer*(manager: TextLayoutManager): TextContainer {.optional.}
  method textLayoutContainers*(
    manager: TextLayoutManager
  ): seq[TextContainer] {.optional.}

  method textLayoutStyle*(manager: TextLayoutManager): TextStyle {.optional.}
  method textLayoutAlignment*(manager: TextLayoutManager): TextAlignment {.optional.}

protocol TextLayoutDelegateProtocol:
  method shouldGenerateGlyphs*(
    manager: TextLayoutManager, range: TextRange
  ): bool {.optional.}

  method lineSpacingAfterGlyph*(
    manager: TextLayoutManager, glyphIndex: GlyphIndex
  ): float32 {.optional.}

  method paragraphSpacingBeforeGlyph*(
    manager: TextLayoutManager, glyphIndex: GlyphIndex
  ): float32 {.optional.}

  method paragraphSpacingAfterGlyph*(
    manager: TextLayoutManager, glyphIndex: GlyphIndex
  ): float32 {.optional.}

  method shouldHyphenateText*(
    manager: TextLayoutManager, range: TextRange, word: string
  ): bool {.optional.}

  method layoutDidFinish*(
    manager: TextLayoutManager, snapshot: TextLayoutSnapshot
  ) {.optional.}

  method tempAttributesForRange*(
    manager: TextLayoutManager, range: TextRange
  ): seq[TextAttributeRun] {.optional.}

protocol TextLayoutManagerProtocol {.selectorScope: protocol.} from TextLayoutManager:
  method lmUpdate*(manager: TextLayoutManager) =
    manager.defaultUpdateLayout()

  method lmInvalidate*(manager: TextLayoutManager, range: TextRange) =
    manager.defaultInvalidateLayout(range)

  method lmInvalidateChars*(manager: TextLayoutManager, range: TextRange) =
    manager.defaultInvalidateCharacters(range)

  method lmInvalidateGlyphs*(manager: TextLayoutManager, range: GlyphRange) =
    manager.defaultInvalidateGlyphs(range)

  method lmInvalidateDisplay*(manager: TextLayoutManager, range: TextRange) =
    manager.defaultInvalidateDisplay(range)

  method lmInvalidateContainer*(manager: TextLayoutManager, index: TextContainerIndex) =
    manager.defaultInvalidateContainer(index)

  method lmHasLayout*(manager: TextLayoutManager): bool =
    manager.defaultHasValidLayout()

  method lmLineFragments*(manager: TextLayoutManager): seq[TextLineFragment] =
    manager.defaultLineFragments()

  method lmSnapshot*(manager: TextLayoutManager): TextLayoutSnapshot =
    manager.defaultLayoutSnapshot()

  method lmCaretRect*(manager: TextLayoutManager, insertionPoint: int): Rect =
    manager.defaultCaretRect(insertionPoint)

  method lmSelectionRects*(manager: TextLayoutManager, range: TextRange): seq[Rect] =
    manager.defaultSelectionRects(range)

  method lmTextIndexAtPoint*(manager: TextLayoutManager, point: Point): int =
    manager.defaultTextIndexAtPoint(point)

protocol TextLayoutStorageEditingSlots of TextStorageEditingEvents:
  proc storageDidProcessEditing(
      manager: TextLayoutManager, edit: TextStorageEdit
  ) {.slot.} =
    if tseCharacters in edit.kinds:
      manager.defaultInvalidateCharacters(edit.range)
    else:
      manager.defaultInvalidateLayout(edit.range)

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

func initTextContainerIndex*(value: int): TextContainerIndex =
  TextContainerIndex(max(value, 0).Natural)

func toInt*(index: TextContainerIndex): int =
  system.int(Natural(index))

proc initTextContainer*(
    size = initSize(0.0, 0.0),
    insets = insets(0.0),
    wraps = false,
    origin = initPoint(0.0, 0.0),
    lineFragmentPadding = 0.0'f32,
    widthTracksTextView = false,
    heightTracksTextView = false,
    maximumNumberOfLines = 0,
    lineBreakMode = tlbmClipping,
    exclusionPaths: openArray[Rect] = [],
): TextContainer =
  TextContainer(
    origin: origin,
    size: size,
    insets: insets,
    lineFragmentPadding: max(lineFragmentPadding, 0.0'f32),
    widthTracksTextView: widthTracksTextView,
    heightTracksTextView: heightTracksTextView,
    maximumNumberOfLines: max(maximumNumberOfLines, 0).Natural,
    lineBreakMode:
      if wraps and lineBreakMode == tlbmClipping: tlbmWordWrapping else: lineBreakMode,
    wraps: wraps,
    exclusionPaths: @exclusionPaths,
  )

func frame*(container: TextContainer): Rect =
  rect(container.origin, container.size)

func layoutRect*(container: TextContainer): Rect =
  let
    rect = container.frame().inset(container.insets)
    padding = max(container.lineFragmentPadding, 0.0'f32)
  rect(
    rect.origin.x + padding,
    rect.origin.y,
    max(rect.size.width - padding * 2.0'f32, 0.0'f32),
    rect.size.height,
  )

func wrapsText*(container: TextContainer): bool =
  container.wraps or container.lineBreakMode in {tlbmWordWrapping, tlbmCharWrapping}

func effectiveLineFragmentRect*(container: TextContainer, proposed: Rect): Rect =
  result = proposed
  for exclusion in container.exclusionPaths:
    let hit = result.intersection(exclusion)
    if hit.isEmpty:
      discard
    elif hit.origin.x <= result.origin.x:
      let shift = min(hit.size.width, result.size.width)
      result.x += shift
      result.w = max(result.w - shift, 0.0'f32)
    elif hit.maxX >= result.maxX:
      result.w = max(hit.origin.x - result.origin.x, 0.0'f32)
    else:
      let
        leftWidth = max(hit.origin.x - result.origin.x, 0.0'f32)
        rightOrigin = hit.maxX
        rightWidth = max(result.maxX - rightOrigin, 0.0'f32)
      if rightWidth > leftWidth:
        result.x = rightOrigin
        result.w = rightWidth
      else:
        result.w = leftWidth

func effectiveContainers(
    primary: TextContainer, containers: openArray[TextContainer]
): seq[TextContainer] =
  if containers.len == 0:
    @[primary]
  else:
    @containers

proc effectiveContainers(manager: TextLayoutManager): seq[TextContainer] =
  effectiveContainers(manager.xTextContainer, manager.xTextContainers)

func effectiveContainers(request: TextLayoutRequest): seq[TextContainer] =
  effectiveContainers(request.container, request.containers)

func layoutRects(containers: openArray[TextContainer]): seq[Rect] =
  for container in containers:
    result.add container.layoutRect()

func unionRects(rects: openArray[Rect]): Rect =
  var hasRect = false
  for rect in rects:
    if not hasRect:
      result = rect
      hasRect = true
    elif not rect.isEmpty:
      result = result.union(rect)

func virtualLayoutRect(containers: openArray[TextContainer]): Rect =
  if containers.len == 0:
    return rect(0.0, 0.0, 0.0, 0.0)
  if containers.len == 1:
    return containers[0].layoutRect()

  var
    width = 0.0'f32
    height = 0.0'f32
  for container in containers:
    let rect = container.layoutRect()
    width = max(width, rect.size.width)
    height += max(rect.size.height, 0.0'f32)
  rect(0.0, 0.0, width, height)

func virtualContainerRect(containers: openArray[TextContainer], index: int): Rect =
  if containers.len == 0:
    return rect(0.0, 0.0, 0.0, 0.0)
  let clamped = max(0, min(index, containers.len - 1))
  if containers.len == 1:
    return containers[0].layoutRect()

  var y = 0.0'f32
  for containerIndex, container in containers:
    let rect = container.layoutRect()
    if containerIndex == clamped:
      return rect(0.0, y, rect.size.width, rect.size.height)
    y += max(rect.size.height, 0.0'f32)
  rect(0.0, y, 0.0, 0.0)

func containerIndexForVirtualY(
    containers: openArray[TextContainer], y: float32
): TextContainerIndex =
  if containers.len <= 1:
    return initTextContainerIndex(0)

  var top = 0.0'f32
  for index, container in containers:
    let height = max(container.layoutRect().size.height, 0.0'f32)
    if y >= top and y < top + height:
      return initTextContainerIndex(index)
    top += height
  if y < 0.0'f32:
    initTextContainerIndex(0)
  else:
    initTextContainerIndex(containers.len - 1)

func containerIndexForVirtualRect(
    containers: openArray[TextContainer], rect: Rect
): TextContainerIndex =
  containerIndexForVirtualY(containers, rect.origin.y + rect.size.height * 0.5'f32)

func actualRectForVirtualRect(containers: openArray[TextContainer], rect: Rect): Rect =
  if containers.len <= 1:
    return rect
  let
    index = containerIndexForVirtualRect(containers, rect).toInt
    virtualRect = containers.virtualContainerRect(index)
    actualRect = containers[index].layoutRect()
  rect(
    actualRect.origin.x + rect.origin.x - virtualRect.origin.x,
    actualRect.origin.y + rect.origin.y - virtualRect.origin.y,
    rect.size.width,
    rect.size.height,
  )

proc actualRectForVirtualRect(manager: TextLayoutManager, rect: Rect): Rect =
  manager.effectiveContainers().actualRectForVirtualRect(rect)

func nearestContainerIndexAtPoint(
    containers: openArray[TextContainer], point: Point
): int =
  if containers.len == 0:
    return 0
  var
    bestIndex = 0
    bestDistance = high(float32)
  for index, container in containers:
    let rect = container.layoutRect()
    if rect.contains(point):
      return index
    let
      dx =
        if point.x < rect.minX:
          rect.minX - point.x
        elif point.x > rect.maxX:
          point.x - rect.maxX
        else:
          0.0'f32
      dy =
        if point.y < rect.minY:
          rect.minY - point.y
        elif point.y > rect.maxY:
          point.y - rect.maxY
        else:
          0.0'f32
      distance = dx * dx + dy * dy
    if distance < bestDistance:
      bestDistance = distance
      bestIndex = index
  bestIndex

func virtualPointForActualPoint(
    containers: openArray[TextContainer], point: Point
): Point =
  if containers.len <= 1:
    return point
  let
    index = containers.nearestContainerIndexAtPoint(point)
    actualRect = containers[index].layoutRect()
    virtualRect = containers.virtualContainerRect(index)
  initPoint(
    virtualRect.origin.x + point.x - actualRect.origin.x,
    virtualRect.origin.y + point.y - actualRect.origin.y,
  )

proc localLayoutPoint(manager: TextLayoutManager, point: Point): Point =
  let virtualPoint = manager.effectiveContainers().virtualPointForActualPoint(point)
  initPoint(
    virtualPoint.x - manager.xLayoutRect.origin.x,
    virtualPoint.y - manager.xLayoutRect.origin.y,
  )

proc virtualCaretRect(manager: TextLayoutManager, insertionPoint: int): Rect =
  result = caretRect(manager.xLayoutRect, manager.xLayout, insertionPoint)
  if result.size.height <= 1.0'f32:
    let
      lineHeight = textNaturalSize("", manager.xTextStyle).height
      height =
        if manager.xLayoutRect.size.height > 0.0'f32:
          min(lineHeight, manager.xLayoutRect.size.height)
        else:
          lineHeight
    result = rect(result.origin, initSize(result.size.width, max(height, 1.0'f32)))

func anyContainerWraps(containers: openArray[TextContainer]): bool =
  for container in containers:
    if container.wrapsText:
      return true

func enforceLineLimits(
    fragments: seq[TextLineFragment], containers: openArray[TextContainer]
): seq[TextLineFragment] =
  if containers.len == 0:
    return fragments
  var counts = newSeq[int](containers.len)
  for fragment in fragments:
    let index = max(0, min(fragment.containerIndex.toInt, containers.len - 1))
    if containers[index].maximumNumberOfLines == 0 or
        counts[index] < int(containers[index].maximumNumberOfLines):
      result.add fragment
      inc counts[index]

proc newFigDrawTextTypesetter*(): FigDrawTextTypesetter =
  result = FigDrawTextTypesetter()
  discard result.withProto()
  discard result.withProtocol(FigDrawTextTypesetterProtocol)

proc fullTextRange(manager: TextLayoutManager): TextRange =
  initTextRange(0, if manager.xTextStorage.isNil: 0 else: manager.xTextStorage.len)

proc observeTextStorage(manager: TextLayoutManager, storage: TextStorage) =
  if not storage.isNil:
    manager.observeProtocol(storage, TextLayoutStorageEditingSlots)

proc unobserveTextStorage(manager: TextLayoutManager, storage: TextStorage) =
  if not storage.isNil:
    manager.unobserveProtocol(storage, TextLayoutStorageEditingSlots)

proc initTextLayoutManagerFields*(
    manager: TextLayoutManager,
    storage: TextStorage = nil,
    container = initTextContainer(),
    alignment = taLeft,
    style = initAppearance().resolveTextStyle(
        controlStyle(srTextView), color(0.08, 0.09, 0.11, 1.0), insets(0.0)
      ),
) =
  discard manager.withProto()
  discard manager.withProtocol(TextLayoutStorageEditingSlots)
  manager.xTextStorage = storage
  manager.xTextContainer = container
  manager.xTextStyle = style
  manager.xAlignment = alignment
  manager.xBackend = newFigDrawTextTypesetter()
  manager.observeTextStorage(storage)

proc newTextLayoutManager*(
    storage: TextStorage = nil,
    container = initTextContainer(),
    alignment = taLeft,
    style = initAppearance().resolveTextStyle(
        controlStyle(srTextView), color(0.08, 0.09, 0.11, 1.0), insets(0.0)
      ),
): TextLayoutManager =
  result = TextLayoutManager()
  initTextLayoutManagerFields(result, storage, container, alignment, style)

proc invalidateLayout*(manager: TextLayoutManager) =
  manager.lmInvalidate(manager.fullTextRange())

proc invalidateLayout*(manager: TextLayoutManager, range: TextRange) =
  manager.lmInvalidate(range)

proc hasValidLayout*(manager: TextLayoutManager): bool =
  manager.lmHasLayout()

proc textStorage*(manager: TextLayoutManager): TextStorage =
  manager.xTextStorage

proc `textStorage=`*(manager: TextLayoutManager, storage: TextStorage) =
  if manager.xTextStorage == storage:
    return
  manager.unobserveTextStorage(manager.xTextStorage)
  manager.xTextStorage = storage
  manager.observeTextStorage(storage)
  manager.invalidateLayout()

proc textContainer*(manager: TextLayoutManager): TextContainer =
  manager.xTextContainer

proc `textContainer=`*(manager: TextLayoutManager, container: TextContainer) =
  if manager.xTextContainers.len == 0 and manager.xTextContainer == container:
    return
  manager.xTextContainer = container
  manager.xTextContainers.setLen(0)
  emit manager.containersDidChange(manager.effectiveContainers())
  manager.invalidateLayout()

proc textContainers*(manager: TextLayoutManager): seq[TextContainer] =
  manager.effectiveContainers()

proc `textContainers=`*(manager: TextLayoutManager, containers: seq[TextContainer]) =
  let normalized =
    if containers.len == 0:
      @[initTextContainer()]
    else:
      containers
  if manager.effectiveContainers() == normalized:
    return
  manager.xTextContainer = normalized[0]
  manager.xTextContainers = normalized
  emit manager.containersDidChange(normalized)
  manager.invalidateLayout()

proc addTextContainer*(manager: TextLayoutManager, container: TextContainer) =
  var containers = manager.effectiveContainers()
  containers.add container
  manager.textContainers = containers

proc insertTextContainer*(
    manager: TextLayoutManager, index: int, container: TextContainer
) =
  var containers = manager.effectiveContainers()
  containers.insert(container, max(0, min(index, containers.len)))
  manager.textContainers = containers

proc replaceTextContainer*(
    manager: TextLayoutManager, index: TextContainerIndex, container: TextContainer
) =
  var containers = manager.effectiveContainers()
  let position = index.toInt
  if position < 0 or position >= containers.len:
    return
  if containers[position] == container:
    return
  containers[position] = container
  manager.textContainers = containers
  manager.lmInvalidateContainer(index)

proc removeTextContainer*(manager: TextLayoutManager, index: TextContainerIndex) =
  var containers = manager.effectiveContainers()
  let position = index.toInt
  if position < 0 or position >= containers.len:
    return
  containers.delete(position)
  manager.textContainers = containers

proc invalidateTextContainer*(manager: TextLayoutManager, index: TextContainerIndex) =
  manager.lmInvalidateContainer(index)

proc textStyle*(manager: TextLayoutManager): TextStyle =
  manager.xTextStyle

proc `textStyle=`*(manager: TextLayoutManager, style: TextStyle) =
  if manager.xTextStyle == style:
    return
  manager.xTextStyle = style
  manager.invalidateLayout()

proc alignment*(manager: TextLayoutManager): TextAlignment =
  manager.xAlignment

proc `alignment=`*(manager: TextLayoutManager, alignment: TextAlignment) =
  if manager.xAlignment == alignment:
    return
  manager.xAlignment = alignment
  manager.invalidateLayout()

proc textLayoutBackend*(manager: TextLayoutManager): TextLayoutBackend =
  manager.xBackend

proc `textLayoutBackend=`*(manager: TextLayoutManager, backend: TextLayoutBackend) =
  manager.xBackend = backend
  manager.invalidateLayout()

proc layoutClient*(manager: TextLayoutManager): DynamicAgent =
  manager.xClient

proc `layoutClient=`*(manager: TextLayoutManager, client: DynamicAgent) =
  if manager.xClient == client:
    return
  manager.xClient = client
  manager.invalidateLayout()

proc delegate*(manager: TextLayoutManager): DynamicAgent =
  manager.xDelegate

proc `delegate=`*(manager: TextLayoutManager, delegate: DynamicAgent) =
  manager.xDelegate = delegate

proc usesBackgroundLayout*(manager: TextLayoutManager): bool =
  manager.xUsesBackgroundLayout

proc `usesBackgroundLayout=`*(manager: TextLayoutManager, value: bool) =
  manager.xUsesBackgroundLayout = value

proc allowsNonContiguousLayout*(manager: TextLayoutManager): bool =
  manager.xAllowsNonContiguousLayout

proc `allowsNonContiguousLayout=`*(manager: TextLayoutManager, value: bool) =
  if manager.xAllowsNonContiguousLayout == value:
    return
  manager.xAllowsNonContiguousLayout = value
  manager.xHasNonContiguousLayout = false

proc hasNonContiguousLayout*(manager: TextLayoutManager): bool =
  manager.xHasNonContiguousLayout

proc recordInvalidation(
    manager: TextLayoutManager, invalidation: TextLayoutInvalidation
) =
  manager.xInvalidations.add invalidation
  emit manager.textLayoutDidInvalidate(manager.xInvalidations)

proc invalidateCharacters*(manager: TextLayoutManager, range: TextRange) =
  manager.lmInvalidateChars(range)

proc invalidateGlyphs*(manager: TextLayoutManager, range: GlyphRange) =
  manager.lmInvalidateGlyphs(range)

proc invalidateDisplay*(manager: TextLayoutManager, range: TextRange) =
  manager.lmInvalidateDisplay(range)

proc invalidateDisplayForGlyphRange*(manager: TextLayoutManager, range: GlyphRange) =
  manager.invalidateDisplay(manager.textRangeForGlyphRange(range))

proc updateLayoutForTextRange*(manager: TextLayoutManager, range: TextRange) =
  discard range
  manager.updateLayout()

proc updateLayoutForGlyphRange*(manager: TextLayoutManager, range: GlyphRange) =
  discard range
  manager.updateLayout()

proc updateLayoutForContainer*(manager: TextLayoutManager, index: TextContainerIndex) =
  discard index
  manager.updateLayout()

proc requestBackgroundLayout*(manager: TextLayoutManager) =
  if not manager.xUsesBackgroundLayout:
    return
  manager.updateLayout()

func clampTextRange(total: int, range: TextRange): TextRange =
  let
    start = max(0, min(int(range.location), total))
    length = max(0, min(int(range.length), total - start))
  initTextRange(start, length)

func sourceSlice(range: TextRange): Slice[int] =
  if range.length == 0:
    return 0 .. -1
  int(range.location) .. range.maxIndex - 1

func toContainerRect(rect: auto, layoutRect: Rect): Rect =
  rect(layoutRect.origin.x + rect.x, layoutRect.origin.y + rect.y, rect.w, rect.h)

func toTextRange(source: GlyphSourceRange): TextRange =
  initTextRange(source.runeStart, max(source.runeEnd - source.runeStart, 0))

func sourceRangeForGlyph(layout: GlyphArrangement, glyphIndex: int): TextRange =
  layout.glyphSourceRange(glyphIndex).toTextRange()

func textRangeForGlyphLine(layout: GlyphArrangement, line: Slice[int]): TextRange =
  if line.a > line.b:
    return initTextRange(0, 0)
  var
    found = false
    start = high(int)
    stop = 0
  for glyphIndex in line:
    let source = layout.sourceRangeForGlyph(glyphIndex)
    if source.length > 0:
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

func glyphRangeIntersects(a, b: GlyphRange): bool =
  a.location.toInt < b.maxIndex and b.location.toInt < a.maxIndex

func clampedGlyphRange(total: int, range: GlyphRange): GlyphRange =
  let
    start = max(0, min(range.location.toInt, total))
    length = max(0, min(int(range.length), total - start))
  initGlyphRange(start, length)

func invalidationForText(
    kind: TextLayoutInvalidationKind, range: TextRange
): TextLayoutInvalidation =
  TextLayoutInvalidation(
    kind: kind,
    textRange: range,
    glyphRange: initGlyphRange(0, 0),
    containerIndex: none(TextContainerIndex),
  )

func invalidationForGlyphs(
    kind: TextLayoutInvalidationKind, range: GlyphRange, textRange: TextRange
): TextLayoutInvalidation =
  TextLayoutInvalidation(
    kind: kind,
    textRange: textRange,
    glyphRange: range,
    containerIndex: none(TextContainerIndex),
  )

func invalidationForContainer(index: TextContainerIndex): TextLayoutInvalidation =
  TextLayoutInvalidation(
    kind: tlikContainer,
    textRange: initTextRange(0, 0),
    glyphRange: initGlyphRange(0, 0),
    containerIndex: some(index),
  )

proc sortedTemporaryRuns(runs: seq[TextAttributeRun]): seq[TextAttributeRun] =
  result = runs
  result.sort(
    proc(a, b: TextAttributeRun): int =
      cmp(int(a.range.location), int(b.range.location))
  )

proc sortedGlyphPropertyRuns(
    runs: seq[TextGlyphPropertyRun]
): seq[TextGlyphPropertyRun] =
  result = runs
  result.sort(
    proc(a, b: TextGlyphPropertyRun): int =
      cmp(a.range.location.toInt, b.range.location.toInt)
  )

func toTextCaretPositionKind(affinity: TextCaretAffinity): TextCaretPositionKind =
  case affinity
  of CaretLeading: tcpLeading
  of CaretInside: tcpInside
  of CaretTrailing: tcpTrailing

proc applyClientInputs(manager: TextLayoutManager) =
  if manager.xClient.isNil:
    return
  let storage = manager.xClient.trySendLocal(textLayoutStorage(), manager)
  if storage.isSome and storage.get() != manager.xTextStorage:
    manager.unobserveTextStorage(manager.xTextStorage)
    manager.xTextStorage = storage.get()
    manager.observeTextStorage(manager.xTextStorage)
    manager.xHasLayout = false

  let containers = manager.xClient.trySendLocal(textLayoutContainers(), manager)
  if containers.isSome and containers.get().len > 0:
    let supplied = containers.get()
    if supplied != manager.effectiveContainers():
      manager.xTextContainer = supplied[0]
      manager.xTextContainers = supplied
      manager.xHasLayout = false
  else:
    let container = manager.xClient.trySendLocal(textLayoutContainer(), manager)
    if container.isSome and
        (manager.xTextContainers.len > 0 or container.get() != manager.xTextContainer):
      manager.xTextContainer = container.get()
      manager.xTextContainers.setLen(0)
      manager.xHasLayout = false

  let style = manager.xClient.trySendLocal(textLayoutStyle(), manager)
  if style.isSome and style.get() != manager.xTextStyle:
    manager.xTextStyle = style.get()
    manager.xHasLayout = false
  let alignment = manager.xClient.trySendLocal(textLayoutAlignment(), manager)
  if alignment.isSome and alignment.get() != manager.xAlignment:
    manager.xAlignment = alignment.get()
    manager.xHasLayout = false

proc layoutRequest(manager: TextLayoutManager): TextLayoutRequest =
  let containers = manager.effectiveContainers()
  TextLayoutRequest(
    storage: manager.xTextStorage,
    container: containers[0],
    containers: containers,
    style: manager.xTextStyle,
    alignment: manager.xAlignment,
    wraps: containers.anyContainerWraps(),
    invalidatedRanges: manager.xInvalidatedRanges,
    invalidatedGlyphRanges: manager.xInvalidatedGlyphRanges,
    invalidatedContainers: manager.xInvalidatedContainers,
    invalidations: manager.xInvalidations,
  )

proc defaultInvalidateLayout(manager: TextLayoutManager, range: TextRange) =
  manager.xInvalidatedRanges.add range
  manager.recordInvalidation(invalidationForText(tlikLayout, range))
  manager.xHasLayout = false
  emit manager.layoutDidInvalidate(manager.xInvalidatedRanges)

proc defaultInvalidateCharacters(manager: TextLayoutManager, range: TextRange) =
  manager.xInvalidatedRanges.add range
  manager.recordInvalidation(invalidationForText(tlikCharacters, range))
  manager.xHasLayout = false
  emit manager.layoutDidInvalidate(manager.xInvalidatedRanges)

proc defaultInvalidateGlyphs(manager: TextLayoutManager, range: GlyphRange) =
  manager.updateLayout()
  let clamped = clampedGlyphRange(manager.currentGlyphCount(), range)
  manager.xInvalidatedGlyphRanges.add clamped
  manager.recordInvalidation(
    invalidationForGlyphs(tlikGlyphs, clamped, manager.textRangeForGlyphRange(clamped))
  )
  manager.xHasLayout = false
  emit manager.layoutDidInvalidate(manager.xInvalidatedRanges)

proc defaultInvalidateDisplay(manager: TextLayoutManager, range: TextRange) =
  manager.recordInvalidation(invalidationForText(tlikDisplay, range))

proc defaultInvalidateContainer(manager: TextLayoutManager, index: TextContainerIndex) =
  let containers = manager.effectiveContainers()
  if containers.len == 0:
    return
  let position = max(0, min(index.toInt, containers.len - 1))
  let clamped = initTextContainerIndex(position)
  manager.xInvalidatedContainers.add clamped
  manager.recordInvalidation(invalidationForContainer(clamped))
  manager.xHasLayout = false
  emit manager.containerDidInvalidate(clamped, containers[position])

proc defaultHasValidLayout(manager: TextLayoutManager): bool =
  manager.xHasLayout

proc currentGlyphCount(manager: TextLayoutManager): int =
  max(manager.xLayout.glyphCount(), int(manager.xSnapshot.glyphCount))

proc delegateAllowsGlyphGeneration(manager: TextLayoutManager, range: TextRange): bool =
  if manager.xDelegate.isNil:
    return true

  manager.xDelegate
  .trySendLocal(shouldGenerateGlyphs(), (manager: manager, range: range))
  .get(true)

proc delegateLineSpacing(manager: TextLayoutManager, glyphIndex: GlyphIndex): float32 =
  if manager.xDelegate.isNil:
    return 0.0'f32
  max(
    manager.xDelegate
    .trySendLocal(lineSpacingAfterGlyph(), (manager: manager, glyphIndex: glyphIndex))
    .get(0.0'f32),
    0.0'f32,
  )

proc delegateParagraphSpacingBefore(
    manager: TextLayoutManager, glyphIndex: GlyphIndex
): float32 =
  if manager.xDelegate.isNil:
    return 0.0'f32
  max(
    manager.xDelegate
    .trySendLocal(
      paragraphSpacingBeforeGlyph(), (manager: manager, glyphIndex: glyphIndex)
    )
    .get(0.0'f32),
    0.0'f32,
  )

proc delegateParagraphSpacingAfter(
    manager: TextLayoutManager, glyphIndex: GlyphIndex
): float32 =
  if manager.xDelegate.isNil:
    return 0.0'f32
  max(
    manager.xDelegate
    .trySendLocal(
      paragraphSpacingAfterGlyph(), (manager: manager, glyphIndex: glyphIndex)
    )
    .get(0.0'f32),
    0.0'f32,
  )

proc dispatchLayoutDidFinish(manager: TextLayoutManager, snapshot: TextLayoutSnapshot) =
  if not manager.xDelegate.isNil:
    discard manager.xDelegate.trySendLocal(
      layoutDidFinish(), (manager: manager, snapshot: snapshot)
    )

proc shouldHyphenate*(manager: TextLayoutManager, range: TextRange, word = ""): bool =
  if manager.xDelegate.isNil:
    return false

  manager.xDelegate
  .trySendLocal(shouldHyphenateText(), (manager: manager, range: range, word: word))
  .get(false)

proc defaultUpdateLayout(manager: TextLayoutManager) =
  manager.applyClientInputs()
  if manager.xHasLayout:
    return
  if manager.xBackend.isNil:
    manager.xBackend = newFigDrawTextTypesetter()

  let
    request = manager.layoutRequest()
    oldSnapshot = manager.xSnapshot
    oldUsedRect = oldSnapshot.usedRect
    oldContentSize = oldSnapshot.contentSize
    layout = manager.xBackend.layoutText(request)
  manager.xFontRefs = layout.fontRefs
  manager.xLayout = layout.arrangement
  manager.xLayoutRect = request.effectiveContainers().virtualLayoutRect()
  manager.xSnapshot = layout.snapshot
  manager.xHasLayout = true
  manager.xInvalidatedRanges.setLen(0)
  manager.xInvalidatedGlyphRanges.setLen(0)
  manager.xInvalidatedContainers.setLen(0)
  manager.xInvalidations.setLen(0)
  manager.xHasNonContiguousLayout = false

  emit manager.layoutDidComplete(manager.xSnapshot)
  manager.dispatchLayoutDidFinish(manager.xSnapshot)
  if oldUsedRect != manager.xSnapshot.usedRect or
      oldContentSize != manager.xSnapshot.contentSize:
    emit manager.layoutGeometryDidChange(oldUsedRect, oldContentSize, manager.xSnapshot)

proc updateLayout*(manager: TextLayoutManager) =
  manager.lmUpdate()

proc buildFigDrawTextLayout(request: TextLayoutRequest): TextLayoutResult =
  let
    containers = request.effectiveContainers()
    rect = containers.virtualLayoutRect()
    wraps = request.wraps or containers.anyContainerWraps()
  result.arrangement =
    textLayout(rect, request.storage, request.style, request.alignment, wraps)
  var retainedFontIds = initHashSet[FontId]()
  for glyphFont in result.arrangement.fonts:
    if glyphFont.fontId notin retainedFontIds:
      retainedFontIds.incl glyphFont.fontId
      result.fontRefs.add(fontRef(getFigFont(glyphFont.fontId)))
  let manager = TextLayoutManager(
    xTextStorage: request.storage,
    xTextContainer: containers[0],
    xTextContainers: containers,
    xTextStyle: request.style,
    xAlignment: request.alignment,
    xLayout: result.arrangement,
    xFontRefs: result.fontRefs,
    xLayoutRect: rect,
    xHasLayout: true,
  )
  result.snapshot = manager.snapshotFromCurrentLayout()

proc glyphArrangement*(manager: TextLayoutManager): GlyphArrangement =
  manager.updateLayout()
  manager.xLayout

proc retainedFontCount*(manager: TextLayoutManager): Natural =
  manager.updateLayout()
  manager.xFontRefs.len.Natural

proc layoutBounds*(manager: TextLayoutManager): Rect =
  manager.updateLayout()
  manager.xSnapshot.containerRect

proc glyphCount*(manager: TextLayoutManager): Natural =
  manager.updateLayout()
  manager.currentGlyphCount().Natural

proc lineFragment(
    manager: TextLayoutManager, visualIndex: int, line: Slice[int], lineCount: int
): TextLineFragment =
  let
    containers = manager.effectiveContainers()
    layout = manager.xLayout
    glyphRange = initGlyphRange(line.a, line.b - line.a + 1)
    sourceRunes =
      if manager.xTextStorage.isNil:
        @[]
      else:
        manager.xTextStorage.stringValue().toRunes()
  var textRange = layout.textRangeForGlyphLine(line)
  if textRange.maxIndex < sourceRunes.len and
      sourceRunes[textRange.maxIndex] in [Rune('\n'), Rune('\r')]:
    inc textRange.length
  let hardBreak = containsHardBreak(sourceRunes, textRange)

  var
    virtualUsedRect = rect(0.0, 0.0, 0.0, 0.0)
    hasUsedRect = false
    lineHeight = 0.0'f32
    baselineOffset = 0.0'f32

  for glyphIndex in line:
    let
      glyphBounds = layout.glyphRect(glyphIndex).toContainerRect(manager.xLayoutRect)
      font = layout.glyphFont(glyphIndex)
    if not glyphBounds.isEmpty:
      if hasUsedRect:
        virtualUsedRect = virtualUsedRect.union(glyphBounds)
      else:
        virtualUsedRect = glyphBounds
        hasUsedRect = true
    lineHeight = max(lineHeight, max(font.lineHeight, virtualUsedRect.size.height))
    baselineOffset = max(baselineOffset, font.descentAdj)

  if lineHeight <= 0.0'f32:
    lineHeight = defaultFontSize()
  if baselineOffset <= 0.0'f32:
    baselineOffset = min(lineHeight, lineHeight * 0.8'f32)

  let
    lineTop =
      if hasUsedRect: virtualUsedRect.origin.y else: manager.xLayoutRect.origin.y
    containerIndex = containers.containerIndexForVirtualY(lineTop)
    container = containers[containerIndex.toInt]
    virtualContainer = containers.virtualContainerRect(containerIndex.toInt)
    virtualFragmentRect = rect(
      virtualContainer.origin.x,
      lineTop,
      virtualContainer.size.width,
      max(lineHeight, virtualUsedRect.size.height),
    )
    fragmentRect = manager.actualRectForVirtualRect(virtualFragmentRect)
    usedRect =
      if hasUsedRect:
        manager.actualRectForVirtualRect(virtualUsedRect)
      else:
        rect(fragmentRect.origin, initSize(0.0, fragmentRect.size.height))
    wrapped = container.wrapsText and not hardBreak and visualIndex < lineCount - 1
  let
    ascent = min(max(baselineOffset, 0.0'f32), fragmentRect.size.height)
    leading =
      manager.delegateLineSpacing(glyphRange.location) +
      manager.delegateParagraphSpacingBefore(glyphRange.location) +
      manager.delegateParagraphSpacingAfter(glyphRange.location)

  TextLineFragment(
    lineIndex: initTextLineIndex(visualIndex),
    containerIndex: containerIndex,
    glyphRange: glyphRange,
    textRange: textRange,
    fragmentRect: fragmentRect,
    usedRect: usedRect,
    baseline: fragmentRect.origin.y + ascent,
    ascent: ascent,
    descent: max(fragmentRect.size.height - ascent, 0.0'f32),
    leading: leading,
    hardBreak: hardBreak,
    wrapped: wrapped,
  )

proc emptyLineFragment(
    manager: TextLayoutManager, visualIndex: int, sourceIndex: int
): TextLineFragment =
  let
    containers = manager.effectiveContainers()
    sourceRunes =
      if manager.xTextStorage.isNil:
        @[]
      else:
        manager.xTextStorage.stringValue().toRunes()
    hardBreak =
      sourceIndex < sourceRunes.len and
      sourceRunes[sourceIndex] in [Rune('\n'), Rune('\r')]
    caret = manager.virtualCaretRect(sourceIndex)
    lineHeight = max(caret.size.height, defaultFontSize())
    containerIndex = containers.containerIndexForVirtualY(caret.origin.y)
    virtualContainer = containers.virtualContainerRect(containerIndex.toInt)
    virtualFragmentRect = rect(
      virtualContainer.origin.x, caret.origin.y, virtualContainer.size.width, lineHeight
    )
    fragmentRect = manager.actualRectForVirtualRect(virtualFragmentRect)
  let
    glyphIndex = initGlyphIndex(0)
    ascent = min(lineHeight, lineHeight * 0.8'f32)
    leading =
      manager.delegateLineSpacing(glyphIndex) +
      manager.delegateParagraphSpacingBefore(glyphIndex) +
      manager.delegateParagraphSpacingAfter(glyphIndex)
  TextLineFragment(
    lineIndex: initTextLineIndex(visualIndex),
    containerIndex: containerIndex,
    glyphRange: initGlyphRange(0, 0),
    textRange: initTextRange(sourceIndex, if hardBreak: 1 else: 0),
    fragmentRect: fragmentRect,
    usedRect: rect(fragmentRect.origin, initSize(0.0, lineHeight)),
    baseline: fragmentRect.origin.y + ascent,
    ascent: ascent,
    descent: max(lineHeight - ascent, 0.0'f32),
    leading: leading,
    hardBreak: hardBreak,
  )

func startsAtTextIndex(fragments: openArray[TextLineFragment], index: int): bool =
  for fragment in fragments:
    if int(fragment.textRange.location) == index:
      return true

proc reindexLineFragments(fragments: var seq[TextLineFragment]) =
  fragments.sort(
    proc(a, b: TextLineFragment): int =
      result = cmp(a.containerIndex.toInt, b.containerIndex.toInt)
      if result == 0:
        result = cmp(a.fragmentRect.origin.y, b.fragmentRect.origin.y)
      if result == 0:
        result = cmp(a.fragmentRect.origin.x, b.fragmentRect.origin.x)
  )
  for index in 0 ..< fragments.len:
    fragments[index].lineIndex = initTextLineIndex(index)

proc defaultLineFragments(manager: TextLayoutManager): seq[TextLineFragment] =
  if not manager.xHasLayout:
    manager.updateLayout()

  let count = manager.xLayout.glyphCount()
  if count == 0:
    result.add manager.emptyLineFragment(0, 0)
    result = result.enforceLineLimits(manager.effectiveContainers())
    return

  let lines = manager.xLayout.lineGlyphRanges()

  for visualIndex, rawLine in lines:
    if rawLine.a <= rawLine.b:
      result.add manager.lineFragment(visualIndex, rawLine, lines.len)

  if not manager.xTextStorage.isNil:
    var index = 0
    for rune in manager.xTextStorage.stringValue().runes:
      if rune == Rune('\n'):
        let nextIndex = index + 1
        if not result.startsAtTextIndex(nextIndex):
          result.add manager.emptyLineFragment(result.len, nextIndex)
      inc index
  result = result.enforceLineLimits(manager.effectiveContainers())
  result.reindexLineFragments()

proc lineFragments*(manager: TextLayoutManager): seq[TextLineFragment] =
  manager.lmLineFragments()

iterator lineFragmentItems*(manager: TextLayoutManager): TextLineFragment =
  for fragment in manager.lineFragments():
    yield fragment

proc lineCount*(manager: TextLayoutManager): Natural =
  manager.lineFragments().len.Natural

proc snapshotFromCurrentLayout(manager: TextLayoutManager): TextLayoutSnapshot =
  result.textHash =
    if manager.xTextStorage.isNil:
      hash("")
    else:
      hash(manager.xTextStorage.stringValue())
  let containers = manager.effectiveContainers()
  result.layoutHash = manager.xLayout.contentHash
  result.containers = containers
  result.containerRects = containers.layoutRects()
  result.containerRect = result.containerRects.unionRects()
  result.glyphCount = manager.xLayout.glyphCount().Natural
  result.lineFragments = manager.defaultLineFragments()

  var hasUsedRect = false
  for fragment in result.lineFragments:
    if not fragment.usedRect.isEmpty:
      if hasUsedRect:
        result.usedRect = result.usedRect.union(fragment.usedRect)
      else:
        result.usedRect = fragment.usedRect
        hasUsedRect = true

  if not hasUsedRect:
    result.usedRect = rect(result.containerRect.origin, initSize(0.0, 0.0))

  let layoutContentSize = manager.xLayout.layoutContentSize()
  var
    contentWidth = layoutContentSize.x
    contentHeight = layoutContentSize.y
  if hasUsedRect:
    contentWidth = max(contentWidth, result.usedRect.size.width)
    contentHeight =
      max(contentHeight, result.usedRect.maxY - result.containerRect.origin.y)
  if result.lineFragments.len > 0:
    contentHeight = max(
      contentHeight,
      result.lineFragments[^1].fragmentRect.maxY - result.containerRect.origin.y,
    )
  result.contentSize = initSize(max(contentWidth, 0.0'f32), max(contentHeight, 0.0'f32))

proc defaultLayoutSnapshot(manager: TextLayoutManager): TextLayoutSnapshot =
  manager.updateLayout()
  manager.xSnapshot

proc layoutSnapshot*(manager: TextLayoutManager): TextLayoutSnapshot =
  manager.lmSnapshot()

proc usedRect*(manager: TextLayoutManager): Rect =
  manager.layoutSnapshot().usedRect

proc contentSize*(manager: TextLayoutManager): Size =
  manager.layoutSnapshot().contentSize

proc emptyGlyphRangeForTextIndex(
    manager: TextLayoutManager, sourceIndex, count: int
): GlyphRange =
  if sourceIndex <= 0:
    return initGlyphRange(0, 0)
  if sourceIndex >= manager.xLayout.sourceRuneCount():
    return initGlyphRange(count, 0)

  for glyphIndex in 0 ..< count:
    let source = manager.xLayout.sourceRangeForGlyph(glyphIndex)
    if sourceIndex <= source.maxIndex:
      return initGlyphRange(glyphIndex, 0)
  initGlyphRange(count, 0)

proc glyphRangeForTextRange*(manager: TextLayoutManager, range: TextRange): GlyphRange =
  manager.updateLayout()
  let
    count = manager.xLayout.glyphCount()
    clamped = clampTextRange(manager.xLayout.sourceRuneCount(), range)
  if clamped.length == 0 or count == 0:
    return manager.emptyGlyphRangeForTextIndex(int(clamped.location), count)

  let glyphRange = manager.xLayout.glyphRangeFor(clamped.sourceSlice)
  if glyphRange.a > glyphRange.b:
    return initGlyphRange(0, 0)
  initGlyphRange(glyphRange.a, glyphRange.b - glyphRange.a + 1)

proc textRangeForGlyphRange*(manager: TextLayoutManager, range: GlyphRange): TextRange =
  manager.updateLayout()
  let
    count = manager.xLayout.glyphCount()
    start = max(0, min(range.location.toInt, count))
    stop = max(start, min(range.maxIndex, count))
  if range.length == 0:
    if start >= count:
      return initTextRange(manager.xLayout.sourceRuneCount(), 0)
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
  manager.updateLayout()
  let localPoint = manager.localLayoutPoint(point)
  let glyphIndex = manager.xLayout.glyphIndexAt(vec2(localPoint.x, localPoint.y))
  if glyphIndex < 0:
    none(GlyphIndex)
  else:
    some(initGlyphIndex(glyphIndex))

proc textIndexAtPoint*(manager: TextLayoutManager, point: Point): int

proc textRangeAtPoint*(manager: TextLayoutManager, point: Point): TextRange =
  manager.updateLayout()
  let localPoint = manager.localLayoutPoint(point)
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

proc defaultGlyphProperties(
    manager: TextLayoutManager, textRange: TextRange
): GlyphProperties =
  if textRange.length == 0:
    return {gpNull}
  if manager.xTextStorage.isNil:
    return

  let
    text = manager.xTextStorage.stringValue().toRunes()
    index = int(textRange.location)
  if index < 0 or index >= text.len:
    return {gpNull}
  case text[index]
  of Rune('\n'), Rune('\r'), Rune('\t'):
    result.incl gpControl
  of Rune(' '):
    result.incl gpElastic
  else:
    discard

  if manager.xTextStorage.attributesAt(index).hasAttachment:
    result.incl gpAttachment

proc glyphProperties*(manager: TextLayoutManager, index: GlyphIndex): GlyphProperties =
  let range = initGlyphRange(index.toInt, 1)
  for run in manager.xGlyphProperties:
    if run.range.glyphRangeIntersects(range):
      return run.properties
  manager.defaultGlyphProperties(manager.textRangeForGlyphRange(range))

proc setGlyphProperties*(
    manager: TextLayoutManager, range: GlyphRange, properties: GlyphProperties
) =
  let clamped = clampedGlyphRange(int(manager.glyphCount()), range)
  if clamped.length == 0:
    return

  var nextRuns: seq[TextGlyphPropertyRun]
  for run in manager.xGlyphProperties:
    if not run.range.glyphRangeIntersects(clamped):
      nextRuns.add run
    else:
      let
        runStart = run.range.location.toInt
        runStop = run.range.maxIndex
        start = clamped.location.toInt
        stop = clamped.maxIndex
      if runStart < start:
        nextRuns.add TextGlyphPropertyRun(
          range: initGlyphRange(runStart, start - runStart), properties: run.properties
        )
      if runStop > stop:
        nextRuns.add TextGlyphPropertyRun(
          range: initGlyphRange(stop, runStop - stop), properties: run.properties
        )
  nextRuns.add TextGlyphPropertyRun(range: clamped, properties: properties)
  manager.xGlyphProperties = nextRuns.sortedGlyphPropertyRuns()
  manager.invalidateGlyphs(clamped)

proc removeGlyphProperties*(manager: TextLayoutManager, range: GlyphRange) =
  let clamped = clampedGlyphRange(int(manager.glyphCount()), range)
  if clamped.length == 0:
    return

  var nextRuns: seq[TextGlyphPropertyRun]
  for run in manager.xGlyphProperties:
    if not run.range.glyphRangeIntersects(clamped):
      nextRuns.add run
    else:
      let
        runStart = run.range.location.toInt
        runStop = run.range.maxIndex
        start = clamped.location.toInt
        stop = clamped.maxIndex
      if runStart < start:
        nextRuns.add TextGlyphPropertyRun(
          range: initGlyphRange(runStart, start - runStart), properties: run.properties
        )
      if runStop > stop:
        nextRuns.add TextGlyphPropertyRun(
          range: initGlyphRange(stop, runStop - stop), properties: run.properties
        )
  manager.xGlyphProperties = nextRuns.sortedGlyphPropertyRuns()
  manager.invalidateGlyphs(clamped)

proc glyphPropertyRuns*(manager: TextLayoutManager): seq[TextGlyphPropertyRun] =
  manager.xGlyphProperties

proc glyphIndexForTextIndex*(
    manager: TextLayoutManager, index: TextIndex
): Option[GlyphIndex] =
  let range = manager.glyphRangeForTextRange(initTextRange(index.toInt, 1))
  if range.length == 0:
    none(GlyphIndex)
  else:
    some(range.location)

proc glyphIndexForTextIndex*(
    manager: TextLayoutManager, index: int
): Option[GlyphIndex] =
  if index < 0:
    none(GlyphIndex)
  else:
    manager.glyphIndexForTextIndex(initTextIndex(index))

proc textIndexForGlyphIndex*(manager: TextLayoutManager, index: GlyphIndex): TextIndex =
  initTextIndex(
    int(manager.textRangeForGlyphRange(initGlyphRange(index.toInt, 1)).location)
  )

proc textIndexForGlyphIndex*(manager: TextLayoutManager, index: int): TextIndex =
  manager.textIndexForGlyphIndex(initGlyphIndex(index))

proc glyphInfo*(manager: TextLayoutManager, index: GlyphIndex): Option[TextGlyph] =
  manager.updateLayout()
  let
    glyphIndex = index.toInt
    count = manager.xLayout.glyphCount()
  if glyphIndex < 0 or glyphIndex >= count:
    return none(TextGlyph)
  let
    textRange = manager.textRangeForGlyphRange(initGlyphRange(glyphIndex, 1))
    fragment = manager.lineFragmentForGlyphIndex(index)
  result = some(
    TextGlyph(
      index: index,
      textRange: textRange,
      properties: manager.glyphProperties(index),
      bounds: manager.actualRectForVirtualRect(
        manager.xLayout.glyphRect(glyphIndex).toContainerRect(manager.xLayoutRect)
      ),
      lineIndex:
        if fragment.isSome:
          fragment.get().lineIndex
        else:
          initTextLineIndex(0),
      containerIndex:
        if fragment.isSome:
          fragment.get().containerIndex
        else:
          initTextContainerIndex(0),
    )
  )

proc glyphInfo*(manager: TextLayoutManager, index: int): Option[TextGlyph] =
  if index < 0:
    none(TextGlyph)
  else:
    manager.glyphInfo(initGlyphIndex(index))

proc generatedGlyphsForTextRange*(
    manager: TextLayoutManager, range: TextRange
): seq[TextGlyph] =
  manager.updateLayout()
  let
    clamped = clampTextRange(manager.xLayout.sourceRuneCount(), range)
    glyphRange = manager.glyphRangeForTextRange(clamped)
  if not manager.delegateAllowsGlyphGeneration(clamped):
    return
  for glyphIndex in glyphRange.location.toInt ..< glyphRange.maxIndex:
    let glyph = manager.glyphInfo(glyphIndex)
    if glyph.isSome:
      result.add glyph.get()

proc glyphsForTextRange*(manager: TextLayoutManager, range: TextRange): seq[TextGlyph] =
  manager.generatedGlyphsForTextRange(range)

proc lineFragmentsForTextRange*(
    manager: TextLayoutManager, range: TextRange
): seq[TextLineFragment] =
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

proc defaultCaretRect(manager: TextLayoutManager, insertionPoint: int): Rect =
  manager.updateLayout()
  manager.actualRectForVirtualRect(manager.virtualCaretRect(insertionPoint))

proc caretRect*(manager: TextLayoutManager, insertionPoint: int): Rect =
  manager.lmCaretRect(insertionPoint)

proc caretPositions*(
    manager: TextLayoutManager, insertionPoint: int
): seq[TextCaretPosition] =
  manager.updateLayout()
  let
    sourceCount = manager.xLayout.sourceRuneCount()
    index = max(0, min(insertionPoint, sourceCount))
    containers = manager.effectiveContainers()
  for caret in manager.xLayout.caretPositionsFor(index):
    let
      virtualRect = rect(
        manager.xLayoutRect.origin.x + caret.rect.x,
        manager.xLayoutRect.origin.y + caret.rect.y,
        caret.rect.w,
        caret.rect.h,
      )
      containerIndex = containers.containerIndexForVirtualRect(virtualRect)
    result.add TextCaretPosition(
      textIndex: initTextIndex(caret.sourceRune),
      glyphIndex:
        if caret.glyphIndex >= 0:
          some(initGlyphIndex(caret.glyphIndex))
        else:
          none(GlyphIndex),
      lineIndex: initTextLineIndex(caret.lineIndex),
      containerIndex: containerIndex,
      kind: caret.affinity.toTextCaretPositionKind(),
      rect: manager.actualRectForVirtualRect(virtualRect),
    )
  if result.len == 0:
    let rect = manager.caretRect(index)
    result.add TextCaretPosition(
      textIndex: initTextIndex(index),
      glyphIndex: none(GlyphIndex),
      lineIndex: initTextLineIndex(0),
      containerIndex:
        containers.containerIndexForVirtualRect(manager.virtualCaretRect(index)),
      kind: tcpInside,
      rect: rect,
    )

proc defaultSelectionRects(manager: TextLayoutManager, range: TextRange): seq[Rect] =
  if range.length == 0:
    return @[]
  manager.updateLayout()
  let clamped = clampTextRange(manager.xLayout.sourceRuneCount(), range)
  for rect in manager.xLayout.selectionRectsFor(clamped.sourceSlice):
    result.add manager.actualRectForVirtualRect(
      rect.toContainerRect(manager.xLayoutRect)
    )

proc selectionRects*(manager: TextLayoutManager, range: TextRange): seq[Rect] =
  manager.lmSelectionRects(range)

proc firstRectForTextRange*(manager: TextLayoutManager, range: TextRange): Rect =
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

proc temporaryAttributeRuns*(
    manager: TextLayoutManager, range: TextRange
): seq[TextAttributeRun] =
  let
    total = if manager.xTextStorage.isNil: 0 else: manager.xTextStorage.len
    clamped = clampTextRange(total, range)
  for run in manager.xTemporaryAttributes:
    if run.range.textRangeIntersects(clamped):
      result.add run
  if not manager.xDelegate.isNil:
    let supplied = manager.xDelegate.trySendLocal(
      tempAttributesForRange(), (manager: manager, range: clamped)
    )
    if supplied.isSome:
      for run in supplied.get():
        if run.range.textRangeIntersects(clamped):
          result.add run
  result = result.sortedTemporaryRuns()

proc temporaryAttributesAt*(manager: TextLayoutManager, index: int): TextAttributes =
  let runs = manager.temporaryAttributeRuns(initTextRange(index, 1))
  if runs.len > 0:
    runs[^1].attributes
  elif not manager.xTextStorage.isNil:
    manager.xTextStorage.attributesAt(index)
  else:
    defaultTextAttributes()

proc temporaryAttributesAt*(
    manager: TextLayoutManager, index: TextIndex
): TextAttributes =
  manager.temporaryAttributesAt(index.toInt)

proc setTemporaryAttributes*(
    manager: TextLayoutManager, range: TextRange, attributes: TextAttributes
) =
  let
    total = if manager.xTextStorage.isNil: 0 else: manager.xTextStorage.len
    clamped = clampTextRange(total, range)
  if clamped.length == 0:
    return

  var nextRuns: seq[TextAttributeRun]
  for run in manager.xTemporaryAttributes:
    if not run.range.textRangeIntersects(clamped):
      nextRuns.add run
    else:
      let
        runStart = int(run.range.location)
        runStop = run.range.maxIndex
        start = int(clamped.location)
        stop = clamped.maxIndex
      if runStart < start:
        nextRuns.add TextAttributeRun(
          range: initTextRange(runStart, start - runStart), attributes: run.attributes
        )
      if runStop > stop:
        nextRuns.add TextAttributeRun(
          range: initTextRange(stop, runStop - stop), attributes: run.attributes
        )
  nextRuns.add TextAttributeRun(range: clamped, attributes: attributes)
  manager.xTemporaryAttributes = nextRuns.sortedTemporaryRuns()
  manager.invalidateDisplay(clamped)

proc addTemporaryAttributes*(
    manager: TextLayoutManager, range: TextRange, attributes: TextAttributes
) =
  manager.setTemporaryAttributes(range, attributes)

proc removeTemporaryAttributes*(manager: TextLayoutManager, range: TextRange) =
  let
    total = if manager.xTextStorage.isNil: 0 else: manager.xTextStorage.len
    clamped = clampTextRange(total, range)
  if clamped.length == 0:
    return

  var nextRuns: seq[TextAttributeRun]
  for run in manager.xTemporaryAttributes:
    if not run.range.textRangeIntersects(clamped):
      nextRuns.add run
    else:
      let
        runStart = int(run.range.location)
        runStop = run.range.maxIndex
        start = int(clamped.location)
        stop = clamped.maxIndex
      if runStart < start:
        nextRuns.add TextAttributeRun(
          range: initTextRange(runStart, start - runStart), attributes: run.attributes
        )
      if runStop > stop:
        nextRuns.add TextAttributeRun(
          range: initTextRange(stop, runStop - stop), attributes: run.attributes
        )
  manager.xTemporaryAttributes = nextRuns.sortedTemporaryRuns()
  manager.invalidateDisplay(clamped)

proc characterRect*(manager: TextLayoutManager, index: int): Rect =
  if manager.xTextStorage.isNil:
    return rect(0.0, 0.0, 0.0, 0.0)
  let total = manager.xTextStorage.len
  if index < 0 or index >= total:
    return rect(0.0, 0.0, 0.0, 0.0)
  result = manager.textRangeBounds(initTextRange(index, 1))
  if result.isEmpty:
    result = manager.caretRect(index)

proc boundsForGlyphRange*(manager: TextLayoutManager, range: GlyphRange): Rect =
  if range.length == 0:
    return rect(0.0, 0.0, 0.0, 0.0)
  manager.updateLayout()
  let
    count = manager.xLayout.glyphCount()
    start = max(0, min(range.location.toInt, count))
    stop = max(start, min(range.maxIndex, count))
  for glyphIndex in start ..< stop:
    let rect = manager.actualRectForVirtualRect(
      manager.xLayout.glyphRect(glyphIndex).toContainerRect(manager.xLayoutRect)
    )
    if result.isEmpty:
      result = rect
    else:
      result = result.union(rect)

proc glyphRangeForBoundingRect*(manager: TextLayoutManager, rect: Rect): GlyphRange =
  if rect.isEmpty:
    return initGlyphRange(0, 0)
  manager.updateLayout()

  var
    found = false
    start = high(int)
    stop = 0
  for glyphIndex in 0 ..< manager.xLayout.glyphCount():
    let glyph = manager.glyphInfo(glyphIndex)
    if glyph.isSome and not glyph.get().bounds.intersection(rect).isEmpty:
      found = true
      start = min(start, glyphIndex)
      stop = max(stop, glyphIndex + 1)
  if found:
    initGlyphRange(start, stop - start)
  else:
    initGlyphRange(0, 0)

proc glyphRangeForBoundingRect*(
    manager: TextLayoutManager, rect: Rect, containerIndex: TextContainerIndex
): GlyphRange =
  let containers = manager.effectiveContainers()
  if containerIndex.toInt < 0 or containerIndex.toInt >= containers.len:
    return initGlyphRange(0, 0)
  manager.glyphRangeForBoundingRect(
    rect.intersection(containers[containerIndex.toInt].layoutRect())
  )

proc lineFragmentRectForGlyphIndex*(
    manager: TextLayoutManager, index: GlyphIndex
): Rect =
  let fragment = manager.lineFragmentForGlyphIndex(index)
  if fragment.isSome:
    fragment.get().fragmentRect
  else:
    rect(0.0, 0.0, 0.0, 0.0)

proc lineFragmentRectForGlyphIndex*(manager: TextLayoutManager, index: int): Rect =
  if index < 0:
    rect(0.0, 0.0, 0.0, 0.0)
  else:
    manager.lineFragmentRectForGlyphIndex(initGlyphIndex(index))

proc usedRectForLineFragmentAtGlyphIndex*(
    manager: TextLayoutManager, index: GlyphIndex
): Rect =
  let fragment = manager.lineFragmentForGlyphIndex(index)
  if fragment.isSome:
    fragment.get().usedRect
  else:
    rect(0.0, 0.0, 0.0, 0.0)

proc usedRectForLineFragmentAtGlyphIndex*(
    manager: TextLayoutManager, index: int
): Rect =
  if index < 0:
    rect(0.0, 0.0, 0.0, 0.0)
  else:
    manager.usedRectForLineFragmentAtGlyphIndex(initGlyphIndex(index))

proc lineFragmentMetrics*(
    manager: TextLayoutManager, index: TextLineIndex
): Option[TextLineFragmentMetrics] =
  let fragment = manager.lineFragment(index)
  if fragment.isNone:
    return none(TextLineFragmentMetrics)
  let
    glyphIndex = fragment.get().glyphRange.location
    lineSpacing = manager.delegateLineSpacing(glyphIndex)
    before = manager.delegateParagraphSpacingBefore(glyphIndex)
    after = manager.delegateParagraphSpacingAfter(glyphIndex)
    textLength = if manager.xTextStorage.isNil: 0 else: manager.xTextStorage.len
    isExtra =
      fragment.get().textRange.isEmpty and
      int(fragment.get().textRange.location) == textLength
  some(
    TextLineFragmentMetrics(
      fragment: fragment.get(),
      lineSpacing: lineSpacing,
      paragraphSpacingBefore: before,
      paragraphSpacingAfter: after,
      extraLineFragment: isExtra,
    )
  )

proc lineFragmentMetrics*(
    manager: TextLayoutManager, index: int
): Option[TextLineFragmentMetrics] =
  if index < 0:
    none(TextLineFragmentMetrics)
  else:
    manager.lineFragmentMetrics(initTextLineIndex(index))

proc lineFragmentMetricsForGlyphIndex*(
    manager: TextLayoutManager, index: GlyphIndex
): Option[TextLineFragmentMetrics] =
  let fragment = manager.lineFragmentForGlyphIndex(index)
  if fragment.isNone:
    none(TextLineFragmentMetrics)
  else:
    manager.lineFragmentMetrics(fragment.get().lineIndex)

proc extraLineFragment*(manager: TextLayoutManager): TextLineFragment =
  manager.updateLayout()
  let
    textLength = if manager.xTextStorage.isNil: 0 else: manager.xTextStorage.len
    fragment = manager.lineFragmentForTextIndex(textLength)
  if fragment.isSome and fragment.get().textRange.isEmpty:
    fragment.get()
  else:
    manager.emptyLineFragment(manager.lineFragments().len, textLength)

proc extraLineFragmentRect*(manager: TextLayoutManager): Rect =
  manager.extraLineFragment().fragmentRect

proc extraLineFragmentUsedRect*(manager: TextLayoutManager): Rect =
  manager.extraLineFragment().usedRect

proc extraLineFragmentContainerIndex*(manager: TextLayoutManager): TextContainerIndex =
  manager.extraLineFragment().containerIndex

proc boundingRectForGlyphRange*(manager: TextLayoutManager, range: GlyphRange): Rect =
  manager.boundsForGlyphRange(range)

proc characterRangeForGlyphRange*(
    manager: TextLayoutManager, range: GlyphRange
): TextRange =
  manager.textRangeForGlyphRange(range)

proc glyphRangeForCharacterRange*(
    manager: TextLayoutManager, range: TextRange
): GlyphRange =
  manager.glyphRangeForTextRange(range)

proc glyphIndexForCharacterIndex*(
    manager: TextLayoutManager, index: int
): Option[GlyphIndex] =
  manager.glyphIndexForTextIndex(index)

proc characterIndexForGlyphIndex*(manager: TextLayoutManager, index: int): TextIndex =
  manager.textIndexForGlyphIndex(index)

proc numberOfGlyphs*(manager: TextLayoutManager): Natural =
  manager.glyphCount()

proc lineFragmentRectForGlyphAtIndex*(manager: TextLayoutManager, index: int): Rect =
  manager.lineFragmentRectForGlyphIndex(index)

proc usedRectForLineFragmentAtIndex*(manager: TextLayoutManager, index: int): Rect =
  manager.usedRectForLineFragmentAtGlyphIndex(index)

proc usedRectForTextContainer*(
    manager: TextLayoutManager, index: TextContainerIndex
): Rect =
  for fragment in manager.lineFragments():
    if fragment.containerIndex == index:
      if result.isEmpty:
        result = fragment.usedRect
      else:
        result = result.union(fragment.usedRect)

proc invalidateLayoutForCharacterRange*(manager: TextLayoutManager, range: TextRange) =
  manager.invalidateLayout(range)

proc invalidateGlyphsForCharacterRange*(manager: TextLayoutManager, range: TextRange) =
  manager.invalidateGlyphs(manager.glyphRangeForTextRange(range))

proc invalidateDisplayForCharacterRange*(manager: TextLayoutManager, range: TextRange) =
  manager.invalidateDisplay(range)

proc lineRange*(manager: TextLayoutManager, line: int): TextRange =
  if manager.xTextStorage.isNil or line < 0:
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
  if manager.xTextStorage.isNil:
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
  if manager.xTextStorage.isNil or line < 0:
    return rect(0.0, 0.0, 0.0, 0.0)
  let range = manager.lineRange(line)
  if range.length > 0:
    return manager.textRangeBounds(range)
  if line == manager.lineForIndex(int(range.location)):
    return manager.caretRect(int(range.location))
  rect(0.0, 0.0, 0.0, 0.0)

proc emptyLineIndexAtPoint(manager: TextLayoutManager, point: Point): int =
  if manager.xTextStorage.isNil:
    return -1

  let runes = manager.xTextStorage.stringValue().toRunes()
  for index, rune in runes:
    if rune != Rune('\n'):
      continue
    let nextIndex = index + 1
    if nextIndex < runes.len and runes[nextIndex] != Rune('\n'):
      continue

    let
      caret = manager.virtualCaretRect(nextIndex)
      lineHeight = max(caret.size.height, defaultFontSize())
      caretY = caret.origin.y - manager.xLayoutRect.origin.y
    if point.y >= caretY and point.y < caretY + lineHeight:
      return nextIndex

  -1

proc lineBoundedIndexAtPoint(manager: TextLayoutManager, point: Point): int =
  if manager.xTextStorage.isNil:
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
      caret = manager.virtualCaretRect(index)
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

proc defaultTextIndexAtPoint(manager: TextLayoutManager, point: Point): int =
  manager.updateLayout()
  let localPoint = manager.localLayoutPoint(point)
  let emptyLineIndex = manager.emptyLineIndexAtPoint(localPoint)
  if emptyLineIndex >= 0:
    return emptyLineIndex
  let lineBoundedIndex = manager.lineBoundedIndexAtPoint(localPoint)
  if lineBoundedIndex >= 0:
    return lineBoundedIndex
  let nearest =
    manager.xLayout.nearestSourceRuneForCaretPoint(vec2(localPoint.x, localPoint.y))
  max(0, min(nearest, manager.xTextStorage.len))

proc textIndexAtPoint*(manager: TextLayoutManager, point: Point): int =
  manager.lmTextIndexAtPoint(point)

proc containerIndexAtPoint*(
    manager: TextLayoutManager, point: Point
): Option[TextContainerIndex] =
  let containers = manager.effectiveContainers()
  for index, container in containers:
    if container.layoutRect().contains(point):
      return some(initTextContainerIndex(index))
  none(TextContainerIndex)

proc textHitTestAtPoint*(manager: TextLayoutManager, point: Point): TextHitTestResult =
  result.point = point
  if manager.isNil:
    result.textIndex = initTextIndex(0)
    result.textRange = initTextRange(0, 0)
    result.glyphIndex = none(GlyphIndex)
    result.lineIndex = none(TextLineIndex)
    result.containerIndex = none(TextContainerIndex)
    return

  let
    index = manager.textIndexAtPoint(point)
    fragment = manager.lineFragmentForTextIndex(index)
  result.textIndex = initTextIndex(index)
  result.textRange = manager.textRangeAtPoint(point)
  result.glyphIndex = manager.glyphIndexAtPoint(point)
  result.containerIndex = manager.containerIndexAtPoint(point)
  if result.containerIndex.isNone and fragment.isSome:
    result.containerIndex = some(fragment.get().containerIndex)
  result.lineIndex =
    if fragment.isSome:
      some(fragment.get().lineIndex)
    else:
      none(TextLineIndex)
