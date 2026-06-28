import std/[hashes, options, unicode, unittest]

import sigils/core

import merenda/nimkit

const TextLayoutEpsilon = 0.01'f32

type
  TextStorageSignalSpy = ref object of DynamicAgent
    willCount: int
    didCount: int
    lastEdit: TextStorageEdit

  TextLayoutSignalSpy = ref object of DynamicAgent
    invalidations: int
    containerChanges: int
    containerInvalidations: int
    completions: int
    geometryChanges: int
    lastRanges: seq[TextRange]
    lastContainers: seq[TextContainer]
    lastContainerIndex: TextContainerIndex
    lastSnapshot: TextLayoutSnapshot

  LayoutClientSpy = ref object of DynamicAgent
    storage: TextStorage
    container: TextContainer
    alignment: TextAlignment
    invalidations: int
    completions: int
    geometryChanges: int
    contentChanges: int

  ContractBackend = ref object of TextLayoutBackend
    charWidth: float32
    lineHeight: float32
    requests: seq[TextLayoutRequest]

protocol TextStorageSignalSpyEvents from TextStorageSignalSpy:
  includes TextStorageEditingEvents

  proc willEdit(spy: TextStorageSignalSpy, edit: TextStorageEdit) {.slot.} =
    inc spy.willCount
    spy.lastEdit = edit

  proc didEdit(spy: TextStorageSignalSpy, edit: TextStorageEdit) {.slot.} =
    inc spy.didCount
    spy.lastEdit = edit

protocol TextLayoutSignalSpyEvents from TextLayoutSignalSpy:
  includes TextLayoutEvents

  proc layoutDidInvalidate(spy: TextLayoutSignalSpy, ranges: seq[TextRange]) {.slot.} =
    inc spy.invalidations
    spy.lastRanges = ranges

  proc containersDidChange(
      spy: TextLayoutSignalSpy, containers: seq[TextContainer]
  ) {.slot.} =
    inc spy.containerChanges
    spy.lastContainers = containers

  proc containerDidInvalidate(
      spy: TextLayoutSignalSpy, index: TextContainerIndex, container: TextContainer
  ) {.slot.} =
    discard container
    inc spy.containerInvalidations
    spy.lastContainerIndex = index

  proc layoutDidComplete(
      spy: TextLayoutSignalSpy, snapshot: TextLayoutSnapshot
  ) {.slot.} =
    inc spy.completions
    spy.lastSnapshot = snapshot

  proc layoutGeometryDidChange(
      spy: TextLayoutSignalSpy,
      oldUsedRect: Rect,
      oldContentSize: Size,
      snapshot: TextLayoutSnapshot,
  ) {.slot.} =
    discard oldUsedRect
    discard oldContentSize
    inc spy.geometryChanges
    spy.lastSnapshot = snapshot

protocol LayoutClientSpyProtocol of TextLayoutClientProtocol:
  method textLayoutStorage(
      spy: LayoutClientSpy, manager: TextLayoutManager
  ): TextStorage =
    discard manager
    spy.storage

  method textLayoutContainer(
      spy: LayoutClientSpy, manager: TextLayoutManager
  ): TextContainer =
    discard manager
    spy.container

  method textLayoutAlignment(
      spy: LayoutClientSpy, manager: TextLayoutManager
  ): TextAlignment =
    discard manager
    spy.alignment

protocol LayoutClientSpyEvents from LayoutClientSpy:
  includes TextLayoutEvents

  proc layoutDidInvalidate(spy: LayoutClientSpy, ranges: seq[TextRange]) {.slot.} =
    discard ranges
    inc spy.invalidations

  proc layoutDidComplete(spy: LayoutClientSpy, snapshot: TextLayoutSnapshot) {.slot.} =
    discard snapshot
    inc spy.completions

  proc layoutGeometryDidChange(
      spy: LayoutClientSpy,
      oldUsedRect: Rect,
      oldContentSize: Size,
      snapshot: TextLayoutSnapshot,
  ) {.slot.} =
    discard oldUsedRect
    discard oldContentSize
    discard snapshot
    inc spy.geometryChanges
    inc spy.contentChanges

func contractLayoutRect(container: TextContainer): Rect =
  container.layoutRect()

