import std/unicode

import ./texttypes

const
  RuneIndexStride = 256
  LineIndexStride = 128

type
  RuneIndex = distinct int
  ByteOffset = distinct int

  GapTextIndexCache = object
    valid: bool
    runeByteOffsets: seq[ByteOffset]
    lineStarts: seq[RuneIndex]
    lineCount: int

  GapTextBuffer* = object
    ## UTF-8 bytes after the gap are stored in reverse order. Moving the gap
    ## therefore only pops and appends ARC-owned bytes; public positions remain
    ## rune indexes.
    xBefore: seq[char]
    xAfter: seq[char]
    xRuneLength: int
    xBeforeRuneLength: int
    xIndexCache: ref GapTextIndexCache

func toInt(index: RuneIndex): int {.inline.} =
  int(index)

func toInt(offset: ByteOffset): int {.inline.} =
  int(offset)

func runeIndex(value: int): RuneIndex {.inline.} =
  RuneIndex(max(value, 0))

func byteOffset(value: int): ByteOffset {.inline.} =
  ByteOffset(max(value, 0))

func clampTextRange(total: int, range: TextRange): TextRange =
  let
    start = max(0, min(int(range.location), total))
    length = max(0, min(int(range.length), total - start))
  initTextRange(start, length)

func byteLen(buffer: GapTextBuffer): int {.inline.} =
  buffer.xBefore.len + buffer.xAfter.len

func byteAt(buffer: GapTextBuffer, offset: ByteOffset): char {.inline.} =
  let index = offset.toInt()
  if index < buffer.xBefore.len:
    buffer.xBefore[index]
  else:
    buffer.xAfter[buffer.xAfter.len - 1 - (index - buffer.xBefore.len)]

func runeWidthAt(buffer: GapTextBuffer, offset: ByteOffset): int {.inline.} =
  let
    index = offset.toInt()
    lead = ord(buffer.byteAt(offset))
    available = buffer.byteLen - index
    expected =
      if lead < 0x80:
        1
      elif (lead and 0xE0) == 0xC0:
        2
      elif (lead and 0xF0) == 0xE0:
        3
      elif (lead and 0xF8) == 0xF0:
        4
      else:
        1
  min(expected, available)

func runeAtByte(buffer: GapTextBuffer, offset: ByteOffset): Rune =
  let
    width = buffer.runeWidthAt(offset)
    first = ord(buffer.byteAt(offset))
  case width
  of 1:
    Rune(first)
  of 2:
    Rune(
      ((first and 0x1F) shl 6) or
        (ord(buffer.byteAt(byteOffset(offset.toInt() + 1))) and 0x3F)
    )
  of 3:
    Rune(
      ((first and 0x0F) shl 12) or
        ((ord(buffer.byteAt(byteOffset(offset.toInt() + 1))) and 0x3F) shl 6) or
        (ord(buffer.byteAt(byteOffset(offset.toInt() + 2))) and 0x3F)
    )
  of 4:
    Rune(
      ((first and 0x07) shl 18) or
        ((ord(buffer.byteAt(byteOffset(offset.toInt() + 1))) and 0x3F) shl 12) or
        ((ord(buffer.byteAt(byteOffset(offset.toInt() + 2))) and 0x3F) shl 6) or
        (ord(buffer.byteAt(byteOffset(offset.toInt() + 3))) and 0x3F)
    )
  else:
    Rune(0)

proc invalidateIndexCache(buffer: var GapTextBuffer) =
  buffer.xIndexCache = new GapTextIndexCache

proc ensureIndexCache(buffer: GapTextBuffer) =
  if buffer.xIndexCache.isNil:
    return
  if buffer.xIndexCache.valid:
    return

  buffer.xIndexCache.runeByteOffsets = @[byteOffset(0)]
  buffer.xIndexCache.lineStarts = @[runeIndex(0)]
  buffer.xIndexCache.lineCount = 1
  var
    byte = 0
    rune = 0
  while byte < buffer.byteLen:
    let
      offset = byteOffset(byte)
      item = buffer.runeAtByte(offset)
    byte += buffer.runeWidthAt(offset)
    inc rune
    if rune mod RuneIndexStride == 0:
      buffer.xIndexCache.runeByteOffsets.add byteOffset(byte)
    if item == Rune('\n'):
      inc buffer.xIndexCache.lineCount
      if (buffer.xIndexCache.lineCount - 1) mod LineIndexStride == 0:
        buffer.xIndexCache.lineStarts.add runeIndex(rune)
  buffer.xIndexCache.valid = true

