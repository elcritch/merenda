import std/[algorithm, options, unicode]

import sigils/core
import sigils/selectors
import ../foundation/undomanagers
import ../foundation/types
import ./gaptextbuffers
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

  TextStorage* = ref object of DynamicAgent
    xStringValue: string
    xGapBuffer: GapTextBuffer
    xUsesGapBuffer: bool
    xRuns: seq[TextAttributeRun]
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

  AttributedString* = TextStorage
  MutableAttributedString* = TextStorage

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
  not storage.isNil and storage.xHasPendingEdit

proc currentEdit*(storage: TextStorage): TextStorageEdit =
  if storage.isNil:
    return
  if storage.xHasPendingEdit: storage.xPendingEdit else: storage.xLastProcessedEdit

proc editedMask*(storage: TextStorage): TextStorageEditKinds =
  storage.currentEdit().kinds

proc editedRange*(storage: TextStorage): TextRange =
  storage.currentEdit().range

proc changeInLength*(storage: TextStorage): int =
  storage.currentEdit().textDelta

proc delegate*(storage: TextStorage): DynamicAgent =
  if storage.isNil: nil else: storage.xDelegate

proc `delegate=`*(storage: TextStorage, delegate: DynamicAgent) =
  if not storage.isNil:
    storage.xDelegate = delegate

proc undoManager*(storage: TextStorage): UndoManager =
  if storage.isNil: nil else: storage.xUndoManager

proc `undoManager=`*(storage: TextStorage, undoManager: UndoManager) =
  if not storage.isNil:
    storage.xUndoManager = undoManager

proc lazyProvider*(storage: TextStorage): DynamicAgent =
  if storage.isNil: nil else: storage.xLazyProvider

proc `lazyProvider=`*(storage: TextStorage, provider: DynamicAgent) =
  if storage.isNil:
    return
  storage.xLazyProvider = provider
  storage.xMaterialized = provider.isNil

proc isMaterialized*(storage: TextStorage): bool =
  storage.isNil or storage.xMaterialized

proc usesGapTextBuffer*(storage: TextStorage): bool =
  (not storage.isNil) and storage.xUsesGapBuffer

proc backingLength(storage: TextStorage): int =
  if storage.xUsesGapBuffer: storage.xGapBuffer.len else: storage.xStringValue.runeLen

proc backingStringValue(storage: TextStorage): string =
  if storage.xUsesGapBuffer:
    storage.xGapBuffer.stringValue()
  else:
    storage.xStringValue

proc setBackingStringValue(storage: TextStorage, value: string) =
  if storage.xUsesGapBuffer:
    storage.xGapBuffer.setText(value)
    storage.xStringValue.setLen(0)
  else:
    storage.xStringValue = value

proc backingSubstring(storage: TextStorage, range: TextRange): string =
  if storage.xUsesGapBuffer:
    storage.xGapBuffer.substring(range)
  else:
    storage.xStringValue.runeSubStr(int(range.location), int(range.length))

proc replaceBackingText(storage: TextStorage, range: TextRange, text: string) =
  if storage.xUsesGapBuffer:
    storage.xGapBuffer.replace(range, text)
    storage.xStringValue.setLen(0)
  else:
    let
      replaceStart = int(range.location)
      replaceStop = range.maxIndex
      current = storage.xStringValue
    storage.xStringValue =
      current.runeSubStr(0, replaceStart) & text & current.runeSubStr(replaceStop)

proc backingLineCount(storage: TextStorage): int =
  if storage.xUsesGapBuffer:
    result = storage.xGapBuffer.lineCount()
  else:
    result = 1
    for item in storage.xStringValue.runes:
      if item == Rune('\n'):
        inc result

proc backingLineRange(storage: TextStorage, line: int): TextRange =
  if storage.xUsesGapBuffer:
    return storage.xGapBuffer.lineRange(line)

  let
    runes = storage.xStringValue.toRunes()
    targetLine = max(line, 0)
  var
    currentLine = 0
    start = 0
    index = 0
  while index < runes.len and currentLine < targetLine:
    if runes[index] == Rune('\n'):
      inc currentLine
      start = index + 1
    inc index

  if currentLine < targetLine:
    return initTextRange(runes.len, 0)

  var stop = start
  while stop < runes.len and runes[stop] != Rune('\n'):
    inc stop
  if stop < runes.len and runes[stop] == Rune('\n'):
    inc stop
  initTextRange(start, stop - start)

