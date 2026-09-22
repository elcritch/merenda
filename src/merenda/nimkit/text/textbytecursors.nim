## Monotonic UTF-8 endpoint conversion without a byte- or rune-sized index.

import std/unicode

type TextByteCursor* = object
  byteOffset*: int
  runeIndex*: int

proc runeIndexAtByte*(source: string, cursor: var TextByteCursor, target: int): int =
  ## Returns the rune containing `target`, or the rune at that byte boundary.
  let clamped = max(0, min(target, source.len))
  if clamped < cursor.byteOffset:
    cursor = TextByteCursor()
  while cursor.byteOffset < clamped and cursor.byteOffset < source.len:
    let nextByte =
      min(source.len, cursor.byteOffset + max(1, source.runeLenAt(cursor.byteOffset)))
    if nextByte > clamped:
      break
    cursor.byteOffset = nextByte
    inc cursor.runeIndex
  cursor.runeIndex

proc byteOffsetAtRune*(source: string, cursor: var TextByteCursor, target: int): int =
  ## Clamps out-of-range rune endpoints to the source byte length.
  let clamped = max(target, 0)
  if clamped < cursor.runeIndex:
    cursor = TextByteCursor()
  while cursor.runeIndex < clamped and cursor.byteOffset < source.len:
    cursor.byteOffset =
      min(source.len, cursor.byteOffset + max(1, source.runeLenAt(cursor.byteOffset)))
    inc cursor.runeIndex
  cursor.byteOffset
