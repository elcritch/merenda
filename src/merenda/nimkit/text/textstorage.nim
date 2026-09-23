import std/[algorithm, heapqueue, options, unicode]

import sigils/core
import sigils/selectors
import ../foundation/undomanagers
import ../foundation/types
import ./gaptextbuffers
import ./textsnapshots
import ./texttypes

type
  TextStorageEditKind* = enum
    tseCharacters
    tseAttributes

  TextStorageEditKinds* = set[TextStorageEditKind]
  TextStorageEditedMask* = TextStorageEditKind
  TextStorageEditedMasks* = TextStorageEditKinds

  TextStorageEdit* = object
    range*: TextRange
    replacementLength*: Natural
    textDelta*: int
    kinds*: TextStorageEditKinds

  TextStyleRun = object
    range: TextRange
    styleId: uint32

  TextStyledSpan* = object
    source*: TextSnapshot
    byteStart*: int
    byteEnd*: int
    runeStart*: int
    runeEnd*: int
    styleId*: uint32

  TextStorage* = ref object of DynamicAgent
    xSnapshot: TextSnapshot
    xRuns: seq[TextStyleRun]
    xStyles: seq[TextAttributes]
    xRevision: Natural
    xDelegate: DynamicAgent
    xLazyProvider: DynamicAgent
    xUndoManager: UndoManager
    xMaterialized: bool
    xEditingDepth: Natural
    xProcessingEditing: bool
    xPendingEdit: TextStorageEdit
    xHasPendingEdit: bool
    xLastProcessedEdit: TextStorageEdit
    xHasLastProcessedEdit: bool

  TextGapStorage* = ref object of TextStorage
    xGapBuffer: GapTextBuffer

  AttributedString* = TextStorage
  MutableAttributedString* = TextStorage

func byteRange*(span: TextStyledSpan): TextByteRange =
  ## UTF-8 source range borrowed by this styled span.
  initTextByteRange(span.byteStart, span.byteEnd - span.byteStart)

func initTextStorageEdit*(
    range: TextRange,
    replacementLength: int,
    textDelta: int,
    kinds: TextStorageEditKinds,
): TextStorageEdit =
  TextStorageEdit(
    range: range,
    replacementLength: max(replacementLength, 0).Natural,
    textDelta: textDelta,
    kinds: kinds,
  )

## Signal/slot observer surface for committed text storage edit lifecycle events.
## Mutation code should route delivery through TextStorageEditDispatchProtocol
## so external editor bridges can coalesce, suppress, mirror, or instrument
## notifications before observers receive them.
protocol TextStorageEditingEvents:
  proc willEdit*(storage: TextStorage, edit: TextStorageEdit) {.signal.}
  proc didEdit*(storage: TextStorage, edit: TextStorageEdit) {.signal.}
  proc storageValueDidChange*(storage: TextStorage, edit: TextStorageEdit) {.signal.}
  proc storageAttributesDidChange*(
    storage: TextStorage, edit: TextStorageEdit
  ) {.signal.}

  proc storageWillProcessEditing*(
    storage: TextStorage, edit: TextStorageEdit
  ) {.signal.}

  proc storageDidProcessEditing*(storage: TextStorage, edit: TextStorageEdit) {.signal.}

protocol TextStorageDelegateProtocol:
  method textStorageShouldFixAttributes*(
    storage: TextStorage, range: TextRange
  ): bool {.optional.}

  method textStorageFixAttributes*(
    storage: TextStorage, range: TextRange
  ): bool {.optional.}

  method textStorageResolveFontFallback*(
    storage: TextStorage, range: TextRange, attributes: TextAttributes
  ): TextAttributes {.optional.}

protocol TextStorageLazyProviderProtocol:
  method lazyTextStorageString*(storage: TextStorage): string {.optional.}
  method lazyTextStorageRuns*(storage: TextStorage): seq[TextAttributeRun] {.optional.}

## Overridable edit event delivery path used by TextStorage mutation procs.
## Backends may override these methods to bridge, coalesce, suppress, or
## instrument edits, then emit TextStorageEditingEvents when observers should
## receive them.
protocol TextStorageEditDispatchProtocol {.selectorScope: protocol.} from TextStorage:
  method dispatchWillEdit*(storage: TextStorage, edit: TextStorageEdit) =
    emit storage.willEdit(edit)

  method dispatchDidEdit*(storage: TextStorage, edit: TextStorageEdit) =
    emit storage.didEdit(edit)

  method dispatchValue*(storage: TextStorage, edit: TextStorageEdit) =
    emit storage.storageValueDidChange(edit)

  method dispatchAttrs*(storage: TextStorage, edit: TextStorageEdit) =
    emit storage.storageAttributesDidChange(edit)

  method dispatchWillProc*(storage: TextStorage, edit: TextStorageEdit) =
    emit storage.storageWillProcessEditing(edit)

  method dispatchDidProc*(storage: TextStorage, edit: TextStorageEdit) =
    emit storage.storageDidProcessEditing(edit)