proc backingParagraphRange(storage: TextStorage, range: TextRange): TextRange =
  if storage.xUsesGapBuffer:
    storage.xGapBuffer.paragraphRange(range)
  else:
    let
      runes = storage.xStringValue.toRunes()
      clamped = clampTextRange(runes.len, range)
    if runes.len == 0:
      return initTextRange(0, 0)

    var start = min(int(clamped.location), runes.len)
    while start > 0 and runes[start - 1] != Rune('\n'):
      dec start

    var stop = min(max(clamped.maxIndex, start), runes.len)
    if stop < runes.len and clamped.length == 0 and stop == start:
      discard
    while stop < runes.len and runes[stop] != Rune('\n'):
      inc stop
    if stop < runes.len and runes[stop] == Rune('\n'):
      inc stop
    initTextRange(start, stop - start)

proc notifyCommittedEdit(storage: TextStorage, edit: TextStorageEdit) =
  if storage.isNil:
    return
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
  if storage.isNil:
    return
  storage.materialize()
  let
    clamped = clampTextRange(storage.backingLength(), range)
    replacementLength = max(int(clamped.length) + changeInLength, 0)
  storage.notifyCommittedEdit(
    initTextStorageEdit(clamped, replacementLength, changeInLength, kinds)
  )

proc beginEditing*(storage: TextStorage) =
  if not storage.isNil:
    inc storage.xEditingDepth

proc endEditing*(storage: TextStorage) =
  if storage.isNil or storage.xEditingDepth == 0:
    return
  dec storage.xEditingDepth
  if storage.xEditingDepth == 0:
    storage.processEditing()

proc normalizeRuns(storage: TextStorage) =
  if storage.isNil:
    return
  let total = storage.backingLength()
  if total == 0:
    storage.xRuns.setLen(0)
    return

  storage.xRuns.sort(
    proc(a, b: TextAttributeRun): int =
      cmp(int(a.range.location), int(b.range.location))
  )

  var normalized: seq[TextAttributeRun]
  for run in storage.xRuns:
    let clamped = clampTextRange(total, run.range)
    if clamped.length == 0:
      discard
    elif normalized.len > 0 and normalized[^1].attributes == run.attributes and
        normalized[^1].range.maxIndex == int(clamped.location):
      normalized[^1].range.length =
        (int(normalized[^1].range.length) + int(clamped.length)).Natural
    else:
      normalized.add TextAttributeRun(range: clamped, attributes: run.attributes)

  if normalized.len == 0:
    normalized.add TextAttributeRun(
      range: initTextRange(0, total), attributes: defaultTextAttributes()
    )
  storage.xRuns = normalized

proc materialize*(storage: TextStorage) =
  if storage.isNil or storage.xMaterialized:
    return
  var value = ""
  var runs: seq[TextAttributeRun]
  if not storage.xLazyProvider.isNil:
    value = storage.xLazyProvider.trySendLocal(lazyTextStorageString(), storage).get("")
    runs = storage.xLazyProvider.trySendLocal(lazyTextStorageRuns(), storage).get(@[])
  storage.setBackingStringValue(value)
  storage.xRuns = runs
  if storage.backingLength() > 0 and storage.xRuns.len == 0:
    storage.xRuns.add TextAttributeRun(
      range: initTextRange(0, storage.backingLength()),
      attributes: defaultTextAttributes(),
    )
  storage.xMaterialized = true
  storage.normalizeRuns()

proc paragraphRangeForRange*(storage: TextStorage, range: TextRange): TextRange =
  if storage.isNil:
    return
  storage.materialize()
  storage.backingParagraphRange(range)

