import std/tables

import ./types

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

  StyleState* = enum
    ssDisabled
    ssHighlighted
    ssHovered
    ssActive
    ssFocused
    ssFocusVisible
    ssFocusWithin
    ssSelected
    ssOpen

  StyleContext* = object
    role*: StyleRole
    states*: set[StyleState]
    id*: string
    classes*: seq[string]

  StyleSelector* = object
    role*: StyleRole
    states*: set[StyleState]
    id*: string
    classes*: seq[string]

  StyleValueKind* = enum
    svMissing
    svColor
    svLength
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
    of svLength:
      length*: float32
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
    fill*: Color
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

  ChoiceButtonStyle* = object
    indicator*: ControlBoxStyle
    markColor*: Color
    text*: TextStyle
    indicatorSize*: float32
    indicatorSpacing*: float32

  TextFieldStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle

  ComboBoxStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle
    arrowWidth*: float32
    arrowColor*: Color

const
  StyleFill* = StyleKey[Color]("fill")
  StyleBorderColor* = StyleKey[Color]("border.color")
  StyleBorderWidth* = StyleKey[float32]("border.width")
  StyleCornerRadius* = StyleKey[float32]("corner.radius")
  StyleFocusRingWidth* = StyleKey[float32]("focus.ring.width")
  StyleFocusRingInset* = StyleKey[float32]("focus.ring.inset")
  StyleFocusRingColor* = StyleKey[Color]("focus.ring.color")
  StyleBoxShadows* = StyleKey[seq[BoxShadow]]("box.shadows")
  StyleTextColor* = StyleKey[Color]("text.color")
  StyleTextInsets* = StyleKey[EdgeInsets]("text.insets")
  StyleIndicatorSize* = StyleKey[float32]("indicator.size")
  StyleIndicatorSpacing* = StyleKey[float32]("indicator.spacing")
  StyleMarkColor* = StyleKey[Color]("mark.color")

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

func initEdgeInsets*(top, left, bottom, right: float32): EdgeInsets =
  EdgeInsets(top: top, left: left, bottom: bottom, right: right)

func initEdgeInsets*(vertical, horizontal: float32): EdgeInsets =
  initEdgeInsets(vertical, horizontal, vertical, horizontal)

func initEdgeInsets*(all: float32): EdgeInsets =
  initEdgeInsets(all, all, all, all)

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

func styleLength*(length: float32): StyleValue =
  StyleValue(kind: svLength, length: length)

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
    role: StyleRole, states: set[StyleState] = {}, id = "", classes: seq[string] = @[]
): StyleSelector =
  StyleSelector(role: role, states: states, id: id, classes: classes)

func initStyleContext*(
    role: StyleRole, states: set[StyleState] = {}, id = "", classes: seq[string] = @[]
): StyleContext =
  StyleContext(role: role, states: states, id: id, classes: classes)

func initControlStyleContext*(
    role: StyleRole,
    enabled = true,
    highlighted = false,
    hovered = false,
    active = false,
    focused = false,
    focusVisible = false,
    focusWithin = false,
    selected = false,
    opened = false,
    id = "",
    classes: seq[string] = @[],
): StyleContext =
  result = initStyleContext(role, id = id, classes = classes)
  if not enabled:
    result.states.incl ssDisabled
  if highlighted:
    result.states.incl ssHighlighted
  if hovered:
    result.states.incl ssHovered
  if active:
    result.states.incl ssActive
  if focused:
    result.states.incl ssFocused
  if focusVisible:
    result.states.incl ssFocusVisible
  if focusWithin:
    result.states.incl ssFocusWithin
  if selected:
    result.states.incl ssSelected
  if opened:
    result.states.incl ssOpen

func inset*(rect: Rect, insets: EdgeInsets): Rect =
  initRect(
    rect.origin.x + insets.left,
    rect.origin.y + insets.top,
    rect.size.width - insets.left - insets.right,
    rect.size.height - insets.top - insets.bottom,
  )

proc newStyleTokenStore*(parent: StyleTokenStore = nil): StyleTokenStore =
  StyleTokenStore(parent: parent, values: initTable[string, StyleValue]())

proc ensureTokens(theme: var Theme): StyleTokenStore =
  if theme.tokens.isNil:
    theme.tokens = newStyleTokenStore()
  theme.tokens

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

proc setToken*(tokens: StyleTokenStore, name: string, value: StyleValue) =
  if tokens.isNil:
    return
  tokens.values[name] = value

