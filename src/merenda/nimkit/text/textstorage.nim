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
    displayOnly*: bool
      ## Attribute edits whose only changes are colors. False is conservative:
      ## externally reported edits and edits requiring attribute fixing reflow.

  TextStyleRun = object
    range: TextRange
    styleId: uint32

  TextStyleRuns = object
    # The suffix is reversed. Rune lookups can binary search either side while
    # successive streamed edits move only the runs between changed ranges.
    before, after: seq[TextStyleRun]

  TextStyledSpan* = object
    source*: TextSnapshot
    byteStart*: int
    byteEnd*: int
    runeStart*: int
    runeEnd*: int
    styleId*: uint32

  TextStorage* = ref object of DynamicAgent
    xSnapshot: TextSnapshot
    xRuns: TextStyleRuns
    xStyles: seq[TextAttributes]
    xStyleUses: seq[int] # Stored run counts; -1 marks a reclaimed style slot.
    xFreeStyles: seq[uint32]
    xUnusedStyles: seq[uint32] # New or released styles to check after a splice.
    xOverlappingRuns: bool
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

func len(runs: TextStyleRuns): int {.inline.} =
  runs.before.len + runs.after.len

func `[]`(runs: TextStyleRuns, index: int): TextStyleRun {.inline.} =
  if index < runs.before.len:
    runs.before[index]
  else:
    runs.after[runs.after.len - 1 - (index - runs.before.len)]

iterator items(runs: TextStyleRuns): TextStyleRun =
  for run in runs.before:
    yield run
  for index in countdown(runs.after.high, 0):
    yield runs.after[index]

iterator mitems(runs: var TextStyleRuns): var TextStyleRun =
  for run in runs.before.mitems:
    yield run
  for index in countdown(runs.after.high, 0):
    yield runs.after[index]

proc moveGap(runs: var TextStyleRuns, index: int) =
  while runs.before.len > index:
    runs.after.add runs.before.pop()
  while runs.before.len < index:
    runs.before.add runs.after.pop()

proc add(runs: var TextStyleRuns, run: TextStyleRun) =
  runs.moveGap(runs.len)
  runs.before.add run

proc clear(runs: var TextStyleRuns) =
  runs.before.setLen(0)
  runs.after.setLen(0)

proc replace(
    runs: var TextStyleRuns, first, last: int, replacement: openArray[TextStyleRun]
) =
  runs.moveGap(first)
  runs.after.setLen(runs.after.len - (last - first))
  runs.before.add replacement

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
  result = initTextStorageEdit(
    initTextRange(start, oldLength), max(oldLength + delta, 0), delta, a.kinds + b.kinds
  )
  result.displayOnly = a.displayOnly and b.displayOnly

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
    if storage.xStyleUses[index] >= 0 and existing == attributes:
      return index.uint32
  if storage.xFreeStyles.len > 0:
    result = storage.xFreeStyles.pop()
    storage.xStyles[int(result)] = attributes
    storage.xStyleUses[int(result)] = 0
  else:
    result = storage.xStyles.len.uint32
    storage.xStyles.add attributes
    storage.xStyleUses.add 0
  storage.xUnusedStyles.add result

proc clearStyles(storage: TextStorage) =
  storage.xStyles.setLen(0)
  storage.xStyleUses.setLen(0)
  storage.xFreeStyles.setLen(0)
  storage.xUnusedStyles.setLen(0)

proc reclaimUnusedStyles(storage: TextStorage) =
  for id in storage.xUnusedStyles:
    if storage.xStyleUses[int(id)] == 0:
      storage.xStyles[int(id)] = TextAttributes()
      storage.xStyleUses[int(id)] = -1
      storage.xFreeStyles.add id
  storage.xUnusedStyles.setLen(0)

proc styleRun(
    storage: TextStorage, range: TextRange, attributes: TextAttributes
): TextStyleRun =
  TextStyleRun(range: range, styleId: storage.styleId(attributes))

func styleAttributes*(storage: TextStorage, styleId: uint32): TextAttributes =
  storage.xStyles[int(styleId)]

