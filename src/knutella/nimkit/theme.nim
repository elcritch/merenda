import std/tables

import ./types

type
  EdgeInsets* = object
    top*: float32
    left*: float32
    bottom*: float32
    right*: float32

  StyleRole* = enum
    srView
    srButton
    srCheckBox
    srRadioButton
    srTextField

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

  StyleValueKind* = enum
    svMissing
    svColor
    svLength
    svInsets
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

  ThemeControlState* = enum
    tcsNormal
    tcsHighlighted
    tcsDisabled

  ControlBoxStyle* = object
    fill*: Color
    borderColor*: Color
    borderWidth*: float32
    cornerRadius*: float32
    focusRingWidth*: float32
    focusRingInset*: float32
    focusRingColor*: Color

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

  ButtonTheme* = object
    fill*: array[ThemeControlState, Color]
    textColor*: array[ThemeControlState, Color]
    borderColor*: array[ThemeControlState, Color]
    borderWidth*: float32
    cornerRadius*: float32
    contentInsets*: EdgeInsets
    focusRingWidth*: float32
    focusRingInset*: float32
    focusRingColor*: Color

  ChoiceButtonTheme* = object
    indicatorFill*: array[ThemeControlState, Color]
    indicatorSelectedFill*: array[ThemeControlState, Color]
    indicatorBorderColor*: array[ThemeControlState, Color]
    markColor*: array[ThemeControlState, Color]
    textColor*: array[ThemeControlState, Color]
    indicatorSize*: float32
    indicatorBorderWidth*: float32
    checkBoxCornerRadius*: float32
    radioCornerRadius*: float32
    indicatorSpacing*: float32
    contentInsets*: EdgeInsets
    focusRingWidth*: float32
    focusRingInset*: float32
    focusRingColor*: Color

  TextFieldTheme* = object
    fill*: Color
    borderColor*: Color
    borderWidth*: float32
    cornerRadius*: float32
    textInsets*: EdgeInsets
    focusRingWidth*: float32
    focusRingInset*: float32
    focusRingColor*: Color

  Theme* = object
    button*: ButtonTheme
    choiceButton*: ChoiceButtonTheme
    textField*: TextFieldTheme

  Appearance* = object
    theme*: Theme
    tokens*: StyleTokenStore
    patches*: array[StyleRole, StylePatch]

