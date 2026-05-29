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
    ssFocused
    ssSelected

  StyleContext* = object
    role*: StyleRole
    states*: set[StyleState]

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

func initEdgeInsets*(top, left, bottom, right: float32): EdgeInsets =
  EdgeInsets(top: top, left: left, bottom: bottom, right: right)

func initEdgeInsets*(vertical, horizontal: float32): EdgeInsets =
  initEdgeInsets(vertical, horizontal, vertical, horizontal)

func initEdgeInsets*(all: float32): EdgeInsets =
  initEdgeInsets(all, all, all, all)

func initStyleContext*(role: StyleRole, states: set[StyleState] = {}): StyleContext =
  StyleContext(role: role, states: states)

func initControlStyleContext*(
    role: StyleRole,
    enabled = true,
    highlighted = false,
    focused = false,
    selected = false,
): StyleContext =
  result = initStyleContext(role)
  if not enabled:
    result.states.incl ssDisabled
  if highlighted:
    result.states.incl ssHighlighted
  if focused:
    result.states.incl ssFocused
  if selected:
    result.states.incl ssSelected

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
  elif ssHighlighted in context.states:
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

func resolveButtonStyle*(appearance: Appearance, context: StyleContext): ButtonStyle =
  appearance.theme.resolveButtonStyle(context)

func resolveTextFieldStyle*(
    appearance: Appearance, context: StyleContext, textColor: Color
): TextFieldStyle =
  appearance.theme.resolveTextFieldStyle(context, textColor)

func resolveTextFieldStyle*(
    appearance: Appearance, context: StyleContext
): TextFieldStyle =
  appearance.theme.resolveTextFieldStyle(context)

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

func initAppearance*(theme: Theme): Appearance =
  Appearance(theme: theme)

func initAppearance*(): Appearance =
  initAppearance(initTheme())
