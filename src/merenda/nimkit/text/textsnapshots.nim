## Immutable UTF-8 text with sparse rune and line indexes.

import std/unicode

import figdraw

import ./texttypes

const LineCheckpointStride = 64

type TextSnapshot* = ref object
  xSource: Utf8Runes
  xLineCount: int
  xLineRunes: seq[int]
  xLineBytes: seq[int]

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
