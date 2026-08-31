## Moe's tokenizer adapted to NimKit's frontend-neutral syntax spans.

import std/unicode

import moepkg/syntax/tokenizer as moeTokenizer

import ../nimkit as nimkit

func syntaxTokenClass(token: moeTokenizer.TokenClass): nimkit.SyntaxTokenClass =
  case token
  of gtKeyword, gtBoolean, gtPragma, gtCommand:
    nimkit.stcKeyword
  of gtIdentifier, gtSpecialVar, gtBuiltin, gtFunctionName, gtTypeName, gtKey, gtValue,
      gtLabel, gtReference, gtTable:
    nimkit.stcIdentifier
  of gtStringLit, gtLongStringLit, gtCharLit, gtEscapeSequence, gtRegularExpression,
      gtRawData, gtCData, gtHyperlink, gtDate:
    nimkit.stcString
  of gtDecNumber, gtBinNumber, gtHexNumber, gtOctNumber, gtFloatNumber:
    nimkit.stcNumber
  of gtComment, gtLongComment, gtDocComment, gtDocLongComment:
    nimkit.stcComment
  of gtOperator:
    nimkit.stcOperator
  of gtPunctuation, gtTagStart, gtTagEnd:
    nimkit.stcPunctuation
  of gtAssembler, gtPreprocessor, gtDirective:
    nimkit.stcPreprocessor
  else:
    nimkit.stcOther

proc byteRuneMap(source: string): seq[int] =
  result = newSeq[int](source.len + 1)
  var
    byteIndex = 0
    runeIndex = 0
  while byteIndex < source.len:
    let nextByte = min(byteIndex + max(runeLenAt(source, byteIndex), 1), source.len)
    for index in byteIndex ..< nextByte:
      result[index] = runeIndex
    byteIndex = nextByte
    inc runeIndex
  result[source.len] = runeIndex

proc addSpan(
    spans: var seq[nimkit.SyntaxTokenSpan],
    byteToRune: openArray[int],
    startByte, stopByte: int,
    tokenClass: nimkit.SyntaxTokenClass,
) =
  let
    start = max(0, min(startByte, byteToRune.high))
    stop = max(start, min(stopByte, byteToRune.high))
    startRune = byteToRune[start]
    stopRune = byteToRune[stop]
  if stopRune <= startRune:
    return
  if spans.len > 0 and spans[^1].tokenClass == tokenClass and
      spans[^1].range.maxIndex == startRune:
    spans[^1].range.length =
      (int(spans[^1].range.length) + stopRune - startRune).Natural
  else:
    spans.add nimkit.SyntaxTokenSpan(
      range: nimkit.initTextRange(startRune, stopRune - startRune),
      tokenClass: tokenClass,
    )

proc moeSyntaxHighlighter*(source, language: string): seq[nimkit.SyntaxTokenSpan] =
  ## Classify `source` with Moe without exposing Moe values to NimKit.
  let sourceLanguage = moeTokenizer.getSourceLanguage(language)
  if source.len == 0 or sourceLanguage == moeTokenizer.langNone:
    return

  let byteToRune = source.byteRuneMap()
  var tokenizer: moeTokenizer.GeneralTokenizer
  tokenizer.initGeneralTokenizer(source)
  while true:
    tokenizer.getNextToken(sourceLanguage)
    if tokenizer.kind == moeTokenizer.gtEof:
      break
    result.addSpan(
      byteToRune,
      tokenizer.start,
      tokenizer.start + tokenizer.length,
      tokenizer.kind.syntaxTokenClass(),
    )

proc installMoeSyntaxHighlighter*(view: nimkit.SynEditView) =
  ## Install Moe classification on a NimKit source editor.
  if not view.isNil:
    view.syntaxHighlighter = moeSyntaxHighlighter

proc installMoeSyntaxHighlighter*(view: nimkit.MarkdownView) =
  ## Install Moe classification for language-tagged Markdown code fences.
  if not view.isNil:
    view.syntaxHighlighter = moeSyntaxHighlighter