proc byteOffsetForRune(buffer: GapTextBuffer, index: RuneIndex): ByteOffset =
  if buffer.xIndexCache.isNil:
    return byteOffset(0)
  buffer.ensureIndexCache()
  let
    target = max(0, min(index.toInt(), buffer.xRuneLength))
    checkpoint = target div RuneIndexStride
  var
    rune = checkpoint * RuneIndexStride
    byte = buffer.xIndexCache.runeByteOffsets[checkpoint].toInt()
  while rune < target:
    byte += buffer.runeWidthAt(byteOffset(byte))
    inc rune
  byteOffset(byte)

func len*(buffer: GapTextBuffer): int =
  buffer.xRuneLength

func isEmpty*(buffer: GapTextBuffer): bool =
  buffer.len == 0

func cursor*(buffer: GapTextBuffer): int =
  buffer.xBeforeRuneLength

func `[]`*(buffer: GapTextBuffer, index: int): Rune =
  if index < 0 or index >= buffer.len:
    Rune(0)
  else:
    buffer.runeAtByte(buffer.byteOffsetForRune(runeIndex(index)))

proc initGapTextBuffer*(value = ""): GapTextBuffer =
  result.xBefore = newSeqOfCap[char](value.len)
  result.xBefore.add value
  result.xRuneLength = value.runeLen
  result.xBeforeRuneLength = result.xRuneLength
  result.invalidateIndexCache()

proc copyGapTextBuffer*(buffer: GapTextBuffer): GapTextBuffer =
  result.xBefore = newSeqOfCap[char](buffer.xBefore.len)
  result.xBefore.add buffer.xBefore
  result.xAfter = newSeqOfCap[char](buffer.xAfter.len)
  result.xAfter.add buffer.xAfter
  result.xRuneLength = buffer.xRuneLength
  result.xBeforeRuneLength = buffer.xBeforeRuneLength
  result.invalidateIndexCache()

proc setText*(buffer: var GapTextBuffer, value: string) =
  buffer.xBefore = newSeqOfCap[char](value.len)
  buffer.xBefore.add value
  buffer.xAfter.setLen(0)
  buffer.xRuneLength = value.runeLen
  buffer.xBeforeRuneLength = buffer.xRuneLength
  buffer.invalidateIndexCache()

proc stringValue*(buffer: GapTextBuffer): string =
  result = newStringOfCap(buffer.byteLen)
  for item in buffer.xBefore:
    result.add item
  for index in countdown(buffer.xAfter.high, 0):
    result.add buffer.xAfter[index]

proc substring*(buffer: GapTextBuffer, range: TextRange): string =
  let
    clamped = clampTextRange(buffer.len, range)
    start = buffer.byteOffsetForRune(runeIndex(int(clamped.location))).toInt()
    stop = buffer.byteOffsetForRune(runeIndex(clamped.maxIndex)).toInt()
  result = newStringOfCap(stop - start)
  for index in start ..< stop:
    result.add buffer.byteAt(byteOffset(index))

proc moveGap(buffer: var GapTextBuffer, index: RuneIndex) =
  let
    targetRune = max(0, min(index.toInt(), buffer.len))
    targetByte = buffer.byteOffsetForRune(runeIndex(targetRune)).toInt()
  while buffer.xBefore.len > targetByte:
    buffer.xAfter.add buffer.xBefore[^1]
    buffer.xBefore.setLen(buffer.xBefore.len - 1)
  while buffer.xBefore.len < targetByte and buffer.xAfter.len > 0:
    buffer.xBefore.add buffer.xAfter[^1]
    buffer.xAfter.setLen(buffer.xAfter.len - 1)
  buffer.xBeforeRuneLength = targetRune

