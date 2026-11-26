## Expands the demo's native GUI and style shorthand into its canonical NIF nodes.

import std/[sets, strutils]
import openparser/nif

proc htmlName*(value: string): string =
  ## Converts a camel-case markup name to kebab case.
  for ch in value:
    if ch in {'A' .. 'Z'}:
      if result.len > 0:
        result.add '-'
      result.add ch.toLowerAscii()
    else:
      result.add ch

proc quoted(value: string): NifNode =
  NifNode(kind: nkStrLit, strVal: value)

proc compound(tag: string, children: seq[NifNode] = @[]): NifNode =
  newNifCompound(tag, tag, children)

proc name(node: NifNode): string =
  if node.kind != nkCompound:
    raise newException(ValueError, "expected a shorthand element")
  node.tag

proc oneChild(node: NifNode): NifNode =
  discard node.name()
  if node.children.len != 1:
    raise newException(ValueError, node.tag & " requires one value")
  node.children[0]

proc scalar(node: NifNode): string =
  case node.kind
  of nkStrLit:
    node.strVal
  of nkCharLit:
    node.charVal
  of nkIdent:
    node.ident
  of nkInt:
    $node.intVal
  of nkUInt:
    $node.uintVal
  of nkFloat:
    $node.floatVal
  else:
    raise newException(ValueError, "expected a shorthand scalar value")

proc attribute(key: string, value: NifNode): NifNode =
  compound("kv", @[quoted(key), value])

proc appendText(children: var seq[NifNode], text: string) =
  for index, line in text.split('\n').pairs():
    if index > 0:
      children.add compound("br")
    children.add quoted(line)

proc expandGuiShorthand*(node: NifNode): NifNode =
  ## Expands one native widget and its property children.
  let kind = node.name()
  if kind == "option":
    if node.children.len != 2:
      raise newException(ValueError, "option requires an object value and display text")
    return compound(
      "option",
      @[
        compound("attrs", @[attribute("value", quoted(node.children[0].scalar()))]),
        quoted(node.children[1].scalar()),
      ],
    )
  let tag =
    case kind
    of "Window":
      "nkWindow"
    of "StackView":
      "nkStackView"
    of "View":
      "nkView"
    of "Label":
      "span"
    of "TextField", "CheckBox":
      "input"
    of "TextView":
      "textarea"
    of "ComboBox":
      "select"
    of "ComboBoxOption":
      "option"
    of "Button":
      "button"
    of "ProgressIndicator":
      "progress"
    of "Box":
      "nkGroup"
    else:
      raise newException(ValueError, "unsupported shorthand widget: " & kind)
  var
    attributes, children: seq[NifNode]
    properties = initHashSet[string]()
    selectedIndex: int
    selectionSpecified = false
    fieldText: string
    hasFieldText = false
  if kind in ["TextField", "CheckBox"]:
    attributes.add attribute(
      "type", quoted(if kind == "CheckBox": "checkbox" else: "text")
    )
  for child in node.children:
    if child.kind in {nkStrLit, nkCharLit}:
      if kind == "TextField":
        fieldText.add child.scalar()
        hasFieldText = true
      elif kind == "TextView":
        children.add quoted(child.scalar())
      else:
        children.appendText(child.scalar())
      continue
    let key = child.name()
    if key[0] in {'A' .. 'Z'} or key == "option":
      children.add child.expandGuiShorthand()
      continue
    if key in properties:
      raise newException(ValueError, "duplicate shorthand property: " & key)
    properties.incl key
    if key == "selectedIndex" and kind == "ComboBox":
      selectedIndex = parseInt(child.oneChild().scalar())
      selectionSpecified = true
      continue
    if key == "title" and kind == "Button" or
        key == "displayText" and kind == "ComboBoxOption":
      children.appendText(child.oneChild().scalar())
      continue
    if key == "state" and kind == "CheckBox":
      let state = child.oneChild().scalar()
      case state
      of "on":
        attributes.add attribute("checked", quoted(""))
      of "off":
        discard
      else:
        raise newException(ValueError, "checkbox state must be on or off")
      continue
    let attributeName =
      case key
      of "id":
        "id"
      of "classes":
        "class"
      of "placeholder":
        "placeholder"
      of "title":
        (if kind == "Window": "title" else: "data-title")
      of "boxTitle":
        "data-title"
      of "objectValue":
        (if kind == "ComboBoxOption": "value" else: "data-object-value")
      of "maxValue":
        (if kind == "ProgressIndicator": "max" else: "data-max-value")
      of "value":
        (if kind in ["ProgressIndicator", "TextField"]: "value" else: "data-value")
      else:
        "data-" & key.htmlName()
    if child.children.len == 0:
      raise newException(ValueError, key & " requires a value")
    if key in ["frame", "padding"]:
      if key == "frame" and child.children.len != 4 or
          key == "padding" and child.children.len notin [1, 2, 4]:
        raise newException(ValueError, "invalid shorthand " & key & " dimensions")
      var parts: seq[string]
      for part in child.children:
        parts.add part.scalar()
      attributes.add attribute(attributeName, quoted(parts.join(" ")))
    else:
      attributes.add attribute(attributeName, quoted(child.oneChild().scalar()))
  if hasFieldText:
    if "value" in properties:
      raise
        newException(ValueError, "TextField accepts either text or a value property")
    attributes.add attribute("value", quoted(fieldText))
  if kind == "ComboBox":
    for option in children:
      if option.name() != "option":
        raise newException(ValueError, "ComboBox requires option children")
    if selectionSpecified and (selectedIndex < -1 or selectedIndex >= children.len):
      raise newException(ValueError, "selectedIndex is outside the ComboBox options")
    if children.len > 0 and selectedIndex >= 0:
      children[selectedIndex].children[0].children.add attribute("selected", quoted(""))
    elif selectionSpecified:
      attributes.add attribute("data-selected-index", quoted("-1"))
  result = compound(tag, @[compound("attrs", attributes)])
  result.children.add children

