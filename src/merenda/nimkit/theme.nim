import std/tables

import figdraw/common/filltypes
from pkg/chroma import rgba

import ./types

export filltypes

type
  EdgeInsets* = object
    top*: float32
    left*: float32
    bottom*: float32
    right*: float32

  BoxShadowKind* = enum
    bskDrop
    bskInset

  BoxShadow* = object
    kind*: BoxShadowKind
    color*: Color
    x*: float32
    y*: float32
    blur*: float32
    spread*: float32

  StyleRole* = enum
    srView
    srButton
    srCheckBox
    srRadioButton
    srTextField
    srComboBox
    srComboBoxItem
    srListView
    srListItem

  StyleContext* = object
    role*: StyleRole
    states*: set[WidgetState]
    id*: string
    classes*: seq[string]

  StyleSelector* = object
    role*: StyleRole
    states*: set[WidgetState]
    id*: string
    classes*: seq[string]

  StyleValueKind* = enum
    svMissing
    svColor
    svFill
    svLength
    svSize
    svInsets
    svShadows
    svToken
    svKeyword

  StyleValue* = object
    case kind*: StyleValueKind
    of svMissing:
      discard
    of svColor:
      color*: Color
    of svFill:
      fill*: Fill
    of svLength:
      length*: float32
    of svSize:
      size*: Size
    of svInsets:
      insets*: EdgeInsets
    of svShadows:
      shadows*: seq[BoxShadow]
    of svToken:
      token*: string
    of svKeyword:
      keyword*: string

  StyleTokenStore* = ref object
    parent*: StyleTokenStore
    values*: Table[string, StyleValue]

  StyleKey*[T] = distinct string

  StylePatch* = ref object
    values*: Table[string, StyleValue]

  StyleRule* = object
    selector*: StyleSelector
    patch*: StylePatch

  Theme* = object
    tokens*: StyleTokenStore
    rules*: seq[StyleRule]

  Appearance* = object
    theme*: Theme

  ControlBoxStyle* = object
    fill*: Fill
    borderColor*: Color
    borderWidth*: float32
    cornerRadius*: float32
    focusRingWidth*: float32
    focusRingInset*: float32
    focusRingColor*: Color
    shadows*: seq[BoxShadow]

  TextStyle* = object
    color*: Color
    insets*: EdgeInsets

  ButtonStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle
    minSize*: Size

  ChoiceButtonStyle* = object
    indicator*: ControlBoxStyle
    markColor*: Color
    text*: TextStyle
    indicatorSize*: float32
    indicatorSpacing*: float32
    minSize*: Size

  TextFieldStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle
    selectionColor*: Color
    minSize*: Size

  ComboBoxStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle
    arrowWidth*: float32
    arrowColor*: Color
    minSize*: Size

  ListViewStyle* = object
    box*: ControlBoxStyle
    minSize*: Size

  ListItemStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle
    minSize*: Size

const
  StyleFill* = StyleKey[Fill]("fill")
  StyleBorderColor* = StyleKey[Color]("border.color")
  StyleBorderWidth* = StyleKey[float32]("border.width")
  StyleCornerRadius* = StyleKey[float32]("corner.radius")
  StyleFocusRingWidth* = StyleKey[float32]("focus.ring.width")
  StyleFocusRingInset* = StyleKey[float32]("focus.ring.inset")
  StyleFocusRingColor* = StyleKey[Color]("focus.ring.color")
  StyleBoxShadows* = StyleKey[seq[BoxShadow]]("box.shadows")
  StyleTextColor* = StyleKey[Color]("text.color")
  StyleSelectionColor* = StyleKey[Color]("selection.color")
  StyleTextInsets* = StyleKey[EdgeInsets]("text.insets")
  StyleIndicatorSize* = StyleKey[float32]("indicator.size")
  StyleIndicatorSpacing* = StyleKey[float32]("indicator.spacing")
  StyleMarkColor* = StyleKey[Color]("mark.color")
  StyleMinimumSize* = StyleKey[Size]("minimum.size")

  AccentToken* = "accent"
  AccentPressedToken* = "accent.pressed"
  DisabledFillToken* = "disabled.fill"
  DisabledTextColorToken* = "disabled.text.color"
  FocusRingColorToken* = "focus.ring.color"

  ButtonFillToken* = "button.fill"
  ButtonHighlightedFillToken* = "button.fill.highlighted"
  ButtonDisabledFillToken* = "button.fill.disabled"
  ButtonTextColorToken* = "button.text.color"
  ButtonDisabledTextColorToken* = "button.text.color.disabled"
  ButtonBorderColorToken* = "button.border.color"
  ButtonHighlightedBorderColorToken* = "button.border.color.highlighted"
  ButtonDisabledBorderColorToken* = "button.border.color.disabled"
  ButtonFocusRingColorToken* = "button.focus.ring.color"
  ButtonShadowsToken* = "button.shadows"
  ButtonHighlightedShadowsToken* = "button.shadows.highlighted"
  ButtonDisabledShadowsToken* = "button.shadows.disabled"

  ChoiceIndicatorFillToken* = "choice.indicator.fill"
  ChoiceIndicatorHighlightedFillToken* = "choice.indicator.fill.highlighted"
  ChoiceIndicatorDisabledFillToken* = "choice.indicator.fill.disabled"
  ChoiceIndicatorSelectedFillToken* = "choice.indicator.fill.selected"
  ChoiceIndicatorSelectedHighlightedFillToken* =
    "choice.indicator.fill.selected.highlighted"
  ChoiceIndicatorSelectedDisabledFillToken* = "choice.indicator.fill.selected.disabled"
  ChoiceIndicatorBorderColorToken* = "choice.indicator.border.color"
  ChoiceIndicatorHighlightedBorderColorToken* =
    "choice.indicator.border.color.highlighted"
  ChoiceIndicatorDisabledBorderColorToken* = "choice.indicator.border.color.disabled"
  ChoiceMarkColorToken* = "choice.mark.color"
  ChoiceDisabledMarkColorToken* = "choice.mark.color.disabled"
  ChoiceTextColorToken* = "choice.text.color"
  ChoiceDisabledTextColorToken* = "choice.text.color.disabled"

  TextFieldFillToken* = "textField.fill"
  TextFieldBorderColorToken* = "textField.border.color"
  TextFieldTextColorToken* = "textField.text.color"
  TextFieldSelectionColorToken* = "textField.selection.color"

  LabelStyleClass* = "label"
  LabelTitleStyleClass* = "label-title"
  LabelHeadingStyleClass* = "label-heading"
  LabelStatusStyleClass* = "label-status"
  LabelFormStyleClass* = "label-form"

  ComboBoxFillToken* = "comboBox.fill"
  ComboBoxBorderColorToken* = "comboBox.border.color"
  ComboBoxOpenBorderColorToken* = "comboBox.border.color.open"
  ComboBoxTextColorToken* = "comboBox.text.color"
  ComboBoxArrowColorToken* = "comboBox.arrow.color"
  ComboBoxItemFillToken* = "comboBox.item.fill"
  ComboBoxItemHighlightedFillToken* = "comboBox.item.fill.highlighted"
  ComboBoxItemSelectedFillToken* = "comboBox.item.fill.selected"
  ComboBoxItemSelectedHighlightedFillToken* = "comboBox.item.fill.selected.highlighted"
  ComboBoxItemTextColorToken* = "comboBox.item.text.color"
  ComboBoxItemSelectedTextColorToken* = "comboBox.item.text.color.selected"
  ListViewFillToken* = "listView.fill"
  ListViewBorderColorToken* = "listView.border.color"
  ListItemFillToken* = "list.item.fill"
  ListItemHighlightedFillToken* = "list.item.fill.highlighted"
  ListItemSelectedFillToken* = "list.item.fill.selected"
  ListItemSelectedHighlightedFillToken* = "list.item.fill.selected.highlighted"
  ListItemTextColorToken* = "list.item.text.color"
  ListItemSelectedTextColorToken* = "list.item.text.color.selected"
  ListItemSeparatorColorToken* = "list.item.separator.color"

func initEdgeInsets*(top, left, bottom, right: float32): EdgeInsets =
  EdgeInsets(top: top, left: left, bottom: bottom, right: right)

func initEdgeInsets*(vertical, horizontal: float32): EdgeInsets =
  initEdgeInsets(vertical, horizontal, vertical, horizontal)

func initEdgeInsets*(all: float32): EdgeInsets =
  initEdgeInsets(all, all, all, all)

func horizontal*(insets: EdgeInsets): float32 =
  insets.left + insets.right

func vertical*(insets: EdgeInsets): float32 =
  insets.top + insets.bottom

