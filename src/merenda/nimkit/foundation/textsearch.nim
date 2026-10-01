## Shared literal/Reni matching and validated capture replacement templates.

import std/options
import reni

type
  TextSearchError* = object of ValueError

  TextSearchPattern* = object
    expression: Regex
    regularExpression: bool

  TextSearchMatch* = object
    first*, last*: int ## Half-open UTF-8 byte offsets in the searched line.
    captures: Match

  ReplacementPart = object
    text: string
    group: int

  TextSearchReplacement* = object
    parts: seq[ReplacementPart]

proc initTextSearchPattern*(
    query: string, regularExpression = false, caseSensitive = true
): TextSearchPattern =
  ## Compile once and match many lines. Raises TextSearchError on invalid syntax.
  var source = query
  if not regularExpression:
    source = ""
    for c in query:
      if c in {'\\', '.', '^', '$', '|', '?', '*', '+', '(', ')', '[', ']', '{', '}'}:
        source.add '\\'
      source.add c
  try:
    result = TextSearchPattern(
      expression: re(
        source,
        if caseSensitive:
          {}
        else:
          {rfIgnoreCase},
      ),
      regularExpression: regularExpression,
    )
  except RegexError as error:
    raise newException(TextSearchError, error.msg)

iterator findMatches*(pattern: TextSearchPattern, subject: string): TextSearchMatch =
  ## Reni's scanner advances zero-width matches by character and honors \K.
  ## Each engine search is bounded by Reni's default matching budget.
  try:
    for match in findAll(subject, pattern.expression):
      let span = match.matchSpan()
      yield TextSearchMatch(first: span.a, last: span.b, captures: match)
  except RegexError as error:
    raise newException(TextSearchError, error.msg)

proc initTextSearchReplacement*(
    pattern: TextSearchPattern, text: string
): TextSearchReplacement =
  ## Validate every reference before editing. Literal mode preserves all bytes.
  ## Expression mode accepts $0, $1..., ${name}, and $$ (a literal dollar sign).
  if not pattern.regularExpression:
    result.parts.add ReplacementPart(text: text, group: -1)
    return
  var literal = ""
  var index = 0
  while index < text.len:
    if text[index] != '$' or index + 1 == text.len:
      literal.add text[index]
      inc index
    elif text[index + 1] == '$':
      literal.add '$'
      index += 2
    elif text[index + 1] in {'0' .. '9', '{'}:
      if literal.len > 0:
        result.parts.add ReplacementPart(text: move(literal), group: -1)
      let first = index
      inc index
      var group = 0
      if text[index] == '{':
        inc index
        let nameStart = index
        while index < text.len and text[index] != '}':
          inc index
        if index == text.len:
          raise
            newException(TextSearchError, "Unterminated ${...} replacement reference")
        let name = text[nameStart ..< index]
        group = pattern.expression.captureIndex(name)
        inc index
      else:
        while index < text.len and text[index] in {'0' .. '9'}:
          let digit = ord(text[index]) - ord('0')
          if group > (high(int) - digit) div 10:
            raise
              newException(TextSearchError, "Replacement capture number is too large")
          group = group * 10 + digit
          inc index
      if group < 0 or group > pattern.expression.captureCount:
        raise newException(
          TextSearchError, "Unknown replacement capture: " & text[first ..< index]
        )
      result.parts.add ReplacementPart(group: group)
    else:
      literal.add '$'
      inc index
  if literal.len > 0:
    result.parts.add ReplacementPart(text: move(literal), group: -1)

proc expand*(
    replacement: TextSearchReplacement, match: TextSearchMatch, subject: string
): string =
  ## Expand a validated template using captures from this original subject.
  for part in replacement.parts:
    if part.group < 0:
      result.add part.text
    else:
      result.add match.captures.captureText(part.group, subject).get("")