proc normalizeRuns(storage: TextStorage) =
  storage.xOverlappingRuns = false
  let total = storage.storageLength()
  if total == 0:
    storage.xRuns.clear()
    storage.clearStyles()
    return

  var sorted = newSeqOfCap[TextStyleRun](storage.xRuns.len)
  for run in storage.xRuns:
    sorted.add run
  sorted.sort(
    proc(a, b: TextStyleRun): int =
      cmp(int(a.range.location), int(b.range.location))
  )

  var normalized: seq[TextStyleRun]
  for run in sorted:
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
  var styleUses: seq[int]
  var remap = newSeq[int](storage.xStyles.len)
  for index in 0 ..< remap.len:
    remap[index] = -1
  var previousStop = 0
  for run in normalized.mitems:
    if int(run.range.location) < previousStop:
      storage.xOverlappingRuns = true
    previousStop = max(previousStop, run.range.maxIndex)
    let oldId = int(run.styleId)
    if remap[oldId] < 0:
      remap[oldId] = compactStyles.len
      compactStyles.add storage.xStyles[oldId]
      styleUses.add 0
    run.styleId = remap[oldId].uint32
    inc styleUses[int(run.styleId)]
  storage.xRuns = TextStyleRuns(before: normalized)
  storage.xStyles = compactStyles
  storage.xStyleUses = styleUses
  storage.xFreeStyles.setLen(0)
  storage.xUnusedStyles.setLen(0)

proc materialize*(storage: TextStorage) =
  if storage.xMaterialized:
    return
  var value = ""
  var runs: seq[TextAttributeRun]
  if not storage.xLazyProvider.isNil:
    value = storage.xLazyProvider.trySendLocal(lazyTextStorageString(), storage).get("")
    runs = storage.xLazyProvider.trySendLocal(lazyTextStorageRuns(), storage).get(@[])
  storage.setStorageString(value)
  storage.xRuns.clear()
  storage.clearStyles()
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

  var edit = storage.xPendingEdit
  if not storage.xDelegate.isNil:
    # Delegate attribute fixing can change metrics even after a color edit.
    edit.displayOnly = false
  storage.xPendingEdit = TextStorageEdit()
  storage.xHasPendingEdit = false
  storage.xProcessingEditing = true
  storage.xLastProcessedEdit = edit
  storage.xHasLastProcessedEdit = true
  inc storage.xRevision

  storage.dispatchWillProc(edit)
  if tseAttributes in edit.kinds and not edit.displayOnly:
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
  storage.xOverlappingRuns = false
  storage.xRuns.clear()
  storage.clearStyles()
  if value.runeLen > 0:
    storage.xRuns.add storage.styleRun(initTextRange(0, value.runeLen), attributes)
    storage.xStyleUses[0] = 1
    storage.xUnusedStyles.setLen(0)

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
  storage.xOverlappingRuns = false
  storage.xRuns.clear()
  storage.clearStyles()
  if value.runeLen > 0:
    storage.xRuns.add storage.styleRun(initTextRange(0, value.runeLen), attributes)
    storage.xStyleUses[0] = 1
    storage.xUnusedStyles.setLen(0)

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
  result.xStyleUses = storage.xStyleUses
  result.xFreeStyles = storage.xFreeStyles
  result.xUnusedStyles = storage.xUnusedStyles
  result.xOverlappingRuns = storage.xOverlappingRuns
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
  storage.xStyleUses = snapshot.xStyleUses
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
  storage.xRuns.clear()
  storage.clearStyles()
  storage.xOverlappingRuns = false
  if value.runeLen > 0:
    storage.xRuns.add storage.styleRun(
      initTextRange(0, value.runeLen), defaultTextAttributes()
    )
    storage.xStyleUses[0] = 1
    storage.xUnusedStyles.setLen(0)
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

func firstStyleRunAfter(storage: TextStorage, index: int): int =
  if storage.xOverlappingRuns:
    # Precomputed storage can contain overlaps. Preserve the first matching
    # run's precedence when its endpoints cannot be binary searched.
    while result < storage.xRuns.len and storage.xRuns[result].range.maxIndex <= index:
      inc result
    return
  var high = storage.xRuns.len
  while result < high:
    let middle = (result + high) div 2
    if storage.xRuns[middle].range.maxIndex <= index:
      result = middle + 1
    else:
      high = middle