const
  StyleFill* = StyleKey[Color]("fill")
  StyleBorderColor* = StyleKey[Color]("border.color")
  StyleBorderWidth* = StyleKey[float32]("border.width")
  StyleCornerRadius* = StyleKey[float32]("corner.radius")
  StyleFocusRingWidth* = StyleKey[float32]("focus.ring.width")
  StyleFocusRingInset* = StyleKey[float32]("focus.ring.inset")
  StyleFocusRingColor* = StyleKey[Color]("focus.ring.color")
  StyleTextColor* = StyleKey[Color]("text.color")
  StyleTextInsets* = StyleKey[EdgeInsets]("text.insets")
  StyleIndicatorSize* = StyleKey[float32]("indicator.size")
  StyleIndicatorSpacing* = StyleKey[float32]("indicator.spacing")
  StyleMarkColor* = StyleKey[Color]("mark.color")

  ButtonFillTokens*: array[ThemeControlState, string] = [
    tcsNormal: "button.fill",
    tcsHighlighted: "button.fill.highlighted",
    tcsDisabled: "button.fill.disabled",
  ]
  ButtonTextColorTokens*: array[ThemeControlState, string] = [
    tcsNormal: "button.text.color",
    tcsHighlighted: "button.text.color.highlighted",
    tcsDisabled: "button.text.color.disabled",
  ]
  ButtonBorderColorTokens*: array[ThemeControlState, string] = [
    tcsNormal: "button.border.color",
    tcsHighlighted: "button.border.color.highlighted",
    tcsDisabled: "button.border.color.disabled",
  ]
  ButtonBorderWidthToken* = "button.border.width"
  ButtonCornerRadiusToken* = "button.corner.radius"
  ButtonContentInsetsToken* = "button.content.insets"
  ButtonFocusRingWidthToken* = "button.focus.ring.width"
  ButtonFocusRingInsetToken* = "button.focus.ring.inset"
  ButtonFocusRingColorToken* = "button.focus.ring.color"
  CheckBoxIndicatorFillTokens*: array[ThemeControlState, string] = [
    tcsNormal: "checkBox.indicator.fill",
    tcsHighlighted: "checkBox.indicator.fill.highlighted",
    tcsDisabled: "checkBox.indicator.fill.disabled",
  ]
  CheckBoxIndicatorSelectedFillTokens*: array[ThemeControlState, string] = [
    tcsNormal: "checkBox.indicator.fill.selected",
    tcsHighlighted: "checkBox.indicator.fill.selected.highlighted",
    tcsDisabled: "checkBox.indicator.fill.selected.disabled",
  ]
  CheckBoxIndicatorBorderColorTokens*: array[ThemeControlState, string] = [
    tcsNormal: "checkBox.indicator.border.color",
    tcsHighlighted: "checkBox.indicator.border.color.highlighted",
    tcsDisabled: "checkBox.indicator.border.color.disabled",
  ]
  CheckBoxMarkColorTokens*: array[ThemeControlState, string] = [
    tcsNormal: "checkBox.mark.color",
    tcsHighlighted: "checkBox.mark.color.highlighted",
    tcsDisabled: "checkBox.mark.color.disabled",
  ]
  CheckBoxTextColorTokens*: array[ThemeControlState, string] = [
    tcsNormal: "checkBox.text.color",
    tcsHighlighted: "checkBox.text.color.highlighted",
    tcsDisabled: "checkBox.text.color.disabled",
  ]
  CheckBoxIndicatorSizeToken* = "checkBox.indicator.size"
  CheckBoxIndicatorBorderWidthToken* = "checkBox.indicator.border.width"
  CheckBoxIndicatorCornerRadiusToken* = "checkBox.indicator.corner.radius"
  CheckBoxIndicatorSpacingToken* = "checkBox.indicator.spacing"
  CheckBoxContentInsetsToken* = "checkBox.content.insets"
  CheckBoxFocusRingWidthToken* = "checkBox.focus.ring.width"
  CheckBoxFocusRingInsetToken* = "checkBox.focus.ring.inset"
  CheckBoxFocusRingColorToken* = "checkBox.focus.ring.color"
  RadioButtonIndicatorFillTokens*: array[ThemeControlState, string] = [
    tcsNormal: "radioButton.indicator.fill",
    tcsHighlighted: "radioButton.indicator.fill.highlighted",
    tcsDisabled: "radioButton.indicator.fill.disabled",
  ]
  RadioButtonIndicatorSelectedFillTokens*: array[ThemeControlState, string] = [
    tcsNormal: "radioButton.indicator.fill.selected",
    tcsHighlighted: "radioButton.indicator.fill.selected.highlighted",
    tcsDisabled: "radioButton.indicator.fill.selected.disabled",
  ]
  RadioButtonIndicatorBorderColorTokens*: array[ThemeControlState, string] = [
    tcsNormal: "radioButton.indicator.border.color",
    tcsHighlighted: "radioButton.indicator.border.color.highlighted",
    tcsDisabled: "radioButton.indicator.border.color.disabled",
  ]
  RadioButtonMarkColorTokens*: array[ThemeControlState, string] = [
    tcsNormal: "radioButton.mark.color",
    tcsHighlighted: "radioButton.mark.color.highlighted",
    tcsDisabled: "radioButton.mark.color.disabled",
  ]
  RadioButtonTextColorTokens*: array[ThemeControlState, string] = [
    tcsNormal: "radioButton.text.color",
    tcsHighlighted: "radioButton.text.color.highlighted",
    tcsDisabled: "radioButton.text.color.disabled",
  ]
  RadioButtonIndicatorSizeToken* = "radioButton.indicator.size"
  RadioButtonIndicatorBorderWidthToken* = "radioButton.indicator.border.width"
  RadioButtonIndicatorCornerRadiusToken* = "radioButton.indicator.corner.radius"
  RadioButtonIndicatorSpacingToken* = "radioButton.indicator.spacing"
  RadioButtonContentInsetsToken* = "radioButton.content.insets"
  RadioButtonFocusRingWidthToken* = "radioButton.focus.ring.width"
  RadioButtonFocusRingInsetToken* = "radioButton.focus.ring.inset"
  RadioButtonFocusRingColorToken* = "radioButton.focus.ring.color"
  TextFieldFillToken* = "textField.fill"
  TextFieldBorderColorToken* = "textField.border.color"
  TextFieldBorderWidthToken* = "textField.border.width"
  TextFieldCornerRadiusToken* = "textField.corner.radius"
  TextFieldTextInsetsToken* = "textField.text.insets"
  TextFieldTextColorToken* = "textField.text.color"
  TextFieldFocusRingWidthToken* = "textField.focus.ring.width"
  TextFieldFocusRingInsetToken* = "textField.focus.ring.inset"
  TextFieldFocusRingColorToken* = "textField.focus.ring.color"

func initEdgeInsets*(top, left, bottom, right: float32): EdgeInsets =
  EdgeInsets(top: top, left: left, bottom: bottom, right: right)

func initEdgeInsets*(vertical, horizontal: float32): EdgeInsets =
  initEdgeInsets(vertical, horizontal, vertical, horizontal)

func initEdgeInsets*(all: float32): EdgeInsets =
  initEdgeInsets(all, all, all, all)

func missingStyleValue*(): StyleValue =
  StyleValue(kind: svMissing)

func styleColor*(color: Color): StyleValue =
  StyleValue(kind: svColor, color: color)

func styleLength*(length: float32): StyleValue =
  StyleValue(kind: svLength, length: length)

func styleInsets*(insets: EdgeInsets): StyleValue =
  StyleValue(kind: svInsets, insets: insets)