proc resolvedFontFallbackAttributes(
    storage: TextStorage, range: TextRange, attributes: TextAttributes
): TextAttributes =
  result = attributes
  if result.fontSize.isAutoMetric or result.fontSize <= 0.0'f32:
    result.fontSize = defaultFontSize()
  if result.paragraphStyle.maximumLineHeight > 0.0'f32 and
      result.paragraphStyle.minimumLineHeight > result.paragraphStyle.maximumLineHeight:
    result.paragraphStyle.maximumLineHeight = result.paragraphStyle.minimumLineHeight
  if not storage.isNil and not storage.xDelegate.isNil:
    let resolved = storage.xDelegate.trySendLocal(
      textStorageResolveFontFallback(),
      (storage: storage, range: range, attributes: result),
    )
    if resolved.isSome:
      result = resolved.get()

proc fixFontFallbackInRange*(storage: TextStorage, range: TextRange) =
  if storage.isNil:
    return
  storage.materialize()
  let clamped = clampTextRange(storage.backingLength(), range)
  if clamped.length == 0:
    return

  var changed = false
  for run in storage.xRuns.mitems:
    if run.range.intersects(clamped):
      let nextAttributes =
        storage.resolvedFontFallbackAttributes(run.range, run.attributes)
      if nextAttributes != run.attributes:
        run.attributes = nextAttributes
        changed = true
  if changed:
    storage.normalizeRuns()

proc delegateHandledAttributeFixing(storage: TextStorage, range: TextRange): bool =
  if storage.isNil or storage.xDelegate.isNil:
    return false

  storage.xDelegate
  .trySendLocal(textStorageFixAttributes(), (storage: storage, range: range))
  .get(false)

proc shouldFixAttributes(storage: TextStorage, range: TextRange): bool =
  if storage.isNil or storage.xDelegate.isNil:
    return true

  storage.xDelegate
  .trySendLocal(textStorageShouldFixAttributes(), (storage: storage, range: range))
  .get(true)

proc fixAttributesInRange*(storage: TextStorage, range: TextRange) =
  if storage.isNil:
    return
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
  if storage.isNil or storage.xProcessingEditing or storage.xEditingDepth > 0 or
      not storage.xHasPendingEdit:
    return

  let edit = storage.xPendingEdit
  storage.xPendingEdit = TextStorageEdit()
  storage.xHasPendingEdit = false
  storage.xProcessingEditing = true
  storage.xLastProcessedEdit = edit
  storage.xHasLastProcessedEdit = true

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
  storage.xUsesGapBuffer = false
  storage.xStringValue = value
  storage.xGapBuffer = GapTextBuffer()
  storage.xMaterialized = true
  storage.xRuns.setLen(0)
  if value.runeLen > 0:
    storage.xRuns.add TextAttributeRun(
      range: initTextRange(0, value.runeLen), attributes: attributes
    )

proc newTextStorage*(value = "", attributes = defaultTextAttributes()): TextStorage =
  result = TextStorage()
  initTextStorageFields(result, value, attributes)

proc initGapTextStorageFields*(
    storage: TextStorage, value = "", attributes = defaultTextAttributes()
) =
  discard storage.withProto()
  storage.xStringValue.setLen(0)
  storage.xGapBuffer = initGapTextBuffer(value)
  storage.xUsesGapBuffer = true
  storage.xMaterialized = true
  storage.xRuns.setLen(0)
  if value.runeLen > 0:
    storage.xRuns.add TextAttributeRun(
      range: initTextRange(0, value.runeLen), attributes: attributes
    )

proc newGapTextStorage*(value = "", attributes = defaultTextAttributes()): TextStorage =
  result = TextStorage()
  initGapTextStorageFields(result, value, attributes)

proc newLazyTextStorage*(provider: DynamicAgent): TextStorage =
  result = TextStorage(xLazyProvider: provider)
  discard result.withProto()
  result.xMaterialized = provider.isNil

proc newAttributedString*(
    value = "", attributes = defaultTextAttributes()
): MutableAttributedString =
  newTextStorage(value, attributes)

proc copyTextStorage*(storage: TextStorage): TextStorage =
  result = newTextStorage()
  if storage.isNil:
    return
  storage.materialize()
  if storage.xUsesGapBuffer:
    result.xUsesGapBuffer = true
    result.xGapBuffer = storage.xGapBuffer.copyGapTextBuffer()
    result.xStringValue.setLen(0)
  else:
    result.xStringValue = storage.xStringValue
  result.xRuns = storage.xRuns
  result.xMaterialized = true