func firstStyleRunStartingAt(storage: TextStorage, index: int): int =
  var high = storage.xRuns.len
  while result < high:
    let middle = (result + high) div 2
    if int(storage.xRuns[middle].range.location) < index:
      result = middle + 1
    else:
      high = middle

iterator runs*(storage: TextStorage, range: TextRange): TextAttributeRun =
  ## Stored runs intersecting `range`, in source order, with their original
  ## (unclipped) ranges. Disjoint runs use indexed lookup; overlapping precomputed
  ## runs retain their order.
  if not storage.isNil:
    storage.materialize()
    let clamped = clampTextRange(storage.storageLength(), range)
    if clamped.length > 0:
      var index = storage.firstStyleRunAfter(int(clamped.location))
      while index < storage.xRuns.len and
          int(storage.xRuns[index].range.location) < clamped.maxIndex:
        let run = storage.xRuns[index]
        if run.range.maxIndex > int(clamped.location):
          yield TextAttributeRun(
            range: run.range, attributes: storage.styleAttributes(run.styleId)
          )
        inc index

proc attributeRunAt*(storage: TextStorage, index: int): TextAttributeRun =
  ## Returns the attributes and effective rune range at the clamped index.
  ## Gaps between stored runs use the default attributes. The returned range
  ## lets renderers reuse a lookup while walking neighboring source glyphs.
  storage.materialize()
  let total = storage.len
  if total == 0:
    return TextAttributeRun(attributes: defaultTextAttributes())
  let
    clamped = max(0, min(index, total - 1))
    position = storage.firstStyleRunAfter(clamped)
  var previousStop =
    if position > 0:
      storage.xRuns[position - 1].range.maxIndex
    else:
      0
  if storage.xOverlappingRuns:
    for index in 0 ..< position:
      previousStop = max(previousStop, storage.xRuns[index].range.maxIndex)
  if position < storage.xRuns.len:
    let run = storage.xRuns[position]
    if int(run.range.location) <= clamped:
      let first = max(previousStop, int(run.range.location))
      return TextAttributeRun(
        range: initTextRange(first, run.range.maxIndex - first),
        attributes: storage.styleAttributes(run.styleId),
      )
  let stop =
    if position < storage.xRuns.len:
      int(storage.xRuns[position].range.location)
    else:
      total
  TextAttributeRun(
    range: initTextRange(previousStop, stop - previousStop),
    attributes: defaultTextAttributes(),
  )

proc attributesAt*(storage: TextStorage, index: int): TextAttributes =
  storage.attributeRunAt(index).attributes

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
  storage.xRuns = TextStyleRuns(before: nextRuns)
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

func sameLayoutAttributes(a, b: TextAttributes): bool =
  for name, left, right in fieldPairs(a, b):
    when name notin ["foregroundColor", "backgroundColor", "lineBackgroundColor"]:
      if left != right:
        return false
  true

proc addNormalized(runs: var seq[TextStyleRun], run: TextStyleRun) =
  if runs.len > 0 and runs[^1].styleId == run.styleId and
      runs[^1].range.maxIndex == int(run.range.location):
    runs[^1].range.length += run.range.length
  else:
    runs.add run