func styleToken*(name: string): StyleValue =
  StyleValue(kind: svToken, token: name)

func styleKeyword*(keyword: string): StyleValue =
  StyleValue(kind: svKeyword, keyword: keyword)

func styleKey*[T](name: string): StyleKey[T] =
  StyleKey[T](name)

func keyName*[T](key: StyleKey[T]): string =
  string(key)

proc newStyleTokenStore*(parent: StyleTokenStore = nil): StyleTokenStore =
  StyleTokenStore(parent: parent, values: initTable[string, StyleValue]())

proc newStylePatch*(): StylePatch =
  StylePatch(values: initTable[string, StyleValue]())

proc setToken*(tokens: StyleTokenStore, name: string, value: StyleValue) =
  if tokens.isNil:
    return
  tokens.values[name] = value

proc setDefaultToken*(tokens: StyleTokenStore, name: string, value: StyleValue) =
  if tokens.isNil:
    return
  if not tokens.values.hasKey(name):
    tokens.setToken(name, value)

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

proc getStyle*(patch: StylePatch, key: string, value: var StyleValue): bool =
  if patch.isNil:
    return false
  if patch.values.hasKey(key):
    value = patch.values[key]
    return true

proc getStyle*[T](patch: StylePatch, key: StyleKey[T], value: var StyleValue): bool =
  patch.getStyle(key.keyName, value)

proc stylePatch*(appearance: Appearance, role: StyleRole): StylePatch =
  appearance.patches[role]

proc stylePatch*(appearance: var Appearance, role: StyleRole): StylePatch =
  if appearance.patches[role].isNil:
    appearance.patches[role] = newStylePatch()
  appearance.patches[role]

proc setStyle*[T](
    appearance: var Appearance, role: StyleRole, key: StyleKey[T], value: StyleValue
) =
  appearance.stylePatch(role).setStyle(key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[Color], value: Color
) =
  appearance.stylePatch(role).setStyle(key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float32
) =
  appearance.stylePatch(role).setStyle(key, value)

proc setStyle*(
    appearance: var Appearance, role: StyleRole, key: StyleKey[float32], value: float
) =
  appearance.stylePatch(role).setStyle(key, value)

proc setStyle*(
    appearance: var Appearance,
    role: StyleRole,
    key: StyleKey[EdgeInsets],
    value: EdgeInsets,
) =
  appearance.stylePatch(role).setStyle(key, value)

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

proc `[]`*[T](appearance: Appearance, role: StyleRole, key: StyleKey[T]): StyleValue =
  if not appearance.stylePatch(role).getStyle(key, result):
    result = missingStyleValue()

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

func buttonThemeState*(context: StyleContext): ThemeControlState =
  if ssDisabled in context.states:
    tcsDisabled
  elif ssHighlighted in context.states or ssActive in context.states:
    tcsHighlighted
  else:
    tcsNormal

func buttonThemeState*(enabled, highlighted: bool): ThemeControlState =
  buttonThemeState(initControlStyleContext(srButton, enabled, highlighted))

func resolveButtonStyle*(theme: Theme, context: StyleContext): ButtonStyle =
  let state = buttonThemeState(context)
  ButtonStyle(
    box: ControlBoxStyle(
      fill: theme.button.fill[state],
      borderColor: theme.button.borderColor[state],
      borderWidth: theme.button.borderWidth,
      cornerRadius: theme.button.cornerRadius,
      focusRingWidth: theme.button.focusRingWidth,
      focusRingInset: theme.button.focusRingInset,
      focusRingColor: theme.button.focusRingColor,
    ),
    text: TextStyle(
      color: theme.button.textColor[state], insets: theme.button.contentInsets
    ),
  )

func choiceButtonCornerRadius(theme: ChoiceButtonTheme, role: StyleRole): float32 =
  if role == srRadioButton: theme.radioCornerRadius else: theme.checkBoxCornerRadius

func resolveChoiceButtonStyle*(theme: Theme, context: StyleContext): ChoiceButtonStyle =
  let
    state = buttonThemeState(context)
    selected = ssSelected in context.states
    indicatorFill =
      if selected:
        theme.choiceButton.indicatorSelectedFill[state]
      else:
        theme.choiceButton.indicatorFill[state]
  ChoiceButtonStyle(
    indicator: ControlBoxStyle(
      fill: indicatorFill,
      borderColor: theme.choiceButton.indicatorBorderColor[state],
      borderWidth: theme.choiceButton.indicatorBorderWidth,
      cornerRadius: theme.choiceButton.choiceButtonCornerRadius(context.role),
      focusRingWidth: theme.choiceButton.focusRingWidth,
      focusRingInset: theme.choiceButton.focusRingInset,
      focusRingColor: theme.choiceButton.focusRingColor,
    ),
    markColor: theme.choiceButton.markColor[state],
    text: TextStyle(
      color: theme.choiceButton.textColor[state],
      insets: theme.choiceButton.contentInsets,
    ),
    indicatorSize: theme.choiceButton.indicatorSize,
    indicatorSpacing: theme.choiceButton.indicatorSpacing,
  )