func clampTextRange(total: int, range: TextRange): TextRange =
  let
    start = max(0, min(int(range.location), total))
    length = max(0, min(int(range.length), total - start))
  initTextRange(start, length)

func intersects(a, b: TextRange): bool =
  int(a.location) < b.maxIndex and int(b.location) < a.maxIndex

func coalesceEdits(a, b: TextStorageEdit): TextStorageEdit =
  let
    start = min(int(a.range.location), int(b.range.location))
    stop = max(a.range.maxIndex, b.range.maxIndex)
    oldLength = max(stop - start, 0)
    delta = a.textDelta + b.textDelta
  initTextStorageEdit(
    initTextRange(start, oldLength), max(oldLength + delta, 0), delta, a.kinds + b.kinds
  )

proc materialize*(storage: TextStorage)
proc processEditing*(storage: TextStorage)
proc fixAttributesInRange*(storage: TextStorage, range: TextRange)
proc applySnapshot(storage: TextStorage, snapshot: TextStorage, actionName: string)

proc hasPendingEdit*(storage: TextStorage): bool =
  storage.xHasPendingEdit

proc currentEdit*(storage: TextStorage): TextStorageEdit =
  if storage.xHasPendingEdit: storage.xPendingEdit else: storage.xLastProcessedEdit

proc editedMask*(storage: TextStorage): TextStorageEditKinds =
  storage.currentEdit().kinds

proc editedRange*(storage: TextStorage): TextRange =
  storage.currentEdit().range

proc changeInLength*(storage: TextStorage): int =
  storage.currentEdit().textDelta

proc revision*(storage: TextStorage): Natural =
  ## Returns the number of committed editing batches applied to this storage.
  if storage.isNil: 0 else: storage.xRevision

proc delegate*(storage: TextStorage): DynamicAgent =
  storage.xDelegate

proc `delegate=`*(storage: TextStorage, delegate: DynamicAgent) =
  storage.xDelegate = delegate

proc undoManager*(storage: TextStorage): UndoManager =
  storage.xUndoManager

proc `undoManager=`*(storage: TextStorage, undoManager: UndoManager) =
  storage.xUndoManager = undoManager

proc lazyProvider*(storage: TextStorage): DynamicAgent =
  storage.xLazyProvider

proc `lazyProvider=`*(storage: TextStorage, provider: DynamicAgent) =
  storage.xLazyProvider = provider
  storage.xMaterialized = provider.isNil

proc isMaterialized*(storage: TextStorage): bool =
  storage.xMaterialized

proc usesGapTextBuffer*(storage: TextStorage): bool =
  storage of TextGapStorage

method storageLength*(storage: TextStorage): int {.base.} =
  storage.xSnapshot.runeLength

method storageLength*(storage: TextGapStorage): int =
  storage.xGapBuffer.len

method storageString*(storage: TextStorage): string {.base.} =
  storage.xSnapshot.bytes

method storageString*(storage: TextGapStorage): string =
  storage.xGapBuffer.stringValue()

method storageSnapshot(storage: TextStorage): TextSnapshot {.base.} =
  storage.xSnapshot

method storageSnapshot(storage: TextGapStorage): TextSnapshot =
  if storage.xSnapshot.isNil:
    storage.xSnapshot = newTextSnapshot(storage.storageString())
  storage.xSnapshot

method setStorageString*(storage: TextStorage, value: string) {.base.} =
  storage.xSnapshot = newTextSnapshot(value)

method setStorageString*(storage: TextGapStorage, value: string) =
  storage.xGapBuffer.setText(value)
  storage.xSnapshot = nil

method restoreStorageText(storage: TextStorage, snapshot: TextStorage) {.base.} =
  storage.xSnapshot = snapshot.storageSnapshot()

method restoreStorageText(storage: TextGapStorage, snapshot: TextStorage) =
  storage.setStorageString(snapshot.storageString())

method storageSubstring*(storage: TextStorage, range: TextRange): string {.base.} =
  let
    clamped = clampTextRange(storage.xSnapshot.runeLength, range)
    start = storage.xSnapshot.byteOffset(int(clamped.location))
    stop = storage.xSnapshot.byteOffset(clamped.maxIndex)
  storage.xSnapshot.bytes[start ..< stop]

