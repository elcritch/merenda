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
      let semicolon = source.find(';', position + 1, result.finish - 1)
      let rune =
        if semicolon > position and semicolon < result.finish:
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

proc prepareHtml*(source: string, limits: ResourceLoadLimits): PreparedHtml =
  result.identifiers = initHashSet[string]()
  if source.len > limits.maximumDataBytes:
    result.diagnostics.add(
      rdsError, "html.data.tooLarge", "HTML exceeds the byte limit"
    )
    return

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
    of xmlElementOpen, xmlElementStart:
      tag = parser.elementName.toLowerAscii()
      lastAttributeEnd = -1
      inc nodeCount
      if nodeCount > limits.maximumNodes:
        result.diagnostics.add(
          rdsError, "html.nodes.tooMany", "HTML exceeds the node limit"
        )
        return
    of xmlAttribute:
      lastAttributeEnd = lineStarts[parser.getLine() - 1] + parser.getColumn()
      let attribute = attributeText(source, tokenStart, lastAttributeEnd)
      if attribute.encoded != source[attribute.start ..< attribute.finish]:
        replacements.add HtmlReplacement(
          start: attribute.start, finish: attribute.finish, text: attribute.encoded
        )
      if parser.attrKey.toLowerAscii() in ["id", "data-window"]:
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
            rdsError, "html.tree.tooDeep", "HTML exceeds the depth limit"
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