func resolveTextFieldStyle*(
    theme: Theme, context: StyleContext, textColor: Color
): TextFieldStyle =
  TextFieldStyle(
    box: ControlBoxStyle(
      fill: theme.textField.fill,
      borderColor: theme.textField.borderColor,
      borderWidth: theme.textField.borderWidth,
      cornerRadius: theme.textField.cornerRadius,
      focusRingWidth: theme.textField.focusRingWidth,
      focusRingInset: theme.textField.focusRingInset,
      focusRingColor: theme.textField.focusRingColor,
    ),
    text: TextStyle(color: textColor, insets: theme.textField.textInsets),
  )

func resolveTextFieldStyle*(theme: Theme, context: StyleContext): TextFieldStyle =
  resolveTextFieldStyle(theme, context, initColor(0.08, 0.09, 0.11))

proc styleValue*(
    appearance: Appearance, name: string, fallback: StyleValue
): StyleValue =
  if appearance.tokens.isNil:
    return fallback
  if not appearance.tokens.resolveToken(name, result):
    result = fallback

proc colorToken*(appearance: Appearance, name: string, fallback: Color): Color =
  let value = appearance.styleValue(name, styleColor(fallback))
  if value.kind == svColor: value.color else: fallback

proc lengthToken*(appearance: Appearance, name: string, fallback: float32): float32 =
  let value = appearance.styleValue(name, styleLength(fallback))
  if value.kind == svLength: value.length else: fallback

proc insetsToken*(
    appearance: Appearance, name: string, fallback: EdgeInsets
): EdgeInsets =
  let value = appearance.styleValue(name, styleInsets(fallback))
  if value.kind == svInsets: value.insets else: fallback

proc patchValue(
    appearance: Appearance, role: StyleRole, key: string, fallback: StyleValue
): StyleValue =
  var value: StyleValue
  if not appearance.stylePatch(role).getStyle(key, value):
    return fallback
  if not appearance.tokens.resolveValue(value, result):
    result = fallback

proc colorPatch*(
    appearance: Appearance, role: StyleRole, key: StyleKey[Color], fallback: Color
): Color =
  let value = appearance.patchValue(role, key.keyName, styleColor(fallback))
  if value.kind == svColor: value.color else: fallback

proc lengthPatch*(
    appearance: Appearance, role: StyleRole, key: StyleKey[float32], fallback: float32
): float32 =
  let value = appearance.patchValue(role, key.keyName, styleLength(fallback))
  if value.kind == svLength: value.length else: fallback

proc insetsPatch*(
    appearance: Appearance,
    role: StyleRole,
    key: StyleKey[EdgeInsets],
    fallback: EdgeInsets,
): EdgeInsets =
  let value = appearance.patchValue(role, key.keyName, styleInsets(fallback))
  if value.kind == svInsets: value.insets else: fallback

proc resolveButtonStyle*(appearance: Appearance, context: StyleContext): ButtonStyle =
  let state = buttonThemeState(context)
  result = appearance.theme.resolveButtonStyle(context)
  result.box.fill = appearance.colorToken(ButtonFillTokens[state], result.box.fill)
  result.box.borderColor =
    appearance.colorToken(ButtonBorderColorTokens[state], result.box.borderColor)
  result.box.borderWidth =
    appearance.lengthToken(ButtonBorderWidthToken, result.box.borderWidth)
  result.box.cornerRadius =
    appearance.lengthToken(ButtonCornerRadiusToken, result.box.cornerRadius)
  result.box.focusRingWidth =
    appearance.lengthToken(ButtonFocusRingWidthToken, result.box.focusRingWidth)
  result.box.focusRingInset =
    appearance.lengthToken(ButtonFocusRingInsetToken, result.box.focusRingInset)
  result.box.focusRingColor =
    appearance.colorToken(ButtonFocusRingColorToken, result.box.focusRingColor)
  result.text.color =
    appearance.colorToken(ButtonTextColorTokens[state], result.text.color)
  result.text.insets =
    appearance.insetsToken(ButtonContentInsetsToken, result.text.insets)
  result.box.fill = appearance.colorPatch(context.role, StyleFill, result.box.fill)
  result.box.borderColor =
    appearance.colorPatch(context.role, StyleBorderColor, result.box.borderColor)
  result.box.borderWidth =
    appearance.lengthPatch(context.role, StyleBorderWidth, result.box.borderWidth)
  result.box.cornerRadius =
    appearance.lengthPatch(context.role, StyleCornerRadius, result.box.cornerRadius)
  result.box.focusRingWidth =
    appearance.lengthPatch(context.role, StyleFocusRingWidth, result.box.focusRingWidth)
  result.box.focusRingInset =
    appearance.lengthPatch(context.role, StyleFocusRingInset, result.box.focusRingInset)
  result.box.focusRingColor =
    appearance.colorPatch(context.role, StyleFocusRingColor, result.box.focusRingColor)
  result.text.color =
    appearance.colorPatch(context.role, StyleTextColor, result.text.color)
  result.text.insets =
    appearance.insetsPatch(context.role, StyleTextInsets, result.text.insets)