func fill*(color: Color): Fill =
  filltypes.fill(color.rgba)

func linear*(start, stop: Color, axis: FillGradientAxis): Fill =
  filltypes.linear(start.rgba, stop.rgba, axis)

func linear*(start, mid, stop: Color, axis: FillGradientAxis, midPos = 128'u8): Fill =
  filltypes.linear(start.rgba, mid.rgba, stop.rgba, axis, midPos)

func initBoxShadow*(
    kind: BoxShadowKind,
    color: Color,
    x = 0.0'f32,
    y = 0.0'f32,
    blur = 0.0'f32,
    spread = 0.0'f32,
): BoxShadow =
  BoxShadow(kind: kind, color: color, x: x, y: y, blur: blur, spread: spread)

func dropShadow*(
    color: Color, x = 0.0'f32, y = 1.0'f32, blur = 3.0'f32, spread = 0.0'f32
): BoxShadow =
  initBoxShadow(bskDrop, color, x, y, blur, spread)

func insetShadow*(
    color: Color, x = 0.0'f32, y = 1.0'f32, blur = 2.0'f32, spread = 0.0'f32
): BoxShadow =
  initBoxShadow(bskInset, color, x, y, blur, spread)

func missingStyleValue*(): StyleValue =
  StyleValue(kind: svMissing)

func styleColor*(color: Color): StyleValue =
  StyleValue(kind: svColor, color: color)

func styleFill*(fill: Fill): StyleValue =
  StyleValue(kind: svFill, fill: fill)

func styleFill*(color: Color): StyleValue =
  styleFill(fill(color))

func styleLength*(length: float32): StyleValue =
  StyleValue(kind: svLength, length: length)

func styleSize*(size: Size): StyleValue =
  StyleValue(
    kind: svSize,
    size: Size(width: max(size.width, 0.0'f32), height: max(size.height, 0.0'f32)),
  )

func styleInsets*(insets: EdgeInsets): StyleValue =
  StyleValue(kind: svInsets, insets: insets)

func styleShadows*(shadows: openArray[BoxShadow]): StyleValue =
  StyleValue(kind: svShadows, shadows: @shadows)

func styleToken*(name: string): StyleValue =
  StyleValue(kind: svToken, token: name)

func styleKeyword*(keyword: string): StyleValue =
  StyleValue(kind: svKeyword, keyword: keyword)

func styleKey*[T](name: string): StyleKey[T] =
  StyleKey[T](name)

func keyName*[T](key: StyleKey[T]): string =
  string(key)

func initStyleSelector*(
    role: StyleRole, states: set[WidgetState] = {}, id = "", classes: seq[string] = @[]
): StyleSelector =
  StyleSelector(role: role, states: states, id: id, classes: classes)

func initStyleContext*(
    role: StyleRole, states: set[WidgetState] = {}, id = "", classes: seq[string] = @[]
): StyleContext =
  StyleContext(role: role, states: states, id: id, classes: classes)

func initControlStyleContext*(
    role: StyleRole, states: set[WidgetState] = {}, id = "", classes: seq[string] = @[]
): StyleContext =
  initStyleContext(role, states, id, classes)

func inset*(rect: Rect, insets: EdgeInsets): Rect =
  initRect(
    rect.origin.x + insets.left,
    rect.origin.y + insets.top,
    rect.size.width - insets.left - insets.right,
    rect.size.height - insets.top - insets.bottom,
  )

proc newStyleTokenStore*(parent: StyleTokenStore = nil): StyleTokenStore =
  StyleTokenStore(parent: parent, values: initTable[string, StyleValue]())

proc newStylePatch*(): StylePatch =
  StylePatch(values: initTable[string, StyleValue]())

proc clone*(tokens: StyleTokenStore): StyleTokenStore =
  if tokens.isNil:
    return
  result = newStyleTokenStore(tokens.parent.clone)
  result.values = tokens.values

proc clone*(patch: StylePatch): StylePatch =
  if patch.isNil:
    return
  result = newStylePatch()
  result.values = patch.values

proc clone*(theme: Theme): Theme =
  result.tokens = theme.tokens.clone
  for rule in theme.rules:
    result.rules.add StyleRule(selector: rule.selector, patch: rule.patch.clone)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: StyleValue) =
  tokens.values[name] = value

proc `[]=`*(tokens: StyleTokenStore, name: string, value: Color) =
  tokens[name] = styleColor(value)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: Fill) =
  tokens[name] = styleFill(value)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: float32) =
  tokens[name] = styleLength(value)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: float) =
  tokens[name] = styleLength(value.float32)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: Size) =
  tokens[name] = styleSize(value)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: EdgeInsets) =
  tokens[name] = styleInsets(value)

proc `[]=`*(tokens: StyleTokenStore, name: string, value: openArray[BoxShadow]) =
  tokens[name] = styleShadows(value)

proc `[]=`*(theme: var Theme, name: string, value: StyleValue) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: Color) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: Fill) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: float32) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: float) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: Size) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: EdgeInsets) =
  theme.tokens[name] = value

proc `[]=`*(theme: var Theme, name: string, value: openArray[BoxShadow]) =
  theme.tokens[name] = value

proc lookupToken(tokens: StyleTokenStore, name: string, value: var StyleValue): bool =
  var current = tokens
  while not current.isNil:
    if current.values.hasKey(name):
      value = current.values[name]
      return true
    current = current.parent

proc resolveToken*(tokens: StyleTokenStore, name: string, value: var StyleValue): bool =
  var
    currentName = name
    currentValue: StyleValue
  for depth in 0 ..< 16:
    if not tokens.lookupToken(currentName, currentValue):
      value = missingStyleValue()
      return false
    if currentValue.kind != svToken:
      value = currentValue
      return true
    currentName = currentValue.token
  value = missingStyleValue()

proc resolveValue*(
    tokens: StyleTokenStore, input: StyleValue, value: var StyleValue
): bool =
  if input.kind == svToken:
    tokens.resolveToken(input.token, value)
  elif input.kind == svMissing:
    value = missingStyleValue()
    false
  else:
    value = input
    true

proc setStyle*(patch: StylePatch, key: string, value: StyleValue) =
  patch.values[key] = value

proc setStyle*[T](patch: StylePatch, key: StyleKey[T], value: StyleValue) =
  patch.setStyle(key.keyName, value)

proc setStyle*(patch: StylePatch, key: StyleKey[Color], value: Color) =
  patch.setStyle(key, styleColor(value))

proc setStyle*(patch: StylePatch, key: StyleKey[Fill], value: Fill) =
  patch.setStyle(key, styleFill(value))

proc setStyle*(patch: StylePatch, key: StyleKey[float32], value: float32) =
  patch.setStyle(key, styleLength(value))

proc setStyle*(patch: StylePatch, key: StyleKey[float32], value: float) =
  patch.setStyle(key, styleLength(value.float32))

proc setStyle*(patch: StylePatch, key: StyleKey[Size], value: Size) =
  patch.setStyle(key, styleSize(value))

proc setStyle*(patch: StylePatch, key: StyleKey[EdgeInsets], value: EdgeInsets) =
  patch.setStyle(key, styleInsets(value))

proc setStyle*(
    patch: StylePatch, key: StyleKey[seq[BoxShadow]], value: openArray[BoxShadow]
) =
  patch.setStyle(key, styleShadows(value))

proc `[]=`*(patch: StylePatch, key: string, value: StyleValue) =
  patch.setStyle(key, value)

proc `[]=`*[T](patch: StylePatch, key: StyleKey[T], value: StyleValue) =
  patch.setStyle(key, value)

proc `[]=`*(patch: StylePatch, key: StyleKey[Color], value: Color) =
  patch.setStyle(key, value)

proc `[]=`*(patch: StylePatch, key: StyleKey[Fill], value: Fill) =
  patch.setStyle(key, value)

proc `[]=`*(patch: StylePatch, key: StyleKey[float32], value: float32) =
  patch.setStyle(key, value)

proc `[]=`*(patch: StylePatch, key: StyleKey[float32], value: float) =
  patch.setStyle(key, value)

proc `[]=`*(patch: StylePatch, key: StyleKey[Size], value: Size) =
  patch.setStyle(key, value)

proc `[]=`*(patch: StylePatch, key: StyleKey[EdgeInsets], value: EdgeInsets) =
  patch.setStyle(key, value)

proc `[]=`*(
    patch: StylePatch, key: StyleKey[seq[BoxShadow]], value: openArray[BoxShadow]
) =
  patch.setStyle(key, value)

proc getStyle*(patch: StylePatch, key: string, value: var StyleValue): bool =
  if patch.values.hasKey(key):
    value = patch.values[key]
    return true

