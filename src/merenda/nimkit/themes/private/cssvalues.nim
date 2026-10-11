## Internal typed CSS declaration parsing. The tokenizer owns source locations.

import std/[math, strutils, tables]
import stylus
from figdraw import SystemTypeface

import ../stylevalues
import ../../foundation/types
import ./[cssproperties, csstokens]

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

proc fillValue*(tokens: seq[LocatedToken], value: var StyleValue): bool =
  var c: Color
  if tokens.colorValue(c):
    value = styleColor(c)
    return true
  if tokens.len < 5 or tokens[0].value.kind != tkFunction or
      tokens[0].value.fnName.toLowerAscii() != "linear-gradient" or
      tokens[^1].value.kind != tkCloseParen:
    return
  var parts: seq[seq[LocatedToken]]
  var start = 1
  var depth = 0
  for index in 1 ..< tokens.high:
    case tokens[index].value.kind
    of tkFunction, tkParenBlock:
      inc depth
    of tkCloseParen:
      dec depth
    else:
      discard
    if tokens[index].value.kind == tkComma and depth == 0:
      parts.add tokens[start ..< index]
      start = index + 1
  parts.add tokens[start ..< tokens.high]
  var axis = fgaY
  var reverse = false
  if parts.len > 0 and parts[0].len > 0:
    let direction = parts[0]
    if direction[0].value.kind == tkIdent and
        direction[0].value.ident.toLowerAscii() == "to":
      var names: seq[string]
      for token in direction:
        if token.value.kind != tkIdent:
          return
        names.add token.value.ident.toLowerAscii()
      case names.join(" ")
      of "to bottom":
        axis = fgaY
      of "to top":
        axis = fgaY
        reverse = true
      of "to right":
        axis = fgaX
      of "to left":
        axis = fgaX
        reverse = true
      of "to bottom right", "to right bottom":
        axis = fgaDiagTLBR
      of "to top left", "to left top":
        axis = fgaDiagTLBR
        reverse = true
      of "to top right", "to right top":
        axis = fgaDiagBLTR
      of "to bottom left", "to left bottom":
        axis = fgaDiagBLTR
        reverse = true
      else:
        return
      parts.delete(0)
    elif direction.len == 1 and direction[0].value.kind == tkDimension and
        direction[0].value.unit.toLowerAscii() == "deg":
      let angle = direction[0].value.dValue
      case angle
      of 0.0'f32, 360.0'f32:
        axis = fgaY
        reverse = true
      of 45.0'f32:
        axis = fgaDiagBLTR
      of 90.0'f32:
        axis = fgaX
      of 135.0'f32:
        axis = fgaDiagTLBR
      of 180.0'f32:
        axis = fgaY
      of 225.0'f32:
        axis = fgaDiagBLTR
        reverse = true
      of 270.0'f32:
        axis = fgaX
        reverse = true
      of 315.0'f32:
        axis = fgaDiagTLBR
        reverse = true
      else:
        return
      parts.delete(0)
  if parts.len notin 2 .. 3:
    return
  var colors: seq[Color]
  var mid = 128'u8
  for index, part in parts:
    var ending = part.len
    if ending == 0:
      return
    if part[^1].value.kind == tkPercentage:
      let position = part[^1].value.pUnitValue
      if position.classify in {fcNan, fcInf, fcNegInf} or position < 0 or position > 1:
        return
      if index == 0 and position != 0 or index == parts.high and position != 1:
        return
      if index == 1 and parts.len == 3:
        mid = uint8(round(position * 255))
      dec ending
    var stop: Color
    if ending == 0 or not colorValue(part[0 ..< ending], stop):
      return
    colors.add stop
  if reverse:
    swap(colors[0], colors[^1])
    mid = 255'u8 - mid
  value = styleFill(
    if colors.len == 2:
      linear(colors[0], colors[1], axis)
    else:
      linear(colors[0], colors[1], colors[2], axis, mid)
  )
  true

proc expressionValue(tokens: seq[LocatedToken], property = ""): StyleValue =
  var parts: seq[string]
  for token in tokens:
    parts.add token.text
  StyleValue(kind: svCssExpression, cssProperty: property, cssText: parts.join(" "))

proc cssRootValue*(tokens: seq[LocatedToken]): StyleValue =
  ## Keep CSS syntax until its destination is known; aliases may carry native resources.
  if not tokens.singleVariable(result):
    result = expressionValue(tokens)

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

