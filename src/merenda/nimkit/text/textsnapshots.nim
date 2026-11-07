## Immutable UTF-8 text with sparse rune and line indexes.

import std/[sets, unicode]

import figdraw

import ./texttypes

const LineCheckpointStride = 64

type
  TextPayloadOwnerKind* = enum
    tpoStorage
    tpoSnapshot
    tpoUtf8Source
    tpoLayoutManager
    tpoLayout
    tpoGapIndex
    tpoImage
    tpoImagePixels

  TextPayloadEstimate* = object
    ## Logical live payload length, not allocator capacity or resident memory.
    ## Unknown native, custom, font and image resources make it incomplete.
    bytes*: uint64
    incomplete*: bool
    seen: HashSet[tuple[kind: TextPayloadOwnerKind, identity: pointer]]

  TextSnapshot* = ref object
    xSource: Utf8Runes
    xLineCount: int
    xLineRunes: seq[int]
    xLineBytes: seq[int]

proc claimTextPayloadOwner*(
    estimate: var TextPayloadEstimate, kind: TextPayloadOwnerKind, identity: pointer
): bool =
  ## Identity is borrowed and does not retain its owner. Keep all accounted
  ## owners alive throughout the accounting pass.
  if identity.isNil:
    return
  if estimate.seen.len == 0:
    estimate.seen = initHashSet[tuple[kind: TextPayloadOwnerKind, identity: pointer]]()
  let key = (kind, identity)
  if key notin estimate.seen:
    estimate.seen.incl key
    result = true

proc addTextPayloadBytes*(estimate: var TextPayloadEstimate, bytes: int) =
  if bytes > 0:
    let amount = uint64(bytes)
    if high(uint64) - estimate.bytes < amount:
      estimate.bytes = high(uint64)
      estimate.incomplete = true
    else:
      estimate.bytes += amount

proc addUtf8RunesPayload*(estimate: var TextPayloadEstimate, source: Utf8Runes) =
  ## Count a source and its sparse rune checkpoints once by shared identity.
  if estimate.claimTextPayloadOwner(tpoUtf8Source, cast[pointer](source)):
    estimate.addTextPayloadBytes(source.byteLength)
    estimate.addTextPayloadBytes(source.runeCheckpointCount * sizeof(uint32))

proc addTextSnapshotPayload*(
    estimate: var TextPayloadEstimate, snapshot: TextSnapshot
) =
  ## Count existing source and line indexes without creating a snapshot or text.
  if estimate.claimTextPayloadOwner(tpoSnapshot, cast[pointer](snapshot)):
    estimate.addTextPayloadBytes(snapshot.xLineRunes.len * sizeof(int))
    estimate.addTextPayloadBytes(snapshot.xLineBytes.len * sizeof(int))
    estimate.addUtf8RunesPayload(snapshot.xSource)

when defined(useNativeDynlib):
  func bytes*(snapshot: TextSnapshot): string =
    snapshot.xSource.stringValue()
else:
  func bytes*(snapshot: TextSnapshot): lent string =
    snapshot.xSource.bytes

proc newTextSnapshot*(bytes: sink string): TextSnapshot =
  new result
  result.xSource = initUtf8Runes(bytes)
  result.xLineRunes = @[0]
  result.xLineBytes = @[0]
  result.xLineCount = 1
  let source = result.bytes()
  var byteIndex = 0
  var runeIndex = 0
  while byteIndex < source.len:
    let
      newline = source[byteIndex] == '\n'
      width = max(1, source.runeLenAt(byteIndex))
    byteIndex = min(byteIndex + width, source.len)
    inc runeIndex
    if newline:
      inc result.xLineCount
      if (result.xLineCount - 1) mod LineCheckpointStride == 0:
        result.xLineRunes.add runeIndex
        result.xLineBytes.add byteIndex

func sourceRunes*(snapshot: TextSnapshot): Utf8Runes =
  snapshot.xSource

func runeLength*(snapshot: TextSnapshot): int =
  if snapshot.isNil: 0 else: snapshot.xSource.len