proc getStyle*[T](patch: StylePatch, key: StyleKey[T], value: var StyleValue): bool =
  patch.getStyle(key.keyName, value)

func matches*(selector: StyleSelector, context: StyleContext): bool =
  if selector.role != context.role:
    return false
  if not (selector.states <= context.states):
    return false
  if selector.id.len > 0 and selector.id != context.id:
    return false
  for class in selector.classes:
    if class notin context.classes:
      return false
  true

proc stylePatch*(theme: var Theme, selector: StyleSelector): StylePatch =
  for rule in theme.rules:
    if rule.selector == selector:
      return rule.patch
  result = newStylePatch()
  theme.rules.add StyleRule(selector: selector, patch: result)

proc stylePatch*(theme: Theme, selector: StyleSelector): StylePatch =
  for rule in theme.rules:
    if rule.selector == selector:
      return rule.patch

proc addRule*(theme: var Theme, selector: StyleSelector, patch: StylePatch) =
  theme.rules.add StyleRule(selector: selector, patch: patch)

proc setStyle*[T](
    theme: var Theme, selector: StyleSelector, key: StyleKey[T], value: StyleValue
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[Color], value: Color
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[Fill], value: Fill
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[float32], value: float32
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[float32], value: float
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[Size], value: Size
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme,
    selector: StyleSelector,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme,
    selector: StyleSelector,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*[T](
    theme: var Theme, role: StyleRole, key: StyleKey[T], value: StyleValue
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(theme: var Theme, role: StyleRole, key: StyleKey[Color], value: Color) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(theme: var Theme, role: StyleRole, key: StyleKey[Fill], value: Fill) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var Theme, role: StyleRole, key: StyleKey[float32], value: float32
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var Theme, role: StyleRole, key: StyleKey[float32], value: float
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(theme: var Theme, role: StyleRole, key: StyleKey[Size], value: Size) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var Theme, role: StyleRole, key: StyleKey[EdgeInsets], value: EdgeInsets
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*[T](
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[T],
    value: StyleValue,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Color],
    value: Color,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Fill],
    value: Fill,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float32,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Size],
    value: Size,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc `[]=`*[T](
    theme: var Theme, selector: StyleSelector, key: StyleKey[T], value: StyleValue
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[Color], value: Color
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[Fill], value: Fill
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[float32], value: float32
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[float32], value: float
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[Size], value: Size
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme,
    selector: StyleSelector,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.setStyle(selector, key, value)

proc `[]=`*(
    theme: var Theme,
    selector: StyleSelector,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(selector, key, value)

proc `[]=`*[T](theme: var Theme, role: StyleRole, key: StyleKey[T], value: StyleValue) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[Color], value: Color) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[Fill], value: Fill) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[float32], value: float32) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[float32], value: float) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[Size], value: Size) =
  theme.setStyle(role, key, value)

proc `[]=`*(
    theme: var Theme, role: StyleRole, key: StyleKey[EdgeInsets], value: EdgeInsets
) =
  theme.setStyle(role, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(role, key, value)

proc `[]=`*[T](
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[T],
    value: StyleValue,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Color],
    value: Color,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Fill],
    value: Fill,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float32,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Size],
    value: Size,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.setStyle(role, states, key, value)

proc `[]=`*(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(role, states, key, value)

proc `[]`*[T](theme: Theme, role: StyleRole, key: StyleKey[T]): StyleValue =
  let patch = theme.stylePatch(initStyleSelector(role))
  if patch.isNil or not patch.getStyle(key, result):
    result = missingStyleValue()

proc ruleValue(
    theme: Theme, context: StyleContext, key: string, fallback: StyleValue
): StyleValue =
  result = fallback
  for rule in theme.rules:
    if rule.selector.matches(context):
      var value: StyleValue
      if rule.patch.getStyle(key, value):
        var resolved: StyleValue
        if theme.tokens.resolveValue(value, resolved):
          result = resolved
        elif value.kind != svToken:
          result = value

proc colorRule(
    theme: Theme, context: StyleContext, key: StyleKey[Color], fallback: Color
): Color =
  let value = theme.ruleValue(context, key.keyName, styleColor(fallback))
  case value.kind
  of svColor:
    value.color
  of svFill:
    value.fill.centerColor()
  else:
    fallback

proc fillRule(
    theme: Theme, context: StyleContext, key: StyleKey[Fill], fallback: Fill
): Fill =
  let value = theme.ruleValue(context, key.keyName, styleFill(fallback))
  case value.kind
  of svFill:
    value.fill
  of svColor:
    fill(value.color)
  else:
    fallback

proc lengthRule(
    theme: Theme, context: StyleContext, key: StyleKey[float32], fallback: float32
): float32 =
  let value = theme.ruleValue(context, key.keyName, styleLength(fallback))
  if value.kind == svLength: value.length else: fallback

proc sizeRule(
    theme: Theme, context: StyleContext, key: StyleKey[Size], fallback: Size
): Size =
  let value = theme.ruleValue(context, key.keyName, styleSize(fallback))
  if value.kind == svSize: value.size else: fallback

proc insetsRule(
    theme: Theme, context: StyleContext, key: StyleKey[EdgeInsets], fallback: EdgeInsets
): EdgeInsets =
  let value = theme.ruleValue(context, key.keyName, styleInsets(fallback))
  if value.kind == svInsets: value.insets else: fallback

proc shadowsRule(
    theme: Theme,
    context: StyleContext,
    key: StyleKey[seq[BoxShadow]],
    fallback: seq[BoxShadow],
): seq[BoxShadow] =
  let value = theme.ruleValue(context, key.keyName, styleShadows(fallback))
  if value.kind == svShadows: value.shadows else: fallback

proc styleValue*(theme: Theme, name: string, fallback: StyleValue): StyleValue =
  if theme.tokens.isNil:
    return fallback
  if not theme.tokens.resolveToken(name, result):
    result = fallback

proc colorToken*(theme: Theme, name: string, fallback: Color): Color =
  let value = theme.styleValue(name, styleColor(fallback))
  case value.kind
  of svColor:
    value.color
  of svFill:
    value.fill.centerColor()
  else:
    fallback

proc fillToken*(theme: Theme, name: string, fallback: Fill): Fill =
  let value = theme.styleValue(name, styleFill(fallback))
  case value.kind
  of svFill:
    value.fill
  of svColor:
    fill(value.color)
  else:
    fallback

proc lengthToken*(theme: Theme, name: string, fallback: float32): float32 =
  let value = theme.styleValue(name, styleLength(fallback))
  if value.kind == svLength: value.length else: fallback

proc sizeToken*(theme: Theme, name: string, fallback: Size): Size =
  let value = theme.styleValue(name, styleSize(fallback))
  if value.kind == svSize: value.size else: fallback

proc insetsToken*(theme: Theme, name: string, fallback: EdgeInsets): EdgeInsets =
  let value = theme.styleValue(name, styleInsets(fallback))
  if value.kind == svInsets: value.insets else: fallback

proc shadowsToken*(
    theme: Theme, name: string, fallback: seq[BoxShadow]
): seq[BoxShadow] =
  let value = theme.styleValue(name, styleShadows(fallback))
  if value.kind == svShadows: value.shadows else: fallback

proc styleValue*(
    appearance: Appearance, name: string, fallback: StyleValue
): StyleValue =
  appearance.theme.styleValue(name, fallback)

proc colorToken*(appearance: Appearance, name: string, fallback: Color): Color =
  appearance.theme.colorToken(name, fallback)

proc fillToken*(appearance: Appearance, name: string, fallback: Fill): Fill =
  appearance.theme.fillToken(name, fallback)

proc lengthToken*(appearance: Appearance, name: string, fallback: float32): float32 =
  appearance.theme.lengthToken(name, fallback)

proc sizeToken*(appearance: Appearance, name: string, fallback: Size): Size =
  appearance.theme.sizeToken(name, fallback)

proc insetsToken*(
    appearance: Appearance, name: string, fallback: EdgeInsets
): EdgeInsets =
  appearance.theme.insetsToken(name, fallback)

proc shadowsToken*(
    appearance: Appearance, name: string, fallback: seq[BoxShadow]
): seq[BoxShadow] =
  appearance.theme.shadowsToken(name, fallback)

proc setStyle*[T](
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[T],
    value: StyleValue,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Color],
    value: Color,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Fill],
    value: Fill,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float32,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Size],
    value: Size,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  appearance.theme.setStyle(selector, key, value)

proc setStyle*[T](
    appearance: var Appearance, role: StyleRole, key: StyleKey[T], value: StyleValue
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Color], value: Color
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Fill], value: Fill
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float32
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Size], value: Size
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance,
    role: StyleRole,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance,
    role: StyleRole,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  appearance.theme.setStyle(role, key, value)