proc setToken*(tokens: StyleTokenStore, name: string, value: Color) =
  tokens.setToken(name, styleColor(value))

proc setToken*(tokens: StyleTokenStore, name: string, value: float32) =
  tokens.setToken(name, styleLength(value))

proc setToken*(tokens: StyleTokenStore, name: string, value: float) =
  tokens.setToken(name, styleLength(value.float32))

proc setToken*(tokens: StyleTokenStore, name: string, value: EdgeInsets) =
  tokens.setToken(name, styleInsets(value))

proc setToken*(tokens: StyleTokenStore, name: string, value: openArray[BoxShadow]) =
  tokens.setToken(name, styleShadows(value))

proc setToken*(theme: var Theme, name: string, value: StyleValue) =
  theme.ensureTokens().setToken(name, value)

proc setToken*(theme: var Theme, name: string, value: Color) =
  theme.ensureTokens().setToken(name, value)

proc setToken*(theme: var Theme, name: string, value: float32) =
  theme.ensureTokens().setToken(name, value)

proc setToken*(theme: var Theme, name: string, value: float) =
  theme.ensureTokens().setToken(name, value)

proc setToken*(theme: var Theme, name: string, value: EdgeInsets) =
  theme.ensureTokens().setToken(name, value)

proc setToken*(theme: var Theme, name: string, value: openArray[BoxShadow]) =
  theme.ensureTokens().setToken(name, value)

proc setDefaultToken*(tokens: StyleTokenStore, name: string, value: StyleValue) =
  if tokens.isNil:
    return
  if not tokens.values.hasKey(name):
    tokens.setToken(name, value)

proc setDefaultToken*(tokens: StyleTokenStore, name: string, value: Color) =
  tokens.setDefaultToken(name, styleColor(value))

proc setDefaultToken*(tokens: StyleTokenStore, name: string, value: float32) =
  tokens.setDefaultToken(name, styleLength(value))

proc setDefaultToken*(tokens: StyleTokenStore, name: string, value: float) =
  tokens.setDefaultToken(name, styleLength(value.float32))

proc setDefaultToken*(tokens: StyleTokenStore, name: string, value: EdgeInsets) =
  tokens.setDefaultToken(name, styleInsets(value))

proc setDefaultToken*(
    tokens: StyleTokenStore, name: string, value: openArray[BoxShadow]
) =
  tokens.setDefaultToken(name, styleShadows(value))

proc setDefaultToken*(theme: var Theme, name: string, value: StyleValue) =
  theme.ensureTokens().setDefaultToken(name, value)

proc setDefaultToken*(theme: var Theme, name: string, value: Color) =
  theme.ensureTokens().setDefaultToken(name, value)

proc setDefaultToken*(theme: var Theme, name: string, value: float32) =
  theme.ensureTokens().setDefaultToken(name, value)

proc setDefaultToken*(theme: var Theme, name: string, value: float) =
  theme.ensureTokens().setDefaultToken(name, value)

proc setDefaultToken*(theme: var Theme, name: string, value: EdgeInsets) =
  theme.ensureTokens().setDefaultToken(name, value)

proc setDefaultToken*(theme: var Theme, name: string, value: openArray[BoxShadow]) =
  theme.ensureTokens().setDefaultToken(name, value)

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
  if patch.isNil:
    return
  patch.values[key] = value

proc setStyle*[T](patch: StylePatch, key: StyleKey[T], value: StyleValue) =
  patch.setStyle(key.keyName, value)

proc setStyle*(patch: StylePatch, key: StyleKey[Color], value: Color) =
  patch.setStyle(key, styleColor(value))

proc setStyle*(patch: StylePatch, key: StyleKey[float32], value: float32) =
  patch.setStyle(key, styleLength(value))

proc setStyle*(patch: StylePatch, key: StyleKey[float32], value: float) =
  patch.setStyle(key, styleLength(value.float32))

proc setStyle*(patch: StylePatch, key: StyleKey[EdgeInsets], value: EdgeInsets) =
  patch.setStyle(key, styleInsets(value))

proc setStyle*(
    patch: StylePatch, key: StyleKey[seq[BoxShadow]], value: openArray[BoxShadow]
) =
  patch.setStyle(key, styleShadows(value))

proc getStyle*(patch: StylePatch, key: string, value: var StyleValue): bool =
  if patch.isNil:
    return false
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
    theme: var Theme, selector: StyleSelector, key: StyleKey[float32], value: float32
) =
  theme.stylePatch(selector).setStyle(key, value)