proc replaceAttributeRuns(
    storage: TextStorage, range: TextRange, replacement: openArray[TextStyleRun]
) =
  let
    start = int(range.location)
    stop = range.maxIndex
  if storage.xOverlappingRuns:
    # Precomputed overlapping runs cannot be locally spliced by their end
    # positions. Keep their historical precedence and normalize this uncommon
    # representation using the complete table.
    var updated: seq[TextStyleRun]
    for run in storage.xRuns:
      let
        first = int(run.range.location)
        last = run.range.maxIndex
      if last <= start or first >= stop:
        updated.add run
      else:
        if first < start:
          updated.add TextStyleRun(
            range: initTextRange(first, start - first), styleId: run.styleId
          )
        if last > stop:
          updated.add TextStyleRun(
            range: initTextRange(stop, last - stop), styleId: run.styleId
          )
    updated.add replacement
    storage.xRuns = TextStyleRuns(before: updated)
    storage.normalizeRuns()
  else:
    var
      first = storage.firstStyleRunAfter(start)
      last = storage.firstStyleRunStartingAt(stop)
      updated = newSeqOfCap[TextStyleRun](replacement.len + 2)
    if first < last:
      let run = storage.xRuns[first]
      if int(run.range.location) < start:
        updated.add TextStyleRun(
          range: initTextRange(int(run.range.location), start - int(run.range.location)),
          styleId: run.styleId,
        )
    for run in replacement:
      updated.addNormalized(run)
    if first < last:
      let run = storage.xRuns[last - 1]
      if run.range.maxIndex > stop:
        updated.addNormalized(
          TextStyleRun(
            range: initTextRange(stop, run.range.maxIndex - stop), styleId: run.styleId
          )
        )
    if first > 0:
      let previous = storage.xRuns[first - 1]
      if previous.range.maxIndex == int(updated[0].range.location) and
          previous.styleId == updated[0].styleId:
        updated[0].range.location = previous.range.location
        updated[0].range.length += previous.range.length
        dec first
    if last < storage.xRuns.len:
      let following = storage.xRuns[last]
      if updated[^1].range.maxIndex == int(following.range.location) and
          updated[^1].styleId == following.styleId:
        updated[^1].range.length += following.range.length
        inc last
    for run in updated:
      inc storage.xStyleUses[int(run.styleId)]
    for index in first ..< last:
      let id = storage.xRuns[index].styleId
      dec storage.xStyleUses[int(id)]
      if storage.xStyleUses[int(id)] == 0:
        storage.xUnusedStyles.add id
    storage.xRuns.replace(first, last, updated)
    storage.reclaimUnusedStyles()

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
  var edit = initTextStorageEdit(clamped, int(clamped.length), 0, {tseAttributes})
  edit.displayOnly = storage.xDelegate.isNil
  var nextRuns: seq[TextStyleRun]
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
    previousRun = storage.firstStyleRunAfter(start)
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
    # Compare effective styles, including overlapping overlays and gaps. Walk
    # the old runs once rather than comparing every old run with every overlay.
    var position = first
    while edit.displayOnly and position < last:
      while previousRun < storage.xRuns.len and
          storage.xRuns[previousRun].range.maxIndex <= position:
        inc previousRun
      var stop = last
      var previousAttributes = defaultTextAttributes()
      if previousRun < storage.xRuns.len:
        let previous = storage.xRuns[previousRun]
        if int(previous.range.location) <= position:
          previousAttributes = storage.styleAttributes(previous.styleId)
          stop = min(stop, previous.range.maxIndex)
        else:
          stop = min(stop, int(previous.range.location))
      edit.displayOnly =
        sameLayoutAttributes(previousAttributes, storage.xStyles[int(id)])
      position = stop
    nextRuns.addNormalized(
      TextStyleRun(range: initTextRange(first, last - first), styleId: id)
    )
  storage.registerSnapshotUndo(before, "Set Attributes")
  storage.dispatchWillEdit(edit)
  storage.replaceAttributeRuns(clamped, nextRuns)
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

proc overlayAttributeRanges*(
    storage: TextStorage, overlays: openArray[TextAttributeRun]
) =
  ## Replaces styles under the given rune ranges, preserving styles and default
  ## gaps between them. Later entries win; input ranges may be unsorted. Emits
  ## one attribute edit and records one undo operation for the affected interval.
  storage.materialize()
  let total = storage.storageLength()
  var
    first = total
    stop = 0
  for overlay in overlays:
    let affected = clampTextRange(total, overlay.range)
    if affected.length > 0:
      first = min(first, int(affected.location))
      stop = max(stop, affected.maxIndex)
  if stop <= first:
    return
  let affected = initTextRange(first, stop - first)
  var preserved: seq[TextAttributeRun]
  for run in storage.runs(affected):
    preserved.add run
  if storage.xOverlappingRuns:
    # Attribute lookup gives earlier precomputed runs precedence. The batch
    # setter gives later overlays precedence, so reverse only these old runs.
    preserved.reverse()
  preserved.add overlays
  storage.setAttributeRanges(affected, defaultTextAttributes(), preserved)

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