func choiceIndicatorFillToken(role: StyleRole, state: ThemeControlState): string =
  if role == srRadioButton:
    RadioButtonIndicatorFillTokens[state]
  else:
    CheckBoxIndicatorFillTokens[state]

func choiceIndicatorSelectedFillToken(
    role: StyleRole, state: ThemeControlState
): string =
  if role == srRadioButton:
    RadioButtonIndicatorSelectedFillTokens[state]
  else:
    CheckBoxIndicatorSelectedFillTokens[state]

func choiceIndicatorBorderColorToken(
    role: StyleRole, state: ThemeControlState
): string =
  if role == srRadioButton:
    RadioButtonIndicatorBorderColorTokens[state]
  else:
    CheckBoxIndicatorBorderColorTokens[state]

func choiceMarkColorToken(role: StyleRole, state: ThemeControlState): string =
  if role == srRadioButton:
    RadioButtonMarkColorTokens[state]
  else:
    CheckBoxMarkColorTokens[state]

func choiceTextColorToken(role: StyleRole, state: ThemeControlState): string =
  if role == srRadioButton:
    RadioButtonTextColorTokens[state]
  else:
    CheckBoxTextColorTokens[state]

func choiceIndicatorSizeToken(role: StyleRole): string =
  if role == srRadioButton:
    RadioButtonIndicatorSizeToken
  else:
    CheckBoxIndicatorSizeToken

func choiceIndicatorBorderWidthToken(role: StyleRole): string =
  if role == srRadioButton:
    RadioButtonIndicatorBorderWidthToken
  else:
    CheckBoxIndicatorBorderWidthToken

func choiceIndicatorCornerRadiusToken(role: StyleRole): string =
  if role == srRadioButton:
    RadioButtonIndicatorCornerRadiusToken
  else:
    CheckBoxIndicatorCornerRadiusToken

func choiceIndicatorSpacingToken(role: StyleRole): string =
  if role == srRadioButton:
    RadioButtonIndicatorSpacingToken
  else:
    CheckBoxIndicatorSpacingToken

func choiceContentInsetsToken(role: StyleRole): string =
  if role == srRadioButton:
    RadioButtonContentInsetsToken
  else:
    CheckBoxContentInsetsToken

func choiceFocusRingWidthToken(role: StyleRole): string =
  if role == srRadioButton:
    RadioButtonFocusRingWidthToken
  else:
    CheckBoxFocusRingWidthToken

func choiceFocusRingInsetToken(role: StyleRole): string =
  if role == srRadioButton:
    RadioButtonFocusRingInsetToken
  else:
    CheckBoxFocusRingInsetToken

func choiceFocusRingColorToken(role: StyleRole): string =
  if role == srRadioButton:
    RadioButtonFocusRingColorToken
  else:
    CheckBoxFocusRingColorToken

proc resolveChoiceButtonStyle*(
    appearance: Appearance, context: StyleContext
): ChoiceButtonStyle =
  let state = buttonThemeState(context)
  result = appearance.theme.resolveChoiceButtonStyle(context)
  result.indicator.fill =
    if ssSelected in context.states:
      appearance.colorToken(
        choiceIndicatorSelectedFillToken(context.role, state), result.indicator.fill
      )
    else:
      appearance.colorToken(
        choiceIndicatorFillToken(context.role, state), result.indicator.fill
      )
  result.indicator.borderColor = appearance.colorToken(
    choiceIndicatorBorderColorToken(context.role, state), result.indicator.borderColor
  )
  result.indicator.borderWidth = appearance.lengthToken(
    choiceIndicatorBorderWidthToken(context.role), result.indicator.borderWidth
  )
  result.indicator.cornerRadius = appearance.lengthToken(
    choiceIndicatorCornerRadiusToken(context.role), result.indicator.cornerRadius
  )
  result.indicator.focusRingWidth = appearance.lengthToken(
    choiceFocusRingWidthToken(context.role), result.indicator.focusRingWidth
  )
  result.indicator.focusRingInset = appearance.lengthToken(
    choiceFocusRingInsetToken(context.role), result.indicator.focusRingInset
  )
  result.indicator.focusRingColor = appearance.colorToken(
    choiceFocusRingColorToken(context.role), result.indicator.focusRingColor
  )
  result.markColor =
    appearance.colorToken(choiceMarkColorToken(context.role, state), result.markColor)
  result.text.color =
    appearance.colorToken(choiceTextColorToken(context.role, state), result.text.color)
  result.text.insets =
    appearance.insetsToken(choiceContentInsetsToken(context.role), result.text.insets)
  result.indicatorSize =
    appearance.lengthToken(choiceIndicatorSizeToken(context.role), result.indicatorSize)
  result.indicatorSpacing = appearance.lengthToken(
    choiceIndicatorSpacingToken(context.role), result.indicatorSpacing
  )
  result.indicator.fill =
    appearance.colorPatch(context.role, StyleFill, result.indicator.fill)
  result.indicator.borderColor =
    appearance.colorPatch(context.role, StyleBorderColor, result.indicator.borderColor)
  result.indicator.borderWidth =
    appearance.lengthPatch(context.role, StyleBorderWidth, result.indicator.borderWidth)
  result.indicator.cornerRadius = appearance.lengthPatch(
    context.role, StyleCornerRadius, result.indicator.cornerRadius
  )
  result.indicator.focusRingWidth = appearance.lengthPatch(
    context.role, StyleFocusRingWidth, result.indicator.focusRingWidth
  )
  result.indicator.focusRingInset = appearance.lengthPatch(
    context.role, StyleFocusRingInset, result.indicator.focusRingInset
  )
  result.indicator.focusRingColor = appearance.colorPatch(
    context.role, StyleFocusRingColor, result.indicator.focusRingColor
  )
  result.markColor =
    appearance.colorPatch(context.role, StyleMarkColor, result.markColor)
  result.text.color =
    appearance.colorPatch(context.role, StyleTextColor, result.text.color)
  result.text.insets =
    appearance.insetsPatch(context.role, StyleTextInsets, result.text.insets)
  result.indicatorSize =
    appearance.lengthPatch(context.role, StyleIndicatorSize, result.indicatorSize)
  result.indicatorSpacing =
    appearance.lengthPatch(context.role, StyleIndicatorSpacing, result.indicatorSpacing)