proc extensionValue(
    spec: CssPropertySpec, tokens: seq[LocatedToken], value: var StyleValue
): bool =
  if tokens.singleVariable(value):
    return true
  case spec.kind
  of cpkColor:
    var c: Color
    if tokens.colorValue(c):
      value = styleColor(c)
      return true
  of cpkFill:
    return tokens.fillValue(value)
  of cpkLength:
    var amount: float32
    if tokens.len == 1 and (not spec.unitless or tokens[0].value.kind == tkNumber) and
        tokens[0].value.lengthValue(amount, signed = spec.minimum < 0):
      value = styleLength(amount)
      return true
  of cpkSize:
    if tokens.len in 1 .. 2:
      var width, height: float32
      if tokens[0].value.lengthValue(width):
        height = width
        if tokens.len == 1 or tokens[1].value.lengthValue(height):
          value = styleSize(initSize(width, height))
          return true
  of cpkInsets:
    var lengths: array[4, float32]
    if tokens.fourLengths(lengths):
      value = styleInsets(insets(lengths[0], lengths[3], lengths[2], lengths[1]))
      return true
  of cpkShadows:
    return tokens.shadowValue(value)
  of cpkFontFace:
    if tokens.len == 1 and tokens[0].value.kind == tkIdent and
        tokens[0].value.ident.toLowerAscii() == "none":
      value = styleFontFace(SystemTypeface())
      return true
  of cpkKeyword:
    if tokens.len == 1:
      let token = tokens[0].value
      if token.kind in {tkIdent, tkQuotedString}:
        value = styleKeyword(if token.kind == tkIdent: token.ident else: token.qStr)
        return true

proc geometryValue(
    spec: CssGeometryProperty, token: Token, value: var StyleValue
): bool =
  if token.kind == tkIdent and token.ident.toLowerAscii() == "auto":
    value = styleConstraints([])
    return true
  var constraint = StyleLayoutConstraint(
    attribute: spec.attribute, relation: spec.relation, priority: spec.priority
  )
  if token.kind == tkPercentage and spec.name in ["width", "height"]:
    let factor = token.pUnitValue
    if factor.classify in {fcNan, fcInf, fcNegInf} or factor < 0:
      return
    if factor > 0:
      constraint.target = sltParent
      constraint.targetAttribute = spec.attribute
      constraint.multiplier = factor
  else:
    if not token.lengthValue(constraint.constant, signed = spec.edge):
      return
    if spec.edge:
      constraint.target = sltParent
      constraint.targetAttribute = spec.attribute
      if spec.attribute in {atRight, atBottom}:
        constraint.constant = -constraint.constant
  value = styleConstraints([constraint])
  true

proc parseAttribute(name: string, attribute: var LayoutAttribute): bool =
  case name.toLowerAscii()
  of "left":
    attribute = atLeft
  of "right":
    attribute = atRight
  of "leading":
    attribute = atLeading
  of "trailing":
    attribute = atTrailing
  of "center-x":
    attribute = atCenterX
  of "top":
    attribute = atTop
  of "bottom":
    attribute = atBottom
  of "center-y":
    attribute = atCenterY
  of "first-baseline":
    attribute = atFirstBaseline
  of "last-baseline":
    attribute = atLastBaseline
  of "width":
    attribute = atWidth
  of "height":
    attribute = atHeight
  else:
    return
  true

func delimiter(token: Token, character: char): bool =
  token.kind == tkDelim and token.delim == character

