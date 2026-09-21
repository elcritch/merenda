import std/unicode

from figdraw import Utf8Runes, initUtf8Runes, len, `[]`, utf8RunesFromText

import ./texttypes

proc utf8RunesForText*(text: string): Utf8Runes =
  ## Creates an indexed UTF-8 view with Nim's replacement-rune semantics.
  if text.validateUtf8() >= 0:
    var normalized = newStringOfCap(text.len)
    for rune in text.runes:
      normalized.add rune.toUTF8()
    return initUtf8Runes(move(normalized))
  utf8RunesFromText(text)

func clampRuneIndex(runes: Utf8Runes, index: int): int {.inline.} =
  max(0, min(index, runes.len))

func isWordRune*(rune: Rune): bool =
  let code = rune.int
  (code >= int('a') and code <= int('z')) or (code >= int('A') and code <= int('Z')) or
    (code >= int('0') and code <= int('9')) or code == int('_')

proc previousWordBoundary*(runes: Utf8Runes, index: int): int =
  result = runes.clampRuneIndex(index)
  while result > 0 and runes[result - 1].isWhiteSpace:
    dec result
  while result > 0 and not runes[result - 1].isWhiteSpace:
    dec result

proc nextWordBoundary*(runes: Utf8Runes, index: int): int =
  result = runes.clampRuneIndex(index)
  while result < runes.len and runes[result].isWhiteSpace:
    inc result
  while result < runes.len and not runes[result].isWhiteSpace:
    inc result

proc wordRangeAt*(runes: Utf8Runes, index: int): TextRange =
  if runes.len == 0:
    return initTextRange(0, 0)
  var
    start = runes.clampRuneIndex(index)
    stop = start
  if start == runes.len and start > 0:
    dec start
    stop = runes.len
  while start > 0 and runes[start - 1].isWordRune:
    dec start
  while stop < runes.len and runes[stop].isWordRune:
    inc stop
  initTextRange(start, stop - start)

proc previousWordBoundary*(text: string, index: int): int =
  utf8RunesForText(text).previousWordBoundary(index)

proc nextWordBoundary*(text: string, index: int): int =
  utf8RunesForText(text).nextWordBoundary(index)

proc wordRangeAt*(text: string, index: int): TextRange =
  utf8RunesForText(text).wordRangeAt(index)