proc resolveTextFieldStyle*(
    appearance: Appearance, context: StyleContext, textColor: Color
): TextFieldStyle =
  result = appearance.theme.resolveTextFieldStyle(context, textColor)
  result.box.fill = appearance.colorToken(TextFieldFillToken, result.box.fill)
  result.box.borderColor =
    appearance.colorToken(TextFieldBorderColorToken, result.box.borderColor)
  result.box.borderWidth =
    appearance.lengthToken(TextFieldBorderWidthToken, result.box.borderWidth)
  result.box.cornerRadius =
    appearance.lengthToken(TextFieldCornerRadiusToken, result.box.cornerRadius)
  result.box.focusRingWidth =
    appearance.lengthToken(TextFieldFocusRingWidthToken, result.box.focusRingWidth)
  result.box.focusRingInset =
    appearance.lengthToken(TextFieldFocusRingInsetToken, result.box.focusRingInset)
  result.box.focusRingColor =
    appearance.colorToken(TextFieldFocusRingColorToken, result.box.focusRingColor)
  result.text.color = appearance.colorToken(TextFieldTextColorToken, result.text.color)
  result.text.insets =
    appearance.insetsToken(TextFieldTextInsetsToken, result.text.insets)
  result.box.fill = appearance.colorPatch(context.role, StyleFill, result.box.fill)
  result.box.borderColor =
    appearance.colorPatch(context.role, StyleBorderColor, result.box.borderColor)
  result.box.borderWidth =
    appearance.lengthPatch(context.role, StyleBorderWidth, result.box.borderWidth)
  result.box.cornerRadius =
    appearance.lengthPatch(context.role, StyleCornerRadius, result.box.cornerRadius)
  result.box.focusRingWidth =
    appearance.lengthPatch(context.role, StyleFocusRingWidth, result.box.focusRingWidth)
  result.box.focusRingInset =
    appearance.lengthPatch(context.role, StyleFocusRingInset, result.box.focusRingInset)
  result.box.focusRingColor =
    appearance.colorPatch(context.role, StyleFocusRingColor, result.box.focusRingColor)
  result.text.color =
    appearance.colorPatch(context.role, StyleTextColor, result.text.color)
  result.text.insets =
    appearance.insetsPatch(context.role, StyleTextInsets, result.text.insets)

proc resolveTextFieldStyle*(
    appearance: Appearance, context: StyleContext
): TextFieldStyle =
  appearance.resolveTextFieldStyle(context, initColor(0.08, 0.09, 0.11))

func buttonFillColor*(theme: Theme, enabled, highlighted: bool): Color =
  theme.resolveButtonStyle(initControlStyleContext(srButton, enabled, highlighted)).box.fill

func buttonTextColor*(theme: Theme, enabled, highlighted: bool): Color =
  theme.resolveButtonStyle(initControlStyleContext(srButton, enabled, highlighted)).text.color

func buttonBorderColor*(theme: Theme, enabled, highlighted: bool): Color =
  theme.resolveButtonStyle(initControlStyleContext(srButton, enabled, highlighted)).box.borderColor

func buttonTextRect*(style: ButtonStyle, bounds: Rect): Rect =
  bounds.inset(style.text.insets)

func buttonTextRect*(theme: Theme, bounds: Rect): Rect =
  theme.resolveButtonStyle(initControlStyleContext(srButton)).buttonTextRect(bounds)

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