proc constraintValue(
    tokens: openArray[LocatedToken], constraint: var StyleLayoutConstraint
): bool =
  var ending = tokens.len
  if ending >= 3 and tokens[ending - 3].value.kind == tkFunction and
      tokens[ending - 3].value.fnName.toLowerAscii() == "priority" and
      tokens[ending - 1].value.kind == tkCloseParen:
    let priority = tokens[ending - 2].value
    if priority.kind == tkNumber:
      constraint.priority = LayoutPriority(priority.nValue)
    elif priority.kind == tkIdent:
      case priority.ident.toLowerAscii()
      of "required":
        constraint.priority = LayoutPriorityRequired
      of "high":
        constraint.priority = LayoutPriorityHigh
      of "low":
        constraint.priority = LayoutPriorityLow
      of "fitting":
        constraint.priority = LayoutPriorityFittingSizeLevel
      else:
        return
    else:
      return
    ending -= 3
  if ending < 3 or tokens[0].value.kind != tkIdent or
      not parseAttribute(tokens[0].value.ident, constraint.attribute):
    return
  var index = 1
  let operator = tokens[index].value
  if operator.delimiter('='):
    inc index
    if tokens[index].value.delimiter('='):
      inc index
  elif operator.delimiter('>') or operator.delimiter('<'):
    constraint.relation =
      if operator.delimiter('>'): lrGreaterThanOrEqual else: lrLessThanOrEqual
    inc index
    if not tokens[index].value.delimiter('='):
      return
    inc index
  else:
    return
  if index >= ending:
    return
  let target = tokens[index].value
  if target.kind in {tkNumber, tkDimension}:
    if not target.lengthValue(constraint.constant, signed = true):
      return
    inc index
  else:
    case target.kind
    of tkIdent:
      case target.ident.toLowerAscii()
      of "parent":
        constraint.target = sltParent
      of "self":
        constraint.target = sltSelf
      else:
        return
    of tkIDHash, tkHash:
      constraint.target = sltSibling
      constraint.targetId = if target.kind == tkIDHash: target.idHash else: target.hash
    else:
      return
    inc index
    if index + 1 >= ending or not tokens[index].value.delimiter('.') or
        tokens[index + 1].value.kind != tkIdent or
        not parseAttribute(tokens[index + 1].value.ident, constraint.targetAttribute):
      return
    index += 2
    if index < ending and tokens[index].value.delimiter('*'):
      inc index
      if index >= ending or tokens[index].value.kind != tkNumber:
        return
      constraint.multiplier = tokens[index].value.nValue
      index += 1
    if index < ending:
      let offset = tokens[index].value
      var sign = 1.0'f32
      if offset.delimiter('+') or offset.delimiter('-') or
          (offset.kind == tkIdent and offset.ident == "-"):
        if offset.delimiter('-') or (offset.kind == tkIdent and offset.ident == "-"):
          sign = -1
        inc index
        if index >= ending or not tokens[index].value.lengthValue(constraint.constant):
          return
        constraint.constant *= sign
        inc index
      elif (offset.kind == tkNumber and offset.nHasSign) or
          (offset.kind == tkDimension and offset.dHasSign):
        if not offset.lengthValue(constraint.constant, signed = true):
          return
        inc index
      else:
        return
  index == ending and constraint.validStyleConstraint()

proc constraintsValue(tokens: seq[LocatedToken], value: var StyleValue): bool =
  if tokens.len == 1 and tokens[0].value.kind == tkIdent and
      tokens[0].value.ident.toLowerAscii() == "none":
    value = styleConstraints([])
    return true
  var
    constraints: seq[StyleLayoutConstraint]
    start = 0
  for index in 0 .. tokens.len:
    if index == tokens.len or tokens[index].value.kind == tkComma:
      var constraint = StyleLayoutConstraint()
      if start == index or
          not constraintValue(tokens.toOpenArray(start, index - 1), constraint):
        return
      constraints.add constraint
      start = index + 1
  value = styleConstraints(constraints)
  true

proc validateCssValue*(key: string, resolved: var StyleValue): bool =
  var geometry: CssGeometryProperty
  if cssGeometryByKey(key, geometry):
    if resolved.kind == svLength:
      if resolved.length.classify in {fcNan, fcInf, fcNegInf} or
          (not geometry.edge and resolved.length < 0):
        return
      var constraint = StyleLayoutConstraint(
        attribute: geometry.attribute,
        relation: geometry.relation,
        constant: resolved.length,
        priority: geometry.priority,
      )
      if geometry.edge:
        constraint.target = sltParent
        constraint.targetAttribute = geometry.attribute
        if geometry.attribute in {atRight, atBottom}:
          constraint.constant = -constraint.constant
      resolved = styleConstraints([constraint])
    if resolved.kind != svConstraints:
      return
    for constraint in resolved.constraints:
      if not constraint.validStyleConstraint:
        return
    result = true
    return
  if key == StyleLayoutConstraints.keyName:
    if resolved.kind != svConstraints:
      return
    for constraint in resolved.constraints:
      if not constraint.validStyleConstraint:
        return
    return true
  var spec: CssPropertySpec
  if cssPropertyByKey(key, spec):
    case spec.kind
    of cpkColor:
      return resolved.kind == svColor
    of cpkFill:
      return resolved.kind in {svColor, svFill}
    of cpkLength:
      return
        resolved.kind == svLength and
        resolved.length.classify notin {fcNan, fcInf, fcNegInf} and
        resolved.length >= spec.minimum and resolved.length <= spec.maximum
    of cpkSize:
      if resolved.kind == svLength:
        resolved = styleSize(initSize(resolved.length, resolved.length))
      return
        resolved.kind == svSize and
        resolved.size.width.classify notin {fcNan, fcInf, fcNegInf} and
        resolved.size.height.classify notin {fcNan, fcInf, fcNegInf} and
        resolved.size.width >= 0 and resolved.size.height >= 0
    of cpkInsets:
      if resolved.kind == svLength:
        resolved = styleInsets(insets(resolved.length))
      if resolved.kind != svInsets:
        return
      for amount in [
        resolved.insets.top, resolved.insets.right, resolved.insets.bottom,
        resolved.insets.left,
      ]:
        if amount.classify in {fcNan, fcInf, fcNegInf} or amount < 0:
          return
      return true
    of cpkShadows:
      if resolved.kind == svKeyword and resolved.keyword == "none":
        resolved = styleShadows([])
      return resolved.kind == svShadows
    of cpkFontFace:
      return resolved.kind == svFontFace
    of cpkKeyword:
      if resolved.kind != svKeyword or resolved.keyword.len == 0:
        return
      if spec.keywords.len > 0:
        resolved = styleKeyword(resolved.keyword.toLowerAscii())
        return resolved.keyword in spec.keywords.split('|')
      return true

