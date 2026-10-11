## Demo-local adapters from a small textual NIF vocabulary to GUI markup and CSS.
## Uses nifcore's token buffer and cursors; this is not a general NIF reader.

import std/[sets, strutils]
import nifcore

type MarkupReader = object
  source: string
  position: int

const NifControlCharacters =
  {'(', ')', '[', ']', '{', '}', '~', '#', '\'', '"', '\\', ':', '@'}

proc fail(reader: MarkupReader, message: string) {.noreturn.} =
  raise newException(ValueError, "NIF byte " & $(reader.position + 1) & ": " & message)

proc escapedByte(reader: var MarkupReader): char =
  inc reader.position
  if reader.position >= reader.source.len:
    reader.fail("incomplete escape")
  let shortcut = reader.source[reader.position]
  inc reader.position
  case shortcut
  of 'n':
    return '\n'
  of 't':
    return '\t'
  of 'r':
    return '\r'
  of '|':
    return '\\'
  of '^':
    return '"'
  else:
    discard
  if shortcut notin HexDigits - {'a' .. 'f'} or reader.position >= reader.source.len or
      reader.source[reader.position] notin HexDigits - {'a' .. 'f'}:
    reader.fail("expected an uppercase hex escape or NIF shortcut")
  result = char(parseHexInt($shortcut & $reader.source[reader.position]))
  inc reader.position

proc quotedString(reader: var MarkupReader): string =
  inc reader.position
  while reader.position < reader.source.len:
    case reader.source[reader.position]
    of '"':
      inc reader.position
      return
    of '\\':
      result.add reader.escapedByte()
    else:
      if reader.source[reader.position] in NifControlCharacters:
        reader.fail("NIF control characters must use escapes")
      result.add reader.source[reader.position]
      inc reader.position
  reader.fail("unclosed string")

proc tagName(reader: var MarkupReader): string =
  while reader.position < reader.source.len and
      reader.source[reader.position] notin {' ', '\t', '\r', '\n', '(', ')'}:
    if reader.source[reader.position] == '\\':
      result.add reader.escapedByte()
    else:
      if reader.source[reader.position] notin Letters + Digits + {'_'}:
        reader.fail("tag characters must be identifiers or escapes")
      result.add reader.source[reader.position]
      inc reader.position
  if result.len == 0 or result[0] notin Letters + {'_'}:
    reader.fail("expected a tag name")
  for ch in result:
    if ch notin Letters + Digits + {'_', '-'}:
      reader.fail("unsupported tag character")

proc parseMarkup(source: string): TokenBuf =
  if source.len > 64 * 1024 * 1024:
    raise newException(ValueError, "NIF markup exceeds the byte limit")
  result = createTokenBuf()
  var reader = MarkupReader(source: source)
  if source.startsWith("(.nif27)"):
    reader.position = "(.nif27)".len
  var depth, nodes: int
  while reader.position < source.len:
    case source[reader.position]
    of ' ', '\t', '\r', '\n':
      inc reader.position
    of '(':
      inc reader.position
      let name = reader.tagName()
      let tag = result.tags.registerTag(name)
      if tag.uint32 > TagMask:
        reader.fail("too many distinct tags")
      inc depth
      inc nodes
      if depth > 256:
        reader.fail("markup exceeds the depth limit")
      result.openTag(tag)
    of ')':
      if depth == 0:
        reader.fail("unmatched closing parenthesis")
      result.closeTag()
      dec depth
      inc reader.position
    of '"':
      if depth == 0:
        reader.fail("text must be inside an element")
      result.addStrLit(reader.quotedString())
      inc nodes
    else:
      reader.fail("expected an element or quoted string")
    if nodes > 100_000:
      reader.fail("markup exceeds the node limit")
  if depth != 0:
    reader.fail("unclosed element")
  if result.len == 0:
    reader.fail("markup is empty")

proc name(cursor: Cursor): string =
  if not cursor.hasMore or cursor.kind != TagLit:
    raise newException(ValueError, "expected a NIF element")
  cursor.tags.tagName(cursor.cursorTagId)

proc takeString(cursor: var Cursor): string =
  if not cursor.hasMore or cursor.kind != StrLit:
    raise newException(ValueError, "expected a quoted NIF string")
  result = cursor.strVal()
  cursor.inc()

