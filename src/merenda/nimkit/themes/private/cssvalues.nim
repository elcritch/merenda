## Internal typed CSS declaration parsing. The tokenizer owns source locations.

import std/[math, strutils]
import stylus
from figdraw import SystemTypeface

import ../themecore
import ../../foundation/types
import ./cssproperties

type LocatedToken* = object
  value*: Token
  line*, column*: int

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

proc basicValue*(tokens: seq[LocatedToken], value: var StyleValue): bool =
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

proc extensionValue(
    spec: CssPropertySpec, tokens: seq[LocatedToken], value: var StyleValue
): bool =
  if tokens.singleVariable(value):
    return true
  case spec.kind
  of cpkColor, cpkFill:
    var c: Color
    if tokens.colorValue(c):
      value = styleColor(c)
      return true
  of cpkLength:
    var amount: float32
    if tokens.len == 1 and (not spec.unitless or tokens[0].value.kind == tkNumber) and
        tokens[0].value.lengthValue(amount):
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

proc declarationPatch*(propertyName: string, tokens: seq[LocatedToken]): StylePatch =
  let name = propertyName.toLowerAscii()
  var
    value: StyleValue
    c: Color
    amount: float32
  let variable = tokens.singleVariable(value)
  result = newStylePatch()
  var spec: CssPropertySpec
  if cssPropertyByName(name, spec):
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