method storageSubstring*(storage: TextGapStorage, range: TextRange): string =
  storage.xGapBuffer.substring(range)

method replaceStorageText*(
    storage: TextStorage, range: TextRange, text: string
) {.base.} =
  let
    snapshot = storage.xSnapshot
    clamped = clampTextRange(snapshot.runeLength, range)
    replaceStart = int(clamped.location)
    replaceStop = clamped.maxIndex
    startByte = snapshot.byteOffset(replaceStart)
    stopByte = snapshot.byteOffset(replaceStop)
  storage.xSnapshot = newTextSnapshot(
    snapshot.bytes[0 ..< startByte] & text &
      snapshot.bytes[stopByte ..< snapshot.byteLength]
  )

method replaceStorageText*(storage: TextGapStorage, range: TextRange, text: string) =
  storage.xGapBuffer.replace(range, text)
  storage.xSnapshot = nil

method storageLineCount*(storage: TextStorage): int {.base.} =
  storage.xSnapshot.lineCount

method storageLineCount*(storage: TextGapStorage): int =
  storage.xGapBuffer.lineCount()

method storageLineRange*(storage: TextStorage, line: int): TextRange {.base.} =
  storage.xSnapshot.lineRange(line)

method storageLineRange*(storage: TextGapStorage, line: int): TextRange =
  storage.xGapBuffer.lineRange(line)

method storageParagraphRange*(
    storage: TextStorage, range: TextRange
): TextRange {.base.} =
  let
    total = storage.xSnapshot.runeLength
    clamped = clampTextRange(total, range)
    startTarget = int(clamped.location)
    stopTarget = min(max(clamped.maxIndex, startTarget), total)
  if total == 0:
    return initTextRange(0, 0)

  var
    start = 0
    stop = total
    index = 0
  for rune in storage.xSnapshot.bytes.runes:
    if index < startTarget and rune == Rune('\n'):
      start = index + 1
    elif index >= stopTarget and rune == Rune('\n'):
      stop = index + 1
      break
    inc index
  initTextRange(start, stop - start)

method storageParagraphRange*(storage: TextGapStorage, range: TextRange): TextRange =
  storage.xGapBuffer.paragraphRange(range)

proc notifyCommittedEdit(storage: TextStorage, edit: TextStorageEdit) =
  storage.dispatchDidEdit(edit)
  if storage.xHasPendingEdit:
    storage.xPendingEdit = coalesceEdits(storage.xPendingEdit, edit)
  else:
    storage.xPendingEdit = edit
    storage.xHasPendingEdit = true
  if storage.xEditingDepth == 0 and not storage.xProcessingEditing:
    storage.processEditing()

proc edited*(
    storage: TextStorage,
    kinds: TextStorageEditKinds,
    range: TextRange,
    changeInLength: int,
) =
  storage.materialize()
  let
    clamped = clampTextRange(storage.storageLength(), range)
    replacementLength = max(int(clamped.length) + changeInLength, 0)
  storage.notifyCommittedEdit(
    initTextStorageEdit(clamped, replacementLength, changeInLength, kinds)
  )

proc beginEditing*(storage: TextStorage) =
  inc storage.xEditingDepth

proc endEditing*(storage: TextStorage) =
  if storage.xEditingDepth == 0:
    return
  dec storage.xEditingDepth
  if storage.xEditingDepth == 0:
    storage.processEditing()

proc styleId(storage: TextStorage, attributes: TextAttributes): uint32 =
  for index, existing in storage.xStyles:
    if existing == attributes:
      return index.uint32
  result = storage.xStyles.len.uint32
  storage.xStyles.add attributes

proc styleRun(
    storage: TextStorage, range: TextRange, attributes: TextAttributes
): TextStyleRun =
  TextStyleRun(range: range, styleId: storage.styleId(attributes))

func styleAttributes*(storage: TextStorage, styleId: uint32): TextAttributes =
  storage.xStyles[int(styleId)]