proc `[]=`*[T](
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[T],
    value: StyleValue,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Color],
    value: Color,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Fill],
    value: Fill,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float32,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[float32],
    value: float,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[Size],
    value: Size,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  appearance.theme[selector, key] = value

proc `[]=`*(
    appearance: var Appearance,
    selector: StyleSelector,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  appearance.theme[selector, key] = value

proc `[]=`*[T](
    appearance: var Appearance, role: StyleRole, key: StyleKey[T], value: StyleValue
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Color], value: Color
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Fill], value: Fill
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float32
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Size], value: Size
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  appearance.setStyle(role, key, value)

proc `[]=`*[T](
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[T],
    value: StyleValue,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Color],
    value: Color,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Fill],
    value: Fill,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float32,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[float32],
    value: float,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[Size],
    value: Size,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  appearance.theme[role, states, key] = value

proc `[]=`*(
    appearance: var Appearance,
    role: StyleRole,
    states: set[WidgetState],
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  appearance.theme[role, states, key] = value

proc `[]`*[T](appearance: Appearance, role: StyleRole, key: StyleKey[T]): StyleValue =
  appearance.theme[role, key]

proc resolveButtonStyle*(theme: Theme, context: StyleContext): ButtonStyle =
  ButtonStyle(
    box: ControlBoxStyle(
      fill: theme.fillRule(context, StyleFill, fill(initColor(0.20, 0.48, 0.86, 1.0))),
      borderColor:
        theme.colorRule(context, StyleBorderColor, initColor(0.10, 0.25, 0.46, 1.0)),
      borderWidth: theme.lengthRule(context, StyleBorderWidth, 1.0),
      cornerRadius: theme.lengthRule(context, StyleCornerRadius, 14.0),
      focusRingWidth: theme.lengthRule(context, StyleFocusRingWidth, 3.0),
      focusRingInset: theme.lengthRule(context, StyleFocusRingInset, 2.0),
      focusRingColor:
        theme.colorRule(context, StyleFocusRingColor, initColor(0.24, 0.48, 0.92, 0.58)),
      shadows: theme.shadowsRule(context, StyleBoxShadows, @[]),
    ),
    text: TextStyle(
      color: theme.colorRule(context, StyleTextColor, initColor(1.0, 1.0, 1.0, 1.0)),
      insets: theme.insetsRule(context, StyleTextInsets, initEdgeInsets(0.0, 8.0)),
    ),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(0.0, 32.0)),
  )

proc resolveChoiceButtonStyle*(theme: Theme, context: StyleContext): ChoiceButtonStyle =
  ChoiceButtonStyle(
    indicator: ControlBoxStyle(
      fill: theme.fillRule(context, StyleFill, fill(initColor(1.0, 1.0, 1.0, 1.0))),
      borderColor:
        theme.colorRule(context, StyleBorderColor, initColor(0.50, 0.55, 0.62, 1.0)),
      borderWidth: theme.lengthRule(context, StyleBorderWidth, 1.0),
      cornerRadius: theme.lengthRule(context, StyleCornerRadius, 6.0),
      focusRingWidth: theme.lengthRule(context, StyleFocusRingWidth, 3.0),
      focusRingInset: theme.lengthRule(context, StyleFocusRingInset, 2.0),
      focusRingColor:
        theme.colorRule(context, StyleFocusRingColor, initColor(0.24, 0.48, 0.92, 0.58)),
      shadows: theme.shadowsRule(context, StyleBoxShadows, @[]),
    ),
    markColor: theme.colorRule(context, StyleMarkColor, initColor(1.0, 1.0, 1.0, 1.0)),
    text: TextStyle(
      color: theme.colorRule(context, StyleTextColor, initColor(0.08, 0.09, 0.11, 1.0)),
      insets: theme.insetsRule(context, StyleTextInsets, initEdgeInsets(0.0, 2.0)),
    ),
    indicatorSize: theme.lengthRule(context, StyleIndicatorSize, 14.0),
    indicatorSpacing: theme.lengthRule(context, StyleIndicatorSpacing, 7.0),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(0.0, 18.0)),
  )

proc resolveTextFieldStyle*(
    theme: Theme, context: StyleContext, textColor: Color
): TextFieldStyle =
  TextFieldStyle(
    box: ControlBoxStyle(
      fill: theme.fillRule(context, StyleFill, fill(initColor(1.0, 1.0, 1.0, 1.0))),
      borderColor:
        theme.colorRule(context, StyleBorderColor, initColor(0.72, 0.75, 0.80, 1.0)),
      borderWidth: theme.lengthRule(context, StyleBorderWidth, 1.0),
      cornerRadius: theme.lengthRule(context, StyleCornerRadius, 6.0),
      focusRingWidth: theme.lengthRule(context, StyleFocusRingWidth, 3.0),
      focusRingInset: theme.lengthRule(context, StyleFocusRingInset, 2.0),
      focusRingColor:
        theme.colorRule(context, StyleFocusRingColor, initColor(0.24, 0.48, 0.92, 0.58)),
      shadows: theme.shadowsRule(context, StyleBoxShadows, @[]),
    ),
    text: TextStyle(
      color: theme.colorRule(context, StyleTextColor, textColor),
      insets: theme.insetsRule(context, StyleTextInsets, initEdgeInsets(0.0, 6.0)),
    ),
    selectionColor:
      theme.colorRule(context, StyleSelectionColor, initColor(0.22, 0.46, 0.84, 0.32)),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(80.0, 24.0)),
  )

proc resolveTextFieldStyle*(theme: Theme, context: StyleContext): TextFieldStyle =
  theme.resolveTextFieldStyle(context, initColor(0.08, 0.09, 0.11, 1.0))

proc resolveComboBoxStyle*(theme: Theme, context: StyleContext): ComboBoxStyle =
  ComboBoxStyle(
    box: ControlBoxStyle(
      fill: theme.fillRule(context, StyleFill, fill(initColor(1.0, 1.0, 1.0, 1.0))),
      borderColor:
        theme.colorRule(context, StyleBorderColor, initColor(0.72, 0.75, 0.80, 1.0)),
      borderWidth: theme.lengthRule(context, StyleBorderWidth, 1.0),
      cornerRadius: theme.lengthRule(context, StyleCornerRadius, 6.0),
      focusRingWidth: theme.lengthRule(context, StyleFocusRingWidth, 3.0),
      focusRingInset: theme.lengthRule(context, StyleFocusRingInset, 2.0),
      focusRingColor:
        theme.colorRule(context, StyleFocusRingColor, initColor(0.24, 0.48, 0.92, 0.58)),
      shadows: theme.shadowsRule(context, StyleBoxShadows, @[]),
    ),
    text: TextStyle(
      color: theme.colorRule(context, StyleTextColor, initColor(0.08, 0.09, 0.11, 1.0)),
      insets: theme.insetsRule(context, StyleTextInsets, initEdgeInsets(0.0, 8.0)),
    ),
    arrowWidth: theme.lengthRule(context, StyleIndicatorSize, 24.0),
    arrowColor:
      theme.colorRule(context, StyleMarkColor, initColor(0.20, 0.22, 0.26, 1.0)),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(90.0, 24.0)),
  )

proc resolveListViewStyle*(theme: Theme, context: StyleContext): ListViewStyle =
  ListViewStyle(
    box: ControlBoxStyle(
      fill: theme.fillRule(context, StyleFill, fill(initColor(1.0, 1.0, 1.0, 1.0))),
      borderColor:
        theme.colorRule(context, StyleBorderColor, initColor(0.72, 0.75, 0.80, 1.0)),
      borderWidth: theme.lengthRule(context, StyleBorderWidth, 1.0),
      cornerRadius: theme.lengthRule(context, StyleCornerRadius, 6.0),
      focusRingWidth: theme.lengthRule(context, StyleFocusRingWidth, 3.0),
      focusRingInset: theme.lengthRule(context, StyleFocusRingInset, 2.0),
      focusRingColor:
        theme.colorRule(context, StyleFocusRingColor, initColor(0.24, 0.48, 0.92, 0.58)),
      shadows: theme.shadowsRule(context, StyleBoxShadows, @[]),
    ),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(120.0, 24.0)),
  )

