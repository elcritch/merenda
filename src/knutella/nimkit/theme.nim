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

  TextStyle* = object
    color*: Color
    insets*: EdgeInsets

  ButtonStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle

  TextFieldStyle* = object
    box*: ControlBoxStyle
    text*: TextStyle

  ControlBoxStyleOverride* = object
    fill*: StyleValue
    borderColor*: StyleValue
    borderWidth*: StyleValue
    cornerRadius*: StyleValue
    focusRingWidth*: StyleValue
    focusRingInset*: StyleValue

  TextStyleOverride* = object
    color*: StyleValue
    insets*: StyleValue

  ButtonStyleOverride* = object
    box*: ControlBoxStyleOverride
    text*: TextStyleOverride

  TextFieldStyleOverride* = object
    box*: ControlBoxStyleOverride
    text*: TextStyleOverride

  ButtonTheme* = object
    fill*: array[ThemeControlState, Color]
    textColor*: array[ThemeControlState, Color]
    borderColor*: array[ThemeControlState, Color]
    borderWidth*: float32
    cornerRadius*: float32
    contentInsets*: EdgeInsets
    focusRingWidth*: float32
    focusRingInset*: float32

  TextFieldTheme* = object
    fill*: Color
    borderColor*: Color
    borderWidth*: float32
    cornerRadius*: float32
    textInsets*: EdgeInsets
    focusRingWidth*: float32
    focusRingInset*: float32

  Theme* = object
    button*: ButtonTheme
    textField*: TextFieldTheme

  Appearance* = object
    theme*: Theme
    tokens*: StyleTokenStore
    button*: ButtonStyleOverride
    textField*: TextFieldStyleOverride

const
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
  TextFieldFillToken* = "textField.fill"
  TextFieldBorderColorToken* = "textField.border.color"
  TextFieldBorderWidthToken* = "textField.border.width"
  TextFieldCornerRadiusToken* = "textField.corner.radius"
  TextFieldTextInsetsToken* = "textField.text.insets"
  TextFieldTextColorToken* = "textField.text.color"
  TextFieldFocusRingWidthToken* = "textField.focus.ring.width"
  TextFieldFocusRingInsetToken* = "textField.focus.ring.inset"

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

proc newStyleTokenStore*(parent: StyleTokenStore = nil): StyleTokenStore =
  StyleTokenStore(parent: parent, values: initTable[string, StyleValue]())

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
    ),
    text: TextStyle(
      color: theme.button.textColor[state], insets: theme.button.contentInsets
    ),
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

proc colorValue(appearance: Appearance, value: StyleValue, fallback: Color): Color =
  var resolved: StyleValue
  if not appearance.tokens.resolveValue(value, resolved):
    return fallback
  if resolved.kind == svColor: resolved.color else: fallback

proc lengthValue(
    appearance: Appearance, value: StyleValue, fallback: float32
): float32 =
  var resolved: StyleValue
  if not appearance.tokens.resolveValue(value, resolved):
    return fallback
  if resolved.kind == svLength: resolved.length else: fallback

proc insetsValue(
    appearance: Appearance, value: StyleValue, fallback: EdgeInsets
): EdgeInsets =
  var resolved: StyleValue
  if not appearance.tokens.resolveValue(value, resolved):
    return fallback
  if resolved.kind == svInsets: resolved.insets else: fallback

proc applyOverride(
    style: var ControlBoxStyle,
    override: ControlBoxStyleOverride,
    appearance: Appearance,
) =
  style.fill = appearance.colorValue(override.fill, style.fill)
  style.borderColor = appearance.colorValue(override.borderColor, style.borderColor)
  style.borderWidth = appearance.lengthValue(override.borderWidth, style.borderWidth)
  style.cornerRadius = appearance.lengthValue(override.cornerRadius, style.cornerRadius)
  style.focusRingWidth =
    appearance.lengthValue(override.focusRingWidth, style.focusRingWidth)
  style.focusRingInset =
    appearance.lengthValue(override.focusRingInset, style.focusRingInset)

proc applyOverride(
    style: var TextStyle, override: TextStyleOverride, appearance: Appearance
) =
  style.color = appearance.colorValue(override.color, style.color)
  style.insets = appearance.insetsValue(override.insets, style.insets)

proc applyOverride*(
    style: var ButtonStyle, override: ButtonStyleOverride, appearance: Appearance
) =
  style.box.applyOverride(override.box, appearance)
  style.text.applyOverride(override.text, appearance)

proc applyOverride*(
    style: var TextFieldStyle, override: TextFieldStyleOverride, appearance: Appearance
) =
  style.box.applyOverride(override.box, appearance)
  style.text.applyOverride(override.text, appearance)

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
  result.text.color =
    appearance.colorToken(ButtonTextColorTokens[state], result.text.color)
  result.text.insets =
    appearance.insetsToken(ButtonContentInsetsToken, result.text.insets)
  result.applyOverride(appearance.button, appearance)

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
  result.text.color = appearance.colorToken(TextFieldTextColorToken, result.text.color)
  result.text.insets =
    appearance.insetsToken(TextFieldTextInsetsToken, result.text.insets)
  result.applyOverride(appearance.textField, appearance)

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
    ),
    textField: TextFieldTheme(
      fill: initColor(1.0, 1.0, 1.0, 1.0),
      borderColor: initColor(0.72, 0.75, 0.80, 1.0),
      borderWidth: 1.0,
      cornerRadius: 3.0,
      textInsets: initEdgeInsets(0.0, 6.0),
      focusRingWidth: 3.0,
      focusRingInset: 2.0,
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

proc initAppearance*(theme: Theme): Appearance =
  Appearance(theme: theme, tokens: newStyleTokenStore(theme))

proc initAppearance*(): Appearance =
  initAppearance(initTheme())
