## Demo-local adapters from OpenParser's NIF nodes to GUI markup and CSS.

import std/[math, sets, strutils]
import openparser/nif
import ./nifshorthand

proc name(node: NifNode): string =
  if node.kind != nkCompound:
    raise newException(ValueError, "expected a NIF element")
  node.tag

proc requireChildren(node: NifNode, count: int) =
  if node.children.len != count:
    raise newException(ValueError, node.name() & " expects " & $count & " values")

proc validateNode(node: NifNode, count: var int) =
  inc count
  if count > 100_000:
    raise newException(ValueError, "NIF markup exceeds the node limit")
  case node.kind
  of nkCompound:
    let tag = node.name()
    if tag.len == 0 or tag[0] notin Letters + {'_'}:
      raise newException(ValueError, "expected a markup tag name")
    for ch in tag:
      if ch notin Letters + Digits + {'_', '-'}:
        raise newException(ValueError, "unsupported markup tag: " & tag)
    for child in node.children:
      child.validateNode(count)
  of nkFloat:
    if node.floatVal.classify in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError, "NIF markup numbers must be finite")
  of nkUInt:
    if node.rawUInt.startsWith("-"):
      raise newException(ValueError, "NIF markup unsigned numbers cannot be negative")
  of nkStrLit, nkCharLit, nkIdent, nkInt, nkSymbolDef:
    discard
  else:
    raise newException(ValueError, "unsupported NIF markup node: " & $node.kind)

proc parseMarkup(source: string, language = "", lineBased = false): NifModule =
  if source.len > 64 * 1024 * 1024:
    raise newException(ValueError, "NIF markup exceeds the byte limit")
  let options = defaultNifOptions()
  options.maxDepth = 256
  options.expandGlobalSymbols = false
  options.preserveComments = false
  options.allowLineBased = lineBased
  try:
    result = fromNif(source, options)
  except OpenParserNifError as error:
    raise newException(ValueError, error.msg)
  if result.len > 0 and result[0].kind == nkDirective and result[0].tag == ".nif27":
    if result[0].children.len != 0:
      raise newException(ValueError, "the NIF version marker takes no values")
    result.delete(0)
  if language.len > 0 and result.len > 0 and result[0].kind == nkDirective and
      result[0].tag == ".lang":
    if result[0].children.len != 1 or result[0].children[0].kind != nkStrLit or
        result[0].children[0].strVal != language:
      raise newException(ValueError, "expected the " & language & " language directive")
    result.delete(0)
  if result.len == 0:
    raise newException(ValueError, "NIF markup is empty")
  var count: int
  for node in result:
    node.validateNode(count)

proc stringValue(node: NifNode): string =
  case node.kind
  of nkStrLit:
    node.strVal
  of nkCharLit:
    node.charVal
  else:
    raise newException(ValueError, "expected a NIF string or character literal")

proc numberValue(node: NifNode): string =
  case node.kind
  of nkInt:
    $node.intVal
  of nkUInt:
    $node.uintVal
  of nkFloat:
    $node.floatVal
  else:
    raise newException(ValueError, "expected a NIF number")

proc value(node: NifNode): string =
  case node.kind
  of nkStrLit, nkCharLit:
    return node.stringValue()
  of nkInt, nkUInt, nkFloat:
    return node.numberValue()
  else:
    discard
  if node.name() != "hexColor":
    raise newException(ValueError, "expected a string, number, or hexColor value")
  node.requireChildren(1)
  let color = node.children[0]
  var digits: string
  case color.kind
  of nkStrLit:
    digits = color.strVal
  of nkInt, nkUInt:
    let raw = if color.kind == nkInt: color.rawInt else: color.rawUInt
    if not raw.startsWith("0x"):
      raise newException(ValueError, "hexColor integers require a 0x prefix")
    digits = raw[2 .. ^1].replace("_", "")
    if digits.endsWith("u"):
      digits.setLen(digits.len - 1)
  else:
    raise newException(ValueError, "hexColor requires hex digits or a 0x integer")
  if digits.len notin [3, 4, 6, 8]:
    raise newException(ValueError, "hexColor requires 3, 4, 6, or 8 hex digits")
  for ch in digits:
    if ch notin HexDigits:
      raise newException(ValueError, "invalid hexColor digit")
  "#" & digits

proc word(node: NifNode): string =
  case node.kind
  of nkIdent:
    node.ident
  of nkStrLit:
    node.strVal
  else:
    raise newException(ValueError, "expected a NIF identifier or string")

proc cssIdentifier(value: string): string =
  if value.len == 0 or value[0] notin Letters + {'_'}:
    raise newException(
      ValueError, "expected a style name starting with a letter or underscore"
    )
  for ch in value:
    if ch notin Letters + Digits + {'_', '-'}:
      raise newException(ValueError, "unsupported style name: " & value)
  value

proc simpleSelector(node: NifNode): string =
  let tag = node.name()
  if tag notin ["role", "id", "class", "state"]:
    raise newException(ValueError, "expected role, id, class, or state selector")
  node.requireChildren(1)
  let value = node.children[0].word().cssIdentifier()
  case tag
  of "role":
    value.htmlName()
  of "id":
    "#" & value
  of "class":
    "." & value
  of "state":
    ":" & value.htmlName()
  else:
    ""