proc registerSnapshotUndo(
    storage: TextStorage, snapshot: TextStorage, actionName: string
) =
  let manager = storage.undoManager()
  if manager.isNil or snapshot.isNil:
    return
  let undoSnapshot = snapshot.copyTextStorage()
  manager.registerUndo(
    proc() =
      storage.applySnapshot(undoSnapshot, actionName),
    actionName,
  )

proc applySnapshot(storage: TextStorage, snapshot: TextStorage, actionName: string) =
  if storage.isNil or snapshot.isNil:
    return
  storage.materialize()
  snapshot.materialize()
  let
    before = storage.copyTextStorage()
    oldLength = storage.backingLength()
    newLength = snapshot.backingLength()
    edit = initTextStorageEdit(
      initTextRange(0, oldLength),
      newLength,
      newLength - oldLength,
      {tseCharacters, tseAttributes},
    )
  storage.registerSnapshotUndo(before, actionName)
  storage.dispatchWillEdit(edit)
  storage.setBackingStringValue(snapshot.backingStringValue())
  storage.xRuns = snapshot.xRuns
  storage.xMaterialized = true
  storage.normalizeRuns()
  storage.notifyCommittedEdit(edit)

proc mutableCopy*(storage: AttributedString): MutableAttributedString =
  storage.copyTextStorage()

proc sliceTextStorage*(storage: TextStorage, range: TextRange): TextStorage =
  result = newTextStorage()
  if storage.isNil:
    return
  storage.materialize()
  let
    clamped = clampTextRange(storage.backingLength(), range)
    start = int(clamped.location)
    stop = clamped.maxIndex
  result.xStringValue = storage.backingSubstring(clamped)
  for run in storage.xRuns:
    let
      runStart = int(run.range.location)
      runStop = run.range.maxIndex
      overlapStart = max(start, runStart)
      overlapStop = min(stop, runStop)
    if overlapStop > overlapStart:
      result.xRuns.add TextAttributeRun(
        range: initTextRange(overlapStart - start, overlapStop - overlapStart),
        attributes: run.attributes,
      )
  result.normalizeRuns()

proc attributedSubstring*(
    storage: AttributedString, range: TextRange
): AttributedString =
  storage.sliceTextStorage(range)

proc stringValue*(storage: TextStorage): string =
  if storage.isNil:
    return ""
  storage.materialize()
  storage.backingStringValue()

proc `stringValue=`*(storage: TextStorage, value: string) =
  if storage.isNil:
    return
  storage.materialize()
  let before = storage.copyTextStorage()
  let oldLength = storage.backingLength()
  let edit = initTextStorageEdit(
    initTextRange(0, oldLength),
    value.runeLen,
    value.runeLen - oldLength,
    {tseCharacters, tseAttributes},
  )
  storage.registerSnapshotUndo(before, "Set Text")
  storage.dispatchWillEdit(edit)
  storage.setBackingStringValue(value)
  storage.xRuns.setLen(0)
  if value.runeLen > 0:
    storage.xRuns.add TextAttributeRun(
      range: initTextRange(0, value.runeLen), attributes: defaultTextAttributes()
    )
  storage.notifyCommittedEdit(edit)

proc len*(storage: TextStorage): int =
  if storage.isNil:
    return 0
  storage.materialize()
  storage.backingLength()

proc substring*(storage: TextStorage, range: TextRange): string =
  if storage.isNil:
    return ""
  storage.materialize()
  let clamped = clampTextRange(storage.len, range)
  storage.backingSubstring(clamped)

proc lineCount*(storage: TextStorage): int =
  if storage.isNil:
    return 0
  storage.materialize()
  storage.backingLineCount()

proc lineRange*(storage: TextStorage, line: int): TextRange =
  if storage.isNil:
    return initTextRange(0, 0)
  storage.materialize()
  storage.backingLineRange(line)

proc attributesAt*(storage: TextStorage, index: int): TextAttributes =
  if storage.isNil:
    return defaultTextAttributes()
  storage.materialize()
  let total = storage.len
  if total == 0:
    return defaultTextAttributes()
  let clamped = max(0, min(index, total - 1))
  for run in storage.xRuns:
    if clamped >= int(run.range.location) and clamped < run.range.maxIndex:
      return run.attributes
  defaultTextAttributes()