func textFieldTextRect*(theme: Theme, bounds: Rect): Rect =
  theme.resolveTextFieldStyle(initControlStyleContext(srTextField)).textFieldTextRect(
    bounds
  )

func initTheme*(): Theme =
  Theme(
    button: ButtonTheme(
      fill: [
        tcsNormal: initColor(0.20, 0.48, 0.86, 1.0),
        tcsHighlighted: initColor(0.12, 0.34, 0.68, 1.0),
        tcsDisabled: initColor(0.58, 0.62, 0.68, 1.0),
      ],
      textColor: [
        tcsNormal: initColor(1.0, 1.0, 1.0, 1.0),
        tcsHighlighted: initColor(1.0, 1.0, 1.0, 1.0),
        tcsDisabled: initColor(0.92, 0.94, 0.96, 1.0),
      ],
      borderColor: [
        tcsNormal: initColor(0.10, 0.25, 0.46, 1.0),
        tcsHighlighted: initColor(0.06, 0.18, 0.36, 1.0),
        tcsDisabled: initColor(0.46, 0.50, 0.56, 1.0),
      ],
      borderWidth: 1.0,
      cornerRadius: 4.0,
      contentInsets: initEdgeInsets(0.0, 8.0),
      focusRingWidth: 3.0,
      focusRingInset: 2.0,
      focusRingColor: initColor(0.24, 0.48, 0.92, 0.58),
    ),
    choiceButton: ChoiceButtonTheme(
      indicatorFill: [
        tcsNormal: initColor(1.0, 1.0, 1.0, 1.0),
        tcsHighlighted: initColor(0.90, 0.94, 1.0, 1.0),
        tcsDisabled: initColor(0.90, 0.92, 0.95, 1.0),
      ],
      indicatorSelectedFill: [
        tcsNormal: initColor(0.20, 0.48, 0.86, 1.0),
        tcsHighlighted: initColor(0.12, 0.34, 0.68, 1.0),
        tcsDisabled: initColor(0.58, 0.62, 0.68, 1.0),
      ],
      indicatorBorderColor: [
        tcsNormal: initColor(0.50, 0.55, 0.62, 1.0),
        tcsHighlighted: initColor(0.24, 0.38, 0.58, 1.0),
        tcsDisabled: initColor(0.68, 0.72, 0.78, 1.0),
      ],
      markColor: [
        tcsNormal: initColor(1.0, 1.0, 1.0, 1.0),
        tcsHighlighted: initColor(1.0, 1.0, 1.0, 1.0),
        tcsDisabled: initColor(0.92, 0.94, 0.96, 1.0),
      ],
      textColor: [
        tcsNormal: initColor(0.08, 0.09, 0.11, 1.0),
        tcsHighlighted: initColor(0.08, 0.09, 0.11, 1.0),
        tcsDisabled: initColor(0.52, 0.56, 0.62, 1.0),
      ],
      indicatorSize: 14.0,
      indicatorBorderWidth: 1.0,
      checkBoxCornerRadius: 3.0,
      radioCornerRadius: 7.0,
      indicatorSpacing: 7.0,
      contentInsets: initEdgeInsets(0.0, 2.0),
      focusRingWidth: 3.0,
      focusRingInset: 2.0,
      focusRingColor: initColor(0.24, 0.48, 0.92, 0.58),
    ),
    textField: TextFieldTheme(
      fill: initColor(1.0, 1.0, 1.0, 1.0),
      borderColor: initColor(0.72, 0.75, 0.80, 1.0),
      borderWidth: 1.0,
      cornerRadius: 3.0,
      textInsets: initEdgeInsets(0.0, 6.0),
      focusRingWidth: 3.0,
      focusRingInset: 2.0,
      focusRingColor: initColor(0.24, 0.48, 0.92, 0.58),
    ),
  )