proc selector(node: NifNode): string =
  if node.kind == nkStrLit:
    return node.strVal
  case node.name()
  of "any":
    for child in node.children:
      if result.len > 0:
        result.add ", "
      result.add child.selector()
    if result.len == 0:
      raise newException(ValueError, "any requires at least one selector")
  of "match":
    var role: string
    var hasId = false
    for child in node.children:
      let tag = child.name()
      let part = child.simpleSelector()
      case tag
      of "role":
        if role.len > 0:
          raise newException(ValueError, "match accepts at most one role")
        role = part
      of "id":
        if hasId:
          raise newException(ValueError, "match accepts at most one id")
        hasId = true
        result.add part
      else:
        result.add part
    if role.len == 0 and result.len == 0:
      raise newException(ValueError, "match requires at least one selector")
    result = role & result
  else:
    result = node.simpleSelector()

proc styleValue(node: NifNode): string =
  if node.children.len == 0:
    raise newException(ValueError, "expected a style value")
  let first = node.children[0]
  if first.kind in {nkInt, nkUInt, nkFloat}:
    var index: int
    while index < node.children.len:
      if result.len > 0:
        result.add ' '
      result.add node.children[index].numberValue()
      inc index
      if index < node.children.len and node.children[index].kind == nkIdent:
        if node.children[index].ident != "px":
          raise newException(ValueError, "the theme engine supports px lengths")
        result.add "px"
        inc index
    return
  node.requireChildren(1)
  case first.kind
  of nkIdent:
    result = first.word().cssIdentifier().htmlName()
  of nkCompound:
    if first.name() == "var":
      first.requireChildren(1)
      let token = first.children[0].word().cssIdentifier().htmlName()
      result = "var(--" & token & ")"
    else:
      result = first.value()
  of nkStrLit, nkCharLit:
    result = first.stringValue()
  else:
    raise newException(ValueError, "unsupported style value")

proc escapedHtml(value: string): string =
  value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
    "\"", "&quot;"
  )

proc emitElement(node: NifNode, output: var string) =
  if node.kind in {nkStrLit, nkCharLit}:
    output.add escapedHtml(node.stringValue())
    return
  let tag = node.name().htmlName()
  if tag in ["attrs", "kv"]:
    raise newException(ValueError, "attrs must be the first child of an element")
  output.add '<' & tag
  var childIndex: int
  if node.children.len > 0 and node.children[0].kind == nkCompound and
      node.children[0].name() == "attrs":
    var attributes = initHashSet[string]()
    for entry in node.children[0].children:
      if entry.name() != "kv":
        raise newException(ValueError, "attrs requires kv entries")
      entry.requireChildren(2)
      let key = entry.children[0].stringValue()
      if key.len == 0 or key.toLowerAscii() in attributes:
        raise newException(ValueError, "empty or duplicate attribute: " & key)
      for ch in key:
        if ch notin Letters + Digits + {'-', '_'}:
          raise newException(ValueError, "invalid attribute name: " & key)
      attributes.incl key.toLowerAscii()
      output.add ' ' & key & "=\"" & entry.children[1].value().escapedHtml() & '"'
    inc childIndex
  output.add '>'
  if tag in ["input", "img", "br"]:
    if node.children.len != childIndex:
      raise newException(ValueError, "unexpected content in " & tag)
  else:
    while childIndex < node.children.len:
      node.children[childIndex].emitElement(output)
      inc childIndex
    output.add "</" & tag & '>'

proc nifGuiMarkup*(source: string): string =
  ## Converts elements with `(attrs (kv "name" value))` blocks to GUI markup.
  ## Camel-case tags such as `nkStackView` map to native `nk-stack-view` tags.
  var nodes = parseMarkup(source)
  let windowDocument = nodes[0].kind == nkCompound and nodes[0].tag == "Window"
  for node in nodes.mitems:
    if node.kind == nkCompound and node.tag[0] in {'A' .. 'Z'}:
      node = node.expandGuiShorthand()
  if windowDocument:
    newNifCompound("nkMain", "nkMain", nodes).emitElement(result)
  else:
    for node in nodes:
      node.emitElement(result)

proc emitDeclarations(
    nodes: openArray[NifNode], output: var string, customProperties: bool
) =
  for declaration in nodes:
    var property = declaration.name().htmlName()
    if customProperties:
      property = "--" & property
    elif property.startsWith("nimkit-"):
      property = "-" & property
    output.add "  " & property & ": " & declaration.styleValue() & ";\n"

proc nifStylesheet*(source: string): string =
  ## Converts native selectors and values into the existing theme engine's CSS.
  ## Numbers support NIF bases; hexColor keeps leading zeros and alpha digits.
  var nodes = parseMarkup(source, language = "nimkit-css", lineBased = true)
  if nodes[0].kind == nkCompound and nodes[0].tag == "style":
    nodes = @[nodes.expandStyleShorthand()]
  if nodes.len != 1 or nodes[0].name() != "stylesheet":
    raise newException(ValueError, "expected one stylesheet root")
  for node in nodes[0].children:
    case node.name()
    of "tokens":
      result.add ":root {\n"
      node.children.emitDeclarations(result, customProperties = true)
      result.add "}\n"
    of "rule":
      if node.children.len == 0:
        raise newException(ValueError, "rule requires a selector")
      result.add node.children[0].selector() & " {\n"
      node.children.toOpenArray(1, node.children.high).emitDeclarations(
        result, customProperties = false
      )
      result.add "}\n"
    else:
      raise newException(ValueError, "stylesheet requires tokens or rule elements")
