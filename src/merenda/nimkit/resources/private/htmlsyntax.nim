## Adapt HTML5 void elements to the stdlib parser without changing text or attributes.

import std/[htmlparser, parsexml, sets, streams, strutils, unicode]

import ../resrccore

type
  PreparedHtml* = object
    source*: string
    identifiers*: HashSet[string]
    diagnostics*: ResourceDiagnostics

  HtmlReplacement = object
    start, finish: int
    text: string

  HtmlAttribute = object
    start, finish: int
    value, encoded: string

const htmlVoidTags = [
  "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
  "source", "track", "wbr",
]

proc matchesTag(source: string, position: int, tag: string): bool =
  if position + tag.len > source.len:
    return
  for index, ch in tag:
    if source[position + index].toLowerAscii() != ch:
      return
  let finish = position + tag.len
  finish < source.len and source[finish] in Whitespace + {'/', '>'}

proc tagEnd(source: string, position: int): int =
  result = position
  var quote: char
  while result < source.len:
    let ch = source[result]
    if quote != '\0':
      if ch == quote:
        quote = '\0'
    elif ch in {'\'', '"'}:
      quote = ch
    elif ch == '>':
      return
    inc result

proc textareaEnd(source: string, position: int): int =
  result = position
  while result < source.len:
    result = source.find('<', result)
    if result < 0:
      return source.len
    if result + 1 < source.len and source[result + 1] == '/' and
        source.matchesTag(result + 2, "textarea"):
      return
    inc result

proc selfClosingTag(source: string, start, finish: int): bool =
  var position = start
  while position < finish:
    while position < finish and source[position] in Whitespace:
      inc position
    if position == finish:
      return
    if source[position] == '/':
      return position == finish - 1
    while position < finish and source[position] notin Whitespace + {'=', '/'}:
      inc position
    while position < finish and source[position] in Whitespace:
      inc position
    if position < finish and source[position] == '=':
      inc position
      while position < finish and source[position] in Whitespace:
        inc position
      if position < finish and source[position] in {'\'', '"'}:
        let quote = source[position]
        inc position
        while position < finish and source[position] != quote:
          inc position
        if position < finish:
          inc position
      else:
        # An unquoted value consumes its trailing slash, as in value=notes/.
        while position < finish and source[position] notin Whitespace:
          inc position

proc protectTextarea(source: string): string =
  # XML treats markup inside textarea as nodes. Escape it before either XML
  # pass so literal tags neither disappear nor affect IDs and resource limits.
  var position, start: int
  while position < source.len:
    if source[position] != '<':
      inc position
      continue
    if source[position .. min(position + 3, source.high)] == "<!--":
      let finish = source.find("-->", position + 4)
      position =
        if finish < 0:
          source.len
        else:
          finish + 3
      continue
    if position + 1 >= source.len or
        source[position + 1] notin {'a' .. 'z', 'A' .. 'Z', '/', '!', '?'}:
      inc position
      continue
    let finish = source.tagEnd(position + 1)
    if finish == source.len:
      break
    if source.matchesTag(position + 1, "textarea") and
        not source.selfClosingTag(position + "<textarea".len, finish):
      let contentStart = finish + 1
      let contentEnd = source.textareaEnd(contentStart)
      result.add source[start ..< contentStart]
      for index in contentStart ..< contentEnd:
        if source[index] == '<':
          result.add "&lt;"
        else:
          result.add source[index]
      start = contentEnd
      position = contentEnd
    else:
      position = finish + 1
  result.add source[start ..^ 1]

proc attributeText(source: string, start, finish: int): HtmlAttribute =
  if finish <= start:
    return
  let equals = source.find('=', start, finish - 1)
  if equals < 0 or equals >= finish:
    return
  var position = equals + 1
  while position < finish and source[position] in Whitespace:
    inc position
  if position >= finish:
    return
  let quote = source[position]
  if quote in {'\'', '"'}:
    inc position
    result.start = position
    result.finish = source.find(quote, position, finish - 1)
    if result.finish < position or result.finish >= finish:
      return HtmlAttribute()
  else:
    result.start = position
    result.finish = position
    while result.finish < finish and source[result.finish] notin Whitespace:
      inc result.finish

  # Numeric references avoid parsexml's whitespace collapsing and slash handling
  # inside attribute values. Decode HTML named entities before that XML layer.
  while position < result.finish:
    let ch = source[position]
    if ch == '&':
      # Stop at the first non-entity character, especially another '&', so
      # repeated literal ampersands cannot repeatedly scan the remaining value.
      var semicolon = position + 1
      while semicolon < result.finish and
          source[semicolon] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '#'}:
        inc semicolon
      let rune =
        if semicolon < result.finish and source[semicolon] == ';':
          entityToRune(source[position + 1 ..< semicolon])
        else:
          Rune(0)
      if rune.int > 0:
        result.value.add rune.toUTF8()
        result.encoded.add "&#" & $rune.int & ";"
        position = semicolon + 1
      else:
        result.value.add '&'
        result.encoded.add "&amp;"
        inc position
    elif ch in {' ', '\t', '\r', '\n', '/'}:
      let normalized = if ch == '\r': '\n' else: ch
      result.value.add normalized
      result.encoded.add "&#" & $normalized.ord & ";"
      inc position
      if ch == '\r' and position < result.finish and source[position] == '\n':
        inc position
    else:
      result.value.add ch
      result.encoded.add ch
      inc position