proc normalizeRuns(storage: TextStorage) =
  let total = storage.storageLength()
  if total == 0:
    storage.xRuns.setLen(0)
    storage.xStyles.setLen(0)
    return

  storage.xRuns.sort(
    proc(a, b: TextStyleRun): int =
      cmp(int(a.range.location), int(b.range.location))
  )

  var normalized: seq[TextStyleRun]
  for run in storage.xRuns:
    let clamped = clampTextRange(total, run.range)
    if clamped.length == 0:
      discard
    elif normalized.len > 0 and normalized[^1].styleId == run.styleId and
        normalized[^1].range.maxIndex == int(clamped.location):
      normalized[^1].range.length =
        (int(normalized[^1].range.length) + int(clamped.length)).Natural
    else:
      normalized.add TextStyleRun(range: clamped, styleId: run.styleId)

  if normalized.len == 0:
    normalized.add storage.styleRun(initTextRange(0, total), defaultTextAttributes())
  var compactStyles: seq[TextAttributes]
  var remap = newSeq[int](storage.xStyles.len)
  for index in 0 ..< remap.len:
    remap[index] = -1
  for run in normalized.mitems:
    let oldId = int(run.styleId)
    if remap[oldId] < 0:
      remap[oldId] = compactStyles.len
      compactStyles.add storage.xStyles[oldId]
    run.styleId = remap[oldId].uint32
  storage.xRuns = normalized
  storage.xStyles = compactStyles

proc materialize*(storage: TextStorage) =
  if storage.xMaterialized:
    return
  var value = ""
  var runs: seq[TextAttributeRun]
  if not storage.xLazyProvider.isNil:
    value = storage.xLazyProvider.trySendLocal(lazyTextStorageString(), storage).get("")
    runs = storage.xLazyProvider.trySendLocal(lazyTextStorageRuns(), storage).get(@[])
  storage.setStorageString(value)
  storage.xRuns.setLen(0)
  storage.xStyles.setLen(0)
  for run in runs:
    storage.xRuns.add storage.styleRun(run.range, run.attributes)
  if storage.storageLength() > 0 and storage.xRuns.len == 0:
    storage.xRuns.add storage.styleRun(
      initTextRange(0, storage.storageLength()), defaultTextAttributes()
    )
  storage.xMaterialized = true
  storage.normalizeRuns()

proc paragraphRangeForRange*(storage: TextStorage, range: TextRange): TextRange =
  storage.materialize()
  storage.storageParagraphRange(range)

proc resolvedFontFallbackAttributes(
    storage: TextStorage, range: TextRange, attributes: TextAttributes
): TextAttributes =
  result = attributes
  if result.fontSize.isAutoMetric or result.fontSize <= 0.0'f32:
    result.fontSize = defaultFontSize()
  if result.paragraphStyle.maximumLineHeight > 0.0'f32 and
      result.paragraphStyle.minimumLineHeight > result.paragraphStyle.maximumLineHeight:
    result.paragraphStyle.maximumLineHeight = result.paragraphStyle.minimumLineHeight
  if not storage.xDelegate.isNil:
    let resolved = storage.xDelegate.trySendLocal(
      textStorageResolveFontFallback(),
      (storage: storage, range: range, attributes: result),
    )
    if resolved.isSome:
      result = resolved.get()

proc fixFontFallbackInRange*(storage: TextStorage, range: TextRange) =
  storage.materialize()
  let clamped = clampTextRange(storage.storageLength(), range)
  if clamped.length == 0:
    return

  var changed = false
  for run in storage.xRuns.mitems:
    if run.range.intersects(clamped):
      let attributes = storage.styleAttributes(run.styleId)
      let nextAttributes = storage.resolvedFontFallbackAttributes(run.range, attributes)
      if nextAttributes != attributes:
        run.styleId = storage.styleId(nextAttributes)
        changed = true
  if changed:
    storage.normalizeRuns()

proc delegateHandledAttributeFixing(storage: TextStorage, range: TextRange): bool =
  if storage.xDelegate.isNil:
    return false

  storage.xDelegate
  .trySendLocal(textStorageFixAttributes(), (storage: storage, range: range))
  .get(false)

proc shouldFixAttributes(storage: TextStorage, range: TextRange): bool =
  if storage.xDelegate.isNil:
    return true

  storage.xDelegate
  .trySendLocal(textStorageShouldFixAttributes(), (storage: storage, range: range))
  .get(true)

proc fixAttributesInRange*(storage: TextStorage, range: TextRange) =
  storage.materialize()
  let paragraphRange = storage.paragraphRangeForRange(range)
  if paragraphRange.length == 0:
    return
  if not storage.shouldFixAttributes(paragraphRange):
    return
  if storage.delegateHandledAttributeFixing(paragraphRange):
    storage.normalizeRuns()
  else:
    storage.fixFontFallbackInRange(paragraphRange)