proc declarationPatch*(
  propertyName: string, tokens: seq[LocatedToken]
): StylePatch {.noSideEffect.}

proc parseDeclarationPatch(
    propertyName: string, tokens: seq[LocatedToken]
): StylePatch =
  let name = propertyName.toLowerAscii()
  var
    value: StyleValue
    amount: float32
  let variable = tokens.singleVariable(value)
  var compositeVariable = false
  for token in tokens:
    if token.value.kind == tkFunction and token.value.fnName.toLowerAscii() == "var":
      compositeVariable = not variable
  if compositeVariable:
    let prototype =
      @[
        LocatedToken(value: Token(kind: tkFunction, fnName: "var")),
        LocatedToken(value: Token(kind: tkIdent, ident: "--prototype")),
        LocatedToken(value: Token(kind: tkCloseParen)),
      ]
    result = declarationPatch(name, prototype)
    if not result.isNil:
      for key, candidate in result.values.mpairs:
        if candidate.kind in {svToken, svCssExpression}:
          candidate = expressionValue(tokens, name)
    return
  result = newStylePatch()
  var spec: CssPropertySpec
  if cssPropertyByName(name, spec) and not spec.shorthand:
    if not extensionValue(spec, tokens, value):
      return nil
    result.setStyle(spec.key, value)
    if spec.key == StyleContainerAlignment.keyName:
      result[StyleContainerRowAlignment] = value
      result[StyleContainerColumnAlignment] = value
    return
  var geometry: CssGeometryProperty
  if cssGeometryByName(name, geometry):
    if not variable and
        (tokens.len != 1 or not geometryValue(geometry, tokens[0].value, value)):
      return nil
    result.setStyle(geometry.key, value)
    return
  if name == "-nimkit-constraints":
    if not tokens.constraintsValue(value):
      return nil
    result[StyleLayoutConstraints] = value
    return
  if name in ["inset", "-nimkit-pin-edges"]:
    if not variable and tokens.len notin 1 .. 4:
      return nil
    let positions =
      case tokens.len
      of 1:
        [0, 0, 0, 0]
      of 2:
        [0, 1, 0, 1]
      of 3:
        [0, 1, 2, 1]
      else:
        [0, 1, 2, 3]
    for index, edge in ["top", "right", "bottom", "left"]:
      discard cssGeometryByName(edge, geometry)
      if not variable and
          not geometryValue(geometry, tokens[positions[index]].value, value):
        return nil
      result.setStyle(geometry.key, value)
    return
  if name == "gap":
    if not variable and tokens.len notin 1 .. 2:
      return nil
    for index, key in [StyleContainerRowGap, StyleContainerColumnGap]:
      if not variable:
        if not tokens[min(index, tokens.high)].value.lengthValue(amount):
          return nil
        value = styleLength(amount)
      result[key] = value
    return
  case name
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
  of "font-family":
    if not variable:
      if tokens.len != 1 or tokens[0].value.kind notin {tkIdent, tkQuotedString}:
        return nil
      value = styleKeyword(
        if tokens[0].value.kind == tkIdent:
          tokens[0].value.ident
        else:
          tokens[0].value.qStr
      )
    result[StyleFontName] = value
    for key in [
      StyleFontFace, StyleItalicFontFace, StyleBoldFontFace, StyleBoldItalicFontFace
    ]:
      result[key] = styleFontFace(SystemTypeface())
  else:
    return nil