proc setStyle*(
    theme: var Theme, selector: StyleSelector, key: StyleKey[float32], value: float
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

proc setStyle*(
    theme: var Theme, role: StyleRole, key: StyleKey[float32], value: float32
) =
  theme.setStyle(initStyleSelector(role), key, value)

proc setStyle*(
    theme: var Theme, role: StyleRole, key: StyleKey[float32], value: float
) =
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
    states: set[StyleState],
    key: StyleKey[T],
    value: StyleValue,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[StyleState],
    key: StyleKey[Color],
    value: Color,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[StyleState],
    key: StyleKey[float32],
    value: float32,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[StyleState],
    key: StyleKey[float32],
    value: float,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[StyleState],
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc setStyle*(
    theme: var Theme,
    role: StyleRole,
    states: set[StyleState],
    key: StyleKey[seq[BoxShadow]],
    value: openArray[BoxShadow],
) =
  theme.setStyle(initStyleSelector(role, states), key, value)

proc `[]=`*[T](theme: var Theme, role: StyleRole, key: StyleKey[T], value: StyleValue) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[Color], value: Color) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[float32], value: float32) =
  theme.setStyle(role, key, value)

proc `[]=`*(theme: var Theme, role: StyleRole, key: StyleKey[float32], value: float) =
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
  if value.kind == svColor: value.color else: fallback

proc lengthRule(
    theme: Theme, context: StyleContext, key: StyleKey[float32], fallback: float32
): float32 =
  let value = theme.ruleValue(context, key.keyName, styleLength(fallback))
  if value.kind == svLength: value.length else: fallback

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
  if value.kind == svColor: value.color else: fallback

proc lengthToken*(theme: Theme, name: string, fallback: float32): float32 =
  let value = theme.styleValue(name, styleLength(fallback))
  if value.kind == svLength: value.length else: fallback

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

proc lengthToken*(appearance: Appearance, name: string, fallback: float32): float32 =
  appearance.theme.lengthToken(name, fallback)

proc insetsToken*(
    appearance: Appearance, name: string, fallback: EdgeInsets
): EdgeInsets =
  appearance.theme.insetsToken(name, fallback)

proc shadowsToken*(
    appearance: Appearance, name: string, fallback: seq[BoxShadow]
): seq[BoxShadow] =
  appearance.theme.shadowsToken(name, fallback)

proc setToken*(appearance: var Appearance, name: string, value: StyleValue) =
  appearance.theme.setToken(name, value)

proc setToken*(appearance: var Appearance, name: string, value: Color) =
  appearance.theme.setToken(name, value)

proc setToken*(appearance: var Appearance, name: string, value: float32) =
  appearance.theme.setToken(name, value)

proc setToken*(appearance: var Appearance, name: string, value: float) =
  appearance.theme.setToken(name, value)

proc setToken*(appearance: var Appearance, name: string, value: EdgeInsets) =
  appearance.theme.setToken(name, value)

proc setToken*(appearance: var Appearance, name: string, value: openArray[BoxShadow]) =
  appearance.theme.setToken(name, value)

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
    key: StyleKey[float32],
    value: float32,
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
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float32
) =
  appearance.theme.setStyle(role, key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float
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
    appearance: var Appearance, role: StyleRole, key: StyleKey[T], value: StyleValue
) =
  appearance.setStyle(role, key, value)

proc `[]=`*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Color], value: Color
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

proc `[]`*[T](appearance: Appearance, role: StyleRole, key: StyleKey[T]): StyleValue =
  appearance.theme[role, key]