proc processEditing*(storage: TextStorage) =
  if storage.xProcessingEditing or storage.xEditingDepth > 0 or
      not storage.xHasPendingEdit:
    return

  let edit = storage.xPendingEdit
  storage.xPendingEdit = TextStorageEdit()
  storage.xHasPendingEdit = false
  storage.xProcessingEditing = true
  storage.xLastProcessedEdit = edit
  storage.xHasLastProcessedEdit = true
  inc storage.xRevision

  storage.dispatchWillProc(edit)
  if tseAttributes in edit.kinds:
    storage.fixAttributesInRange(edit.range)
  storage.dispatchDidProc(edit)
  if tseCharacters in edit.kinds:
    storage.dispatchValue(edit)
  if tseAttributes in edit.kinds:
    storage.dispatchAttrs(edit)

  storage.xProcessingEditing = false
  if storage.xEditingDepth == 0 and storage.xHasPendingEdit:
    storage.processEditing()

proc initTextStorageFields*(
    storage: TextStorage, value = "", attributes = defaultTextAttributes()
) =
  discard storage.withProto()
  storage.xSnapshot = newTextSnapshot(value)
  storage.xMaterialized = true
  storage.xRuns.setLen(0)
  storage.xStyles.setLen(0)
  if value.runeLen > 0:
    storage.xRuns.add storage.styleRun(initTextRange(0, value.runeLen), attributes)

proc newTextStorage*(value = "", attributes = defaultTextAttributes()): TextStorage =
  result = TextStorage()
  initTextStorageFields(result, value, attributes)

proc newTextStorage*(
    value: sink string, runs: sink seq[TextAttributeRun]
): TextStorage =
  ## Creates attributed storage from complete text and precomputed attribute runs.
  ## Runs are normalized and clamped to the text length without emitting edit events.
  result = TextStorage()
  discard result.withProto()
  result.xSnapshot = newTextSnapshot(value)
  for run in runs:
    result.xRuns.add result.styleRun(run.range, run.attributes)
  result.xMaterialized = true
  if result.xSnapshot.runeLength > 0 and result.xRuns.len == 0:
    result.xRuns.add result.styleRun(
      initTextRange(0, result.xSnapshot.runeLength), defaultTextAttributes()
    )
  result.normalizeRuns()

proc initTextGapStorageFields*(
    storage: TextGapStorage, value = "", attributes = defaultTextAttributes()
) =
  discard storage.withProto()
  storage.xSnapshot = nil
  storage.xGapBuffer = initGapTextBuffer(value)
  storage.xMaterialized = true
  storage.xRuns.setLen(0)
  storage.xStyles.setLen(0)
  if value.runeLen > 0:
    storage.xRuns.add storage.styleRun(initTextRange(0, value.runeLen), attributes)

proc newTextGapStorage*(
    value = "", attributes = defaultTextAttributes()
): TextGapStorage =
  result = TextGapStorage()
  initTextGapStorageFields(result, value, attributes)

proc initGapTextStorageFields*(
    storage: TextGapStorage, value = "", attributes = defaultTextAttributes()
) =
  storage.initTextGapStorageFields(value, attributes)

proc newGapTextStorage*(
    value = "", attributes = defaultTextAttributes()
): TextGapStorage =
  newTextGapStorage(value, attributes)

proc newLazyTextStorage*(provider: DynamicAgent): TextStorage =
  result = TextStorage(xLazyProvider: provider)
  discard result.withProto()
  result.xMaterialized = provider.isNil
  if provider.isNil:
    result.xSnapshot = newTextSnapshot("")

proc newAttributedString*(
    value = "", attributes = defaultTextAttributes()
): MutableAttributedString =
  newTextStorage(value, attributes)

method newEmptyStorageCopy*(storage: TextStorage): TextStorage {.base.} =
  newTextStorage()

method newEmptyStorageCopy*(storage: TextGapStorage): TextStorage =
  newTextGapStorage()

method copyStorageTextTo*(storage: TextStorage, copy: TextStorage) {.base.} =
  copy.xSnapshot = storage.xSnapshot

method copyStorageTextTo*(storage: TextGapStorage, copy: TextStorage) =
  let gapCopy = TextGapStorage(copy)
  gapCopy.xGapBuffer = storage.xGapBuffer.copyGapTextBuffer()
  gapCopy.xSnapshot = storage.xSnapshot

proc copyTextStorage*(storage: TextStorage): TextStorage =
  storage.materialize()
  result = storage.newEmptyStorageCopy()
  storage.copyStorageTextTo(result)
  result.xRuns = storage.xRuns
  result.xStyles = storage.xStyles
  result.xMaterialized = true

method sameStorageText*(storage, other: TextStorage): bool {.base.} =
  ## Compares values without making whole-text strings for gap-backed storage.
  storage.storageSnapshot().bytes == other.storageSnapshot().bytes

method sameStorageText*(storage: TextGapStorage, other: TextStorage): bool =
  if other of TextGapStorage:
    storage.xGapBuffer.sameText(TextGapStorage(other).xGapBuffer)
  else:
    storage.storageString() == other.storageString()

