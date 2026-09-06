## Frontend-neutral syntax highlighting values.
##
## Highlighters classify rune ranges without carrying fonts, colors, parser
## objects, or editor state across the boundary. Views remain responsible for
## mapping the classes to their own presentation.

import ./texttypes

type
  SyntaxTokenClass* = enum
    stcKeyword
    stcIdentifier
    stcString
    stcNumber
    stcComment
    stcOperator
    stcPunctuation
    stcPreprocessor
    stcOther

  SyntaxChangeKind* = enum
    sckUnchanged
    sckAdded
    sckDeleted

  SyntaxTokenSpan* = object
    range*: TextRange ## Rune-based half-open source range.
    tokenClass*: SyntaxTokenClass
    changeKind*: SyntaxChangeKind ## Optional diff decoration, independent of syntax.
    changeMarker*: bool ## The leading diff marker, rather than source code.

  SyntaxHighlighter* = proc(source, language: string): seq[SyntaxTokenSpan] {.closure.}
    ## Classify rune ranges in `source` for a language name or code-fence tag.

func syntaxTokenAt*(
    spans: openArray[SyntaxTokenSpan], runeIndex: int
): SyntaxTokenClass =
  ## Return the class covering `runeIndex`, or `stcOther` when none does.
  for span in spans:
    if runeIndex >= int(span.range.location) and runeIndex < span.range.maxIndex:
      return span.tokenClass
  stcOther