proc newStyleTokenStore*(theme: Theme): StyleTokenStore =
  result = newStyleTokenStore()
  for state in ThemeControlState:
    result.setDefaultToken(
      ButtonFillTokens[state], styleColor(theme.button.fill[state])
    )
    result.setDefaultToken(
      ButtonTextColorTokens[state], styleColor(theme.button.textColor[state])
    )
    result.setDefaultToken(
      ButtonBorderColorTokens[state], styleColor(theme.button.borderColor[state])
    )
  result.setDefaultToken(ButtonBorderWidthToken, styleLength(theme.button.borderWidth))
  result.setDefaultToken(
    ButtonCornerRadiusToken, styleLength(theme.button.cornerRadius)
  )
  result.setDefaultToken(
    ButtonContentInsetsToken, styleInsets(theme.button.contentInsets)
  )
  result.setDefaultToken(
    ButtonFocusRingWidthToken, styleLength(theme.button.focusRingWidth)
  )
  result.setDefaultToken(
    ButtonFocusRingInsetToken, styleLength(theme.button.focusRingInset)
  )
  result.setDefaultToken(
    ButtonFocusRingColorToken, styleColor(theme.button.focusRingColor)
  )
  for state in ThemeControlState:
    result.setDefaultToken(
      CheckBoxIndicatorFillTokens[state],
      styleColor(theme.choiceButton.indicatorFill[state]),
    )
    result.setDefaultToken(
      CheckBoxIndicatorSelectedFillTokens[state],
      styleColor(theme.choiceButton.indicatorSelectedFill[state]),
    )
    result.setDefaultToken(
      CheckBoxIndicatorBorderColorTokens[state],
      styleColor(theme.choiceButton.indicatorBorderColor[state]),
    )
    result.setDefaultToken(
      CheckBoxMarkColorTokens[state], styleColor(theme.choiceButton.markColor[state])
    )
    result.setDefaultToken(
      CheckBoxTextColorTokens[state], styleColor(theme.choiceButton.textColor[state])
    )
    result.setDefaultToken(
      RadioButtonIndicatorFillTokens[state],
      styleColor(theme.choiceButton.indicatorFill[state]),
    )
    result.setDefaultToken(
      RadioButtonIndicatorSelectedFillTokens[state],
      styleColor(theme.choiceButton.indicatorSelectedFill[state]),
    )
    result.setDefaultToken(
      RadioButtonIndicatorBorderColorTokens[state],
      styleColor(theme.choiceButton.indicatorBorderColor[state]),
    )
    result.setDefaultToken(
      RadioButtonMarkColorTokens[state], styleColor(theme.choiceButton.markColor[state])
    )
    result.setDefaultToken(
      RadioButtonTextColorTokens[state], styleColor(theme.choiceButton.textColor[state])
    )
  result.setDefaultToken(
    CheckBoxIndicatorSizeToken, styleLength(theme.choiceButton.indicatorSize)
  )
  result.setDefaultToken(
    CheckBoxIndicatorBorderWidthToken,
    styleLength(theme.choiceButton.indicatorBorderWidth),
  )
  result.setDefaultToken(
    CheckBoxIndicatorCornerRadiusToken,
    styleLength(theme.choiceButton.checkBoxCornerRadius),
  )
  result.setDefaultToken(
    CheckBoxIndicatorSpacingToken, styleLength(theme.choiceButton.indicatorSpacing)
  )
  result.setDefaultToken(
    CheckBoxContentInsetsToken, styleInsets(theme.choiceButton.contentInsets)
  )
  result.setDefaultToken(
    CheckBoxFocusRingWidthToken, styleLength(theme.choiceButton.focusRingWidth)
  )
  result.setDefaultToken(
    CheckBoxFocusRingInsetToken, styleLength(theme.choiceButton.focusRingInset)
  )
  result.setDefaultToken(
    CheckBoxFocusRingColorToken, styleColor(theme.choiceButton.focusRingColor)
  )
  result.setDefaultToken(
    RadioButtonIndicatorSizeToken, styleLength(theme.choiceButton.indicatorSize)
  )
  result.setDefaultToken(
    RadioButtonIndicatorBorderWidthToken,
    styleLength(theme.choiceButton.indicatorBorderWidth),
  )
  result.setDefaultToken(
    RadioButtonIndicatorCornerRadiusToken,
    styleLength(theme.choiceButton.radioCornerRadius),
  )
  result.setDefaultToken(
    RadioButtonIndicatorSpacingToken, styleLength(theme.choiceButton.indicatorSpacing)
  )
  result.setDefaultToken(
    RadioButtonContentInsetsToken, styleInsets(theme.choiceButton.contentInsets)
  )
  result.setDefaultToken(
    RadioButtonFocusRingWidthToken, styleLength(theme.choiceButton.focusRingWidth)
  )
  result.setDefaultToken(
    RadioButtonFocusRingInsetToken, styleLength(theme.choiceButton.focusRingInset)
  )
  result.setDefaultToken(
    RadioButtonFocusRingColorToken, styleColor(theme.choiceButton.focusRingColor)
  )
  result.setDefaultToken(TextFieldFillToken, styleColor(theme.textField.fill))
  result.setDefaultToken(
    TextFieldBorderColorToken, styleColor(theme.textField.borderColor)
  )
  result.setDefaultToken(
    TextFieldBorderWidthToken, styleLength(theme.textField.borderWidth)
  )
  result.setDefaultToken(
    TextFieldCornerRadiusToken, styleLength(theme.textField.cornerRadius)
  )
  result.setDefaultToken(
    TextFieldTextInsetsToken, styleInsets(theme.textField.textInsets)
  )
  result.setDefaultToken(
    TextFieldFocusRingWidthToken, styleLength(theme.textField.focusRingWidth)
  )
  result.setDefaultToken(
    TextFieldFocusRingInsetToken, styleLength(theme.textField.focusRingInset)
  )
  result.setDefaultToken(
    TextFieldFocusRingColorToken, styleColor(theme.textField.focusRingColor)
  )

proc initAppearance*(theme: Theme): Appearance =
  Appearance(theme: theme, tokens: newStyleTokenStore(theme))

proc initAppearance*(): Appearance =
  initAppearance(initTheme())