proc shouldRecordUndo(storage: TextStorage): bool =
  let manager = storage.undoManager()
  not manager.isNil and manager.isUndoRegistrationEnabled()

proc undoSnapshot(storage: TextStorage): TextStorage =
  if storage.shouldRecordUndo():
    result = storage.copyTextStorage()

proc registerSnapshotUndo(
    storage: TextStorage, snapshot: TextStorage, actionName: string
) =
  let manager = storage.undoManager()
  if manager.isNil or not manager.isUndoRegistrationEnabled() or snapshot.isNil:
    return
  manager.registerUndo(
    proc() =
      storage.applySnapshot(snapshot, actionName),
    actionName,
  )

proc applySnapshot(storage: TextStorage, snapshot: TextStorage, actionName: string) =
  if snapshot.isNil:
    return
  storage.materialize()
  snapshot.materialize()
  let
    before = storage.undoSnapshot()
    oldLength = storage.storageLength()
    newLength = snapshot.storageLength()
    edit = initTextStorageEdit(
      initTextRange(0, oldLength),
      newLength,
      newLength - oldLength,
      {tseCharacters, tseAttributes},
    )
  storage.registerSnapshotUndo(before, actionName)
  storage.dispatchWillEdit(edit)
  storage.restoreStorageText(snapshot)
  storage.xRuns = snapshot.xRuns
  storage.xStyles = snapshot.xStyles
  storage.xMaterialized = true
  storage.normalizeRuns()
  storage.notifyCommittedEdit(edit)

proc mutableCopy*(storage: AttributedString): MutableAttributedString =
  storage.copyTextStorage()

proc sliceTextStorage*(storage: TextStorage, range: TextRange): TextStorage =
  result = newTextStorage()
  storage.materialize()
  let
    clamped = clampTextRange(storage.storageLength(), range)
    start = int(clamped.location)
    stop = clamped.maxIndex
  result.xSnapshot = newTextSnapshot(storage.storageSubstring(clamped))
  for run in storage.xRuns:
    let
      runStart = int(run.range.location)
      runStop = run.range.maxIndex
      overlapStart = max(start, runStart)
      overlapStop = min(stop, runStop)
    if overlapStop > overlapStart:
      result.xRuns.add result.styleRun(
        initTextRange(overlapStart - start, overlapStop - overlapStart),
        storage.styleAttributes(run.styleId),
      )
  result.normalizeRuns()

proc attributedSubstring*(
    storage: AttributedString, range: TextRange
): AttributedString =
  storage.sliceTextStorage(range)

proc stringValue*(storage: TextStorage): string =
  storage.materialize()
  storage.storageString()

proc `stringValue=`*(storage: TextStorage, value: string) =
  storage.materialize()
  let before = storage.undoSnapshot()
  let oldLength = storage.storageLength()
  let edit = initTextStorageEdit(
    initTextRange(0, oldLength),
    value.runeLen,
    value.runeLen - oldLength,
    {tseCharacters, tseAttributes},
  )
  storage.registerSnapshotUndo(before, "Set Text")
  storage.dispatchWillEdit(edit)
  storage.setStorageString(value)
  storage.xRuns.setLen(0)
  storage.xStyles.setLen(0)
  if value.runeLen > 0:
    storage.xRuns.add storage.styleRun(
      initTextRange(0, value.runeLen), defaultTextAttributes()
    )
  storage.notifyCommittedEdit(edit)

proc len*(storage: TextStorage): int =
  storage.materialize()
  storage.storageLength()

proc substring*(storage: TextStorage, range: TextRange): string =
  storage.materialize()
  let clamped = clampTextRange(storage.len, range)
  storage.storageSubstring(clamped)

proc lineCount*(storage: TextStorage): int =
  storage.materialize()
  storage.storageLineCount()

proc lineRange*(storage: TextStorage, line: int): TextRange =
  storage.materialize()
  storage.storageLineRange(line)

proc attributesAt*(storage: TextStorage, index: int): TextAttributes =
  storage.materialize()
  let total = storage.len
  if total == 0:
    return defaultTextAttributes()
  let clamped = max(0, min(index, total - 1))
  for run in storage.xRuns:
    if clamped >= int(run.range.location) and clamped < run.range.maxIndex:
      return storage.styleAttributes(run.styleId)
  defaultTextAttributes()

proc attributesAtIndex*(storage: AttributedString, index: int): TextAttributes =
  storage.attributesAt(index)

