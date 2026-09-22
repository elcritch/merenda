## Immutable UTF-8 text with sparse rune and line indexes.

import std/unicode

import ./texttypes

const
  RuneCheckpointStride = 64
  LineCheckpointStride = 64

type TextSnapshot* = ref object
  xBytes: string
  xRuneLength: int
  xLineCount: int
  xRuneBytes: seq[int]
  xLineRunes: seq[int]
  xLineBytes: seq[int]

proc newTextSnapshot*(bytes: sink string): TextSnapshot =
  new result
  result.xBytes = bytes
  result.xRuneBytes = @[0]
  result.xLineRunes = @[0]
  result.xLineBytes = @[0]
  result.xLineCount = 1
  var byteIndex = 0
  while byteIndex < result.xBytes.len:
    let
      newline = result.xBytes[byteIndex] == '\n'
      width = max(1, result.xBytes.runeLenAt(byteIndex))
    byteIndex = min(byteIndex + width, result.xBytes.len)
    inc result.xRuneLength
    if result.xRuneLength mod RuneCheckpointStride == 0:
      result.xRuneBytes.add byteIndex
    if newline:
      inc result.xLineCount
      if (result.xLineCount - 1) mod LineCheckpointStride == 0:
        result.xLineRunes.add result.xRuneLength
        result.xLineBytes.add byteIndex

func bytes*(snapshot: TextSnapshot): lent string =
  snapshot.xBytes

func runeLength*(snapshot: TextSnapshot): int =
  if snapshot.isNil: 0 else: snapshot.xRuneLength

func byteLength*(snapshot: TextSnapshot): int =
  if snapshot.isNil: 0 else: snapshot.xBytes.len

func lineCount*(snapshot: TextSnapshot): int =
  if snapshot.isNil: 1 else: snapshot.xLineCount

func runeCheckpointCount*(snapshot: TextSnapshot): int =
  if snapshot.isNil: 0 else: snapshot.xRuneBytes.len

func lineCheckpointCount*(snapshot: TextSnapshot): int =
  if snapshot.isNil: 0 else: snapshot.xLineRunes.len

proc byteOffset*(snapshot: TextSnapshot, runeIndex: int): int =
  if runeIndex < 0 or runeIndex > snapshot.runeLength:
    raise newException(IndexDefect, "text snapshot rune index out of bounds")
  let checkpoint = runeIndex div RuneCheckpointStride
  var
    index = checkpoint * RuneCheckpointStride
    offset = snapshot.xRuneBytes[checkpoint]
  while index < runeIndex:
    offset += max(1, snapshot.xBytes.runeLenAt(offset))
    inc index
  offset

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
  while byteIndex < snapshot.byteLength:
    let
      newline = snapshot.xBytes[byteIndex] == '\n'
      width = max(1, snapshot.xBytes.runeLenAt(byteIndex))
    byteIndex = min(byteIndex + width, snapshot.byteLength)
    inc runeIndex
    if newline:
      if currentLine == target:
        return initTextRange(startRune, runeIndex - startRune)
      inc currentLine
      startRune = runeIndex
  initTextRange(startRune, snapshot.runeLength - startRune)
