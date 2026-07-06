import std/unicode

import ./texttypes

type GapTextBuffer* = object
  xBefore: seq[Rune]
  xAfter: seq[Rune]

func clampTextRange(total: int, range: TextRange): TextRange =
  let
    start = max(0, min(int(range.location), total))
    length = max(0, min(int(range.length), total - start))
  initTextRange(start, length)

func len*(buffer: GapTextBuffer): int =
  buffer.xBefore.len + buffer.xAfter.len

proc moveGap(buffer: var GapTextBuffer, index: int) =
  let target = max(0, min(index, buffer.len))
  while buffer.xBefore.len > target:
    buffer.xAfter.add buffer.xBefore[^1]
    buffer.xBefore.setLen(buffer.xBefore.len - 1)
  while buffer.xBefore.len < target and buffer.xAfter.len > 0:
    buffer.xBefore.add buffer.xAfter[^1]
    buffer.xAfter.setLen(buffer.xAfter.len - 1)

func isEmpty*(buffer: GapTextBuffer): bool =
  buffer.len == 0

func cursor*(buffer: GapTextBuffer): int =
  buffer.xBefore.len

func `[]`*(buffer: GapTextBuffer, index: int): Rune =
  if index < 0 or index >= buffer.len:
    Rune(0)
  elif index < buffer.xBefore.len:
    buffer.xBefore[index]
  else:
    buffer.xAfter[buffer.xAfter.len - 1 - (index - buffer.xBefore.len)]

proc initGapTextBuffer*(value = ""): GapTextBuffer =
  result.xBefore = value.toRunes()

proc copyGapTextBuffer*(buffer: GapTextBuffer): GapTextBuffer =
  result.xBefore = newSeqOfCap[Rune](buffer.xBefore.len)
  result.xBefore.add buffer.xBefore
  result.xAfter = newSeqOfCap[Rune](buffer.xAfter.len)
  result.xAfter.add buffer.xAfter

proc setText*(buffer: var GapTextBuffer, value: string) =
  buffer.xBefore = value.toRunes()
  buffer.xAfter.setLen(0)

proc stringValue*(buffer: GapTextBuffer): string =
  result = newStringOfCap(buffer.len)
  for item in buffer.xBefore:
    result.add item
  for index in countdown(buffer.xAfter.high, 0):
    result.add buffer.xAfter[index]

proc substring*(buffer: GapTextBuffer, range: TextRange): string =
  let clamped = clampTextRange(buffer.len, range)
  result = newStringOfCap(int(clamped.length))
  let stop = clamped.maxIndex
  for index in int(clamped.location) ..< stop:
    result.add buffer[index]

proc replace*(buffer: var GapTextBuffer, range: TextRange, text: string) =
  let clamped = clampTextRange(buffer.len, range)
  buffer.moveGap(int(clamped.location))
  let removed = min(int(clamped.length), buffer.xAfter.len)
  if removed > 0:
    buffer.xAfter.setLen(buffer.xAfter.len - removed)
  for item in text.runes:
    buffer.xBefore.add item

proc lineCount*(buffer: GapTextBuffer): int =
  result = 1
  for index in 0 ..< buffer.len:
    if buffer[index] == Rune('\n'):
      inc result

proc lineRange*(buffer: GapTextBuffer, line: int): TextRange =
  let targetLine = max(line, 0)
  var
    currentLine = 0
    start = 0
    index = 0
  while index < buffer.len and currentLine < targetLine:
    if buffer[index] == Rune('\n'):
      inc currentLine
      start = index + 1
    inc index

  if currentLine < targetLine:
    return initTextRange(buffer.len, 0)

  var stop = start
  while stop < buffer.len and buffer[stop] != Rune('\n'):
    inc stop
  if stop < buffer.len and buffer[stop] == Rune('\n'):
    inc stop
  initTextRange(start, stop - start)

proc paragraphRange*(buffer: GapTextBuffer, range: TextRange): TextRange =
  let clamped = clampTextRange(buffer.len, range)
  if buffer.len == 0:
    return initTextRange(0, 0)

  var start = min(int(clamped.location), buffer.len)
  while start > 0 and buffer[start - 1] != Rune('\n'):
    dec start

  var stop = min(max(clamped.maxIndex, start), buffer.len)
  if stop < buffer.len and clamped.length == 0 and stop == start:
    discard
  while stop < buffer.len and buffer[stop] != Rune('\n'):
    inc stop
  if stop < buffer.len and buffer[stop] == Rune('\n'):
    inc stop
  initTextRange(start, stop - start)