proc styleValue(node: NifNode): NifNode =
  if node.kind == nkSymbolDef:
    if not node.symDef.startsWith("var.") or node.symDef.len == "var.".len:
      raise newException(ValueError, "style references must use :var.name")
    return compound("var", @[quoted(node.symDef[4 .. ^1])])
  if node.kind == nkCompound and node.tag == "color":
    let color = node.oneChild().styleValue()
    if color.kind in {nkInt, nkUInt}:
      return compound("hexColor", @[color])
    if color.kind == nkStrLit and color.strVal.len in [3, 4, 6, 8] and
        color.strVal.allCharsInSet(HexDigits):
      return compound("hexColor", @[color])
    return color
  node

proc declarations(nodes: openArray[NifNode]): seq[NifNode] =
  for node in nodes:
    let key = node.name()
    case key
    of "border", "focusRing":
      if node.children.len == 0:
        raise newException(ValueError, key & " requires property children")
      for property in node.children:
        let part = property.name()
        let target =
          if key == "border" and part in ["color", "width", "radius"]:
            "border" & part.capitalizeAscii()
          elif key == "focusRing" and part == "color":
            "nimkitFocusRingColor"
          else:
            raise newException(ValueError, "unsupported " & key & " property: " & part)
        if part == "color":
          result.add compound(target, @[property.styleValue()])
        else:
          if property.children.len == 0:
            raise newException(ValueError, part & " requires a length")
          result.add compound(target, property.children)
    of "chrome":
      if node.children.len == 0:
        raise newException(ValueError, "chrome requires a name")
      var parts: seq[string]
      for child in node.children:
        parts.add child.scalar()
      result.add compound("nimkitChrome", @[quoted(parts.join("-"))])
    else:
      let target =
        case key
        of "indicatorFill": "nimkitIndicatorFill"
        of "markColor": "nimkitMarkColor"
        else: key
      var values: seq[NifNode]
      if key == "color":
        values.add node.styleValue()
      else:
        for child in node.children:
          values.add child.styleValue()
      result.add compound(target, values)

proc expandStyleShorthand*(nodes: NifModule): NifNode =
  ## Expands line-based style rules into a stylesheet root.
  result = compound("stylesheet")
  for node in nodes:
    if node.name() != "style" or node.children.len < 2:
      raise newException(ValueError, "expected style selectors followed by a body")
    var selectors: seq[NifNode]
    var index: int
    while index < node.children.len and node.children[index].kind == nkStrLit:
      selectors.add node.children[index]
      inc index
    if selectors.len == 0 or index == node.children.len:
      raise
        newException(ValueError, "style requires quoted selectors and a body: " & $node)
    if selectors.len == 1 and selectors[0].strVal in ["root", ":root"]:
      result.children.add compound(
        "tokens", node.children.toOpenArray(index, node.children.high).declarations()
      )
    else:
      if index != node.children.high or node.children[index].name() != "rule":
        raise newException(ValueError, "style requires one rule body")
      let selector =
        if selectors.len == 1:
          selectors[0]
        else:
          compound("any", selectors)
      var rule = compound("rule", @[selector])
      rule.children.add node.children[index].children.declarations()
      result.children.add rule