proc prepareHtml*(input: string, limits: ResourceLoadLimits): PreparedHtml =
  result.identifiers = initHashSet[string]()
  if input.len > limits.maximumDataBytes:
    result.diagnostics.add(
      rdsError, "gui.data.tooLarge", "GUI markup exceeds the byte limit"
    )
    return

  let source = protectTextarea(input)
  var lineStarts = @[0]
  for index, ch in source:
    if ch == '\n' or
        (ch == '\r' and (index + 1 == source.len or source[index + 1] != '\n')):
      lineStarts.add index + 1

  var
    parser: XmlParser
    tag: string
    stack: seq[string]
    replacements: seq[HtmlReplacement]
    nodeCount: int
    emptyEndPending: bool
    doctypeSeen: bool
    lastAttributeEnd = -1
  parser.open(
    newStringStream(source), "HTML", {allowUnquotedAttribs, allowEmptyAttribs}
  )
  defer:
    parser.close()

  while true:
    let tokenStart = lineStarts[parser.getLine() - 1] + parser.getColumn()
    parser.next()
    case parser.kind
    of xmlSpecial:
      if doctypeSeen or nodeCount != 0 or
          strutils.splitWhitespace(parser.charData.toLowerAscii()) !=
          @["doctype", "nimkit"]:
        result.diagnostics.add(
          rdsError, "gui.doctype.unsupported",
          "use an optional <!doctype nimkit> before the GUI; DTDs are unsupported",
        )
        return
      doctypeSeen = true
    of xmlElementOpen, xmlElementStart:
      tag = parser.elementName.toLowerAscii()
      if tag == "document":
        result.diagnostics.add(
          rdsError, "gui.element.unsupported", "use nk-main for the GUI document"
        )
        return
      lastAttributeEnd = -1
      inc nodeCount
      if nodeCount > limits.maximumNodes:
        result.diagnostics.add(
          rdsError, "gui.nodes.tooMany", "GUI markup exceeds the node limit"
        )
        return
    of xmlAttribute:
      lastAttributeEnd = lineStarts[parser.getLine() - 1] + parser.getColumn()
      let attribute = attributeText(source, tokenStart, lastAttributeEnd)
      if attribute.encoded != source[attribute.start ..< attribute.finish]:
        replacements.add HtmlReplacement(
          start: attribute.start, finish: attribute.finish, text: attribute.encoded
        )
      if parser.attrKey.toLowerAscii() == "id":
        result.identifiers.incl attribute.value
    else:
      discard

    if parser.kind in {xmlElementStart, xmlElementClose}:
      let offset = lineStarts[parser.getLine() - 1] + parser.getColumn()
      # A slash attached to an unquoted value belongs to the value in HTML.
      let selfClosing =
        offset >= 2 and source[offset - 2] == '/' and lastAttributeEnd != offset - 1
      emptyEndPending = selfClosing
      if tag in htmlVoidTags:
        if not selfClosing:
          replacements.add HtmlReplacement(
            start: offset - 1, finish: offset - 1, text: " /"
          )
      elif not selfClosing:
        stack.add tag
        if stack.len > limits.maximumTreeDepth:
          result.diagnostics.add(
            rdsError, "gui.tree.tooDeep", "GUI markup exceeds the depth limit"
          )
          return
    elif parser.kind == xmlElementEnd:
      let closing = parser.elementName.toLowerAscii()
      if emptyEndPending:
        emptyEndPending = false
      else:
        for index in countdown(stack.high, 0):
          if stack[index] == closing:
            stack.setLen(index)
            break
    elif parser.kind == xmlEof:
      break

  var start = 0
  for replacement in replacements:
    result.source.add source[start ..< replacement.start]
    result.source.add replacement.text
    start = replacement.finish
  result.source.add source[start ..^ 1]