func len*(snapshot: TextSnapshot): int =
  ## Number of runes. Use `byteLength` for the UTF-8 byte count.
  snapshot.runeLength

func byteLength*(snapshot: TextSnapshot): int =
  if snapshot.isNil: 0 else: snapshot.xSource.byteLength

func lineCount*(snapshot: TextSnapshot): int =
  if snapshot.isNil: 1 else: snapshot.xLineCount

func runeCheckpointCount*(snapshot: TextSnapshot): int =
  if snapshot.isNil: 0 else: snapshot.xSource.runeCheckpointCount

func lineCheckpointCount*(snapshot: TextSnapshot): int =
  if snapshot.isNil: 0 else: snapshot.xLineRunes.len

proc byteOffset*(snapshot: TextSnapshot, runeIndex: int): int =
  snapshot.xSource.byteOffsetForRune(runeIndex)

proc byteRange*(snapshot: TextSnapshot, range: TextRange): TextByteRange =
  ## Converts a rune range to byte offsets in this immutable snapshot.
  if snapshot.isNil:
    raise newException(ValueError, "cannot convert a range in a nil text snapshot")
  let
    startRune = min(int(range.location), snapshot.runeLength)
    stopRune = min(range.maxIndex, snapshot.runeLength)
    startByte = snapshot.byteOffset(startRune)
    stopByte = snapshot.byteOffset(stopRune)
  initTextByteRange(startByte, stopByte - startByte)

proc runeRange*(snapshot: TextSnapshot, range: TextByteRange): TextRange =
  ## Converts a byte range whose endpoints are rune boundaries. Raises
  ## ValueError if either endpoint falls inside a multibyte rune.
  if snapshot.isNil:
    raise newException(ValueError, "cannot convert a range in a nil text snapshot")
  let
    startByte = min(int(range.location), snapshot.byteLength)
    stopByte = min(range.maxIndex, snapshot.byteLength)
    startRune = snapshot.xSource.runeIndexAtOrBeforeByte(startByte)
    stopRune = snapshot.xSource.runeIndexAtOrBeforeByte(stopByte)
  if snapshot.byteOffset(startRune) != startByte or
      snapshot.byteOffset(stopRune) != stopByte:
    raise newException(ValueError, "UTF-8 byte range endpoint is inside a rune")
  initTextRange(startRune, stopRune - startRune)

proc `[]`*(snapshot: TextSnapshot, index: int): Rune =
  ## Reads one rune without creating a decoded sequence.
  snapshot.xSource[index]

iterator items*(snapshot: TextSnapshot): Rune =
  ## Iterates runes without creating a decoded sequence.
  if not snapshot.isNil:
    for rune in snapshot.xSource:
      yield rune

iterator pairs*(snapshot: TextSnapshot): tuple[index: int, value: Rune] =
  ## Iterates rune indexes and values without creating a decoded sequence.
  if not snapshot.isNil:
    for index, rune in snapshot.xSource.pairs:
      yield (index, rune)

proc toRunes*(snapshot: TextSnapshot): seq[Rune] =
  ## Materializes a decoded sequence when random rune access is preferred.
  if not snapshot.isNil:
    result = snapshot.xSource.toRunes()

proc lineRange*(snapshot: TextSnapshot, line: int): TextRange =
  let target = max(line, 0)
  if target >= snapshot.lineCount:
    return initTextRange(snapshot.runeLength, 0)
  let checkpoint = target div LineCheckpointStride
  var
    currentLine = checkpoint * LineCheckpointStride
    startRune = snapshot.xLineRunes[checkpoint]
    runeIndex = startRune
    byteIndex = snapshot.xLineBytes[checkpoint]
  let source = snapshot.bytes()
  while byteIndex < snapshot.byteLength:
    let
      newline = source[byteIndex] == '\n'
      width = max(1, source.runeLenAt(byteIndex))
    byteIndex = min(byteIndex + width, snapshot.byteLength)
    inc runeIndex
    if newline:
      if currentLine == target:
        return initTextRange(startRune, runeIndex - startRune)
      inc currentLine
      startRune = runeIndex
  initTextRange(startRune, snapshot.runeLength - startRune)