proc attributesAtIndex*(storage: AttributedString, index: int): TextAttributes =
  storage.attributesAt(index)

proc attributeRuns*(storage: AttributedString): seq[TextAttributeRun] =
  if storage.isNil:
    return
  storage.materialize()
  for run in storage.xRuns:
    result.add run

proc replace*(
    storage: TextStorage,
    range: TextRange,
    text: string,
    attributes = defaultTextAttributes(),
) =
  if storage.isNil:
    return
  storage.materialize()
  let
    total = storage.len
    clamped = clampTextRange(total, range)
    replaceStart = int(clamped.location)
    replaceStop = clamped.maxIndex
    insertedLength = text.runeLen
    delta = insertedLength - int(clamped.length)
    edit = initTextStorageEdit(clamped, insertedLength, delta, {tseCharacters})
    before = storage.copyTextStorage()

  storage.registerSnapshotUndo(before, "Edit Text")
  storage.dispatchWillEdit(edit)
  storage.replaceBackingText(clamped, text)

  var nextRuns: seq[TextAttributeRun]
  for run in storage.xRuns:
    let
      runStart = int(run.range.location)
      runStop = run.range.maxIndex
    if runStop <= replaceStart:
      nextRuns.add run
    elif runStart >= replaceStop:
      nextRuns.add TextAttributeRun(
        range: initTextRange(runStart + delta, int(run.range.length)),
        attributes: run.attributes,
      )
    else:
      if runStart < replaceStart:
        nextRuns.add TextAttributeRun(
          range: initTextRange(runStart, replaceStart - runStart),
          attributes: run.attributes,
        )
      if runStop > replaceStop:
        nextRuns.add TextAttributeRun(
          range: initTextRange(replaceStart + insertedLength, runStop - replaceStop),
          attributes: run.attributes,
        )

  if insertedLength > 0:
    nextRuns.add TextAttributeRun(
      range: initTextRange(replaceStart, insertedLength), attributes: attributes
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

proc setAttributes*(
    storage: TextStorage, range: TextRange, attributes: TextAttributes
) =
  if storage.isNil:
    return
  storage.materialize()
  let
    total = storage.len
    clamped = clampTextRange(total, range)
    start = int(clamped.location)
    stop = clamped.maxIndex
  if clamped.length == 0:
    return
  let before = storage.copyTextStorage()
  let edit = initTextStorageEdit(clamped, int(clamped.length), 0, {tseAttributes})

  storage.registerSnapshotUndo(before, "Set Attributes")
  storage.dispatchWillEdit(edit)
  var nextRuns: seq[TextAttributeRun]
  for run in storage.xRuns:
    let
      runStart = int(run.range.location)
      runStop = run.range.maxIndex
    if runStop <= start or runStart >= stop:
      nextRuns.add run
    else:
      if runStart < start:
        nextRuns.add TextAttributeRun(
          range: initTextRange(runStart, start - runStart), attributes: run.attributes
        )
      nextRuns.add TextAttributeRun(
        range:
          initTextRange(max(runStart, start), min(runStop, stop) - max(runStart, start)),
        attributes: attributes,
      )
      if runStop > stop:
        nextRuns.add TextAttributeRun(
          range: initTextRange(stop, runStop - stop), attributes: run.attributes
        )
  storage.xRuns = nextRuns
  storage.normalizeRuns()
  storage.notifyCommittedEdit(edit)

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
  if storage.isNil:
    return
  if inserted.isNil:
    storage.replace(range, "")
    return
  storage.materialize()
  inserted.materialize()
  let
    clamped = clampTextRange(storage.len, range)
    start = int(clamped.location)
  storage.beginEditing()
  storage.replace(clamped, inserted.stringValue())
  for run in inserted.xRuns:
    storage.setAttributes(
      initTextRange(start + int(run.range.location), int(run.range.length)),
      run.attributes,
    )
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
      yield run

iterator styledRuns*(
    storage: TextStorage
): tuple[attributes: TextAttributes, text: string] =
  if not storage.isNil:
    storage.materialize()
    for run in storage.xRuns:
      yield (run.attributes, storage.substring(run.range))