proc resolveListItemStyle*(theme: Theme, context: StyleContext): ListItemStyle =
  ListItemStyle(
    box: ControlBoxStyle(
      fill: theme.fillRule(context, StyleFill, fill(initColor(1.0, 1.0, 1.0, 1.0))),
      borderColor:
        theme.colorRule(context, StyleBorderColor, initColor(0.0, 0.0, 0.0, 0.0)),
      borderWidth: theme.lengthRule(context, StyleBorderWidth, 0.0),
      cornerRadius: theme.lengthRule(context, StyleCornerRadius, 0.0),
      focusRingWidth: theme.lengthRule(context, StyleFocusRingWidth, 0.0),
      focusRingInset: theme.lengthRule(context, StyleFocusRingInset, 0.0),
      focusRingColor:
        theme.colorRule(context, StyleFocusRingColor, initColor(0.0, 0.0, 0.0, 0.0)),
      shadows: theme.shadowsRule(context, StyleBoxShadows, @[]),
    ),
    text: TextStyle(
      color: theme.colorRule(context, StyleTextColor, initColor(0.08, 0.09, 0.11, 1.0)),
      insets: theme.insetsRule(context, StyleTextInsets, initEdgeInsets(0.0, 6.0)),
    ),
    minSize: theme.sizeRule(context, StyleMinimumSize, initSize(0.0, 22.0)),
  )

proc resolveButtonStyle*(appearance: Appearance, context: StyleContext): ButtonStyle =
  appearance.theme.resolveButtonStyle(context)

proc resolveChoiceButtonStyle*(
    appearance: Appearance, context: StyleContext
): ChoiceButtonStyle =
  appearance.theme.resolveChoiceButtonStyle(context)

proc resolveTextFieldStyle*(
    appearance: Appearance, context: StyleContext, textColor: Color
): TextFieldStyle =
  appearance.theme.resolveTextFieldStyle(context, textColor)

proc resolveTextFieldStyle*(
    appearance: Appearance, context: StyleContext
): TextFieldStyle =
  appearance.theme.resolveTextFieldStyle(context)

proc resolveComboBoxStyle*(
    appearance: Appearance, context: StyleContext
): ComboBoxStyle =
  appearance.theme.resolveComboBoxStyle(context)

proc resolveListViewStyle*(
    appearance: Appearance, context: StyleContext
): ListViewStyle =
  appearance.theme.resolveListViewStyle(context)

proc resolveListItemStyle*(
    appearance: Appearance, context: StyleContext
): ListItemStyle =
  appearance.theme.resolveListItemStyle(context)

func buttonTextRect*(style: ButtonStyle, bounds: Rect): Rect =
  bounds.inset(style.text.insets)