proc attributeRuns*(storage: AttributedString): seq[TextAttributeRun] =
  if storage.isNil:
    return
  storage.materialize()
  for run in storage.xRuns:
    result.add TextAttributeRun(
      range: run.range, attributes: storage.styleAttributes(run.styleId)
    )

proc replace*(
    storage: TextStorage,
    range: TextRange,
    text: string,
    attributes = defaultTextAttributes(),
) =
  storage.materialize()
  let
    total = storage.len
    clamped = clampTextRange(total, range)
    replaceStart = int(clamped.location)
    replaceStop = clamped.maxIndex
    insertedLength = text.runeLen
    delta = insertedLength - int(clamped.length)
    edit = initTextStorageEdit(clamped, insertedLength, delta, {tseCharacters})
    before = storage.undoSnapshot()

  storage.registerSnapshotUndo(before, "Edit Text")
  storage.dispatchWillEdit(edit)
  storage.replaceStorageText(clamped, text)

  var nextRuns: seq[TextStyleRun]
  for run in storage.xRuns:
    let
      runStart = int(run.range.location)
      runStop = run.range.maxIndex
    if runStop <= replaceStart:
      nextRuns.add run
    elif runStart >= replaceStop:
      nextRuns.add TextStyleRun(
        range: initTextRange(runStart + delta, int(run.range.length)),
        styleId: run.styleId,
      )
    else:
      if runStart < replaceStart:
        nextRuns.add TextStyleRun(
          range: initTextRange(runStart, replaceStart - runStart), styleId: run.styleId
        )
      if runStop > replaceStop:
        nextRuns.add TextStyleRun(
          range: initTextRange(replaceStart + insertedLength, runStop - replaceStop),
          styleId: run.styleId,
        )

  if insertedLength > 0:
    nextRuns.add storage.styleRun(
      initTextRange(replaceStart, insertedLength), attributes
    )
  storage.xRuns = nextRuns
  storage.normalizeRuns()
  storage.notifyCommittedEdit(edit)

proc replaceCharacters*(
    storage: MutableAttributedString,
    range: TextRange,
    text: string,
    attributes = defaultTextAttributes(),
) =
  storage.replace(range, text, attributes)

proc setAttributeRanges*(
  storage: TextStorage,
  range: TextRange,
  baseAttributes: TextAttributes,
  overlays: openArray[TextAttributeRun],
)

proc setAttributes*(
    storage: TextStorage, range: TextRange, attributes: TextAttributes
) =
  storage.setAttributeRanges(range, attributes, [])

proc applyAttributeRanges(
    storage: TextStorage,
    range: TextRange,
    baseAttributes: TextAttributes,
    overlays: openArray[TextAttributeRun],
    recordUndo: bool,
) =
  storage.materialize()
  let
    total = storage.len
    clamped = clampTextRange(total, range)
    start = int(clamped.location)
    stop = clamped.maxIndex
  if clamped.length == 0:
    return
  let before =
    if recordUndo:
      storage.undoSnapshot()
    else:
      nil
  let edit = initTextStorageEdit(clamped, int(clamped.length), 0, {tseAttributes})

  storage.registerSnapshotUndo(before, "Set Attributes")
  storage.dispatchWillEdit(edit)
  var nextRuns: seq[TextStyleRun]
  for run in storage.xRuns:
    let
      runStart = int(run.range.location)
      runStop = run.range.maxIndex
    if runStop <= start or runStart >= stop:
      nextRuns.add run
    else:
      if runStart < start:
        nextRuns.add TextStyleRun(
          range: initTextRange(runStart, start - runStart), styleId: run.styleId
        )
      if runStop > stop:
        nextRuns.add TextStyleRun(
          range: initTextRange(stop, runStop - stop), styleId: run.styleId
        )
  type AttributeOverlay = object
    start, stop, order: int
    styleId: uint32

  var
    changes: seq[AttributeOverlay]
    boundaries = @[start, stop]
    interned: seq[tuple[attributes: TextAttributes, id: uint32]]
  let baseId = storage.styleId(baseAttributes)
  interned.add (baseAttributes, baseId)
  for index, overlay in overlays:
    let affected = clampTextRange(total, overlay.range)
    let
      first = max(start, int(affected.location))
      last = min(stop, affected.maxIndex)
    if last <= first:
      continue
    var id = uint32.high
    for item in interned:
      if item.attributes == overlay.attributes:
        id = item.id
        break
    if id == uint32.high:
      id = storage.styleId(overlay.attributes)
      interned.add (overlay.attributes, id)
    changes.add AttributeOverlay(start: first, stop: last, order: index, styleId: id)
    boundaries.add first
    boundaries.add last
  changes.sort(
    proc(a, b: AttributeOverlay): int =
      cmp(a.start, b.start)
  )
  boundaries.sort()
  var
    nextChange = 0
    active: HeapQueue[tuple[priority, stop: int, styleId: uint32]]
  for index in 0 ..< boundaries.high:
    let first = boundaries[index]
    let last = boundaries[index + 1]
    if last <= first:
      continue
    while nextChange < changes.len and changes[nextChange].start <= first:
      let item = changes[nextChange]
      active.push((-item.order, item.stop, item.styleId))
      inc nextChange
    while active.len > 0 and active[0].stop <= first:
      discard active.pop()
    let id =
      if active.len > 0:
        active[0].styleId
      else:
        baseId
    nextRuns.add TextStyleRun(range: initTextRange(first, last - first), styleId: id)
  storage.xRuns = nextRuns
  storage.normalizeRuns()
  storage.notifyCommittedEdit(edit)

