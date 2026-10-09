## Safe Stylus adapter and source locations; shared by stylesheet and value parsing.

import std/strutils
import stylus

const StylusTokenStartCharacters = {
  'a' .. 'z',
  'A' .. 'Z',
  '0' .. '9',
  '_',
  ' ',
  '\t',
  '\n',
  '\r',
  '\x0c',
  '#',
  '$',
  '(',
  ')',
  '*',
  '+',
  '-',
  ',',
  '.',
  '/',
  ':',
  ';',
  '<',
  '@',
  ']',
  '^',
  '{',
  '|',
  '}',
  '~',
  '>',
}

type
  CssDiagnostic* = object ## One-based line and byte column in the stylesheet source.
    line*, column*: int
    message*: string

  LocatedToken* = object
    value*: Token
    line*, column*: int
    text*: string

proc addDiagnostic(
    diagnostics: var seq[CssDiagnostic], token: LocatedToken, message: string
) =
  diagnostics.add CssDiagnostic(
    line: token.line, column: token.column, message: message
  )

proc advanceLocation(source: string, start, finish: int, line, column: var int) =
  for index in start ..< finish:
    if source[index] in {'\n', '\r'}:
      if source[index] != '\n' or index == 0 or source[index - 1] != '\r':
        inc line
      column = 1
    else:
      inc column

proc tokenizeCss*(
    source: string, tokens: var seq[LocatedToken], diagnostics: var seq[CssDiagnostic]
) =
  # Stylus 0.1.5 has internal loops for escaped identifiers and NUL. Check
  # these before entering consumeName; strings/comments use safe adapters.
  var
    scan = 0
    line = 1
    column = 1
  while scan < source.len:
    let start = scan
    if source[scan] in {'"', '\''}:
      let quote = source[scan]
      inc scan
      while scan < source.len and source[scan] != quote:
        if source[scan] == '\\' and scan + 1 < source.len:
          inc scan
        inc scan
      if scan < source.len:
        inc scan
    elif source[scan] == '/' and scan + 1 < source.len and source[scan + 1] == '*':
      let ending = source.find("*/", scan + 2)
      scan =
        if ending < 0:
          source.len
        else:
          ending + 2
    elif source[scan] in {'\\', '\0'}:
      diagnostics.add CssDiagnostic(
        line: line,
        column: column,
        message: "Escaped identifiers and NUL are unsupported",
      )
      return
    else:
      inc scan
    source.advanceLocation(start, scan, line, column)

  let tokenizer = newTokenizer(source & "  ")
  line = 1
  column = 1
  while int(tokenizer.position()) < source.len:
    let start = int(tokenizer.position())
    let location = LocatedToken(line: line, column: column)
    var token: Token
    let current = source[start]
    if current in {'"', '\''}:
      let quote = current
      var
        ending = start + 1
        text: string
        valid = true
      while ending < source.len and source[ending] != quote:
        let character = source[ending]
        if character in {'\n', '\r', '\0'}:
          valid = false
        if character == '\\':
          inc ending
          if ending < source.len and source[ending] in {'\\', '"', '\''}:
            text.add source[ending]
          else:
            valid = false
        else:
          text.add character
        inc ending
      if ending == source.len:
        valid = false
      else:
        inc ending
      tokenizer.forwards(uint(ending - start))
      token =
        if valid:
          Token(kind: tkQuotedString, qStr: text)
        else:
          Token(kind: tkBadString, badString: text)
      if not valid:
        diagnostics.addDiagnostic(location, "Unclosed or unsupported quoted string")
    elif current == '/' and start + 1 < source.len and source[start + 1] == '*':
      let ending = source.find("*/", start + 2)
      let finish =
        if ending < 0:
          source.len
        else:
          ending + 2
      tokenizer.forwards(uint(finish - start))
      token = Token(kind: tkComment, comment: source[start ..< finish])
      if ending < 0:
        diagnostics.addDiagnostic(location, "Unclosed CSS comment")
    elif current == '[':
      tokenizer.forwards(1)
      token = Token(kind: tkSquareBracketBlock)
    elif current notin StylusTokenStartCharacters:
      tokenizer.forwards(1)
      token = Token(kind: tkDelim, delim: current)
    else:
      token = tokenizer.nextToken()
      # Stylus leaves the opening parenthesis in the input for ordinary
      # function tokens (its URL path consumes it itself).
      if not token.isNil and token.kind == tkFunction and tokenizer.charAt() == '(':
        tokenizer.forwards(1)
      # isIdentStart can mistake a following delimiter for a unit. A real
      # dimension's unit is part of its consumed source span.
      if not token.isNil and token.kind == tkDimension:
        let consumed = source[start ..< min(int(tokenizer.position()), source.len)]
        if not consumed.endsWith(token.unit):
          token = Token(
            kind: tkNumber,
            nHasSign: token.dHasSign,
            nValue: token.dValue,
            nIntVal: token.dIntVal,
          )
      if token.isNil or int(tokenizer.position()) <= start:
        if int(tokenizer.position()) <= start:
          tokenizer.forwards(1)
        token = Token(kind: tkDelim, delim: current)
    let finish = min(int(tokenizer.position()), source.len)
    tokens.add LocatedToken(
      value: token, line: line, column: column, text: source[start ..< finish]
    )
    source.advanceLocation(start, finish, line, column)