func choiceIndicatorRect*(style: ChoiceButtonStyle, bounds: Rect): Rect =
  let
    size = max(style.indicatorSize, 0.0'f32)
    x = bounds.origin.x + style.text.insets.left
    y = bounds.origin.y + max((bounds.size.height - size) / 2.0'f32, 0.0'f32)
  initRect(x, y, size, size)

func choiceTextRect*(style: ChoiceButtonStyle, bounds: Rect): Rect =
  let indicator = style.choiceIndicatorRect(bounds)
  initRect(
    indicator.maxX + style.indicatorSpacing,
    bounds.origin.y + style.text.insets.top,
    bounds.size.width - style.text.insets.left - style.text.insets.right -
      style.indicatorSize - style.indicatorSpacing,
    bounds.size.height - style.text.insets.top - style.text.insets.bottom,
  )

func textFieldTextRect*(style: TextFieldStyle, bounds: Rect): Rect =
  bounds.inset(style.text.insets)

func comboBoxArrowRect*(style: ComboBoxStyle, bounds: Rect): Rect =
  let arrowWidth = min(max(style.arrowWidth, 0.0'f32), bounds.size.width)
  initRect(bounds.maxX - arrowWidth, bounds.origin.y, arrowWidth, bounds.size.height)

func comboBoxTextRect*(style: ComboBoxStyle, bounds: Rect): Rect =
  let
    arrow = style.comboBoxArrowRect(bounds)
    insets = style.text.insets
  initRect(
    bounds.origin.x + insets.left,
    bounds.origin.y + insets.top,
    max(bounds.size.width - insets.left - insets.right - arrow.size.width, 0.0'f32),
    max(bounds.size.height - insets.top - insets.bottom, 0.0'f32),
  )

func listItemTextRect*(style: ListItemStyle, bounds: Rect): Rect =
  bounds.inset(style.text.insets)

func controlChromeOutset*(box: ControlBoxStyle): float32 =
  max(-box.focusRingInset, 0.0'f32)

func controlChromeWidth*(box: ControlBoxStyle): float32 =
  box.borderWidth * 2.0'f32 + box.controlChromeOutset() * 2.0'f32

func controlChromeHeight*(box: ControlBoxStyle): float32 =
  box.controlChromeWidth()

func controlSizeWithChrome*(
    contentSize: Size, insets: EdgeInsets, box: ControlBoxStyle, minSize: Size
): Size =
  initSize(
    max(minSize.width, contentSize.width + insets.horizontal + box.controlChromeWidth()),
    max(
      minSize.height, contentSize.height + insets.vertical + box.controlChromeHeight()
    ),
  )

func buttonControlSize*(style: ButtonStyle, titleSize: Size): Size =
  controlSizeWithChrome(titleSize, style.text.insets, style.box, style.minSize)

func choiceControlSize*(style: ChoiceButtonStyle, titleSize: Size): Size =
  let
    indicatorChrome = style.indicator.controlChromeWidth()
    indicatorWidth = style.indicatorSize + indicatorChrome
    indicatorHeight = style.indicatorSize + style.indicator.controlChromeHeight()
    contentWidth = indicatorWidth + style.indicatorSpacing + titleSize.width
    contentHeight = max(indicatorHeight, titleSize.height)
  controlSizeWithChrome(
    initSize(contentWidth, contentHeight),
    style.text.insets,
    style.indicator,
    style.minSize,
  )

func textFieldControlSize*(style: TextFieldStyle, textSize: Size): Size =
  controlSizeWithChrome(textSize, style.text.insets, style.box, style.minSize)

func comboBoxControlSize*(style: ComboBoxStyle, textSize: Size): Size =
  let contentSize = initSize(textSize.width + style.arrowWidth, textSize.height)
  controlSizeWithChrome(contentSize, style.text.insets, style.box, style.minSize)

proc addRoleRule(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    fill: StyleValue,
    borderColor: StyleValue,
    textColor: StyleValue,
) =
  let selector = initStyleSelector(role, states)
  theme[selector, StyleFill] = fill
  theme[selector, StyleBorderColor] = borderColor
  theme[selector, StyleTextColor] = textColor

proc addChoiceRule(
    theme: var Theme,
    role: StyleRole,
    states: set[WidgetState],
    fill: StyleValue,
    borderColor: StyleValue,
    markColor: StyleValue,
    textColor: StyleValue,
) =
  let selector = initStyleSelector(role, states)
  theme[selector, StyleFill] = fill
  theme[selector, StyleBorderColor] = borderColor
  theme[selector, StyleMarkColor] = markColor
  theme[selector, StyleTextColor] = textColor

proc addLabelRule(
    theme: var Theme,
    className: string,
    fillValue: Fill,
    borderColor: Color,
    borderWidth: float32,
    cornerRadius: float32,
    textColor: Color,
    textInsets: EdgeInsets,
    minSize: Size,
) =
  let selector = initStyleSelector(srTextField, classes = @[className])
  theme[selector, StyleFill] = fillValue
  theme[selector, StyleBorderColor] = borderColor
  theme[selector, StyleBorderWidth] = borderWidth
  theme[selector, StyleCornerRadius] = cornerRadius
  theme[selector, StyleTextColor] = textColor
  theme[selector, StyleTextInsets] = textInsets
  theme[selector, StyleMinimumSize] = minSize
  theme[selector, StyleFocusRingWidth] = 0.0
  theme[selector, StyleFocusRingInset] = 0.0
  theme[selector, StyleBoxShadows] = newSeq[BoxShadow]()

func defaultButtonShadows(): seq[BoxShadow] =
  @[
    insetShadow(initColor(1.0, 1.0, 1.0, 0.30), x = 2.0, y = 1.0, blur = 5.0),
    insetShadow(initColor(0.0, 0.0, 0.0, 0.24), x = -1.0, y = -2.0, blur = 5.0),
  ]

func highlightedButtonShadows(): seq[BoxShadow] =
  @[
    insetShadow(initColor(1.0, 1.0, 1.0, 0.12), x = 2.0, y = 1.0, blur = 3.0),
    insetShadow(initColor(0.0, 0.0, 0.0, 0.38), x = -1.0, y = -2.0, blur = 9.0),
  ]

func aquaButtonFill(): Fill =
  linear(
    initColor(0.72, 0.91, 1.0, 1.0),
    initColor(0.18, 0.61, 0.98, 1.0),
    initColor(0.02, 0.30, 0.82, 1.0),
    fgaY,
    88'u8,
  )

func aquaButtonPressedFill(): Fill =
  linear(
    initColor(0.11, 0.48, 0.92, 1.0),
    initColor(0.02, 0.28, 0.75, 1.0),
    initColor(0.01, 0.14, 0.46, 1.0),
    fgaY,
    96'u8,
  )

func aquaButtonDisabledFill(): Fill =
  linear(initColor(0.92, 0.94, 0.97, 1.0), initColor(0.70, 0.75, 0.82, 1.0), fgaY)

func aquaChoiceFill(): Fill =
  linear(initColor(1.0, 1.0, 1.0, 1.0), initColor(0.90, 0.94, 0.99, 1.0), fgaY)

func aquaChoiceHighlightedFill(): Fill =
  linear(initColor(1.0, 1.0, 1.0, 1.0), initColor(0.82, 0.91, 1.0, 1.0), fgaY)

func aquaTextFieldFill(): Fill =
  linear(initColor(1.0, 1.0, 1.0, 1.0), initColor(0.95, 0.98, 1.0, 1.0), fgaY)

func aquaComboItemHighlightFill(): Fill =
  linear(initColor(0.90, 0.96, 1.0, 1.0), initColor(0.72, 0.87, 1.0, 1.0), fgaY)

func aquaComboItemSelectedFill(): Fill =
  linear(
    initColor(0.45, 0.75, 1.0, 1.0),
    initColor(0.10, 0.45, 0.95, 1.0),
    initColor(0.02, 0.26, 0.76, 1.0),
    fgaY,
    104'u8,
  )

func aquaComboItemSelectedHighlightedFill(): Fill =
  linear(
    initColor(0.20, 0.57, 0.98, 1.0),
    initColor(0.03, 0.33, 0.82, 1.0),
    initColor(0.01, 0.18, 0.58, 1.0),
    fgaY,
    104'u8,
  )

func aquaButtonShadows(): seq[BoxShadow] =
  @[
    dropShadow(initColor(0.0, 0.0, 0.0, 0.17), y = 2.0, blur = 4.0),
    insetShadow(initColor(1.0, 1.0, 1.0, 0.72), y = 1.0, blur = 2.0),
    insetShadow(initColor(0.55, 0.86, 1.0, 0.17), y = 2.0, blur = 4.0),
    insetShadow(initColor(0.0, 0.05, 0.18, 0.15), y = -2.0, blur = 5.0),
  ]

func aquaPressedButtonShadows(): seq[BoxShadow] =
  @[
    dropShadow(initColor(0.0, 0.0, 0.0, 0.13), y = 1.0, blur = 3.0),
    insetShadow(initColor(0.0, 0.05, 0.20, 0.23), y = 2.0, blur = 5.0),
    insetShadow(initColor(1.0, 1.0, 1.0, 0.20), y = -1.0, blur = 3.0),
  ]

func aquaInsetControlShadows(): seq[BoxShadow] =
  @[
    insetShadow(initColor(0.0, 0.05, 0.18, 0.20), y = 1.0, blur = 3.0),
    insetShadow(initColor(1.0, 1.0, 1.0, 0.80), y = -1.0, blur = 2.0),
  ]

proc initTheme*(): Theme =
  result.tokens = newStyleTokenStore()
  result[AccentToken] = styleColor(initColor(0.10, 0.48, 0.96, 1.0))
  result[AccentPressedToken] = styleColor(initColor(0.02, 0.25, 0.70, 1.0))
  result[DisabledFillToken] = styleColor(initColor(0.64, 0.68, 0.74, 1.0))
  result[DisabledTextColorToken] = styleColor(initColor(0.90, 0.92, 0.95, 1.0))
  result[FocusRingColorToken] = styleColor(initColor(0.34, 0.66, 1.0, 0.72))

  result[ButtonFillToken] = aquaButtonFill()
  result[ButtonHighlightedFillToken] = aquaButtonPressedFill()
  result[ButtonDisabledFillToken] = aquaButtonDisabledFill()
  result[ButtonTextColorToken] = styleColor(initColor(1.0, 1.0, 1.0, 1.0))
  result[ButtonDisabledTextColorToken] = styleToken(DisabledTextColorToken)
  result[ButtonBorderColorToken] = styleColor(initColor(0.02, 0.20, 0.58, 1.0))
  result[ButtonHighlightedBorderColorToken] =
    styleColor(initColor(0.01, 0.12, 0.42, 1.0))
  result[ButtonDisabledBorderColorToken] = styleColor(initColor(0.52, 0.57, 0.64, 1.0))
  result[ButtonFocusRingColorToken] = styleColor(initColor(1.0, 1.0, 1.0, 0.90))
  result[ButtonShadowsToken] = aquaButtonShadows()
  result[ButtonHighlightedShadowsToken] = aquaPressedButtonShadows()
  result[ButtonDisabledShadowsToken] = newSeq[BoxShadow]()

  result[ChoiceIndicatorFillToken] = aquaChoiceFill()
  result[ChoiceIndicatorHighlightedFillToken] = aquaChoiceHighlightedFill()
  result[ChoiceIndicatorDisabledFillToken] = aquaButtonDisabledFill()
  result[ChoiceIndicatorSelectedFillToken] = aquaButtonFill()
  result[ChoiceIndicatorSelectedHighlightedFillToken] = aquaButtonPressedFill()
  result[ChoiceIndicatorSelectedDisabledFillToken] = aquaButtonDisabledFill()
  result[ChoiceIndicatorBorderColorToken] = styleColor(initColor(0.42, 0.50, 0.62, 1.0))
  result[ChoiceIndicatorHighlightedBorderColorToken] =
    styleColor(initColor(0.16, 0.38, 0.72, 1.0))
  result[ChoiceIndicatorDisabledBorderColorToken] =
    styleColor(initColor(0.64, 0.68, 0.74, 1.0))
  result[ChoiceMarkColorToken] = styleColor(initColor(1.0, 1.0, 1.0, 1.0))
  result[ChoiceDisabledMarkColorToken] = styleToken(DisabledTextColorToken)
  result[ChoiceTextColorToken] = styleColor(initColor(0.08, 0.09, 0.11, 1.0))
  result[ChoiceDisabledTextColorToken] = styleColor(initColor(0.48, 0.52, 0.58, 1.0))

  result[TextFieldFillToken] = aquaTextFieldFill()
  result[TextFieldBorderColorToken] = styleColor(initColor(0.56, 0.64, 0.76, 1.0))
  result[TextFieldTextColorToken] = styleColor(initColor(0.08, 0.09, 0.11, 1.0))
  result[TextFieldSelectionColorToken] = styleColor(initColor(0.24, 0.56, 1.0, 0.34))
  result[ComboBoxFillToken] = styleToken(TextFieldFillToken)
  result[ComboBoxBorderColorToken] = styleToken(TextFieldBorderColorToken)
  result[ComboBoxOpenBorderColorToken] = styleColor(initColor(0.12, 0.42, 0.86, 1.0))
  result[ComboBoxTextColorToken] = styleToken(TextFieldTextColorToken)
  result[ComboBoxArrowColorToken] = styleColor(initColor(0.10, 0.16, 0.26, 1.0))
  result[ComboBoxItemFillToken] = fill(initColor(1.0, 1.0, 1.0, 1.0))
  result[ComboBoxItemHighlightedFillToken] = aquaComboItemHighlightFill()
  result[ComboBoxItemSelectedFillToken] = aquaComboItemSelectedFill()
  result[ComboBoxItemSelectedHighlightedFillToken] =
    aquaComboItemSelectedHighlightedFill()
  result[ComboBoxItemTextColorToken] = styleColor(initColor(0.08, 0.09, 0.11, 1.0))
  result[ComboBoxItemSelectedTextColorToken] = styleColor(initColor(1.0, 1.0, 1.0, 1.0))
  result[ListViewFillToken] = styleToken(TextFieldFillToken)
  result[ListViewBorderColorToken] = styleToken(TextFieldBorderColorToken)
  result[ListItemFillToken] = styleToken(ComboBoxItemFillToken)
  result[ListItemHighlightedFillToken] = styleToken(ComboBoxItemHighlightedFillToken)
  result[ListItemSelectedFillToken] = styleToken(ComboBoxItemSelectedFillToken)
  result[ListItemSelectedHighlightedFillToken] =
    styleToken(ComboBoxItemSelectedHighlightedFillToken)
  result[ListItemTextColorToken] = styleToken(ComboBoxItemTextColorToken)
  result[ListItemSelectedTextColorToken] =
    styleToken(ComboBoxItemSelectedTextColorToken)
  result[ListItemSeparatorColorToken] = styleColor(initColor(0.86, 0.88, 0.91, 1.0))

  result.addRoleRule(
    srButton,
    {},
    styleToken(ButtonFillToken),
    styleToken(ButtonBorderColorToken),
    styleToken(ButtonTextColorToken),
  )
  result.addRoleRule(
    srButton,
    {ssHighlighted},
    styleToken(ButtonHighlightedFillToken),
    styleToken(ButtonHighlightedBorderColorToken),
    styleToken(ButtonTextColorToken),
  )
  result.addRoleRule(
    srButton,
    {ssActive},
    styleToken(ButtonHighlightedFillToken),
    styleToken(ButtonHighlightedBorderColorToken),
    styleToken(ButtonTextColorToken),
  )
  result.addRoleRule(
    srButton,
    {ssDisabled},
    styleToken(ButtonDisabledFillToken),
    styleToken(ButtonDisabledBorderColorToken),
    styleToken(ButtonDisabledTextColorToken),
  )
  result[srButton, StyleBorderWidth] = 1.0
  result[srButton, StyleCornerRadius] = 14.0
  result[srButton, StyleTextInsets] = initEdgeInsets(0.0, 8.0)
  result[srButton, StyleMinimumSize] = initSize(0.0, 32.0)
  result[srButton, StyleFocusRingWidth] = 3.0
  result[srButton, StyleFocusRingInset] = -2.0
  result[srButton, StyleFocusRingColor] = styleToken(ButtonFocusRingColorToken)
  result[srButton, StyleBoxShadows] = styleToken(ButtonShadowsToken)
  result[srButton, {ssHighlighted}, StyleBoxShadows] =
    styleToken(ButtonHighlightedShadowsToken)
  result[srButton, {ssActive}, StyleBoxShadows] =
    styleToken(ButtonHighlightedShadowsToken)
  result[srButton, {ssDisabled}, StyleBoxShadows] =
    styleToken(ButtonDisabledShadowsToken)

  for role in [srCheckBox, srRadioButton]:
    let radius = if role == srCheckBox: 6.0'f32 else: 7.0'f32
    result.addChoiceRule(
      role,
      {},
      styleToken(ChoiceIndicatorFillToken),
      styleToken(ChoiceIndicatorBorderColorToken),
      styleToken(ChoiceMarkColorToken),
      styleToken(ChoiceTextColorToken),
    )
    result.addChoiceRule(
      role,
      {ssHighlighted},
      styleToken(ChoiceIndicatorHighlightedFillToken),
      styleToken(ChoiceIndicatorHighlightedBorderColorToken),
      styleToken(ChoiceMarkColorToken),
      styleToken(ChoiceTextColorToken),
    )
    result.addChoiceRule(
      role,
      {ssSelected},
      styleToken(ChoiceIndicatorSelectedFillToken),
      styleToken(ChoiceIndicatorBorderColorToken),
      styleToken(ChoiceMarkColorToken),
      styleToken(ChoiceTextColorToken),
    )
    result.addChoiceRule(
      role,
      {ssSelected, ssHighlighted},
      styleToken(ChoiceIndicatorSelectedHighlightedFillToken),
      styleToken(ChoiceIndicatorHighlightedBorderColorToken),
      styleToken(ChoiceMarkColorToken),
      styleToken(ChoiceTextColorToken),
    )
    result.addChoiceRule(
      role,
      {ssDisabled},
      styleToken(ChoiceIndicatorDisabledFillToken),
      styleToken(ChoiceIndicatorDisabledBorderColorToken),
      styleToken(ChoiceDisabledMarkColorToken),
      styleToken(ChoiceDisabledTextColorToken),
    )
    result.addChoiceRule(
      role,
      {ssSelected, ssDisabled},
      styleToken(ChoiceIndicatorSelectedDisabledFillToken),
      styleToken(ChoiceIndicatorDisabledBorderColorToken),
      styleToken(ChoiceDisabledMarkColorToken),
      styleToken(ChoiceDisabledTextColorToken),
    )
    result[role, StyleIndicatorSize] = 14.0
    result[role, StyleBorderWidth] = 1.0
    result[role, StyleCornerRadius] = radius
    result[role, StyleIndicatorSpacing] = 7.0
    result[role, StyleTextInsets] = initEdgeInsets(0.0, 2.0)
    result[role, StyleMinimumSize] = initSize(0.0, 18.0)
    result[role, StyleFocusRingWidth] = 3.0
    result[role, StyleFocusRingInset] = 2.0
    result[role, StyleFocusRingColor] = styleToken(FocusRingColorToken)
    result[role, StyleBoxShadows] = aquaInsetControlShadows()

  result[srTextField, StyleFill] = styleToken(TextFieldFillToken)
  result[srTextField, StyleBorderColor] = styleToken(TextFieldBorderColorToken)
  result[srTextField, StyleBorderWidth] = 1.0
  result[srTextField, StyleCornerRadius] = 6.0
  result[srTextField, StyleTextInsets] = initEdgeInsets(0.0, 6.0)
  result[srTextField, StyleMinimumSize] = initSize(80.0, 24.0)
  result[srTextField, StyleSelectionColor] = styleToken(TextFieldSelectionColorToken)
  result[srTextField, StyleFocusRingWidth] = 3.0
  result[srTextField, StyleFocusRingInset] = -2.0
  result[srTextField, StyleFocusRingColor] = styleToken(FocusRingColorToken)
  result[srTextField, StyleBoxShadows] = aquaInsetControlShadows()

  result.addLabelRule(
    LabelStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(0.09, 0.12, 0.18, 1.0),
    initEdgeInsets(0.0),
    initSize(0.0, 18.0),
  )
  result.addLabelRule(
    LabelTitleStyleClass,
    linear(initColor(0.94, 0.98, 1.0, 1.0), initColor(0.84, 0.91, 0.98, 1.0), fgaY),
    initColor(0.62, 0.70, 0.84, 1.0),
    1.0,
    6.0,
    initColor(0.09, 0.14, 0.26, 1.0),
    initEdgeInsets(0.0, 12.0),
    initSize(0.0, 28.0),
  )
  result.addLabelRule(
    LabelHeadingStyleClass,
    linear(initColor(0.90, 0.95, 1.0, 1.0), initColor(0.78, 0.86, 0.96, 1.0), fgaY),
    initColor(0.74, 0.82, 0.93, 1.0),
    1.0,
    5.0,
    initColor(0.10, 0.18, 0.32, 1.0),
    initEdgeInsets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  result.addLabelRule(
    LabelStatusStyleClass,
    linear(initColor(0.94, 0.99, 0.95, 1.0), initColor(0.84, 0.94, 0.87, 1.0), fgaY),
    initColor(0.68, 0.82, 0.72, 1.0),
    1.0,
    6.0,
    initColor(0.09, 0.27, 0.18, 1.0),
    initEdgeInsets(0.0, 10.0),
    initSize(0.0, 24.0),
  )
  result.addLabelRule(
    LabelFormStyleClass,
    fill(initColor(0.0, 0.0, 0.0, 0.0)),
    initColor(0.0, 0.0, 0.0, 0.0),
    0.0,
    0.0,
    initColor(0.10, 0.14, 0.22, 1.0),
    initEdgeInsets(0.0, 2.0),
    initSize(0.0, 18.0),
  )

  result.addRoleRule(
    srComboBox,
    {},
    styleToken(ComboBoxFillToken),
    styleToken(ComboBoxBorderColorToken),
    styleToken(ComboBoxTextColorToken),
  )
  result.addRoleRule(
    srComboBox,
    {ssOpen},
    styleToken(ComboBoxFillToken),
    styleToken(ComboBoxOpenBorderColorToken),
    styleToken(ComboBoxTextColorToken),
  )
  result.addRoleRule(
    srComboBox,
    {ssDisabled},
    styleToken(TextFieldFillToken),
    styleToken(TextFieldBorderColorToken),
    styleToken(DisabledTextColorToken),
  )
  result[srComboBox, StyleBorderWidth] = 1.0
  result[srComboBox, StyleCornerRadius] = 6.0
  result[srComboBox, StyleTextInsets] = initEdgeInsets(0.0, 8.0)
  result[srComboBox, StyleFocusRingWidth] = 3.0
  result[srComboBox, StyleFocusRingInset] = -2.0
  result[srComboBox, StyleFocusRingColor] = styleToken(FocusRingColorToken)
  result[srComboBox, StyleIndicatorSize] = 24.0
  result[srComboBox, StyleMinimumSize] = initSize(90.0, 24.0)
  result[srComboBox, StyleMarkColor] = styleToken(ComboBoxArrowColorToken)
  result[srComboBox, StyleBoxShadows] = aquaInsetControlShadows()

  result.addRoleRule(
    srComboBoxItem,
    {},
    styleToken(ComboBoxItemFillToken),
    styleColor(initColor(0.0, 0.0, 0.0, 0.0)),
    styleToken(ComboBoxItemTextColorToken),
  )
  result.addRoleRule(
    srComboBoxItem,
    {ssHovered},
    styleToken(ComboBoxItemHighlightedFillToken),
    styleColor(initColor(0.0, 0.0, 0.0, 0.0)),
    styleToken(ComboBoxItemTextColorToken),
  )
  result.addRoleRule(
    srComboBoxItem,
    {ssSelected},
    styleToken(ComboBoxItemSelectedFillToken),
    styleColor(initColor(0.0, 0.0, 0.0, 0.0)),
    styleToken(ComboBoxItemSelectedTextColorToken),
  )
  result.addRoleRule(
    srComboBoxItem,
    {ssSelected, ssHovered},
    styleToken(ComboBoxItemSelectedHighlightedFillToken),
    styleColor(initColor(0.0, 0.0, 0.0, 0.0)),
    styleToken(ComboBoxItemSelectedTextColorToken),
  )
  result[srComboBoxItem, StyleBorderWidth] = 0.0
  result[srComboBoxItem, StyleCornerRadius] = 0.0
  result[srComboBoxItem, StyleTextInsets] = initEdgeInsets(0.0, 6.0)
  result[srComboBoxItem, StyleMinimumSize] = initSize(0.0, 22.0)

  result[srListView, StyleFill] = styleToken(ListViewFillToken)
  result[srListView, StyleBorderColor] = styleToken(ListViewBorderColorToken)
  result[srListView, StyleBorderWidth] = 1.0
  result[srListView, StyleCornerRadius] = 6.0
  result[srListView, StyleMinimumSize] = initSize(120.0, 24.0)
  result[srListView, StyleFocusRingWidth] = 3.0
  result[srListView, StyleFocusRingInset] = 2.0
  result[srListView, StyleFocusRingColor] = styleToken(FocusRingColorToken)
  result[srListView, StyleBoxShadows] = aquaInsetControlShadows()

  result.addRoleRule(
    srListItem,
    {},
    styleToken(ListItemFillToken),
    styleToken(ListItemSeparatorColorToken),
    styleToken(ListItemTextColorToken),
  )
  result.addRoleRule(
    srListItem,
    {ssHovered},
    styleToken(ListItemHighlightedFillToken),
    styleToken(ListItemSeparatorColorToken),
    styleToken(ListItemTextColorToken),
  )
  result.addRoleRule(
    srListItem,
    {ssHighlighted},
    styleToken(ListItemHighlightedFillToken),
    styleToken(ListItemSeparatorColorToken),
    styleToken(ListItemTextColorToken),
  )
  result.addRoleRule(
    srListItem,
    {ssPressed},
    styleToken(ListItemHighlightedFillToken),
    styleToken(ListItemSeparatorColorToken),
    styleToken(ListItemTextColorToken),
  )
  result.addRoleRule(
    srListItem,
    {ssSelected},
    styleToken(ListItemSelectedFillToken),
    styleToken(ListItemSeparatorColorToken),
    styleToken(ListItemSelectedTextColorToken),
  )
  result.addRoleRule(
    srListItem,
    {ssSelected, ssHovered},
    styleToken(ListItemSelectedHighlightedFillToken),
    styleToken(ListItemSeparatorColorToken),
    styleToken(ListItemSelectedTextColorToken),
  )
  result.addRoleRule(
    srListItem,
    {ssSelected, ssHighlighted},
    styleToken(ListItemSelectedHighlightedFillToken),
    styleToken(ListItemSeparatorColorToken),
    styleToken(ListItemSelectedTextColorToken),
  )
  result.addRoleRule(
    srListItem,
    {ssSelected, ssPressed},
    styleToken(ListItemSelectedHighlightedFillToken),
    styleToken(ListItemSeparatorColorToken),
    styleToken(ListItemSelectedTextColorToken),
  )
  result[srListItem, StyleBorderWidth] = 0.0
  result[srListItem, StyleCornerRadius] = 0.0
  result[srListItem, StyleTextInsets] = initEdgeInsets(0.0, 6.0)
  result[srListItem, StyleMinimumSize] = initSize(0.0, 22.0)

proc initBannerTheme*(): Theme =
  result = initTheme()
  result[AccentToken] = initColor(0.89, 0.38, 0.21, 1.0)
  result[AccentPressedToken] = initColor(0.62, 0.24, 0.14, 1.0)
  result[DisabledFillToken] = initColor(0.52, 0.50, 0.45, 1.0)
  result[DisabledTextColorToken] = initColor(0.94, 0.91, 0.86, 1.0)
  result[FocusRingColorToken] = initColor(0.31, 0.58, 0.54, 0.60)
  result[ListItemSeparatorColorToken] = initColor(0.74, 0.70, 0.63, 1.0)

  result[ButtonFillToken] = styleToken(AccentToken)
  result[ButtonHighlightedFillToken] = styleToken(AccentPressedToken)
  result[ButtonDisabledFillToken] = styleToken(DisabledFillToken)
  result[ButtonTextColorToken] = initColor(1.0, 0.97, 0.94, 1.0)
  result[ButtonBorderColorToken] = initColor(0.18, 0.12, 0.08, 1.0)
  result[ButtonHighlightedBorderColorToken] = initColor(0.12, 0.08, 0.05, 1.0)
  result[ButtonDisabledBorderColorToken] = initColor(0.40, 0.37, 0.33, 1.0)
  result[ButtonFocusRingColorToken] = initColor(1.0, 0.97, 0.94, 0.90)
  result[ButtonShadowsToken] = defaultButtonShadows()
  result[ButtonHighlightedShadowsToken] = highlightedButtonShadows()

  result[ChoiceIndicatorFillToken] = initColor(1.0, 0.97, 0.94, 1.0)
  result[ChoiceIndicatorHighlightedFillToken] = initColor(0.98, 0.93, 0.84, 1.0)
  result[ChoiceIndicatorDisabledFillToken] = initColor(0.86, 0.82, 0.75, 1.0)
  result[ChoiceIndicatorSelectedFillToken] = styleToken(AccentToken)
  result[ChoiceIndicatorSelectedHighlightedFillToken] = styleToken(AccentPressedToken)
  result[ChoiceIndicatorSelectedDisabledFillToken] = styleToken(DisabledFillToken)
  result[ChoiceIndicatorBorderColorToken] = initColor(0.54, 0.49, 0.42, 1.0)
  result[ChoiceIndicatorHighlightedBorderColorToken] = initColor(0.26, 0.51, 0.47, 1.0)
  result[ChoiceIndicatorDisabledBorderColorToken] = initColor(0.70, 0.65, 0.58, 1.0)
  result[ChoiceMarkColorToken] = initColor(1.0, 0.97, 0.94, 1.0)
  result[ChoiceTextColorToken] = initColor(0.11, 0.10, 0.10, 1.0)
  result[ChoiceDisabledTextColorToken] = initColor(0.48, 0.45, 0.40, 1.0)

  result[TextFieldFillToken] = initColor(1.0, 0.97, 0.94, 1.0)
  result[TextFieldBorderColorToken] = initColor(0.84, 0.80, 0.75, 1.0)
  result[TextFieldTextColorToken] = initColor(0.11, 0.10, 0.10, 1.0)
  result[TextFieldSelectionColorToken] = initColor(0.31, 0.58, 0.54, 0.32)

  result[ComboBoxOpenBorderColorToken] = initColor(0.31, 0.58, 0.54, 1.0)
  result[ComboBoxArrowColorToken] = initColor(0.16, 0.15, 0.15, 1.0)
  result[ComboBoxItemFillToken] = initColor(1.0, 0.97, 0.94, 1.0)
  result[ComboBoxItemHighlightedFillToken] = initColor(0.99, 0.93, 0.84, 1.0)
  result[ComboBoxItemSelectedFillToken] = initColor(0.26, 0.51, 0.47, 1.0)
  result[ComboBoxItemSelectedHighlightedFillToken] = initColor(0.19, 0.38, 0.35, 1.0)
  result[ComboBoxItemTextColorToken] = initColor(0.11, 0.10, 0.10, 1.0)
  result[ComboBoxItemSelectedTextColorToken] = initColor(1.0, 0.97, 0.94, 1.0)

proc initAppearance*(theme: Theme): Appearance =
  Appearance(theme: theme.clone)

proc initAppearance*(): Appearance =
  initAppearance(initTheme())