proc resolveButtonStyle*(theme: Theme, context: StyleContext): ButtonStyle =
  ButtonStyle(
    box: ControlBoxStyle(
      fill: theme.colorRule(context, StyleFill, initColor(0.20, 0.48, 0.86, 1.0)),
      borderColor:
        theme.colorRule(context, StyleBorderColor, initColor(0.10, 0.25, 0.46, 1.0)),
      borderWidth: theme.lengthRule(context, StyleBorderWidth, 1.0),
      cornerRadius: theme.lengthRule(context, StyleCornerRadius, 4.0),
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
  )

proc resolveChoiceButtonStyle*(theme: Theme, context: StyleContext): ChoiceButtonStyle =
  ChoiceButtonStyle(
    indicator: ControlBoxStyle(
      fill: theme.colorRule(context, StyleFill, initColor(1.0, 1.0, 1.0, 1.0)),
      borderColor:
        theme.colorRule(context, StyleBorderColor, initColor(0.50, 0.55, 0.62, 1.0)),
      borderWidth: theme.lengthRule(context, StyleBorderWidth, 1.0),
      cornerRadius: theme.lengthRule(context, StyleCornerRadius, 3.0),
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
  )

proc resolveTextFieldStyle*(
    theme: Theme, context: StyleContext, textColor: Color
): TextFieldStyle =
  TextFieldStyle(
    box: ControlBoxStyle(
      fill: theme.colorRule(context, StyleFill, initColor(1.0, 1.0, 1.0, 1.0)),
      borderColor:
        theme.colorRule(context, StyleBorderColor, initColor(0.72, 0.75, 0.80, 1.0)),
      borderWidth: theme.lengthRule(context, StyleBorderWidth, 1.0),
      cornerRadius: theme.lengthRule(context, StyleCornerRadius, 3.0),
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
  )

proc resolveTextFieldStyle*(theme: Theme, context: StyleContext): TextFieldStyle =
  theme.resolveTextFieldStyle(context, initColor(0.08, 0.09, 0.11, 1.0))

proc resolveComboBoxStyle*(theme: Theme, context: StyleContext): ComboBoxStyle =
  ComboBoxStyle(
    box: ControlBoxStyle(
      fill: theme.colorRule(context, StyleFill, initColor(1.0, 1.0, 1.0, 1.0)),
      borderColor:
        theme.colorRule(context, StyleBorderColor, initColor(0.72, 0.75, 0.80, 1.0)),
      borderWidth: theme.lengthRule(context, StyleBorderWidth, 1.0),
      cornerRadius: theme.lengthRule(context, StyleCornerRadius, 3.0),
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

proc addRoleRule(
    theme: var Theme,
    role: StyleRole,
    states: set[StyleState],
    fill: StyleValue,
    borderColor: StyleValue,
    textColor: StyleValue,
) =
  let selector = initStyleSelector(role, states)
  theme.setStyle(selector, StyleFill, fill)
  theme.setStyle(selector, StyleBorderColor, borderColor)
  theme.setStyle(selector, StyleTextColor, textColor)

proc addChoiceRule(
    theme: var Theme,
    role: StyleRole,
    states: set[StyleState],
    fill: StyleValue,
    borderColor: StyleValue,
    markColor: StyleValue,
    textColor: StyleValue,
) =
  let selector = initStyleSelector(role, states)
  theme.setStyle(selector, StyleFill, fill)
  theme.setStyle(selector, StyleBorderColor, borderColor)
  theme.setStyle(selector, StyleMarkColor, markColor)
  theme.setStyle(selector, StyleTextColor, textColor)

func defaultButtonShadows(): seq[BoxShadow] =
  @[
    insetShadow(initColor(1.0, 1.0, 1.0, 0.30), x = 1.0, y = 1.0, blur = 9.0),
    insetShadow(initColor(0.0, 0.0, 0.0, 0.24), x = -1.0, y = -1.0, blur = 9.0),
  ]

func highlightedButtonShadows(): seq[BoxShadow] =
  @[
    insetShadow(initColor(1.0, 1.0, 1.0, 0.12), x = 1.0, y = 1.0, blur = 3.0),
    insetShadow(initColor(0.0, 0.0, 0.0, 0.38), x = -1.0, y = -1.0, blur = 12.0),
  ]

proc initTheme*(): Theme =
  result.tokens = newStyleTokenStore()
  result.setDefaultToken(AccentToken, styleColor(initColor(0.20, 0.48, 0.86, 1.0)))
  result.setDefaultToken(
    AccentPressedToken, styleColor(initColor(0.12, 0.34, 0.68, 1.0))
  )
  result.setDefaultToken(
    DisabledFillToken, styleColor(initColor(0.58, 0.62, 0.68, 1.0))
  )
  result.setDefaultToken(
    DisabledTextColorToken, styleColor(initColor(0.92, 0.94, 0.96, 1.0))
  )
  result.setDefaultToken(
    FocusRingColorToken, styleColor(initColor(0.24, 0.48, 0.92, 0.58))
  )

  result.setDefaultToken(ButtonFillToken, styleToken(AccentToken))
  result.setDefaultToken(ButtonHighlightedFillToken, styleToken(AccentPressedToken))
  result.setDefaultToken(ButtonDisabledFillToken, styleToken(DisabledFillToken))
  result.setDefaultToken(
    ButtonTextColorToken, styleColor(initColor(1.0, 1.0, 1.0, 1.0))
  )
  result.setDefaultToken(
    ButtonDisabledTextColorToken, styleToken(DisabledTextColorToken)
  )
  result.setDefaultToken(
    ButtonBorderColorToken, styleColor(initColor(0.10, 0.25, 0.46, 1.0))
  )
  result.setDefaultToken(
    ButtonHighlightedBorderColorToken, styleColor(initColor(0.06, 0.18, 0.36, 1.0))
  )
  result.setDefaultToken(
    ButtonDisabledBorderColorToken, styleColor(initColor(0.46, 0.50, 0.56, 1.0))
  )
  result.setDefaultToken(
    ButtonFocusRingColorToken, styleColor(initColor(1.0, 1.0, 1.0, 0.90))
  )
  result.setDefaultToken(ButtonShadowsToken, defaultButtonShadows())
  result.setDefaultToken(ButtonHighlightedShadowsToken, highlightedButtonShadows())
  result.setDefaultToken(ButtonDisabledShadowsToken, newSeq[BoxShadow]())

  result.setDefaultToken(
    ChoiceIndicatorFillToken, styleColor(initColor(1.0, 1.0, 1.0, 1.0))
  )
  result.setDefaultToken(
    ChoiceIndicatorHighlightedFillToken, styleColor(initColor(0.90, 0.94, 1.0, 1.0))
  )
  result.setDefaultToken(
    ChoiceIndicatorDisabledFillToken, styleColor(initColor(0.90, 0.92, 0.95, 1.0))
  )
  result.setDefaultToken(ChoiceIndicatorSelectedFillToken, styleToken(AccentToken))
  result.setDefaultToken(
    ChoiceIndicatorSelectedHighlightedFillToken, styleToken(AccentPressedToken)
  )
  result.setDefaultToken(
    ChoiceIndicatorSelectedDisabledFillToken, styleToken(DisabledFillToken)
  )
  result.setDefaultToken(
    ChoiceIndicatorBorderColorToken, styleColor(initColor(0.50, 0.55, 0.62, 1.0))
  )
  result.setDefaultToken(
    ChoiceIndicatorHighlightedBorderColorToken,
    styleColor(initColor(0.24, 0.38, 0.58, 1.0)),
  )
  result.setDefaultToken(
    ChoiceIndicatorDisabledBorderColorToken,
    styleColor(initColor(0.68, 0.72, 0.78, 1.0)),
  )
  result.setDefaultToken(
    ChoiceMarkColorToken, styleColor(initColor(1.0, 1.0, 1.0, 1.0))
  )
  result.setDefaultToken(
    ChoiceDisabledMarkColorToken, styleToken(DisabledTextColorToken)
  )
  result.setDefaultToken(
    ChoiceTextColorToken, styleColor(initColor(0.08, 0.09, 0.11, 1.0))
  )
  result.setDefaultToken(
    ChoiceDisabledTextColorToken, styleColor(initColor(0.52, 0.56, 0.62, 1.0))
  )

  result.setDefaultToken(TextFieldFillToken, styleColor(initColor(1.0, 1.0, 1.0, 1.0)))
  result.setDefaultToken(
    TextFieldBorderColorToken, styleColor(initColor(0.72, 0.75, 0.80, 1.0))
  )
  result.setDefaultToken(
    TextFieldTextColorToken, styleColor(initColor(0.08, 0.09, 0.11, 1.0))
  )
  result.setDefaultToken(ComboBoxFillToken, styleToken(TextFieldFillToken))
  result.setDefaultToken(
    ComboBoxBorderColorToken, styleToken(TextFieldBorderColorToken)
  )
  result.setDefaultToken(
    ComboBoxOpenBorderColorToken, styleColor(initColor(0.30, 0.50, 0.84, 1.0))
  )
  result.setDefaultToken(ComboBoxTextColorToken, styleToken(TextFieldTextColorToken))
  result.setDefaultToken(
    ComboBoxArrowColorToken, styleColor(initColor(0.20, 0.22, 0.26, 1.0))
  )
  result.setDefaultToken(
    ComboBoxItemFillToken, styleColor(initColor(1.0, 1.0, 1.0, 1.0))
  )
  result.setDefaultToken(
    ComboBoxItemHighlightedFillToken, styleColor(initColor(0.88, 0.93, 1.0, 1.0))
  )
  result.setDefaultToken(
    ComboBoxItemSelectedFillToken, styleColor(initColor(0.20, 0.48, 0.86, 1.0))
  )
  result.setDefaultToken(
    ComboBoxItemSelectedHighlightedFillToken,
    styleColor(initColor(0.12, 0.34, 0.68, 1.0)),
  )
  result.setDefaultToken(
    ComboBoxItemTextColorToken, styleColor(initColor(0.08, 0.09, 0.11, 1.0))
  )
  result.setDefaultToken(
    ComboBoxItemSelectedTextColorToken, styleColor(initColor(1.0, 1.0, 1.0, 1.0))
  )

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
  result.setStyle(srButton, StyleBorderWidth, 1.0)
  result.setStyle(srButton, StyleCornerRadius, 4.0)
  result.setStyle(srButton, StyleTextInsets, initEdgeInsets(0.0, 8.0))
  result.setStyle(srButton, StyleFocusRingWidth, 3.0)
  result.setStyle(srButton, StyleFocusRingInset, -2.0)
  result.setStyle(srButton, StyleFocusRingColor, styleToken(ButtonFocusRingColorToken))
  result.setStyle(srButton, StyleBoxShadows, styleToken(ButtonShadowsToken))
  result.setStyle(
    srButton,
    {ssHighlighted},
    StyleBoxShadows,
    styleToken(ButtonHighlightedShadowsToken),
  )
  result.setStyle(
    srButton, {ssActive}, StyleBoxShadows, styleToken(ButtonHighlightedShadowsToken)
  )
  result.setStyle(
    srButton, {ssDisabled}, StyleBoxShadows, styleToken(ButtonDisabledShadowsToken)
  )

  for role in [srCheckBox, srRadioButton]:
    let radius = if role == srCheckBox: 3.0'f32 else: 7.0'f32
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
    result.setStyle(role, StyleIndicatorSize, 14.0)
    result.setStyle(role, StyleBorderWidth, 1.0)
    result.setStyle(role, StyleCornerRadius, radius)
    result.setStyle(role, StyleIndicatorSpacing, 7.0)
    result.setStyle(role, StyleTextInsets, initEdgeInsets(0.0, 2.0))
    result.setStyle(role, StyleFocusRingWidth, 3.0)
    result.setStyle(role, StyleFocusRingInset, 2.0)
    result.setStyle(role, StyleFocusRingColor, styleToken(FocusRingColorToken))

  result.setStyle(srTextField, StyleFill, styleToken(TextFieldFillToken))
  result.setStyle(srTextField, StyleBorderColor, styleToken(TextFieldBorderColorToken))
  result.setStyle(srTextField, StyleBorderWidth, 1.0)
  result.setStyle(srTextField, StyleCornerRadius, 3.0)
  result.setStyle(srTextField, StyleTextInsets, initEdgeInsets(0.0, 6.0))
  result.setStyle(srTextField, StyleFocusRingWidth, 3.0)
  result.setStyle(srTextField, StyleFocusRingInset, 2.0)
  result.setStyle(srTextField, StyleFocusRingColor, styleToken(FocusRingColorToken))

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
  result.setStyle(srComboBox, StyleBorderWidth, 1.0)
  result.setStyle(srComboBox, StyleCornerRadius, 3.0)
  result.setStyle(srComboBox, StyleTextInsets, initEdgeInsets(0.0, 8.0))
  result.setStyle(srComboBox, StyleFocusRingWidth, 3.0)
  result.setStyle(srComboBox, StyleFocusRingInset, 2.0)
  result.setStyle(srComboBox, StyleFocusRingColor, styleToken(FocusRingColorToken))
  result.setStyle(srComboBox, StyleIndicatorSize, 24.0)
  result.setStyle(srComboBox, StyleMarkColor, styleToken(ComboBoxArrowColorToken))

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
  result.setStyle(srComboBoxItem, StyleBorderWidth, 0.0)
  result.setStyle(srComboBoxItem, StyleCornerRadius, 0.0)
  result.setStyle(srComboBoxItem, StyleTextInsets, initEdgeInsets(0.0, 6.0))

proc initAppearance*(theme: Theme): Appearance =
  Appearance(theme: theme.clone)

proc initAppearance*(): Appearance =
  initAppearance(initTheme())