proc declarationPatch*(
    propertyName: string, tokens: seq[LocatedToken]
): StylePatch {.noSideEffect.} =
  result = parseDeclarationPatch(propertyName, tokens)
  var variable: StyleValue
  if not result.isNil and tokens.singleVariable(variable) and
      propertyName.toLowerAscii() in
      ["padding", "border-radius", "font-family", "gap", "inset", "-nimkit-pin-edges"]:
    # Preserve the shorthand so every output key projects the same expanded value.
    for key, value in result.values.mpairs:
      if value.kind == svToken:
        value = expressionValue(tokens, propertyName)
  if not result.isNil:
    for key, value in result.values.mpairs:
      if value.kind notin {svToken, svCssExpression} and not validateCssValue(
        key, value
      ):
        return nil

proc compactValueTokens(source: string, tokens: var seq[LocatedToken]): bool =
  var scanned: seq[LocatedToken]
  var diagnostics: seq[CssDiagnostic]
  tokenizeCss(source, scanned, diagnostics)
  if diagnostics.len > 0:
    return
  for token in scanned:
    if token.value.kind notin {tkWhiteSpace, tkComment}:
      tokens.add token
  tokens.len > 0

proc colorText(c: Color): string =
  "rgba(" & $(c.r * 255) & ", " & $(c.g * 255) & ", " & $(c.b * 255) & ", " & $c.a & ")"

