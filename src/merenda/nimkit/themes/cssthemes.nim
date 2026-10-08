## Compile a bounded CSS theming vocabulary into immutable NimKit themes.
##
## Selectors describe semantic roles, style ids/classes and widget states.
## Appearance inheritance provides stylesheet scope; browser layout, tree
## selectors and per-view custom-property inheritance are not supported.

import std/[math, sets, strutils, tables]
import stylus
from figdraw import SystemTypeface

import ./[defaulttheme, themecore]
import ../foundation/types

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

  CssThemeResult* = object
    ## A usable theme plus diagnostics for skipped or unresolved declarations.
    theme*: Theme
    diagnostics*: seq[CssDiagnostic]

  LocatedToken = object
    value: Token
    line, column: int

  CssSelector = object
    selector: StyleSelector
    specificity: array[3, int]
    hasRole, root: bool

  CssDeclaration = object
    name: string
    values: seq[LocatedToken]
    important: bool
    line, column: int

  CssRule = object
    selectors: seq[CssSelector]
    declarations: seq[CssDeclaration]

  CssParser = object
    tokens: seq[LocatedToken]
    index: int
    diagnostics: seq[CssDiagnostic]

proc diagnostic(parser: var CssParser, token: LocatedToken, message: string) =
  parser.diagnostics.add CssDiagnostic(
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

proc tokenize(source: string, parser: var CssParser) =
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
      parser.diagnostics.add CssDiagnostic(
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
        parser.diagnostic(location, "Unclosed or unsupported quoted string")
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
        parser.diagnostic(location, "Unclosed CSS comment")
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
    parser.tokens.add LocatedToken(value: token, line: line, column: column)
    source.advanceLocation(start, finish, line, column)

func roleName(role: StyleRole): string =
  let name = ($role)[2 ..^ 1]
  for index, character in name:
    if character in {'A' .. 'Z'}:
      if index > 0:
        result.add '-'
      result.add character.toLowerAscii()
    else:
      result.add character

proc parseRole(name: string, selector: var CssSelector): bool =
  let normalized = name.toLowerAscii()
  if normalized == "label":
    selector.selector.role = srTextField
    selector.selector.classes.add LabelStyleClass
    return true
  let canonical =
    case normalized
    of "checkbox": "check-box"
    of "radio": "radio-button"
    else: normalized
  for role in StyleRole:
    if canonical == role.roleName():
      selector.selector.role = role
      return true

proc parseState(name: string, state: var WidgetState): bool =
  case name.toLowerAscii()
  of "hover":
    state = ssHovered
  of "active":
    state = ssActive
  of "focus":
    state = ssFocused
  of "focus-visible":
    state = ssFocusVisible
  of "focus-within":
    state = ssFocusWithin
  of "disabled":
    state = ssDisabled
  of "selected", "checked":
    state = ssSelected
  of "open":
    state = ssOpen
  of "highlighted":
    state = ssHighlighted
  of "pressed":
    state = ssPressed
  of "accent":
    state = ssAccent
  of "alternating":
    state = ssAlternating
  of "invalid":
    state = ssInvalid
  else:
    return
  true

proc compact(tokens: openArray[LocatedToken]): seq[LocatedToken] =
  for token in tokens:
    if token.value.kind notin {tkWhiteSpace, tkComment}:
      result.add token

proc parseSelector(
    parser: var CssParser, tokens: seq[LocatedToken], selector: var CssSelector
): bool =
  var
    index = 0
    seen = false
    separated = false
  while index < tokens.len:
    let token = tokens[index]
    let value = token.value
    if value.kind in {tkWhiteSpace, tkComment}:
      if value.kind == tkWhiteSpace and seen:
        separated = true
      inc index
    else:
      if separated:
        parser.diagnostic(token, "Tree selector combinators are unsupported")
        return
      case value.kind
      of tkIdent:
        if seen or not parseRole(value.ident, selector):
          parser.diagnostic(token, "Unknown or misplaced style role: " & value.ident)
          return
        selector.hasRole = true
        inc selector.specificity[2]
        inc index
      of tkIDHash, tkHash:
        if selector.selector.id.len > 0:
          parser.diagnostic(token, "Repeated ids are unsupported")
          return
        selector.selector.id = if value.kind == tkIDHash: value.idHash else: value.hash
        inc selector.specificity[0]
        inc index
      of tkDelim:
        if value.delim == '*' and not seen:
          inc index
        elif value.delim == '.' and index + 1 < tokens.len and
            tokens[index + 1].value.kind == tkIdent:
          selector.selector.classes.add tokens[index + 1].value.ident
          inc selector.specificity[1]
          index += 2
        else:
          parser.diagnostic(token, "Unsupported selector syntax")
          return
      of tkColon:
        if index + 1 >= tokens.len or tokens[index + 1].value.kind != tkIdent:
          parser.diagnostic(token, "Unsupported pseudo class")
          return
        let name = tokens[index + 1].value.ident
        if name.toLowerAscii() == "root" and not seen and index + 2 == tokens.len:
          selector.root = true
        else:
          var state: WidgetState
          if not parseState(name, state):
            parser.diagnostic(token, "Unknown pseudo class: " & name)
            return
          selector.selector.states.incl state
          inc selector.specificity[1]
        index += 2
      else:
        parser.diagnostic(token, "Unsupported selector syntax")
        return
      seen = true
  result = seen

proc parseSelectors(
    parser: var CssParser, tokens: seq[LocatedToken]
): seq[CssSelector] =
  var start = 0
  for index in 0 .. tokens.len:
    if index == tokens.len or tokens[index].value.kind == tkComma:
      var ending = index
      while start < ending and tokens[start].value.kind in {tkWhiteSpace, tkComment}:
        inc start
      while ending > start and tokens[ending - 1].value.kind in {
        tkWhiteSpace, tkComment
      }
      :
        dec ending
      var selector: CssSelector
      if start == ending or not parser.parseSelector(tokens[start ..< ending], selector):
        if start == ending:
          parser.diagnostic(
            (if tokens.len > 0: tokens[0]
            else: LocatedToken(line: 1, column: 1)),
            "Empty selector",
          )
        return @[]
      result.add selector
      start = index + 1
  if result.len > 1:
    for selector in result:
      if selector.root:
        parser.diagnostic(tokens[0], ":root must be a standalone selector")
        return @[]

proc parseDeclaration(
    parser: var CssParser, tokens: seq[LocatedToken], declaration: var CssDeclaration
): bool =
  let values = tokens.compact()
  if values.len == 0:
    return
  if values.len < 3 or values[0].value.kind != tkIdent or values[1].value.kind != tkColon:
    parser.diagnostic(values[0], "Expected property: value")
    return
  declaration.name = values[0].value.ident
  declaration.line = values[0].line
  declaration.column = values[0].column
  declaration.values = values[2 ..^ 1]
  let count = declaration.values.len
  if count >= 2 and declaration.values[count - 2].value.kind == tkDelim and
      declaration.values[count - 2].value.delim == '!' and
      declaration.values[count - 1].value.kind == tkIdent and
      declaration.values[count - 1].value.ident.toLowerAscii() == "important":
    declaration.important = true
    declaration.values.setLen(count - 2)
  if declaration.values.len == 0:
    parser.diagnostic(values[0], "Missing property value")
    return
  true

proc parseRule(parser: var CssParser, rules: var seq[CssRule])

proc parseRules(parser: var CssParser): seq[CssRule] =
  while parser.index < parser.tokens.len:
    while parser.index < parser.tokens.len and
        parser.tokens[parser.index].value.kind in {tkWhiteSpace, tkComment, tkSemicolon}:
      inc parser.index
    if parser.index >= parser.tokens.len:
      break
    let start = parser.index
    if parser.tokens[start].value.kind == tkAtKeyword:
      parser.diagnostic(parser.tokens[start], "CSS at-rules are unsupported")
      var depth = 0
      while parser.index < parser.tokens.len:
        let kind = parser.tokens[parser.index].value.kind
        inc parser.index
        if kind == tkCurlyBracketBlock:
          inc depth
        elif kind == tkCloseCurlyBracket:
          dec depth
          if depth <= 0:
            break
        elif kind == tkSemicolon and depth == 0:
          break
    elif parser.tokens[start].value.kind == tkCloseCurlyBracket:
      parser.diagnostic(parser.tokens[start], "Unmatched closing block")
      inc parser.index
    else:
      parser.parseRule(result)

proc parseRule(parser: var CssParser, rules: var seq[CssRule]) =
  let start = parser.index
  while parser.index < parser.tokens.len and
      parser.tokens[parser.index].value.kind != tkCurlyBracketBlock:
    inc parser.index
  if parser.index == parser.tokens.len:
    parser.diagnostic(parser.tokens[start], "Expected a CSS declaration block")
    return
  let selectors = parser.parseSelectors(parser.tokens[start ..< parser.index])
  inc parser.index
  var
    rule = CssRule(selectors: selectors)
    declarationStart = parser.index
    nested = 0
    closed = false
  while parser.index < parser.tokens.len:
    let token = parser.tokens[parser.index]
    case token.value.kind
    of tkFunction, tkParenBlock, tkSquareBracketBlock, tkCurlyBracketBlock:
      inc nested
    of tkCloseParen, tkCloseSquareBracket:
      if nested > 0:
        dec nested
      else:
        parser.diagnostic(token, "Unmatched closing delimiter")
    of tkCloseCurlyBracket:
      if nested > 0:
        dec nested
      else:
        var declaration: CssDeclaration
        if parser.parseDeclaration(
          parser.tokens[declarationStart ..< parser.index], declaration
        ):
          rule.declarations.add declaration
        closed = true
    of tkSemicolon:
      if nested == 0:
        var declaration: CssDeclaration
        if parser.parseDeclaration(
          parser.tokens[declarationStart ..< parser.index], declaration
        ):
          rule.declarations.add declaration
        declarationStart = parser.index + 1
    else:
      discard
    inc parser.index
    if closed:
      break
  if not closed:
    parser.diagnostic(parser.tokens[start], "Unclosed CSS declaration block")
  elif selectors.len > 0:
    rules.add rule

proc singleVariable(tokens: seq[LocatedToken], value: var StyleValue): bool =
  if tokens.len == 3 and tokens[0].value.kind == tkFunction and
      tokens[0].value.fnName.toLowerAscii() == "var" and tokens[1].value.kind == tkIdent and
      tokens[1].value.ident.startsWith("--") and tokens[2].value.kind == tkCloseParen:
    value = styleToken(tokens[1].value.ident)
    return true

proc lengthValue(token: Token, value: var float32, signed = false): bool =
  case token.kind
  of tkNumber:
    value = token.nValue
  of tkDimension:
    if token.unit.toLowerAscii() != "px":
      return
    value = token.dValue
  else:
    return
  result = value.classify notin {fcNan, fcInf, fcNegInf} and (signed or value >= 0)

proc colorValue(tokens: seq[LocatedToken], value: var Color): bool =
  if tokens.len == 1:
    let token = tokens[0].value
    var text: string
    case token.kind
    of tkIdent:
      if token.ident.toLowerAscii() == "transparent":
        value = color(0, 0, 0, 0)
        return true
      text = token.ident.toLowerAscii()
    of tkHash:
      text = "#" & token.hash
    of tkIDHash:
      text = "#" & token.idHash
    else:
      return
    if text.len in [5, 9] and text[0] == '#':
      try:
        let digits = text[1 ..^ 1]
        if digits.len == 4:
          value = color(
            parseHexInt($digits[0]).float32 / 15,
            parseHexInt($digits[1]).float32 / 15,
            parseHexInt($digits[2]).float32 / 15,
            parseHexInt($digits[3]).float32 / 15,
          )
        else:
          value = color(
            parseHexInt(digits[0 .. 1]).float32 / 255,
            parseHexInt(digits[2 .. 3]).float32 / 255,
            parseHexInt(digits[4 .. 5]).float32 / 255,
            parseHexInt(digits[6 .. 7]).float32 / 255,
          )
        return true
      except ValueError:
        return
    try:
      value = parseHtmlColor(text)
      return true
    except InvalidColor:
      return
  if tokens.len >= 5 and tokens[0].value.kind == tkFunction and
      tokens[^1].value.kind == tkCloseParen:
    let name = tokens[0].value.fnName.toLowerAscii()
    if name notin ["rgb", "rgba"]:
      return
    var components: seq[float32]
    var hasComma = false
    for index in 1 ..< tokens.high:
      if tokens[index].value.kind == tkComma:
        hasComma = true
    for index in 1 ..< tokens.high:
      let token = tokens[index].value
      if hasComma and ((index mod 2 == 0) != (token.kind == tkComma)):
        return
      if token.kind != tkComma:
        var amount: float32
        if token.kind == tkPercentage:
          amount = token.pUnitValue
        elif token.kind == tkNumber:
          amount = token.nValue
          if components.len < 3:
            amount /= 255
        else:
          return
        if amount.classify in {fcNan, fcInf, fcNegInf}:
          return
        components.add max(0.0'f32, min(1.0'f32, amount))
    if components.len == (if name == "rgb": 3 else: 4) and
        (not hasComma or tokens.len == components.len * 2 + 1):
      value = color(
        components[0],
        components[1],
        components[2],
        (if components.len == 4: components[3] else: 1.0'f32),
      )
      return true

proc basicValue(tokens: seq[LocatedToken], value: var StyleValue): bool =
  if tokens.singleVariable(value):
    return true
  var c: Color
  if tokens.colorValue(c):
    value = styleColor(c)
    return true
  if tokens.len == 1:
    var amount: float32
    if tokens[0].value.lengthValue(amount, signed = true):
      value = styleLength(amount)
      return true
    case tokens[0].value.kind
    of tkIdent:
      value = styleKeyword(tokens[0].value.ident)
    of tkQuotedString:
      value = styleKeyword(tokens[0].value.qStr)
    else:
      return
    return true

proc fourLengths(tokens: seq[LocatedToken], values: var array[4, float32]): bool =
  if tokens.len notin 1 .. 4:
    return
  var amounts: seq[float32]
  for token in tokens:
    var amount: float32
    if not token.value.lengthValue(amount):
      return
    amounts.add amount
  values =
    case amounts.len
    of 1:
      [amounts[0], amounts[0], amounts[0], amounts[0]]
    of 2:
      [amounts[0], amounts[1], amounts[0], amounts[1]]
    of 3:
      [amounts[0], amounts[1], amounts[2], amounts[1]]
    else:
      [amounts[0], amounts[1], amounts[2], amounts[3]]
  true

proc shadowValue(tokens: seq[LocatedToken], value: var StyleValue): bool =
  if tokens.len == 1 and tokens[0].value.kind == tkIdent and
      tokens[0].value.ident.toLowerAscii() == "none":
    value = styleShadows([])
    return true
  var
    shadows: seq[BoxShadow]
    start = 0
    depth = 0
  for index in 0 .. tokens.len:
    if index < tokens.len:
      case tokens[index].value.kind
      of tkFunction, tkParenBlock:
        inc depth
      of tkCloseParen:
        dec depth
      else:
        discard
    if index == tokens.len or (tokens[index].value.kind == tkComma and depth == 0):
      var
        lengths: seq[float32]
        colors: seq[LocatedToken]
        inset = false
        colorDepth = 0
      for token in tokens[start ..< index]:
        if token.value.kind == tkFunction:
          inc colorDepth
          colors.add token
        elif token.value.kind == tkCloseParen:
          dec colorDepth
          colors.add token
        elif colorDepth > 0:
          colors.add token
        elif token.value.kind == tkIdent and token.value.ident.toLowerAscii() == "inset":
          inset = true
        else:
          var amount: float32
          if token.value.lengthValue(amount, signed = true):
            lengths.add amount
          else:
            colors.add token
      var shadowColor = color(0, 0, 0, 1)
      if lengths.len notin 2 .. 4 or
          (colors.len > 0 and not colors.colorValue(shadowColor)):
        return
      let blur =
        if lengths.len >= 3:
          lengths[2]
        else:
          0.0'f32
      if blur < 0:
        return
      shadows.add BoxShadow(
        kind: (if inset: bskInset else: bskDrop),
        color: shadowColor,
        x: lengths[0],
        y: lengths[1],
        blur: blur,
        spread: (if lengths.len >= 4: lengths[3] else: 0.0'f32),
      )
      start = index + 1
  value = styleShadows(shadows)
  true

proc declarationPatch(declaration: CssDeclaration): StylePatch =
  let name = declaration.name.toLowerAscii()
  let tokens = declaration.values
  var
    value: StyleValue
    c: Color
    amount: float32
  let variable = tokens.singleVariable(value)
  result = newStylePatch()
  case name
  of "color", "background", "background-color", "border-color",
      "-nimkit-focus-ring-color":
    if not variable:
      if not tokens.colorValue(c):
        return nil
      value = styleColor(c)
    case name
    of "color":
      result[StyleTextColor] = value
    of "background", "background-color":
      result[StyleFill] = value
    of "border-color":
      result[StyleBorderColor] = value
    else:
      result[StyleFocusRingColor] = value
  of "border-width", "font-size", "-nimkit-focus-ring-width", "-nimkit-focus-ring-inset":
    if not variable:
      if tokens.len != 1 or
          not tokens[0].value.lengthValue(
            amount, signed = name == "-nimkit-focus-ring-inset"
          ):
        return nil
      value = styleLength(amount)
    let key =
      case name
      of "border-width": StyleBorderWidth
      of "font-size": StyleFontSize
      of "-nimkit-focus-ring-width": StyleFocusRingWidth
      else: StyleFocusRingInset
    result[key] = value
  of "padding", "border-radius":
    var lengths: array[4, float32]
    if not variable and not tokens.fourLengths(lengths):
      return nil
    if name == "padding":
      if not variable:
        value = styleInsets(insets(lengths[0], lengths[3], lengths[2], lengths[1]))
      result[StylePadding] = value
      result[StyleTextInsets] = value
    else:
      result[StyleCornerRadius] =
        if variable:
          value
        else:
          styleLength(lengths[0])
      for index, key in [
        StyleCornerRadiusTopLeft, StyleCornerRadiusTopRight,
        StyleCornerRadiusBottomRight, StyleCornerRadiusBottomLeft,
      ]:
        result[key] =
          if variable:
            value
          else:
            styleLength(lengths[index])
  of "font-family", "font-style", "-nimkit-chrome":
    if not variable:
      if tokens.len != 1 or tokens[0].value.kind notin {tkIdent, tkQuotedString}:
        return nil
      value = styleKeyword(
        if tokens[0].value.kind == tkIdent:
          tokens[0].value.ident
        else:
          tokens[0].value.qStr
      )
    if name == "font-family":
      result[StyleFontName] = value
      for key in [
        StyleFontFace, StyleItalicFontFace, StyleBoldFontFace, StyleBoldItalicFontFace
      ]:
        result[key] = styleFontFace(SystemTypeface())
    elif name == "font-style":
      if not variable and value.keyword notin ["normal", "italic", "oblique"]:
        return nil
      result[StyleFontSlant] = value
    else:
      result[StyleChrome] = value
  of "-nimkit-minimum-size":
    if variable:
      result[StyleMinimumSize] = value
    elif tokens.len in 1 .. 2:
      var width, height: float32
      if not tokens[0].value.lengthValue(width):
        return nil
      height = width
      if tokens.len == 2 and not tokens[1].value.lengthValue(height):
        return nil
      result[StyleMinimumSize] = styleSize(initSize(width, height))
    else:
      return nil
  of "box-shadow":
    if not variable and not tokens.shadowValue(value):
      return nil
    result[StyleBoxShadows] = value
  else:
    return nil

proc parseCssTheme*(source: string, base: Theme = initTheme()): CssThemeResult =
  ## Compiles CSS into `base`, retaining valid declarations and diagnostics.
  ##
  ## Reuse the original base to replace a stylesheet. Passing a previously
  ## compiled theme appends CSS in the same cascade and revalidates typed vars.
  var parser: CssParser
  source.tokenize(parser)
  let rules = parser.parseRules()
  var builder = initThemeBuilder(base)
  for rule in rules:
    if rule.selectors[0].root:
      for declaration in rule.declarations:
        var value: StyleValue
        if not declaration.name.startsWith("--") or
            not declaration.values.basicValue(value):
          parser.diagnostic(
            LocatedToken(line: declaration.line, column: declaration.column),
            ":root permits only typed custom properties",
          )
        else:
          builder.setCssToken(declaration.name, value, declaration.important)
  let rootTheme = builder.finish()
  for rule in rules:
    if not rule.selectors[0].root:
      for declaration in rule.declarations:
        let patch = declaration.declarationPatch()
        var valid = not patch.isNil
        if valid:
          for key, value in patch.values:
            var resolved: StyleValue
            if value.kind != svToken and
                not rootTheme.resolveCssValue(value, key, resolved):
              valid = false
        if not valid:
          parser.diagnostic(
            LocatedToken(line: declaration.line, column: declaration.column),
            "Unsupported property or invalid value: " & declaration.name,
          )
        else:
          let order = builder.nextCssSourceOrder()
          for selector in rule.selectors:
            if selector.hasRole:
              builder.addCssRule(
                selector.selector, patch, selector.specificity, order,
                declaration.important, declaration.line, declaration.column,
              )
            else:
              for role in StyleRole:
                var expanded = selector.selector
                expanded.role = role
                builder.addCssRule(
                  expanded, patch, selector.specificity, order, declaration.important,
                  declaration.line, declaration.column,
                )
  result.theme = builder.finish()
  var reported = initHashSet[int]()
  for rule in result.theme.rules:
    if rule.origin == sroCss:
      for key, value in rule.patch.values:
        if value.kind == svToken:
          var resolved: StyleValue
          if not result.theme.resolveCssValue(value, key, resolved) and
              rule.sourceOrder notin reported:
            reported.incl rule.sourceOrder
            parser.diagnostics.add CssDiagnostic(
              line: rule.line,
              column: rule.column,
              message:
                "Unresolved or wrong-type variable " & value.token &
                " (missing, cyclic, or beyond 16 reference steps)",
            )
  result.diagnostics = move parser.diagnostics

proc loadCssTheme*(path: string, base: Theme = initTheme()): CssThemeResult =
  ## Reads a stylesheet. Filesystem failures raise `IOError` or `OSError`.
  parseCssTheme(readFile(path), base)
