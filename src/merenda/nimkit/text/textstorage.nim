import std/[algorithm, unicode]

import sigils/core
import sigils/selectors
import ./texttypes

type
  TextStorageEditKind* = enum
    tseCharacters
    tseAttributes

  TextStorageEditKinds* = set[TextStorageEditKind]

  TextStorageEdit* = object
    range*: TextRange
    replacementLength*: Natural
    textDelta*: int
    kinds*: TextStorageEditKinds

  TextStorage* = ref object of DynamicAgent
    xStringValue: string
    xRuns: seq[TextAttributeRun]

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

protocol TextStorageEditingEvents:
  proc willEdit*(storage: TextStorage, edit: TextStorageEdit) {.signal.}
  proc didEdit*(storage: TextStorage, edit: TextStorageEdit) {.signal.}

protocol TextStorageEditingProtocol {.selectorScope: protocol.} from TextStorage:
  method notifyWillEdit*(storage: TextStorage, edit: TextStorageEdit) =
    emit storage.willEdit(edit)

  method notifyDidEdit*(storage: TextStorage, edit: TextStorageEdit) =
    emit storage.didEdit(edit)

func clampTextRange(total: int, range: TextRange): TextRange =
  let
    start = max(0, min(int(range.location), total))
    length = max(0, min(int(range.length), total - start))
  initTextRange(start, length)

proc normalizeRuns(storage: TextStorage) =
  if storage.isNil:
    return
  let total = storage.xStringValue.runeLen
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

proc initTextStorageFields*(
    storage: TextStorage, value = "", attributes = defaultTextAttributes()
) =
  discard storage.withProto()
  storage.xStringValue = value
  storage.xRuns.setLen(0)
  if value.runeLen > 0:
    storage.xRuns.add TextAttributeRun(
      range: initTextRange(0, value.runeLen), attributes: attributes
    )

proc newTextStorage*(value = "", attributes = defaultTextAttributes()): TextStorage =
  result = TextStorage()
  initTextStorageFields(result, value, attributes)

proc copyTextStorage*(storage: TextStorage): TextStorage =
  result = newTextStorage()
  if storage.isNil:
    return
  result.xStringValue = storage.xStringValue
  result.xRuns = storage.xRuns

proc sliceTextStorage*(storage: TextStorage, range: TextRange): TextStorage =
  result = newTextStorage()
  if storage.isNil:
    return
  let
    clamped = clampTextRange(storage.xStringValue.runeLen, range)
    start = int(clamped.location)
    stop = clamped.maxIndex
  result.xStringValue = storage.xStringValue.runeSubStr(start, int(clamped.length))
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

proc stringValue*(storage: TextStorage): string =
  if storage.isNil: "" else: storage.xStringValue

proc `stringValue=`*(storage: TextStorage, value: string) =
  if storage.isNil:
    return
  let oldLength = storage.xStringValue.runeLen
  let edit = initTextStorageEdit(
    initTextRange(0, oldLength),
    value.runeLen,
    value.runeLen - oldLength,
    {tseCharacters, tseAttributes},
  )
  storage.notifyWillEdit(edit)
  storage.xStringValue = value
  storage.xRuns.setLen(0)
  if value.runeLen > 0:
    storage.xRuns.add TextAttributeRun(
      range: initTextRange(0, value.runeLen), attributes: defaultTextAttributes()
    )
  storage.notifyDidEdit(edit)

proc len*(storage: TextStorage): int =
  if storage.isNil: 0 else: storage.xStringValue.runeLen

proc substring*(storage: TextStorage, range: TextRange): string =
  if storage.isNil:
    return ""
  let clamped = clampTextRange(storage.len, range)
  storage.xStringValue.runeSubStr(int(clamped.location), int(clamped.length))

proc attributesAt*(storage: TextStorage, index: int): TextAttributes =
  if storage.isNil:
    return defaultTextAttributes()
  let total = storage.len
  if total == 0:
    return defaultTextAttributes()
  let clamped = max(0, min(index, total - 1))
  for run in storage.xRuns:
    if clamped >= int(run.range.location) and clamped < run.range.maxIndex:
      return run.attributes
  defaultTextAttributes()

proc replace*(
    storage: TextStorage,
    range: TextRange,
    text: string,
    attributes = defaultTextAttributes(),
) =
  if storage.isNil:
    return

  let
    total = storage.len
    clamped = clampTextRange(total, range)
    replaceStart = int(clamped.location)
    replaceStop = clamped.maxIndex
    insertedLength = text.runeLen
    delta = insertedLength - int(clamped.length)
    current = storage.xStringValue
    edit = initTextStorageEdit(clamped, insertedLength, delta, {tseCharacters})

  storage.notifyWillEdit(edit)
  storage.xStringValue =
    current.runeSubStr(0, replaceStart) & text & current.runeSubStr(replaceStop)

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
  storage.notifyDidEdit(edit)

proc setAttributes*(
    storage: TextStorage, range: TextRange, attributes: TextAttributes
) =
  if storage.isNil:
    return
  let
    total = storage.len
    clamped = clampTextRange(total, range)
    start = int(clamped.location)
    stop = clamped.maxIndex
  if clamped.length == 0:
    return
  let edit = initTextStorageEdit(clamped, int(clamped.length), 0, {tseAttributes})

  storage.notifyWillEdit(edit)
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
  storage.notifyDidEdit(edit)

proc replace*(storage: TextStorage, range: TextRange, inserted: TextStorage) =
  if storage.isNil:
    return
  if inserted.isNil:
    storage.replace(range, "")
    return
  let
    clamped = clampTextRange(storage.len, range)
    start = int(clamped.location)
  storage.replace(clamped, inserted.stringValue())
  for run in inserted.xRuns:
    storage.setAttributes(
      initTextRange(start + int(run.range.location), int(run.range.length)),
      run.attributes,
    )

iterator runs*(storage: TextStorage): TextAttributeRun =
  if not storage.isNil:
    for run in storage.xRuns:
      yield run

iterator styledRuns*(
    storage: TextStorage
): tuple[attributes: TextAttributes, text: string] =
  if not storage.isNil:
    for run in storage.xRuns:
      yield (run.attributes, storage.substring(run.range))