proc valueText(value: StyleValue): string =
  case value.kind
  of svCssExpression:
    value.cssText
  of svLength:
    $value.length
  of svColor:
    colorText(value.color)
  of svKeyword:
    if value.keyword.len > 0 and value.keyword[0] in {'a' .. 'z', 'A' .. 'Z', '_', '-'} and
        value.keyword.allCharsInSet({'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '-'}):
      value.keyword
    else:
      "\"" & value.keyword.replace("\\", "\\\\").replace("\"", "\\\"") & "\""
  of svInsets:
    $value.insets.top & "px " & $value.insets.right & "px " & $value.insets.bottom &
      "px " & $value.insets.left & "px"
  of svSize:
    $value.size.width & "px " & $value.size.height & "px"
  of svShadows:
    if value.shadows.len == 0:
      return "none"
    var shadows: seq[string]
    for shadow in value.shadows:
      shadows.add (if shadow.kind == bskInset: "inset " else: "") & $shadow.x & "px " &
        $shadow.y & "px " & $shadow.blur & "px " & $shadow.spread & "px " &
        colorText(shadow.color)
    shadows.join(", ")
  of svFill:
    case value.fill.kind
    of flColor:
      colorText(value.fill.color.color)
    of flLinear2:
      let gradient = value.fill.lin2
      let direction =
        ["right", "bottom", "bottom right", "top right"][ord(gradient.axis)]
      "linear-gradient(to " & direction & ", " & colorText(gradient.start.color) & ", " &
        colorText(gradient.stop.color) & ")"
    of flLinear3:
      let gradient = value.fill.lin3
      let direction =
        ["right", "bottom", "bottom right", "top right"][ord(gradient.axis)]
      "linear-gradient(to " & direction & ", " & colorText(gradient.start.color) & ", " &
        colorText(gradient.mid.color) & " " & $(gradient.midPos.float32 / 255 * 100) &
        "%, " & colorText(gradient.stop.color) & ")"
  else:
    ""

const MaximumCssValueTokens = 4096

proc substituteVariables(
    store: StyleTokenStore,
    tokens: seq[LocatedToken],
    expanded: var seq[LocatedToken],
    visiting: var seq[string],
    work: var int,
): bool =
  var index = 0
  while index < tokens.len:
    inc work
    if work > MaximumCssValueTokens or expanded.len >= MaximumCssValueTokens:
      return
    let token = tokens[index]
    if token.value.kind == tkFunction and token.value.fnName.toLowerAscii() == "var":
      if index + 2 >= tokens.len or tokens[index + 1].value.kind != tkIdent or
          not tokens[index + 1].value.ident.startsWith("--") or
          tokens[index + 2].value.kind != tkCloseParen:
        return
      let name = tokens[index + 1].value.ident
      if visiting.len >= 16 or name in visiting:
        return
      var value: StyleValue
      if not store.lookupToken(name, value):
        return
      visiting.add name
      while value.kind == svToken:
        let alias = value.token.cssTokenName
        if visiting.len >= 16 or alias in visiting or not store.lookupToken(
          alias, value
        ):
          return
        visiting.add alias
      var replacement: seq[LocatedToken]
      if not compactValueTokens(value.valueText, replacement) or
          not substituteVariables(store, replacement, expanded, visiting, work):
        return
      # The caller owns its traversal stack, including token aliases.
      while visiting.len > 0 and visiting[^1] != name:
        visiting.setLen(visiting.len - 1)
      visiting.setLen(visiting.len - 1)
      index += 3
    else:
      expanded.add token
      inc index
  true

proc expandCssExpression(
    store: StyleTokenStore, expression: StyleValue, expanded: var seq[LocatedToken]
): bool =
  var tokens: seq[LocatedToken]
  if not compactValueTokens(expression.cssText, tokens):
    return
  var visiting: seq[string]
  var work = 0
  substituteVariables(store, tokens, expanded, visiting, work)

func sourceExpression(input, resolved: StyleValue): StyleValue =
  if input.kind == svToken:
    # Expand from the original reference so aliases share the reference budget.
    StyleValue(
      kind: svCssExpression,
      cssProperty: resolved.cssProperty,
      cssText: "var(" & input.token.cssTokenName & ")",
    )
  else:
    resolved

type CssValueResolver = object
  store: StyleTokenStore
  cached: bool
  text, property: string
  patch: StylePatch

proc resolveValue(
    resolver: var CssValueResolver,
    input: StyleValue,
    key: string,
    resolved: var StyleValue,
): bool =
  if not resolver.store.resolveValue(input, resolved):
    return
  if resolved.kind == svCssExpression:
    let expression = sourceExpression(input, resolved)
    var property = expression.cssProperty
    if property.len == 0:
      var spec: CssPropertySpec
      if cssPropertyByKey(key, spec):
        property = spec.name
      else:
        var geometry: CssGeometryProperty
        if not cssGeometryByKey(key, geometry):
          return
        property = geometry.name
    if not resolver.cached or resolver.text != expression.cssText or
        resolver.property != property:
      resolver.cached = true
      resolver.text = expression.cssText
      resolver.property = property
      resolver.patch = nil
      var expanded: seq[LocatedToken]
      if resolver.store.expandCssExpression(expression, expanded):
        resolver.patch = declarationPatch(property, expanded)
    if resolver.patch.isNil or key notin resolver.patch.values:
      return
    resolved = resolver.patch.values[key]
  elif input.kind == svToken and resolved.kind == svConstraints:
    # Native list tokens cannot supply a scalar CSS geometry property.
    var geometry: CssGeometryProperty
    if cssGeometryByKey(key, geometry):
      return
  validateCssValue(key, resolved)

proc resolveCssValue*(
    store: StyleTokenStore, input: StyleValue, key: string, resolved: var StyleValue
): bool =
  var resolver = CssValueResolver(store: store)
  resolver.resolveValue(input, key, resolved)

proc resolveCssPatch*(
    store: StyleTokenStore, source: StylePatch, invalid: var StyleValue
): StylePatch =
  ## Compile a declaration atomically, sharing shorthand expansion across its keys.
  result = newStylePatch()
  var resolver = CssValueResolver(store: store)
  for key, value in source.values:
    var resolved: StyleValue
    if not resolver.resolveValue(value, key, resolved):
      invalid = value
      return nil
    result.values[key] = resolved

proc resolveCssToken*(
    store: StyleTokenStore, name: string, kind: StyleValueKind, resolved: var StyleValue
): bool =
  ## Typed token access uses the requested type, without borrowing a property's bounds.
  if not store.resolveToken(name, resolved):
    return
  if resolved.kind != svCssExpression or kind in {svMissing, svToken, svCssExpression}:
    return true
  var tokens: seq[LocatedToken]
  if not store.expandCssExpression(sourceExpression(styleToken(name), resolved), tokens):
    return
  if kind in {svColor, svFill}:
    return tokens.fillValue(resolved)
  if kind == svConstraints:
    return tokens.constraintsValue(resolved)
  let propertyKind =
    case kind
    of svLength:
      cpkLength
    of svSize:
      cpkSize
    of svInsets:
      cpkInsets
    of svShadows:
      cpkShadows
    of svKeyword:
      cpkKeyword
    of svFontFace:
      cpkFontFace
    else:
      return false
  extensionValue(
    CssPropertySpec(kind: propertyKind, minimum: -float32.high), tokens, resolved
  )