proc requireEnd(cursor: Cursor) =
  if cursor.hasMore:
    raise newException(ValueError, "unexpected NIF element content")

proc takeValue(cursor: var Cursor): string =
  if cursor.hasMore and cursor.kind == StrLit:
    return cursor.takeString()
  if cursor.name() != "hexColor":
    raise newException(ValueError, "expected a string or hexColor value")
  cursor.into:
    let digits = cursor.takeString()
    cursor.requireEnd()
    if digits.len notin [3, 4, 6, 8]:
      raise newException(ValueError, "hexColor requires 3, 4, 6, or 8 hex digits")
    for ch in digits:
      if ch notin HexDigits:
        raise newException(ValueError, "invalid hexColor digit")
    result = "#" & digits

proc htmlName(value: string): string =
  for ch in value:
    if ch in {'A' .. 'Z'}:
      if result.len > 0:
        result.add '-'
      result.add ch.toLowerAscii()
    else:
      result.add ch

proc escapedHtml(value: string): string =
  value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
    "\"", "&quot;"
  )

proc emitElement(cursor: var Cursor, output: var string) =
  if cursor.kind == StrLit:
    output.add escapedHtml(cursor.takeString())
    return
  let tag = cursor.name().htmlName()
  if tag in ["attrs", "kv"]:
    raise newException(ValueError, "attrs must be the first child of an element")
  output.add '<' & tag
  cursor.into:
    if cursor.hasMore and cursor.kind == TagLit and cursor.name() == "attrs":
      var attributes = initHashSet[string]()
      cursor.into:
        while cursor.hasMore:
          if cursor.name() != "kv":
            raise newException(ValueError, "attrs requires kv entries")
          cursor.into:
            let key = cursor.takeString()
            if key.len == 0 or key.toLowerAscii() in attributes:
              raise newException(ValueError, "empty or duplicate attribute: " & key)
            for ch in key:
              if ch notin Letters + Digits + {'-', '_'}:
                raise newException(ValueError, "invalid attribute name: " & key)
            attributes.incl key.toLowerAscii()
            let value = cursor.takeValue()
            cursor.requireEnd()
            output.add ' ' & key & "=\"" & value.escapedHtml() & '"'
    output.add '>'
    if tag in ["input", "img", "br"]:
      cursor.requireEnd()
    else:
      while cursor.hasMore:
        cursor.emitElement(output)
      output.add "</" & tag & '>'

proc nifGuiMarkup*(source: string): string =
  ## Converts elements with htmlnif-style `(attrs (kv "name" "value"))` blocks.
  ## Camel-case tags such as `nkStackView` map to native `nk-stack-view` tags.
  var buffer = parseMarkup(source)
  var cursor = buffer.beginRead()
  while cursor.hasMore:
    cursor.emitElement(result)

proc emitDeclarations(cursor: var Cursor, output: var string, customProperties: bool) =
  while cursor.hasMore:
    var property = cursor.name().htmlName()
    if customProperties:
      property = "--" & property
    elif property.startsWith("nimkit-"):
      property = "-" & property
    cursor.into:
      let value = cursor.takeValue()
      cursor.requireEnd()
      output.add "  " & property & ": " & value & ";\n"

proc nifStylesheet*(source: string): string =
  ## Converts property tags with string or `(hexColor "829fff")` values.
  ## `tokens` defines root custom properties; camel-case tags become CSS names.
  var buffer = parseMarkup(source)
  var cursor = buffer.beginRead()
  if cursor.name() != "stylesheet":
    raise newException(ValueError, "expected a stylesheet root")
  cursor.into:
    while cursor.hasMore:
      case cursor.name()
      of "tokens":
        result.add ":root {\n"
        cursor.into:
          cursor.emitDeclarations(result, customProperties = true)
        result.add "}\n"
      of "rule":
        cursor.into:
          result.add cursor.takeString() & " {\n"
          cursor.emitDeclarations(result, customProperties = false)
          result.add "}\n"
      else:
        raise newException(ValueError, "stylesheet requires tokens or rule elements")
  cursor.requireEnd()