proc setAttributeRanges*(
    storage: TextStorage,
    range: TextRange,
    baseAttributes: TextAttributes,
    overlays: openArray[TextAttributeRun],
) =
  ## Applies a base style and ordered overrides in one edit. Later overrides win.
  ## Existing styles outside `range` are retained. Style IDs remain valid until
  ## the next storage edit, as with `styledSpans`.
  storage.applyAttributeRanges(range, baseAttributes, overlays, true)

proc setAttributesForRange*(
    storage: MutableAttributedString, range: TextRange, attributes: TextAttributes
) =
  storage.setAttributes(range, attributes)

proc addAttributes*(
    storage: MutableAttributedString, range: TextRange, attributes: TextAttributes
) =
  storage.setAttributes(range, attributes)

proc removeAttributes*(storage: MutableAttributedString, range: TextRange) =
  storage.setAttributes(range, defaultTextAttributes())

proc setParagraphStyle*(
    storage: MutableAttributedString,
    range: TextRange,
    paragraphStyle: TextParagraphStyle,
) =
  if storage.isNil:
    return
  var attributes = storage.attributesAt(int(range.location))
  attributes.paragraphStyle = paragraphStyle
  storage.setAttributes(range, attributes)

proc replace*(storage: TextStorage, range: TextRange, inserted: TextStorage) =
  if inserted.isNil:
    storage.replace(range, "")
    return
  storage.materialize()
  inserted.materialize()
  let
    clamped = clampTextRange(storage.len, range)
    start = int(clamped.location)
  storage.beginEditing()
  try:
    storage.replace(clamped, inserted.stringValue())
    var overlays: seq[TextAttributeRun]
    for run in inserted.xRuns:
      overlays.add TextAttributeRun(
        range: initTextRange(start + int(run.range.location), int(run.range.length)),
        attributes: inserted.styleAttributes(run.styleId),
      )
    storage.applyAttributeRanges(
      initTextRange(start, inserted.len), defaultTextAttributes(), overlays, false
    )
  finally:
    storage.endEditing()

proc replaceCharacters*(
    storage: MutableAttributedString, range: TextRange, inserted: AttributedString
) =
  storage.replace(range, inserted)

proc insertAttributedString*(
    storage: MutableAttributedString, index: int, inserted: AttributedString
) =
  storage.replace(initTextRange(index, 0), inserted)

iterator runs*(storage: TextStorage): TextAttributeRun =
  if not storage.isNil:
    storage.materialize()
    for run in storage.xRuns:
      yield TextAttributeRun(
        range: run.range, attributes: storage.styleAttributes(run.styleId)
      )

proc textSnapshot*(storage: TextStorage): TextSnapshot =
  ## Returns a stable snapshot. Editing storage creates a new snapshot.
  if storage.isNil:
    return newTextSnapshot("")
  storage.materialize()
  storage.storageSnapshot()

iterator styledSpans*(storage: TextStorage): TextStyledSpan =
  ## Span style IDs refer to this storage's style table until its next edit.
  if not storage.isNil:
    storage.materialize()
    let source = storage.textSnapshot()
    for run in storage.xRuns:
      let range = clampTextRange(source.runeLength, run.range)
      yield TextStyledSpan(
        source: source,
        byteStart: source.byteOffset(int(range.location)),
        byteEnd: source.byteOffset(range.maxIndex),
        runeStart: int(range.location),
        runeEnd: range.maxIndex,
        styleId: run.styleId,
      )

iterator styledRuns*(
    storage: TextStorage
): tuple[attributes: TextAttributes, text: string] =
  if not storage.isNil:
    storage.materialize()
    for span in storage.styledSpans():
      yield (
        storage.styleAttributes(span.styleId),
        span.source.bytes[span.byteStart ..< span.byteEnd],
      )