proc replace*(buffer: var GapTextBuffer, range: TextRange, text: string) =
  let
    clamped = clampTextRange(buffer.len, range)
    startRune = int(clamped.location)
    stopRune = clamped.maxIndex
    startByte = buffer.byteOffsetForRune(runeIndex(startRune)).toInt()
    stopByte = buffer.byteOffsetForRune(runeIndex(stopRune)).toInt()
    insertedRunes = text.runeLen
  buffer.moveGap(runeIndex(startRune))
  let removedBytes = min(stopByte - startByte, buffer.xAfter.len)
  if removedBytes > 0:
    buffer.xAfter.setLen(buffer.xAfter.len - removedBytes)
  buffer.xBefore.add text
  buffer.xRuneLength += insertedRunes - int(clamped.length)
  buffer.xBeforeRuneLength = startRune + insertedRunes
  buffer.invalidateIndexCache()

proc lineCount*(buffer: GapTextBuffer): int =
  if buffer.xIndexCache.isNil:
    return 1
  buffer.ensureIndexCache()
  buffer.xIndexCache.lineCount

proc lineStart(buffer: GapTextBuffer, line: int): RuneIndex =
  let checkpoint = line div LineIndexStride
  var
    currentLine = checkpoint * LineIndexStride
    rune = buffer.xIndexCache.lineStarts[checkpoint].toInt()
    byte = buffer.byteOffsetForRune(runeIndex(rune)).toInt()
  while currentLine < line and byte < buffer.byteLen:
    let
      offset = byteOffset(byte)
      item = buffer.runeAtByte(offset)
    byte += buffer.runeWidthAt(offset)
    inc rune
    if item == Rune('\n'):
      inc currentLine
  runeIndex(rune)

proc lineStop(buffer: GapTextBuffer, start: RuneIndex): RuneIndex =
  var
    rune = start.toInt()
    byte = buffer.byteOffsetForRune(start).toInt()
  while byte < buffer.byteLen:
    let
      offset = byteOffset(byte)
      item = buffer.runeAtByte(offset)
    byte += buffer.runeWidthAt(offset)
    inc rune
    if item == Rune('\n'):
      break
  runeIndex(rune)

proc lineRange*(buffer: GapTextBuffer, line: int): TextRange =
  if buffer.xIndexCache.isNil:
    return initTextRange(0, 0)
  buffer.ensureIndexCache()
  let target = max(line, 0)
  if target >= buffer.xIndexCache.lineCount:
    return initTextRange(buffer.len, 0)
  let
    start = buffer.lineStart(target)
    stop = buffer.lineStop(start)
  initTextRange(start.toInt(), stop.toInt() - start.toInt())

func lineCheckpoint(lineStarts: openArray[RuneIndex], index: int): int =
  var
    low = 0
    high = lineStarts.len
  while low < high:
    let middle = (low + high) div 2
    if lineStarts[middle].toInt() <= index:
      low = middle + 1
    else:
      high = middle
  max(low - 1, 0)

proc lineStart(buffer: GapTextBuffer, index: RuneIndex): RuneIndex =
  let checkpoint = buffer.xIndexCache.lineStarts.lineCheckpoint(index.toInt())
  var
    start = buffer.xIndexCache.lineStarts[checkpoint].toInt()
    rune = start
    byte = buffer.byteOffsetForRune(runeIndex(rune)).toInt()
  while rune < index.toInt() and byte < buffer.byteLen:
    let
      offset = byteOffset(byte)
      item = buffer.runeAtByte(offset)
    byte += buffer.runeWidthAt(offset)
    inc rune
    if item == Rune('\n'):
      start = rune
  runeIndex(start)

proc paragraphRange*(buffer: GapTextBuffer, range: TextRange): TextRange =
  if buffer.len == 0:
    return initTextRange(0, 0)
  buffer.ensureIndexCache()
  let
    clamped = clampTextRange(buffer.len, range)
    start = buffer.lineStart(runeIndex(int(clamped.location)))
    lastStart = buffer.lineStart(runeIndex(clamped.maxIndex))
    stop = buffer.lineStop(lastStart)
  initTextRange(start.toInt(), stop.toInt() - start.toInt())
