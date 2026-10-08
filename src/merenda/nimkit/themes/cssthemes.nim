## Compile a bounded CSS theming vocabulary into immutable NimKit themes.
##
## Selectors describe semantic roles, style ids/classes and widget states.
## Appearance inheritance provides stylesheet scope; browser layout, tree
## selectors and per-view custom-property inheritance are not supported.

import std/[sets, strutils, tables]
import stylus

import ./[defaulttheme, themecore]
import ./private/cssvalues
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
        let patch = declarationPatch(declaration.name, declaration.values)
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