func contractContainers(request: TextLayoutRequest): seq[TextContainer] =
  if request.containers.len == 0:
    @[request.container]
  else:
    request.containers

func contractUnionRects(rects: openArray[Rect]): Rect =
  var hasRect = false
  for rect in rects:
    if not hasRect:
      result = rect
      hasRect = true
    else:
      result = result.union(rect)

func contractLineCapacity(container: TextContainer, lineHeight: float32): int =
  if container.maximumNumberOfLines > 0:
    return int(container.maximumNumberOfLines)
  let height = container.contractLayoutRect().size.height
  if height <= 0.0'f32:
    high(int)
  else:
    max(1, int(height / max(lineHeight, 1.0'f32)))

proc mapContractFragmentsToContainers(
    fragments: seq[TextLineFragment],
    containers: openArray[TextContainer],
    lineHeight: float32,
): seq[TextLineFragment] =
  if containers.len == 0:
    return fragments

  var
    containerIndex = 0
    lineInContainer = 0
  for fragment in fragments:
    while containerIndex < containers.len:
      let capacity = containers[containerIndex].contractLineCapacity(lineHeight)
      if lineInContainer < capacity:
        break
      inc containerIndex
      lineInContainer = 0
    if containerIndex >= containers.len:
      break

    let
      layoutRect = containers[containerIndex].contractLayoutRect()
      lineY = layoutRect.origin.y + lineInContainer.float32 * lineHeight
    var mapped = fragment
    mapped.containerIndex = initTextContainerIndex(containerIndex)
    mapped.fragmentRect =
      initRect(layoutRect.origin.x, lineY, layoutRect.size.width, lineHeight)
    mapped.usedRect = initRect(
      layoutRect.origin.x,
      lineY,
      min(fragment.usedRect.size.width, layoutRect.size.width),
      lineHeight,
    )
    mapped.baseline = lineY + lineHeight * 0.75'f32
    mapped.ascent = lineHeight * 0.75'f32
    mapped.descent = lineHeight * 0.25'f32
    result.add mapped
    inc lineInContainer

proc addContractFragment(
    fragments: var seq[TextLineFragment],
    lineIndex: var int,
    glyphIndex: var int,
    maxUsedWidth: var float32,
    layoutRect: Rect,
    charWidth, lineHeight: float32,
    start, length: int,
    hardBreak, wrapped: bool,
) =
  let
    usedLength =
      if hardBreak and length > 0:
        length - 1
      else:
        length
    lineY = layoutRect.origin.y + lineIndex.float32 * lineHeight
    usedWidth = usedLength.float32 * charWidth
    fragmentRect =
      initRect(layoutRect.origin.x, lineY, layoutRect.size.width, lineHeight)
    usedRect = initRect(layoutRect.origin.x, lineY, usedWidth, lineHeight)
  fragments.add TextLineFragment(
    lineIndex: initTextLineIndex(lineIndex),
    containerIndex: initTextContainerIndex(0),
    glyphRange: initGlyphRange(glyphIndex, length),
    textRange: initTextRange(start, length),
    fragmentRect: fragmentRect,
    usedRect: usedRect,
    baseline: lineY + lineHeight * 0.75'f32,
    ascent: lineHeight * 0.75'f32,
    descent: lineHeight * 0.25'f32,
    leading: 0.0'f32,
    hardBreak: hardBreak,
    wrapped: wrapped,
  )
  glyphIndex += length
  maxUsedWidth = max(maxUsedWidth, usedWidth)
  inc lineIndex

proc contractSnapshot(
    backend: ContractBackend, request: TextLayoutRequest
): TextLayoutSnapshot =
  let
    text =
      if request.storage.isNil:
        ""
      else:
        request.storage.stringValue()
    containers = request.contractContainers()
    runes = text.toRunes()
    layoutRect = containers[0].contractLayoutRect()
    wraps = request.wraps or containers[0].wrapsText
    maxChars =
      if wraps:
        max(1, int(layoutRect.size.width / max(backend.charWidth, 1.0'f32)))
      else:
        max(runes.len, 1)

  result.textHash = hash(text)
  result.layoutHash = hash(
    text & "|" & $layoutRect.size.width & "|" & $layoutRect.size.height & "|" &
      $containers.len & "|" & $wraps
  )
  result.containers = containers
  for container in containers:
    result.containerRects.add container.contractLayoutRect()
  result.containerRect = result.containerRects.contractUnionRects()
  result.glyphCount = runes.len.Natural

  var
    lineIndex = 0
    glyphIndex = 0
    maxUsedWidth = 0.0'f32
    fragments: seq[TextLineFragment]

  if runes.len == 0:
    addContractFragment(
      fragments,
      lineIndex,
      glyphIndex,
      maxUsedWidth,
      layoutRect,
      backend.charWidth,
      backend.lineHeight,
      0,
      0,
      hardBreak = false,
      wrapped = false,
    )
  else:
    var sourceStart = 0
    while sourceStart < runes.len:
      var lineEnd = sourceStart
      while lineEnd < runes.len and runes[lineEnd] != Rune('\n'):
        inc lineEnd
      let
        hasBreak = lineEnd < runes.len and runes[lineEnd] == Rune('\n')
        contentLength = lineEnd - sourceStart

      if contentLength == 0:
        addContractFragment(
          fragments,
          lineIndex,
          glyphIndex,
          maxUsedWidth,
          layoutRect,
          backend.charWidth,
          backend.lineHeight,
          sourceStart,
          if hasBreak: 1 else: 0,
          hardBreak = hasBreak,
          wrapped = false,
        )
      else:
        var chunkStart = sourceStart
        while chunkStart < lineEnd:
          let
            remaining = lineEnd - chunkStart
            take =
              if wraps:
                min(maxChars, remaining)
              else:
                remaining
            chunkEnd = chunkStart + take
            lastChunk = chunkEnd == lineEnd
            length = take + (if lastChunk and hasBreak: 1 else: 0)
          addContractFragment(
            fragments,
            lineIndex,
            glyphIndex,
            maxUsedWidth,
            layoutRect,
            backend.charWidth,
            backend.lineHeight,
            chunkStart,
            length,
            hardBreak = lastChunk and hasBreak,
            wrapped = wraps and not lastChunk,
          )
          chunkStart = chunkEnd

      if not hasBreak:
        break
      sourceStart = lineEnd + 1
      if sourceStart == runes.len:
        addContractFragment(
          fragments,
          lineIndex,
          glyphIndex,
          maxUsedWidth,
          layoutRect,
          backend.charWidth,
          backend.lineHeight,
          sourceStart,
          0,
          hardBreak = false,
          wrapped = false,
        )
        break

  result.lineFragments =
    fragments.mapContractFragmentsToContainers(containers, backend.lineHeight)

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
  var fragmentRect = result.usedRect
  for fragment in result.lineFragments:
    fragmentRect = fragmentRect.union(fragment.fragmentRect)
  result.contentSize = fragmentRect.size

protocol ContractBackendProtocol of TextLayoutBackendProtocol:
  method layoutText(
      backend: ContractBackend, request: TextLayoutRequest
  ): TextLayoutResult =
    backend.requests.add request
    TextLayoutResult(snapshot: backend.contractSnapshot(request))

proc checkClose(actual, expected: float32) =
  check abs(actual - expected) <= TextLayoutEpsilon

proc hasLineStart(snapshot: TextLayoutSnapshot, index: int): bool =
  for fragment in snapshot.lineFragments:
    if int(fragment.textRange.location) == index:
      return true

proc newTextStorageSignalSpy(): TextStorageSignalSpy =
  result = TextStorageSignalSpy()
  discard result.withProto()

proc newTextLayoutSignalSpy(): TextLayoutSignalSpy =
  result = TextLayoutSignalSpy()
  discard result.withProto()

proc newLayoutClientSpy(
    storage: TextStorage, container: TextContainer, alignment = taLeft
): LayoutClientSpy =
  result = LayoutClientSpy(storage: storage, container: container, alignment: alignment)
  discard result.withProto()
  discard result.withProtocol(LayoutClientSpyProtocol)

proc newContractBackend(charWidth = 10.0'f32, lineHeight = 12.0'f32): ContractBackend =
  result = ContractBackend(charWidth: charWidth, lineHeight: lineHeight)
  discard result.withProtocol(ContractBackendProtocol)

suite "nimkit text layout":
  test "text storage editing protocol emits mutation signals":
    let
      storage = newTextStorage("Alpha")
      spy = newTextStorageSignalSpy()

    spy.observeProtocol(storage, TextStorageEditingEvents)
    check storage.conformsTo(TextStorageEditDispatchProtocol)

    storage.replace(initTextRange(1, 2), "zz")
    check spy.willCount == 1
    check spy.didCount == 1
    check spy.lastEdit.range == initTextRange(1, 2)
    check spy.lastEdit.replacementLength == 2
    check spy.lastEdit.textDelta == 0
    check spy.lastEdit.kinds == {tseCharacters}

    storage.setAttributes(
      initTextRange(0, 1), defaultTextAttributes(initColor(1.0, 0.0, 0.0), 13.0)
    )
    check spy.willCount == 2
    check spy.didCount == 2
    check spy.lastEdit.kinds == {tseAttributes}

  test "storage edits invalidate layout through manager slots":
    let
      storage = newTextStorage("Alpha Beta")
      manager = newTextLayoutManager(
        storage, initTextContainer(initSize(180.0, 80.0), insets(0.0))
      )
      spy = newTextLayoutSignalSpy()

    spy.observeProtocol(manager, TextLayoutEvents)
    check manager.conformsTo(TextLayoutManagerProtocol)
    manager.updateLayout()
    check manager.hasValidLayout()
    check spy.completions == 1

    storage.replace(initTextRange(1, 3), "XYZ")
    check not manager.hasValidLayout()
    check spy.invalidations == 1
    check spy.lastRanges[^1] == initTextRange(1, 3)

    manager.updateLayout()
    check manager.hasValidLayout()
    check spy.completions == 2

  test "batched storage edits invalidate multiple layout managers once":
    let
      storage = newTextStorage("Shared storage")
      managerA = newTextLayoutManager(
        storage, initTextContainer(initSize(180.0, 80.0), insets(0.0))
      )
      managerB = newTextLayoutManager(
        storage, initTextContainer(initSize(120.0, 80.0), insets(0.0))
      )
      spyA = newTextLayoutSignalSpy()
      spyB = newTextLayoutSignalSpy()

    spyA.observeProtocol(managerA, TextLayoutEvents)
    spyB.observeProtocol(managerB, TextLayoutEvents)
    managerA.updateLayout()
    managerB.updateLayout()
    check managerA.hasValidLayout()
    check managerB.hasValidLayout()

    storage.beginEditing()
    storage.replace(initTextRange(0, 6), "Updated")
    storage.setAttributes(
      initTextRange(0, 7), defaultTextAttributes(initColor(0.4, 0.2, 0.8), 15.0)
    )
    check managerA.hasValidLayout()
    check managerB.hasValidLayout()

    storage.endEditing()
    check not managerA.hasValidLayout()
    check not managerB.hasValidLayout()
    check spyA.invalidations == 1
    check spyB.invalidations == 1
    check spyA.lastRanges[^1] == initTextRange(0, 7)
    check spyB.lastRanges[^1] == initTextRange(0, 7)

  test "figdraw text typesetter implements backend protocol":
    let
      storage = newTextStorage("Backend")
      container = initTextContainer(initSize(160.0, 60.0), insets(2.0))
      style = newTextLayoutManager(storage, container).textStyle()
      backend = newFigDrawTextTypesetter()
      layout = backend.layoutText(
        TextLayoutRequest(
          storage: storage,
          container: container,
          style: style,
          alignment: taLeft,
          wraps: false,
          invalidatedRanges: @[initTextRange(0, storage.len)],
        )
      )

    check backend.conformsTo(TextLayoutBackendProtocol)
    check layout.snapshot.glyphCount > 0
    check layout.snapshot.lineFragments.len > 0
    checkClose(layout.snapshot.containerRect.origin.x, 2.0)

  test "text containers expose padding tracking limits and exclusions":
    let container = initTextContainer(
      initSize(120.0, 60.0),
      insets(2.0, 4.0, 6.0, 8.0),
      wraps = true,
      origin = initPoint(10.0, 20.0),
      lineFragmentPadding = 3.0,
      widthTracksTextView = true,
      heightTracksTextView = true,
      maximumNumberOfLines = 2,
      lineBreakMode = tlbmCharWrapping,
      exclusionPaths = [initRect(20.0, 22.0, 20.0, 12.0)],
    )
    let
      layoutRect = container.layoutRect()
      effective = container.effectiveLineFragmentRect(
        initRect(layoutRect.origin.x, layoutRect.origin.y, 60.0, 12.0)
      )

    checkClose(layoutRect.origin.x, 17.0)
    checkClose(layoutRect.origin.y, 22.0)
    checkClose(layoutRect.size.width, 102.0)
    checkClose(layoutRect.size.height, 52.0)
    check container.wrapsText
    check container.widthTracksTextView
    check container.heightTracksTextView
    check container.maximumNumberOfLines == 2
    check container.lineBreakMode == tlbmCharWrapping
    checkClose(effective.origin.x, 40.0)
    checkClose(effective.size.width, 37.0)

  test "layout manager replaces and invalidates text containers":
    let
      storage = newTextStorage("Alpha\nBeta\nGamma")
      first = initTextContainer(initSize(120.0, 24.0), insets(0.0))
      second = initTextContainer(
        initSize(120.0, 24.0), insets(0.0), origin = initPoint(150.0, 0.0)
      )
      replacement = initTextContainer(
        initSize(140.0, 24.0), insets(1.0), origin = initPoint(150.0, 0.0)
      )
      backend = newContractBackend()
      manager = newTextLayoutManager(storage, first)
      spy = newTextLayoutSignalSpy()

    manager.textLayoutBackend = backend
    spy.observeProtocol(manager, TextLayoutEvents)
    manager.textContainers = @[first, second]
    check spy.containerChanges == 1
    check spy.lastContainers.len == 2
    discard manager.layoutSnapshot()

    manager.replaceTextContainer(initTextContainerIndex(1), replacement)
    check spy.containerChanges == 2
    check spy.containerInvalidations == 1
    check spy.lastContainerIndex == initTextContainerIndex(1)
    check not manager.hasValidLayout()

    discard manager.layoutSnapshot()
    check backend.requests[^1].containers.len == 2
    check backend.requests[^1].invalidatedContainers[^1] == initTextContainerIndex(1)

  test "backend-free snapshots assign multi-container line indexes":
    let
      storage = newTextStorage("A\nB\nC\nD")
      first =
        initTextContainer(initSize(100.0, 24.0), insets(0.0), maximumNumberOfLines = 1)
      second = initTextContainer(
        initSize(100.0, 48.0),
        insets(0.0),
        origin = initPoint(140.0, 0.0),
        maximumNumberOfLines = 2,
      )
      backend = newContractBackend(charWidth = 10.0, lineHeight = 12.0)
      manager = newTextLayoutManager(storage, first)

    manager.textLayoutBackend = backend
    manager.textContainers = @[first, second]
    let snapshot = manager.layoutSnapshot()

    check backend.requests[^1].containers.len == 2
    check snapshot.containers.len == 2
    check snapshot.containerRects.len == 2
    check snapshot.lineFragments.len == 3
    check snapshot.lineFragments[0].containerIndex == initTextContainerIndex(0)
    check snapshot.lineFragments[1].containerIndex == initTextContainerIndex(1)
    check snapshot.lineFragments[2].containerIndex == initTextContainerIndex(1)
    check snapshot.lineFragments[0].lineIndex.toInt == 0
    check snapshot.lineFragments[1].lineIndex.toInt == 1
    check snapshot.lineFragments[2].lineIndex.toInt == 2

  test "text hit testing reports container indexes":
    let
      first = initTextContainer(initSize(160.0, 80.0), insets(4.0))
      second = initTextContainer(
        initSize(160.0, 80.0), insets(4.0), origin = initPoint(220.0, 0.0)
      )
      manager = newTextLayoutManager(newTextStorage("Alpha Beta"), first)

    manager.textContainers = @[first, second]
    let
      firstHit = manager.textHitTestAtPoint(initPoint(8.0, 8.0))
      secondHit = manager.textHitTestAtPoint(initPoint(224.0, 8.0))

    check firstHit.containerIndex == some(initTextContainerIndex(0))
    check secondHit.containerIndex == some(initTextContainerIndex(1))
    check firstHit.lineIndex.isSome
    check firstHit.textIndex.toInt >= 0

  test "layout client protocol supplies inputs and observes layout hooks":
    let
      client = newLayoutClientSpy(
        newTextStorage("Client text"),
        initTextContainer(initSize(120.0, 60.0), insets(1.0), wraps = true),
      )
      manager = newTextLayoutManager()

    client.observeProtocol(manager, TextLayoutEvents)
    manager.layoutClient = DynamicAgent(client)
    check client.conformsTo(TextLayoutClientProtocol)

    let snapshot = manager.layoutSnapshot()
    check snapshot.glyphCount > 0
    check client.invalidations == 1
    check client.completions == 1
    check client.geometryChanges == 1
    check client.contentChanges == 1

    client.storage.replace(initTextRange(0, 6), "Updated")
    check not manager.hasValidLayout()
    discard manager.layoutSnapshot()
    check client.invalidations == 2
    check client.completions == 2

  test "backend-free snapshots preserve empty hard-break wrapped and trailing lines":
    let emptyBackend = newContractBackend()
    let emptyManager = newTextLayoutManager(
      newTextStorage(""),
      initTextContainer(initSize(80.0, 40.0), insets(2.0), wraps = true),
    )
    emptyManager.textLayoutBackend = emptyBackend

    let emptySnapshot = emptyManager.layoutSnapshot()
    check emptyBackend.requests.len == 1
    check emptySnapshot.glyphCount == 0
    check emptySnapshot.containerRect == initRect(2.0, 2.0, 76.0, 36.0)
    check emptySnapshot.lineFragments.len == 1
    check emptySnapshot.lineFragments[0].textRange == initTextRange(0, 0)
    check emptySnapshot.lineFragments[0].glyphRange == initGlyphRange(0, 0)

    let
      storage = newTextStorage("A\nBCDE\n")
      backend = newContractBackend(charWidth = 10.0, lineHeight = 12.0)
      manager = newTextLayoutManager(
        storage, initTextContainer(initSize(20.0, 80.0), insets(0.0), wraps = true)
      )
    manager.textLayoutBackend = backend

    let snapshot = manager.layoutSnapshot()
    check backend.requests.len == 1
    check snapshot.glyphCount == storage.len.Natural
    check snapshot.lineFragments.len == 4
    check snapshot.lineFragments[0].textRange == initTextRange(0, 2)
    check snapshot.lineFragments[0].hardBreak
    check not snapshot.lineFragments[0].wrapped
    check snapshot.lineFragments[1].textRange == initTextRange(2, 2)
    check snapshot.lineFragments[1].wrapped
    check not snapshot.lineFragments[1].hardBreak
    check snapshot.lineFragments[2].textRange == initTextRange(4, 3)
    check snapshot.lineFragments[2].hardBreak
    check not snapshot.lineFragments[2].wrapped
    check snapshot.lineFragments[3].textRange == initTextRange(storage.len, 0)
    check snapshot.lineFragments[3].glyphRange.isEmpty
    check snapshot.contentSize == initSize(20.0, 48.0)

  test "backend-free layout requests carry text and attribute invalidations":
    let
      storage = newTextStorage("Alpha")
      backend = newContractBackend()
      manager = newTextLayoutManager(
        storage, initTextContainer(initSize(120.0, 40.0), insets(0.0))
      )
      spy = newTextLayoutSignalSpy()

    manager.textLayoutBackend = backend
    spy.observeProtocol(manager, TextLayoutEvents)
    discard manager.layoutSnapshot()
    check manager.hasValidLayout()

    storage.replace(initTextRange(1, 2), "ZZ")
    check not manager.hasValidLayout()
    check spy.invalidations == 1
    check spy.lastRanges[^1] == initTextRange(1, 2)
    discard manager.layoutSnapshot()
    check backend.requests[^1].invalidatedRanges[^1] == initTextRange(1, 2)
    check backend.requests[^1].storage.stringValue() == "AZZha"

    storage.setAttributes(
      initTextRange(0, 3), defaultTextAttributes(initColor(0.8, 0.1, 0.2), 15.0)
    )
    check not manager.hasValidLayout()
    check spy.invalidations == 2
    check spy.lastRanges[^1] == initTextRange(0, 3)
    discard manager.layoutSnapshot()
    check backend.requests[^1].invalidatedRanges[^1] == initTextRange(0, 3)
    check manager.hasValidLayout()

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

  test "wrapped selections return merged visual line bands":
    let storage = newTextStorage("one two three four five six")
    let manager = newTextLayoutManager(
      storage, initTextContainer(initSize(36.0, 160.0), insets(0.0), wraps = true)
    )
    let
      snapshot = manager.layoutSnapshot()
      selection = manager.selectionRects(initTextRange(0, storage.len))

    check snapshot.lineFragments.len > 1
    check selection.len == snapshot.lineFragments.len
    check selection.len < int(snapshot.glyphCount)
    for index, rect in selection:
      check rect.size.width > 0.0
      check rect.size.height > 0.0
      check rect.origin.y >= snapshot.lineFragments[index].fragmentRect.origin.y

  test "caret positions preserve wrapped visual line indexes":
    let manager = newTextLayoutManager(
      newTextStorage("one two three four five six"),
      initTextContainer(initSize(36.0, 160.0), insets(0.0), wraps = true),
    )
    let
      snapshot = manager.layoutSnapshot()
      lastLine = snapshot.lineFragments[^1]
      positions = manager.caretPositions(int(lastLine.textRange.location))

    var foundLine = false
    for position in positions:
      if position.lineIndex == lastLine.lineIndex:
        foundLine = true
        check position.rect.origin.y >= lastLine.fragmentRect.origin.y
        check position.rect.origin.y <= lastLine.fragmentRect.maxY
    check foundLine

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

  test "figdraw snapshots hit-test blank and trailing hard-break lines":
    let
      storage = newTextStorage("A\n\nB\n")
      manager = newTextLayoutManager(
        storage, initTextContainer(initSize(120.0, 120.0), insets(4.0), wraps = false)
      )
      snapshot = manager.layoutSnapshot()
      blank = manager.lineFragmentForTextIndex(2)
      trailing = manager.lineFragmentForTextIndex(storage.len)

    check snapshot.lineFragments.len >= 4
    check blank.isSome
    check blank.get().textRange.location == 2
    check blank.get().hardBreak
    check trailing.isSome
    check trailing.get().textRange == initTextRange(storage.len, 0)

    let
      blankRect = blank.get().fragmentRect
      trailingRect = trailing.get().fragmentRect
    check manager.textIndexAtPoint(
      initPoint(blankRect.origin.x + 1.0, blankRect.origin.y + 1.0)
    ) == 2
    check manager.textIndexAtPoint(
      initPoint(trailingRect.origin.x + 1.0, trailingRect.origin.y + 1.0)
    ) == storage.len

  test "figdraw wrapped selection caret affinity and range round trips stay coherent":
    let
      storage = newTextStorage("one two three four five six")
      manager = newTextLayoutManager(
        storage, initTextContainer(initSize(38.0, 180.0), insets(0.0), wraps = true)
      )
      range = initTextRange(4, 16)
      fragments = manager.lineFragmentsForTextRange(range)
      lineRange = manager.lineRangeForTextRange(range)
      selection = manager.selectionRects(range)

    check fragments.len >= 2
    check lineRange.length == fragments.len.Natural
    check selection.len == fragments.len

    for fragment in fragments:
      if fragment.glyphRange.isEmpty:
        continue
      let
        roundTrip = manager.textRangeForGlyphRange(fragment.glyphRange)
        glyphRoundTrip = manager.glyphRangeForTextRange(roundTrip)
      check int(roundTrip.location) <= fragment.textRange.maxIndex
      check roundTrip.maxIndex >= int(fragment.textRange.location)
      check not glyphRoundTrip.isEmpty

    let
      wrappedBoundary = fragments[1].textRange.location
      positions = manager.caretPositions(int(wrappedBoundary))
    var foundBoundaryLine = false
    for position in positions:
      check position.textIndex.toInt == int(wrappedBoundary)
      check position.rect.size.height > 0.0
      if position.lineIndex == fragments[1].lineIndex:
        foundBoundaryLine = true
    check foundBoundaryLine
